const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createInvoiceHandler}=require('../invoices');
const {createLeaseLifecycleHandler}=require('../lease_lifecycle');
const {meterId}=require('../utility_invoice');
const {createServiceFeesHandler}=require('../service_fees');
const at=d=>Ts.fromMillis(Date.parse(d+'T00:00:00+07:00'));
const owner={ownerId:'owner',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]};
const fees0={internetFee:0,cableTVFee:0,hotWaterFee:0,lateFee:0,taxAmount:0};
const readingPath=id=>`utilityMeters/${meterId('o','r','electricity')}/readings/${id}`;

// Le Van Chinh moved in on 2 Oct (3-month periods, 15.000.000, deposit 5.000.000).
// Today is 20 Nov 2026 in Vietnam.
function setup({roommateOut=true}={}){
 Ts.clock=Date.parse('2026-11-20T05:00:00Z');
 const db=fakeDb({'organizations/o':{accessVersion:2,paymentAccounts:[{id:'vcb',label:'Vietcombank 0123'}]},'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},'rooms/r':{organizationId:'o',buildingId:'b',roomNumber:'101'},
  'memberships/owner_o':owner,
  'tenants/t':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,status:'active',fullName:'Le Van Chinh',currency:'VND',moveInDate:at('2026-10-02'),monthlyRentMinor:5000000,monthlyRent:5000000,paymentPeriodMonths:3,paymentDueDay:5,periodRentMinor:15000000,depositMinor:5000000,depositMethod:'bankTransfer'},
  'tenants/m':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:false,mainTenantId:'t',fullName:'Pham Thi Dung',currency:'VND',moveInDate:at('2026-10-02'),
   ...(roommateOut?{status:'moveOut',moveOutDate:at('2026-11-10')}:{status:'active'})},
  [`utilityMeters/${meterId('o','r','electricity')}`]:{organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity'},
  [readingPath('x')]:{organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity',startDate:'2026-10-02',date:'2026-10-31',calculation:{currency:'VND',amountMinor:87500,usageMilli:25000},tariff:{currency:'VND'},invoiceId:null}});
 const invoices=createInvoiceHandler({db,Timestamp:Ts,HttpsError:CodeError}),lease=createLeaseLifecycleHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const bill=(data,uid='owner')=>invoices({auth:{uid},data:{organizationId:'o',buildingId:'b',...data}});
 const call=(data,uid='owner')=>lease({auth:{uid},data:{organizationId:'o',buildingId:'b',tenantId:'t',...data}});
 let n=0;const feesHandler=createServiceFeesHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const defineFee=(o={})=>feesHandler({auth:{uid:'owner'},data:{organizationId:'o',buildingId:'b',action:'define',operationId:'f'+(++n),reason:'Bảng giá',revision:n-1,feeId:null,name:'Rác',basis:'room',unitLabel:'',version:{effectiveDate:'2026-10-01',active:true,rateMinor:100000,rule:{mode:'days'},includedPeople:0,roundingMinor:0},...o}});
 return {db,bill,call,defineFee};
}
// The first period invoice (2 Oct - 1 Jan), optionally paid.
async function firstPeriod(bill,db,paidMinor=0){
 const p={kind:'period',tenantId:'t',startDate:'2026-10-02',endDate:'2027-01-02',dueDate:'2026-10-05',feesMinor:fees0,reason:'Kỳ 1',includeRent:true,serviceFeeIds:[],readings:[],lines:[]};
 const q=await bill({action:'quote',...p});const {invoiceId}=await bill({action:'create',...p,operationId:'p1',quoteRevision:q.record.quoteRevision});
 if(paidMinor){const doc=db.store.get(`payments/${invoiceId}`);db.store.set(`payments/${invoiceId}`,{...doc,paidAmount:paidMinor,status:paidMinor===doc.totalMinor?'paid':'partial'});}
 return invoiceId;
}
const choice=o=>({effectiveDate:'2026-11-20',includeRent:false,serviceFeeIds:[],readings:[],lines:[],creditRent:false,creditFees:false,refundMethod:null,refundAccountId:null,dueDate:'2026-11-20',reason:'Trả phòng',...o});
async function settle(call,o={},operationId='s1'){
 const q=await call({action:'settlementQuote',...choice(o)});
 const p=(await call({action:'settlementPreview',effectiveDate:choice(o).effectiveDate})).record;
 return {quote:q.record,result:await call({action:'settle',...choice(o),operationId,revision:p.revision,timeZone:p.timeZone,quoteRevision:q.record.quoteRevision})};
}

test('the preview lists what can be settled and blocks while a roommate still lives there',async()=>{
 const {bill,db,call}=setup({roommateOut:false});await firstPeriod(bill,db,10000000);
 let p=(await call({action:'settlementPreview',effectiveDate:'2026-11-20'})).record;
 assert.equal(p.dateProblem,'lease_handle_roommates_first');
 await assert.rejects(call({action:'settlementQuote',...choice()}),e=>e.message==='lease_handle_roommates_first');
 db.store.set('tenants/m',{...db.store.get('tenants/m'),status:'moveOut',moveOutDate:at('2026-11-10')});
 p=(await call({action:'settlementPreview',effectiveDate:'2026-11-20'})).record;
 assert.equal(p.dateProblem,null);
 assert.equal(p.depositMinor,5000000);
 assert.equal(p.rent,null,'rent is billed until 2 Jan');
 assert.equal(p.credits.length,1);
 assert.equal(p.credits[0].startDate,'2026-11-20');
 assert.equal(p.readings.length,1);
 assert.equal(p.openInvoices[0].balanceMinor,5000000);
 assert.equal(p.lastReading.electricity,'2026-10-31');
 assert.deepEqual(p.accounts,[{id:'vcb',label:'Vietcombank 0123'}]);
});

test('credit for unused rent, final charges and kept deposit; the rest is refunded',async()=>{
 const {bill,db,call}=setup();const first=await firstPeriod(bill,db,15000000);
 const o={creditRent:true,readings:[{roomId:'r',kind:'electricity',readingId:'x'}],lines:[{kind:'damage',label:'Vỡ kính',amountMinor:300000},{kind:'keepDeposit',label:'Phá hợp đồng',amountMinor:1000000}]};
 await assert.rejects(settle(call,o),e=>e.message==='settlement_refund_method_required');
 const {quote,result}=await settle(call,{...o,refundMethod:'bankTransfer',refundAccountId:'vcb'},'s2');
 // 20 Nov - 1 Jan: 11/30 + 31/31 + 1/31 of 5.000.000.
 assert.equal(quote.credits[0].creditMinor,6994624);
 assert.equal(quote.credits[0].returnedMinor,6994624);
 assert.equal(quote.finalMinor,87500+300000+1000000);
 assert.equal(quote.refundMinor,5000000+6994624-1387500);
 assert.equal(quote.owedMinor,0);
 assert.equal(result.refundMinor,quote.refundMinor);
 const t=db.store.get('tenants/t');assert.equal(t.status,'moveOut');assert.equal(t.moveOutLocalDate,'2026-11-20');assert.equal(t.settlementId,result.settlementId);
 const p=db.store.get(`payments/${first}`);assert.equal(p.totalMinor,15000000-6994624);assert.equal(p.paidAmount,15000000-6994624);assert.equal(p.status,'paid');assert.equal(p.amount,15000000-6994624);
 const f=db.store.get(`payments/${result.finalInvoiceId}`);assert.equal(f.invoiceKind,'settlement');assert.equal(f.status,'paid');assert.equal(f.paymentMethod,'deposit');
 assert.equal(db.store.get(readingPath('x')).invoiceId,result.finalInvoiceId);
 const s=db.store.get(`leaseSettlements/${result.settlementId}`);assert.equal(s.refundMethod,'bankTransfer');assert.equal(s.refundAccount.label,'Vietcombank 0123');assert.equal(s.keptMinor,1000000);
 assert.ok([...db.store.keys()].some(k=>k.startsWith('leaseOccupancy/')),'the stay is recorded like "Trả phòng"');
 // An exact retry replays; a second settlement is refused; the final invoice cannot be voided.
 const p2=(await call({action:'settlementPreview'}).catch(e=>e));assert.equal(p2.message,'settlement_exists');
 await assert.rejects(bill({action:'void',invoiceId:result.finalInvoiceId,revision:'0:0',reason:'x',operationId:'v1'}),e=>e.message==='invoice_refund_first'||e.message==='settlement_invoice_locked');
});

test('a period not on calendar months: the tenant pays the normal price for the days stayed',async()=>{
 const {bill,db,call}=setup();db.store.delete('tenants/m');
 // One month, 2 Oct - 1 Nov (charged 5.000.000), moving out on 3 Oct.
 const p={kind:'period',tenantId:'t',startDate:'2026-10-02',endDate:'2026-11-02',dueDate:'2026-10-02',feesMinor:fees0,reason:'Kỳ 1',includeRent:true,serviceFeeIds:[],readings:[],lines:[]};
 const q=await bill({action:'quote',...p});const {invoiceId}=await bill({action:'create',...p,operationId:'p1',quoteRevision:q.record.quoteRevision});
 const doc=db.store.get(`payments/${invoiceId}`);assert.equal(doc.totalMinor,5000000);db.store.set(`payments/${invoiceId}`,{...doc,paidAmount:5000000,status:'paid'});
 const {quote}=await settle(call,{effectiveDate:'2026-10-03',dueDate:'2026-10-03',creditRent:true,refundMethod:'cash'});
 // 2 Oct only = 1/31 of 5.000.000 = 161.290 kept; the rest comes back.
 assert.equal(quote.credits[0].creditMinor,5000000-161290);
 assert.equal(quote.refundMinor,5000000+5000000-161290);
});

test('service fees paid ahead: each fee is priced again with its own short-stay rule',async()=>{
 const {bill,db,call,defineFee}=setup();
 const {feeId:days}=await defineFee();
 const {feeId:first}=await defineFee({name:'Internet',version:{effectiveDate:'2026-10-01',active:true,rateMinor:200000,rule:{mode:'checkDate',day:'first'},includedPeople:0,roundingMinor:0}});
 const p={kind:'period',tenantId:'t',startDate:'2026-10-02',endDate:'2027-01-02',dueDate:'2026-10-05',feesMinor:fees0,reason:'Kỳ 1',includeRent:true,serviceFeeIds:[days,first],readings:[],lines:[]};
 const q=await bill({action:'quote',...p});const {invoiceId}=await bill({action:'create',...p,operationId:'p1',quoteRevision:q.record.quoteRevision});
 const doc=db.store.get(`payments/${invoiceId}`);assert.equal(doc.totalMinor,15000000+300000+600000);
 db.store.set(`payments/${invoiceId}`,{...doc,paidAmount:doc.totalMinor,status:'paid'});
 const pv=(await call({action:'settlementPreview',effectiveDate:'2026-11-20'})).record;
 // "By days": 49 of 92 days stayed, x3 months -> 159.783 used of 300.000.
 // "Full month if there on the 1st": there on 2 Oct, so all of it is used - nothing back.
 assert.deepEqual(pv.feeCredits.map(c=>[c.feeId,c.feeName,c.startDate,c.endDate,c.creditMinor]),[[days,'Rác','2026-11-20','2027-01-02',140217]]);
 await assert.rejects(call({action:'settlementQuote',...choice({creditFees:true})},'nobody'),e=>e.code==='permission-denied');
 const {quote,result}=await settle(call,{creditFees:true,refundMethod:'cash'});
 assert.deepEqual(quote.credits.map(c=>[c.kind,c.feeName,c.creditMinor,c.returnedMinor]),[['fee','Rác',140217,140217]]);
 assert.equal(quote.refundMinor,5000000+140217);
 const after=db.store.get(`payments/${invoiceId}`);assert.equal(after.totalMinor,15900000-140217);assert.equal(after.status,'paid');assert.equal(after.moveOutCredit.creditMinor,140217);
 assert.equal(result.refundMinor,5140217);
});

test('rent and fee credits together on one invoice add up',async()=>{
 const {bill,db,call,defineFee}=setup();const {feeId}=await defineFee();
 const p={kind:'period',tenantId:'t',startDate:'2026-10-02',endDate:'2027-01-02',dueDate:'2026-10-05',feesMinor:fees0,reason:'Kỳ 1',includeRent:true,serviceFeeIds:[feeId],readings:[],lines:[]};
 const q=await bill({action:'quote',...p});const {invoiceId}=await bill({action:'create',...p,operationId:'p1',quoteRevision:q.record.quoteRevision});
 const doc=db.store.get(`payments/${invoiceId}`);db.store.set(`payments/${invoiceId}`,{...doc,paidAmount:doc.totalMinor,status:'paid'});
 const {quote}=await settle(call,{creditRent:true,creditFees:true,refundMethod:'cash'});
 assert.deepEqual(quote.credits.map(c=>[c.kind,c.creditMinor,c.returnedMinor]),[['rent',6994624,6994624],['fee',140217,140217]]);
 assert.equal(quote.refundMinor,5000000+6994624+140217);
 assert.equal(db.store.get(`payments/${invoiceId}`).totalMinor,15300000-6994624-140217);
});

test('a deposit smaller than the unpaid invoices leaves the rest owed',async()=>{
 const {bill,db,call}=setup();const first=await firstPeriod(bill,db,0);
 const {quote,result}=await settle(call,{});
 assert.equal(quote.finalMinor,0);
 assert.deepEqual(quote.applications,[{invoiceId:first,amountMinor:5000000}]);
 assert.equal(quote.refundMinor,0);assert.equal(quote.owedMinor,10000000);
 assert.equal(result.finalInvoiceId,null);
 const p=db.store.get(`payments/${first}`);assert.equal(p.paidAmount,5000000);assert.equal(p.status,'partial');assert.equal(p.paymentMethod,'deposit');
});

test('rent not billed yet is charged up to the move-out day',async()=>{
 const {call}=setup();
 const {quote}=await settle(call,{includeRent:true,refundMethod:'cash'});
 // 2 Oct - 19 Nov: 30/31 of October + 19/30 of November.
 const rent=quote.lines.find(l=>l.type==='rent');
 assert.equal(rent.startDate,'2026-10-02');assert.equal(rent.endDate,'2026-11-20');
 assert.equal(rent.amountMinor,Math.round(5000000*30/31+5000000*19/30));
 // 8.005.376 owed against a 5.000.000 deposit: nothing to refund, the rest stays owed.
 assert.equal(quote.refundMinor,0);assert.equal(quote.owedMinor,rent.amountMinor-5000000);
});

test('a lease moved out earlier is settled on its recorded date',async()=>{
 const {call,db}=setup();
 const r=(await call({action:'read'})).record;
 await call({action:'moveOut',operationId:'mo',revision:r.revision,timeZone:r.timeZone,reason:'Trả phòng',effectiveDate:'2026-11-15'});
 const p=(await call({action:'settlementPreview'})).record;
 assert.equal(p.moveOutDate,'2026-11-15');assert.equal(p.dateFixed,true);
 await assert.rejects(call({action:'settlementQuote',...choice()}),e=>e.message==='settlement_date_fixed');
 const {quote}=await settle(call,{effectiveDate:'2026-11-15',includeRent:true,refundMethod:'cash'});
 assert.equal(quote.lines[0].endDate,'2026-11-15');
 assert.equal(db.store.get('tenants/t').moveOutLocalDate,'2026-11-15');
});

test('lines and credits need price authority; returning paid money needs refund authority',async()=>{
 const {bill,db,call}=setup();await firstPeriod(bill,db,15000000);
 db.store.set('memberships/staff_o',{...owner,ownerId:'staff',role:'custom_staff',roleGrants:{manageLease:'all',readFinancialReports:'all',collectPayments:'all'}});
 await assert.rejects(call({action:'settlementQuote',...choice({lines:[{kind:'damage',label:'Hỏng',amountMinor:1000}]})},'staff'),e=>e.message==='settlement_lines_need_price_authority');
 await assert.rejects(call({action:'settlementQuote',...choice({creditRent:true})},'staff'),e=>e.message==='settlement_lines_need_price_authority');
 db.store.set('memberships/staff_o',{...db.store.get('memberships/staff_o'),roleGrants:{manageLease:'all',readFinancialReports:'all',collectPayments:'all',overridePrices:'all'}});
 await assert.rejects(call({action:'settlementQuote',...choice({creditRent:true})},'staff'),e=>e.message==='settlement_refund_needs_permission');
 // Plain settlement (deposit back) works for staff who can manage leases and collect payments.
 assert.equal((await call({action:'settlementQuote',...choice()},'staff')).record.refundMinor,5000000);
 db.store.set('memberships/outsider_o',{...owner,ownerId:'outsider',role:'custom_staff',roleGrants:{readFinancialReports:'all'}});
 await assert.rejects(call({action:'settlementPreview'},'outsider'),e=>e.code==='permission-denied');
});

test('invalid input, kept deposit above the deposit, future dates and backdating',async()=>{
 const {call,db}=setup();
 for(const bad of [{lines:[{kind:'late',label:'x',amountMinor:-1}]},{lines:[{kind:'keepDeposit',label:'',amountMinor:1}]},{refundMethod:'gold'},{refundAccountId:'vcb'},{reason:' '},{serviceFeeIds:['a','a']}])
  await assert.rejects(call({action:'settlementQuote',...choice(bad)}),e=>e.code==='invalid-argument',JSON.stringify(bad));
 await assert.rejects(call({action:'settlementQuote',...choice({lines:[{kind:'keepDeposit',label:'Giữ',amountMinor:6000000}]})}),e=>e.message==='settlement_keep_exceeds_deposit');
 await assert.rejects(call({action:'settlementQuote',...choice({effectiveDate:'2026-11-21'})}),e=>e.message==='lease_actual_date_required');
 await assert.rejects(call({action:'settlementQuote',...choice({lines:[{kind:'other',label:'Trả lại',amountMinor:-100}]})}),e=>e.message==='settlement_total_negative');
 db.store.set('memberships/staff_o',{...owner,ownerId:'staff',role:'custom_staff',roleGrants:{manageLease:'all',readFinancialReports:'all',collectPayments:'all'}});
 await assert.rejects(call({action:'settlementQuote',...choice({effectiveDate:'2026-11-18'})},'staff'),e=>e.message==='invoice_backdate_owner_required');
 assert.equal((await call({action:'settlementQuote',...choice({effectiveDate:'2026-11-18'})})).record.moveOutDate,'2026-11-18');
});
