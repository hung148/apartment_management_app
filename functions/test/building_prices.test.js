// Building price defaults (PRICE_DEFAULTS.md, Tom 2026-10-26).
const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createPropertyDetailsHandler}=require('../property_details');
const {createRoomRatesHandler}=require('../room_rates');
const {createBulkRoomsHandler}=require('../bulk_rooms');
const {createTenantLeasesHandler}=require('../tenant_leases');
const {meterId}=require('../utility_invoice');

const owner={organizationId:'org',ownerId:'owner',role:'owner',status:'active',accessVersion:2,buildingScope:'all',buildingIds:[]};
const defaults=(o={})=>({roomPriceMinor:5000000,nightlyPriceMinor:400000,waterMonthMinor:100000,waterBasis:'person',...o});
const rates=(roomPrice,nightlyPrice)=>({roomPrice,nightlyPrice,hourlyPrice:null});
function setup(){
 Ts.clock=Date.parse('2026-10-27T03:00:00Z');
 const db=fakeDb({'organizations/org':{accessVersion:2},'memberships/owner_org':owner,
  'memberships/mgr_org':{...owner,ownerId:'mgr',role:'custom',roleGrants:{manageProperty:'all'},roleRevision:1}});
 const as=uid=>({
  building:d=>createPropertyDetailsHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'org',buildingId:'b',...d}}),
  room:d=>createRoomRatesHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'org',buildingId:'b',...d}}),
  bulk:d=>createBulkRoomsHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'org',buildingId:'b',...d}}),
  lease:d=>createTenantLeasesHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'org',buildingId:'b',...d}}),
 });
 return {db,...as('owner'),as};
}
const roomsOf=db=>[...db.store.keys()].filter(k=>k.startsWith('rooms/')).map(k=>({id:k.slice(6),...db.store.get(k)})).sort((a,b)=>a.roomNumber.localeCompare(b.roomNumber));
async function create(t,o={}){
 await t.building({action:'create',operationId:'c1',name:'Tòa A',address:'',timeZone:'Asia/Ho_Chi_Minh',currency:'VND',defaultPrices:defaults(),electricityPriceMinor:3500,
  rooms:[{roomNumber:'101',roomType:'',area:null,ratesMinor:rates(5000000,400000)},{roomNumber:'102',roomType:'',area:null,ratesMinor:rates(6000000,400000)}],...o});
}
const err=(code,key)=>e=>e.code===code&&(!key||e.message===key);

test('a new building keeps its prices; rooms with the same price follow it',async()=>{
 const t=setup();await create(t);
 const b=t.db.store.get('buildings/b');
 assert.deepEqual(b.defaultPrices,defaults());
 const [r101,r102]=roomsOf(t.db);
 assert.deepEqual(r101.priceFollows,{roomPrice:true,nightlyPrice:true});
 assert.deepEqual(r102.priceFollows,{roomPrice:false,nightlyPrice:true},'102 typed its own monthly price');
 const p=(await t.building({action:'readPrices'})).record;
 assert.equal(p.electricity.priceMinor,3500);assert.equal(p.electricity.from,'2026-10-27');
 assert.deepEqual(p.rooms.map(r=>[r.roomNumber,r.follows.roomPrice,r.roomPriceMinor]),[['101',true,5000000],['102',false,6000000]]);
 assert.deepEqual(p.hourTemplates,[]);assert.equal(p.canSaveTemplates,true);
});

test('changing a building price: followers change, own prices only when ticked (then they follow)',async()=>{
 const t=setup();await create(t);
 const p=(await t.building({action:'readPrices'})).record,[r101,r102]=p.rooms;
 await t.building({action:'savePrices',operationId:'s1',revision:p.revision,defaults:defaults({roomPriceMinor:5500000}),electricity:null,apply:{roomPrice:[],nightlyPrice:[],electricity:[]}});
 let rooms=roomsOf(t.db);
 assert.equal(rooms[0].roomPrice,5500000);assert.equal(rooms[1].roomPrice,6000000,'own price untouched');
 const q=(await t.building({action:'readPrices'})).record;
 await t.building({action:'savePrices',operationId:'s2',revision:q.revision,defaults:defaults({roomPriceMinor:5800000}),electricity:null,apply:{roomPrice:[r102.id],nightlyPrice:[],electricity:[]}});
 rooms=roomsOf(t.db);
 assert.equal(rooms[0].roomPrice,5800000);assert.equal(rooms[1].roomPrice,5800000);
 assert.equal(rooms[1].priceFollows.roomPrice,true,'ticked → follows from now on');
 assert.ok([...t.db.store.values()].some(v=>v.action==='building_prices_updated'));
 // Ticking needs a building price for that kind.
 await assert.rejects(t.building({action:'savePrices',operationId:'s3',revision:q.revision,defaults:defaults({nightlyPriceMinor:null}),electricity:null,apply:{roomPrice:[],nightlyPrice:[r101.id],electricity:[]}}),err('invalid-argument','price_apply_without_price'));
});

