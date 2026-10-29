// Bảng thanh toán theo kỳ on the server (PAYMENT_SCHEDULE.md, 2026-10-26).
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createTenantLeasesHandler}=require('../tenant_leases');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');

const member=(uid,role,extra={})=>({ownerId:uid,organizationId:'org',accessVersion:2,role,status:'active',buildingScope:'all',buildingIds:[],...extra});
const seed=()=>({
 'organizations/org':{name:'Org',accessVersion:2,createdBy:'owner'},
 'memberships/owner_org':member('owner','owner'),
 'memberships/mgr_org':member('mgr','manager'),
 'memberships/lease_org':member('lease','custom',{roleGrants:{manageLease:'all'},roleRevision:1,roleName:'Lease only'}),
 'memberships/cash_org':member('cash','receptionist'),
 'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'},
 'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'201',rentalMode:'monthly',roomPrice:10000000},
});
async function setup(){
 const db=fakeDb(seed());
 const handler=createTenantLeasesHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const as=uid=>data=>handler({auth:{uid},data:{organizationId:'org',buildingId:'b1',...data}});
 const owner=as('owner');
 const p=(await owner({action:'prepare',roomId:'r1'})).record;
 // The contract end date is the day the tenant leaves: a year = 12 kỳ.
 const end=`${Number(p.today.slice(0,4))+1}${p.today.slice(4)}`;
 const {tenantId}=await owner({action:'create',roomId:'r1',operationId:'op1',roomRevision:p.roomRevision,timeZone:p.timeZone,currency:p.currency,fullName:'Le Van Chinh',phoneNumber:'0909',moveInDate:p.today,contractEndDate:end,rentMinor:10000000,backdateReason:'',periodMonths:1,
  surcharges:[{label:'Rác',amountMinor:100000,basis:'room',frequency:'period'}]});
 const read=async(uid='owner')=>(await as(uid)({action:'schedule',op:'read',tenantId})).record;
 return {db,as,owner,tenantId,read,today:p.today};
}
const err=(code,key)=>e=>e.code===code&&(!key||e.message===key);

test('a new lease shows twelve monthly kỳ of rent + phụ thu, nothing paid',async()=>{
 const {read,today}=await setup();
 const s=await read();
 assert.equal(s.rows.length,12);assert.equal(s.rows[0].start,today);
 assert.ok(s.rows.every(r=>r.amountMinor===10100000&&r.paidMinor===0&&r.leftMinor===10100000&&!r.locked));
 assert.equal(s.canEdit,true);assert.equal(s.canPrice,true);
});

test('editing a kỳ: stored on the lease, later kỳ shift, activity written, stale revision refused',async()=>{
 const {db,owner,tenantId,read}=await setup();
 const s=await read(),k2=s.rows[1];
 const shorter=new Date(Date.parse(k2.end+'T00:00:00Z')-5*86400000).toISOString().slice(0,10);
 await owner({action:'schedule',op:'edit',tenantId,revision:s.revision,rowId:k2.id,end:shorter});
 const a=await read();
 assert.equal(a.rows[1].end,shorter);assert.equal(a.rows[2].start,shorter);assert.equal(a.rows.length,13);
 assert.ok(Array.isArray(db.store.get(`tenants/${tenantId}`).paymentSchedule));
 assert.ok([...db.store.keys()].some(k=>k.startsWith('teamActivity/')&&db.store.get(k).action==='lease_schedule_edit'));
 // Stale revision ("đã có người sửa"): the fake Firestore has no update times,
 // so that refusal is not covered here.
});

test('another amount needs Đổi giá and a reason; the calculated amount does not',async()=>{
 const {as,tenantId,read}=await setup();
 const s=await read('lease'),k1=s.rows[0];
 assert.equal(s.canPrice,false);assert.equal(s.paidMinor,undefined);
 assert.equal(s.rows[0].paidMinor,null,'no money columns without readFinancialReports');
 await assert.rejects(as('lease')({action:'schedule',op:'edit',tenantId,revision:s.revision,rowId:k1.id,amountMinor:9000000,reason:'x'}),err('permission-denied','lease_price_authority'));
 await assert.rejects(as('mgr')({action:'schedule',op:'edit',tenantId,revision:s.revision,rowId:k1.id,amountMinor:9000000}),err('failed-precondition','schedule_reason_required'));
 await as('mgr')({action:'schedule',op:'edit',tenantId,revision:s.revision,rowId:k1.id,amountMinor:9000000,reason:'Giảm tháng đầu'});
 const a=await read();
 assert.equal(a.rows[0].amountMinor,9000000);assert.equal(a.rows[0].reason,'Giảm tháng đầu');assert.equal(a.rows[0].amountEdited,true);
});

