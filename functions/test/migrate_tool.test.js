// G8: tool/migrate_v2.cjs against the in-memory Firestore (read, plan, apply,
// drift stop, undo, anonymized rehearsal copy).
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fakeDb,DELETE}=require('./fake_firestore');
const {planMigration}=require('../migration_plan');
const tool=require('../../tool/migrate_v2.cjs');

class None{}
const codec=db=>tool.codec(db,{Timestamp:None,GeoPoint:None,DocumentReference:None});
const seed=()=>({
  'organizations/org':{name:'Daily+',createdBy:'boss',inviteCode:'CODE1',address:'12 Real Street'},
  'invite_codes/CODE1':{orgId:'org'},
  'memberships/boss_org':{organizationId:'org',ownerId:'boss',role:'admin',status:'active',email:'boss@gmail.com',displayName:'Anh Hung'},
  'memberships/clerk_org':{organizationId:'org',ownerId:'clerk',role:'member',status:'active',email:'clerk@gmail.com'},
  'buildings/b1':{organizationId:'org',name:'Real Tower',address:'12 Real Street'},
  'rooms/r1':{organizationId:'org',buildingId:'b1',roomNumber:'101',roomPrice:5000000,hourlyPrice:100000},
  'tenants/t1':{roomId:'r1',fullName:'Nguyen Van A',phoneNumber:'0912345678',monthlyRent:5000000},
  'tenants/t1/rentHistory/h1':{amount:5000000,note:'paid cash to A'},
  'bookings/k1':{organizationId:'org',roomId:'r1',guestName:'Guest B',guestPhone:'0987654321',totalPrice:300000,status:'confirmed'},
  'organizations/other':{name:'Other',createdBy:'x'},
  'rooms/rx':{organizationId:'other',buildingId:'bx'},
});
const plannedFrom=async db=>{
  const {enc}=codec(db);
  const {docs}=await tool.readOrganization(db,'org',{subcollections:true});
  const p=planMigration(tool.snapshotFor('org',docs));
  // Same shape as plan.json (JSON round trip).
  return {docs,p:JSON.parse(JSON.stringify({...p,changes:p.changes.map(c=>({...c,set:enc(c.set),previous:enc(c.previous)}))}))};
};

test('reads only this organization, including records found through their room',async()=>{
  const db=fakeDb(seed());
  const {docs}=await tool.readOrganization(db,'org',{subcollections:true});
  const paths=docs.map(d=>d.path).sort();
  assert.deepEqual(paths,['bookings/k1','buildings/b1','invite_codes/CODE1','memberships/boss_org','memberships/clerk_org',
    'organizations/org','rooms/r1','tenants/t1','tenants/t1/rentHistory/h1']);
});

test('apply then undo puts every record back exactly; the switch goes last',async()=>{
  const db=fakeDb(seed());
  const before=new Map([...db.store].map(([k,v])=>[k,{...v}]));
  const {p}=await plannedFrom(db);
  assert.deepEqual(p.blockers,[]);
  await tool.applyChanges(db,p,codec(db));
  assert.equal(db.store.get('organizations/org').accessVersion,2);
  assert.equal(db.store.get('memberships/boss_org').role,'owner');
  assert.equal(db.store.get('memberships/clerk_org').status,'assignmentRequired');
  assert.equal(db.store.get('rooms/r1').rentalMode,'both');
  assert.deepEqual([db.store.get('tenants/t1').organizationId,db.store.get('tenants/t1').buildingId],['org','b1']);
  assert.equal(db.store.get('buildings/b1').timeZone,'Asia/Ho_Chi_Minh');
  // Running the same plan again is harmless (everything already at its new value).
  await tool.applyChanges(db,p,codec(db));
  const drift=await tool.undoChanges(db,p,codec(db),()=>DELETE);
  assert.deepEqual(drift,[]);
  assert.deepEqual(new Map(db.store),before);
});

test('apply stops before writing when a record changed since the plan',async()=>{
  const db=fakeDb(seed());
  const {p}=await plannedFrom(db);
  db.store.get('memberships/clerk_org').role='admin';
  await assert.rejects(tool.applyChanges(db,p,codec(db)),/Changed since the plan[\s\S]*memberships\/clerk_org\.role/);
  assert.equal(db.store.get('organizations/org').accessVersion,undefined);
});

test('undo leaves fields changed after the move unless forced',async()=>{
  const db=fakeDb(seed());
  const {p}=await plannedFrom(db);
  await tool.applyChanges(db,p,codec(db));
  db.store.get('memberships/clerk_org').role='receptionist'; // owner gave a role in v2
  const drift=await tool.undoChanges(db,p,codec(db),()=>DELETE);
  assert.deepEqual(drift,['memberships/clerk_org.role: changed after the move']);
  assert.equal(db.store.get('memberships/clerk_org').role,'receptionist');
  assert.equal(db.store.get('memberships/clerk_org').status,'active');
  assert.equal(db.store.get('organizations/org').accessVersion,undefined);
  await tool.undoChanges(db,p,codec(db),()=>DELETE,true);
  assert.equal(db.store.get('memberships/clerk_org').role,'member');
});

test('rehearsal copy has new IDs, no personal text, same structure and amounts',async()=>{
  const db=fakeDb(seed());
  const {docs}=await tool.readOrganization(db,'org',{subcollections:true});
  const {newOrg,copies}=tool.anonymizedCopy(docs,'org','stagingUid','salt');
  const text=JSON.stringify(copies);
  for(const real of ['Daily+','Anh Hung','Nguyen Van A','Guest B','0912345678','0987654321','boss@gmail.com','clerk@gmail.com','12 Real Street','paid cash','Real Tower','"org"','"boss"','"clerk"','"b1"','"r1"','"t1"','CODE1'])
    assert.ok(!text.includes(real),real);
  const by=Object.fromEntries(copies.map(c=>[c.path,c.data]));
  const org=by['organizations/'+newOrg];
  assert.equal(org.createdBy,'stagingUid');assert.equal(org.rehearsal,true);assert.equal(org.accessVersion,undefined);
  assert.ok(by[`memberships/stagingUid_${newOrg}`]);
  assert.equal(by[`invite_codes/${org.inviteCode}`].orgId,newOrg);
  const room=Object.entries(by).find(([k])=>k.startsWith('rooms/'))[1];
  assert.deepEqual([room.roomNumber,room.roomPrice,room.hourlyPrice,room.organizationId],['101',5000000,100000,newOrg]);
  const tenant=Object.entries(by).find(([k])=>/^tenants\/[^/]+$/.test(k));
  assert.equal(tenant[1].roomId,Object.keys(by).find(k=>k.startsWith('rooms/')).split('/')[1]);
  assert.ok(by[`${tenant[0]}/rentHistory/${Object.keys(by).find(k=>k.includes('/rentHistory/')).split('/')[3]}`].amount===5000000);
  // The copy plans like the original.
  const copyDb=fakeDb(Object.fromEntries(copies.map(c=>[c.path,c.data])));
  const {docs:copyDocs}=await tool.readOrganization(copyDb,newOrg,{subcollections:true});
  const plan=planMigration(tool.snapshotFor(newOrg,copyDocs));
  assert.deepEqual(plan.blockers,[]);
  assert.equal(plan.changes.length,planMigration(tool.snapshotFor('org',docs)).changes.length);
});
