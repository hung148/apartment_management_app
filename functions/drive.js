'use strict';
// B7b Google Drive connection, TECHNICAL_PROBLEMS.md.
// The owner (connectDrive permission) connects one Google account per
// organization with the Google pop-up (code flow, redirect "postmessage").
// The server keeps the refresh token in driveConnections/{orgId}, a
// server-only document (Firestore rules deny every client). Scope drive.file:
// the app only sees files it created. Photos go to
// "CanHo360 / <property> / Sự cố" in the owner's Drive.
// Staging deploys refuse secret bindings, so the client secret is read from
// Secret Manager at run time with the runtime service account.
const {allows}=require('./team_access');

const DRIVE_SCOPE='https://www.googleapis.com/auth/drive.file';
// OAuth web client ids are public (the browser sees them). One per project.
const CLIENT_IDS=Object.freeze({
 'apartment-management-staging':'933030543017-o28nmj2q5ggd4jf3jld5kan23p38m8v4.apps.googleusercontent.com',
});
const SECRET_NAME='drive-oauth-client-secret';
const FOLDER='application/vnd.google-apps.folder';

class DriveError extends Error{constructor(kind,message){super(message||kind);this.kind=kind;}}

// ---- Real Google client (fetch only, no extra packages) ----
function googleDrive({project=process.env.GCLOUD_PROJECT,fetchFn=fetch}={}){
 const clientId=CLIENT_IDS[project]??null;let secret=null;
 const call=async(url,init={},what='drive')=>{
  let r;try{r=await fetchFn(url,{...init,signal:AbortSignal.timeout(30000)});}catch(e){throw new DriveError('unavailable',`${what}: ${e.message}`);}
  return r;
 };
 async function clientSecret(){
  if(secret)return secret;
  const meta=await call('http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token',{headers:{'Metadata-Flavor':'Google'}},'metadata');
  if(!meta.ok)throw new DriveError('not_configured','metadata '+meta.status);
  const {access_token}=await meta.json();
  const r=await call(`https://secretmanager.googleapis.com/v1/projects/${project}/secrets/${SECRET_NAME}/versions/latest:access`,{headers:{Authorization:'Bearer '+access_token}},'secret');
  if(!r.ok)throw new DriveError('not_configured','secret '+r.status);
  secret=Buffer.from((await r.json()).payload.data,'base64').toString('utf8').trim();
  return secret;
 }
 async function token(form){
  const r=await call('https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},
   body:new URLSearchParams({client_id:clientId,client_secret:await clientSecret(),...form})},'token');
  const v=await r.json().catch(()=>({}));
  if(!r.ok){
   // Google's own reason (no secrets in it), kept for the function log.
   const why=`token ${r.status} ${v.error??''}: ${v.error_description??''}`;
   if(v.error==='invalid_grant')throw new DriveError(form.grant_type==='refresh_token'?'revoked':'bad_code',why);
   // Wrong client id/secret, redirect or client type: a setup problem, not a passing one.
   if(['invalid_client','unauthorized_client','redirect_uri_mismatch','invalid_request'].includes(v.error))throw new DriveError('not_configured',why);
   throw new DriveError('unavailable',why);
  }
  return v;
 }
 const auth=a=>({Authorization:'Bearer '+a});
 const check=async(r,what)=>{
  if(r.status===404)throw new DriveError('missing',what);
  if(r.status===401)throw new DriveError('revoked',what);
  if(r.status===403){const v=await r.json().catch(()=>({}));const reason=v.error?.errors?.[0]?.reason;throw new DriveError(reason==='storageQuotaExceeded'?'full':'denied',what+' 403 '+(reason??''));}
  if(!r.ok)throw new DriveError('unavailable',what+' '+r.status);
  return r;
 };
 return {
  clientId,
  async exchange(code){
   if(!clientId)throw new DriveError('not_configured');
   const v=await token({code,grant_type:'authorization_code',redirect_uri:'postmessage'});
   const scopes=String(v.scope??'').split(' ');
   let email=null;try{email=JSON.parse(Buffer.from(String(v.id_token).split('.')[1],'base64url').toString()).email??null;}catch{}
   return {refreshToken:v.refresh_token??null,email,hasScope:scopes.includes(DRIVE_SCOPE)};
  },
  async access(refreshToken){return (await token({refresh_token:refreshToken,grant_type:'refresh_token'})).access_token;},
  async revoke(refreshToken){await call('https://oauth2.googleapis.com/revoke',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({token:refreshToken})},'revoke').catch(()=>{});},
  async folder(access,name,parent,existing){
   if(existing){
    const r=await call(`https://www.googleapis.com/drive/v3/files/${existing}?fields=id,trashed`,{headers:auth(access)});
    if(r.ok&&!(await r.json()).trashed)return existing;
    if(r.status!==404&&!r.ok)await check(r,'folder');
   }
   const r=await call('https://www.googleapis.com/drive/v3/files?fields=id',{method:'POST',headers:{...auth(access),'Content-Type':'application/json'},
    body:JSON.stringify({name,mimeType:FOLDER,...(parent?{parents:[parent]}:{})})});
   return (await (await check(r,'create folder')).json()).id;
  },
  // convertTo (2026-10-05, sheet import): e.g. an .xlsx saved as a Google Sheet.
  async upload(access,{name,mimeType,parent,bytes,convertTo}){
   const boundary='canho360'+Date.now().toString(36);
   const head=Buffer.from(`--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify({name,parents:[parent],...(convertTo?{mimeType:convertTo}:{})})}\r\n--${boundary}\r\nContent-Type: ${mimeType}\r\n\r\n`);
   const body=Buffer.concat([head,bytes,Buffer.from(`\r\n--${boundary}--`)]);
   const r=await call('https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id',{method:'POST',headers:{...auth(access),'Content-Type':`multipart/related; boundary=${boundary}`},body});
   return {id:(await (await check(r,'upload')).json()).id};
  },
  async download(access,id){
   const r=await call(`https://www.googleapis.com/drive/v3/files/${id}?alt=media`,{headers:auth(access)});
   await check(r,'download');
   return {mimeType:r.headers.get('content-type')??'image/jpeg',bytes:Buffer.from(await r.arrayBuffer())};
  },
  async trash(access,id){
   const r=await call(`https://www.googleapis.com/drive/v3/files/${id}`,{method:'PATCH',headers:{...auth(access),'Content-Type':'application/json'},body:JSON.stringify({trashed:true})});
   if(r.status===404)return;await check(r,'trash');
  },
 };
}

