const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createServiceFeesHandler}=require('../service_fees');
const {createInvoiceHandler}=require('../invoices');
const {meterId}=require('../utility_invoice');
const {feesId}=require('../service_fee_invoice');
const {addMonths,periodRent}=require('../period_invoice');
const at=d=>Ts.fromMillis(Date.parse(d+'T00:00:00+07:00'));
const owner={ownerId:'owner',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]};
const fees0={internetFee:0,cableTVFee:0,hotWaterFee:0,lateFee:0,taxAmount:0};
const readingPath=id=>`utilityMeters/${meterId('o','r','electricity')}/readings/${id}`;
function setup(){
 Ts.clock=Date.parse('2026-10-03T05:00:00Z');
 const db=fakeDb({'organizations/o':{accessVersion:2},'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},'rooms/r':{organizationId:'o',buildingId:'b',roomNumber:'101'},
  'memberships/owner_o':owner,
  // Le Van Chinh: moved in 2 Oct, pays every 3 months on day 5, 15.000.000 per period, 5.000.000 deposit.
  'tenants/t':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,fullName:'Le Van Chinh',currency:'VND',moveInDate:at('2026-10-02'),monthlyRentMinor:5000000,monthlyRent:5000000,paymentPeriodMonths:3,paymentDueDay:5,periodRentMinor:15000000,depositMinor:5000000},
  'tenants/m':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:false,mainTenantId:'t',fullName:'Pham Thi Dung',currency:'VND',moveInDate:at('2026-10-02')},
  [`utilityMeters/${meterId('o','r','electricity')}`]:{organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity'},
  [readingPath('x')]:{organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity',startDate:'2026-10-02',date:'2026-10-31',calculation:{currency:'VND',amountMinor:87500,usageMilli:25000},tariff:{currency:'VND'},invoiceId:null},
  // Measured before this lease began: never offered or billed to it.
  [readingPath('old')]:{organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity',startDate:'2026-09-01',date:'2026-10-01',calculation:{currency:'VND',amountMinor:50000,usageMilli:10000},tariff:{currency:'VND'},invoiceId:null}});
 const feesHandler=createServiceFeesHandler({db,Timestamp:Ts,HttpsError:CodeError}),invoices=createInvoiceHandler({db,Timestamp:Ts,HttpsError:CodeError});let n=0;
 const defineFee=(o={})=>feesHandler({auth:{uid:'owner'},data:{organizationId:'o',buildingId:'b',action:'define',operationId:'f'+(++n),reason:'Bảng giá',revision:n-1,feeId:null,name:'Rác',basis:'person',unitLabel:'',version:{effectiveDate:'2026-10-01',active:true,rateMinor:20000,rule:{mode:'days'},includedPeople:0,roundingMinor:0},...o}});
 const bill=(data,uid='owner')=>invoices({auth:{uid},data:{organizationId:'o',buildingId:'b',...data}});
 return {db,bill,defineFee};
}
const period=o=>({kind:'period',tenantId:'t',startDate:'2026-10-02',endDate:'2027-01-02',dueDate:'2026-10-05',feesMinor:fees0,reason:'Kỳ 1',includeRent:true,serviceFeeIds:[],readings:[],lines:[],...o});
async function create(bill,o={},operationId='p1'){const q=await bill({action:'quote',...period(o)});return bill({action:'create',...period(o),operationId,quoteRevision:q.record.quoteRevision});}

test('months add with month-end clamping',()=>{
 assert.equal(addMonths('2026-10-02',3),'2027-01-02');assert.equal(addMonths('2026-01-31',1),'2026-02-28');assert.equal(addMonths('2024-01-31',1),'2024-02-29');
});
test('the preview suggests the next lease period, due day, and what can go on it',async()=>{
 const {bill,defineFee}=setup();const {feeId}=await defineFee();
 const p=(await bill({action:'periodPreview',tenantId:'t'})).record;
 assert.deepEqual(p.suggestion,{startDate:'2026-10-02',endDate:'2027-01-02',dueDate:'2026-10-05'});
 assert.equal(p.periodRentMinor,15000000);assert.equal(p.periodMonths,3);
 assert.deepEqual(p.fees.map(f=>f.id),[feeId]);
 assert.deepEqual(p.readings.map(r=>r.readingId),['x'],'readings from before the lease are not offered');
 // The latest electricity reading of the lease and its state (2026-10-04).
 assert.deepEqual(p.lastElectricity,{date:'2026-10-31',status:'unbilled'});
});
test('a whole period uses the lease price; fees for 3 months; usage behind; late fee and discount lines',async()=>{
 const {bill,defineFee,db}=setup();const {feeId}=await defineFee();
 const q=(await bill({action:'quote',...period({serviceFeeIds:[feeId],readings:[{roomId:'r',kind:'electricity',readingId:'x'}],lines:[{kind:'late',label:'Trễ hạn',amountMinor:50000},{kind:'discount',label:'Giảm 10%',percent:10}]})})).record;
 assert.deepEqual(q.lines.map(l=>[l.type,l.amountMinor]),[['rent',15000000],['service',120000],['utility',87500],['manual',50000],['manual',-1500000]]);
 assert.equal(q.lines[0].basis,'period');assert.equal(q.totalMinor,13757500);
 const {invoiceId}=await bill({action:'create',...period({serviceFeeIds:[feeId],readings:[{roomId:'r',kind:'electricity',readingId:'x'}],lines:[{kind:'late',label:'Trễ hạn',amountMinor:50000},{kind:'discount',label:'Giảm 10%',percent:10}]}),operationId:'p1',quoteRevision:q.quoteRevision});
 const saved=db.store.get('payments/'+invoiceId);
 assert.equal(saved.invoiceKind,'period');assert.equal(saved.type,'period');assert.equal(saved.amountMinor,13757500);assert.equal(saved.roomId,'r');
 assert.equal(db.store.get(readingPath('x')).invoiceId,invoiceId);
 assert.equal(db.store.get(`serviceFees/${feesId('o','b')}`).fees[0].billedThrough,'2027-01-02');
 // Nothing is offered again for the same period.
 const p=(await bill({action:'periodPreview',tenantId:'t'})).record;
 assert.equal(p.suggestion.startDate,'2027-01-02');assert.deepEqual(p.readings,[]);
 // The form can say why there is no electricity line: it is already on an invoice.
 assert.deepEqual(p.lastElectricity,{date:'2026-10-31',status:'invoiced'});
});
test('rent, fees and readings cannot be billed twice across period, rent, fee and utility invoices',async()=>{
 const {bill,defineFee}=setup();const {feeId}=await defineFee();
 await create(bill,{serviceFeeIds:[feeId]});
 await assert.rejects(create(bill,{},'p2'),e=>e.message==='invoice_period_exists');
 await assert.rejects(create(bill,{includeRent:false,serviceFeeIds:[feeId]},'p3'),e=>e.message==='invoice_period_exists');
 // Refused already at review (quote), before anyone presses Create.
 await assert.rejects(bill({action:'quote',kind:'tenantRent',tenantId:'t',startDate:'2026-11-01',endDate:'2026-12-01',dueDate:'2026-11-05',feesMinor:fees0,reason:'Tháng 11'}),e=>e.message==='invoice_period_exists');
 await assert.rejects(bill({action:'quote',kind:'service',tenantId:'t',roomId:'r',feeId,quantityMilli:null,startDate:'2026-11-01',endDate:'2026-12-01',dueDate:'2026-11-05',feesMinor:fees0,reason:'Rác'}),e=>e.message==='invoice_period_exists');
 // The preview says how far the fee is billed, so the form can leave it unticked.
 const preview=(await bill({action:'periodPreview',tenantId:'t'})).record;
 assert.equal(preview.fees.find(f=>f.id===feeId).billedUntil,preview.suggestion.startDate);
 // A period invoice with only usage is fine next to the rent invoice.
 await create(bill,{includeRent:false,readings:[{roomId:'r',kind:'electricity',readingId:'x'}]},'p4');
 await assert.rejects(create(bill,{includeRent:false,readings:[{roomId:'r',kind:'electricity',readingId:'x'}]},'p5'),e=>e.message==='utility_already_billed');
});
test('a partial period is prorated by days; readings outside the lease are refused',async()=>{
 const {bill}=setup();
 const q=(await bill({action:'quote',...period({endDate:'2026-11-02'})})).record;
 assert.equal(q.lines[0].basis,'months');assert.equal(q.lines[0].amountMinor,5000000);
 assert.equal((await bill({action:'quote',...period({endDate:'2026-10-17'})})).record.lines[0].amountMinor,2419355);// 15 of 31 days
 await assert.rejects(bill({action:'quote',...period({readings:[{roomId:'r',kind:'electricity',readingId:'old'}]})}),e=>e.message==='utility_tenant_boundary_required');
});
test('a rent change inside the period is prorated, not the old period price',()=>{
 const tenant={currency:'VND',monthlyRentMinor:5000000,paymentPeriodMonths:3,periodRentMinor:15000000,rentSchedule:[{effectiveDate:'2026-12-02',amountMinor:6000000}]};
 const r=periodRent({tenant,startDate:'2026-10-02',endDate:'2027-01-02',intervals:[{startDate:'2026-10-02',endDate:null}],timeZone:'Asia/Ho_Chi_Minh'});
 assert.equal(r.basis,'days');assert.ok(r.amountMinor>15000000&&r.amountMinor<16100000);
});
test('void releases readings so they can be billed again; paid invoices must be refunded first',async()=>{
 const {bill,db}=setup();
 const {invoiceId}=await create(bill,{readings:[{roomId:'r',kind:'electricity',readingId:'x'}]});
 db.store.get('payments/'+invoiceId).paidAmount=1000;
 await assert.rejects(bill({action:'void',invoiceId,revision:'0:0',operationId:'v1',reason:'Sai'}),e=>e.message==='invoice_refund_first');
 db.store.get('payments/'+invoiceId).paidAmount=0;
 await bill({action:'void',invoiceId,revision:'0:0',operationId:'v1',reason:'Sai'});
 assert.equal(db.store.get(readingPath('x')).invoiceId,null);
 await create(bill,{readings:[{roomId:'r',kind:'electricity',readingId:'x'}]},'p2');
});
test('manual lines need price authority; collect-payment staff can still bill plain periods',async()=>{
 const {bill,db}=setup();Ts.clock=Date.parse('2026-10-01T05:00:00Z');
 db.store.set('memberships/staff_o',{...owner,ownerId:'staff',role:'custom_staff',roleGrants:{readFinancialReports:'all',collectPayments:'all'}});
 await assert.rejects(bill({action:'quote',...period({lines:[{kind:'discount',label:'Giảm',amountMinor:100000}]})},'staff'),e=>e.message==='period_lines_need_price_authority');
 assert.equal((await bill({action:'quote',...period()},'staff')).record.totalMinor,15000000);
 await assert.rejects(bill({action:'periodPreview',tenantId:'t'},'outsider'),e=>e.code==='permission-denied');
});
test('invalid lines and totals are refused',async()=>{
 const {bill}=setup();
 for(const lines of [[{kind:'late',label:'x',amountMinor:-1}],[{kind:'discount',label:'x',percent:0}],[{kind:'other',label:'',amountMinor:1}],[{kind:'bonus',label:'x',amountMinor:1}],[{kind:'discount',label:'x',amountMinor:1,percent:5}]])
  await assert.rejects(bill({action:'quote',...period({lines})}),e=>e.code==='invalid-argument');
 await assert.rejects(bill({action:'quote',...period({includeRent:false})}),e=>e.message==='period_empty');
 await assert.rejects(bill({action:'quote',...period({includeRent:false,lines:[{kind:'discount',label:'Giảm',percent:10}]})}),e=>e.message==='period_discount_needs_rent');
 await assert.rejects(bill({action:'quote',...period({lines:[{kind:'discount',label:'Giảm hết',amountMinor:15000000}]})}),e=>e.message==='period_total_not_positive');
});
test('overdue shows on unpaid invoices after the due date',async()=>{
 const {bill}=setup();await create(bill,{dueDate:'2026-10-02'});
 Ts.clock=Date.parse('2026-10-10T05:00:00Z');
 const list=(await bill({action:'list'})).records;assert.equal(list[0].overdue,true);assert.equal(list[0].roomId,'r');
});
