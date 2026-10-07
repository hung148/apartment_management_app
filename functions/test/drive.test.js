const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createGoogleDriveHandler,googleDrive,DriveError,DRIVE_SCOPE}=require('../drive');
const {createTechnicalProblemsHandler}=require('../technical_problems');
const member=(uid,role,extra={})=>({ownerId:uid,organizationId:'o',accessVersion:2,status:'active',role,buildingScope:'all',buildingIds:[],displayName:uid,...extra});
const JPEG=Buffer.concat([Buffer.from([0xff,0xd8,0xff,0xe0]),Buffer.alloc(200,7)]);
const PNG=Buffer.concat([Buffer.from([0x89,0x50,0x4e,0x47,0x0d,0x0a]),Buffer.alloc(50,1)]);

// In-memory Drive with a switch to make Google refuse the token.
function memoryDrive(){
 const files=new Map();let n=0;
 const drive={files,revoked:false,uploads:0,revokedTokens:[],clientId:'cid',
  next:{refreshToken:'r1',email:'owner@gmail.com',hasScope:true},
  async exchange(code){if(code==='badcode')throw new DriveError('bad_code');return {...drive.next};},
  async access(t){if(drive.revoked||t!=='r1')throw new DriveError('revoked');return 'a';},
  async revoke(t){drive.revokedTokens.push(t);},
  async folder(a,name,parent,existing){if(existing&&files.has(existing)&&!files.get(existing).trashed)return existing;const id='f'+(++n);files.set(id,{name,parent,folder:true});return id;},
  async upload(a,{name,mimeType,parent,bytes}){drive.uploads++;const id='p'+(++n);files.set(id,{name,mimeType,parent,bytes});return {id};},
  async download(a,id){const f=files.get(id);if(!f||f.trashed)throw new DriveError('missing');return {mimeType:f.mimeType,bytes:f.bytes};},
  async trash(a,id){const f=files.get(id);if(f)f.trashed=true;},
 };
 return drive;
}

function setup(){
 Ts.clock=Date.parse('2026-11-20T05:00:00Z');
 const db=fakeDb({
  'organizations/o':{accessVersion:2},
  'buildings/b':{organizationId:'o',name:'Toa A',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'o',buildingId:'b',roomNumber:'101'},
  'memberships/owner_o':member('owner','owner'),
  'memberships/maid_o':member('maid','housekeeper'),
  'memberships/front_o':member('front','receptionist'),
  'memberships/inv_o':member('inv','investor'),
 });
 const drive=memoryDrive();
 const deps={db,Timestamp:Ts,HttpsError:CodeError,drive};
 const g=createGoogleDriveHandler(deps),p=createTechnicalProblemsHandler(deps);
 const gd=(data,uid='owner')=>g({auth:{uid},data:{organizationId:'o',...data}});
 const tp=(data,uid='owner')=>p({auth:{uid},data:{organizationId:'o',buildingId:'b',...data}});
 return {db,drive,gd,tp};
}
const report=async tp=>(await tp({action:'report',operationId:'rep',roomId:'r1',title:'Đèn hỏng',description:'',blocksRoom:false},'maid')).problemId;
const add=(problemId,op,o={})=>({action:'addPhoto',operationId:op,problemId,mimeType:'image/jpeg',dataBase64:JPEG.toString('base64'),...o});

test('owner connects and disconnects; staff only see the state',async()=>{
 const {db,drive,gd}=setup();
 assert.deepEqual(await gd({action:'status'},'maid'),{state:'none',email:null,connectedByName:null,canConnect:false,clientId:null});
 await assert.rejects(gd({action:'connect',code:'abcd'},'maid'),e=>e.message==='drive_access_denied');
 const s=await gd({action:'connect',code:'abcd'});
 assert.equal(s.state,'connected');assert.equal(s.email,'owner@gmail.com');assert.equal(s.clientId,'cid');
 const saved=db.store.get('driveConnections/o');assert.equal(saved.refreshToken,'r1');assert.equal(saved.connectedBy,'owner');
 // The token never leaves the server.
 assert.equal(JSON.stringify(await gd({action:'status'},'front')).includes('r1'),false);
 await gd({action:'disconnect'});
 assert.deepEqual(drive.revokedTokens,['r1']);
 assert.equal(db.store.get('driveConnections/o').status,'disconnected');assert.equal(db.store.get('driveConnections/o').refreshToken,null);
 assert.equal((await gd({action:'status'})).state,'none');
});

test('connect refuses a missing Drive tick, a missing long-lived token and a bad code',async()=>{
 const {db,drive,gd}=setup();
 drive.next={refreshToken:'x',email:'a@b.c',hasScope:false};
 await assert.rejects(gd({action:'connect',code:'abcd'}),e=>e.message==='drive_scope_missing');
 assert.deepEqual(drive.revokedTokens,['x']);
 drive.next={refreshToken:null,email:'a@b.c',hasScope:true};
 await assert.rejects(gd({action:'connect',code:'abcd'}),e=>e.message==='drive_no_offline_access');
 await assert.rejects(gd({action:'connect',code:'badcode'}),e=>e.message==='drive_connect_failed');
 await assert.rejects(gd({action:'connect',code:'abcd',extra:1}),e=>e.message==='drive_invalid');
 assert.equal(db.store.has('driveConnections/o'),false);
});

