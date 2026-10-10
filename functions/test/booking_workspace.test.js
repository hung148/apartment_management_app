// Booking lists show the room number, not the internal room ID (2026-10-01).
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createBookingWorkspaceHandler}=require('../booking_workspace');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const seed=()=>({
  'organizations/org':{name:'Org',accessVersion:2,createdBy:'owner'},
  'memberships/owner_org':{ownerId:'owner',organizationId:'org',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]},
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'P602',rentalMode:'both',hourlyPrice:100000},
  'bookings/k1':{organizationId:'org',buildingId:'b1',roomId:'r1',guestName:'Khach',status:'pending',
    startTime:new Ts(Date.parse('2026-10-10T07:00:00Z')),endTime:new Ts(Date.parse('2026-10-10T10:00:00Z')),currency:'VND',totalPrice:300000,paidAmount:0},
  'bookings/k2':{organizationId:'org',buildingId:'b1',roomId:'gone',guestName:'Old',status:'pending',currency:'VND'},
});
const call=(db,data)=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid:'owner'},data});

test('list and read return the room number next to the room ID',async()=>{
  const db=fakeDb(seed());
  const list=await call(db,{action:'list',organizationId:'org',buildingId:'b1'});
  const byId=Object.fromEntries(list.records.map(r=>[r.id,r]));
  assert.equal(byId.k1.roomNumber,'P602');
  assert.equal(byId.k1.startLocal,'2026-10-10 14:00');
  assert.equal(byId.k2.roomNumber,'');
  const read=await call(db,{action:'read',organizationId:'org',buildingId:'b1',bookingId:'k1'});
  assert.equal(read.record.roomNumber,'P602');assert.equal(read.record.roomId,'r1');
});

// Short stays priced per hour (2026-10-03): hours × price, no switch to a day price.
test('quote: hours × the hourly price; another price needs "Đổi giá"',async()=>{
  const s=seed();Object.assign(s['rooms/r1'],{dailyPrice:500000,dailyPriceThresholdHours:6});
  const q=d=>call(fakeDb(s),{action:'quote',organizationId:'org',buildingId:'b1',roomId:'r1',startLocal:'2026-10-10 14:00',endLocal:'2026-10-10 22:30',occurrence:'first',pricingType:'hourly',...d});
  // 8.5 hours at the room's 100,000 per hour; no day price even past 6 hours.
  const room=await q({hourlyPriceMinor:100000});
  assert.deepEqual([room.record.totalMinor,room.record.pricingType],[850000,'hourly']);
  // Older apps (no hourly price sent) keep the old rule.
  assert.equal((await q({})).record.pricingType,'daily');
  const own=await q({hourlyPriceMinor:80000});
  assert.equal(own.record.totalMinor,680000);
  // Without "Đổi giá" only the room's price is accepted.
  s['memberships/rec_org']={ownerId:'rec',organizationId:'org',accessVersion:2,role:'custom',roleGrants:{readBookings:'managed',createBookings:'managed',manageBookings:'managed'},status:'active',buildingScope:'all',buildingIds:[]};
  const as=(d)=>createBookingWorkspaceHandler({db:fakeDb(s),Timestamp:Ts,HttpsError:CodeError})({auth:{uid:'rec'},data:{action:'quote',organizationId:'org',buildingId:'b1',roomId:'r1',startLocal:'2026-10-10 14:00',endLocal:'2026-10-10 17:00',occurrence:'first',pricingType:'hourly',...d}});
  assert.equal((await as({hourlyPriceMinor:100000})).record.totalMinor,300000);
  await assert.rejects(as({hourlyPriceMinor:90000}),e=>e.code==='permission-denied');
  // Only with per-hour pricing, and a real amount.
  await assert.rejects(q({pricingType:'nightly',hourlyPriceMinor:100000}),e=>e.code==='invalid-argument');
  await assert.rejects(q({hourlyPriceMinor:0}),e=>e.code==='invalid-argument');
});

