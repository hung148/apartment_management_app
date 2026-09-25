const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc,deleteDoc}=require('firebase/firestore');
const admin=require('firebase-admin');
const {createTeamHandler}=require('../team');
let env,db,handler;
before(async()=>{
  if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required; production is forbidden');
  env=await initializeTestEnvironment({projectId:'demo-apartment-calendar',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
  admin.initializeApp({projectId:'demo-apartment-calendar'});db=admin.firestore();
  handler=createTeamHandler({db,Timestamp:admin.firestore.Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
});
after(async()=>{await env?.cleanup();await Promise.all(admin.apps.map(a=>a.delete()));});
beforeEach(async()=>{
  await env.clearFirestore();
  await db.doc('organizations/org').set({createdBy:'owner',accessVersion:2});
  await db.doc('memberships/owner_org').set({organizationId:'org',ownerId:'owner',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]});
  await db.doc('staffProfiles/staff').set({organizationId:'org',displayName:'Staff',code:'S1',accountId:null,employmentStatus:'active'});
  await db.doc('buildings/a').set({organizationId:'org'});
});
const call=(data,uid='owner')=>handler({auth:{uid,token:{email:`${uid}@example.com`,email_verified:true}},data:{organizationId:'org',...data}});
const invitation={action:'invite',operationId:'invite',staffId:'staff',email:'new@example.com',access:{role:'receptionist',buildingScope:'selected',buildingIds:['a']}};
test('Firestore transaction accepts once and commits membership, staff link and audit together',async()=>{
  const result=await call(invitation);
  const input={action:'acceptInvitation',operationId:'accept',invitationId:result.invitationId};
  const results=await Promise.all([call(input,'new'),call(input,'new')]);
  assert.deepEqual(results[0],results[1]);
  assert.equal((await db.doc('memberships/new_org').get()).data().role,'receptionist');
  assert.equal((await db.doc('staffProfiles/staff').get()).data().accountId,'new');
  assert.equal((await db.collection('teamActivity').get()).size,2);
  assert.equal((await db.collection('teamOperations').get()).size,2);
});
test('direct clients cannot read invitations or forge, alter, delete backend team records',async()=>{
  await call(invitation);
  for(const uid of ['owner','new']){
    const client=env.authenticatedContext(uid).firestore();
    for(const collection of ['teamInvitations','teamRequests','teamOperations','teamActivity','staffProfiles']){
      await db.doc(`${collection}/protected`).set({organizationId:'org',actorId:uid});
      const ref=doc(client,`${collection}/protected`);
      await assertFails(getDoc(ref));await assertFails(setDoc(ref,{organizationId:'org'}));
      await assertFails(updateDoc(ref,{role:'owner'}));await assertFails(deleteDoc(ref));
    }
  }
});
test('failed recipient check leaves membership and audit untouched',async()=>{
  const {invitationId}=await call(invitation);
  await assert.rejects(call({action:'acceptInvitation',operationId:'wrong',invitationId},'wrong'),/team_invitation_recipient/);
  assert.equal((await db.doc('memberships/wrong_org').get()).exists,false);
  assert.equal((await db.collection('teamActivity').get()).size,1);
});
