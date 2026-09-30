const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createAccountDeletionHandler}=require('../account_deletion');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const nowSec=Math.floor(Ts.clock/1000);
const m=(uid,org,role,extra={})=>({ownerId:uid,organizationId:org,accessVersion:2,role,status:'active',buildingScope:'all',buildingIds:[],displayName:uid+' name',email:uid+'@x.com',...extra});
const legacy=(uid,org,role)=>({ownerId:uid,organizationId:org,role,status:'active',displayName:uid,email:uid+'@x.com'});
const seed=()=>({
  // v2 org owned by me with an administrator -> I decide
  'organizations/team':{name:'Team',accessVersion:2,createdBy:'me'},
  'memberships/me_team':m('me','team','owner'),'memberships/adm_team':m('adm','team','administrator'),'memberships/rec_team':m('rec','team','receptionist'),
  // v2 org owned by me, other members but no administrator -> close only
  'organizations/solo':{name:'Solo',accessVersion:2,createdBy:'me'},
  'memberships/me_solo':m('me','solo','owner'),'memberships/hk_solo':m('hk','solo','housekeeper',{status:'suspended'}),
  // v2 org where I am staff -> leave
  'organizations/work':{name:'Work',accessVersion:2,createdBy:'boss'},
  'memberships/boss_work':m('boss','work','owner'),'memberships/me_work':m('me','work','manager'),
  // legacy: sole admin -> close; shared admin -> leave
  'organizations/oldSole':{name:'Old sole',createdBy:'me'},'memberships/me_oldSole':legacy('me','oldSole','admin'),'memberships/x_oldSole':legacy('x','oldSole','member'),
  'organizations/oldShared':{name:'Old shared',createdBy:'y'},'memberships/me_oldShared':legacy('me','oldShared','admin'),'memberships/y_oldShared':legacy('y','oldShared','admin'),
  // personal records
  'owners/me':{name:'Me'},'staffProfiles/s1':{organizationId:'work',accountId:'me',displayName:'Me'},
  'teamRequests/me_other':{organizationId:'other',userId:'me',email:'me@x.com',status:'pending'},
  'aiUsage/me_day':{ownerId:'me'},'aiEntitlements/me':{status:'active'},'aiDrafts/d':{ownerId:'me'},
  'owners/boss':{name:'Boss'},'aiUsage/boss_day':{ownerId:'boss'},
});
const setup=(data=seed())=>{const db=fakeDb(data);const api=createAccountDeletionHandler({db,Timestamp:Ts,HttpsError:CodeError});
  return {db,call:(input,{uid='me',authTime=nowSec}={})=>api({auth:uid&&{uid,token:{auth_time:authTime}},data:input})};};
const rejects=(p,code,message)=>assert.rejects(p,e=>e.code===code&&(!message||e.message===message));

test('preview explains every organization and who can take over',async()=>{
  const {call}=setup();
  const r=await call({action:'preview'});
  assert.equal(r.recentLogin,true);
  const by=Object.fromEntries(r.organizations.map(o=>[o.organizationId,o]));
  assert.deepEqual(Object.keys(by).sort(),['oldShared','oldSole','solo','team','work']);
  assert.equal(by.team.plan,'decide');assert.deepEqual(by.team.candidates,[{userId:'adm',name:'adm name'}]);
  assert.equal(by.solo.plan,'close');assert.equal(by.solo.otherMembers,1);
  assert.equal(by.work.plan,'leave');assert.equal(by.oldSole.plan,'close');assert.equal(by.oldShared.plan,'leave');
  assert.equal((await call({action:'preview'},{authTime:nowSec-3600})).recentLogin,false);
});

test('delete needs a recent sign-in, valid input and a choice for each shared organization',async()=>{
  const {call,db}=setup();
  await rejects(call({action:'preview'},{uid:null}),'unauthenticated');
  await rejects(call({action:'delete',operationId:'op',decisions:{}},{authTime:nowSec-3600}),'failed-precondition','recent_login_required');
  for(const decisions of [[],{team:{action:'transfer'}},{team:{action:'close',x:1}},{'../x':{action:'close'}}])
    await rejects(call({action:'delete',operationId:'op',decisions}),'invalid-argument');
  await rejects(call({action:'delete',operationId:'op',decisions:{}}),'failed-precondition','account_deletion_decision_required');
  await rejects(call({action:'delete',operationId:'op',decisions:{team:{action:'transfer',to:'rec'}}}),'failed-precondition','account_deletion_plan_changed');
  assert.ok(db.store.has('owners/me')&&!db.store.has('accountDeletions/me'),'nothing touched');
});

