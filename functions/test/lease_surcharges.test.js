// 2026-10-04: long-stay lease surcharges (phụ thu), electricity price typed with
// the lease, and the stay status shown on the tenant page.
const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createTenantLeasesHandler}=require('../tenant_leases');
const {createInvoiceHandler}=require('../invoices');
const {createTenantContactsHandler}=require('../tenant_contacts');
const {meterId}=require('../utility_invoice');
const {templates}=require('../team_access');
const at=d=>Ts.fromMillis(Date.parse(d+'T00:00:00+07:00'));
const member=(uid,role,extra={})=>({ownerId:uid,organizationId:'o',accessVersion:2,status:'active',role,buildingScope:'all',buildingIds:[],...extra});
const fees0={internetFee:0,cableTVFee:0,hotWaterFee:0,lateFee:0,taxAmount:0};
const meterPath=`utilityMeters/${meterId('o','r','electricity')}`;

function setup(extra={}){
 Ts.clock=Date.parse('2026-10-03T05:00:00Z');
 const db=fakeDb({'organizations/o':{accessVersion:2},'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},'rooms/r':{organizationId:'o',buildingId:'b',roomNumber:'101'},
  'memberships/owner_o':member('owner','owner'),'memberships/acc_o':member('acc','accountant'),
  'memberships/lease_o':member('lease','leaser',{roleGrants:Object.fromEntries(Object.entries(templates.manager.grants).filter(([k])=>k!=='overridePrices'))}),
  // Le Van Chinh lives in 101 with one roommate; parking per room each period, cleaning per person once.
  'tenants/t':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,status:'active',fullName:'Le Van Chinh',currency:'VND',moveInDate:at('2026-10-02'),moveInLocalDate:'2026-10-02',monthlyRentMinor:5000000,monthlyRent:5000000,paymentPeriodMonths:1,depositMinor:5000000,
   surcharges:[{id:'park',label:'Gửi xe',amountMinor:100000,basis:'room',frequency:'period'},{id:'clean',label:'Vệ sinh',amountMinor:50000,basis:'person',frequency:'once'}]},
  'tenants/m':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:false,mainTenantId:'t',status:'active',fullName:'Pham Thi Dung',currency:'VND',moveInDate:at('2026-10-02')},
  ...extra});
 const lease=(data,uid='owner')=>createTenantLeasesHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'o',buildingId:'b',...data}});
 const bill=(data,uid='owner')=>createInvoiceHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'o',buildingId:'b',...data}});
 const contacts=(data,uid='owner')=>createTenantContactsHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:{uid},data:{organizationId:'o',buildingId:'b',...data}});
 return {db,lease,bill,contacts};
}
const periodOf=o=>({kind:'period',tenantId:'t',startDate:'2026-10-02',endDate:'2026-11-02',dueDate:'2026-10-05',feesMinor:fees0,reason:'Kỳ 1',includeRent:false,serviceFeeIds:[],readings:[],lines:[],...o});
const period=periodOf;
async function create(bill,o={},operationId='p1',uid='owner'){const q=await bill({action:'quote',...period(o)},uid);return bill({action:'create',...period(o),operationId,quoteRevision:q.record.quoteRevision},uid);}

