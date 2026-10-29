// Short-stay payment list (2026-10-24, Tom): each "lần thanh toán" has a day, a type, an amount, how it was paid and who
// received it (staff for cash, an account otherwise). More than owed = change given back. Refunds are a type. Changing a
// recorded payment needs "Sửa lần thanh toán" and is kept in activity history.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createBookingWorkspaceHandler}=require('../booking_workspace');
const {createCalendarHandler}=require('../calendar');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const seed=()=>({
  'organizations/org':{name:'Org',accessVersion:2,createdBy:'owner',paymentAccounts:[{id:'vcb',label:'Vietcombank 0123'}]},
  'organizations/v1':{name:'Old',createdBy:'owner'},
  'memberships/owner_org':{ownerId:'owner',organizationId:'org',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]},
  'memberships/rec_org':{ownerId:'rec',organizationId:'org',accessVersion:2,role:'receptionist',status:'active',buildingScope:'all',buildingIds:[]},
  'memberships/acc_org':{ownerId:'acc',organizationId:'org',accessVersion:2,role:'accountant',status:'active',buildingScope:'all',buildingIds:[]},
  'memberships/admin_org':{ownerId:'admin',organizationId:'org',accessVersion:2,role:'administrator',status:'active',buildingScope:'all',buildingIds:[]},
  'memberships/gone_org':{ownerId:'gone',organizationId:'org',accessVersion:2,role:'administrator',status:'suspended',buildingScope:'all',buildingIds:[]},
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'101',rentalMode:'both',hourlyPrice:100000,nightlyPrice:500000},
  'staffProfiles/s1':{organizationId:'org',displayName:'Trần Minh Khoa',accountId:'rec'},
  'staffProfiles/s2':{organizationId:'org',displayName:'Nghỉ việc',employmentStatus:'inactive'},
  'staffProfiles/x9':{organizationId:'other',displayName:'Người ngoài'},
});
const FieldValue={increment:n=>n};
const setup=()=>{
  const db=fakeDb(seed());
  const calendar=createCalendarHandler({db,Timestamp:Ts,FieldValue,HttpsError:CodeError});
  const as=uid=>data=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar,FieldValue})({auth:{uid},data:{organizationId:'org',buildingId:'b1',...data}});
  return {db,as,owner:as('owner'),rec:as('rec'),acc:as('acc'),admin:as('admin'),gone:as('gone')};
};
const stay={roomId:'r1',startLocal:'2026-09-28 14:00',endLocal:'2026-09-30 12:00',occurrence:'first',pricingType:'nightly'};// 2 × 500,000
const save=(call,data)=>call({action:'save',bookingId:'k1',operationId:'s1',roomRevision:'0:0',guestName:'Anh',guestPhone:'',notes:'',depositMinor:0,...stay,...data});
const cash={methodId:'cash',paidOn:'2026-09-27'};
const pay=(call,data)=>call({action:'receipt',bookingId:'k1',...data});
const list=async call=>call({action:'receipts',bookingId:'k1'});
const payments=db=>[...db.store.entries()].filter(([k])=>k.startsWith('payments/')).map(([,v])=>v);

test('payments add up: deposit with the cashier, a transfer into an account, then the rest with change',async()=>{
  const {db,owner,rec}=setup();
  await save(owner,{});
  await pay(rec,{operationId:'p1',kind:'deposit',amountMinor:300000,...cash,receivedById:'s1',note:' Cọc qua Zalo '});
  await pay(rec,{operationId:'p2',kind:'room',amountMinor:200000,methodId:'bankTransfer',paidOn:'2026-09-28',accountId:'vcb'});
  const b=db.store.get('bookings/k1');
  assert.equal(b.paidAmount,500000);assert.equal(b.depositReceivedAmount,300000);
  // The guest hands over 1,000,000 for the 500,000 still owed: 500,000 is recorded, 500,000 given back.
  const r=await pay(rec,{operationId:'p3',kind:'room',amountMinor:1000000,...cash,paidOn:'2026-09-28'});
  assert.equal(r.recordedMinor,500000);assert.equal(r.changeMinor,500000);
  const l=await list(rec);
  assert.equal(l.totalMinor,1000000);assert.equal(l.paidMinor,1000000);assert.equal(l.remainingMinor,0);assert.equal(l.depositMinor,300000);
  assert.deepEqual(l.records.map(x=>[x.kind,x.amountMinor,x.methodId,x.receivedByName,x.accountLabel,x.changeMinor,x.note]),[
    ['deposit',300000,'cash','Trần Minh Khoa',null,0,'Cọc qua Zalo'],
    ['room',200000,'bankTransfer',null,'Vietcombank 0123',0,''],
    ['room',500000,'cash',null,null,500000,''],
  ]);
  assert.equal(l.canEdit,false);assert.equal(l.canCollect,true);
  // Nothing more is owed now.
  await assert.rejects(pay(rec,{operationId:'p4',kind:'other',amountMinor:1,...cash}),e=>e.message==='booking_nothing_owed');
  const deposited=payments(db).find(p=>p.receiptKind==='deposit');
  assert.equal(deposited.bookingDeposit,true);assert.equal(deposited.descriptionKey,'booking_deposit_payment');
});

