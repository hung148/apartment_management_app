const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createOrganizationPurge}=require('../organization_purge');
const {fakeDb,Ts}=require('./fake_firestore');
const DAY=86400000,now=Ts.clock;
const logs=[];const logger={info:(...a)=>logs.push(['info',...a]),warn:(...a)=>logs.push(['warn',...a]),error:(...a)=>logs.push(['error',...a])};
const closed=(days,extra={})=>({name:'Closed',accessVersion:2,closedAt:new Ts(now-40*DAY),closedBy:'owner',purgeAfter:new Ts(now+days*DAY),...extra});
const seed=()=>({
  'organizations/due':closed(-1),
  'organizations/early':closed(5),
  'organizations/live':{name:'Live',accessVersion:2},
  'organizations/stuck':closed(-2),
  'memberships/owner_due':{organizationId:'due',status:'revoked'},
  'memberships/x_stuck':{organizationId:'stuck',status:'active'},
  'buildings/b':{organizationId:'due'},'rooms/r':{organizationId:'due',buildingId:'b'},
  'tenants/t':{organizationId:'due',roomId:'r'},'tenants/t/rentHistory/h':{organizationId:'due'},
  'tenants/legacy':{roomId:'r'},'payments/p':{tenantId:'legacy'},
  'teamActivity/a':{organizationId:'due'},'invite_codes/C':{orgId:'due'},'organizationOperations/o':{organizationId:'due'},
  'buildings/keep':{organizationId:'live'},'buildings/early':{organizationId:'early'},
  'owners/owner':{name:'Owner profile stays'},
});
const run=db=>createOrganizationPurge({db,Timestamp:Ts,logger,now:()=>now})();

test('purges only due, closed organizations and everything that belongs to them',async()=>{
  const db=fakeDb(seed());
  const results=await run(db);
  const due=results.find(r=>r.id==='due');
  assert.equal(due.status,'purged');
  for(const p of ['organizations/due','buildings/b','rooms/r','tenants/t','tenants/t/rentHistory/h','tenants/legacy','payments/p','teamActivity/a','invite_codes/C','organizationOperations/o','memberships/owner_due'])
    assert.equal(db.store.has(p),false,p);
  for(const p of ['organizations/early','buildings/early','organizations/live','buildings/keep','owners/owner'])assert.ok(db.store.has(p),p);
  const record=db.store.get('purgedOrganizations/due');
  assert.equal(record.closedBy,'owner');assert.equal(record.name,undefined,'no names in the purge record');
  assert.equal(results.find(r=>r.id==='stuck').reason,'active_membership');
  assert.ok(db.store.has('organizations/stuck'));
  assert.equal(results.some(r=>r.id==='early'||r.id==='live'),false,'not due yet');
});

test('a cross-organization link skips the purge instead of deleting another organization\'s data',async()=>{
  const db=fakeDb({...seed(),'payments/foreign':{organizationId:'live',tenantId:'t'}});
  const results=await run(db);
  assert.equal(results.find(r=>r.id==='due').reason,'cross_link');
  assert.ok(db.store.has('buildings/b')&&db.store.has('payments/foreign'));
  // Running again after the data is fixed completes the purge.
  db.store.delete('payments/foreign');
  assert.equal((await run(db)).find(r=>r.id==='due').status,'purged');
});

test('the scheduled function is exported, server-only and runs daily',()=>{
  const api=require('../index');
  const e=api.purgeClosedOrganizations.__endpoint;
  assert.ok(e.scheduleTrigger);assert.equal(e.scheduleTrigger.schedule,'15 3 * * *');
  assert.equal(e.callableTrigger,undefined);assert.equal(e.httpsTrigger,undefined);
});

test('a restore in progress wins over the purge',async()=>{
  const db=fakeDb({...seed(),'organizations/due':{...closed(-1),restoringAt:new Ts(now)}});
  const results=await run(db);
  assert.equal(results.find(r=>r.id==='due').reason,'restoring_or_reopened');
  assert.ok(db.store.has('buildings/b')&&db.store.has('organizations/due'));
  assert.equal(db.store.get('organizations/due').purgeStartedAt,undefined);
});

test('a legacy organization closed by account deletion is purged too',async()=>{
  const db=fakeDb({'organizations/old':{name:'Old',closedAt:new Ts(now-40*DAY),closedBy:'me',closedReason:'accountDeleted',purgeAfter:new Ts(now-DAY)},
    'memberships/x_old':{organizationId:'old',role:'member',status:'revoked'},'rooms/r':{organizationId:'old'},'tenants/t':{roomId:'r'},
    'invite_codes/CODE':{orgId:'old'},'organizations/keep':{name:'Keep'},'rooms/k':{organizationId:'keep'}});
  const results=await run(db);
  assert.equal(results.find(r=>r.id==='old').status,'purged');
  for(const p of ['organizations/old','memberships/x_old','rooms/r','tenants/t','invite_codes/CODE'])assert.equal(db.store.has(p),false,p);
  assert.ok(db.store.has('rooms/k'));
});
