const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createServiceFeesHandler}=require('../service_fees');
const {createInvoiceHandler}=require('../invoices');
const {feesId,roomFeesId}=require('../service_fee_invoice');
const at=d=>Ts.fromMillis(Date.parse(d+'T00:00:00+07:00'));
const owner={ownerId:'owner',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]};
const fees0={internetFee:0,cableTVFee:0,hotWaterFee:0,lateFee:0,taxAmount:0};
function setup(){
 Ts.clock=Date.parse('2026-10-02T05:00:00Z');
 const db=fakeDb({'organizations/o':{accessVersion:2},'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},'rooms/r':{organizationId:'o',buildingId:'b',roomNumber:'101'},
  'memberships/owner_o':owner,
  'tenants/t':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,fullName:'Le Van Chinh',currency:'VND',moveInDate:at('2026-08-01')},
  'tenants/m':{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:false,mainTenantId:'t',fullName:'Pham Thi Dung',currency:'VND',moveInDate:at('2026-09-21')}});
 const fees=createServiceFeesHandler({db,Timestamp:Ts,HttpsError:CodeError}),invoices=createInvoiceHandler({db,Timestamp:Ts,HttpsError:CodeError});let n=0;
 const call=(data,uid='owner')=>fees({auth:{uid},data:{organizationId:'o',buildingId:'b',...(data.action!=='read'?{operationId:'op'+(++n),reason:'Bảng giá'}:{}),...data}});
 const bill=(data,uid='owner')=>invoices({auth:{uid},data:{organizationId:'o',buildingId:'b',...data}});
 return {db,call,bill};
}
const version=o=>({effectiveDate:'2026-09-01',active:true,rateMinor:100000,rule:{mode:'days'},includedPeople:0,roundingMinor:0,...o});
const define=(call,o={},uid='owner')=>call({action:'define',revision:0,feeId:null,name:'Rác',basis:'person',unitLabel:'',version:version(),...o},uid);
test('new service price version retains selected currency without rewriting old versions',async()=>{
 const {db,call,bill}=setup();const first=await define(call);
 db.store.get('organizations/o').displayCurrency='USD';
 await define(call,{revision:1,feeId:first.feeId,inputCurrency:'USD',version:version({effectiveDate:'2026-10-01',rateMinor:400})});
 const doc=db.store.get(`serviceFees/${feesId('o','b')}`);
 assert.equal(doc.fees[0].versions[0].rateMinor,100000);
 assert.equal(doc.fees[0].versions[1].currency,'USD');
 const q=await bill({action:'quote',...invoice({feeId:first.feeId,startDate:'2026-10-01',endDate:'2026-11-01'}),inputCurrency:'USD'});
 assert.equal(q.record.currency,'USD');assert.equal(q.record.totalMinor,800);
});
const invoice=o=>({kind:'service',tenantId:'t',roomId:'r',quantityMilli:null,startDate:'2026-09-01',endDate:'2026-10-01',dueDate:'2026-10-05',feesMinor:fees0,reason:'Phí tháng 9',...o});
async function create(bill,o={},operationId='inv1'){const q=await bill({action:'quote',...invoice(o)});return bill({action:'create',...invoice(o),operationId,quoteRevision:q.record.quoteRevision});}

