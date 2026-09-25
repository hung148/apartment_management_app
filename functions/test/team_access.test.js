const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {permissions, roles, allows, canManageAccessOf, migrationProposal} = require('../team_access');
const member = role => ({accessVersion:2, organizationId:'org', ownerId:'user',
  status:'active', role, buildingScope:'selected', buildingIds:['a']});

test('every role respects organization, identity, building and status boundaries', () => {
  for (const role of Object.keys(roles)) for (const permission of permissions) {
    const m = member(role);
    assert.equal(allows(m, permission, {organizationId:'org',userId:'user',buildingId:'a'}), roles[role].includes(permission));
    for (const context of [{organizationId:'other'}, {userId:'other'}, {buildingId:'b'}, {buildingId:''}]) {
      assert.equal(allows(m, permission, context), false);
    }
    for (const status of ['invited','suspended','revoked','assignmentRequired']) {
      assert.equal(allows({...m,status}, permission), false);
    }
  }
});
test('unknown, legacy, missing and malformed roles fail closed', () => {
  for (const m of [null, {}, {...member('owner'),accessVersion:1}, member('member'), member('admin'), member('toString'), member('__proto__')]) {
    for (const p of permissions) assert.equal(allows(m,p),false);
  }
  assert.equal(allows(member('owner'),'unknown'),false);
});
test('empty scope is denied and explicit all includes future buildings', () => {
  const m = {...member('manager'),buildingIds:[]};
  assert.equal(allows(m,'manageProperty',{buildingId:'new'}),false);
  assert.equal(allows({...m,buildingScope:'all'},'manageProperty',{buildingId:'new'}),true);
  assert.equal(allows({...m,buildingScope:'bad',buildingIds:['a']},'manageProperty',{buildingId:'a'}),false);
  assert.equal(allows({...member('owner'),buildingScope:'bad'},'manageTeam'),false);
});
test('only approved overrides apply and cannot bypass scope', () => {
  const m = {...member('receptionist'), permissionOverrides:{refundPayments:true,manageTeam:true}};
  assert.equal(allows(m,'refundPayments',{buildingId:'a'}),true);
  assert.equal(allows(m,'refundPayments',{buildingId:'b'}),false);
  assert.equal(allows(m,'manageTeam'),false);
  assert.equal(allows({...member('manager'),permissionOverrides:{overridePrices:false}},'overridePrices'),false);
});
test('administrator cannot change peer or owner access', () => {
  assert.equal(canManageAccessOf(member('administrator'),'administrator'),false);
  assert.equal(canManageAccessOf(member('administrator'),'owner'),false);
  assert.equal(canManageAccessOf(member('owner'),'administrator'),true);
  assert.equal(canManageAccessOf(member('manager'),'receptionist'),false);
});
test('migration proposes roles without modifying input or promoting members', () => {
  const org = {id:'org',createdBy:'owner'};
  const members = ['owner','admin','member'].map((ownerId,i)=>({id:String(i),organizationId:'org',ownerId,role:i===2?'member':'admin',status:'active'}));
  const before = JSON.stringify(members);
  const result = migrationProposal(org,members);
  assert.deepEqual(result.proposals.map(p=>p.proposed.role),['owner','administrator',null]);
  assert.equal(result.proposals[2].proposed.status,'assignmentRequired');
  assert.equal(result.proposals[2].proposed.buildingScope,'selected');
  assert.deepEqual(result.issues,[]);
  assert.equal(JSON.stringify(members),before);
  assert.deepEqual(migrationProposal(org,members),result);
});
test('migration preserves v2 assignments and flags missing owner/duplicate accounts', () => {
  const m = {...member('receptionist'),id:'m'};
  assert.equal(migrationProposal({id:'org',createdBy:'user'},[m]).proposals[0].action,'unchanged');
  const result = migrationProposal({id:'org',createdBy:'missing'},[m,{...m,id:'duplicate'}]);
  assert.ok(result.issues.some(i=>i.reason==='missingActiveOwner'));
  assert.ok(result.issues.some(i=>i.reason==='missingOrDuplicateAccount'));
});
test('Dart and server policies expose the same permission and role names', () => {
  const source = fs.readFileSync(path.join(__dirname,'../../lib/models/team_access.dart'),'utf8');
  const names = name => source.match(new RegExp(`enum ${name} \\{([^}]+)\\}`))[1].split(',').map(s=>s.trim()).filter(Boolean);
  assert.deepEqual(names('TeamRole'),Object.keys(roles));
  assert.deepEqual(names('TeamPermission'),permissions);
});