test('a lease is created with surcharges and an electricity price for its room meter',async()=>{
 const {db,lease}=setup({'rooms/r2':{organizationId:'o',buildingId:'b',roomNumber:'102'}});
 const p=(await lease({action:'prepare',roomId:'r2'})).record;
 const base={action:'create',roomId:'r2',operationId:'L1',roomRevision:p.roomRevision,timeZone:p.timeZone,currency:p.currency,fullName:'Tran B',phoneNumber:'',moveInDate:'2026-10-10',contractEndDate:'2027-10-01',rentMinor:4000000,backdateReason:''};
 for(const bad of [[{label:'',amountMinor:1,basis:'room',frequency:'once'}],[{label:'X',amountMinor:0,basis:'room',frequency:'once'}],[{label:'X',amountMinor:1,basis:'bed',frequency:'once'}],[{id:'a',label:'X',amountMinor:1,basis:'room',frequency:'once'}]])
  await assert.rejects(lease({...base,surcharges:bad}),e=>e.code==='invalid-argument');
 // Someone who may sign leases but not set prices cannot set the electricity price.
 await assert.rejects(lease({...base,operationId:'L0',electricityPriceMinor:3500},'lease'),e=>e.message==='lease_price_authority');
 const r=await lease({...base,surcharges:[{label:'Gửi xe',amountMinor:100000,basis:'room',frequency:'period'}],electricityPriceMinor:3500});
 const t=db.store.get(`tenants/${r.tenantId}`);
 assert.equal(t.surcharges.length,1);assert.match(t.surcharges[0].id,/^sc_/);assert.equal(t.surcharges[0].frequency,'period');
 const meter=db.store.get(`utilityMeters/${meterId('o','r2','electricity')}`);
 assert.deepEqual(meter.tariffHistory,[{effectiveDate:'2026-10-10',tariff:{currency:'VND',bands:[{throughMilli:null,priceMinor:3500}]}}]);
 assert.equal(meter.revision,1);
});

test('the electricity price starts at the last reading when that is after the move-in day',async()=>{
 const {db,lease}=setup({'rooms/r2':{organizationId:'o',buildingId:'b',roomNumber:'102'},[`utilityMeters/${meterId('o','r2','electricity')}`]:{organizationId:'o',buildingId:'b',roomId:'r2',kind:'electricity',revision:4,lastDate:'2026-10-03',lastReadingMilli:1000000,tariffHistory:[{effectiveDate:'2026-10-03',tariff:{currency:'VND',bands:[{throughMilli:null,priceMinor:3000}]}}]}});
 const p=(await lease({action:'prepare',roomId:'r2'})).record;
 await lease({action:'create',roomId:'r2',operationId:'L1',roomRevision:p.roomRevision,timeZone:p.timeZone,currency:p.currency,fullName:'Tran B',phoneNumber:'',moveInDate:'2026-10-03',contractEndDate:'2027-10-01',rentMinor:4000000,backdateReason:'',electricityPriceMinor:3800});
 const meter=db.store.get(`utilityMeters/${meterId('o','r2','electricity')}`);
 assert.deepEqual(meter.tariffHistory.map(x=>[x.effectiveDate,x.tariff.bands[0].priceMinor]),[['2026-10-03',3800]],'the same-day price is replaced');
 assert.equal(meter.revision,5);assert.equal(meter.lastReadingMilli,1000000);
});

test('surcharges can be edited later; existing lines keep their id',async()=>{
 const {db,lease}=setup();
 const r=await lease({action:'surcharges',tenantId:'t',surcharges:[{id:'park',label:'Gửi xe máy',amountMinor:120000,basis:'room',frequency:'period'},{label:'Internet',amountMinor:80000,basis:'room',frequency:'period'}]});
 assert.deepEqual(r.surcharges.map(s=>s.id.startsWith('sc_')?'new':s.id),['park','new']);
 assert.equal(db.store.get('tenants/t').surcharges[0].amountMinor,120000);
 await assert.rejects(lease({action:'surcharges',tenantId:'m',surcharges:[]}),e=>e.code==='not-found');
 await assert.rejects(lease({action:'surcharges',tenantId:'t',surcharges:[]},'acc'),e=>e.code==='permission-denied');
});

