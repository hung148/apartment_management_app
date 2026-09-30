const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createOrganizationSettingsHandler}=require('../organization_settings');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const member=(uid,role,extra={})=>({ownerId:uid,organizationId:'org',accessVersion:2,role,status:'active',buildingScope:'all',buildingIds:[],...extra});
const seed=()=>({
  'organizations/org':{name:'Sunrise',accessVersion:2,createdBy:'owner',createdAt:new Ts(1),bankAccountNumber:'123456',taxCode:'TAX'},
  'memberships/owner_org':member('owner','owner'),
  'memberships/admin_org':member('admin','administrator'),
  'memberships/staff_org':member('staff','receptionist',{buildingScope:'selected',buildingIds:['b1']}),
  'memberships/gone_org':member('gone','manager',{status:'revoked'}),
  'organizations/legacy':{name:'Old',createdBy:'owner'},
  'memberships/owner_legacy':{...member('owner','admin'),organizationId:'legacy',accessVersion:undefined},
});
const setup=(data=seed())=>{const db=fakeDb(data);return {db,call:(uid,input)=>createOrganizationSettingsHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:uid&&{uid},data:input})};};
const rejects=(p,code,message)=>assert.rejects(p,e=>e.code===code&&(!message||e.message===message));
const fields={name:'Sunrise Homes',address:'1 Main',phone:'',email:'a@b.co',taxCode:'',bankName:'',bankAccountNumber:'999',bankAccountName:''};

test('validates identity, action shape and fields before touching data',async()=>{
  const {call,db}=setup();
  await rejects(call(null,{action:'read',organizationId:'org'}),'unauthenticated');
  for(const input of [{},{action:'drop',organizationId:'org'},{action:'read',organizationId:'../x'},
    {action:'read',organizationId:'org',extra:1},{action:'update',organizationId:'org',fields},
    {action:'update',organizationId:'org',operationId:'op',fields:{...fields,createdBy:'me'}},
    {action:'update',organizationId:'org',operationId:'op',fields:{name:'Only name'}},
    {action:'update',organizationId:'org',operationId:'op',fields:{...fields,name:' '}},
    {action:'update',organizationId:'org',operationId:'op',fields:{...fields,email:'nope'}},
    {action:'update',organizationId:'org',operationId:'op',fields:{...fields,address:'x'.repeat(301)}},
    {action:'close',organizationId:'org',operationId:'op',confirmName:'Sunrise',x:1}])
    await rejects(call('owner',input),'invalid-argument');
  assert.equal(db.store.get('organizations/org').name,'Sunrise');
});

test('read returns private fields only to organization managers',async()=>{
  const {call}=setup();
  const owner=await call('owner',{action:'read',organizationId:'org'});
  assert.equal(owner.bankAccountNumber,'123456');assert.equal(owner.role,'owner');
  assert.deepEqual([owner.canManage,owner.canClose,owner.canLeave],[true,true,false]);
  assert.equal(owner.createdAt,new Date(1).toISOString());
  const staff=await call('staff',{action:'read',organizationId:'org'});
  assert.equal(staff.bankAccountNumber,undefined);assert.equal(staff.taxCode,undefined);
  assert.deepEqual([staff.canManage,staff.canClose,staff.canLeave],[false,false,true]);
  await rejects(call('gone',{action:'read',organizationId:'org'}),'permission-denied');
  await rejects(call('stranger',{action:'read',organizationId:'org'}),'permission-denied');
  await rejects(call('owner',{action:'read',organizationId:'legacy'}),'failed-precondition','team_migration_required');
});

