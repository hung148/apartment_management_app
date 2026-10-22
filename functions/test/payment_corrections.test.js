'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createPaymentHandler}=require('../payments');
function setup(booking=true){
 const db=fakeDb({
  'organizations/o':{accessVersion:2},
  'memberships/u_o':{ownerId:'u',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all'},
  'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh'},
  'bookings/k':{organizationId:'o',roomId:'r',totalPrice:1000,paidAmount:300,currency:'VND',rentPayments:[{paymentId:'p',amount:300,paidOn:'2026-09-25',note:'old'}]},
  'rooms/r':{organizationId:'o',buildingId:'b'},
  'tenants/t':{organizationId:'o',buildingId:'b'},
  'payments/p':{organizationId:'o',buildingId:'b',...(booking?{bookingId:'k'}:{tenantId:'t',invoiceVersion:2,totalMinor:1000}),currency:'VND',amount:booking?300:1000,paidAmount:300,status:booking?'paid':'partial',paidAt:Ts.fromMillis(Date.parse('2026-09-25')),notes:'old'},
  ...(!booking?{'paymentOperations/receipt':{organizationId:'o',paymentId:'p',action:'collect',amountMinor:300,currency:'VND',createdAt:Ts.fromMillis(Date.parse('2026-09-25'))}}:{}),
 });
 const api=createPaymentHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const scope={organizationId:'o',buildingId:'b',...(booking?{bookingId:'k'}:{tenantId:'t'})};
 const call=d=>api({auth:{uid:'u'},data:{...scope,...d}});
 return {db,call};
}
for(const booking of [true,false])test(`correct saved ${booking?'booking':'lease'} receipt without collecting again`,async()=>{
 const {db,call}=setup(booking);
 const list=await call({action:'receipts'});
 assert.equal(list.records.length,1);
 const input={action:'correctReceipt',operationId:'fix',paymentId:'p',receiptId:list.records[0].receiptId,revision:list.records[0].revision,amountMinor:200,paidOn:'2026-09-24',note:'corrected'};
 await call(input);
 assert.equal(db.store.get('payments/p').paidAmount,200);
 if(booking){assert.equal(db.store.get('bookings/k').paidAmount,200);assert.equal(db.store.get('bookings/k').rentPayments[0].note,'corrected');}
 const read=(await call({action:'receipts'})).records[0];
 assert.equal(read.amountMinor,200);assert.equal(read.paidOn,'2026-09-24');assert.equal(read.note,'corrected');
 await call(input);assert.equal(db.store.get('payments/p').paidAmount,200);
 await assert.rejects(call({...input,operationId:'stale'}),e=>e.code==='aborted');
 db.store.get('memberships/u_o').status='revoked';
 await assert.rejects(call(input),e=>e.code==='permission-denied');
});
test('rejects overpayment, invalid dates, precision, scope and unauthorized corrections',async()=>{
 for(const patch of [{amountMinor:1200},{paidOn:'2026-02-30'},{paidOn:'2999-01-01'},{amountMinor:1.5},{amountMinor:0},{buildingId:'other'},{tenantId:'t'}]){
  const {db,call}=setup();const r=(await call({action:'receipts'})).records[0];
  await assert.rejects(call({action:'correctReceipt',operationId:'fix',paymentId:'p',receiptId:r.receiptId,revision:r.revision,amountMinor:200,paidOn:'2026-09-24',note:'note',...patch}));
  assert.equal(db.store.get('payments/p').paidAmount,300);
 }
});
test('corrects one of several lease receipts and keeps original operation/history',async()=>{
 const {db,call}=setup(false);
 db.store.set('paymentOperations/second',{organizationId:'o',paymentId:'p',action:'collect',amountMinor:100,createdAt:Ts.fromMillis(Date.parse('2026-09-26'))});
 db.store.get('payments/p').paidAmount=400;
 const r=(await call({action:'receipts'})).records.find(r=>r.receiptId==='receipt');
 await call({action:'correctReceipt',operationId:'fix',paymentId:'p',receiptId:r.receiptId,revision:r.revision,amountMinor:250,paidOn:'2026-09-24',note:'fixed'});
 assert.equal(db.store.get('payments/p').paidAmount,350);
 assert.equal(db.store.get('paymentOperations/receipt').amountMinor,300);
 assert.equal((await call({action:'receipts'})).records.find(r=>r.receiptId==='second').amountMinor,100);
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('payments/p/invoiceHistory/')).length,1);
});
test('deposit correction updates booking deposit, and refunded records cannot be rewritten',async()=>{
 const {db,call}=setup();const b=db.store.get('bookings/k');
 b.rentPayments=[];b.depositPayment={paymentId:'p',amount:300,paidOn:'2026-09-25'};
 db.store.get('payments/p').bookingDeposit=true;
 const r=(await call({action:'receipts'})).records[0];
 await call({action:'correctReceipt',operationId:'fix',paymentId:'p',receiptId:r.receiptId,revision:r.revision,amountMinor:250,paidOn:'2026-09-24',note:'deposit fixed'});
 assert.equal(db.store.get('bookings/k').depositPayment.amount,250);
 assert.equal(db.store.get('bookings/k').depositNote,'deposit fixed');
 db.store.get('payments/p').status='refunded';
 assert.equal((await call({action:'receipts'})).records.length,0);
});
test('legacy receipt remains editable alongside newer collections; USD keeps cents',async()=>{
 const {db,call}=setup(false);db.store.delete('paymentOperations/receipt');
 Object.assign(db.store.get('payments/p'),{currency:'USD',amount:10,totalMinor:1000,paidAmount:3});
 let r=(await call({action:'receipts'})).records[0];assert.equal(r.receiptId,'legacy');
 await call({action:'correctReceipt',operationId:'fix',paymentId:'p',receiptId:r.receiptId,revision:r.revision,amountMinor:251,paidOn:'2026-09-24',note:'legacy'});
 assert.equal(db.store.get('payments/p').paidAmount,2.51);
 db.store.get('payments/p').paidAmount=3.51;
 db.store.set('paymentOperations/new',{organizationId:'o',paymentId:'p',action:'collect',amountMinor:100,createdAt:Ts.now()});
 const rows=(await call({action:'receipts'})).records;
 assert.deepEqual(rows.map(r=>r.amountMinor),[100,251]);
});
test('collection-only role can correct date but cannot reduce money, and foreign/v1 accounts fail closed',async()=>{
 const {db,call}=setup();const m=db.store.get('memberships/u_o');
 Object.assign(m,{role:'custom',roleGrants:{collectPayments:'all'}});
 const r=(await call({action:'receipts'})).records[0];
 const input={action:'correctReceipt',operationId:'fix',paymentId:'p',receiptId:r.receiptId,revision:r.revision,amountMinor:200,paidOn:'2026-09-24',note:'fixed'};
 await assert.rejects(call(input),e=>e.code==='permission-denied');
 await call({...input,amountMinor:300});
 db.store.get('organizations/o').accessVersion=1;
 await assert.rejects(call({action:'receipts'}),e=>e.code==='permission-denied');
 db.store.get('organizations/o').accessVersion=2;db.store.get('bookings/k').organizationId='foreign';
 await assert.rejects(call({action:'receipts'}),e=>e.code==='not-found');
});
