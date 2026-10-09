const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb}=require('./fake_firestore');
const {utilityInvoiceSource,meterId}=require('../utility_invoice');
const {createInvoiceHandler}=require('../invoices');
const {Ts,CodeError}=require('./fake_firestore');
const {normalizeRates}=require('../reference_rates');
function setup(){
 const path=`utilityMeters/${meterId('o','r','electricity')}/readings/x`;
 const row={organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity',startDate:'2026-09-01',date:'2026-10-01',calculation:{currency:'VND',amountMinor:35000,usageMilli:10000},tariff:{currency:'VND'},invoiceId:null};
 const db=fakeDb({[path]:row});
 const input={db,organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity',readingId:'x',startDate:row.startDate,endDate:row.date,currency:'VND',intervals:[{roomId:'r',startDate:'2026-08-01',endDate:null}]};
 return {db,path,input,load:patch=>db.runTransaction(tx=>utilityInvoiceSource({...input,...patch,tx}))};
}
test('utility invoice uses stored server charge and tariff',async()=>{
 const {load}=setup();const result=await load();assert.equal(result.calculation.amountMinor,35000);assert.equal(result.calculation.readingId,'x');assert.equal(result.calculation.tariff.currency,'VND');
});

test('cross-currency utility invoice pins a server rate and preserves original reading amounts',async()=>{
 const {db,path,load}=setup();
 const rates=normalizeRates([{base:'USD',quote:'VND',rate:25000,date:'2026-10-08'}]);
 db.store.set(`referenceExchangeRates/${rates.id}`,rates);
 const before=structuredClone(db.store.get(path));
 const result=await load({currency:'USD',ratesId:rates.id});
 assert.equal(result.calculation.currency,'USD');
 assert.equal(result.calculation.amountMinor,140);
 assert.equal(result.calculation.usageMilli,10000);
 assert.equal(result.calculation.sourceCalculation.amountMinor,35000);
 assert.equal(result.calculation.sourceCalculation.currency,'VND');
 assert.equal(result.calculation.exchangeRateSnapshotId,rates.id);
 assert.deepEqual(db.store.get(path),before);
 await assert.rejects(load({currency:'USD',ratesId:'f'.repeat(64)}),/rates_required/);
});
test('utility billing refuses duplicate, foreign scope, mismatched dates, currency and zero charges',async()=>{
 for(const [patch,key] of [[{invoiceId:'invoice'},'already_billed'],[{buildingId:'other'},'not_found'],[{calculation:null},'no_billable_charge']]){
  const {db,path,load}=setup();Object.assign(db.store.get(path),patch);await assert.rejects(load(),new RegExp(key));
 }
 const {load}=setup();await assert.rejects(load({startDate:'2026-09-02'}),/invoice_dates/);await assert.rejects(load({currency:'USD'}),/no_billable_charge/);
});
test('a tenant cannot receive another room or partial occupancy interval',async()=>{
 const {load}=setup();
 for(const intervals of [[],[{roomId:'other',startDate:'2026-08-01'}],[{roomId:'r',startDate:'2026-09-02'}],[{roomId:'r',startDate:'2026-08-01',endDate:'2026-09-30'}]])await assert.rejects(load({intervals}),/tenant_boundary_required/);
});
test('invoice transaction links once, refuses a second bill and releases only after void',async()=>{
 const {db,path}=setup();Ts.clock=Date.parse('2026-10-02T12:00:00Z');
 db.store.set('organizations/o',{accessVersion:2});
 db.store.set('memberships/u_o',{ownerId:'u',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]});
 db.store.set('buildings/b',{organizationId:'o',currency:'VND',timeZone:'Asia/Ho_Chi_Minh'});
 db.store.set('tenants/t',{organizationId:'o',buildingId:'b',roomId:'r',isMainTenant:true,fullName:'Tenant',currency:'VND',moveInDate:Ts.fromMillis(Date.parse('2026-08-01T00:00:00Z'))});
 const handler=createInvoiceHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const call=data=>handler({auth:{uid:'u'},data:{organizationId:'o',buildingId:'b',...data}});
 const payload={kind:'utility',tenantId:'t',roomId:'r',readingId:'x',chargeType:'electricity',startDate:'2026-09-01',endDate:'2026-10-01',dueDate:'2026-10-02',feesMinor:{internetFee:0,cableTVFee:0,hotWaterFee:0,lateFee:0,taxAmount:0},reason:'Measured electricity'};
 const quote=await call({action:'quote',...payload});assert.equal(quote.record.totalMinor,35000);
 const request={action:'create',...payload,operationId:'create1',quoteRevision:quote.record.quoteRevision};
 const created=await call(request);assert.deepEqual(await call(request),created);assert.equal(db.store.get(path).invoiceId,created.invoiceId);
 await assert.rejects(call({...request,operationId:'create2'}),e=>e.message==='utility_already_billed');
 db.store.get('payments/'+created.invoiceId).paidAmount=1;
 await assert.rejects(call({action:'void',invoiceId:created.invoiceId,revision:'0:0',operationId:'void1',reason:'Correction'}),e=>e.message==='invoice_refund_first');
 assert.equal(db.store.get(path).invoiceId,created.invoiceId);
 db.store.get('payments/'+created.invoiceId).paidAmount=0;
 await call({action:'void',invoiceId:created.invoiceId,revision:'0:0',operationId:'void1',reason:'Correction'});
 assert.equal(db.store.get(path).invoiceId,null);
 const again=await call({action:'quote',...payload});await call({...request,operationId:'create2',quoteRevision:again.record.quoteRevision});
 assert.notEqual(db.store.get(path).invoiceId,created.invoiceId);
});
