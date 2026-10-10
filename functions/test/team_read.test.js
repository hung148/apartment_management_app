const {test}=require('node:test');
const {via}=require('./call_group');
const assert=require('node:assert/strict');
const {createTeamReadHandler}=require('../team_read');
class CodeError extends Error {constructor(code,message){super(message);this.code=code;}}
const reader=createTeamReadHandler({db:{runTransaction:()=>{throw Error('Unexpected database access');}},HttpsError:CodeError});

test('staff page includes fresh caller access and still denies suspended callers',async()=>{
 const {fakeDb}=require('./fake_firestore');
 const db=fakeDb({'organizations/org':{accessVersion:2},'memberships/u_org':{organizationId:'org',ownerId:'u',accessVersion:2,role:'owner',status:'active',buildingScope:'all'},'staffProfiles/s':{organizationId:'org',displayName:'Staff'}});
 const read=createTeamReadHandler({db,HttpsError:CodeError});
 const request={auth:{uid:'u'},data:{organizationId:'org',view:'staff'}};
 const result=await read(request);
 assert.equal(result.actor?.role,'owner');
 assert.equal(result.actor?.allProperties,true);
 assert.deepEqual(result.actor,(await read({...request,data:{organizationId:'org',view:'myAccess'}})).record);
 assert.equal(result.records.length,1);
 db.store.get('memberships/u_org').status='suspended';
 await assert.rejects(read(request),e=>e.code==='permission-denied');
});
test('read API validates authentication, pagination and filters before touching data',async()=>{
  await assert.rejects(reader({data:{}}),e=>e.code==='unauthenticated');
  for(const data of [
    {},{organizationId:'../org',view:'staff'},
    {organizationId:'org',view:'secrets'},
    {organizationId:'org',view:'staff',limit:0},
    {organizationId:'org',view:'staff',limit:101},
    {organizationId:'org',view:'staff',limit:1.5},
    {organizationId:'org',view:'staff',cursor:'a/b'},
    {organizationId:'org',view:'staff',actorId:'other'},
  ])await assert.rejects(reader({auth:{uid:'u'},data}),e=>e.code==='invalid-argument');
});
test('exported team and membership read callables use current authentication envelope',async()=>{
  const api=require('../index');
  for(const name of ['readWorkspace','lookupTeamInvitation','readTeam','getMyMemberships','getOrganizationMembers'])await assert.rejects(via(api,name).run({data:{}}),e=>e.code==='unauthenticated');
  // The outer boundary rejects missing attestation before any database reads;
  // email, field and scope validation is separately exercised on the handlers.
  for(const name of ['lookupTeamInvitation','readTeam','getOrganizationMembers'])
    await assert.rejects(via(api,name).run({auth:{uid:'u'},data:{}}),e=>e.code==='unauthenticated'&&e.message==='app_check_required');
});
