const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createRoomDetailsHandler}=require('../room_details');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const room=n=>({roomNumber:n,roomType:'',area:null,ratesMinor:{roomPrice:120099,nightlyPrice:null,hourlyPrice:null}});
const command=()=>({action:'createBulk',organizationId:'org',buildingId:'b',operationId:'op',rooms:[room('P001'),room('P002')]});
function fixture(){const db=fakeDb({'organizations/org':{accessVersion:2},'memberships/u_org':{organizationId:'org',ownerId:'u',role:'manager',status:'active',accessVersion:2,buildingScope:'selected',buildingIds:['b']},'buildings/b':{organizationId:'org',currency:'USD'}});const api=createRoomDetailsHandler({db,Timestamp:Ts,HttpsError:CodeError});return {db,run:d=>api({auth:{uid:'u'},data:d})};}
test('bulk rooms inherit currency, commit once and reject changed retry',async()=>{
 const {db,run}=fixture();const d=command();const first=await run(d);assert.equal(first.roomIds.length,2);assert.deepEqual(await run(d),first);
 assert.equal(db.store.get('rooms/'+first.roomIds[0]).roomPrice,1200.99);
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('teamActivity/')).length,2);
 assert(db.store.get('buildings/b').roomInventoryUpdatedAt);
 await assert.rejects(run({...d,rooms:[room('X')]}),e=>e.code==='failed-precondition');
});
test('existing normalized names and invalid batches produce no partial writes',async()=>{
 for(const rows of [[],Array.from({length:51},(_,i)=>room('P'+i)),[room('P001'),room('ｐ００１')],[{...room('P3'),area:-1}]]){
  const {db,run}=fixture();await assert.rejects(run({...command(),rooms:rows}),e=>e.code==='invalid-argument');assert.equal(db.store.size,3);
 }
 const {db,run}=fixture();db.store.set('rooms/old',{organizationId:'org',buildingId:'b',roomNumber:' ｐ００２ '});
 await assert.rejects(run(command()),e=>e.code==='already-exists');assert.equal(db.store.size,4);
});
test('bulk authorization rechecks scope, status, v2, foreign building and price grants',async()=>{
 for(const patch of [{status:'revoked'},{status:'suspended'},{buildingIds:['else']},{roleGrants:{}}]){
  const {db,run}=fixture();Object.assign(db.store.get('memberships/u_org'),patch);await assert.rejects(run(command()),e=>e.code==='permission-denied');assert.equal(db.store.size,3);
 }
 const {db,run}=fixture();db.store.get('memberships/u_org').permissionOverrides={overridePrices:false};
 assert.equal((await run({action:'prepareBulk',organizationId:'org',buildingId:'b'})).record.canSetRoomPrices,false);
 await assert.rejects(run(command()),e=>e.code==='permission-denied');
 await run({...command(),rooms:[{...room('free'),ratesMinor:{roomPrice:null,nightlyPrice:null,hourlyPrice:null}}]});
 db.store.get('buildings/b').organizationId='foreign';await assert.rejects(run({...command(),operationId:'next'}),e=>e.code==='permission-denied');
});
test('legacy currency defaults to VND and maximum batch is supported',async()=>{
 const {db,run}=fixture();delete db.store.get('buildings/b').currency;
 const result=await run({...command(),rooms:Array.from({length:50},(_,i)=>room('N'+i))});
 assert.equal(result.roomIds.length,50);assert.equal(db.store.get('rooms/'+result.roomIds[0]).roomPrice,120099);
});