test('a period invoice bills surcharges per room or per person; a one-time line only once',async()=>{
 const {db,bill}=setup();
 const p=(await bill({action:'periodPreview',tenantId:'t'})).record;
 assert.deepEqual(p.surcharges.map(s=>[s.id,s.count,s.billed]),[['park',1,false],['clean',2,false]]);
 const q=(await bill({action:'quote',...period({surcharges:[{id:'park',amountMinor:100000},{id:'clean',amountMinor:50000}]})})).record;
 assert.deepEqual(q.lines.map(l=>[l.surchargeId,l.count,l.amountMinor]),[['park',1,100000],['clean',2,100000]]);
 assert.equal(q.amountMinor,200000);
 const first=await create(bill,{surcharges:[{id:'park',amountMinor:100000},{id:'clean',amountMinor:50000}]});
 assert.equal((await bill({action:'periodPreview',tenantId:'t'})).record.surcharges[1].billed,true);
 // Next period: parking again is fine, cleaning again is refused.
 const next={startDate:'2026-11-02',endDate:'2026-12-02',reason:'Kỳ 2'};
 await assert.rejects(bill({action:'quote',...period({...next,surcharges:[{id:'clean',amountMinor:50000}]})}),e=>e.message==='period_surcharge_billed');
 await create(bill,{...next,surcharges:[{id:'park',amountMinor:100000}]},'p2');
 // The same period twice is refused for a per-period line.
 await assert.rejects(bill({action:'quote',...period({includeRent:false,surcharges:[{id:'park',amountMinor:100000}]})}),e=>e.message==='period_surcharge_billed');
 // Voiding the first invoice frees the one-time line again.
 const inv=(await bill({action:'read',invoiceId:first.invoiceId})).record;
 await bill({action:'void',invoiceId:first.invoiceId,operationId:'v1',revision:inv.revision,reason:'Sai'});
 assert.equal((await bill({action:'periodPreview',tenantId:'t'})).record.surcharges[1].billed,false);
 await assert.rejects(bill({action:'quote',...period({surcharges:[{id:'nope',amountMinor:1}]})}),e=>e.message==='period_surcharge_unknown');
 assert.ok(db.store.size>0);
});

test('changing a surcharge amount for one period needs price authority',async()=>{
 const {bill}=setup();const period=o=>periodOf({startDate:'2026-10-03',endDate:'2026-11-03',...o});
 await assert.rejects(bill({action:'quote',...period({surcharges:[{id:'park',amountMinor:150000}]})},'acc'),e=>e.message==='period_lines_need_price_authority');
 const q=(await bill({action:'quote',...period({surcharges:[{id:'park',amountMinor:100000}]})},'acc')).record;
 assert.equal(q.amountMinor,100000);
 const owner=(await bill({action:'quote',...period({surcharges:[{id:'park',amountMinor:150000}]})})).record;
 assert.equal(owner.amountMinor,150000);
});

test('the tenant page shows the stay status and surcharges',async()=>{
 const {contacts,db}=setup({'tenants/f':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,status:'active',fullName:'Future',currency:'VND',moveInDate:at('2026-10-20'),moveInLocalDate:'2026-10-20',depositMinor:1000000},
  'tenants/g':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,status:'active',fullName:'Later',currency:'VND',moveInDate:at('2026-10-20'),moveInLocalDate:'2026-10-20'},
  'tenants/h':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,status:'moveOut',fullName:'Gone',currency:'VND',moveInDate:at('2026-01-01'),moveInLocalDate:'2026-01-01',moveOutDate:at('2026-09-01'),contractEndLocalDate:'2026-08-31'},
  'tenants/e':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,status:'active',fullName:'Ended',currency:'VND',moveInDate:at('2026-01-01'),moveInLocalDate:'2026-01-01',contractEndLocalDate:'2026-09-30'}});
 const status=async id=>(await contacts({action:'read',tenantId:id})).record;
 assert.equal((await status('t')).stayStatus,'staying');assert.equal((await status('t')).surcharges.length,2);
 assert.equal((await status('f')).stayStatus,'deposited');
 assert.equal((await status('g')).stayStatus,'notCheckedIn');
 const gone=await status('h');assert.equal(gone.stayStatus,'checkedOut');assert.equal(gone.moveOutLocalDate,'2026-09-01');
 assert.equal((await status('e')).contractEnded,true);assert.equal((await status('t')).contractEnded,false);
 // 2026-10-04: the people living with a main tenant are listed on its page.
 assert.deepEqual((await status('t')).roommates,[{id:'m',fullName:'Pham Thi Dung',moveInLocalDate:''}]);
 assert.deepEqual((await status('m')).roommates,[]);
 assert.ok(db);
});