test('hand-over, close and leave each do exactly what the preview said',async()=>{
  const {call,db}=setup();
  const r=await call({action:'delete',operationId:'op',decisions:{team:{action:'transfer',to:'adm'}}});
  assert.equal(r.status,'dataDeleted');
  const get=p=>db.store.get(p);
  // hand-over: administrator becomes owner; my membership revoked and scrubbed; org stays open
  assert.equal(get('memberships/adm_team').role,'owner');assert.equal(get('memberships/adm_team').buildingScope,'all');
  assert.deepEqual([get('memberships/me_team').status,get('memberships/me_team').email,get('memberships/me_team').displayName],['revoked',null,null]);
  assert.equal(get('organizations/team').closedAt,undefined);assert.equal(get('memberships/rec_team').status,'active');
  // close: everyone out, retained for the purge, previous status remembered
  assert.ok(get('organizations/solo').closedAt);assert.equal(get('organizations/solo').closedReason,'accountDeleted');
  assert.equal(get('memberships/hk_solo').status,'revoked');assert.equal(get('memberships/hk_solo').statusBeforeClose,'suspended');
  // leave v2: revoked + scrubbed, org untouched
  assert.equal(get('memberships/me_work').status,'revoked');assert.equal(get('memberships/me_work').email,null);assert.equal(get('memberships/boss_work').status,'active');
  // legacy: sole admin closes (others revoked, my record deleted); shared admin just leaves
  assert.ok(get('organizations/oldSole').closedAt);assert.equal(get('memberships/x_oldSole').status,'revoked');assert.equal(db.store.has('memberships/me_oldSole'),false);
  assert.equal(get('organizations/oldShared').closedAt,undefined);assert.equal(db.store.has('memberships/me_oldShared'),false);assert.equal(get('memberships/y_oldShared').status,'active');
  // personal records
  for(const p of ['owners/me','teamRequests/me_other','aiUsage/me_day','aiEntitlements/me','aiDrafts/d'])assert.equal(db.store.has(p),false,p);
  assert.equal(get('staffProfiles/s1').accountId,null);assert.equal(get('staffProfiles/s1').displayName,'Me','staff record kept for history');
  for(const p of ['owners/boss','aiUsage/boss_day'])assert.ok(db.store.has(p),'other accounts untouched: '+p);
  const actions=[...db.store].filter(([k])=>k.startsWith('teamActivity/')).map(([,v])=>`${v.organizationId}:${v.action}`).sort();
  assert.deepEqual(actions,['oldSole:closeOrganization','solo:closeOrganization','team:transferOwnership']);
  assert.equal(get('accountDeletions/me').status,'complete');
  // Running again (e.g. the app failed to delete the login) is harmless.
  assert.equal((await call({action:'delete',operationId:'op2',decisions:{}})).status,'dataDeleted');
  assert.equal(get('memberships/adm_team').role,'owner');
});

test('close for everyone is honoured, and an interrupted run resumes with the first choices',async()=>{
  const {call,db}=setup();
  const commit=db.batch;let fails=1;
  db.batch=()=>{const b=commit();const c=b.commit;b.commit=async()=>{if(fails-->0)throw new CodeError('unavailable','network');return c();};return b;};
  await rejects(call({action:'delete',operationId:'op',decisions:{team:{action:'close'}}}),'unavailable');
  assert.equal(db.store.get('accountDeletions/me').status,'pending');
  // A retry sending a different choice still uses the stored one.
  await call({action:'delete',operationId:'op',decisions:{team:{action:'transfer',to:'adm'}}});
  assert.ok(db.store.get('organizations/team').closedAt);
  assert.equal(db.store.get('memberships/adm_team').role,'administrator');
  assert.equal(db.store.get('memberships/adm_team').status,'revoked');
});

test('if the chosen administrator lost the role, nothing is transferred and a new preview is required',async()=>{
  const {call,db}=setup();
  db.store.set('memberships/adm_team',{...db.store.get('memberships/adm_team'),role:'manager'});
  // Demoted after the preview: the organization now could only close, so the user is asked again.
  await rejects(call({action:'delete',operationId:'op',decisions:{team:{action:'transfer',to:'adm'}}}),'failed-precondition','account_deletion_plan_changed');
  assert.equal(db.store.get('organizations/team').closedAt,undefined,'never silently closed');
  assert.equal(db.store.has('accountDeletions/me'),false);
  // Changed after validation but before the hand-over:
  db.store.set('memberships/adm_team',{...db.store.get('memberships/adm_team'),role:'administrator'});
  const {call:call2,db:db2}=setup();
  const get=db2.store.get.bind(db2.store);
  const orig=db2.runTransaction;let n=0;
  db2.runTransaction=async fn=>{if(++n===2)db2.store.set('memberships/adm_team',{...get('memberships/adm_team'),status:'suspended'});return orig(fn);};
  await rejects(call2({action:'delete',operationId:'op',decisions:{team:{action:'transfer',to:'adm'}}}),'failed-precondition','account_deletion_plan_changed');
  assert.equal(db2.store.has('accountDeletions/me'),false,'ledger cleared so the user starts over');
  assert.equal(get('memberships/me_team').status,'active');
});

test('the exported callable passes through the shared security boundary',async()=>{
  const api=require('../index');
  await rejects(api.deleteMyAccount.run({data:{}}),'unauthenticated');
  await rejects(api.deleteMyAccount.run({auth:{uid:'u'},data:{}}),'unauthenticated','app_check_required');
});
