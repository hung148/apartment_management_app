'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createRequestGuard,createSecureCallable,createCallableGroups}=require('../request_security');
class HttpsError extends Error{constructor(code,message){super(message);this.code=code;}}
function fixture(){
 let time=1000000;const db=require('./fake_firestore').fakeDb();const records=db.store;
 const deps={db,HttpsError,Timestamp:{fromMillis:v=>v},now:()=>time};
 return {records,deps,guard:createRequestGuard(deps),advance:ms=>time+=ms};
}
const request=(data={})=>({auth:{uid:'user'},app:{appId:'registered-app'},data});
test('archived and ambiguous ownership attempts are refused and consume the user budget',async()=>{
 for(const archived of [true,false]){
  const f=fixture();f.records.set('organizations/org',{createdBy:'user',accessVersion:2,...(archived?{mergedInto:'target'}:{})});
  f.records.set('memberships/user_org',{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'});
  if(!archived)f.records.set('memberships/other_org',{ownerId:'other',organizationId:'org',accessVersion:2,status:'active',role:'owner'});
  await assert.rejects(f.guard('readTeam',request({organizationId:'org'})),new RegExp(archived?'org_organization_merged':'org_single_organization_review'));
  assert.ok([...f.records.keys()].some(p=>p.startsWith('requestLimits/')));
 }
});
test('missing Auth or App Check never reaches storage or the handler',async()=>{
 const f=fixture();let called=0,options;
 const register=createSecureCallable({ ...f.deps,onCall:(o,h)=>{options=o;return h;}});
 const handler=register('invoices',{enforceAppCheck:false},()=>called++);
 assert.equal(options.enforceAppCheck,true);
 for(const input of [{data:{}},{auth:{uid:'user'},data:{}}])await assert.rejects(handler(input),e=>e.code==='unauthenticated');
 assert.equal(called,0);assert.equal(f.records.size,0);
});
test('legacy calendar buckets derive organization from saved records, not forged top-level scope',async()=>{
 const f=fixture();
 f.records.set('memberships/user_org',{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'});
 f.records.set('bookings/booking',{organizationId:'org'});
 await f.guard('mutateCalendarBooking',request({bookingId:'booking',action:'payment',organizationId:'foreign'}));
 assert.equal(f.records.size,4,'the actual organization must receive a debit');
});
test('lookup limits ignore forged clock, operation IDs and org IDs; server time alone replenishes',async()=>{
 const f=fixture();
 for(let i=0;i<12;i++)await f.guard('lookupTeamInvitation',request({invitationId:`guess${i}`,now:1,organizationId:`foreign${i}`}));
 await assert.rejects(f.guard('lookupTeamInvitation',request({now:9999999999999,operationId:'new'})),e=>e.code==='resource-exhausted');
 f.advance(10000);await f.guard('lookupTeamInvitation',request());
 f.advance(-86400000);await assert.rejects(f.guard('lookupTeamInvitation',request()),e=>e.code==='resource-exhausted');
 assert.equal(f.records.size,2,'outsiders cannot create organization buckets');
});
test('costly attempts share a budget across endpoints; malformed and denied attempts count',async()=>{
 const f=fixture();
 // AI calls were removed (2026-10-10 clean-up); sheet import, merging and creating share the budget.
 for(const [name,data] of [['importSheet',{}],['mergeMyOrganizations',{}],['organizationSettings',{action:'create'}],['importSheet',{}]])await f.guard(name,request(data));
 await assert.rejects(f.guard('mergeMyOrganizations',request()),e=>e.code==='resource-exhausted');
 for(let i=0;i<115;i++)await assert.rejects(f.guard('invoices',request({text:'x'.repeat(131073)})),e=>e.code==='invalid-argument');
 await assert.rejects(f.guard('readWorkspace',request()),e=>e.code==='resource-exhausted');
});
test('organization budgets only include identity-matched active known members',async()=>{
 const f=fixture();
 f.records.set('memberships/user_org',{ownerId:'other',organizationId:'org',accessVersion:2,status:'active',role:'owner'});
 await f.guard('readWorkspace',request({organizationId:'org'}));assert.equal(f.records.size,2);
 f.records.set('memberships/user_org',{ownerId:'user',organizationId:'org',accessVersion:2,status:'active',role:'owner'});
 // The membership is remembered 15 s; the write that changed it forgets it.
 f.guard.forget('user','org');
 await f.guard('readWorkspace',request({organizationId:'org'}));assert.equal(f.records.size,3);
});

test('App Check is skipped only in the local demo emulator, never on a real project',async()=>{
 const saved={emu:process.env.FUNCTIONS_EMULATOR,project:process.env.GCLOUD_PROJECT};
 const restore=()=>{for(const [k,v] of [['FUNCTIONS_EMULATOR',saved.emu],['GCLOUD_PROJECT',saved.project]])if(v===undefined)delete process.env[k];else process.env[k]=v;};
 try{
  const noApp={auth:{uid:'user'},data:{}};
  for(const [emu,project,allowed] of [['true','demo-canho360',true],['true','apartment-management-staging',false],['true','apartment-management-app-776b9',false],[undefined,'demo-canho360',false],['false','demo-canho360',false]]){
   if(emu===undefined)delete process.env.FUNCTIONS_EMULATOR;else process.env.FUNCTIONS_EMULATOR=emu;
   process.env.GCLOUD_PROJECT=project;
   const f=fixture();let options;
   const handler=createSecureCallable({...f.deps,onCall:(o,h)=>{options=o;return h;}})('invoices',()=>'ok');
   assert.equal(options.enforceAppCheck,!allowed,`${emu} ${project}`);
   if(allowed)assert.equal(await handler(noApp),'ok');
   else await assert.rejects(handler(noApp),e=>e.message==='app_check_required');
  }
 }finally{restore();}
});

// Grouped functions (2026-10-06, speed step 4).
function groups(f){
 const options={},g=createCallableGroups({...f.deps,onCall:(o,h)=>h});
 const seen=[];
 g.register('invoices',r=>{seen.push(['invoices',r.data,r.auth.uid]);return 'invoices ok';});
 g.register('claimMyInvitations',r=>{seen.push(['claim',r.data]);return 'claim ok';});
 g.register('importSheet',{group:'heavy'},r=>{seen.push(['import',r.data]);return 'import ok';});
 return {g,seen,app:g.group('app'),heavy:g.group('heavy')};
}
test('a group passes only the call data, under the call name, to that call',async()=>{
 const f=fixture(),{app,seen,g}=groups(f);
 assert.equal(await app(request({fn:'invoices',data:{organizationId:'org',x:1}})),'invoices ok');
 assert.deepEqual(seen,[['invoices',{organizationId:'org',x:1},'user']]);
 assert.deepEqual(g.names('app').sort(),['claimMyInvitations','invoices']);
 assert.deepEqual(g.names('heavy'),['importSheet']);
});
test('the call name picks the rate limit: lookup calls keep their own small bucket',async()=>{
 const f=fixture(),{app}=groups(f);
 for(let i=0;i<12;i++)await app(request({fn:'claimMyInvitations',data:{}}));
 await assert.rejects(app(request({fn:'claimMyInvitations',data:{}})),e=>e.message==='request_rate_limited');
 assert.equal(await app(request({fn:'invoices',data:{}})),'invoices ok');
});
test('unknown names and calls of another group are charged, then refused',async()=>{
 const f=fixture(),{app,heavy,seen}=groups(f);
 for(const data of [{fn:'nope',data:{}},{fn:'importSheet',data:{}},{fn:'../x'},{data:{}},null,'invoices',{fn:'invoices',data:{},extra:'x'.repeat(1000)}])
  await assert.rejects(app(request(data)),e=>e.code==='not-found'&&e.message==='unknown_call');
 await assert.rejects(heavy(request({fn:'invoices',data:{}})),e=>e.code==='not-found');
 assert.deepEqual(seen,[]);
 assert(f.records.size>0,'refused calls still cost the general budget');
});
test('a group checks App Check and sign-in before anything else',async()=>{
 const f=fixture(),{app,seen}=groups(f);
 await assert.rejects(app({data:{fn:'invoices',data:{}}}),e=>e.code==='unauthenticated');
 await assert.rejects(app({auth:{uid:'user'},data:{fn:'invoices',data:{}}}),e=>e.message==='app_check_required');
 assert.deepEqual(seen,[]);assert.equal(f.records.size,0);
});
test('a call name can be registered only once',()=>{
 const f=fixture(),g=createCallableGroups({...f.deps,onCall:(o,h)=>h});
 g.register('invoices',()=>1);
 assert.throws(()=>g.register('invoices',()=>2),/repeated/);
 assert.throws(()=>g.register('bad name',()=>2),/Bad/);
});
