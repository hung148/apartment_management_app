const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createPropertyDetailsHandler,validInitialRooms}=require('../property_details');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const room=(name='101')=>({roomNumber:name,roomType:'Studio',area:25.5,ratesMinor:{roomPrice:125099,nightlyPrice:3500,hourlyPrice:null}});
const command=()=>({action:'create',organizationId:'org',buildingId:'new',operationId:'op',name:'Building',address:'Address',timeZone:'UTC',currency:'USD',exploitationCostMinor:999999,rooms:[room(),room('102')]});
function fixture(){const db=fakeDb({'organizations/org':{accessVersion:2},'memberships/owner_org':{organizationId:'org',ownerId:'owner',role:'owner',status:'active',accessVersion:2,buildingScope:'all'}});const api=createPropertyDetailsHandler({db,Timestamp:Ts,HttpsError:CodeError});return {db,run:d=>api({auth:{uid:'owner'},data:d})};}
test('building cost and multiple rooms commit once with exact cents; retry is idempotent',async()=>{
 const {db,run}=fixture(),d=command();await run(d);await run(d);
 const rooms=[...db.store].filter(([k])=>k.startsWith('rooms/')).map(([,v])=>v);
 assert.equal(rooms.length,2);assert.equal(rooms[0].roomPrice,1250.99);assert.equal(rooms[0].nightlyPrice,35);assert.equal(rooms[0].currency,'USD');assert.equal(rooms[0].rentalMode,'both');
 assert.equal(db.store.get('buildings/new').exploitationCostMinor,999999);
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('teamActivity/')).length,3);
 await assert.rejects(run({...d,rooms:[room('changed')]}),e=>e.code==='already-exists');
});
test('all optional data, old clients and legacy missing cost survive updates',async()=>{
 const {db,run}=fixture(),d=command();delete d.rooms;delete d.exploitationCostMinor;await run(d);
 let record=(await run({action:'read',organizationId:'org',buildingId:'new'})).record;
 assert.equal(record.exploitationCostMinor,null);assert.equal(record.currency,'USD');
 const edit={action:'update',organizationId:'org',buildingId:'new',operationId:'edit',revision:record.revision,name:'B',address:'A',exploitationCostMinor:0};await run(edit);
 assert.equal(db.store.get('buildings/new').exploitationCostMinor,0);
 const oldClient={...edit,operationId:'old'};delete oldClient.exploitationCostMinor;await run(oldClient);assert.equal(db.store.get('buildings/new').exploitationCostMinor,0);
 await run({...edit,operationId:'clear',exploitationCostMinor:null});assert.equal(db.store.get('buildings/new').exploitationCostMinor,null);
});
test('invalid rooms and money leave no building, rooms or audit writes',async()=>{
 for(const patch of [{exploitationCostMinor:-1},{exploitationCostMinor:1.2},{exploitationCostMinor:1e12+1},{rooms:[room(),room(' １０１ ')]},{rooms:[room(),{...room('102'),area:0}]},{rooms:[{...room(),ratesMinor:{roomPrice:0,nightlyPrice:null,hourlyPrice:null}}]},{rooms:Array.from({length:51},(_,i)=>room(String(i)))},{rooms:[{...room(),createdBy:'forged'}]}]){
  const {db,run}=fixture();await assert.rejects(run({...command(),...patch}),e=>e.code==='invalid-argument');assert.equal(db.store.size,2);
 }
 assert.ok(validInitialRooms([]));assert.ok(validInitialRooms(Array.from({length:50},(_,i)=>room(String(i)))));
});
test('room price permission cannot be bypassed by building creation; revoked access blocks retries',async()=>{
 const {db,run}=fixture();const member=db.store.get('memberships/owner_org');member.role='manager';member.permissionOverrides={overridePrices:false};
 assert.equal((await run({action:'prepareCreate',organizationId:'org',buildingId:'new'})).record.canSetRoomPrices,false);
 await assert.rejects(run(command()),e=>e.code==='permission-denied');assert.equal(db.store.size,2);
 await run({...command(),rooms:[{...room(),ratesMinor:{roomPrice:null,nightlyPrice:null,hourlyPrice:null}}]});
 member.status='revoked';await assert.rejects(run(command()),e=>e.code==='permission-denied');
});
test('deterministic room collision refuses all writes and preserves foreign data',async()=>{
 const {createHash}=require('node:crypto');const {db,run}=fixture(),d=command();
 const id=createHash('sha256').update(JSON.stringify(['propertyRoom','org','new','op',1])).digest('hex');
 db.store.set(`rooms/${id}`,{organizationId:'foreign',roomNumber:'Keep'});
 await assert.rejects(run(d),e=>e.code==='already-exists');assert.equal(db.store.size,3);assert.equal(db.store.get(`rooms/${id}`).roomNumber,'Keep');
});
test('maximum list is bounded and VND preserves whole amounts',async()=>{
 const {db,run}=fixture();await run({...command(),currency:'VND',rooms:Array.from({length:50},(_,i)=>room(String(i)))});
 const rooms=[...db.store].filter(([k])=>k.startsWith('rooms/'));assert.equal(rooms.length,50);assert.equal(rooms[0][1].roomPrice,125099);
});