// ---- Local emulator stand-in: files live in the emulator's Firestore ----
// Code "local-<email>" connects as that email; nothing leaves the computer.
function fakeDrive(db){
 const files=id=>db.doc(`localFakeDrive/${id}`);let n=0;
 const make=async v=>{const id='fake'+Date.now().toString(36)+(++n);await files(id).set({...v,trashed:false});return id;};
 return {
  clientId:'local-emulator',
  async exchange(code){if(!/^local-/.test(code))throw new DriveError('bad_code');return {refreshToken:'fake-refresh',email:code.slice(6)||'owner@canho.test',hasScope:true};},
  async access(refreshToken){if(refreshToken!=='fake-refresh')throw new DriveError('revoked');return 'fake-access';},
  async revoke(){},
  async folder(access,name,parent,existing){
   if(existing){const s=(await files(existing).get()).data();if(s&&!s.trashed)return existing;}
   return make({name,parent:parent??null,mimeType:FOLDER});
  },
  async upload(access,{name,mimeType,parent,bytes,convertTo}){return {id:await make({name,parent,mimeType:convertTo??mimeType,dataBase64:bytes.toString('base64')})};},
  async download(access,id){const s=(await files(id).get()).data();if(!s||s.trashed)throw new DriveError('missing');return {mimeType:s.mimeType,bytes:Buffer.from(s.dataBase64,'base64')};},
  async trash(access,id){const s=(await files(id).get()).data();if(s)await files(id).update({trashed:true});},
 };
}

