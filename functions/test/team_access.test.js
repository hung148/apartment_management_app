const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {permissions, permissionScopes, roles, templates, allows, canManageAccessOf, canAssignGrants, canEditRole,
  hasRole, effectiveGrants, parseGrants, canRunOrganization, migrationProposal} = require('../team_access');
const member = role => ({accessVersion:2, organizationId:'org', ownerId:'user',
  status:'active', role, buildingScope:'selected', buildingIds:['a']});

test('every role respects organization, identity, building and status boundaries', () => {
  for (const role of Object.keys(roles)) for (const permission of permissions) {
    const m = member(role);
    // "Own records only" grants need the record (tested below).
    const expected = roles[role].includes(permission) && templates[role].grants[permission] !== 'own';
    assert.equal(allows(m, permission, {organizationId:'org',userId:'user',buildingId:'a'}), expected);
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
  assert.deepEqual(names('TeamPermission'),permissions);
  const ids = source.match(/templateIds = \[([^\]]+)\]/)[1].split(',').map(s=>s.trim().replace(/'/g,'')).filter(Boolean);
  assert.deepEqual(ids,Object.keys(templates));
});

test('the removed viewer role is unknown and grants nothing', () => {
  assert.equal(Object.hasOwn(roles,'viewer'),false);
  for (const p of permissions) assert.equal(allows({...member('viewer'),role:'viewer'},p),false);
});

// ---- R1: roles as data -------------------------------------------------------

test('templates retain operational grants and remove additional-workplace authority', () => {
  // The table before R1 (2026-09-30). manageBookings now also means createBookings,
  // and owner/administrator keep backdating; nothing else changes for current users.
  const old = {
    owner: permissions.filter(p => !p.startsWith('delete')&&!['createBookings','backdateRecords','manageRoles','assignAdditionalWorkplace','changeOrganizationCurrency'].includes(p)),
    manager: ['manageProperty','manageLease','readBookings','manageBookings','collectPayments','overridePrices','readFinancialReports','readOwnActivity'],
    receptionist: ['readBookings','manageBookings','collectPayments','readOwnActivity'],
    housekeeper: ['readAssignedTasks','updateAssignedTasks','readOwnActivity'],
    accountant: ['readBookings','collectPayments','refundPayments','readFinancialReports','readOwnActivity'],
  };
  old.administrator = old.owner;
  for (const [role, list] of Object.entries(old)) {
    const expected = new Set(list);
    if (expected.has('manageBookings')) expected.add('createBookings');
    if (['owner','administrator'].includes(role)) expected.add('backdateRecords');
    if (role === 'owner') { expected.add('changeOrganizationCurrency'); expected.add('manageRoles');for(const p of permissions.filter(p=>p.startsWith('delete')))expected.add(p); }
    assert.deepEqual(new Set(Object.keys(templates[role].grants)), expected, role);
    for (const s of Object.values(templates[role].grants)) assert.ok(['all','managed'].includes(s));
  }
});

test('every template grant uses a scope its permission allows', () => {
  for (const [role, t] of Object.entries(templates)) for (const [p, s] of Object.entries(t.grants)) {
    assert.ok(permissionScopes[p]?.includes(s), `${role}.${p}=${s}`);
  }
});

test('"own records only" needs the record; created by or in charge of the member', () => {
  const m = {...member('staff'), staffId:'S1'};
  const ctx = {organizationId:'org',userId:'user',buildingId:'a'};
  assert.equal(allows(m,'manageBookings',ctx), false);
  assert.equal(allows(m,'manageBookings',{...ctx,anyRecord:true}), true);
  assert.equal(allows(m,'manageBookings',{...ctx,record:{createdBy:'user'}}), true);
  assert.equal(allows(m,'manageBookings',{...ctx,record:{createdBy:'someone',staffInChargeId:'S1'}}), true);
  assert.equal(allows(m,'manageBookings',{...ctx,record:{createdBy:'someone'}}), false);
  assert.equal(allows({...m,staffId:''},'manageBookings',{...ctx,record:{createdBy:'x',staffInChargeId:''}}), false);
  // Still inside their properties.
  assert.equal(allows(m,'manageBookings',{...ctx,buildingId:'b',record:{createdBy:'user'}}), false);
  // Non-own grants ignore the record.
  assert.equal(allows(m,'readBookings',{...ctx,record:{createdBy:'someone'}}), true);
});

test('"All properties" reaches outside the member\'s list only where it is a choice', () => {
  const m = {...member('r_custom'), roleGrants:{readBookings:'all', createBookings:'managed', exportData:'all'}};
  assert.equal(allows(m,'readBookings',{buildingId:'b'}), true);
  assert.equal(allows(m,'createBookings',{buildingId:'b'}), false);
  assert.equal(allows(m,'createBookings',{buildingId:'a'}), true);
  // On/off organization permissions keep the property list when a building is named.
  assert.equal(allows(m,'exportData',{buildingId:'b'}), false);
  assert.equal(allows(m,'exportData'), true);
  assert.equal(allows(m,'manageTeam'), false);
});

test('a grants copy replaces the template; malformed grants are cleaned; unknown roles wait', () => {
  const edited = {...member('receptionist'), roleGrants:{readBookings:'managed', bogus:'all', collectPayments:'own', refundPayments:'managed'}};
  assert.equal(allows(edited,'refundPayments',{buildingId:'a'}), true);
  assert.equal(allows(edited,'collectPayments',{buildingId:'a'}), false); // 'own' is not allowed for payments
  assert.equal(allows(edited,'manageBookings',{buildingId:'a'}), false);
  assert.deepEqual(effectiveGrants(edited), {readBookings:'managed', refundPayments:'managed'});
  assert.equal(hasRole(member('r_missing')), false);
  assert.equal(hasRole({...member('r_x'), roleGrants:{}}), true);
  assert.equal(hasRole(member('staff')), true);
  assert.equal(hasRole({...member('owner'), roleGrants:{}}), true);
  assert.deepEqual(effectiveGrants({...member('owner'), roleGrants:{}}), {...templates.owner.grants});
  // A null copy (template role assigned before it was edited) follows the template.
  assert.equal(allows({...member('manager'), roleGrants:null},'manageProperty',{buildingId:'a'}), true);
});

test('parseGrants rejects unknown permissions and unsupported scopes', () => {
  assert.deepEqual(parseGrants({readBookings:'own', manageTeam:'all'}), {manageTeam:'all', readBookings:'own'});
  for (const bad of [null, [], 'x', {readBookings:'everything'}, {nope:'all'}, {manageTeam:'managed'}, {collectPayments:'own'}]) {
    assert.equal(parseGrants(bad), null);
  }
});

test('only the owner gives or removes "manage roles"; holders assign roles up to their own grants', () => {
  const all = role => ({...member(role), buildingScope:'all', buildingIds:[]});
  const owner = all('owner'), admin = all('administrator');
  const roleManager = {...all('r_rm'), roleGrants:{...templates.administrator.grants, manageRoles:'all'}};
  const teamRole = {...templates.administrator.grants};
  const rolesRole = {...teamRole, manageRoles:'all'};
  const plain = {readBookings:'all', createBookings:'managed'};
  // Assigning
  assert.equal(canAssignGrants(owner, rolesRole), true);
  assert.equal(canAssignGrants(roleManager, teamRole), true);
  assert.equal(canAssignGrants(roleManager, rolesRole), false);
  assert.equal(canAssignGrants(admin, teamRole), false);      // unchanged: admins cannot make admins
  assert.equal(canAssignGrants(admin, plain), true);          // managed over all properties = all
  assert.equal(canAssignGrants({...admin, buildingScope:'selected', buildingIds:['a']}, plain), false);
  assert.equal(canAssignGrants(admin, {...plain, manageRoles:'all'}), false);
  // Editing role definitions
  assert.equal(canEditRole(admin, null, plain), false);        // needs manageRoles
  assert.equal(canEditRole(roleManager, null, plain), true);
  const {exportData, ...lessTeam} = teamRole;
  assert.equal(canEditRole(roleManager, teamRole, lessTeam), true);
  assert.equal(canEditRole(roleManager, null, rolesRole), false);
  assert.equal(canEditRole(roleManager, rolesRole, teamRole), false); // cannot remove it from others either
  assert.equal(canEditRole(owner, rolesRole, teamRole), true);
  const small = {...all('r_small'), roleGrants:{manageRoles:'all', manageTeam:'all', readBookings:'managed'}};
  assert.equal(canEditRole(small, null, {readBookings:'all'}), true);
  assert.equal(canEditRole(small, null, {refundPayments:'managed'}), false); // exceeds own
  // Managing members
  assert.equal(canManageAccessOf(roleManager, admin), true);
  assert.equal(canManageAccessOf(roleManager, {...roleManager}), false);
  assert.equal(canManageAccessOf(owner, roleManager), true);
  assert.equal(canManageAccessOf(roleManager, 'owner'), false);
});

test('account hand-over candidates can run the organization', () => {
  const all = role => ({...member(role), buildingScope:'all', buildingIds:[]});
  assert.equal(canRunOrganization(all('administrator')), true);
  assert.equal(canRunOrganization(member('administrator')), false);
  assert.equal(canRunOrganization(all('manager')), false);
  assert.equal(canRunOrganization({...all('r_x'), roleGrants:{manageOrganization:'all', manageTeam:'all'}}), true);
  assert.equal(canRunOrganization({...all('administrator'), status:'suspended'}), false);
  assert.equal(canRunOrganization(all('owner')), false);
});
