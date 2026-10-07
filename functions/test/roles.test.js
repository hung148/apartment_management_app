const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createRolesHandler} = require('../roles');
const {createTeamHandler} = require('../team');
const {createTeamReadHandler} = require('../team_read');
const {allows, templates} = require('../team_access');

// Same in-memory transaction model as team.test.js (serialized, reads before writes).
class Stamp {constructor(v){this.v=v;} toMillis(){return this.v;} static now(){return new Stamp(1000000);} static fromMillis(v){return new Stamp(v);}}
class CodeError extends Error {constructor(code,message){super(message);this.code=code;}}
class Ref {constructor(name,id){this.path=`${name}/${id}`;this.id=id;}}
class Query {constructor(name,filters=[]){this.name=name;this.filters=filters;} doc(id){return new Ref(this.name,id);} where(k,op,v){assert.equal(op,'==');return new Query(this.name,[...this.filters,[k,v]]);} orderBy(){return this;} startAfter(){return this;} limit(){return this;}}
class DB {
  constructor(seed){this.rows=new Map(Object.entries(seed));this.tail=Promise.resolve();}
  collection(name){return new Query(name);}
  runTransaction(fn){
    const pending=this.tail.then(async()=>{
      const next=new Map([...this.rows].map(([k,v])=>[k,{...v}])); let wrote=false;
      const snap=ref=>({ref,id:ref.id,exists:next.has(ref.path),data:()=>next.get(ref.path)});
      const tx={get:async target=>{assert.equal(wrote,false,'reads before writes');
        if(target instanceof Ref)return snap(target);
        const docs=[...next].filter(([k,v])=>k.startsWith(target.name+'/')&&target.filters.every(([f,x])=>v[f]===x)).map(([k])=>snap(new Ref(target.name,k.split('/')[1])));
        return {docs,size:docs.length};},
        create:(ref,v)=>{wrote=true;assert(!next.has(ref.path),'create over '+ref.path);next.set(ref.path,v);},
        set:(ref,v)=>{wrote=true;next.set(ref.path,v);},
        update:(ref,v)=>{wrote=true;assert(next.has(ref.path));next.set(ref.path,{...next.get(ref.path),...v});}};
      const result=await fn(tx);this.rows=next;return result;
    });this.tail=pending.catch(()=>{});return pending;
  }
}
const membership=(ownerId,role,extra={})=>({organizationId:'org',ownerId,accessVersion:2,status:'active',role,buildingScope:'all',buildingIds:[],...extra});
function fixture(){
  const db=new DB({'organizations/org':{createdBy:'owner',accessVersion:2},
    'memberships/owner_org':membership('owner','owner'),
    'memberships/admin_org':membership('admin','administrator'),
    'memberships/worker_org':membership('worker','receptionist',{buildingScope:'selected',buildingIds:['a']}),
    'memberships/worker2_org':membership('worker2','receptionist',{buildingScope:'selected',buildingIds:['a'],status:'suspended'}),
    'memberships/gone_org':membership('gone','housekeeper',{status:'revoked'}),
    'buildings/a':{organizationId:'org'},
    'staffProfiles/staff':{organizationId:'org',code:'S1',displayName:'Staff',accountId:null,employmentStatus:'active'},
    'staffProfiles/staff2':{organizationId:'org',code:'S2',displayName:'Staff 2',accountId:null,employmentStatus:'active'}});
  const deps={db,Timestamp:Stamp,HttpsError:CodeError};
  const roles=createRolesHandler(deps),team=createTeamHandler(deps),read=createTeamReadHandler(deps);
  let op=0;
  const auth=uid=>uid?{uid,token:{email:`${uid}@example.com`,email_verified:true}}:null;
  const call=(data,uid='owner')=>roles({auth:auth(uid),data:{organizationId:'org',...(data.action!=='list'?{operationId:`op${++op}`}:{}),...data}});
  const teamCall=(data,uid='owner')=>team({auth:auth(uid),data:{organizationId:'org',operationId:`t${++op}`,...data}});
  const readCall=(data,uid)=>read({auth:auth(uid),data:{organizationId:'org',...data}});
  return {db,call,teamCall,readCall};
}
const get=(db,key)=>db.rows.get(key);
const receptionist={...templates.receptionist.grants};

test('list shows the fixed owner, every template and member counts', async()=>{
  const {call}=fixture();
  const r=await call({action:'list'});
  assert.deepEqual(r.roles.map(x=>x.id),Object.keys(templates));
  const owner=r.roles[0];
  assert.equal(owner.fixed,true);assert.equal(owner.canEdit,false);assert.equal(owner.canAssign,false);
  const rec=r.roles.find(x=>x.id==='receptionist');
  assert.equal(rec.members,2);      // active + suspended; revoked does not count
  assert.equal(rec.canDelete,false);
  assert.equal(r.roles.find(x=>x.id==='housekeeper').canDelete,true);
  assert.equal(r.canCreate,true);
});