test('define, read and rename a fee; the room view shows what applies today',async()=>{
 const {call}=setup();const {feeId}=await define(call);
 await call({action:'rename',revision:1,feeId,name:'Phí rác',unitLabel:''});
 const view=(await call({action:'read',roomId:'r'})).record;
 assert.equal(view.fees[0].name,'Phí rác');assert.equal(view.fees[0].current.rateMinor,100000);assert.equal(view.roomNumber,'101');
 assert.deepEqual(view.tenants.map(t=>t.id),['t']);assert.equal(view.canPrice,true);assert.equal(view.today,'2026-10-02');
});
test('lost responses replay exactly; changed payloads and stale revisions fail; names stay unique',async()=>{
 const {call}=setup();const data={action:'define',operationId:'same',revision:0,feeId:null,name:'Rác',basis:'person',unitLabel:'',version:version()};
 assert.deepEqual(await call(data),await call(data));
 await assert.rejects(call({...data,name:'Nước'}),e=>e.code==='failed-precondition');
 await assert.rejects(define(call,{name:'Wifi'}),e=>e.message==='service_changed');
 await assert.rejects(define(call,{revision:1,name:' rác '}),e=>e.message==='service_fee_name_exists');
 assert.equal((await call({action:'read'})).record.fees.length,1);
});
test('the basis is fixed; a new dated version changes the price from that date',async()=>{
 const {call}=setup();const {feeId}=await define(call);
 await assert.rejects(call({action:'define',revision:1,feeId,name:'Rác',basis:'room',unitLabel:'',version:version({effectiveDate:'2026-10-01'})}),e=>e.message==='service_basis_fixed');
 await call({action:'define',revision:1,feeId,name:'Rác',basis:'person',unitLabel:'',version:version({effectiveDate:'2026-10-01',rateMinor:120000})});
 await assert.rejects(call({action:'define',revision:2,feeId,name:'Rác',basis:'person',unitLabel:'',version:version({effectiveDate:'2026-10-01'})}),e=>e.message==='service_fee_date_exists');
 assert.equal((await call({action:'read'})).record.fees[0].current.rateMinor,120000);
});
test('permissions: lease or finance staff may read; only price authority may change; outsiders, inactive and closed are refused',async()=>{
 const {call,db}=setup();await define(call);
 db.store.set('memberships/staff_o',{...owner,ownerId:'staff',role:'custom_staff',roleGrants:{manageLease:'all'}});
 assert.equal((await call({action:'read'},'staff')).record.canPrice,false);
 await assert.rejects(define(call,{revision:1,name:'Wifi'},'staff'),e=>e.code==='permission-denied');
 await assert.rejects(call({action:'read'},'outsider'),e=>e.code==='permission-denied');
 db.store.set('memberships/none_o',{...owner,ownerId:'none',role:'custom_staff',roleGrants:{readBookings:'all'}});
 await assert.rejects(call({action:'read'},'none'),e=>e.code==='permission-denied');
 for(const status of ['suspended','revoked']){const s=setup();s.db.store.get('memberships/owner_o').status=status;await assert.rejects(s.call({action:'read'}),e=>e.code==='permission-denied');}
 for(const patch of [{closedAt:Ts.now()},{accessVersion:1}]){const s=setup();Object.assign(s.db.store.get('organizations/o'),patch);await assert.rejects(s.call({action:'read'}),e=>e.code==='permission-denied');}
 const s=setup();s.db.store.get('rooms/r').organizationId='foreign';await assert.rejects(s.call({action:'read',roomId:'r'}),e=>e.code==='not-found');
 const s2=setup();await assert.rejects(s2.call({action:'read',buildingId:'missing'}),e=>e.code==='not-found');
});
test('invalid input is refused before any write',async()=>{
 const {call,db}=setup();
 for(const o of [{name:''},{name:'x'.repeat(81)},{basis:'monthly'},{version:version({rateMinor:-1})},{version:{effectiveDate:'2026-09-01',active:false}},{unitLabel:'x'.repeat(21)},{extra:1}])
  await assert.rejects(define(call,o));
 await assert.rejects(call({action:'define',revision:0,feeId:null,name:'Rác',basis:'person',unitLabel:'',version:version(),reason:' '}),e=>e.code==='invalid-argument');
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('serviceFees/')).length,0);
});
test('a roommate who moved in on 21 September pays 10/30; the invoice freezes the lines and terms',async()=>{
 const {call,bill,db}=setup();const {feeId}=await define(call);
 const quote=(await bill({action:'quote',...invoice({feeId})})).record;
 assert.equal(quote.amountMinor,133333);assert.deepEqual(quote.lines.map(l=>[l.name,l.days,l.periodDays,l.amountMinor]),[['Le Van Chinh',30,30,100000],['Pham Thi Dung',10,30,33333]]);
 const {invoiceId}=await create(bill,{feeId});const saved=db.store.get('payments/'+invoiceId);
 assert.equal(saved.type,'service');assert.equal(saved.invoiceKind,'service');assert.equal(saved.roomId,'r');assert.equal(saved.calculation.feeId,feeId);assert.equal(saved.calculation.feeName,'Rác');assert.equal(saved.calculation.terms.rateMinor,100000);
 assert.equal(db.store.get(`serviceFees/${feesId('o','b')}`).fees[0].billedThrough,'2026-10-01');
 assert.equal(db.store.get(`serviceFeeRooms/${roomFeesId('o','r')}`).billedThrough[feeId],'2026-10-01');
});
test('the same fee, room and lease cannot be billed twice for overlapping days; a retry replays',async()=>{
 const {call,bill}=setup();const {feeId}=await define(call);
 // A retry resends the same create (the app never re-quotes a pending save).
 const q=await bill({action:'quote',...invoice({feeId})}),args={action:'create',...invoice({feeId}),operationId:'inv1',quoteRevision:q.record.quoteRevision};
 const first=await bill(args);assert.deepEqual(await bill(args),first);
 await assert.rejects(create(bill,{feeId},'inv2'),e=>e.message==='invoice_period_exists');
 await create(bill,{feeId,startDate:'2026-10-01',endDate:'2026-10-02',dueDate:'2026-10-05'},'inv3');
});
test('after billing, prices and room rates cannot be backdated into the billed period',async()=>{
 const {call,bill}=setup();const {feeId}=await define(call);await create(bill,{feeId});
 const rev=(await call({action:'read'})).record.revision;
 await assert.rejects(call({action:'define',revision:rev,feeId,name:'Rác',basis:'person',unitLabel:'',version:version({effectiveDate:'2026-09-15'})}),e=>e.message==='service_fee_past_billed');
 await call({action:'define',revision:rev,feeId,name:'Rác',basis:'person',unitLabel:'',version:version({effectiveDate:'2026-10-01',rateMinor:120000})});
 const roomRev=(await call({action:'read',roomId:'r'})).record.roomRevision;
 await assert.rejects(call({action:'roomRate',revision:roomRev,roomId:'r',feeId,override:{effectiveDate:'2026-09-20',mode:'off'}}),e=>e.message==='service_fee_past_billed');
});
test('room overrides: a lower rate, then off; a price change inside the period needs a boundary',async()=>{
 const {call,bill}=setup();const {feeId}=await define(call);
 await call({action:'roomRate',revision:0,roomId:'r',feeId,override:{effectiveDate:'2026-09-01',mode:'rate',rateMinor:60000}});
 assert.equal((await bill({action:'quote',...invoice({feeId})})).record.lines[0].amountMinor,60000);
 await call({action:'roomRate',revision:1,roomId:'r',feeId,override:{effectiveDate:'2026-09-15',mode:'off'}});
 await assert.rejects(bill({action:'quote',...invoice({feeId})}),e=>e.message==='service_fee_boundary_required');
 await assert.rejects(bill({action:'quote',...invoice({feeId,startDate:'2026-09-15'})}),e=>e.message==='service_fee_not_in_force');
 assert.equal((await bill({action:'quote',...invoice({feeId,endDate:'2026-09-15'})})).record.lines[0].amountMinor,28000);// 14 of 30 days of a 60.000/month room price
 await assert.rejects(call({action:'roomRate',revision:1,roomId:'r',feeId,override:{effectiveDate:'2026-10-01',mode:'inherit'}}),e=>e.message==='service_changed');
});
test('quantity extras: one service date, entered quantity, several allowed in a period',async()=>{
 const {call,bill}=setup();const {feeId}=await define(call,{name:'Giặt',basis:'quantity',unitLabel:'kg',version:version({rule:null,rateMinor:15000})});
 const q=(await bill({action:'quote',...invoice({feeId,quantityMilli:2500,startDate:'2026-09-05',endDate:'2026-09-06'})})).record;assert.equal(q.amountMinor,37500);
 await create(bill,{feeId,quantityMilli:2500,startDate:'2026-09-05',endDate:'2026-09-06'});
 await create(bill,{feeId,quantityMilli:1000,startDate:'2026-09-05',endDate:'2026-09-06'},'inv2');
 await assert.rejects(bill({action:'quote',...invoice({feeId,quantityMilli:2500})}),e=>e.message==='service_invalid_period');
 await assert.rejects(bill({action:'quote',...invoice({feeId,quantityMilli:null,startDate:'2026-09-05',endDate:'2026-09-06'})}),e=>e.message==='service_invalid_quantity');
 const {feeId:per}=await define(call,{revision:(await call({action:'read'})).record.revision,name:'Rác'});
 await assert.rejects(bill({action:'quote',...invoice({feeId:per,quantityMilli:1000})}),e=>e.message==='service_invalid_quantity');
});
test('billing refuses another room, a lease outside the period, an unknown fee and a different currency',async()=>{
 const {call,bill,db}=setup();const {feeId}=await define(call);
 await assert.rejects(bill({action:'quote',...invoice({feeId:'fee_missing'})}),e=>e.message==='service_fee_not_found');
 await assert.rejects(bill({action:'quote',...invoice({feeId,startDate:'2026-06-01',endDate:'2026-07-01'})}),e=>e.message==='service_fee_not_in_force');
 db.store.set('rooms/r2',{organizationId:'o',buildingId:'b',roomNumber:'102'});
 await assert.rejects(bill({action:'quote',...invoice({feeId,roomId:'r2'})}),e=>e.message==='service_tenant_not_in_room');
 db.store.get('tenants/t').currency='USD';
 await assert.rejects(bill({action:'quote',...invoice({feeId})}),e=>e.message==='service_currency_mismatch');
});

