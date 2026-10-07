const {test}=require('node:test');
const assert=require('node:assert/strict');
const {planMigration}=require('../migration_plan');

const snapshot=()=>({
  organization:{id:'org',name:'Daily+',createdBy:'boss',inviteCode:'ABC'},
  memberships:[
    {id:'boss_org',organizationId:'org',ownerId:'boss',role:'admin',status:'active'},
    {id:'helper_org',organizationId:'org',ownerId:'helper',role:'admin',status:'active'},
    {id:'clerk_org',organizationId:'org',ownerId:'clerk',role:'member',status:'active'},
    {id:'old_org',organizationId:'org',ownerId:'old',role:'member',status:'pending'},
  ],
  buildings:[{id:'b1',organizationId:'org',name:'Tower'},{id:'b2',organizationId:'org',timeZone:'Asia/Bangkok',currency:'USD'}],
  rooms:[
    {id:'r1',organizationId:'org',buildingId:'b1',roomNumber:'101',roomPrice:5e6},
    {id:'r2',organizationId:'org',buildingId:'b1',roomNumber:'102',hourlyPrice:1e5},
    {id:'r3',organizationId:'org',buildingId:'b1',roomNumber:'103'},
    {id:'r4',organizationId:'org',buildingId:'b2',rentalMode:'monthly',currency:'USD'},
  ],
  tenants:[{id:'t1',roomId:'r1',fullName:'A'},{id:'t2',organizationId:'org',buildingId:'b1',roomId:'r1'}],
  bookings:[{id:'k1',organizationId:'org',roomId:'r3'},{id:'k2',organizationId:'org',buildingId:'b2',roomId:'r4'}],
  payments:[{id:'p1',roomId:'r1',tenantId:'t1'}],
});
const byPath=plan=>Object.fromEntries(plan.changes.map(c=>[c.path,c]));

test('plans people, properties, rooms and old records; the switch goes last',()=>{
  const plan=planMigration(snapshot());
  assert.deepEqual(plan.blockers,[]);
  const c=byPath(plan);
  assert.equal(plan.changes.at(-1).path,'organizations/org');
  assert.deepEqual(plan.changes.at(-1).set,{accessVersion:2});
  assert.deepEqual(plan.changes.at(-1).missing,['accessVersion']);
  assert.equal(c['memberships/boss_org'].set.role,'owner');
  assert.equal(c['memberships/boss_org'].previous.role,'admin');
  assert.equal(c['memberships/helper_org'].set.role,'administrator');
  assert.deepEqual([c['memberships/clerk_org'].set.role,c['memberships/clerk_org'].set.status,c['memberships/clerk_org'].set.buildingScope],[null,'assignmentRequired','selected']);
  assert.equal(c['memberships/old_org'].set.status,'suspended');
  assert.deepEqual(plan.summary.people,{owner:1,administrator:1,waiting:1,suspended:1,unchanged:0});
  assert.deepEqual(c['buildings/b1'].set,{timeZone:'Asia/Ho_Chi_Minh',currency:'VND'});
  assert.equal(c['buildings/b2'],undefined);
  assert.deepEqual(c['rooms/r1'].set,{rentalMode:'monthly',currency:'VND'});
  assert.equal(c['rooms/r2'].set.rentalMode,'both');
  assert.equal(c['rooms/r3'].set.rentalMode,'both'); // has a booking
  assert.equal(c['rooms/r4'],undefined);
  assert.deepEqual(c['tenants/t1'].set,{organizationId:'org',buildingId:'b1'});
  assert.deepEqual(c['bookings/k1'].set,{buildingId:'b1'});
  assert.deepEqual(c['payments/p1'].set,{organizationId:'org',buildingId:'b1'});
  assert.equal(c['tenants/t2'],undefined);
  const reasons=plan.warnings.map(w=>`${w.reason}:${w.path}`);
  assert.ok(reasons.includes('bookingsOnMonthlyRoom:rooms/r4'));
  assert.ok(reasons.includes('shortStayRoomWithoutHourlyPrice:rooms/r3'));
  assert.ok(reasons.includes('inactiveMemberSuspended:memberships/old_org'));
  assert.ok(!reasons.some(r=>r.endsWith('rooms/r2')));
});

test('a migrated organization plans nothing; problems block the migration',()=>{
  const done=snapshot();
  done.organization.accessVersion=2;
  assert.ok(planMigration(done).blockers.some(b=>b.reason==='alreadyV2'));
  const bad=snapshot();
  bad.memberships[0].status='suspended';
  bad.memberships.push({id:'dup',organizationId:'org',ownerId:'helper',role:'admin',status:'active'});
  bad.buildings[1].timeZone='Mars/Base';
  bad.rooms.push({id:'r9',buildingId:'gone'},{id:'r8',buildingId:'b1',rentalMode:'weekly'});
  bad.tenants.push({id:'t9',organizationId:'other',roomId:'r1'});
  const reasons=planMigration(bad).blockers.map(b=>b.reason).sort();
  assert.deepEqual(reasons,['invalidRentalMode','invalidTimeZone','missingActiveOwner','missingOrDuplicateAccount','otherOrganizationRecord','roomWithoutProperty']);
});

test('previous values make every change reversible',()=>{
  const s=snapshot();
  const plan=planMigration(s);
  const docs=new Map([...['memberships','buildings','rooms','tenants','bookings','payments'].flatMap(n=>s[n].map(d=>[`${n}/${d.id}`,{...d}])),['organizations/org',{...s.organization}]]);
  for(const c of plan.changes)Object.assign(docs.get(c.path),c.set);
  for(const c of plan.changes){const d=docs.get(c.path);Object.assign(d,c.previous);for(const k of c.missing)delete d[k];}
  for(const n of ['memberships','rooms','tenants'])for(const d of s[n])assert.deepEqual(docs.get(`${n}/${d.id}`),d);
  assert.deepEqual(docs.get('organizations/org'),s.organization);
});