test('who may open roles: team or role managers only', async()=>{
  const {call}=fixture();
  await assert.rejects(call({action:'list'},'worker'),/team_access_denied/);
  await assert.rejects(call({action:'list'},null),/team_sign_in_required/);
  const admin=await call({action:'list'},'admin');
  assert.equal(admin.canCreate,false);
  assert.ok(admin.roles.every(x=>!x.canEdit));
  assert.equal(admin.roles.find(x=>x.id==='manager').canAssign,true);
  assert.equal(admin.roles.find(x=>x.id==='administrator').canAssign,false);
});

test('editing a role changes everyone who holds it at once', async()=>{
  const {db,call}=fixture();
  const grants={...receptionist,refundPayments:'managed'};
  const r=await call({action:'save',roleId:'receptionist',expectedRevision:0,name:'Front desk',color:'#1e88e5',grants});
  assert.deepEqual(r,{roleId:'receptionist',revision:1});
  for(const key of ['memberships/worker_org','memberships/worker2_org']){
    assert.deepEqual(get(db,key).roleGrants,Object.fromEntries(Object.entries(grants).sort()));
    assert.equal(get(db,key).roleRevision,1);
  }
  assert.equal(allows(get(db,'memberships/worker_org'),'refundPayments',{buildingId:'a'}),true);
  assert.equal(get(db,'orgRoles/org_receptionist').name,'Front desk');
  assert.equal(get(db,'memberships/worker_org').roleName,'Front desk');
  assert.equal(get(db,'orgRoles/org_receptionist').color,'#1E88E5');
  const events=[...db.rows].filter(([k])=>k.startsWith('teamActivity/')).map(([,v])=>v);
  assert.equal(events.at(-1).action,'updateRole');
  assert.equal(events.at(-1).after.members,2);
});

test('two people editing the same role: the second sees "changed"', async()=>{
  const {call}=fixture();
  const save=name=>call({action:'save',roleId:'manager',expectedRevision:0,name,color:'#00897B',grants:{...templates.manager.grants}});
  await save('First');
  await assert.rejects(save('Second'),/role_changed/);
});

test('retry returns the first result; a reused operation with other data is refused', async()=>{
  const {db,call}=fixture();
  const handler=createRolesHandler({db,Timestamp:Stamp,HttpsError:CodeError});
  const data={organizationId:'org',operationId:'same',action:'save',name:'Night shift',color:'#123456',grants:{readBookings:'own'}};
  const auth={uid:'owner',token:{}};
  const first=await handler({auth,data});
  assert.deepEqual(await handler({auth,data}),first);
  assert.match(first.roleId,/^r_[0-9a-f]{16}$/);
  await assert.rejects(handler({auth,data:{...data,name:'Other'}}),/team_operation_reused/);
  assert.equal([...db.rows.keys()].filter(k=>k.startsWith('orgRoles/')).length,1);
});

test('names are required, unique and short; grants must be valid', async()=>{
  const {call}=fixture();
  await call({action:'save',name:'Cleaner',color:'#123456',grants:{readAssignedTasks:'managed'}});
  await assert.rejects(call({action:'save',name:' cleaner ',color:'#123456',grants:{}}),/role_name_exists/);
  await assert.rejects(call({action:'save',name:'',color:'#123456',grants:{}}),/role_invalid_name/);
  // A starter role may keep no name of its own (the app shows the translated one).
  await call({action:'save',roleId:'accountant',expectedRevision:0,name:'  ',color:'#123456',grants:{readBookings:'managed'}});
  await assert.rejects(call({action:'save',name:'x'.repeat(41),color:'#123456',grants:{}}),/role_invalid_name/);
  await assert.rejects(call({action:'save',name:'A',color:'red',grants:{}}),/role_invalid_input/);
  await assert.rejects(call({action:'save',name:'A',color:'#123456',grants:{collectPayments:'own'}}),/role_invalid_grants/);
  await assert.rejects(call({action:'save',roleId:'owner',expectedRevision:0,name:'A',color:'#123456',grants:{}}),/role_invalid_input/);
  await assert.rejects(call({action:'save',roleId:'r_doesnotexist1',expectedRevision:0,name:'A',color:'#123456',grants:{}}),/role_not_found/);
});

test('"manage roles" is a permission the owner can give; holders stay below it', async()=>{
  const {db,call}=fixture();
  await assert.rejects(call({action:'save',name:'Desk',color:'#123456',grants:{readBookings:'all'}},'admin'),/role_edit_denied/);
  // Owner lets administrators manage roles.
  await call({action:'save',roleId:'administrator',expectedRevision:0,name:'Administrator',color:'#3949AB',grants:{...templates.administrator.grants,manageRoles:'all'}});
  assert.equal(get(db,'memberships/admin_org').roleGrants.manageRoles,'all');
  const made=await call({action:'save',name:'Desk',color:'#123456',grants:{readBookings:'all',manageBookings:'own'}},'admin');
  assert.ok(made.roleId);
  // A role that can manage the team is fine; one that can manage roles is owner-only.
  await call({action:'save',name:'Team lead',color:'#123456',grants:{manageTeam:'all',readBookings:'managed'}},'admin');
  await assert.rejects(call({action:'save',name:'Boss',color:'#123456',grants:{manageRoles:'all'}},'admin'),/role_edit_denied/);
  // Cannot change their own role (it can manage roles) or take the permission away from others.
  const list=await call({action:'list'},'admin');
  assert.equal(list.roles.find(x=>x.id==='administrator').canEdit,false);
  await assert.rejects(call({action:'save',roleId:'administrator',expectedRevision:1,name:'Administrator',color:'#3949AB',grants:{...templates.administrator.grants}},'admin'),/role_edit_denied/);
});

