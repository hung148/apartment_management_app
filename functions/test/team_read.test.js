const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createTeamReadHandler}=require('../team_read');
class CodeError extends Error {constructor(code,message){super(message);this.code=code;}}
const reader=createTeamReadHandler({db:{runTransaction:()=>{throw Error('Unexpected database access');}},HttpsError:CodeError});
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
  for(const name of ['readWorkspace','lookupTeamInvitation','readTeam','getMyMemberships','getOrganizationMembers'])await assert.rejects(api[name].run({data:{}}),e=>e.code==='unauthenticated');
  // The outer boundary rejects missing attestation before any database reads;
  // email, field and scope validation is separately exercised on the handlers.
  for(const name of ['lookupTeamInvitation','readTeam','getOrganizationMembers'])
    await assert.rejects(api[name].run({auth:{uid:'u'},data:{}}),e=>e.code==='unauthenticated'&&e.message==='app_check_required');
});