test('electricity: a new building price from a date; ticked rooms drop their own',async()=>{
 const t=setup();await create(t);
 const [r101,r102]=roomsOf(t.db);
 // 102 has its own electricity price, measured up to 2026-11-05.
 t.db.store.set(`utilityMeters/${meterId('org',r102.id,'electricity')}`,{organizationId:'org',buildingId:'b',roomId:r102.id,kind:'electricity',revision:3,lastDate:'2026-11-05',tariff:{currency:'VND',bands:[{throughMilli:null,priceMinor:4000}]},tariffHistory:[{effectiveDate:'2026-10-27',tariff:{currency:'VND',bands:[{throughMilli:null,priceMinor:4000}]}}]});
 const p=(await t.building({action:'readPrices'})).record;
 assert.deepEqual(p.rooms.map(r=>r.electricity.own),[false,true]);
 assert.equal(p.rooms[1].electricity.ownPriceMinor,4000);
 // Before the room's last reading: refused.
 await assert.rejects(t.building({action:'savePrices',operationId:'e1',revision:p.revision,defaults:defaults(),electricity:{priceMinor:3800,effectiveDate:'2026-11-01',propertyRevision:p.electricity.propertyRevision},apply:{roomPrice:[],nightlyPrice:[],electricity:[r102.id]}}),err('failed-precondition'));
 await t.building({action:'savePrices',operationId:'e2',revision:p.revision,defaults:defaults(),electricity:{priceMinor:3800,effectiveDate:'2026-12-01',propertyRevision:p.electricity.propertyRevision},apply:{roomPrice:[],nightlyPrice:[],electricity:[r102.id]}});
 const meter=t.db.store.get(`utilityMeters/${meterId('org',r102.id,'electricity')}`);
 assert.deepEqual(meter.tariffHistory.at(-1),{effectiveDate:'2026-12-01',tariff:null});
 const q=(await t.building({action:'readPrices'})).record;
 assert.deepEqual(q.electricity.upcoming,[{effectiveDate:'2026-12-01',priceMinor:3800}]);
 assert.equal(r101.id.length>0,true);
});

test('without "Đổi giá" prices can be read but not saved',async()=>{
 const t=setup();await create(t);
 const p=(await t.as('mgr').building({action:'readPrices'})).record;
 assert.equal(p.canPrice,false);
 await assert.rejects(t.as('mgr').building({action:'savePrices',operationId:'m1',revision:p.revision,defaults:defaults(),electricity:null,apply:{roomPrice:[],nightlyPrice:[],electricity:[]}}),err('permission-denied'));
 await assert.rejects(t.building({action:'savePrices',operationId:'x',revision:p.revision,defaults:{...defaults(),waterBasis:'x'},electricity:null,apply:{roomPrice:[],nightlyPrice:[],electricity:[]}}),err('invalid-argument'));
 await assert.rejects(t.building({action:'savePrices',operationId:'y',revision:p.revision,defaults:defaults(),electricity:null,apply:{roomPrice:['nope'],nightlyPrice:[],electricity:[]}}),err('not-found'));
});

