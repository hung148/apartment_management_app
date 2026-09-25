const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createTeamHandler} = require('../team');
class Stamp {constructor(v){this.v=v;} toMillis(){return this.v;} static now(){return new Stamp(1000000);} static fromMillis(v){return new Stamp(v);}}
class CodeError extends Error {constructor(code,message){super(message);this.code=code;}}
class Ref {constructor(name,id){this.path=`${name}/${id}`;this.id=id;}}
class Query {constructor(name,filters=[]){this.name=name;this.filters=filters;} doc(id){return new Ref(this.name,id);} where(k,op,v){assert.equal(op,'==');return new Query(this.name,[...this.filters,[k,v]]);}}
class DB {
  constructor(seed){this.rows=new Map(Object.entries(seed));this.tail=Promise.resolve();}
  collection(name){return new Query(name);}
  runTransaction(fn){
    const pending=this.tail.then(async()=>{
      const next=new Map([...this.rows].map(([k,v])=>[k,{...v}])); let wrote=false;
      const snap=ref=>({ref,id:ref.id,exists:next.has(ref.path),data:()=>next.get(ref.path)});
      const tx={get:async target=>{assert.equal(wrote,false,'reads before writes');
        if(target instanceof Ref)return snap(target);
        return {docs:[...next].filter(([k,v])=>k.startsWith(target.name+'/')&&target.filters.every(([f,x])=>v[f]===x)).map(([k])=>snap(new Ref(target.name,k.split('/')[1])))};},
        create:(ref,v)=>{wrote=true;assert(!next.has(ref.path));next.set(ref.path,v);},
        set:(ref,v)=>{wrote=true;next.set(ref.path,v);},
        update:(ref,v)=>{wrote=true;assert(next.has(ref.path));next.set(ref.path,{...next.get(ref.path),...v});}};
      const result=await fn(tx);this.rows=next;return result;
    });this.tail=pending.catch(()=>{});return pending;
  }
}
const access=(role='receptionist')=>({role,buildingScope:'selected',buildingIds:['a'],permissionOverrides:{}});
const membership=(ownerId,role)=>({organizationId:'org',ownerId,accessVersion:2,status:'active',role,buildingScope:'all',buildingIds:[]});
function fixture(){
  const db=new DB({'organizations/org':{createdBy:'owner',accessVersion:2},
    'memberships/owner_org':membership('owner','owner'),
    'memberships/admin_org':membership('admin','administrator'),
    'memberships/peer_org':membership('peer','administrator'),
    'memberships/worker_org':membership('worker','receptionist'),
    'buildings/a':{organizationId:'org'},'buildings/foreign':{organizationId:'other'},
    'staffProfiles/staff':{organizationId:'org',code:'S1',displayName:'Staff',accountId:null,employmentStatus:'active'},
    'invite_codes/CODE':{orgId:'org'}});
  const handler=createTeamHandler({db,Timestamp:Stamp,HttpsError:CodeError});
  let operation=0;
  const call=(data,uid='owner',token={email:`${uid}@example.com`,email_verified:true})=>handler({auth:uid?{uid,token}:null,data:{organizationId:'org',operationId:`op${++operation}`,...data}});
  return {db,call};
}
const invite={action:'invite',staffId:'staff',email:'new@example.com',access:access()};
const events=db=>[...db.rows].filter(([k])=>k.startsWith('teamActivity/'));