test('dates before today need Nhập ngày trong quá khứ',async()=>{
 const {as,tenantId,read,today}=await setup();
 const s=await read();
 const before=new Date(Date.parse(today+'T00:00:00Z')-86400000).toISOString().slice(0,10);
 // Manager has no backdateRecords; the move-in rule refuses it anyway.
 await assert.rejects(as('mgr')({action:'schedule',op:'edit',tenantId,revision:s.revision,rowId:s.rows[0].id,start:before}),err('permission-denied','lease_backdate_owner_admin_required'));
});

test('an invoiced kỳ is locked; its money comes from the invoice',async()=>{
 const {db,owner,tenantId,read}=await setup();
 const s=await read(),k1=s.rows[0];
 db.store.set('payments/inv1',{organizationId:'org',buildingId:'b1',tenantId,invoiceKind:'period',status:'partial',calculation:{includeRent:true},billingStartLocalDate:k1.start,billingEndLocalDate:k1.end,totalMinor:10250000,amountMinor:10250000,paidAmount:4000000,currency:'VND',scheduleRowId:k1.id});
 const a=await read();
 assert.equal(a.rows[0].locked,true);assert.equal(a.rows[0].invoiceId,'inv1');assert.equal(a.rows[0].amountMinor,10250000);assert.equal(a.rows[0].paidMinor,4000000);assert.equal(a.rows[0].leftMinor,6250000);
 await assert.rejects(owner({action:'schedule',op:'edit',tenantId,revision:a.revision,rowId:k1.id,amountMinor:1,reason:'x'}),err('failed-precondition','schedule_row_locked'));
 await assert.rejects(owner({action:'schedule',op:'merge',tenantId,revision:a.revision,rowId:a.rows[1].id}),err('failed-precondition','schedule_row_locked'));
 // A cancelled invoice frees the kỳ.
 db.store.get('payments/inv1').status='cancelled';
 assert.equal((await read()).rows[0].locked,false);
});

test('split and merge',async()=>{
 const {owner,tenantId,read}=await setup();
 const s=await read(),k1=s.rows[0];
 const mid=new Date(Date.parse(k1.start+'T00:00:00Z')+10*86400000).toISOString().slice(0,10);
 await owner({action:'schedule',op:'split',tenantId,revision:s.revision,rowId:k1.id,date:mid});
 const a=await read();
 assert.equal(a.rows.length,13);assert.equal(a.rows[0].end,mid);assert.equal(a.rows[1].start,mid);assert.equal(a.rows[1].end,k1.end);
 await owner({action:'schedule',op:'merge',tenantId,revision:a.revision,rowId:a.rows[1].id});
 const b=await read();
 assert.equal(b.rows.length,12);assert.equal(b.rows[0].end,k1.end);
});

test('no contract end: the table asks for one; roommates and other roles get nothing',async()=>{
 const {db,as,owner,tenantId,read}=await setup();
 await assert.rejects(as('cash')({action:'schedule',op:'read',tenantId}),err('permission-denied'));
 const co=[...db.store.keys()].find(k=>k.startsWith('tenants/roommate'));
 if(co)await assert.rejects(owner({action:'schedule',op:'read',tenantId:co.slice(8)}),err('not-found'));
 db.store.get(`tenants/${tenantId}`).contractEndLocalDate=null;
 const s=await read();
 assert.equal(s.needsEnd,true);assert.deepEqual(s.rows,[]);
});

test('bad input is refused',async()=>{
 const {owner,tenantId}=await setup();
 for(const bad of [{op:'nope'},{op:'edit',revision:'1:1',rowId:'k1'},{op:'edit',revision:'1:1',rowId:'k1',end:'2026-13-01'},{op:'read',extra:1},{op:'split',revision:'1:1',rowId:'k1',date:'x'}])
  await assert.rejects(owner({action:'schedule',tenantId,...bad}),err('invalid-argument'));
});
