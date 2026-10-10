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

// Saved nightly prices per room (2026-10-09, Tom): chips instead of typing. "Lưu giá phòng" adds and removes
// them; anyone who may book can pick one without "Đổi giá"; the room itself (its revision) is not touched.
test('saved nightly prices: added and removed with "Lưu giá phòng", picked without "Đổi giá"',async()=>{
  const s=seed();s['rooms/r1'].nightlyPrice=600000;
  s['memberships/rec_org']={ownerId:'rec',organizationId:'org',accessVersion:2,role:'custom',roleGrants:{readBookings:'managed',createBookings:'managed',manageBookings:'managed'},status:'active',buildingScope:'all',buildingIds:[]};
  s['rooms/other']={organizationId:'org2',buildingId:'b9',roomNumber:'X',nightlyPrice:1};
  const db=fakeDb(s),roomBefore={...db.store.get('rooms/r1')};
  const as=(uid,data)=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'org',buildingId:'b1',...data}});
  const price=(uid,priceMinor,extra={})=>as(uid,{action:'prices',roomId:'r1',priceMinor,...extra});
  assert.deepEqual((await price('owner',700000)).savedNightPricesMinor,[700000]);
  assert.deepEqual((await price('owner',650000)).savedNightPricesMinor,[650000,700000]);
  // The same price twice is kept once.
  assert.deepEqual((await price('owner',650000)).savedNightPricesMinor,[650000,700000]);
  const stored=db.store.get('roomPriceLists/r1');
  assert.deepEqual([stored.organizationId,stored.buildingId,stored.currency,stored.prices,stored.updatedBy],['org','b1','VND',[650000,700000],'owner']);
  assert.deepEqual(db.store.get('rooms/r1'),roomBefore,'the room and its revision stay as they were');
  const rooms=await as('owner',{action:'rooms'});
  assert.equal(rooms.canSavePrices,true);
  assert.deepEqual(rooms.records.find(r=>r.id==='r1').savedNightPricesMinor,[650000,700000]);
  // Without the permission: the list is shown, nothing can be added or removed.
  const recRooms=await as('rec',{action:'rooms'});
  assert.equal(recRooms.canSavePrices,false);
  assert.deepEqual(recRooms.records.find(r=>r.id==='r1').savedNightPricesMinor,[650000,700000]);
  await assert.rejects(price('rec',800000),e=>e.code==='permission-denied');
  await assert.rejects(price('rec',650000,{remove:true}),e=>e.code==='permission-denied');
  // Picking saved prices (or the room's own) needs no "Đổi giá"; any other price does.
  const quote=(uid,nightPricesMinor)=>as(uid,{action:'quote',roomId:'r1',startLocal:'2026-10-10 14:00',endLocal:'2026-10-12 12:00',occurrence:'first',pricingType:'nightly',nightPricesMinor});
  assert.equal((await quote('rec',[650000,650000])).record.totalMinor,1300000);
  assert.equal((await quote('rec',[600000,700000])).record.totalMinor,1300000);
  await assert.rejects(quote('rec',[650000,640000]),e=>e.code==='permission-denied');
  await assert.rejects(quote('rec',[]),e=>e.code==='permission-denied');
  assert.equal((await quote('owner',[640000,640000])).record.totalMinor,1280000);
  // Removed: no longer free to pick.
  assert.deepEqual((await price('owner',650000,{remove:true})).savedNightPricesMinor,[700000]);
  await assert.rejects(quote('rec',[650000,650000]),e=>e.code==='permission-denied');
  // Removing a price that is not there changes nothing.
  assert.deepEqual((await price('owner',123,{remove:true})).savedNightPricesMinor,[700000]);
});

test('saved nightly prices: bad input, another organization\'s room, a full list and an old currency',async()=>{
  const s=seed();s['rooms/r1'].nightlyPrice=600000;
  s['rooms/other']={organizationId:'org2',buildingId:'b1',roomNumber:'X',nightlyPrice:1};
  s['rooms/gone']={organizationId:'org',buildingId:'b1',roomNumber:'G',deletedAt:new Ts(1)};
  const db=fakeDb(s);
  const price=(data)=>call(db,{action:'prices',organizationId:'org',buildingId:'b1',roomId:'r1',...data});
  for(const bad of [0,-5,1.5,'700000',null,1e13])await assert.rejects(price({priceMinor:bad}),e=>e.code==='invalid-argument',String(bad));
  await assert.rejects(price({priceMinor:700000,remove:'yes'}),e=>e.code==='invalid-argument');
  await assert.rejects(price({priceMinor:700000,extra:1}),e=>e.code==='invalid-argument');
  await assert.rejects(price({roomId:'other',priceMinor:700000}),e=>e.code==='not-found');
  await assert.rejects(price({roomId:'gone',priceMinor:700000}),e=>e.code==='not-found');
  await assert.rejects(price({roomId:'../x',priceMinor:700000}),e=>e.code==='invalid-argument');
  for(let i=1;i<=8;i++)await price({priceMinor:i*100000});
  await assert.rejects(price({priceMinor:900000}),e=>e.code==='failed-precondition'&&e.message==='booking_saved_prices_full');
  assert.equal(db.store.get('roomPriceLists/r1').prices.length,8);
  // A list kept in another currency (the room's currency changed since) is not offered or accepted.
  db.store.get('roomPriceLists/r1').currency='USD';
  const rooms=await call(db,{action:'rooms',organizationId:'org',buildingId:'b1'});
  assert.deepEqual(rooms.records.find(r=>r.id==='r1').savedNightPricesMinor,[]);
});
