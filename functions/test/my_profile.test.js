const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createMyProfileHandler}=require('../my_profile');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const seed=()=>({
  'owners/me':{name:'Old',email:'old@x.com',createdAt:new Ts(1)},
  'memberships/me_v2':{ownerId:'me',organizationId:'v2',accessVersion:2,role:'manager',status:'active',displayName:'Old',email:'old@x.com'},
  'memberships/me_legacy':{ownerId:'me',organizationId:'legacy',role:'member',status:'active',displayName:'',email:'old@x.com'},
  'memberships/me_gone':{ownerId:'me',organizationId:'gone',accessVersion:2,role:'manager',status:'revoked',displayName:null,email:null},
  'memberships/you_v2':{ownerId:'you',organizationId:'v2',accessVersion:2,role:'owner',status:'active',displayName:'You',email:'you@x.com'},
  'teamRequests/me_a':{organizationId:'a',userId:'me',email:'old@x.com',displayName:'Old',status:'pending'},
  'teamRequests/me_b':{organizationId:'b',userId:'me',email:'old@x.com',displayName:'Old',status:'approved'},
  'staffProfiles/s':{organizationId:'v2',accountId:'me',displayName:'Staff record name'},
});
const setup=(data=seed())=>{const db=fakeDb(data);const api=createMyProfileHandler({db,Timestamp:Ts,HttpsError:CodeError});
  return {db,call:(input,token={},uid='me')=>api({auth:uid&&{uid,token},data:input})};};
const rejects=(p,code,message)=>assert.rejects(p,e=>e.code===code&&e.message===message);
const get=(db,p)=>db.store.get(p);

test('name and phone update the profile and every open membership and pending request',async()=>{
  const {db,call}=setup();
  const r=await call({action:'update',name:'  Tom   Trinh ',phone:'+84 90 123 4567'});
  assert.deepEqual([r.name,r.phone,r.updated],['Tom Trinh','+84 90 123 4567',3]);
  assert.equal(get(db,'owners/me').name,'Tom Trinh');
  assert.equal(get(db,'owners/me').phone,'+84 90 123 4567');
  assert.equal(get(db,'memberships/me_v2').displayName,'Tom Trinh');
  assert.equal(get(db,'memberships/me_legacy').displayName,'Tom Trinh');
  assert.equal(get(db,'teamRequests/me_a').displayName,'Tom Trinh');
  // untouched: revoked record, closed request, other people, organization staff records
  assert.equal(get(db,'memberships/me_gone').displayName,null);
  assert.equal(get(db,'teamRequests/me_b').displayName,'Old');
  assert.equal(get(db,'memberships/you_v2').displayName,'You');
  assert.equal(get(db,'staffProfiles/s').displayName,'Staff record name');
  // repeating the same save writes nothing more
  assert.equal((await call({action:'update',name:'Tom Trinh',phone:'+84 90 123 4567'})).updated,0);
  // an empty phone clears it
  assert.equal((await call({action:'update',name:'Tom Trinh',phone:''})).phone,null);
  assert.equal(get(db,'owners/me').phone,null);
});

test('bad input is refused before anything changes',async()=>{
  const {db,call}=setup();
  await rejects(call({action:'update',name:'   '}),'invalid-argument','profile_name_invalid');
  await rejects(call({action:'update',name:'x'.repeat(101)}),'invalid-argument','profile_name_invalid');
  await rejects(call({action:'update',phone:'0901234567'}),'invalid-argument','profile_name_invalid');
  await rejects(call({action:'update',name:'Tom',phone:'12'}),'invalid-argument','profile_phone_invalid');
  await rejects(call({action:'update',name:'Tom',phone:'09x1234567'}),'invalid-argument','profile_phone_invalid');
  await rejects(call({action:'update',name:'Tom',email:'a@b.co'}),'invalid-argument','profile_invalid');
  await rejects(call({action:'nope'}),'invalid-argument','profile_invalid');
  await rejects(call({action:'update',name:'Tom'},{},null),'unauthenticated','team_sign_in_required');
  assert.equal(get(db,'owners/me').name,'Old');
});

test('a missing profile is recreated on save',async()=>{
  const {db,call}=setup({});
  await call({action:'update',name:'New'},{email:'n@x.com'});
  assert.equal(get(db,'owners/me').name,'New');
  assert.ok(get(db,'owners/me').createdAt);
});

test('email sync copies only a verified sign-in email',async()=>{
  const {db,call}=setup();
  await rejects(call({action:'syncEmail'},{email:'new@x.com',email_verified:false}),'failed-precondition','profile_email_not_verified');
  assert.equal(get(db,'owners/me').email,'old@x.com');
  const r=await call({action:'syncEmail'},{email:'New@X.com',email_verified:true});
  assert.deepEqual([r.email,r.updated],['new@x.com',3]);
  assert.equal(get(db,'owners/me').email,'new@x.com');
  assert.equal(get(db,'memberships/me_v2').email,'new@x.com');
  assert.equal(get(db,'memberships/me_legacy').email,'new@x.com');
  assert.equal(get(db,'teamRequests/me_a').email,'new@x.com');
  assert.equal(get(db,'memberships/me_gone').email,null);
  assert.equal((await call({action:'syncEmail'},{email:'new@x.com',email_verified:true})).updated,0);
});