test('the rooms list carries the hourly price; a read carries the booking\'s own hourly price',async()=>{
  const s=seed();s['bookings/k1'].hourlyPrice=90000;
  const rooms=await call(fakeDb(s),{action:'rooms',organizationId:'org',buildingId:'b1'});
  assert.equal(rooms.records[0].hourlyPriceMinor,100000);
  const read=await call(fakeDb(s),{action:'read',organizationId:'org',buildingId:'b1',bookingId:'k1'});
  assert.equal(read.record.hourlyPrice,90000);
});

// Saved nightly prices (2026-10-09, Tom): one list per building, shared by its rooms, with defaults; "Lưu giá phòng"
// adds and removes; anyone who may book picks one without "Đổi giá"; no room or building revision is touched.
const D=[300000,400000,500000,700000,1000000];
test('saved nightly prices: one list per building, defaults, picked without "Đổi giá"',async()=>{
  const s=seed();s['rooms/r1'].nightlyPrice=600000;
  s['rooms/r2']={organizationId:'org',buildingId:'b1',roomNumber:'P603',nightlyPrice:800000};
  s['memberships/rec_org']={ownerId:'rec',organizationId:'org',accessVersion:2,role:'custom',roleGrants:{readBookings:'managed',createBookings:'managed',manageBookings:'managed'},status:'active',buildingScope:'all',buildingIds:[]};
  const db=fakeDb(s),before={r1:{...db.store.get('rooms/r1')},b1:{...db.store.get('buildings/b1')}};
  const as=(uid,data)=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'org',buildingId:'b1',...data}});
  const listOf=async(uid,room)=>(await as(uid,{action:'rooms'})).records.find(r=>r.id===room).savedNightPricesMinor;
  // Nothing saved yet: the defaults, on every room of the building.
  assert.deepEqual(await listOf('owner','r1'),D);
  assert.deepEqual(await listOf('owner','r2'),D);
  assert.equal(db.store.get('buildingPriceLists/b1'),undefined,'reading writes nothing');
  // Saved once (no room needed), shown on every room.
  assert.deepEqual((await as('owner',{action:'prices',priceMinor:650000})).savedNightPricesMinor,[...D.slice(0,3),650000,...D.slice(3)]);
  assert.deepEqual(await listOf('rec','r2'),[300000,400000,500000,650000,700000,1000000]);
  // A removed default stays removed.
  await as('owner',{action:'prices',priceMinor:300000,remove:true});
  assert.deepEqual(await listOf('owner','r1'),[400000,500000,650000,700000,1000000]);
  // Several at once (the nights typed one by one): only the new ones are added, once.
  assert.deepEqual((await as('owner',{action:'prices',pricesMinor:[450000,650000,450000,550000]})).savedNightPricesMinor,
    [400000,450000,500000,550000,650000,700000,1000000]);
  const stored=db.store.get('buildingPriceLists/b1');
  assert.deepEqual([stored.organizationId,stored.buildingId,stored.currency,stored.updatedBy],['org','b1','VND','owner']);
  assert.deepEqual(db.store.get('rooms/r1'),before.r1);assert.deepEqual(db.store.get('buildings/b1'),before.b1);
  // Without "Lưu giá phòng": shown, not changed.
  const rec=await as('rec',{action:'rooms'});assert.equal(rec.canSavePrices,false);
  await assert.rejects(as('rec',{action:'prices',priceMinor:800000}),e=>e.code==='permission-denied');
  await assert.rejects(as('rec',{action:'prices',pricesMinor:[800000]}),e=>e.code==='permission-denied');
  // Picking: saved prices or the room's own, per night too; any other price needs "Đổi giá".
  const quote=(uid,room,nightPricesMinor)=>as(uid,{action:'quote',roomId:room,startLocal:'2026-10-10 14:00',endLocal:'2026-10-12 12:00',occurrence:'first',pricingType:'nightly',nightPricesMinor});
  s['rooms/r1'].nightlyPrice=600000;
  assert.equal((await quote('rec','r1',[450000,1000000])).record.totalMinor,1450000);
  assert.equal((await quote('rec','r1',[600000,650000])).record.totalMinor,1250000,'the room\'s own price');
  assert.equal((await quote('rec','r2',[800000,450000])).record.totalMinor,1250000,'another room, the same list');
  await assert.rejects(quote('rec','r1',[300000,450000]),e=>e.code==='permission-denied','a removed default');
  await assert.rejects(quote('rec','r1',[640000,450000]),e=>e.code==='permission-denied');
  await assert.rejects(quote('rec','r1',[]),e=>e.code==='permission-denied');
  assert.equal((await quote('owner','r1',[640000,640000])).record.totalMinor,1280000);
});