test('checks: who may collect, the day, the method, the person and the account',async()=>{
  const {owner,rec,gone}=setup();
  await save(owner,{});
  await assert.rejects(pay(gone,{operationId:'g1',kind:'room',amountMinor:1,...cash}),e=>e.code==='permission-denied');
  await assert.rejects(pay(rec,{operationId:'a1',kind:'room',amountMinor:1,...cash,paidOn:'2026-09-29'}),e=>e.message==='booking_payment_date');
  await assert.rejects(pay(rec,{operationId:'a2',kind:'room',amountMinor:1,...cash,paidOn:'2024-01-01'}),e=>e.message==='booking_payment_date');
  await assert.rejects(pay(rec,{operationId:'a3',kind:'room',amountMinor:1,methodId:'m_none',paidOn:'2026-09-27'}),e=>e.message==='booking_method_invalid');
  await assert.rejects(pay(rec,{operationId:'a4',kind:'room',amountMinor:1,...cash,accountId:'vcb'}),e=>e.code==='invalid-argument');
  await assert.rejects(pay(rec,{operationId:'a5',kind:'room',amountMinor:1,methodId:'bankTransfer',paidOn:'2026-09-27',receivedById:'s1'}),e=>e.code==='invalid-argument');
  await assert.rejects(pay(rec,{operationId:'a6',kind:'room',amountMinor:1,...cash,receivedById:'s2'}),e=>e.message==='booking_staff_invalid');
  await assert.rejects(pay(rec,{operationId:'a7',kind:'room',amountMinor:1,...cash,receivedById:'x9'}),e=>e.message==='booking_staff_invalid');
  await assert.rejects(pay(rec,{operationId:'a8',kind:'room',amountMinor:1,methodId:'bankTransfer',paidOn:'2026-09-27',accountId:'nope'}),e=>e.message==='booking_account_invalid');
  await assert.rejects(pay(rec,{operationId:'a9',kind:'room',amountMinor:0,...cash}),e=>e.code==='invalid-argument');
  await assert.rejects(pay(rec,{operationId:'a10',kind:'room',amountMinor:1,...cash,note:'x'.repeat(501)}),e=>e.code==='invalid-argument');
  await assert.rejects(pay(rec,{operationId:'a11',kind:'tip',amountMinor:1,...cash}),e=>e.code==='invalid-argument');
  await assert.rejects(pay(rec,{operationId:'a12',kind:'room',refundFrom:'room',amountMinor:1,...cash}),e=>e.code==='invalid-argument');
});

