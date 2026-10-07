// Surcharges per room or per person (2026-10-04): a per-person line is its price × the
// number of guests, once; a per-room line is a fixed amount, once.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createBookingWorkspaceHandler}=require('../booking_workspace');
const {createCalendarHandler}=require('../calendar');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const seed=()=>({
  'organizations/org':{name:'Org',accessVersion:2,createdBy:'owner'},
  'memberships/owner_org':{ownerId:'owner',organizationId:'org',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]},
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'P602',rentalMode:'both',hourlyPrice:100000,nightlyPrice:500000},
});
const setup=()=>{
  const db=fakeDb(seed());
  const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
  const call=data=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar})({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'b1',...data}});
  return {db,call};
};
const stay={roomId:'r1',startLocal:'2026-12-10 14:00',endLocal:'2026-12-12 12:00',occurrence:'first',pricingType:'nightly'};// 1,000,000
const lines=[{label:'Giường phụ',amountMinor:100000},{label:'Ăn sáng',amountMinor:50000,basis:'person'}];

test('quote: a per-room line once, a per-person line × guests once',async()=>{
  const {call}=setup();
  const q=(await call({action:'quote',...stay,numberOfGuests:3,surcharges:lines})).record;
  assert.equal(q.surchargesMinor,100000+150000);
  assert.equal(q.totalMinor,1250000);
  assert.deepEqual(q.surchargeLines.map(l=>[l.basis,l.unitMinor,l.count,l.totalMinor]),[['room',100000,1,100000],['person',50000,3,150000]]);
  // No guest count: one guest.
  assert.equal((await call({action:'quote',...stay,surcharges:lines})).record.surchargesMinor,150000);
});

test('save keeps the price per person and the count; a later guest count re-prices kept lines',async()=>{
  const {db,call}=setup();
  await call({action:'save',bookingId:'k1',operationId:'op1',roomRevision:'0:0',guestName:'Anh',guestPhone:'',notes:'',depositMinor:0,...stay,numberOfGuests:3,surcharges:lines});
  let b=db.store.get('bookings/k1');
  assert.equal(b.totalPrice,1250000);
  assert.deepEqual(b.surcharges[1],{label:'Ăn sáng',amount:150000,basis:'person',unitAmount:50000,count:3});
  assert.deepEqual(b.surcharges[0],{label:'Giường phụ',amount:100000});
  const read=await call({action:'read',bookingId:'k1'});
  assert.deepEqual(read.record.surcharges[1],{label:'Ăn sáng',amount:150000,basis:'person',unitAmount:50000,count:3});
  // Four guests, surcharges left out (older app): the per-person line follows.
  await call({action:'save',bookingId:'k1',operationId:'op2',revision:read.record.revision,roomRevision:'0:0',guestName:'Anh',guestPhone:'',notes:'',depositMinor:0,...stay,numberOfGuests:4});
  b=db.store.get('bookings/k1');
  assert.deepEqual([b.totalPrice,b.surcharges[1].amount,b.surcharges[1].count],[1300000,200000,4]);
});

test('an unknown basis or extra field is refused',async()=>{
  const {call}=setup();
  await assert.rejects(call({action:'quote',...stay,surcharges:[{label:'X',amountMinor:1,basis:'night'}]}),e=>e.message==='booking_invalid_surcharge');
  await assert.rejects(call({action:'quote',...stay,surcharges:[{label:'X',amountMinor:1,count:2}]}),e=>e.message==='booking_invalid_surcharge');
});
