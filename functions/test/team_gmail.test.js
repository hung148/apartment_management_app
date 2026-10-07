// R2: staff added by Gmail, auto-join on sign-in, Gmail typo fix, re-joining.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {createTeamHandler} = require('../team');
const {createClaimInvitationsHandler} = require('../team_claim');
const {createRolesHandler} = require('../roles');

class Stamp {constructor(v){this.v=v;} toMillis(){return this.v;} static now(){return new Stamp(Date.now());} static fromMillis(v){return new Stamp(v);}}
class CodeError extends Error {constructor(code,message){super(message);this.code=code;}}
class Ref {constructor(name,id){this.path=`${name}/${id}`;this.id=id;}}
class DB {
  constructor(seed){this.rows=new Map(Object.entries(seed));this.tail=Promise.resolve();}
  snap(rows,ref){return {ref,id:ref.id,exists:rows.has(ref.path),data:()=>rows.get(ref.path)};}
  query(rows,q){const docs=[...rows].filter(([k,v])=>k.startsWith(q.name+'/')&&q.filters.every(([f,x])=>v[f]===x)).map(([k])=>this.snap(rows,new Ref(q.name,k.split('/')[1]))).slice(0,q.max);return {docs,size:docs.length};}
  collection(name){const db=this;const make=(filters,max=Infinity)=>({name,filters,max,doc:id=>{const r=new Ref(name,id);r.get=async()=>db.snap(db.rows,r);return r;},
    where:(k,op,v)=>{assert.equal(op,'==');return make([...filters,[k,v]],max);},limit:n=>make(filters,n),
    get:async()=>db.query(db.rows,{name,filters,max})});return make([]);}
  runTransaction(fn){
    const pending=this.tail.then(async()=>{
      const next=new Map([...this.rows].map(([k,v])=>[k,{...v}])); let wrote=false;
      const tx={get:async t=>{assert.equal(wrote,false,'reads before writes');return t instanceof Ref?this.snap(next,t):this.query(next,t);},
        create:(ref,v)=>{wrote=true;assert(!next.has(ref.path),'exists '+ref.path);next.set(ref.path,v);},
        set:(ref,v)=>{wrote=true;next.set(ref.path,v);},
        update:(ref,v)=>{wrote=true;assert(next.has(ref.path));next.set(ref.path,{...next.get(ref.path),...v});}};
      const result=await fn(tx);this.rows=next;return result;
    });this.tail=pending.catch(()=>{});return pending;
  }
}
const membership=(ownerId,role,extra={})=>({organizationId:'org',ownerId,accessVersion:2,status:'active',role,buildingScope:'all',buildingIds:[],email:`${ownerId}@example.com`,...extra});
function fixture(){
  const db=new DB({
    'organizations/org':{createdBy:'owner',accessVersion:2,name:'Homestay A'},
    'organizations/org2':{createdBy:'owner2',accessVersion:2,name:'Homestay B'},
    'memberships/owner_org':membership('owner','owner'),
    'memberships/owner2_org2':{...membership('owner2','owner'),organizationId:'org2'},
    'memberships/admin_org':membership('admin','administrator'),
    'buildings/a':{organizationId:'org'},'buildings/b2':{organizationId:'org2'},
    'staffProfiles/s1':{organizationId:'org',code:'S01',displayName:'Old',accountId:null,employmentStatus:'active'},
  });
  const deps={db,Timestamp:Stamp,HttpsError:CodeError};
  const team=createTeamHandler(deps), roles=createRolesHandler(deps);
  const claim=createClaimInvitationsHandler({db,HttpsError:CodeError,team});
  let op=0;
  const auth=(uid,email=`${uid}@example.com`,verified=true)=>uid?{uid,token:{email,email_verified:verified}}:null;
  const call=(data,uid='owner',org='org')=>team({auth:auth(uid),data:{organizationId:org,operationId:`op${++op}`,...data}});
  const signIn=(uid,email,verified=true)=>claim({auth:auth(uid,email,verified),data:{}});
  return {db,call,signIn,roles,auth};
}
const access=(role='receptionist')=>({role,buildingScope:'selected',buildingIds:['a'],permissionOverrides:{}});
const add=(email,extra={})=>({action:'addStaff',profile:{displayName:'Lan',email,phone:'0900',...extra},access:access()});

