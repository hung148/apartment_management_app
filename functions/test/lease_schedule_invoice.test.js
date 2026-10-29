// Bảng thanh toán theo kỳ + Hóa đơn kỳ (PAYMENT_SCHEDULE.md, 2026-10-26).
const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createInvoiceHandler}=require('../invoices');
const {createTenantLeasesHandler}=require('../tenant_leases');
const at=d=>Ts.fromMillis(Date.parse(d+'T00:00:00+07:00'));
const owner={ownerId:'owner',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]};
const fees0={internetFee:0,cableTVFee:0,hotWaterFee:0,lateFee:0,taxAmount:0};
function setup(){
 Ts.clock=Date.parse('2026-10-03T05:00:00Z');
 const db=fakeDb({'organizations/o':{accessVersion:2},'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},'rooms/r':{organizationId:'o',buildingId:'b',roomNumber:'101'},
  'memberships/owner_o':owner,
  'tenants/t':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,status:'active',fullName:'Le Van Chinh',currency:'VND',moveInDate:at('2026-10-02'),moveInLocalDate:'2026-10-02',contractEndLocalDate:'2027-10-02',monthlyRentMinor:5000000,monthlyRent:5000000,paymentPeriodMonths:3,periodRentMinor:15000000,
   surcharges:[{id:'s1',label:'Rác',amountMinor:100000,basis:'room',frequency:'period'}]}});
 const inv=createInvoiceHandler({db,Timestamp:Ts,HttpsError:CodeError}),lease=createTenantLeasesHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const bill=data=>inv({auth:{uid:'owner'},data:{organizationId:'o',buildingId:'b',...data}});
 const sched=data=>lease({auth:{uid:'owner'},data:{organizationId:'o',buildingId:'b',action:'schedule',tenantId:'t',...data}});
 return {db,bill,sched};
}
const period=o=>({kind:'period',tenantId:'t',feesMinor:fees0,reason:'Kỳ',includeRent:true,serviceFeeIds:[],readings:[],lines:[],surcharges:[{id:'s1',amountMinor:100000}],...o});

test('the invoice form suggests the next kỳ and bills its hand-set amount; the kỳ is then locked',async()=>{
 const {db,bill,sched}=setup();
 const s=(await sched({op:'read'})).record;
 assert.deepEqual(s.rows.map(r=>`${r.start}..${r.end}`),['2026-10-02..2027-01-02','2027-01-02..2027-04-02','2027-04-02..2027-07-02','2027-07-02..2027-10-02']);
 assert.equal(s.rows[0].amountMinor,15100000);
 await sched({op:'edit',revision:s.revision,rowId:s.rows[0].id,amountMinor:14100000,due:'2026-10-05',reason:'Giảm kỳ đầu'});
 const p=(await bill({action:'periodPreview',tenantId:'t'})).record;
 assert.deepEqual(p.suggestion,{startDate:'2026-10-02',endDate:'2027-01-02',dueDate:'2026-10-05'});
 assert.equal(p.scheduleRow.amountMinor,14100000);assert.equal(p.scheduleRow.reason,'Giảm kỳ đầu');
 assert.deepEqual(p.scheduleRows.map(r=>[r.startDate,r.rentMinor]),[['2026-10-02',14000000],['2027-01-02',15000000],['2027-04-02',15000000],['2027-07-02',15000000]]);
 const body=period({startDate:'2026-10-02',endDate:'2027-01-02',dueDate:'2026-10-05',lines:[{kind:'late',label:'Phạt',amountMinor:50000}]});
 const q=(await bill({action:'quote',...body})).record;
 assert.equal(q.lines.find(l=>l.type==='rent').amountMinor,14000000);
 assert.equal(q.amountMinor,14000000+100000+50000);
 const {invoiceId}=await bill({action:'create',...body,operationId:'c1',quoteRevision:q.quoteRevision});
 assert.equal(db.store.get(`payments/${invoiceId}`).scheduleRowId,s.rows[0].id);
 const after=(await sched({op:'read'})).record;
 assert.equal(after.rows[0].locked,true);assert.equal(after.rows[0].invoiceId,invoiceId);
 // Tổng tiền = the invoice total, extra lines included.
 assert.equal(after.rows[0].amountMinor,14150000);assert.equal(after.rows[0].leftMinor,14150000);
 const next=(await bill({action:'periodPreview',tenantId:'t'})).record;
 assert.equal(next.suggestion.startDate,'2027-01-02');
});

test('an invoice for other dates is not linked; % discounts follow the kỳ rent',async()=>{
 const {db,bill,sched}=setup();
 const s=(await sched({op:'read'})).record;
 await sched({op:'edit',revision:s.revision,rowId:s.rows[0].id,amountMinor:10100000,reason:'Giảm'});
 const body=period({startDate:'2026-10-02',endDate:'2027-01-02',dueDate:'2026-10-02',lines:[{kind:'discount',label:'10%',percent:10}]});
 const q=(await bill({action:'quote',...body})).record;
 assert.equal(q.lines.find(l=>l.type==='rent').amountMinor,10000000);
 assert.equal(q.lines.find(l=>l.type==='manual').amountMinor,-1000000);
 const odd=period({startDate:'2026-10-02',endDate:'2026-11-02',dueDate:'2026-10-02'});
 const q2=(await bill({action:'quote',...odd})).record;
 const {invoiceId}=await bill({action:'create',...odd,operationId:'c2',quoteRevision:q2.quoteRevision});
 assert.equal(db.store.get(`payments/${invoiceId}`).scheduleRowId,undefined);
});

test('a lease without a contract end keeps the old next-period suggestion',async()=>{
 const {db,bill}=setup();
 db.store.get('tenants/t').contractEndLocalDate=null;
 const p=(await bill({action:'periodPreview',tenantId:'t'})).record;
 assert.deepEqual(p.suggestion,{startDate:'2026-10-02',endDate:'2027-01-02',dueDate:'2026-10-02'});
 assert.equal(p.scheduleRow,null);
});
