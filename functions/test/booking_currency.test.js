const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {normalizeRates}=require('../reference_rates');
const {createBookingWorkspaceHandler}=require('../booking_workspace');
const {createCalendarHandler}=require('../calendar');
function setup(){
 const rates=normalizeRates([{base:'USD',quote:'VND',rate:25000,date:'2026-10-08'}]);
 const db=fakeDb({'organizations/o':{accessVersion:2,displayCurrency:'USD'},
 'memberships/u_o':{ownerId:'u',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all'},
 'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh'},
 'rooms/r':{organizationId:'o',buildingId:'b',currency:'VND',nightlyPrice:500000},
 [`referenceExchangeRates/${rates.id}`]:rates});
 const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
 const api=createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar});
 const data={action:'quote',organizationId:'o',buildingId:'b',roomId:'r',startLocal:'2026-10-10 14:00',endLocal:'2026-10-12 12:00',pricingType:'nightly',inputCurrency:'USD',ratesId:rates.id};
 return {db,data,call:d=>api({auth:{uid:'u'},data:{...data,...d}})};
}
test('creation-time deposit retains original input and rejects currency changes before commit',async()=>{
 for(const race of [false,true]){
  const {db,data}=setup();
  db.store.set('bookings/old',{organizationId:'o',buildingId:'b',roomId:'r',currency:'VND',status:'pending',createdBy:'u',paidAmount:0,nightPrices:[500000,500000],pricingType:'nightly',totalPrice:1000000});
  const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
  const api=createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar:(input,context)=>{if(race)db.store.get('organizations/o').displayCurrency='VND';return calendar(input,context);}});
  const request={auth:{uid:'u'},data:{...data,action:'save',bookingId:'old',revision:'0:0',operationId:'deposit',inputCurrency:'VND',guestName:'Guest',depositMinor:250000,deposit:{amountMinor:250000,method:'cash',paidOn:new Date().toISOString().slice(0,10),inputCurrency:'USD',inputAmountMinor:1000,ratesId:data.ratesId}}};
  if(race){await assert.rejects(api(request),e=>e.message==='booking_currency_changed');assert.equal(db.store.get('bookings/old').paidAmount,0);}
  else {await api(request);assert.deepEqual(db.store.get('bookings/old').depositPayment.originalInput,{currency:'USD',amountMinor:1000,exchangeRateSnapshotId:data.ratesId});}
 }
});
test('new booking quotes and stores selected currency without changing room source',async()=>{
 const {db,data,call}=setup();
 const q=await call({});assert.equal(q.record.currency,'USD');assert.equal(q.record.totalMinor,4000);
 const save={action:'save',bookingId:'k',operationId:'op',roomRevision:'0:0',guestName:'Guest',guestPhone:'',notes:'',depositMinor:0};
 const result=await call(save);
 assert.equal(db.store.get('bookings/k').currency,'USD');assert.equal(db.store.get('bookings/k').totalPrice,40);
 assert.deepEqual(db.store.get('bookings/k').sourceRates,{currency:'VND',exchangeRateSnapshotId:data.ratesId,nightlyPrice:500000});
 assert.equal(db.store.get('rooms/r').currency,'VND');assert.equal(db.store.get('rooms/r').nightlyPrice,500000);
 db.store.get('organizations/o').displayCurrency='VND';
 assert.deepEqual(await call(save),result);
 await assert.rejects(call({...save,guestName:'Changed'}));
 db.store.get('memberships/u_o').status='revoked';
 await assert.rejects(call(save),e=>e.code==='permission-denied');
});

test('existing booking keeps its original currency when selected and room currencies differ',async()=>{
 const {db,call}=setup();
 db.store.set('bookings/old',{organizationId:'o',buildingId:'b',roomId:'r',currency:'VND',status:'pending',createdBy:'u',paidAmount:0,nightPrices:[500001,500001],pricingType:'nightly',totalPrice:1000002});
 const q=await call({bookingId:'old',inputCurrency:'VND'});
 assert.equal(q.record.currency,'VND');assert.equal(q.record.totalMinor,1000002);
 await call({action:'save',bookingId:'old',revision:'0:0',operationId:'edit',inputCurrency:'VND',depositMinor:0,guestName:'Guest'});
 assert.equal(db.store.get('bookings/old').totalPrice,1000002);
 assert.equal(db.store.get('bookings/old').currency,'VND');
});