test('a new way of paying is kept for everyone; the same name gives the same one',async()=>{
  const {db,as,owner,rec}=setup();
  await save(owner,{});
  const momo=await rec({action:'paymentMethod',operationId:'m1',label:'  Momo '});
  assert.deepEqual(momo.methods,[{id:momo.methodId,label:'Momo'}]);
  assert.equal((await owner({action:'paymentMethod',operationId:'m2',label:'MOMO'})).methodId,momo.methodId);
  assert.equal((await owner({action:'paymentMethod',operationId:'m3',label:'Tiền mặt'})).methodId,'cash');
  const rooms=await owner({action:'rooms'});
  assert.deepEqual(rooms.paymentMethods,[{id:momo.methodId,label:'Momo'}]);
  assert.equal(rooms.canEditPayments,true);
  assert.equal((await rec({action:'rooms'})).myStaffId,'s1');
  assert.equal((await rec({action:'rooms'})).canEditPayments,false);
  await pay(rec,{operationId:'p1',kind:'room',amountMinor:100000,methodId:momo.methodId,paidOn:'2026-09-27',accountId:'vcb'});
  const p=payments(db)[0];
  assert.equal(p.paymentMethod,'other');assert.equal(p.methodLabel,'Momo');assert.equal(p.receivedAccountLabel,'Vietcombank 0123');
  await assert.rejects(rec({action:'paymentMethod',operationId:'m4',label:'x'.repeat(41)}),e=>e.code==='invalid-argument');
  // An investor cannot add one.
  db.store.set('memberships/inv_org',{ownerId:'inv',organizationId:'org',accessVersion:2,role:'investor',status:'active',buildingScope:'all',buildingIds:[]});
  await assert.rejects(as('inv')({action:'paymentMethod',operationId:'m5',label:'Thẻ'}),e=>e.code==='permission-denied');
});

test('refunds are a type: from the deposit or the room money, never more than taken, need "Hoàn tiền"',async()=>{
  const {db,owner,rec,acc}=setup();
  await save(owner,{});
  await pay(rec,{operationId:'p1',kind:'deposit',amountMinor:300000,...cash});
  await pay(rec,{operationId:'p2',kind:'room',amountMinor:200000,...cash});
  const refund={kind:'refund',methodId:'bankTransfer',paidOn:'2026-09-28',accountId:'vcb'};
  await assert.rejects(pay(rec,{operationId:'r0',...refund,refundFrom:'deposit',amountMinor:1}),e=>e.code==='permission-denied');
  await assert.rejects(pay(acc,{operationId:'r2',...refund,refundFrom:'room',amountMinor:200001}),e=>e.message==='booking_refund_exceeds_payment');
  // The deposit is part of the payment (Tom): given back only once the booking is cancelled.
  await assert.rejects(pay(acc,{operationId:'r1',...refund,refundFrom:'deposit',amountMinor:100000}),e=>e.message==='booking_deposit_refund_cancelled_only');
  await pay(acc,{operationId:'r4',...refund,refundFrom:'room',amountMinor:150000});
  let b=db.store.get('bookings/k1');assert.equal(b.paidAmount,350000);assert.equal(b.depositReceivedAmount,300000);
  // A cancelled stay only takes refunds, and now the deposit can be given back.
  db.store.set('bookings/k1',{...db.store.get('bookings/k1'),status:'cancelled'});
  await assert.rejects(pay(rec,{operationId:'p3',kind:'room',amountMinor:1,...cash}),e=>e.message==='booking_invalid_transition');
  await assert.rejects(pay(acc,{operationId:'r5',...refund,refundFrom:'deposit',amountMinor:300001}),e=>e.message==='booking_refund_exceeds_deposit');
  await pay(acc,{operationId:'r6',...refund,refundFrom:'deposit',amountMinor:300000});
  await pay(acc,{operationId:'r7',...refund,refundFrom:'room',amountMinor:50000});
  b=db.store.get('bookings/k1');assert.equal(b.paidAmount,0);assert.equal(b.depositReceivedAmount,0);
  const l=await list(acc);
  assert.deepEqual(l.records.filter(x=>x.kind==='refund').map(x=>[x.refundFrom,x.amountMinor,x.changeMinor]),[['room',150000,null],['deposit',300000,null],['room',50000,null]]);
});

