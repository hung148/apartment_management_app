const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createPropertyDetailsHandler}=require('../property_details');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const layout={floors:2,roomPrefix:'A',roomType:'Studio',roomArea:25,floorRoomCounts:[2,1]};
const room=roomNumber=>({roomNumber,roomType:'Studio',area:25,ratesMinor:{roomPrice:null,nightlyPrice:300000,hourlyPrice:null}});
function fixture(){const db=fakeDb({'organizations/org':{accessVersion:2},'memberships/owner_org':{organizationId:'org',ownerId:'owner',role:'owner',status:'active',accessVersion:2,buildingScope:'all'},'buildings/b':{organizationId:'org',name:'Before',currency:'VND'},'rooms/old':{organizationId:'org',buildingId:'b',roomNumber:'A101',area:40}});const api=createPropertyDetailsHandler({db,Timestamp:Ts,HttpsError:CodeError});return {db,run:d=>api({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'b',...d}})};}
test('combined edit saves defaults and new rooms atomically with exact retry',async()=>{
 const {db,run}=fixture(),record=(await run({action:'read'})).record;
 assert.equal(record.canSetRoomPrices,true);
 const d={action:'update',operationId:'edit',revision:record.revision,name:'After',address:'',layout,rooms:[room('A201')]};
 await run(d);await run(d);
 assert.equal(db.store.get('buildings/b').floors,2);
 assert.equal(db.store.get('rooms/old').area,40);
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('rooms/')).length,2);
 await assert.rejects(run({...d,rooms:[room('A202')]}),e=>e.code==='already-exists');
});
test('existing normalized duplicate rejects details, defaults and rooms together',async()=>{
 const {db,run}=fixture(),{record}=await run({action:'read'});
 await assert.rejects(run({action:'update',operationId:'edit',revision:record.revision,name:'After',address:'',layout,rooms:[room(' ａ１０１ ')]}),e=>e.code==='already-exists');
 assert.equal(db.store.get('buildings/b').name,'Before');assert.equal(db.store.get('buildings/b').floors,undefined);
});
test('combined create stores defaults and rooms; malformed layout is rejected',async()=>{
 const {db,run}=fixture();
 const d={action:'create',buildingId:'new',operationId:'new',name:'New',address:'',currency:'VND',timeZone:'UTC',layout,rooms:[room('A101')]};
 await assert.rejects(run({...d,layout:{...layout,floorRoomCounts:[2]}}),e=>e.code==='invalid-argument');
 assert.equal(db.store.has('buildings/new'),false);
 await run(d);assert.equal(db.store.get('buildings/new').roomPrefix,'A');
});
const roles=['owner','administrator','manager','receptionist','accountant','housekeeper'];
test('combined edit enforces roles, assigned scope, price grants, status and org version',async()=>{
 for(const role of roles){
  const {db,run}=fixture(),member=db.store.get('memberships/owner_org');member.role=role;
  const d={action:'update',operationId:'edit',revision:'0:0',name:'After',address:'',layout,rooms:[room('A201')]};
  if(['owner','administrator','manager'].includes(role))await run(d);
  else await assert.rejects(run(d),e=>e.code==='permission-denied');
 }
 for(const status of ['suspended','revoked']){
  const {db,run}=fixture();db.store.get('memberships/owner_org').status=status;
  await assert.rejects(run({action:'read'}),e=>e.code==='permission-denied');
 }
 const {db,run}=fixture(),member=db.store.get('memberships/owner_org');member.role='manager';member.buildingScope='selected';member.buildingIds=['b'];member.permissionOverrides={overridePrices:false};
 const d={action:'update',operationId:'edit',revision:'0:0',name:'After',address:'',layout,rooms:[room('A201')]};
 assert.equal((await run({action:'read'})).record.canSetRoomPrices,false);
 await assert.rejects(run(d),e=>e.code==='permission-denied');
 await run({...d,rooms:[{...room('A201'),ratesMinor:{roomPrice:null,nightlyPrice:null,hourlyPrice:null}}]});
 member.buildingIds=['other'];await assert.rejects(run({...d,rooms:[]}),e=>e.code==='permission-denied');
 member.buildingScope='all';db.store.get('organizations/org').accessVersion=1;
 await assert.rejects(run({action:'read'}),e=>e.code==='permission-denied');
});
test('custom floor defaults survive read and selected currency applies only to new rooms',async()=>{
 const {db,run}=fixture();db.store.get('organizations/org').displayCurrency='USD';
 const custom={...layout,uniformRooms:false,floorDefaults:[{roomType:'Studio',roomArea:25},{roomType:'Family',roomArea:48}]};
 const d={action:'update',operationId:'edit',revision:'0:0',name:'After',address:'',layout:custom,roomCurrency:'USD',rooms:[room('A201')]};
 await run(d);assert.deepEqual((await run({action:'read'})).record.layout,custom);
 assert.equal(db.store.get('buildings/b').currency,'VND');
 const created=[...db.store].find(([k])=>k.startsWith('rooms/')&&k!=='rooms/old')[1];
 assert.equal(created.currency,'USD');assert.equal(created.nightlyPrice,3000);
 db.store.get('organizations/org').displayCurrency='VND';await run(d);
 await assert.rejects(run({...d,operationId:'second',rooms:[room('A202')]}),e=>e.code==='aborted');
});
test('invalid custom defaults, stale revision and foreign property never partially write',async()=>{
 for(const patch of [{layout:{...layout,uniformRooms:'yes'}},{layout:{...layout,floorDefaults:[{}]}},{layout:{...layout,roomArea:-1}},{revision:'1:0'}]){
  const {db,run}=fixture();await assert.rejects(run({action:'update',operationId:'edit',revision:'0:0',name:'After',address:'',layout,rooms:[room('A201')],...patch}),e=>['aborted','invalid-argument'].includes(e.code));assert.equal(db.store.get('buildings/b').name,'Before');assert.equal(db.store.size,4);
 }
 const {db,run}=fixture();db.store.get('buildings/b').organizationId='foreign';
 await assert.rejects(run({action:'update',operationId:'edit',revision:'0:0',name:'After',address:'',rooms:[]}),e=>e.code==='not-found');
});