test('new bookings reject stale currency and missing rates before writes',async()=>{
 for(const patch of [{inputCurrency:'VND'},{ratesId:undefined}]){
  const {db,call}=setup();
  await assert.rejects(call(patch),e=>e.code==='failed-precondition');
  assert.equal([...db.store.keys()].some(k=>k.startsWith('bookings/')),false);
 }
});

test('staff without price override gets converted standard rate but cannot change it',async()=>{
 const {db,call}=setup();
 Object.assign(db.store.get('rooms/r'),{hourlyPrice:100000});
 Object.assign(db.store.get('memberships/u_o'),{role:'custom',roleGrants:{readBookings:'managed',createBookings:'managed'}});
 const q=await call({pricingType:'hourly',hourlyPriceMinor:400,endLocal:'2026-10-10 16:00'});
 assert.equal(q.record.totalMinor,800);
 await assert.rejects(call({pricingType:'hourly',hourlyPriceMinor:399}),e=>e.code==='permission-denied');
});

test('currency changed between workspace pricing and calendar commit blocks a new booking',async()=>{
 const {db,data}=setup();
 const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
 const api=createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar:(input,context)=>{
  db.store.get('organizations/o').displayCurrency='VND';return calendar(input,context);
 }});
 await assert.rejects(api({auth:{uid:'u'},data:{...data,action:'save',bookingId:'k',operationId:'race',guestName:'Guest',depositMinor:0}}),e=>e.message==='booking_currency_changed');
 assert.equal(db.store.has('bookings/k'),false);
});

test('booking collection and refund retain entered currency and validate conversion before applying source balances',async()=>{
 const {db,data}=setup();
 db.store.set('bookings/k',{organizationId:'o',buildingId:'b',roomId:'r',currency:'VND',status:'pending',guestName:'Guest',createdBy:'u',totalPrice:1000000,paidAmount:0,depositAmount:500000,depositPaidAmount:0,depositRefundedAmount:0});
 const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
 const api=createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar});
 const input={action:'command',organizationId:'o',buildingId:'b',bookingId:'k',operationId:'collect',revision:'0:0',command:'payment',amountMinor:250000,inputCurrency:'USD',inputAmountMinor:1000,ratesId:data.ratesId,paymentMethod:'cash',reason:'Paid'};
 const run=d=>api({auth:{uid:'u'},data:{...input,...d}});
 const result=await run({});
 assert.equal(db.store.get('bookings/k').paidAmount,250000);
 assert.deepEqual(db.store.get(result.paymentId?`payments/${result.paymentId}`:'').originalInput,{currency:'USD',amountMinor:1000,exchangeRateSnapshotId:data.ratesId});
 await assert.rejects(run({operationId:'forged',inputAmountMinor:999}),e=>e.message==='booking_invalid_conversion');
 await run({command:'refundRent',operationId:'refund'});
 assert.equal(db.store.get('bookings/k').paidAmount,0);
 db.store.get('organizations/o').displayCurrency='VND';
 assert.deepEqual(await run({}),result);
 await assert.rejects(run({operationId:'stale'}),e=>e.message==='booking_currency_changed');
});

test('paying the displayed full balance preserves the exact source remainder and audits rounding',async()=>{
 const {db,data}=setup();
 db.store.set('bookings/k',{organizationId:'o',buildingId:'b',roomId:'r',currency:'VND',status:'pending',guestName:'Guest',createdBy:'u',totalPrice:500001,paidAmount:0});
 const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue:{increment:n=>n},HttpsError:CodeError});
 const api=createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar});
 const input={action:'command',organizationId:'o',buildingId:'b',bookingId:'k',operationId:'full',revision:'0:0',command:'payment',amountMinor:500001,inputCurrency:'USD',inputAmountMinor:2000,ratesId:data.ratesId,paymentMethod:'cash',reason:'Full balance'};
 const result=await api({auth:{uid:'u'},data:input});
 assert.equal(db.store.get('bookings/k').paidAmount,500001);
 assert.equal(db.store.get(`payments/${result.paymentId}`).originalInput.roundingAdjustmentMinor,1);
 await assert.rejects(api({auth:{uid:'u'},data:{...input,command:'refundRent',operationId:'partial',amountMinor:250001,inputAmountMinor:1000}}),e=>e.message==='booking_invalid_conversion');
 const refund=await api({auth:{uid:'u'},data:{...input,command:'refundRent',operationId:'refund-full'}});
 assert.equal(db.store.get('bookings/k').paidAmount,0);
 assert.equal(db.store.get(`payments/${refund.paymentId}`).originalInput.roundingAdjustmentMinor,1);
});