test('adding staff by Gmail creates the profile and a pre-approval that never expires', async()=>{
  const {db,call}=fixture();
  const r=await call(add('Lan@Gmail.com'));
  assert.equal(r.code,'S02');
  const staff=db.rows.get(`staffProfiles/${r.staffId}`);
  assert.equal(staff.email,'lan@gmail.com');assert.equal(staff.accountId,null);
  const inv=db.rows.get(`teamInvitations/${r.invitationId}`);
  assert.equal(inv.email,'lan@gmail.com');assert.equal(inv.expiresAt,null);assert.equal(inv.status,'pending');assert.equal(inv.kind,'gmail');
  // Same Gmail twice is refused.
  await assert.rejects(call(add('lan@gmail.com')),/team_email_already_invited/);
  await assert.rejects(call(add('not-an-email')),/team_invalid_email/);
  await assert.rejects(call(add('x@gmail.com',{code:'S9'})),/team_invalid_profile/);
});

test('signing in with that Gmail joins automatically; other Gmails and unverified emails do not', async()=>{
  const {db,call,signIn}=fixture();
  const r=await call(add('lan@gmail.com'));
  assert.deepEqual(await signIn('stranger','someone@gmail.com'),{results:[]});
  assert.deepEqual(await signIn('lan','lan@gmail.com',false),{results:[],needsVerifiedEmail:true});
  const joined=await signIn('lan','LAN@gmail.com');
  assert.deepEqual(joined.results,[{organizationId:'org',organizationName:'Homestay A',status:'joined'}]);
  const m=db.rows.get('memberships/lan_org');
  assert.equal(m.status,'active');assert.equal(m.role,'receptionist');assert.equal(m.staffId,r.staffId);assert.equal(m.displayName,'Lan');
  assert.equal(db.rows.get(`staffProfiles/${r.staffId}`).accountId,'lan');
  assert.equal(db.rows.get(`teamInvitations/${r.invitationId}`).status,'accepted');
  // Signing in again does nothing more.
  assert.deepEqual(await signIn('lan','lan@gmail.com'),{results:[]});
});

test('the same owner cannot add a staff Gmail to a second organization', async()=>{
 const {db,call,signIn}=fixture();db.rows.set('organizations/org2',{createdBy:'owner',accessVersion:2,name:'Homestay B'});db.rows.set('memberships/owner_org2',{...membership('owner','owner'),organizationId:'org2'});
 await call(add('lan@gmail.com'));
 await assert.rejects(call({action:'addStaff',profile:{displayName:'Lan',email:'lan@gmail.com'},access:{...access(),buildingIds:['b2']}},'owner','org2'),/team_other_employer/);
 const result=await signIn('lan','lan@gmail.com');assert.deepEqual(result.results.map(x=>x.status),['joined']);assert.ok(db.rows.has('memberships/lan_org'));assert.equal(db.rows.has('memberships/lan_org2'),false);
});

test('a typo can be fixed before the first sign-in; the old Gmail no longer works', async()=>{
  const {db,call,signIn}=fixture();
  const r=await call(add('lann@gmail.com'));
  await call({action:'changeInvitationEmail',invitationId:r.invitationId,email:'lan@gmail.com'});
  assert.equal(db.rows.get(`staffProfiles/${r.staffId}`).email,'lan@gmail.com');
  assert.deepEqual((await signIn('typo','lann@gmail.com')).results,[]);
  assert.equal((await signIn('lan','lan@gmail.com')).results[0].status,'joined');
  // After joining it cannot be changed any more.
  await assert.rejects(call({action:'changeInvitationEmail',invitationId:r.invitationId,email:'x@gmail.com'}),/team_invitation_closed/);
  // Nor changed to an address that is already a member.
  const r2=await call(add('mai@gmail.com'));
  await assert.rejects(call({action:'changeInvitationEmail',invitationId:r2.invitationId,email:'lan@gmail.com'}),/team_email_already_member/);
});

test('removed before first sign-in: the Gmail cannot join', async()=>{
  const {call,signIn}=fixture();
  const r=await call(add('lan@gmail.com'));
  await call({action:'revokeInvitation',invitationId:r.invitationId});
  assert.deepEqual((await signIn('lan','lan@gmail.com')).results,[]);
});