test('update needs manageOrganization, audits field names only and replays exactly',async()=>{
  const {call,db}=setup();
  await rejects(call('staff',{action:'update',organizationId:'org',operationId:'op1',fields}),'permission-denied');
  const first=await call('admin',{action:'update',organizationId:'org',operationId:'op1',fields});
  assert.deepEqual(first.changedFields.sort(),['address','bankAccountNumber','email','name','taxCode']);
  const org=db.store.get('organizations/org');
  assert.equal(org.name,'Sunrise Homes');assert.equal(org.taxCode,null);assert.equal(org.updatedBy,'admin');
  const events=[...db.store].filter(([k])=>k.startsWith('teamActivity/')).map(([,v])=>v);
  assert.equal(events.length,1);assert.equal(events[0].action,'updateOrganization');
  assert.equal(JSON.stringify(events[0]).includes('999'),false,'bank values must not enter activity');
  assert.deepEqual(await call('admin',{action:'update',organizationId:'org',operationId:'op1',fields}),first);
  await rejects(call('admin',{action:'update',organizationId:'org',operationId:'op1',fields:{...fields,name:'Other'}}),'already-exists');
});

test('leave revokes only the caller; the owner cannot leave',async()=>{
  const {call,db}=setup();
  await rejects(call('owner',{action:'leave',organizationId:'org',operationId:'l1'}),'failed-precondition','org_owner_cannot_leave');
  assert.deepEqual(await call('admin',{action:'leave',organizationId:'org',operationId:'l1'}),{status:'left'});
  assert.equal(db.store.get('memberships/admin_org').status,'revoked');
  assert.equal(db.store.get('memberships/staff_org').status,'active');
  // Exact retry after success returns the stored result even though access is gone.
  assert.deepEqual(await call('admin',{action:'leave',organizationId:'org',operationId:'l1'}),{status:'left'});
  await rejects(call('admin',{action:'read',organizationId:'org'}),'permission-denied');
});

test('close is owner-only, needs the exact name and revokes everyone with retained data',async()=>{
  const {call,db}=setup();
  await rejects(call('admin',{action:'close',organizationId:'org',operationId:'c1',confirmName:'Sunrise'}),'permission-denied','org_owner_required');
  await rejects(call('owner',{action:'close',organizationId:'org',operationId:'c1',confirmName:'sunrise'}),'invalid-argument','org_confirm_name');
  assert.equal(db.store.get('organizations/org').closedAt,undefined);
  const result=await call('owner',{action:'close',organizationId:'org',operationId:'c2',confirmName:' Sunrise '});
  assert.equal(result.status,'closed');
  assert.equal(result.purgeAfter,new Date(Ts.clock+30*86400000).toISOString());
  for(const id of ['owner','admin','staff','gone'])assert.equal(db.store.get(`memberships/${id}_org`).status,'revoked',id);
  assert.equal(db.store.get('memberships/gone_org').revokedReason,undefined,'already revoked record keeps its reason');
  assert.equal(db.store.get('memberships/owner_legacy').status,'active','other organizations untouched');
  assert.ok(db.store.has('organizations/org'),'records are retained until the purge date');
  assert.deepEqual(await call('owner',{action:'close',organizationId:'org',operationId:'c2',confirmName:' Sunrise '}),result);
  await rejects(call('owner',{action:'close',organizationId:'org',operationId:'c2',confirmName:'Sunrise'}),'already-exists','org_operation_reused');
  await rejects(call('owner',{action:'read',organizationId:'org'}),'failed-precondition','org_closed');
});

test('an interrupted close resumes for the same owner, even with a new operation',async()=>{
  const data=seed();
  for(let i=0;i<650;i++)data[`memberships/m${String(i).padStart(3,'0')}_org`]=member(`m${String(i).padStart(3,'0')}`,'receptionist');
  const {call,db}=setup(data);
  const commit=db.batch;let fails=1;
  db.batch=()=>{const b=commit();const c=b.commit;b.commit=async()=>{if(db.calls===1&&fails-->0)throw new CodeError('unavailable','network');return c();};return b;};
  await rejects(call('owner',{action:'close',organizationId:'org',operationId:'c1',confirmName:'Sunrise'}),'unavailable');
  assert.ok(db.store.get('organizations/org').closedAt,'phase 1 committed');
  assert.equal(db.store.get('memberships/owner_org').status,'active','owner can still resume');
  await rejects(call('admin',{action:'read',organizationId:'org'}),'failed-precondition','org_closed');
  const result=await call('owner',{action:'close',organizationId:'org',operationId:'c9',confirmName:'ignored after close'});
  assert.equal(result.status,'closed');
  assert.equal([...db.store].filter(([k,v])=>k.startsWith('memberships/')&&v.organizationId==='org'&&v.status!=='revoked').length,0);
  assert.equal([...db.store].filter(([k,v])=>k.startsWith('teamActivity/')&&v.action==='closeOrganization').length,1);
});

