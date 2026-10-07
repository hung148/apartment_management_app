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
