const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createPaymentHandler}=require('../payments');
const {normalizeRates}=require('../reference_rates');
function setup(){
 const rates=normalizeRates([{base:'USD',quote:'VND',rate:25000,date:'2026-10-08'}]);
 const db=fakeDb({
  'organizations/o':{accessVersion:2,displayCurrency:'USD'},
  'memberships/u_o':{ownerId:'u',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all'},
  'buildings/b':{organizationId:'o'},
  'payments/p':{organizationId:'o',buildingId:'b',currency:'VND',amount:1000000,paidAmount:0,status:'pending'},
  [`referenceExchangeRates/${rates.id}`]:rates,
 });
 const api=createPaymentHandler({db,Timestamp:Ts,HttpsError:CodeError});
 return {db,rates,call:data=>api({auth:{uid:'u'},data:{organizationId:'o',paymentId:'p',operationId:'pay',action:'collect',paymentMethod:'cash',amountMinor:250000,...data}})};
}
test('payment records selected input currency while applying the original invoice balance',async()=>{
 const {db,rates,call}=setup();
 const input={inputCurrency:'USD',inputAmountMinor:1000,ratesId:rates.id};
 const result=await call(input);
 assert.equal(db.store.get('payments/p').currency,'VND');
 assert.equal(db.store.get('payments/p').paidAmount,250000);
 const operation=[...db.store.entries()].find(([k])=>k.startsWith('paymentOperations/'))[1];
 assert.deepEqual(operation.originalInput,{currency:'USD',amountMinor:1000,exchangeRateSnapshotId:rates.id});
 db.store.get('organizations/o').displayCurrency='VND';
 assert.deepEqual(await call(input),result);
 await assert.rejects(call({...input,inputAmountMinor:2000}),e=>e.code==='already-exists');
});
test('payment conversion rejects forged values, missing snapshots, and changed currency',async()=>{
 for(const patch of [{inputAmountMinor:999},{ratesId:'a'.repeat(64)},{inputCurrency:'VND'}, {inputAmountMinor:0}]){
  const {db,rates,call}=setup();
  await assert.rejects(call({inputCurrency:'USD',inputAmountMinor:1000,ratesId:rates.id,...patch}));
  assert.equal(db.store.get('payments/p').paidAmount,0);
 }
});
test('refund retains entered currency and rechecks permission even on committed retry',async()=>{
 const {db,rates}=setup();
 Object.assign(db.store.get('payments/p'),{paidAmount:500000,status:'partial',invoiceVersion:2});
 // Refund and collection accept different command fields.
 const api=createPaymentHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const request={organizationId:'o',paymentId:'p',operationId:'refund',action:'refund',reason:'Refund',amountMinor:250000,inputCurrency:'USD',inputAmountMinor:1000,ratesId:rates.id};
 const run=()=>api({auth:{uid:'u'},data:request});
 await run();assert.equal(db.store.get('payments/p').paidAmount,250000);
 const history=[...db.store.entries()].find(([k])=>k.startsWith('payments/p/invoiceHistory/'))[1];
 assert.equal(history.originalInput.currency,'USD');assert.equal(history.originalInput.amountMinor,1000);
 db.store.get('memberships/u_o').status='revoked';
 await assert.rejects(run(),e=>e.code==='permission-denied');
 assert.equal(db.store.get('payments/p').paidAmount,250000);
});