test('a removed person added again can join again; the old profile is unlinked', async()=>{
  const {db,call,signIn}=fixture();
  const first=await call(add('lan@gmail.com'));
  await signIn('lan','lan@gmail.com');
  await call({action:'setAccess',userId:'lan',status:'revoked',reason:'left',access:access()});
  await call(add('lan@gmail.com',{displayName:'Lan B'})); // a revoked member may be added again
  const pending=[...db.rows].filter(([k,v])=>k.startsWith('teamInvitations/')&&v.status==='pending');
  assert.equal(pending.length,1);
  const r=await signIn('lan','lan@gmail.com');
  assert.equal(r.results[0].status,'joined');
  assert.equal(db.rows.get('memberships/lan_org').status,'active');
  // One person keeps one profile: the old one is reused and linked again.
  assert.equal(db.rows.get('memberships/lan_org').staffId,first.staffId);
  assert.equal(db.rows.get(`staffProfiles/${first.staffId}`).accountId,'lan');
  assert.equal(db.rows.get(`staffProfiles/${first.staffId}`).displayName,'Lan B');
  assert.equal([...db.rows].filter(([k,v])=>k.startsWith('staffProfiles/')&&v.email==='lan@gmail.com').length,1);
});

test('a removed pre-approval added again reuses its unused profile', async()=>{
  const {db,call,signIn}=fixture();
  const first=await call(add('lan@gmail.com'));
  await call({action:'revokeInvitation',invitationId:first.invitationId});
  const second=await call(add('lan@gmail.com'));
  assert.equal(second.staffId,first.staffId);assert.equal(second.code,first.code);
  assert.equal((await signIn('lan','lan@gmail.com')).results[0].status,'joined');
  assert.equal([...db.rows].filter(([k,v])=>k.startsWith('staffProfiles/')&&v.email==='lan@gmail.com').length,1);
});

test('adding an active member again is refused; claims skip instead of failing when something changed', async()=>{
  const {db,call,signIn,roles}=fixture();
  await call(add('lan@gmail.com'));
  await signIn('lan','lan@gmail.com');
  await assert.rejects(call(add('lan@gmail.com')),/team_email_already_member/);
  // Pre-approved with a role that is later deleted: skipped, stays pending for the owner.
  const made=await roles({auth:{uid:'owner',token:{}},data:{organizationId:'org',operationId:'r1',action:'save',name:'Temp',color:'#123456',grants:{readBookings:'managed'}}});
  const inv=await call({...add('mai@gmail.com'),access:{...access(),role:made.roleId}});
  db.rows.get(`orgRoles/org_${made.roleId}`).deletedAt=new Stamp(1);
  const r=await signIn('mai','mai@gmail.com');
  assert.equal(r.results[0].status,'skipped');assert.match(r.results[0].reason,/team_invitation_role_removed/);
  assert.equal(db.rows.get(`teamInvitations/${inv.invitationId}`).status,'pending');
});

test('only team managers add staff, and never above their own level', async()=>{
  const {db,call}=fixture();
  db.rows.set('memberships/rec_org',membership('rec','receptionist'));
  await assert.rejects(call(add('x@gmail.com'),'rec'),/team_access_denied/);
  await assert.rejects(call({...add('x@gmail.com'),access:access('administrator')},'admin'),/team_role_protected/);
  await call(add('x@gmail.com'),'admin');
});

test('manager pre-approval cannot be followed by an owner-approved second workplace',async()=>{
 const {db,call,signIn}=fixture();db.rows.set('organizations/org2',{createdBy:'owner',accessVersion:2,name:'Second'});db.rows.set('memberships/owner_org2',{...membership('owner','owner'),organizationId:'org2'});
 await call(add('worker@gmail.com'),'admin');
 await assert.rejects(call({action:'addStaff',profile:{displayName:'Worker',email:'worker@gmail.com'},access:{...access(),buildingIds:['b2']}},'owner','org2'),/team_other_employer/);
 const result=await signIn('worker','worker@gmail.com');assert.deepEqual(result.results.map(r=>r.status),['joined']);assert.equal(db.rows.has('memberships/worker_org2'),false);
});
test('other-owner invitation is refused without creating a staff profile',async()=>{
 const {db,call}=fixture();await call(add('worker@gmail.com'));
 const before=db.rows.size;
 await assert.rejects(call({action:'addStaff',profile:{displayName:'Worker',email:'worker@gmail.com'},access:{...access(),buildingIds:['b2']}},'owner2','org2'),/team_other_employer/);
 assert.equal(db.rows.size,before);
});