test('a role in use cannot be deleted; an unused one disappears and cannot be assigned', async()=>{
  const {call,teamCall}=fixture();
  await assert.rejects(call({action:'delete',roleId:'receptionist',expectedRevision:0}),/role_in_use/);
  const made=await call({action:'save',name:'Temp',color:'#123456',grants:{readBookings:'managed'}});
  // A pending invitation counts as use.
  const inv=await teamCall({action:'invite',staffId:'staff',email:'new@example.com',access:{role:made.roleId,buildingScope:'selected',buildingIds:['a'],permissionOverrides:{}}});
  await assert.rejects(call({action:'delete',roleId:made.roleId,expectedRevision:1}),/role_in_use/);
  await teamCall({action:'revokeInvitation',invitationId:inv.invitationId});
  assert.deepEqual(await call({action:'delete',roleId:made.roleId,expectedRevision:1}),{roleId:made.roleId,deleted:true});
  const list=await call({action:'list'});
  assert.equal(list.roles.some(x=>x.id===made.roleId),false);
  await assert.rejects(teamCall({action:'invite',staffId:'staff',email:'new@example.com',access:{role:made.roleId,buildingScope:'selected',buildingIds:['a'],permissionOverrides:{}}}),/team_role_not_found/);
  // Deleting a template hides it too.
  await call({action:'delete',roleId:'housekeeper',expectedRevision:0});
  assert.equal((await call({action:'list'})).roles.some(x=>x.id==='housekeeper'),false);
});

test('assigning a custom role stores its grants; the invitation gives the grants current at accept', async()=>{
  const {db,call,teamCall,readCall}=fixture();
  const made=await call({action:'save',name:'Nhân viên',color:'#43A047',grants:{readBookings:'managed',manageBookings:'own'}});
  const inv=await teamCall({action:'invite',staffId:'staff2',email:'lan@example.com',access:{role:made.roleId,buildingScope:'selected',buildingIds:['a'],permissionOverrides:{}}});
  await call({action:'save',roleId:made.roleId,expectedRevision:1,name:'Nhân viên',color:'#43A047',grants:{readBookings:'all',manageBookings:'own',createBookings:'managed'}});
  await teamCall({action:'acceptInvitation',invitationId:inv.invitationId},'lan');
  const lan=get(db,'memberships/lan_org');
  assert.equal(lan.role,made.roleId);
  assert.equal(lan.roleRevision,2);
  assert.equal(lan.roleGrants.readBookings,'all');
  assert.equal(lan.roleName,'Nhân viên');
  assert.equal(allows(lan,'createBookings',{buildingId:'a'}),true);
  // myAccess tells the app what the member may do and the role's name.
  const mine=(await readCall({view:'myAccess'},'lan')).record;
  assert.equal(mine.roleName,'Nhân viên');
  assert.equal(mine.grants.manageBookings,'own');
  assert.equal(mine.allProperties,true);
  // Team list shows the name to the owner.
  const team=(await readCall({view:'access'},'owner')).records;
  assert.equal(team.find(x=>x.ownerId==='lan').roleName,'Nhân viên');
  // Template roles assigned before any edit keep following the template.
  await teamCall({action:'setAccess',userId:'worker',status:'active',reason:'r',access:{role:'manager',buildingScope:'selected',buildingIds:['a'],permissionOverrides:{}}});
  assert.equal(get(db,'memberships/worker_org').roleGrants,null);
});

test('an administrator cannot hand out a role stronger than their own', async()=>{
  const {call,teamCall}=fixture();
  const strong=await call({action:'save',name:'Lead',color:'#123456',grants:{manageTeam:'all',readBookings:'managed'}});
  await assert.rejects(teamCall({action:'setAccess',userId:'worker',status:'active',reason:'r',access:{role:strong.roleId,buildingScope:'selected',buildingIds:['a'],permissionOverrides:{}}},'admin'),/team_role_protected/);
  await teamCall({action:'setAccess',userId:'worker',status:'active',reason:'r',access:{role:strong.roleId,buildingScope:'selected',buildingIds:['a'],permissionOverrides:{}}});
});

test('closed and legacy organizations have no roles screen', async()=>{
  const {db,call}=fixture();
  db.rows.get('organizations/org').closedAt=new Stamp(1);
  await assert.rejects(call({action:'list'}),/org_closed/);
  db.rows.get('organizations/org').closedAt=null;db.rows.get('organizations/org').accessVersion=1;
  await assert.rejects(call({action:'list'}),/team_migration_required/);
});