test('the exported callable passes through the shared security boundary',async()=>{
  const api=require('../index');
  await rejects(api.organizationSettings.run({data:{}}),'unauthenticated');
  await rejects(api.organizationSettings.run({auth:{uid:'u'},data:{}}),'unauthenticated','app_check_required');
});

// ── Copy to another organization ────────────────────────────────────────────
const copySeed=()=>({...seed(),
  'organizations/dest':{name:'Dest',accessVersion:2,createdBy:'owner'},
  'memberships/owner_dest':{...member('owner','owner'),organizationId:'dest'},
  'memberships/admin_dest':{...member('admin','manager'),organizationId:'dest'},
  'buildings/b1':{organizationId:'org',name:'Tower',timeZone:'Asia/Ho_Chi_Minh'},
  'buildings/b1/rentalContractHistory/h1':{organizationId:'org',buildingId:'b1',reason:'signed'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'101',rates:{monthly:500}},
  'tenants/t1':{organizationId:'org',buildingId:'b1',roomId:'r1',fullName:'Main',isMainTenant:true,movedIn:new Ts(5)},
  'tenants/t2':{organizationId:'org',buildingId:'b1',roomId:'r1',fullName:'Mate',mainTenantId:'t1'},
  'tenants/t1/rentHistory/x':{organizationId:'org',tenantId:'t1',amountMinor:100},
  'tenants/legacyT':{buildingId:'b1',roomId:'r1',fullName:'Old record without organizationId'},
  'payments/p1':{organizationId:'org',tenantId:'t1',roomId:'r1',lines:[{tenantId:'t2',amountMinor:5}]},
  'payments/p1/invoiceHistory/e1':{organizationId:'org',action:'create'},
  'payments/legacyP':{tenantId:'legacyT',amount:10},
  'bookings/k1':{organizationId:'org',roomId:'r1',paymentIds:['p1'],guestName:'Guest'},
  'leaseOccupancy/o1':{organizationId:'org',tenantId:'t1',roomId:'r1',buildingId:'b1'},
  'housekeepingTasks/task':{organizationId:'org',roomId:'r1',staffId:'s1'},
  'staffProfiles/s1':{organizationId:'org',displayName:'Staff'},
});
const copyCmd={action:'copy',organizationId:'org',operationId:'cp',targetOrganizationId:'dest'};
const inDest=(db,c)=>[...db.store].filter(([k,v])=>k.split('/').length===2&&k.startsWith(c+'/')&&v.organizationId==='dest');

test('copy preview counts records and checks access in both organizations',async()=>{
  const {call}=setup(copySeed());
  const preview=await call('owner',{action:'copyPreview',organizationId:'org',targetOrganizationId:'dest'});
  assert.deepEqual([preview.buildings,preview.rooms,preview.tenants,preview.payments,preview.bookings],[1,1,3,2,1]);
  await rejects(call('owner',{action:'copyPreview',organizationId:'org',targetOrganizationId:'org'}),'invalid-argument','org_copy_target');
  // Manager in the target: no manageOrganization/importData there.
  await rejects(call('admin',{action:'copyPreview',organizationId:'org',targetOrganizationId:'dest'}),'permission-denied','org_copy_access_required');
  await rejects(call('owner',{action:'copyPreview',organizationId:'org',targetOrganizationId:'legacy'}),'failed-precondition','team_migration_required');
});