// Error keys the app translates.
const DRIVE_ERRORS=Object.freeze({
 not_configured:['failed-precondition','drive_not_configured'],
 bad_code:['invalid-argument','drive_connect_failed'],
 revoked:['failed-precondition','drive_reconnect_needed'],
 missing:['not-found','problem_photo_missing'],
 full:['resource-exhausted','drive_full'],
 denied:['permission-denied','drive_denied'],
 unavailable:['unavailable','drive_unavailable'],
});

const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);

/** Public view of the connection (never the token). */
function driveSummary(c){
 const state=c?.status==='active'?'connected':c?.status==='needsReconnect'?'needsReconnect':'none';
 return {state,email:state==='none'?null:c?.email??null,connectedByName:state==='none'?null:c?.connectedByName??null};
}

/**
 * The Drive connection an organization uses (2026-10-06, Tom): the owner's own,
 * connected once on the home screen for every organization they own
 * (driveAccounts/{uid}). An older connection made inside one organization
 * (driveConnections/{org}) still counts first. get: (ref|query) => snapshot,
 * so a transaction can pass tx.get.
 */
async function driveConnectionFor(db,organizationId,get=r=>r.get()){
 const orgRef=db.doc(`driveConnections/${organizationId}`),own=(await get(orgRef)).data();
 if(own?.status==='active'||own?.status==='needsReconnect')return {ref:orgRef,data:own};
 const owners=(await get(db.collection('memberships').where('organizationId','==',organizationId))).docs.map(v=>v.data())
  .filter(m=>m.organizationId===organizationId&&m.accessVersion===2&&m.status==='active'&&m.role==='owner'&&id(m.ownerId))
  .sort((a,b)=>(a.role==='owner'?0:1)-(b.role==='owner'?0:1)||String(a.ownerId).localeCompare(String(b.ownerId)));
 let waiting=null;
 for(const m of owners){
  const ref=db.doc(`driveAccounts/${m.ownerId}`),c=(await get(ref)).data();
  if(c?.status==='active'&&c.refreshToken)return {ref,data:c};
  if(c?.status==='needsReconnect'&&!waiting)waiting={ref,data:c};
 }
 return waiting??{ref:null,data:null};
}

/**
 * Drive access for one organization, used by other handlers (photos).
 * Marks the connection "needs reconnect" when Google refuses the token.
 */
function driveAccess({db,drive,HttpsError}){
 const fail=(e)=>{
  // Log Google's answer (status and reason, never tokens) so setup problems can be found.
  if(e?.kind!=='missing')console.error('googleDrive',e?.kind??'error',e?.message??String(e));
  const [code,key]=DRIVE_ERRORS[e?.kind]??DRIVE_ERRORS.unavailable;
  // A setup problem also tells the owner's screen why (Google's short reason,
  // e.g. "secret 403" or "token 401 invalid_client"; never tokens or secrets)
  // (2026-10-05: the log was not readable from Tom's console).
  if(e?.kind==='not_configured')throw new HttpsError(code,key,{why:String(e?.message??'').slice(0,200)});
  throw new HttpsError(code,key);
 };
 return {
  fail,
  async open(organizationId){
   const {ref,data:c}=await driveConnectionFor(db,organizationId);
   if(c?.status==='needsReconnect')throw new HttpsError('failed-precondition','drive_reconnect_needed');
   if(c?.status!=='active'||!c.refreshToken)throw new HttpsError('failed-precondition','drive_not_connected');
   let access;
   try{access=await drive.access(c.refreshToken);}
   catch(e){if(e.kind==='revoked')await ref.update({status:'needsReconnect',refreshToken:null,lostAt:new Date().toISOString()}).catch(()=>{});fail(e);}
   const guard=async fn=>{try{return await fn();}catch(e){if(e instanceof HttpsError)throw e;if(e.kind==='revoked')await ref.update({status:'needsReconnect',refreshToken:null}).catch(()=>{});fail(e);}};
   return {
    connection:c,
    // CanHo360 / <property> / <name>, created when missing (also when the
    // owner deleted a folder); remembered on the connection document.
    async subFolder(buildingId,buildingName,name,key){
     return guard(async()=>{
      const saved=c.folders?.[buildingId]??{};
      const root=await drive.folder(access,'CanHo360',null,c.rootFolderId??null);
      const property=await drive.folder(access,String(buildingName||'Tòa nhà').slice(0,100),root,root===c.rootFolderId?saved.property??null:null);
      const sub=await drive.folder(access,name,property,property===saved.property?saved[key]??null:null);
      if(root!==c.rootFolderId||property!==saved.property||sub!==saved[key]){
       const folders={...(c.folders??{}),[buildingId]:{...(property===saved.property?saved:{}),property,[key]:sub}};
       await ref.update({rootFolderId:root,folders});
       c.rootFolderId=root;c.folders=folders;
      }
      return sub;
     });
    },
    // The CanHo360 folder itself (2026-10-05: the sheet made by the import).
    rootFolder(){
     return guard(async()=>{
      const root=await drive.folder(access,'CanHo360',null,c.rootFolderId??null);
      if(root!==c.rootFolderId){await ref.update({rootFolderId:root});c.rootFolderId=root;}
      return root;
     });
    },
    problemsFolder(buildingId,buildingName){return this.subFolder(buildingId,buildingName,'Sự cố','problems');},
    // 2026-10-04: meter photos (electricity / water readings).
    metersFolder(buildingId,buildingName){return this.subFolder(buildingId,buildingName,'Điện nước','meters');},
    upload:file=>guard(()=>drive.upload(access,file)),
    download:fileId=>guard(()=>drive.download(access,fileId)),
    trash:fileId=>guard(()=>drive.trash(access,fileId)),
   };
  },
 };
}

