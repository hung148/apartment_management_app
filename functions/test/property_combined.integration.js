const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {initializeTestEnvironment}=require('@firebase/rules-unit-testing');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {createPropertyDetailsHandler}=require('../property_details');
const {createRoomDetailsHandler}=require('../room_details');
let env,app,db,property,single;
class HttpsError extends Error{constructor(code,message){super(message);this.code=code;}}
before(async()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required');
 env=await initializeTestEnvironment({projectId:'demo-apartment-calendar',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
 app=initializeApp({projectId:'demo-apartment-calendar'});db=getFirestore();
 property=createPropertyDetailsHandler({db,Timestamp,HttpsError});single=createRoomDetailsHandler({db,Timestamp,HttpsError});
});
after(async()=>{await env?.cleanup();if(app)await deleteApp(app);});
beforeEach(async()=>{
 await env.clearFirestore();
 await db.doc('organizations/org').set({accessVersion:2});
 await db.doc('memberships/owner_org').set({organizationId:'org',ownerId:'owner',accessVersion:2,role:'owner',status:'active',buildingScope:'all'});
 await db.doc('buildings/b').set({organizationId:'org',name:'Before',currency:'VND'});
});
const run=data=>property({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'b',...data}});
const room=n=>({roomNumber:n,roomType:'Studio',area:25,ratesMinor:{roomPrice:null,nightlyPrice:300000,hourlyPrice:null}});
const layout={floors:2,roomPrefix:'A',roomType:'Studio',roomArea:25,floorRoomCounts:[1,1]};
test('combined edit is atomic and concurrent exact retries create one room batch',async()=>{
 const {record}=await run({action:'read'});
 const d={action:'update',revision:record.revision,operationId:'edit',name:'After',address:'',layout,rooms:[room('A101'),room('A201')]};
 const result=await Promise.all([run(d),run(d)]);assert.deepEqual(result[0],result[1]);
 assert.equal((await db.collection('rooms').get()).size,2);
 const b=(await db.doc('buildings/b').get()).data();assert.equal(b.name,'After');assert.deepEqual(b.floorRoomCounts,[1,1]);
 await assert.rejects(run({...d,operationId:'stale'}),e=>e.code==='aborted');
 await db.doc('memberships/owner_org').update({status:'revoked'});await assert.rejects(run(d),e=>e.code==='permission-denied');
});
test('combined edit and single-room creation cannot claim the same name',async()=>{
 const {record}=await run({action:'read'});
 const edit={action:'update',revision:record.revision,operationId:'edit',name:'After',address:'',layout,rooms:[room('A101')]};
 const one={action:'create',organizationId:'org',buildingId:'b',roomId:'single',operationId:'single',roomNumber:' a101 ',roomType:'',area:20};
 const result=await Promise.allSettled([run(edit),single({auth:{uid:'owner'},data:one})]);
 assert.equal(result.filter(r=>r.status==='fulfilled').length,1);
 assert.equal((await db.collection('rooms').get()).size,1);
 if(result[0].status==='rejected')assert.equal((await db.doc('buildings/b').get()).data().name,'Before');
});
test('200 rooms commit atomically; create-only collision preserves every existing document',async()=>{
 const {createHash}=require('node:crypto');
 const data={action:'create',buildingId:'large',operationId:'large',name:'Large',address:'',currency:'VND',timeZone:'UTC',rooms:Array.from({length:200},(_,i)=>room('N'+i))};
 const hash=createHash('sha256').update(JSON.stringify(['propertyRoom','org','large','large',199])).digest('hex');
 await db.doc(`rooms/${hash}`).set({organizationId:'foreign',roomNumber:'Keep'});
 await assert.rejects(run(data),e=>e.code==='already-exists');
 assert.equal((await db.doc('buildings/large').get()).exists,false);
 assert.equal((await db.collection('rooms').get()).size,1);
 await db.doc(`rooms/${hash}`).delete();
 await run(data);await run(data);
 assert.equal((await db.collection('rooms').get()).size,200);
});