test('room page: "Dùng giá của cơ sở" follows again; a typed price is the room\'s own',async()=>{
 const t=setup();await create(t);
 const [, r102]=roomsOf(t.db);
 let r=(await t.room({action:'read',roomId:r102.id})).record;
 assert.deepEqual(r.follows,{roomPrice:false,nightlyPrice:true});
 assert.deepEqual(r.buildingPrices,{roomPrice:5000000,nightlyPrice:400000});
 await t.room({action:'update',roomId:r102.id,operationId:'r1',revision:r.revision,ratesMinor:{roomPrice:6000000,nightlyPrice:400000},followBuilding:['roomPrice','nightlyPrice']});
 let room=t.db.store.get(`rooms/${r102.id}`);
 assert.equal(room.roomPrice,5000000);assert.deepEqual(room.priceFollows,{roomPrice:true,nightlyPrice:true});
 r=(await t.room({action:'read',roomId:r102.id})).record;
 await t.room({action:'update',roomId:r102.id,operationId:'r2',revision:r.revision,ratesMinor:{roomPrice:5000000,nightlyPrice:450000},followBuilding:['roomPrice']});
 room=t.db.store.get(`rooms/${r102.id}`);
 assert.equal(room.nightlyPrice,450000);assert.deepEqual(room.priceFollows,{roomPrice:true,nightlyPrice:false});
 // Old app (no followBuilding, still sends the hourly price): an unchanged price keeps following.
 r=(await t.room({action:'read',roomId:r102.id})).record;
 await t.room({action:'update',roomId:r102.id,operationId:'r3',revision:r.revision,ratesMinor:{roomPrice:5000000,nightlyPrice:450000,hourlyPrice:null}});
 assert.deepEqual(t.db.store.get(`rooms/${r102.id}`).priceFollows,{roomPrice:true,nightlyPrice:false});
});

test('rooms added later follow when their price equals the building\'s',async()=>{
 const t=setup();await create(t);
 const prep=(await t.bulk({action:'prepareBulk'})).record;
 assert.equal(prep.defaults.roomPriceMinor,5000000);
 await t.bulk({action:'createBulk',operationId:'b1',rooms:[{roomNumber:'201',roomType:'',area:null,ratesMinor:rates(5000000,null)}]});
 const r201=roomsOf(t.db).find(r=>r.roomNumber==='201');
 // Left empty, the nightly price is the building's too (2026-10-28).
 assert.deepEqual(r201.priceFollows,{roomPrice:true,nightlyPrice:true});
 assert.equal(r201.nightlyPrice,400000);
});

test('the lease form gets the building\'s water per month',async()=>{
 const t=setup();await create(t);
 const [r101]=roomsOf(t.db);
 const p=(await t.lease({action:'prepare',roomId:r101.id})).record;
 assert.deepEqual(p.waterDefault,{amountMinor:100000,basis:'person'});
});

// Tom 2026-10-28: a room with no price takes the building's without being asked.
test('rooms with no price take the building price (create, bulk add, save) and follow it',async()=>{
 const t=setup();
 await create(t,{defaultPrices:defaults({nightlyPriceMinor:null}),rooms:[{roomNumber:'101',roomType:'',area:null,ratesMinor:rates(null,null)}]});
 let [r101]=roomsOf(t.db);
 assert.equal(r101.roomPrice,5000000,'empty row took the building monthly price');
 assert.equal(r101.nightlyPrice,null,'no building nightly price yet');
 assert.deepEqual(r101.priceFollows,{roomPrice:true,nightlyPrice:false});
 await t.bulk({action:'createBulk',operationId:'b1',currency:'VND',rooms:[{roomNumber:'102',roomType:'',area:null,ratesMinor:rates(null,450000)}]});
 const r102=roomsOf(t.db)[1];
 assert.equal(r102.roomPrice,5000000);assert.equal(r102.priceFollows.roomPrice,true);
 assert.equal(r102.nightlyPrice,450000);assert.equal(r102.priceFollows.nightlyPrice,false);
 // Now the building gets a nightly price: 101 (none) takes it unasked; 102 keeps its own.
 const p=(await t.building({action:'readPrices'})).record;
 const res=await t.building({action:'savePrices',operationId:'s1',revision:p.revision,defaults:defaults({nightlyPriceMinor:400000}),electricity:null,apply:{roomPrice:[],nightlyPrice:[],electricity:[]}});
 const [a,b]=roomsOf(t.db);
 assert.equal(a.nightlyPrice,400000);assert.equal(a.priceFollows.nightlyPrice,true);
 assert.equal(b.nightlyPrice,450000);assert.equal(b.priceFollows.nightlyPrice,false);
 assert.equal(res.rooms,1);
});