// 2026-10-04 (Tom): water (tiền nước) is per person per month; a 3-month period
// charges 3 months, a part month by its days. The contract end date is required.
test('water per person per month; the end date is required',async()=>{
 const {db,lease,bill}=setup({'rooms/r2':{organizationId:'o',buildingId:'b',roomNumber:'102'}});
 const p=(await lease({action:'prepare',roomId:'r2'})).record;
 const base={action:'create',roomId:'r2',operationId:'W1',roomRevision:p.roomRevision,timeZone:p.timeZone,currency:p.currency,fullName:'Tran B',phoneNumber:'',moveInDate:'2026-10-10',contractEndDate:'2027-10-10',rentMinor:4000000,backdateReason:''};
 for(const end of [null,'','2026-10-10','2026-10-01'])
  await assert.rejects(lease({...base,contractEndDate:end}),e=>e.code==='invalid-argument',String(end));
 const water={label:'Tiền nước',amountMinor:100000,basis:'person',frequency:'month',kind:'water'};
 for(const bad of [[{...water,frequency:'period'}],[{...water,kind:'gas'}],[water,water]])
  await assert.rejects(lease({...base,surcharges:bad}),e=>e.code==='invalid-argument');
 const r=await lease({...base,surcharges:[water]});
 assert.equal(db.store.get(`tenants/${r.tenantId}`).surcharges[0].kind,'water');
 // Editing the list keeps the kind.
 const id=db.store.get(`tenants/${r.tenantId}`).surcharges[0].id;
 await lease({action:'surcharges',tenantId:r.tenantId,surcharges:[{...water,id,amountMinor:120000}]});
 assert.deepEqual(db.store.get(`tenants/${r.tenantId}`).surcharges.map(s=>[s.id,s.kind,s.amountMinor]),[[id,'water',120000]]);
 // Le Van Chinh (2 people) on a 3-month period: 100,000 × 2 × 3.
 const t=db.store.get('tenants/t');t.paymentPeriodMonths=3;t.surcharges=[...t.surcharges,{id:'w',...water}];
 const pre=(await bill({action:'periodPreview',tenantId:'t'})).record;
 assert.deepEqual(pre.surcharges.find(s=>s.id==='w'),{id:'w',label:'Tiền nước',amountMinor:100000,basis:'person',frequency:'month',kind:'water',count:2,billed:false});
 const q=(await bill({action:'quote',...period({endDate:'2027-01-02',surcharges:[{id:'w',amountMinor:100000}]})})).record;
 assert.deepEqual(q.lines.map(l=>[l.kind,l.count,l.monthsFraction,l.amountMinor]),[['water',2,[3,1],600000]]);
 // Half of a 30-day month (2026-11-02 → 2026-11-17: 15 of 30 days): 100,000 × 2 × 1/2.
 const half=(await bill({action:'quote',...period({startDate:'2026-11-02',endDate:'2026-11-17',reason:'Nửa tháng',surcharges:[{id:'w',amountMinor:100000}]})})).record;
 assert.equal(half.lines[0].amountMinor,100000);
 // Billed for a period: the same months again are refused.
 await create(bill,{endDate:'2027-01-02',surcharges:[{id:'w',amountMinor:100000}]},'pw');
 await assert.rejects(bill({action:'quote',...period({startDate:'2026-12-02',endDate:'2027-01-02',surcharges:[{id:'w',amountMinor:100000}]})}),e=>e.message==='period_surcharge_billed');
});

// 2026-10-04 (Tom): water can also be one price for the whole room per month.
test('water for the whole room: price × months, whoever lives there',async()=>{
 const {db,bill}=setup();
 const t=db.store.get('tenants/t');t.paymentPeriodMonths=3;
 t.surcharges=[{id:'w',label:'Tiền nước',amountMinor:150000,basis:'room',frequency:'month',kind:'water'}];
 const pre=(await bill({action:'periodPreview',tenantId:'t'})).record;
 assert.equal(pre.surcharges[0].count,1);
 const q=(await bill({action:'quote',...period({endDate:'2027-01-02',surcharges:[{id:'w',amountMinor:150000}]})})).record;
 assert.deepEqual(q.lines.map(l=>[l.basis,l.count,l.monthsFraction,l.amountMinor]),[['room',1,[3,1],450000]]);
});
