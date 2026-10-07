// Deposit taken in the booking form (2026-10-04): part of the total, paid in cash,
// by bank transfer or by card on a given day, recorded as a payment with the booking.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createBookingWorkspaceHandler}=require('../booking_workspace');
const {createCalendarHandler}=require('../calendar');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const member=(uid,role,extra={})=>({ownerId:uid,organizationId:'org',accessVersion:2,role,status:'active',buildingScope:'all',buildingIds:[],...extra});
const seed=()=>({
  'organizations/org':{name:'Org',accessVersion:2,createdBy:'owner'},
  'memberships/owner_org':member('owner','owner'),
  'memberships/desk_org':member('desk','receptionist'),
  // Can make bookings but not take money.
  'memberships/clerk_org':member('clerk','custom',{roleGrants:{readBookings:'managed',createBookings:'managed',manageBookings:'managed'}}),
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'P602',rentalMode:'both',hourlyPrice:100000,nightlyPrice:500000},
});
const setup=()=>{
  const db=fakeDb(seed());
  const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
  const call=(uid,data)=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar})({auth:{uid},data:{organizationId:'org',buildingId:'b1',...data}});
  return {db,calendar,call};
};
// Property-local day, n days from today.
const day=n=>{const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Ho_Chi_Minh',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(Date.now()+n*86400000)).map(x=>[x.type,x.value]));return `${p.year}-${p.month}-${p.day}`;};
// Two nights at 500,000 = 1,000,000.
const save=(extra={})=>({action:'save',bookingId:'k1',operationId:'op1',roomRevision:'0:0',guestName:'Anh',guestPhone:'0901',notes:'',depositMinor:0,
  roomId:'r1',startLocal:'2026-12-10 14:00',endLocal:'2026-12-12 12:00',occurrence:'first',pricingType:'nightly',...extra});
const payments=db=>[...db.store].filter(([k])=>k.startsWith('payments/')).map(([,v])=>v);

test('a deposit is recorded as a payment on its day and counts toward the total',async()=>{
  const {db,call}=setup();
  await call('owner',save({deposit:{amountMinor:300000,method:'bankTransfer',paidOn:day(-1)}}));
  const b=db.store.get('bookings/k1');
  assert.deepEqual([b.totalPrice,b.paidAmount],[1000000,300000]);
  assert.deepEqual([b.depositPayment.amount,b.depositPayment.paymentMethod,b.depositPayment.paidOn],[300000,'bankTransfer',day(-1)]);
  const [p]=payments(db);
  assert.deepEqual([p.type,p.amount,p.paymentMethod,p.descriptionKey,p.bookingId],['hourlyRent',300000,'bankTransfer','booking_deposit_payment','k1']);
  // Paid yesterday at noon property time, not "now".
  assert.ok(Date.now()-p.paidAt.toMillis()>12*3600000);
  const read=await call('owner',{action:'read',bookingId:'k1'});
  assert.deepEqual(read.record.depositPayment,{amount:300000,paymentMethod:'bankTransfer',paidOn:day(-1)});
  assert.equal(read.record.totalPrice-read.record.paidAmount,700000);
});

test('cash today is dated now; the same save twice records one payment',async()=>{
  const {db,call}=setup();
  const data=save({deposit:{amountMinor:200000,method:'cash',paidOn:day(0)}});
  await call('owner',data);await call('owner',data);
  assert.equal(payments(db).length,1);
  assert.ok(Date.now()-payments(db)[0].paidAt.toMillis()<60000);
  assert.equal(db.store.get('bookings/k1').paidAmount,200000);
});

test('a deposit is at most the total, on a real past day, with a known method',async()=>{
  const {call}=setup();
  const bad=deposit=>call('owner',save({deposit}));
  await assert.rejects(bad({amountMinor:1000001,method:'cash',paidOn:day(0)}),e=>e.message==='booking_deposit_too_large');
  await assert.rejects(bad({amountMinor:100000,method:'cash',paidOn:day(1)}),e=>e.message==='booking_deposit_date');
  await assert.rejects(bad({amountMinor:100000,method:'cash',paidOn:'2026-02-30'}),e=>e.message==='booking_deposit_date');
  await assert.rejects(bad({amountMinor:100000,method:'momo',paidOn:day(0)}),e=>e.code==='invalid-argument');
  await assert.rejects(bad({amountMinor:0,method:'cash',paidOn:day(0)}),e=>e.code==='invalid-argument');
  await assert.rejects(bad({amountMinor:100000,method:'cash',paidOn:day(0),note:'x'}),e=>e.code==='invalid-argument');
  // 1,000,000 exactly is fine: everything paid up front.
  await call('owner',save({deposit:{amountMinor:1000000,method:'creditCard',paidOn:day(0)}}));
});

test('taking a deposit needs "Thu tiền"; a booking without one still saves',async()=>{
  const {db,call}=setup();
  await assert.rejects(call('clerk',save({deposit:{amountMinor:100000,method:'cash',paidOn:day(0)}})),e=>e.code==='permission-denied');
  await call('clerk',save());
  assert.equal(db.store.get('bookings/k1').paidAmount,0);
  assert.equal((await call('clerk',{action:'rooms'})).canCollect,false);
  assert.equal((await call('desk',{action:'rooms'})).canCollect,true);
});

test('a deposit can be added on a later edit once, then stays; checkout collects the rest',async()=>{
  const {db,call}=setup();
  await call('desk',save());
  let read=await call('desk',{action:'read',bookingId:'k1'});
  await call('desk',save({operationId:'op2',revision:read.record.revision,deposit:{amountMinor:400000,method:'cash',paidOn:day(0)}}));
  read=await call('desk',{action:'read',bookingId:'k1'});
  await assert.rejects(call('desk',save({operationId:'op3',revision:read.record.revision,deposit:{amountMinor:100000,method:'cash',paidOn:day(0)}})),e=>e.message==='booking_deposit_recorded');
  // An edit without a deposit keeps it.
  await call('desk',save({operationId:'op4',revision:read.record.revision,guestName:'Anh Hai'}));
  assert.deepEqual([db.store.get('bookings/k1').paidAmount,db.store.get('bookings/k1').depositPayment.amount],[400000,400000]);
  read=await call('desk',{action:'read',bookingId:'k1'});
  await call('desk',{action:'command',bookingId:'k1',operationId:'in',revision:read.record.revision,command:'status',status:'checkedIn',reason:'Nhận phòng'});
  read=await call('desk',{action:'read',bookingId:'k1'});
  await call('desk',{action:'command',bookingId:'k1',operationId:'out',revision:read.record.revision,command:'checkout',paymentMethod:'cash',reason:'Trả phòng'});
  assert.deepEqual(payments(db).map(p=>p.amount).sort((a,b)=>a-b),[400000,600000]);
  assert.equal(db.store.get('bookings/k1').paidAmount,1000000);
});

test('the public calendar callable cannot record a deposit',async()=>{
  const {calendar}=setup();
  await assert.rejects(calendar({action:'create',bookingId:'k9',operationId:'x',serverPricing:true,depositPayment:{amount:1,paymentMethod:'cash',paidOn:day(0),paidAt:{__timestamp:Date.now()}},
    booking:{organizationId:'org',roomId:'r1',guestName:'A',pricingType:'hourly',startTime:{__timestamp:Date.parse('2026-12-10T07:00:00Z')},endTime:{__timestamp:Date.parse('2026-12-10T10:00:00Z')}}},{auth:{uid:'owner'}}),
    e=>e.code==='invalid-argument');
});