test('changing a recorded payment needs "Sửa lần thanh toán", rechecks the totals and goes to history',async()=>{
  const {db,owner,rec,admin}=setup();
  await save(owner,{});
  const {paymentId}=await pay(rec,{operationId:'p1',kind:'room',amountMinor:400000,...cash,receivedById:'s1'});
  const row=async()=>(await list(owner)).records[0];
  const r0=await row();
  const edit=(call,data)=>pay(call,{paymentId,receiptRevision:r0.revision,kind:'room',amountMinor:400000,...cash,receivedById:'s1',...data});
  await assert.rejects(edit(rec,{operationId:'e0',amountMinor:300000}),e=>e.code==='permission-denied');
  await edit(admin,{operationId:'e1',kind:'deposit',amountMinor:300000,paidOn:'2026-09-26',note:'Gõ nhầm'});
  let b=db.store.get('bookings/k1');assert.equal(b.paidAmount,300000);assert.equal(b.depositReceivedAmount,300000);
  const r1=await row();
  assert.deepEqual([r1.kind,r1.amountMinor,r1.paidOn,r1.note,r1.receivedByName],['deposit',300000,'2026-09-26','Gõ nhầm','Trần Minh Khoa']);
  // The old revision no longer matches.
  await assert.rejects(edit(admin,{operationId:'e2'}),e=>e.code==='aborted');
  // A changed amount above what is owed keeps only what is owed (the rest is change).
  const r=await pay(owner,{operationId:'e3',paymentId,receiptRevision:r1.revision,kind:'room',amountMinor:1200000,...cash});
  assert.deepEqual([r.recordedMinor,r.changeMinor],[1000000,200000]);
  b=db.store.get('bookings/k1');assert.equal(b.paidAmount,1000000);assert.equal(b.depositReceivedAmount,0);
  // A payment cannot become a refund (or the other way round).
  await assert.rejects(pay(owner,{operationId:'e4',paymentId,receiptRevision:(await row()).revision,kind:'refund',refundFrom:'room',amountMinor:1,...cash}),e=>e.code==='invalid-argument');
  const history=[...db.store.entries()].filter(([k,v])=>k.startsWith('teamActivity/')&&v.action==='booking_receipt_edit').map(([,v])=>v);
  assert.equal(history.length,2);
  const first=history.find(h=>h.actorId==='admin');
  assert.deepEqual([first.before.amountMinor,first.after.amountMinor,first.after.kind],[400000,300000,'deposit']);
  assert.equal(first.targetId,'k1');
  assert.ok(!JSON.stringify(history).includes('"Anh"'),'no guest details in history');
});

test('an edit that keeps the day keeps the payment in its place in the list',async()=>{
  const {db,owner}=setup();
  await save(owner,{});
  const today={methodId:'cash',paidOn:'2026-09-28'};
  const {paymentId}=await pay(owner,{operationId:'p1',kind:'room',amountMinor:100000,...today});
  Ts.clock+=60000;await pay(owner,{operationId:'p2',kind:'room',amountMinor:100000,...today});
  Ts.clock+=60000;
  const first=(await list(owner)).records[0];
  assert.equal(first.paymentId,paymentId);
  await pay(owner,{operationId:'e1',paymentId,receiptRevision:first.revision,kind:'room',amountMinor:150000,...today});
  assert.deepEqual((await list(owner)).records.map(r=>[r.paymentId,r.amountMinor]),[[paymentId,150000],['booking_k1_p2_receipt',100000]]);
  Ts.clock-=120000;
});

test('a payment recorded by mistake can be deleted: totals go back, history kept, needs "Sửa lần thanh toán"',async()=>{
  const {db,owner,rec,admin}=setup();
  await save(owner,{});
  await pay(rec,{operationId:'p1',kind:'deposit',amountMinor:300000,...cash});
  await pay(rec,{operationId:'p2',kind:'room',amountMinor:200000,...cash});
  const rows=(await list(owner)).records;
  const remove=(call,row,op)=>call({action:'removeReceipt',bookingId:'k1',operationId:op,paymentId:row.paymentId,receiptRevision:row.revision});
  await assert.rejects(remove(rec,rows[1],'d0'),e=>e.code==='permission-denied');
  const r=await remove(admin,rows[1],'d1');
  assert.deepEqual(await remove(admin,rows[1],'d1'),r,'exact retry');
  let b=db.store.get('bookings/k1');assert.equal(b.paidAmount,300000);assert.equal(b.depositReceivedAmount,300000);
  assert.deepEqual((await list(owner)).records.map(x=>x.kind),['deposit']);
  const gone=db.store.get(`payments/${rows[1].paymentId}`);
  assert.equal(gone.status,'cancelled');assert.equal(gone.paidAmount,0);assert.equal(gone.amount,200000);
  const h=[...db.store.values()].find(v=>v.action==='booking_receipt_delete');
  assert.equal(h.before.amountMinor,200000);assert.equal(h.after,null);assert.equal(h.actorId,'admin');
  // Already deleted, or a changed revision.
  await assert.rejects(remove(admin,rows[1],'d2'),e=>e.code==='not-found');
  await assert.rejects(owner({action:'removeReceipt',bookingId:'k1',operationId:'d3',paymentId:rows[0].paymentId,receiptRevision:'old'}),e=>e.code==='aborted');
  // Cancelled, the deposit was partly given back: the deposit cannot be deleted below what was refunded.
  db.store.set('bookings/k1',{...db.store.get('bookings/k1'),status:'cancelled'});
  await pay(owner,{operationId:'r1',kind:'refund',refundFrom:'deposit',amountMinor:100000,...cash});
  const dep=(await list(owner)).records.find(x=>x.kind==='deposit');
  await assert.rejects(remove(owner,dep,'d4'),e=>e.message==='booking_payment_balance');
  const refundRow=(await list(owner)).records.find(x=>x.kind==='refund');
  await remove(owner,refundRow,'d5');
  await remove(owner,(await list(owner)).records[0],'d6');
  b=db.store.get('bookings/k1');assert.equal(b.paidAmount,0);assert.equal(b.depositReceivedAmount,0);
});