test('copy duplicates records with new IDs, rewires every link and keeps the source intact',async()=>{
  const {call,db}=setup(copySeed());
  const before=new Map([...db.store].map(([k,v])=>[k,JSON.stringify(v)]));
  const result=await call('owner',copyCmd);
  assert.equal(result.status,'copied');
  assert.deepEqual(result.counts,{buildings:1,rooms:1,tenants:3,bookings:1,payments:2,leaseOccupancy:1,leaseDateCorrections:0,rentalContractHistory:1,rentHistory:1,invoiceHistory:1});
  const [[bPath]]=inDest(db,'buildings'),bId=bPath.split('/')[1];
  const [[rPath,room]]=inDest(db,'rooms'),rId=rPath.split('/')[1];
  assert.equal(room.buildingId,bId);assert.deepEqual(room.rates,{monthly:500});
  const tenants=Object.fromEntries(inDest(db,'tenants').map(([k,v])=>[v.fullName,{id:k.split('/')[1],...v}]));
  assert.equal(tenants.Mate.mainTenantId,tenants.Main.id);
  assert.equal(tenants['Old record without organizationId'].roomId,rId);
  assert.ok(tenants.Main.movedIn instanceof Ts,'timestamps survive the copy');
  const payments=inDest(db,'payments').map(([k,v])=>({id:k.split('/')[1],...v}));
  const p1=payments.find(p=>p.lines);assert.equal(p1.tenantId,tenants.Main.id);assert.equal(p1.lines[0].tenantId,tenants.Mate.id);
  assert.equal(payments.find(p=>p.amount===10).tenantId,tenants['Old record without organizationId'].id);
  assert.deepEqual(inDest(db,'bookings')[0][1].paymentIds,[p1.id]);
  assert.equal(inDest(db,'leaseOccupancy')[0][1].tenantId,tenants.Main.id);
  assert.equal([...db.store.keys()].filter(k=>k.startsWith(`tenants/${tenants.Main.id}/rentHistory/`)).length,1);
  assert.equal([...db.store.keys()].filter(k=>k.startsWith(`payments/${p1.id}/invoiceHistory/`)).length,1);
  assert.equal(inDest(db,'housekeepingTasks').length+inDest(db,'staffProfiles').length,0,'team and tasks stay behind');
  for(const [k,v] of before)assert.equal(JSON.stringify(db.store.get(k)),v,`source record changed: ${k}`);
  const actions=[...db.store].filter(([k])=>k.startsWith('teamActivity/')).map(([,v])=>`${v.organizationId}:${v.action}`).sort();
  assert.deepEqual(actions,['dest:copyOrganizationIn','org:copyOrganizationOut']);
  const size=db.store.size;
  assert.deepEqual(await call('owner',copyCmd),result);assert.equal(db.store.size,size,'exact retry makes no duplicates');
});

test('an interrupted copy resumes onto the same IDs; a foreign child aborts it',async()=>{
  const data=copySeed();
  for(let i=0;i<500;i++)data[`rooms/x${String(i).padStart(3,'0')}`]={organizationId:'org',buildingId:'b1',roomNumber:String(i)};
  const {call,db}=setup(data);
  const commit=db.batch;let fails=1;
  db.batch=()=>{const b=commit();const c=b.commit;b.commit=async()=>{if(db.calls===1&&fails-->0)throw new CodeError('unavailable','network');return c();};return b;};
  await rejects(call('owner',copyCmd),'unavailable');
  const partial=inDest(db,'rooms').length;assert.ok(partial>0&&partial<501);
  await call('owner',copyCmd);
  assert.equal(inDest(db,'rooms').length,501);assert.equal(inDest(db,'buildings').length,1);
  const bad=setup({...copySeed(),'payments/foreign':{organizationId:'other',tenantId:'t1'}});
  await rejects(bad.call('owner',copyCmd),'failed-precondition','org_copy_cross_link');
  assert.equal(inDest(bad.db,'buildings').length,0);
});

