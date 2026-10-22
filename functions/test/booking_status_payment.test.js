// 2026-10-14 (Tom): short stays get their status from staff (not the clock), and a payment (day, amount, note) can be
// recorded with the booking, next to the deposit.
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
const stay={roomId:'r1',startLocal:'2026-01-10 14:00',endLocal:'2026-01-12 12:00',occurrence:'first',pricingType:'nightly'};// 2 × 500,000
const save=(call,data)=>call({action:'save',bookingId:'k1',roomRevision:'0:0',guestName:'Anh',guestPhone:'',notes:'',depositMinor:0,...stay,...data});
const revision=async call=>(await call({action:'read',bookingId:'k1'})).record.revision;

test('staff choose the stay status, change it later and can set a checked-out stay back',async()=>{
  const {db,owner}=setup();
  await save(owner,{operationId:'o1',stayStatus:'notCheckedIn'});
  assert.equal(db.store.get('bookings/k1').status,'pending');
  await save(owner,{operationId:'o2',revision:await revision(owner),stayStatus:'checkedIn'});
  let b=db.store.get('bookings/k1');assert.equal(b.status,'checkedIn');assert.equal(b.checkedInBy,'owner');
  await save(owner,{operationId:'o3',revision:await revision(owner),stayStatus:'checkedOut'});
  b=db.store.get('bookings/k1');assert.equal(b.status,'checkedOut');assert.equal(b.checkedOutBy,'owner');
  // Still editable, and back to staying.
  await save(owner,{operationId:'o4',revision:await revision(owner),stayStatus:'checkedIn',guestName:'Anh Tuấn'});
  b=db.store.get('bookings/k1');assert.equal(b.status,'checkedIn');assert.equal(b.guestName,'Anh Tuấn');
  await assert.rejects(save(owner,{operationId:'o5',revision:await revision(owner),stayStatus:'gone'}),e=>e.code==='invalid-argument');
});

test('a checked-out stay frees the room; setting it back checks the room again',async()=>{
  const {db,owner}=setup();
  await save(owner,{operationId:'o1',stayStatus:'checkedOut'});
  await save(owner,{bookingId:'k2',operationId:'o2',stayStatus:'notCheckedIn'});
  assert.equal(db.store.get('bookings/k2').status,'pending');
  await assert.rejects(save(owner,{operationId:'o3',revision:await revision(owner),stayStatus:'checkedIn'}),e=>e.code==='already-exists');
});

test('the status command checks out without taking money',async()=>{
  const {db,owner}=setup();
  await save(owner,{operationId:'o1',stayStatus:'checkedIn'});
  await owner({action:'command',bookingId:'k1',operationId:'c1',revision:await revision(owner),command:'status',status:'checkedOut',reason:'Khách đi'});
  const b=db.store.get('bookings/k1');
  assert.equal(b.status,'checkedOut');assert.equal(b.paidAmount,0);
  assert.equal([...db.store.keys()].filter(k=>k.startsWith('payments/')).length,0);
});

test('a payment with the booking: day, amount and note; never more than owed; needs "Thu tiền"',async()=>{
  const {db,owner,rec}=setup();
  const pay={amountMinor:300000,method:'cash',paidOn:'2026-01-10',note:'  Trả trước  '};
  await assert.rejects(save(rec,{operationId:'r1',payment:pay}),e=>e.code==='permission-denied');
  await assert.rejects(save(owner,{operationId:'o0',payment:{...pay,amountMinor:1000001}}),e=>e.code==='invalid-argument');
  await assert.rejects(save(owner,{operationId:'o0',payment:{...pay,paidOn:'2999-01-01'}}),e=>e.code==='invalid-argument');
  await assert.rejects(save(owner,{operationId:'o0',payment:{...pay,note:'x'.repeat(501)}}),e=>e.code==='invalid-argument');
  // Deposit 200,000 + payment 300,000 in one save.
  await save(owner,{operationId:'o1',deposit:{amountMinor:200000,method:'cash',paidOn:'2026-01-09'},payment:pay,depositNote:'Cọc qua Zalo'});
  let b=db.store.get('bookings/k1');
  assert.equal(b.paidAmount,500000);assert.equal(b.depositNote,'Cọc qua Zalo');
  assert.deepEqual(b.rentPayments.map(p=>[p.amount,p.paidOn,p.note,p.paymentMethod]),[[300000,'2026-01-10','Trả trước','cash']]);
  const payments=[...db.store.entries()].filter(([k])=>k.startsWith('payments/')).map(([,v])=>v);
  assert.equal(payments.length,2);
  assert.ok(payments.some(p=>p.amount===300000&&p.notes==='Trả trước'&&p.descriptionKey==='booking_payment'));
  // Read shows it; a second payment adds a line; the rest only up to what is owed.
  const read=(await owner({action:'read',bookingId:'k1'})).record;
  assert.deepEqual(read.rentPayments,[{paymentId:'booking_k1_o1_payment',amount:300000,paymentMethod:'cash',paidOn:'2026-01-10',note:'Trả trước'}]);
  await assert.rejects(save(owner,{operationId:'o2',revision:await revision(owner),payment:{...pay,amountMinor:500001}}),e=>e.code==='invalid-argument');
  await save(owner,{operationId:'o3',revision:await revision(owner),payment:{amountMinor:500000,method:'bankTransfer',paidOn:'2026-01-12'}});
  b=db.store.get('bookings/k1');
  assert.equal(b.paidAmount,1000000);assert.equal(b.rentPayments.length,2);assert.equal(b.rentPayments[1].note,'');
});

test('the public calendar callable cannot set the status or a payment directly',async()=>{
  const {calendar}=setup();
  const booking={organizationId:'org',roomId:'r1',guestName:'X',pricingType:'nightly',totalPrice:1,startTime:{__timestamp:Date.parse('2026-12-10T07:00:00Z')},endTime:{__timestamp:Date.parse('2026-12-11T05:00:00Z')}};
  await assert.rejects(calendar({action:'create',bookingId:'k9',booking,stayStatus:'checkedIn'},{auth:{uid:'owner'}}),e=>e.code==='invalid-argument');
  await assert.rejects(calendar({action:'create',bookingId:'k9',booking,rentPayment:{amount:1,paymentMethod:'cash',paidOn:'2026-12-10',paidAt:{__timestamp:1}}},{auth:{uid:'owner'}}),e=>e.code==='invalid-argument');
});

test('combined deposit and payment retries are exact and recheck current access',async()=>{
  const {db,owner}=setup();
  const request={operationId:'retry',stayStatus:'checkedIn',deposit:{amountMinor:200000,method:'cash',paidOn:'2026-01-10'},payment:{amountMinor:300000,method:'cash',paidOn:'2026-01-10',note:'Receipt'}};
  const first=await save(owner,request);
  assert.deepEqual(await save(owner,request),first);
  assert.equal(db.store.get('bookings/k1').paidAmount,500000);
  assert.equal([...db.store.keys()].filter(k=>k.startsWith('payments/')).length,2);
  await assert.rejects(save(owner,{...request,payment:{...request.payment,note:'Changed'}}),e=>e.code==='failed-precondition');
  db.store.get('memberships/owner_org').status='suspended';
  await assert.rejects(save(owner,request),e=>e.code==='permission-denied');
});