test('saved nightly prices: earlier per-room lists join the building list; other currencies stay apart',async()=>{
  const s=seed();
  s['roomPriceLists/r1']={organizationId:'org',buildingId:'b1',roomId:'r1',currency:'VND',prices:[650000,500000]};
  s['roomPriceLists/x']={organizationId:'other',buildingId:'b1',roomId:'x',currency:'VND',prices:[999000]};
  s['rooms/usd']={organizationId:'org',buildingId:'b1',roomNumber:'U1',currency:'USD',nightlyPrice:40};
  const db=fakeDb(s);
  const call=data=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'b1',...data}});
  const rooms=await call({action:'rooms'});
  assert.deepEqual(rooms.records.find(r=>r.id==='r1').savedNightPricesMinor,[300000,400000,500000,650000,700000,1000000]);
  assert.deepEqual(rooms.records.find(r=>r.id==='usd').savedNightPricesMinor,[],'a USD room does not show VND prices');
  assert.equal(rooms.priceListCurrency,'VND');
  // A building in USD has no defaults.
  db.store.get('buildings/b1').currency='USD';
  const usd=await call({action:'rooms'});
  assert.deepEqual(usd.records.find(r=>r.id==='usd').savedNightPricesMinor,[]);
  assert.deepEqual((await call({action:'prices',priceMinor:4500})).savedNightPricesMinor,[4500]);
  assert.deepEqual(db.store.get('buildingPriceLists/b1').prices,[45]);
});

test('saved nightly prices: bad input and a full list',async()=>{
  const db=fakeDb(seed());
  const price=data=>call(db,{action:'prices',organizationId:'org',buildingId:'b1',...data});
  for(const bad of [{priceMinor:0},{priceMinor:-5},{priceMinor:1.5},{priceMinor:'700000'},{priceMinor:null},{priceMinor:1e13},{priceMinor:700000,remove:'yes'},
    {pricesMinor:[]},{pricesMinor:[1,'2']},{pricesMinor:700000},{pricesMinor:Array.from({length:13},(_,i)=>i+1)},{pricesMinor:[1],priceMinor:2},{pricesMinor:[1],remove:true},
    {priceMinor:700000,roomId:'../x'},{priceMinor:700000,extra:1}])
    await assert.rejects(price(bad),e=>e.code==='invalid-argument',JSON.stringify(bad));
  await assert.rejects(call(db,{action:'prices',organizationId:'org',buildingId:'gone',priceMinor:1}),e=>e.code==='not-found');
  // 5 defaults + 7 = 12; one more is refused, adding several that do not fit adds none.
  await price({pricesMinor:[1,2,3,4,5,6,7]});
  await assert.rejects(price({priceMinor:8}),e=>e.code==='failed-precondition'&&e.message==='booking_saved_prices_full');
  await price({priceMinor:1,remove:true});
  await assert.rejects(price({pricesMinor:[8,9]}),e=>e.message==='booking_saved_prices_full');
  assert.equal(db.store.get('buildingPriceLists/b1').prices.length,11);
  // A price already saved is not counted again.
  assert.equal((await price({pricesMinor:[2,8]})).savedNightPricesMinor.length,12);
});