test('photos: staff add while open, retry is not uploaded twice, everyone who reads can view',async()=>{
 const {db,drive,gd,tp}=setup();
 const id=await report(tp);
 await assert.rejects(tp(add(id,'a0'),'maid'),e=>e.message==='drive_not_connected');
 await gd({action:'connect',code:'abcd'});
 const first=await tp(add(id,'a1'),'maid');
 assert.equal(first.photo.addedByName,'maid');assert.equal(first.photo.addedLocalDate,'2026-11-20');
 assert.deepEqual(await tp(add(id,'a1'),'maid'),first);assert.equal(drive.uploads,1);
 const file=drive.files.get(first.photo.id);assert.equal(file.name,'101 2026-11-20 Đèn hỏng (1).jpg');
 const folder=drive.files.get(file.parent),property=drive.files.get(folder.parent),root=drive.files.get(property.parent);
 assert.deepEqual([root.name,property.name,folder.name],['CanHo360','Toa A','Sự cố']);
 // Second photo reuses the folders.
 const second=await tp(add(id,'a2',{mimeType:'image/png',dataBase64:PNG.toString('base64')}),'front');
 assert.equal(drive.files.get(second.photo.id).parent,file.parent);
 const list=await tp({action:'list'},'inv');
 assert.equal(list.records[0].photos.length,2);assert.equal(list.drive.state,'connected');
 const viewed=await tp({action:'photo',problemId:id,photoId:first.photo.id},'inv');
 assert.equal(Buffer.from(viewed.dataBase64,'base64').equals(JPEG),true);
 // History and activity record each photo.
 assert.equal([...db.store.keys()].filter(k=>k.includes('/problemHistory/')).length,3);
});

test('photo checks: type, size, limit, closed problem, who may remove',async()=>{
 const {db,drive,gd,tp}=setup();
 await gd({action:'connect',code:'abcd'});
 const id=await report(tp);
 await assert.rejects(tp(add(id,'x1',{dataBase64:PNG.toString('base64')})),e=>e.message==='problem_photo_invalid');
 await assert.rejects(tp(add(id,'x2',{mimeType:'image/gif'})),e=>e.message==='problem_photo_invalid');
 await assert.rejects(tp(add(id,'x3',{dataBase64:'not base64!'})),e=>e.message==='problem_photo_invalid');
 const big=Buffer.concat([JPEG,Buffer.alloc(2*1024*1024)]).toString('base64');
 await assert.rejects(tp(add(id,'x4',{dataBase64:big})),e=>e.message==='problem_photo_invalid');
 await assert.rejects(tp(add(id,'x5'),'inv'),e=>e.message==='problem_access_denied');
 const ids=[];for(let i=0;i<6;i++)ids.push((await tp(add(id,'ok'+i),'maid')).photo.id);
 await assert.rejects(tp(add(id,'ok6')),e=>e.message==='problem_photo_limit');
 assert.equal(drive.uploads,6);
 // Front desk did not add the photo; the housekeeper who did may remove it.
 await assert.rejects(tp({action:'removePhoto',operationId:'d0',problemId:id,photoId:ids[0]},'front'),e=>e.message==='problem_access_denied');
 const removed=await tp({action:'removePhoto',operationId:'d1',problemId:id,photoId:ids[0]},'maid');
 assert.equal(removed.trashed,true);assert.equal(drive.files.get(ids[0]).trashed,true);
 assert.equal(db.store.get(`technicalProblems/${id}`).photos.length,5);
 // After the fix only a manager may still add or remove.
 await tp({action:'fix',operationId:'fx',problemId:id,revision:'0:0',fixedByName:'Thợ',fixedDate:'2026-11-20',costMinor:null,recordExpense:false,paymentMethod:null,accountId:null,note:''});
 await assert.rejects(tp({action:'removePhoto',operationId:'d2',problemId:id,photoId:ids[1]},'maid'),e=>e.message==='problem_access_denied');
 await tp({action:'removePhoto',operationId:'d3',problemId:id,photoId:ids[1]});
 await tp(add(id,'late'));
 await assert.rejects(tp(add(id,'late2'),'maid'),e=>e.message==='problem_not_open'||e.message==='problem_photo_limit');
});