test('billing a service in the lease currency preserves source terms and pins the rate on the invoice',async()=>{
 const {call,bill,db}=setup();const {feeId}=await define(call);
 const {normalizeRates}=require('../reference_rates');
 const rates=normalizeRates([{base:'USD',quote:'VND',rate:25000,date:'2026-10-08'}]);
 db.store.set(`referenceExchangeRates/${rates.id}`,rates);
 db.store.get('tenants/t').currency='USD';
 const payload={...invoice({feeId}),ratesId:rates.id};
 const q=(await bill({action:'quote',...payload})).record;
 assert.equal(q.currency,'USD');assert.equal(q.exchangeRateSnapshotId,rates.id);
 assert.equal(q.sourceCalculation.currency,'VND');
 assert.equal(q.amountMinor,q.lines.reduce((sum,line)=>sum+line.amountMinor,0));
 assert.equal(q.terms.rateMinor,400);
 assert.equal(q.sourceCalculation.terms.rateMinor,100000);
 const command={action:'create',...payload,operationId:'fxinvoice',quoteRevision:q.quoteRevision};
 const result=await bill(command),stored=db.store.get('payments/'+result.invoiceId);
 assert.equal(stored.calculation.exchangeRateSnapshotId,rates.id);
 assert.equal(stored.currency,'USD');
 assert.deepEqual(await bill(command),result);
 await assert.rejects(bill({...command,ratesId:'f'.repeat(64)}),e=>e.code==='failed-precondition');
});
test('a past room is billed from the move history; staff need collect-payment authority to bill',async()=>{
 const {call,bill,db}=setup();const {feeId}=await define(call);
 // Le Van Chinh moved from r to r2 on 16 September; the roommate is not linked to r anymore.
 Object.assign(db.store.get('tenants/t'),{roomId:'r2',occupancyStartDate:at('2026-09-16')});db.store.delete('tenants/m');
 db.store.set('rooms/r2',{organizationId:'o',buildingId:'b',roomNumber:'102'});
 db.store.set('leaseOccupancy/h1',{organizationId:'o',tenantId:'t',buildingId:'b',roomId:'r',start:at('2026-08-01'),end:at('2026-09-16'),isMainTenant:true});
 const q=(await bill({action:'quote',...invoice({feeId})})).record;assert.deepEqual(q.lines.map(l=>[l.days,l.amountMinor]),[[15,50000]]);
 db.store.set('memberships/staff_o',{...owner,ownerId:'staff',role:'custom_staff',roleGrants:{readFinancialReports:'all'}});
 await assert.rejects(bill({action:'quote',...invoice({feeId})},'staff'),e=>e.code==='permission-denied');
});
test('voiding a service invoice frees the period again but keeps the billed marker',async()=>{
 const {call,bill,db}=setup();const {feeId}=await define(call);const {invoiceId}=await create(bill,{feeId});
 await bill({action:'void',invoiceId,revision:'0:0',operationId:'void1',reason:'Sai'});
 await create(bill,{feeId},'inv2');
 assert.equal(db.store.get(`serviceFees/${feesId('o','b')}`).fees[0].billedThrough,'2026-10-01');
});
