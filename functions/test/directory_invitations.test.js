// Speed (2026-10-09): the organization list says whether invitations wait to be claimed, so the
// app asks to claim only then.
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {createOrganizationDirectory}=require('../organization_directory');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const call=(data,token,cursor)=>createOrganizationDirectory({db:fakeDb(data),HttpsError:CodeError})({auth:{uid:'u',token},data:cursor?{cursor}:{}});
const inv=(extra={})=>({email:'lan@example.com',status:'pending',organizationId:'org',...extra});

test('pending, unexpired invitations for the verified email are reported on the first page',async()=>{
  const verified={email:'Lan@Example.com',email_verified:true};
  assert.deepEqual((await call({},verified)).invitations,{pending:false,needsVerifiedEmail:false});
  assert.deepEqual((await call({'teamInvitations/a':inv()},verified)).invitations,{pending:true,needsVerifiedEmail:false});
  // Someone else's, accepted, expired or broken ones do not count.
  for(const other of [inv({email:'x@example.com'}),inv({status:'accepted'}),inv({expiresAt:Ts.fromMillis(Date.now()-1000)}),inv({organizationId:'../x'})])
    assert.equal((await call({'teamInvitations/a':other},verified)).invitations.pending,false,JSON.stringify(other));
  assert.equal((await call({'teamInvitations/a':inv({expiresAt:Ts.fromMillis(Date.now()+60000)})},verified)).invitations.pending,true);
});

test('an unverified or missing email claims nothing; later pages carry no invitation info',async()=>{
  const data={'teamInvitations/a':inv()};
  assert.deepEqual((await call(data,{email:'lan@example.com',email_verified:false})).invitations,{pending:false,needsVerifiedEmail:true});
  assert.deepEqual((await call(data,{})).invitations,{pending:false,needsVerifiedEmail:false});
  assert.equal((await call(data,{email:'lan@example.com',email_verified:true},'m_next')).invitations,undefined);
});