test('a way of paying typed once is kept on the payment only, not in the list',async()=>{
  const {db,owner}=setup();
  await save(owner,{});
  await assert.rejects(pay(owner,{operationId:'o0',kind:'room',amountMinor:1,methodId:'other',paidOn:'2026-09-27'}),e=>e.code==='invalid-argument');
  await assert.rejects(pay(owner,{operationId:'o1',kind:'room',amountMinor:1,...cash,methodLabel:'x'}),e=>e.code==='invalid-argument');
  await pay(owner,{operationId:'o2',kind:'room',amountMinor:100000,methodId:'other',methodLabel:'  Thẻ  quà tặng ',paidOn:'2026-09-27'});
  const row=(await list(owner)).records[0];
  assert.deepEqual([row.methodId,row.methodLabel],['other','Thẻ quà tặng']);
  assert.deepEqual((await owner({action:'rooms'})).paymentMethods,[]);
  assert.equal(db.store.get('orgPaymentMethods/org'),undefined);
});

test('retries: the same request returns the first answer; another request under the same ID is refused',async()=>{
  const {db,owner,rec}=setup();
  await save(owner,{});
  const data={operationId:'p1',kind:'room',amountMinor:100000,...cash};
  const first=await pay(rec,data);
  assert.deepEqual(await pay(rec,data),first);
  assert.equal(payments(db).length,1);assert.equal(db.store.get('bookings/k1').paidAmount,100000);
  await assert.rejects(pay(rec,{...data,amountMinor:200000}),e=>e.message==='booking_operation_reused');
});

test('a new booking saves with the payments added before its first save, all or nothing',async()=>{
  const {db,as,owner,rec}=setup();
  await assert.rejects(save(rec,{receipts:[{kind:'deposit',amountMinor:300000,...cash},{kind:'room',amountMinor:700000,...cash},{kind:'other',amountMinor:1,...cash}]}),e=>e.message==='booking_nothing_owed');
  assert.equal(db.store.get('bookings/k1'),undefined);assert.equal(payments(db).length,0);
  await assert.rejects(save(rec,{receipts:[{kind:'refund',refundFrom:'room',amountMinor:1,...cash}]}),e=>e.code==='invalid-argument');
  const r=await save(rec,{receipts:[{kind:'deposit',amountMinor:300000,...cash,receivedById:'s1'},{kind:'room',amountMinor:1000000,methodId:'bankTransfer',paidOn:'2026-09-28',accountId:'vcb'}]});
  assert.equal(r.receiptIds.length,2);
  const b=db.store.get('bookings/k1');assert.equal(b.paidAmount,1000000);assert.equal(b.depositReceivedAmount,300000);
  const l=await list(owner);
  assert.deepEqual(l.records.map(x=>[x.kind,x.amountMinor,x.changeMinor]).sort(),[['deposit',300000,0],['room',700000,300000]]);
  // Only on the first save; later payments use the dialog.
  await assert.rejects(save(owner,{operationId:'s2',revision:'0:0',receipts:[]}),e=>e.code==='invalid-argument');
  // Without "Thu tiền" no payment comes with the booking.
  db.store.set('memberships/c_org',{ownerId:'c',organizationId:'org',accessVersion:2,role:'custom',roleGrants:{readBookings:'managed',createBookings:'managed',manageBookings:'managed'},status:'active',buildingScope:'all',buildingIds:[]});
  await assert.rejects(save(as('c'),{bookingId:'k2',operationId:'s3',startLocal:'2026-10-05 14:00',endLocal:'2026-10-06 12:00',receipts:[{kind:'room',amountMinor:1,...cash}]}),e=>e.code==='permission-denied');
});