/** Callable googleDrive: status / connect / disconnect. */
function createGoogleDriveHandler({db,Timestamp,HttpsError,drive}){
 const fail=(code,key)=>{throw new HttpsError(code,key);};
 const errors=driveAccess({db,drive,HttpsError});
 return async request=>{
  const d=request.data||{},uid=request.auth?.uid;
  if(!uid)fail('unauthenticated','drive_sign_in_required');
  const keys={status:[],connect:['code'],disconnect:[]}[d.action];
  const account=d.organizationId===undefined;
  if(!keys||Object.keys(d).some(k=>!['action','organizationId',...keys].includes(k))||(!account&&!id(d.organizationId)))fail('invalid-argument','drive_invalid');
  if(d.action==='connect'&&(typeof d.code!=='string'||d.code.length<4||d.code.length>2048))fail('invalid-argument','drive_invalid');
  const now=Timestamp.now();
  // 2026-10-06 (Tom): the owner connects Google Drive once, on the home screen,
  // for every organization they own (driveAccounts/{uid}).
  if(account){
   const policy=await db.runTransaction(tx=>require('./account_policy').accountPolicy(db,tx,uid));
   if(policy.mode!=='owner'||policy.deleting)fail('permission-denied','drive_access_denied');
   const ref=db.doc(`driveAccounts/${uid}`),saved=(await ref.get()).data();
   if(d.action==='status')return {...driveSummary(saved),canConnect:true,clientId:drive.clientId??null,account:true};
   if(d.action==='connect'){
    if(!drive.clientId){
     const why='no client id for project '+String(process.env.GCLOUD_PROJECT??'?');
     console.error('googleDrive','not_configured',why);
     throw new HttpsError('failed-precondition','drive_not_configured',{why});
    }
    let got;try{got=await drive.exchange(d.code);}catch(e){errors.fail(e);}
    if(!got.hasScope){if(got.refreshToken)await drive.revoke(got.refreshToken);fail('failed-precondition','drive_scope_missing');}
    if(!got.refreshToken)fail('failed-precondition','drive_no_offline_access');
    if(saved?.status==='active'&&saved.refreshToken&&saved.refreshToken!==got.refreshToken)await drive.revoke(saved.refreshToken);
    const same=saved?.email&&saved.email===got.email;
    await ref.set({ownerId:uid,status:'active',email:got.email,refreshToken:got.refreshToken,connectedBy:uid,connectedAt:now,
     rootFolderId:same?saved.rootFolderId??null:null,folders:same?saved.folders??{}:{},previousEmail:same?saved.previousEmail??null:saved?.email??null});
    return {...driveSummary({status:'active',email:got.email}),canConnect:true,clientId:drive.clientId,account:true};
   }
   if(saved?.refreshToken)await drive.revoke(saved.refreshToken);
   if(saved)await ref.set({...saved,status:'disconnected',refreshToken:null,disconnectedAt:now});
   return {...driveSummary(null),canConnect:true,clientId:drive.clientId??null,account:true};
  }
  const org=(await db.doc(`organizations/${d.organizationId}`).get()).data(),m=(await db.doc(`memberships/${uid}_${d.organizationId}`).get()).data();
  if(!org||org.accessVersion!==2||org.closedAt)fail('failed-precondition','team_migration_required');
  if(!m||m.accessVersion!==2||m.status!=='active'||m.organizationId!==d.organizationId)fail('permission-denied','drive_access_denied');
  const canConnect=allows(m,'connectDrive',{organizationId:d.organizationId,userId:uid});
  const ref=db.doc(`driveConnections/${d.organizationId}`),saved=(await ref.get()).data();
  // What this organization uses: its own older connection, or the owner's.
  if(d.action==='status'){const used=await driveConnectionFor(db,d.organizationId);const source=!used.data?null:used.ref.path.startsWith('driveAccounts/')?'owner':'organization';return {...driveSummary(used.data),canConnect,clientId:canConnect?drive.clientId??null:null,...(source?{source}:{})};}
  if(!canConnect)fail('permission-denied','drive_access_denied');
  const name=String(m.displayName||request.auth?.token?.email||'').slice(0,120);
  if(d.action==='connect'){
   if(!drive.clientId){
    const why='no client id for project '+String(process.env.GCLOUD_PROJECT??'?');
    console.error('googleDrive','not_configured',why);
    throw new HttpsError('failed-precondition','drive_not_configured',{why});
   }
   let got;try{got=await drive.exchange(d.code);}catch(e){errors.fail(e);}
   if(!got.hasScope){if(got.refreshToken)await drive.revoke(got.refreshToken);fail('failed-precondition','drive_scope_missing');}
   // Google gives a long-lived token only on the first consent. Without one we
   // could not keep working after an hour, so the owner must remove the old
   // access in their Google account and connect again.
   if(!got.refreshToken)fail('failed-precondition','drive_no_offline_access');
   if(saved?.status==='active'&&saved.refreshToken&&saved.refreshToken!==got.refreshToken)await drive.revoke(saved.refreshToken);
   const same=saved?.email&&saved.email===got.email;
   await ref.set({organizationId:d.organizationId,status:'active',email:got.email,refreshToken:got.refreshToken,connectedBy:uid,connectedByName:name,connectedAt:now,
    // Same Google account: keep the folders. Another account cannot see the old ones.
    rootFolderId:same?saved.rootFolderId??null:null,folders:same?saved.folders??{}:{},previousEmail:same?saved.previousEmail??null:saved?.email??null});
   await db.collection('teamActivity').doc().set({organizationId:d.organizationId,actorId:uid,createdAt:now,action:'drive_connect',targetId:d.organizationId,after:{email:got.email}});
   return {...driveSummary({status:'active',email:got.email,connectedByName:name}),canConnect,clientId:drive.clientId};
  }
  // disconnect: the files stay in the owner's Drive.
  if(saved?.refreshToken)await drive.revoke(saved.refreshToken);
  if(saved)await ref.set({...saved,status:'disconnected',refreshToken:null,disconnectedAt:now,disconnectedBy:uid});
  await db.collection('teamActivity').doc().set({organizationId:d.organizationId,actorId:uid,createdAt:now,action:'drive_disconnect',targetId:d.organizationId,after:{email:saved?.email??null}});
  return {...driveSummary(null),canConnect,clientId:drive.clientId??null};
 };
}

module.exports={googleDrive,fakeDrive,driveAccess,driveConnectionFor,driveSummary,createGoogleDriveHandler,DriveError,DRIVE_SCOPE,CLIENT_IDS};