test('staff without account can be created and edited, with an atomic audit record',async()=>{
  const {db,call}=fixture();
  const r=await call({action:'saveStaff',profile:{displayName:'Cleaner',code:'S2'}});
  assert.equal(db.rows.get(`staffProfiles/${r.staffId}`).accountId,null);
  await call({action:'saveStaff',staffId:r.staffId,profile:{displayName:'Former cleaner',code:'S2',employmentStatus:'inactive'}});
  assert.equal(db.rows.get(`staffProfiles/${r.staffId}`).employmentStatus,'inactive');
  assert.equal(events(db).length,2);
  await assert.rejects(call({action:'saveStaff',profile:{displayName:'Duplicate',code:'S2'}}),/team_staff_code_exists/);
  await assert.rejects(call({action:'saveStaff',profile:{displayName:'Bad',code:'S3',accountId:'owner'}}),/team_invalid_profile/);
});
test('invitation accepts verified intended recipient only and links one staff/account',async()=>{
  const {db,call}=fixture(); const {invitationId}=await call(invite);
  await assert.rejects(call({action:'acceptInvitation',invitationId},'wrong'),/team_invitation_recipient/);
  await assert.rejects(call({action:'acceptInvitation',invitationId},'new',{email:'new@example.com',email_verified:false}),/team_verified_email_required/);
  await call({action:'acceptInvitation',invitationId},'new');
  assert.equal(db.rows.get('memberships/new_org').role,'receptionist');
  assert.equal(db.rows.get('staffProfiles/staff').accountId,'new');
  assert.equal(db.rows.get(`teamInvitations/${invitationId}`).status,'accepted');
  assert.equal(events(db).length,2);
});
test('exact retries never duplicate invitations, accounts or audit entries',async()=>{
  const {db,call}=fixture(); const req={...invite,operationId:'same'};
  const a=await call(req);assert.deepEqual(await call(req),a);
  const accept={action:'acceptInvitation',invitationId:a.invitationId,operationId:'accept'};
  const b=await call(accept,'new');assert.deepEqual(await call(accept,'new'),b);
  assert.equal(events(db).length,2);
  await assert.rejects(call({...req,email:'other@example.com'}),/team_operation_reused/);
});
test('expired and revoked invitations cannot be accepted',async()=>{
  for(const state of ['expired','revoked']){
    const {db,call}=fixture();const {invitationId}=await call(invite);
    if(state==='revoked')await call({action:'revokeInvitation',invitationId});
    else db.rows.get(`teamInvitations/${invitationId}`).expiresAt=Stamp.fromMillis(1);
    await assert.rejects(call({action:'acceptInvitation',invitationId},'new'),/team_invitation_closed/);
    assert(!db.rows.has('memberships/new_org'));
  }
});
test('suspended inviter invalidates outstanding invitations',async()=>{
  const {db,call}=fixture();const {invitationId}=await call(invite,'admin');
  db.rows.get('memberships/admin_org').status='suspended';
  await assert.rejects(call({action:'acceptInvitation',invitationId},'new'),/team_inviter_access_changed/);
});
test('invitation cannot overwrite existing or revoked membership',async()=>{
  const {db,call}=fixture();const {invitationId}=await call(invite);
  db.rows.set('memberships/new_org',{...membership('new','viewer'),status:'revoked'});
  await assert.rejects(call({action:'acceptInvitation',invitationId},'new'),/team_existing_access/);
  assert.equal(db.rows.get('memberships/new_org').status,'revoked');
});
test('concurrent invitations to one staff profile cannot link two accounts',async()=>{
  const {db,call}=fixture();const a=await call(invite);const b=await call({...invite,email:'second@example.com'});
  const results=await Promise.allSettled([call({action:'acceptInvitation',invitationId:a.invitationId},'new'),call({action:'acceptInvitation',invitationId:b.invitationId},'second')]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal([...db.rows.keys()].filter(k=>['memberships/new_org','memberships/second_org'].includes(k)).length,1);
});
test('join code creates pending request and no membership until administrator approves',async()=>{
  const {db,call}=fixture();const r=await call({action:'requestAccess',inviteCode:'CODE',displayName:'New'},'new');
  assert(!db.rows.has('memberships/new_org'));
  await call({action:'reviewRequest',requestId:r.requestId,decision:'approve',staffId:'staff',access:access()},'admin');
  assert.equal(db.rows.get('memberships/new_org').status,'active');
  assert.equal(db.rows.get(`teamRequests/${r.requestId}`).status,'approved');
});
test('rejected request grants no access and cannot later be approved',async()=>{
  const {db,call}=fixture();const r=await call({action:'requestAccess',inviteCode:'CODE',displayName:'New'},'new');
  await call({action:'reviewRequest',requestId:r.requestId,decision:'reject'});
  await assert.rejects(call({action:'reviewRequest',requestId:r.requestId,decision:'approve',staffId:'staff',access:access()}),/team_request_closed/);
  assert(!db.rows.has('memberships/new_org'));
});
test('cross-organization buildings, staff, and invalid overrides are rejected',async()=>{
  const {db,call}=fixture();
  await assert.rejects(call({...invite,access:{...access(),buildingIds:['foreign']}}),/team_record_not_found/);
  db.rows.get('staffProfiles/staff').organizationId='other';
  await assert.rejects(call(invite),/team_record_not_found/);
  await assert.rejects(call({...invite,access:{...access(),permissionOverrides:{manageTeam:true}}}),/team_invalid_override/);
  assert.equal(events(db).length,0);
});
test('generic member/owner invitations and administrator peer grants are rejected',async()=>{
  const {call}=fixture();
  for(const role of ['member','admin','owner','toString'])await assert.rejects(call({...invite,access:access(role)}),/team_invalid_access/);
  await assert.rejects(call({...invite,access:access('administrator')},'admin'),/team_role_protected/);
});
test('staff management rejects unauthenticated, legacy, restricted and suspended actors',async()=>{
  const {db,call}=fixture();
  await assert.rejects(call(invite,null),/team_sign_in_required/);
  await assert.rejects(call(invite,'worker'),/team_access_denied/);
  db.rows.get('memberships/admin_org').buildingScope='selected';
  await assert.rejects(call(invite,'admin'),/team_all_buildings_required/);
  db.rows.get('memberships/owner_org').status='suspended';
  await assert.rejects(call(invite),/team_access_denied/);
  db.rows.get('memberships/admin_org').accessVersion=1;
  await assert.rejects(call(invite,'admin'),/team_access_denied/);
});
test('organization creator never bypasses required migration',async()=>{
  const {db,call}=fixture();delete db.rows.get('organizations/org').accessVersion;
  await assert.rejects(call(invite),/team_migration_required/);
  assert.equal(events(db).length,0);
});
test('access changes preserve history, require reason, and protect self/owner/administrator',async()=>{
  const {db,call}=fixture();const req={action:'setAccess',userId:'worker',status:'suspended',access:access(),reason:'Access review'};
  await call(req,'admin');
  assert.equal(db.rows.get('memberships/worker_org').status,'suspended');
  assert.equal(events(db)[0][1].before.status,'active');
  assert.equal(events(db)[0][1].after.status,'suspended');
  await assert.rejects(call({...req,userId:'owner'},'admin'),/team_role_protected/);
  await assert.rejects(call({...req,userId:'peer'},'admin'),/team_role_protected/);
  await assert.rejects(call({...req,userId:'admin'},'admin'),/team_self_access_change/);
  await assert.rejects(call({...req,reason:''}),/team_invalid_input/);
});
test('administrator cannot edit staff profile belonging to owner',async()=>{
  const {db,call}=fixture();db.rows.get('staffProfiles/staff').accountId='owner';
  await assert.rejects(call({action:'saveStaff',staffId:'staff',profile:{displayName:'Changed',code:'S1'}},'admin'),/team_role_protected/);
});
test('revocation before retry is still checked and cannot replay privileged operation',async()=>{
  const {db,call}=fixture();const req={...invite,operationId:'fixed'};await call(req,'admin');
  db.rows.get('memberships/admin_org').status='revoked';
  await assert.rejects(call(req,'admin'),/team_access_denied/);
});
test('administrator cannot grant default capabilities they have explicitly lost',async()=>{
  const {db,call}=fixture();db.rows.get('memberships/admin_org').permissionOverrides={refundPayments:false};
  await assert.rejects(call({...invite,access:access('accountant')},'admin'),/team_grant_exceeds_access/);
});
test('callable wrapper forwards authentication and validates input',async()=>{
  const {mutateTeam}=require('../index');
  await assert.rejects(mutateTeam.run({data:{}}),e=>e.code==='unauthenticated');
  await assert.rejects(mutateTeam.run({auth:{uid:'owner'},data:{}}),e=>e.code==='invalid-argument');
});