test('older bookings: their deposit and payments show on the list and can be changed or refunded',async()=>{
  const {db,owner}=setup();
  // Saved with the earlier form: deposit 200,000 with the booking and a payment of 300,000.
  await save(owner,{deposit:{amountMinor:200000,method:'cash',paidOn:'2026-09-27'},payment:{amountMinor:300000,method:'bankTransfer',paidOn:'2026-09-28',note:'Trả trước'}});
  // And a deposit taken with the old "Thu cọc" button (kept apart from the total).
  db.store.set('bookings/k1',{...db.store.get('bookings/k1'),depositAmount:100000,depositPaidAmount:100000});
  db.store.set('payments/old_held',{organizationId:'org',buildingId:'b1',roomId:'r1',bookingId:'k1',type:'deposit',status:'paid',amount:100000,paidAmount:100000,currency:'VND',paymentMethod:'cash',paidAt:Ts.fromMillis(Date.parse('2026-09-27T05:00:00Z')),createdAt:Ts.fromMillis(1)});
  const l=await list(owner);
  assert.deepEqual(l.records.map(x=>[x.kind,x.amountMinor,x.methodId]).sort(),[['deposit',100000,'cash'],['deposit',200000,'cash'],['room',300000,'bankTransfer']]);
  assert.equal(l.depositMinor,200000);assert.equal(l.heldDepositMinor,100000);
  // Changing the earlier payment keeps the booking's copy in step.
  const old=l.records.find(x=>x.kind==='room');
  await owner({action:'receipt',bookingId:'k1',operationId:'e1',paymentId:old.paymentId,receiptRevision:old.revision,kind:'room',amountMinor:250000,methodId:'bankTransfer',paidOn:'2026-09-28',note:'Sửa'});
  let b=db.store.get('bookings/k1');
  assert.equal(b.paidAmount,450000);assert.deepEqual(b.rentPayments.map(r=>[r.amount,r.note]),[[250000,'Sửa']]);
  // The earlier deposit changed to room money: no longer "Đã cọc" from that copy.
  const dep=l.records.find(x=>x.kind==='deposit'&&x.amountMinor===200000);
  await owner({action:'receipt',bookingId:'k1',operationId:'e2',paymentId:dep.paymentId,receiptRevision:dep.revision,kind:'room',amountMinor:200000,...cash});
  b=db.store.get('bookings/k1');assert.equal(b.depositPayment,null);assert.equal(b.depositReceivedAmount,0);assert.equal(b.paidAmount,450000);
  // A refund from the deposit (cancelled booking) first returns the deposit kept apart.
  db.store.set('bookings/k1',{...db.store.get('bookings/k1'),status:'cancelled'});
  await owner({action:'receipt',bookingId:'k1',operationId:'r1',kind:'refund',refundFrom:'deposit',amountMinor:100000,...cash});
  b=db.store.get('bookings/k1');assert.equal(b.depositRefundedAmount,100000);assert.equal(b.depositRefunded,true);assert.equal(b.paidAmount,450000);
});

test('other organizations, old (v1) organizations and other properties see nothing',async()=>{
  const {db,owner}=setup();
  await save(owner,{});
  const call=data=>createBookingWorkspaceHandler({db,Timestamp:Ts,HttpsError:CodeError,calendar:()=>{},FieldValue})({auth:{uid:'owner'},data});
  await assert.rejects(call({action:'receipts',organizationId:'v1',buildingId:'b1',bookingId:'k1'}),e=>e.code==='permission-denied');
  db.store.set('buildings/b2',{organizationId:'org',name:'Other',timeZone:'Asia/Ho_Chi_Minh'});
  await assert.rejects(call({action:'receipts',organizationId:'org',buildingId:'b2',bookingId:'k1'}),e=>e.code==='not-found');
  await assert.rejects(call({action:'receipt',organizationId:'org',buildingId:'b1',bookingId:'k1',operationId:'x',kind:'room',amountMinor:1,...cash,extra:1}),e=>e.code==='invalid-argument');
});
