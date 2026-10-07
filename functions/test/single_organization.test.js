'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createOrganizationSettingsHandler}=require('../organization_settings');
const {createTeamHandler}=require('../team');
const {createGovernanceHandler}=require('../governance');
const {accountPolicy}=require('../account_policy');
const member=(uid,org,role='owner',status='active')=>({ownerId:uid,organizationId:org,role,status,accessVersion:2,buildingScope:'all',buildingIds:[],email:uid+'@example.com'});
const auth=uid=>({uid,token:{email:uid+'@example.com',email_verified:true}});
const fields={name:'New',address:'',phone:'',email:'',taxCode:'',bankName:'',bankAccountNumber:'',bankAccountName:''};
const seed=()=>({'organizations/a':{name:'A',accessVersion:2,createdBy:'boss'},'memberships/boss_a':member('boss','a')});
test('a completed account deletion cannot use a stale token to create another organization',async()=>{
 const db=fakeDb({'accountDeletions/deleted':{status:'complete'},'accountOrganizations/deleted':{organizationId:null,state:'released'}});
 const policy=await db.runTransaction(tx=>accountPolicy(db,tx,'deleted'));assert.equal(policy.canCreate,false);
 const settings=createOrganizationSettingsHandler({db,Timestamp:Ts,HttpsError:CodeError,allowCreate:true});
 await assert.rejects(settings({auth:auth('deleted'),data:{action:'create',operationId:'stale-token',fields}}),/account_deletion_in_progress/);
 assert.equal([...db.store.keys()].filter(p=>p.startsWith('organizations/')).length,0);
});
test('an owner cannot create a second organization, including legacy creation',async()=>{
 for(const legacy of [false,true]){
  const db=fakeDb(seed()),settings=createOrganizationSettingsHandler({db,Timestamp:Ts,HttpsError:CodeError,allowCreate:!legacy});
  await assert.rejects(settings({auth:auth('boss'),data:{action:legacy?'createLegacy':'create',operationId:'second',fields}}),/org_single_organization/);
  assert.equal([...db.store.keys()].filter(k=>k.startsWith('organizations/')).length,1);
 }
});
test('even the common owner cannot invite staff from another of their organizations',async()=>{
 const db=fakeDb({...seed(),'organizations/b':{accessVersion:2,createdBy:'boss'},'memberships/worker_b':member('worker','b','staff')});
 const team=createTeamHandler({db,Timestamp:Ts,HttpsError:CodeError});
 await assert.rejects(team({auth:auth('boss'),data:{organizationId:'a',action:'addStaff',operationId:'invite',profile:{displayName:'Worker',email:'worker@example.com'},access:{role:'staff',buildingScope:'all',buildingIds:[],permissionOverrides:{}}}}),/team_other_employer/);
 assert.equal([...db.store.keys()].filter(k=>k.startsWith('teamInvitations/')).length,0);
});
test('co-owner and sharing proposals and historical approvals are retired',async()=>{
 const db=fakeDb({...seed(),'ownershipAgreements/old':{organizationId:'a',kind:'coOwner',status:'pending'}});
 const g=createGovernanceHandler({db,Timestamp:Ts,HttpsError:CodeError});
 for(const data of [{action:'propose',organizationId:'a',kind:'coOwner',recipientEmail:'worker@example.com',grants:{},controls:{manageCoOwners:'joint',shareStaff:'joint',closeOrganization:'joint',transferOwnership:'joint'}},{action:'approve',agreementId:'old'}]){
  await assert.rejects(g({auth:auth('boss'),data:{...data,operationId:'retired'}}),/organization_governance_retired/);
 }
 assert.equal(db.store.get('ownershipAgreements/old').status,'pending');
});
test('creation persists a server binding and a retry does not create another organization',async()=>{
 const db=fakeDb(),settings=createOrganizationSettingsHandler({db,Timestamp:Ts,HttpsError:CodeError,allowCreate:true});
 const request={auth:auth('new'),data:{action:'create',operationId:'first',fields}};
 const result=await settings(request);
 assert.equal(db.store.get('accountOrganizations/new')?.organizationId,result.organizationId);
 assert.deepEqual(await settings(request),result);
 assert.equal((await db.runTransaction(tx=>accountPolicy(db,tx,'new'))).canCreate,false);
});
