// Meter photos with readings (2026-10-04): stored in the owner's Google Drive
// (CanHo360 / <property> / Điện nước), listed on the reading.
const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createUtilityReadingsHandler}=require('../utility_readings');
const {fakeDrive}=require('../drive');
const JPEG=Buffer.from([0xff,0xd8,0xff,0xe0,1,2,3,4]).toString('base64');
function setup({connected=true}={}){
 Ts.clock=Date.parse('2026-10-02T12:00:00Z');
 const db=fakeDb({'organizations/o':{accessVersion:2},'buildings/b':{organizationId:'o',name:'Nhà A',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},'rooms/r':{organizationId:'o',buildingId:'b',roomNumber:'101'},
  'memberships/owner_o':{ownerId:'owner',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]},
  ...(connected?{'driveConnections/o':{status:'active',refreshToken:'fake-refresh'}}:{})});
 const handler=createUtilityReadingsHandler({db,Timestamp:Ts,HttpsError:CodeError,drive:fakeDrive(db)});let n=0;
 const call=(data,uid='owner')=>handler({auth:{uid},data:{organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity',...data}});
 const record=async()=>(await call({action:'record',operationId:'rec'+(++n),reason:'Chỉ số tháng',revision:0,date:'2026-10-02',readingMilli:1250000})).readingId;
 return {db,call,record};
}

test('a photo goes to Drive under Điện nước and is listed on the reading; it can be downloaded',async()=>{
 const {db,call,record}=setup();const readingId=await record();
 const r=await call({action:'addPhoto',readingId,operationId:'p1',mimeType:'image/jpeg',dataBase64:JPEG});
 assert.equal(r.photo.mimeType,'image/jpeg');
 const view=await call({action:'read'});
 assert.equal(view.records[0].photos.length,1);
 const files=[...db.store].filter(([k])=>k.startsWith('localFakeDrive/')).map(([,v])=>v);
 assert.ok(files.some(f=>f.name==='Điện nước'));
 assert.ok(files.some(f=>f.name==='101 Điện 2026-10-02 (1).jpg'));
 const down=await call({action:'photo',readingId,photoId:r.photo.id});
 assert.equal(down.dataBase64,JPEG);
 // The same upload twice is one photo.
 assert.deepEqual(await call({action:'addPhoto',readingId,operationId:'p1',mimeType:'image/jpeg',dataBase64:JPEG}),r);
 assert.equal((await call({action:'read'})).records[0].photos.length,1);
});

test('not an image, too many, unknown reading, no Drive or no lease rights are refused',async()=>{
 const {call,record,db}=setup();const readingId=await record();
 await assert.rejects(call({action:'addPhoto',readingId,operationId:'x',mimeType:'image/jpeg',dataBase64:Buffer.from('hello').toString('base64')}),e=>e.message==='utility_photo_invalid');
 for(let i=0;i<3;i++)await call({action:'addPhoto',readingId,operationId:'ok'+i,mimeType:'image/jpeg',dataBase64:JPEG});
 await assert.rejects(call({action:'addPhoto',readingId,operationId:'four',mimeType:'image/jpeg',dataBase64:JPEG}),e=>e.message==='utility_photo_limit');
 await assert.rejects(call({action:'addPhoto',readingId:'nope',operationId:'y',mimeType:'image/jpeg',dataBase64:JPEG}),e=>e.message==='utility_reading_not_found');
 db.store.get('memberships/owner_o').role='custom';db.store.get('memberships/owner_o').roleGrants={readBookings:'all'};
 await assert.rejects(call({action:'photo',readingId,photoId:'x'}),e=>e.code==='permission-denied');
 const other=setup({connected:false});const id2=await other.record();
 await assert.rejects(other.call({action:'addPhoto',readingId:id2,operationId:'z',mimeType:'image/jpeg',dataBase64:JPEG}),e=>e.message==='drive_not_connected');
});
