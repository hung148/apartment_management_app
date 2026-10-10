// Fix 5 (2026-10-09, Tom): the room price of a short stay can be changed when it is negotiated up or down. It needs
// "Đổi giá" and a reason; the booking keeps the agreed price, the calculated one, the reason and who changed it.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createBookingWorkspaceHandler}=require('../booking_workspace');
const {createCalendarHandler}=require('../calendar');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const seed=()=>({
  'organizations/org':{name:'Org',accessVersion:2,createdBy:'owner'},
  'memberships/owner_org':{ownerId:'owner',organizationId:'org',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[],displayName:'Chị Hà'},
  'memberships/rec_org':{ownerId:'rec',organizationId:'org',accessVersion:2,role:'custom',roleGrants:{readBookings:'managed',createBookings:'managed',manageBookings:'managed'},status:'active',buildingScope:'all',buildingIds:[],email:'rec@example.com'},
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'P602',rentalMode:'both',hourlyPrice:100000,nightlyPrice:500000},
});
const setup=()=>{
  const db=fakeDb(seed());
  const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
  const as=uid=>data=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar})({auth:{uid},data:{organizationId:'org',buildingId:'b1',...data}});
  return {db,calendar,owner:as('owner'),rec:as('rec')};
};
const stay={roomId:'r1',startLocal:'2026-12-10 14:00',endLocal:'2026-12-12 12:00',occurrence:'first',pricingType:'nightly'};// 2 × 500,000
const extra=[{label:'Giường phụ',amountMinor:100000}];
const save=(call,data)=>call({action:'save',bookingId:'k1',roomRevision:'0:0',guestName:'Anh',guestPhone:'',notes:'',depositMinor:0,...stay,surcharges:extra,...data});

test('a changed price needs "Đổi giá" and a reason, and keeps the calculated price, the reason and who',async()=>{
  const {db,owner,rec}=setup();
  const q=(await owner({action:'quote',...stay,surcharges:extra,overrideMinor:900000,overrideReason:'  Khách quen  '})).record;
  assert.deepEqual([q.calculatedMinor,q.agreedMinor,q.agreedReason,q.baseMinor,q.totalMinor],[1000000,900000,'Khách quen',900000,1000000]);
  // Without a change the quote says nothing about an agreed price.
  const plainQuote=(await owner({action:'quote',...stay})).record;
  assert.equal(plainQuote.agreedMinor,undefined);assert.equal(plainQuote.totalMinor,1000000);
  // No "Đổi giá", no reason, a blank or too long reason, or a bad amount: refused, nothing saved.
  for(const bad of [{overrideMinor:900000,overrideReason:'x'}])await assert.rejects(save(rec,{operationId:'r0',...bad}),e=>e.code==='permission-denied');
  for(const bad of [{overrideMinor:900000},{overrideMinor:900000,overrideReason:'   '},{overrideMinor:900000,overrideReason:'x'.repeat(1001)},{overrideMinor:0,overrideReason:'x'},{overrideMinor:-1,overrideReason:'x'},{overrideMinor:1.5,overrideReason:'x'},{overrideMinor:'900000',overrideReason:'x'}])
    await assert.rejects(save(owner,{operationId:'o0',...bad}),e=>e.code==='permission-denied',JSON.stringify(bad));
  assert.equal(db.store.get('bookings/k1'),undefined);
  await save(owner,{operationId:'o1',overrideMinor:900000,overrideReason:'  Khách quen  '});
  const b=db.store.get('bookings/k1');
  // The agreed room price plus the surcharge.
  assert.equal(b.totalPrice,1000000);
  const {at,...o}=b.priceOverride;
  assert.deepEqual(o,{total:900000,calculatedTotal:1000000,reason:'Khách quen',byId:'owner',byName:'Chị Hà'});
  assert.equal(typeof at.toMillis,'function');
  // The operation record keeps who and why as well.
  const op=[...db.store.entries()].find(([k])=>k.startsWith('bookingOperations/'))[1];
  assert.deepEqual([op.actorId,op.priceOverrideReason],['owner','  Khách quen  ']);
  const read=(await owner({action:'read',bookingId:'k1'})).record;
  assert.deepEqual([read.priceOverride.total,read.priceOverride.calculatedTotal,read.priceOverride.reason,read.priceOverride.byName],[900000,1000000,'Khách quen','Chị Hà']);
  assert.equal(typeof read.priceOverride.at,'string');
});

test('an edit that leaves the price out keeps the agreed price; only "Đổi giá" changes or removes it',async()=>{
  const {db,owner,rec}=setup();
  await save(owner,{operationId:'o1',overrideMinor:900000,overrideReason:'Khách quen'});
  const first=db.store.get('bookings/k1').priceOverride;
  const revision=async()=>(await owner({action:'read',bookingId:'k1'})).record.revision;
  // The receptionist changes the guest's name and a night more: the agreed price stays, by the owner.
  const longer={endLocal:'2026-12-13 12:00'};
  const q=(await rec({action:'quote',...stay,...longer,bookingId:'k1',surcharges:extra})).record;
  assert.deepEqual([q.calculatedMinor,q.agreedMinor,q.agreedReason,q.totalMinor],[1500000,900000,'Khách quen',1000000]);
  await save(rec,{operationId:'r1',revision:await revision(),guestName:'Anh Tuấn',...longer});
  let b=db.store.get('bookings/k1');
  assert.equal(b.guestName,'Anh Tuấn');assert.equal(b.totalPrice,1000000);assert.deepEqual(b.priceOverride,first);
  // The receptionist may not change it, nor go back to the calculated price.
  await assert.rejects(save(rec,{operationId:'r2',revision:await revision(),...longer,overrideMinor:800000,overrideReason:'x'}),e=>e.code==='permission-denied');
  await assert.rejects(save(rec,{operationId:'r3',revision:await revision(),...longer,overrideMinor:null}),e=>e.code==='permission-denied');
  // The owner changes it again: a new reason, a new calculated price.
  await save(owner,{operationId:'o2',revision:await revision(),...longer,overrideMinor:1200000,overrideReason:'Thêm một đêm'});
  b=db.store.get('bookings/k1');
  assert.equal(b.totalPrice,1300000);
  assert.deepEqual([b.priceOverride.total,b.priceOverride.calculatedTotal,b.priceOverride.reason],[1200000,1500000,'Thêm một đêm']);
  // And back to the calculated price.
  await save(owner,{operationId:'o3',revision:await revision(),...longer,overrideMinor:null});
  b=db.store.get('bookings/k1');
  assert.equal(b.totalPrice,1600000);assert.equal(b.priceOverride,null);
  assert.equal((await owner({action:'read',bookingId:'k1'})).record.priceOverride,null);
  // null on a booking without an agreed price changes nothing, for anyone.
  await save(rec,{operationId:'r4',revision:await revision(),...longer,overrideMinor:null});
  assert.equal(db.store.get('bookings/k1').totalPrice,1600000);
});

test('an agreed price cannot be written around the bookings workspace',async()=>{
  const {calendar}=setup();
  const booking={organizationId:'org',roomId:'r1',guestName:'X',pricingType:'nightly',totalPrice:1,startTime:{__timestamp:Date.parse('2026-12-10T07:00:00Z')},endTime:{__timestamp:Date.parse('2026-12-11T05:00:00Z')},
    priceOverride:{total:1,calculatedTotal:1000000,reason:'x',byId:'owner',byName:'x',at:{__timestamp:1}}};
  await assert.rejects(calendar({action:'create',bookingId:'k9',booking},{auth:{uid:'owner'}}),e=>e.code==='invalid-argument');
});