// ── Restore a closed organization ───────────────────────────────────────────
test('the owner can list and restore a closed organization; members return to their previous status',async()=>{
  const data=seed();
  data['memberships/susp_org']=member('susp','manager',{status:'suspended'});
  data['memberships/left_org']=member('left','receptionist',{status:'revoked',revokedReason:'left'});
  const {call,db}=setup(data);
  await call('owner',{action:'close',organizationId:'org',operationId:'c1',confirmName:'Sunrise'});
  const listed=await call('owner',{action:'closedList'});
  assert.deepEqual(listed.records.map(r=>[r.id,r.name]),[['org','Sunrise']]);
  assert.deepEqual((await call('admin',{action:'closedList'})).records,[],'only the account that closed it');
  await rejects(call('admin',{action:'restore',organizationId:'org',operationId:'r0'}),'failed-precondition','org_not_closed');
  assert.deepEqual(await call('owner',{action:'restore',organizationId:'org',operationId:'r1'}),{status:'restored'});
  const status=id=>db.store.get(`memberships/${id}_org`).status;
  assert.deepEqual(['owner','admin','staff','susp','gone','left'].map(status),['active','active','active','suspended','revoked','revoked']);
  const org=db.store.get('organizations/org');
  assert.equal(org.closedAt,null);assert.equal(org.purgeAfter,null);assert.equal(org.restoringAt,null);
  assert.equal((await call('admin',{action:'read',organizationId:'org'})).name,'Sunrise');
  assert.deepEqual(await call('owner',{action:'restore',organizationId:'org',operationId:'r1'}),{status:'restored'},'exact retry');
  await rejects(call('owner',{action:'restore',organizationId:'org',operationId:'r2'}),'failed-precondition','org_not_closed');
  assert.deepEqual((await call('owner',{action:'closedList'})).records,[]);
  const actions=[...db.store].filter(([k])=>k.startsWith('teamActivity/')).map(([,v])=>v.action).sort();
  assert.deepEqual(actions,['closeOrganization','restoreOrganization']);
});

test('restore is refused after the purge date or once the purge has started',async()=>{
  const {call,db}=setup();
  await call('owner',{action:'close',organizationId:'org',operationId:'c1',confirmName:'Sunrise'});
  db.store.set('organizations/org',{...db.store.get('organizations/org'),purgeAfter:new Ts(Ts.clock-1)});
  await rejects(call('owner',{action:'restore',organizationId:'org',operationId:'r1'}),'failed-precondition','org_restore_expired');
  assert.deepEqual((await call('owner',{action:'closedList'})).records,[],'expired ones are not offered');
  db.store.set('organizations/org',{...db.store.get('organizations/org'),purgeAfter:new Ts(Ts.clock+DAY_MS),purgeStartedAt:new Ts(Ts.clock)});
  await rejects(call('owner',{action:'restore',organizationId:'org',operationId:'r2'}),'failed-precondition','org_restore_expired');
});
const DAY_MS=86400000;

// ── Waiting members (no supported role yet, including the removed viewer role) ──
test('waiting members cannot read or manage, but can leave',async()=>{
  const data=seed();
  data['memberships/wait_org']=member('wait',null,{status:'assignmentRequired',buildingScope:'selected'});
  data['memberships/old_org']=member('old','viewer');
  const {call,db}=setup(data);
  for(const uid of ['wait','old']){
    await rejects(call(uid,{action:'read',organizationId:'org'}),'permission-denied');
    await rejects(call(uid,{action:'update',organizationId:'org',operationId:'u'+uid,fields}),'permission-denied');
    assert.deepEqual(await call(uid,{action:'leave',organizationId:'org',operationId:'l'+uid}),{status:'left'});
    assert.equal(db.store.get(`memberships/${uid}_org`).status,'revoked');
  }
  const event=[...db.store].find(([k,v])=>k.startsWith('teamActivity/')&&v.targetId==='wait_org')[1];
  assert.deepEqual(event.before,{status:'assignmentRequired'});
});
