const {test}=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createUtilityReadingsHandler}=require('../utility_readings');
function setup(){
 Ts.clock=Date.parse('2026-10-02T12:00:00Z');
 const db=fakeDb({'organizations/o':{accessVersion:2},'buildings/b':{organizationId:'o',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},'rooms/r':{organizationId:'o',buildingId:'b',roomNumber:'101'},'memberships/owner_o':{ownerId:'owner',organizationId:'o',accessVersion:2,status:'active',role:'owner',buildingScope:'all',buildingIds:[]}});
 const handler=createUtilityReadingsHandler({db,Timestamp:Ts,HttpsError:CodeError});let sequence=0;
 const call=(data,uid='owner')=>handler({auth:{uid},data:{organizationId:'o',buildingId:'b',roomId:'r',kind:'electricity',...(data.action!=='read'?{operationId:'op'+(++sequence),reason:'Meter log'}:{}),...(data.action==='tariff'?{tariffScope:'room',effectiveDate:'2026-09-01',propertyRevision:0}:{}),...data}});
 return {db,call};
}
const tariff={currency:'VND',bands:[{throughMilli:null,priceMinor:3500}]};
test('baseline, tariff snapshot, consumption and reset preserve meter history',async()=>{
 const {call}=setup();assert.equal((await call({action:'read'})).record.revision,0);
 await call({action:'record',revision:0,date:'2026-09-01',readingMilli:100000});
 await call({action:'tariff',revision:1,tariff});
 const charge=await call({action:'record',revision:2,date:'2026-09-15',readingMilli:125000});assert.equal(charge.calculation.amountMinor,87500);
 await call({action:'tariff',revision:3,effectiveDate:'2026-09-15',tariff:{...tariff,bands:[{throughMilli:null,priceMinor:4000}]}});
 const reset=await call({action:'record',revision:4,date:'2026-10-02',readingMilli:10000,oldFinalMilli:130000,newStartMilli:0});assert.equal(reset.calculation.amountMinor,60000);
 const view=await call({action:'read'});assert.equal(view.records.length,3);assert.equal(view.records[0].calculation,null);assert.equal(view.records[1].tariff.bands[0].priceMinor,3500);assert.equal(view.record.lastReadingMilli,10000);
});
test('lost responses replay exactly; changed payload and stale revisions fail',async()=>{
 const {call}=setup();const data={action:'record',operationId:'same',revision:0,date:'2026-10-02',readingMilli:0};
 assert.deepEqual(await call(data),await call(data));
 await assert.rejects(call({...data,readingMilli:1}),e=>e.code==='failed-precondition');
 await assert.rejects(call({action:'tariff',revision:0,tariff}),e=>e.code==='aborted');
 assert.equal((await call({action:'read'})).records.length,1);
});
test('foreign scope, inactive accounts, legacy and closed organizations are refused',async()=>{
 for(const status of ['suspended','revoked','waiting']){
  const {call,db}=setup();db.store.get('memberships/owner_o').status=status;await assert.rejects(call({action:'read'}),e=>e.code==='permission-denied');
 }
 for(const patch of [{closedAt:Ts.now()},{accessVersion:1}]){const {call,db}=setup();Object.assign(db.store.get('organizations/o'),patch);await assert.rejects(call({action:'read'}),e=>e.code==='permission-denied');}
 const {call,db}=setup();await assert.rejects(call({action:'read'},'outsider'),e=>e.code==='permission-denied');db.store.get('rooms/r').organizationId='foreign';await assert.rejects(call({action:'read'}),e=>e.code==='not-found');
});
test('reading order, missing tariff, future date and currency mismatch fail without writes',async()=>{
 const {call}=setup();await call({action:'record',revision:0,date:'2026-09-01',readingMilli:1000});
 await assert.rejects(call({action:'record',revision:1,date:'2026-09-02',readingMilli:2000}),e=>e.message==='utility_tariff_required');
 await assert.rejects(call({action:'tariff',revision:1,tariff:{...tariff,currency:'USD'}}),e=>e.message==='utility_currency_changed');
 await call({action:'tariff',revision:1,tariff});
 for(const date of ['2026-08-01','2026-09-01','2026-10-03'])await assert.rejects(call({action:'record',revision:2,date,readingMilli:2000}));
 await assert.rejects(call({action:'record',revision:2,date:'2026-10-02',readingMilli:0}),e=>e.message==='utility_reading_decreased');
 assert.equal((await call({action:'read'})).records.length,1);
});
test('property prices serve multiple rooms, preserve snapshots, and reject retroactive changes',async()=>{
 const {call,db}=setup();db.store.set('rooms/r2',{organizationId:'o',buildingId:'b',roomNumber:'102'});
 await call({action:'tariff',revision:0,tariffScope:'property',tariff});
 await call({action:'record',roomId:'r2',revision:0,date:'2026-09-01',readingMilli:0});
 const usage=await call({action:'record',roomId:'r2',revision:1,date:'2026-09-15',readingMilli:1000});
 assert.equal(usage.calculation.amountMinor,3500);
 await assert.rejects(call({action:'tariff',revision:1,propertyRevision:1,tariffScope:'property',effectiveDate:'2026-09-14',tariff}),e=>e.message==='utility_tariff_past_reading');
 await assert.rejects(call({action:'tariff',revision:1,propertyRevision:0,tariffScope:'property',effectiveDate:'2026-09-15',tariff}),e=>e.code==='aborted');
 await call({action:'tariff',revision:1,propertyRevision:1,tariffScope:'property',effectiveDate:'2026-09-15',tariff:{...tariff,bands:[{throughMilli:null,priceMinor:4000}]}});
 const view=await call({action:'read',roomId:'r2'});assert.equal(view.records[1].tariff.bands[0].priceMinor,3500);assert.equal(view.record.propertyRevision,2);
 assert.equal((await call({action:'record',roomId:'r2',revision:2,date:'2026-10-02',readingMilli:2000})).calculation.amountMinor,4000);
});
test('a tariff boundary blocks estimated usage and succeeds after the boundary is measured',async()=>{
 const {call}=setup();await call({action:'tariff',revision:0,tariff});
 await call({action:'tariff',revision:1,effectiveDate:'2026-09-15',tariff:{...tariff,bands:[{throughMilli:null,priceMinor:4000}]}});
 await call({action:'record',revision:2,date:'2026-09-01',readingMilli:0});
 await assert.rejects(call({action:'record',revision:3,date:'2026-10-02',readingMilli:2000}),e=>e.message==='utility_tariff_boundary_required');
 assert.equal((await call({action:'record',revision:3,date:'2026-09-15',readingMilli:1000})).calculation.amountMinor,3500);
 assert.equal((await call({action:'record',revision:4,date:'2026-10-02',readingMilli:2000})).calculation.amountMinor,4000);
});
test('scoped lease staff can record today but cannot change prices, backdate or access another property',async()=>{
 const {call,db}=setup();db.store.set('memberships/staff_o',{ownerId:'staff',organizationId:'o',accessVersion:2,status:'active',role:'custom',roleGrants:{manageLease:'managed'},buildingScope:'selected',buildingIds:['b']});
 const view=await call({action:'read'},'staff');assert.equal(view.record.canPrice,false);assert.equal(view.record.canBill,false);
 await assert.rejects(call({action:'tariff',revision:0,tariff},'staff'),e=>e.code==='permission-denied');
 await assert.rejects(call({action:'record',revision:0,date:'2026-10-01',readingMilli:0},'staff'),e=>e.message==='utility_backdate_denied');
 await call({action:'record',revision:0,date:'2026-10-02',readingMilli:0},'staff');
 db.store.get('memberships/staff_o').buildingIds=['other'];await assert.rejects(call({action:'read'},'staff'),e=>e.code==='permission-denied');
});
test('history is paginated without imposing a lifetime meter limit',async()=>{
 const {call,db}=setup();const {meterId}=require('../utility_invoice');const parent=`utilityMeters/${meterId('o','r','electricity')}`;
 for(let i=0;i<55;i++)db.store.set(`${parent}/readings/row${String(i).padStart(3,'0')}`,{date:new Date(Date.UTC(2026,0,1+i)).toISOString().slice(0,10),readingMilli:i,createdAt:Ts.now()});
 const first=await call({action:'read'});assert.equal(first.records.length,50);assert.equal(first.nextCursor,'row049');
 const second=await call({action:'read',cursor:first.nextCursor});assert.equal(second.records.length,5);assert.equal(second.nextCursor,null);assert.equal(second.records[0].id,'row050');
});
test('corrections reverse only the latest unbilled reading and preserve its audit record',async()=>{
 const {call,db}=setup();const baseline=await call({action:'record',revision:0,date:'2026-09-01',readingMilli:1000});
 await call({action:'tariff',revision:1,tariff});
 const measured=await call({action:'record',revision:2,date:'2026-10-01',readingMilli:2000});
 await assert.rejects(call({action:'reverse',revision:3,readingId:baseline.readingId}),e=>e.message==='utility_reverse_latest_only');
 const {meterId}=require('../utility_invoice'),path=`utilityMeters/${meterId('o','r','electricity')}/readings/${measured.readingId}`;
 db.store.get(path).invoiceId='invoice';await assert.rejects(call({action:'reverse',revision:3,readingId:measured.readingId}),e=>e.message==='utility_void_invoice_first');
 db.store.get(path).invoiceId=null;await call({action:'reverse',revision:3,readingId:measured.readingId});
 const view=await call({action:'read'});assert.equal(view.record.lastReadingMilli,1000);assert.equal(view.record.lastReadingId,baseline.readingId);assert.ok(view.records[1].reversedAt);
 const corrected=await call({action:'record',revision:4,date:'2026-10-01',readingMilli:3000});assert.equal(corrected.calculation.amountMinor,7000);assert.equal((await call({action:'read'})).records.length,3);
});
test('custom staff grants are enforced without implicit price authority',async()=>{
 const {call,db}=setup();db.store.set('memberships/co_o',{ownerId:'co',organizationId:'o',accessVersion:2,status:'active',role:'custom_staff',roleGrants:{manageLease:'all'},buildingScope:'all',buildingIds:[]});
 assert.equal((await call({action:'read'},'co')).record.canPrice,false);
 await assert.rejects(call({action:'tariff',revision:0,tariff},'co'),e=>e.code==='permission-denied');
 db.store.get('memberships/co_o').roleGrants.overridePrices='all';await call({action:'tariff',revision:0,tariff},'co');
 db.store.get('memberships/co_o').roleGrants={};await assert.rejects(call({action:'read'},'co'),e=>e.code==='permission-denied');
});