test('Google refusing the token marks "connect again"; a photo deleted in Drive is reported',async()=>{
 const {db,drive,gd,tp}=setup();
 await gd({action:'connect',code:'abcd'});
 const id=await report(tp);
 const {photo}=await tp(add(id,'a1'),'maid');
 drive.files.get(photo.id).trashed=true;
 await assert.rejects(tp({action:'photo',problemId:id,photoId:photo.id}),e=>e.message==='problem_photo_missing');
 drive.revoked=true;
 await assert.rejects(tp(add(id,'a2'),'maid'),e=>e.message==='drive_reconnect_needed');
 assert.equal(db.store.get('driveConnections/o').status,'needsReconnect');
 assert.equal((await gd({action:'status'},'maid')).state,'needsReconnect');
 assert.equal((await tp({action:'list'})).drive.state,'needsReconnect');
 // Reconnecting with the same account keeps the folders.
 drive.revoked=false;const folders=db.store.get('driveConnections/o').folders;
 await gd({action:'connect',code:'abcd'});
 assert.deepEqual(db.store.get('driveConnections/o').folders,folders);
 // Removing a photo while Drive refuses still takes it off the problem.
 drive.revoked=true;
 assert.equal((await tp({action:'removePhoto',operationId:'d1',problemId:id,photoId:photo.id})).trashed,false);
 assert.equal(db.store.get(`technicalProblems/${id}`).photos.length,0);
});

test('Google client: code exchange, scope check, token refusal, secret read once',async()=>{
 const calls=[];
 const reply=(status,body,headers={})=>({ok:status<300,status,json:async()=>body,headers:{get:k=>headers[k]??null},arrayBuffer:async()=>new ArrayBuffer(0)});
 const idToken='x.'+Buffer.from(JSON.stringify({email:'owner@gmail.com'})).toString('base64url')+'.y';
 let refused=false;
 const fetchFn=async(url,init={})=>{
  calls.push(url);
  if(url.includes('metadata.google.internal'))return reply(200,{access_token:'meta'});
  if(url.includes('secretmanager'))return reply(200,{payload:{data:Buffer.from('s3cret\n').toString('base64')}});
  if(url.includes('oauth2.googleapis.com/token')){
   const form=new URLSearchParams(init.body);
   assert.equal(form.get('client_secret'),'s3cret');assert.match(form.get('client_id'),/apps\.googleusercontent\.com$/);
   if(form.get('grant_type')==='authorization_code'){assert.equal(form.get('redirect_uri'),'postmessage');return reply(200,{refresh_token:'rt',scope:`openid ${DRIVE_SCOPE} email`,id_token:idToken});}
   return refused?reply(400,{error:'invalid_grant'}):reply(200,{access_token:'at'});
  }
  return reply(404,{});
 };
 const g=googleDrive({project:'apartment-management-staging',fetchFn});
 assert.match(g.clientId,/apps\.googleusercontent\.com$/);
 assert.deepEqual(await g.exchange('code'),{refreshToken:'rt',email:'owner@gmail.com',hasScope:true});
 assert.equal(await g.access('rt'),'at');
 refused=true;await assert.rejects(g.access('rt'),e=>e.kind==='revoked');
 assert.equal(calls.filter(u=>u.includes('secretmanager')).length,1);
 await assert.rejects(g.download('at','gone'),e=>e.kind==='missing');
 const none=googleDrive({project:'apartment-management-prod-unknown',fetchFn});
 assert.equal(none.clientId,null);await assert.rejects(none.exchange('code'),e=>e.kind==='not_configured');
});

// 2026-10-06 (Tom): connect once on the home screen; every organization the
// owner owns uses it (photos, the import's Google Sheet).
test('the owner\'s own Drive: connected once, used by each organization they own',async()=>{
 const {db,drive,gd,tp}=setup();
 const g=createGoogleDriveHandler({db,Timestamp:Ts,HttpsError:CodeError,drive});
 const mine=(data,uid='owner')=>g({auth:{uid},data});
 assert.deepEqual(await mine({action:'status'}),{state:'none',email:null,connectedByName:null,canConnect:true,clientId:'cid',account:true});
 const s=await mine({action:'connect',code:'abcd'});
 assert.deepEqual([s.state,s.email,s.account],['connected','owner@gmail.com',true]);
 assert.equal(db.store.get('driveAccounts/owner').refreshToken,'r1');
 assert.equal(db.store.has('driveConnections/o'),false);
 // The organization now shows the owner's Drive, to staff too.
 const org=await gd({action:'status'},'maid');
 assert.deepEqual([org.state,org.email,org.source],['connected','owner@gmail.com','owner']);
 // Photos go to the owner's Drive; folders are remembered on the owner's connection.
 const id=await report(tp);
 await tp(add(id,'p1'),'maid');
 assert.equal(drive.uploads,1);
 assert.ok(db.store.get('driveAccounts/owner').rootFolderId);
 // Another account's Drive is not used for this organization.
 await assert.rejects(mine({action:'connect',code:'abcd'},'maid'),e=>e.message==='drive_access_denied');
 await mine({action:'disconnect'});
 assert.equal(db.store.get('driveAccounts/owner').status,'disconnected');
 assert.equal((await gd({action:'status'},'maid')).state,'none');
 await assert.rejects(tp(add(id,'p2'),'maid'),e=>e.message==='drive_not_connected');
 // Nobody else can read or change the owner's connection.
 await assert.rejects(mine({action:'status'},'front'),e=>e.message==='drive_access_denied');
});
