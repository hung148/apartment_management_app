'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createOrganizationTransferHandler}=require('../organization_transfer');
const {accountPolicy}=require('../account_policy');
function fixture(){const db=fakeDb({
 'organizations/org':{createdBy:'owner',accessVersion:2},
 'memberships/owner_org':{ownerId:'owner',organizationId:'org',status:'active',accessVersion:2,role:'owner',buildingScope:'all'},
 'memberships/staff_org':{ownerId:'staff',organizationId:'org',status:'active',accessVersion:2,role:'manager',buildingScope:'all',displayName:'Staff'},
 'memberships/other_org':{ownerId:'other',organizationId:'org',status:'active',accessVersion:2,role:'receptionist',buildingScope:'all'},
 'accountOrganizations/owner':{organizationId:'org',state:'bound'},
 });const handler=createOrganizationTransferHandler({db,Timestamp:Ts,HttpsError:CodeError});return {db,call:(uid,data)=>handler({auth:{uid},data:{organizationId:'org',...data}})};}
const offer={action:'propose',recipientId:'staff',proposalId:'offer'};
test('owner remains sole owner until recipient explicitly accepts; acceptance releases former owner and retries safely',async()=>{
 const {db,call}=fixture();await call('owner',offer);await call('owner',offer);
 assert.equal(db.store.get('memberships/owner_org').role,'owner');assert.equal(db.store.get('memberships/staff_org').role,'manager');
 await assert.rejects(call('other',{action:'accept',proposalId:'offer'}),/org_transfer_changed/);
 const read=await call('staff',{action:'read'});assert.equal(read.proposal.canAccept,true);
 await call('staff',{action:'accept',proposalId:'offer'});await call('staff',{action:'accept',proposalId:'offer'});
 assert.equal(db.store.get('memberships/owner_org').status,'revoked');assert.equal(db.store.get('memberships/staff_org').role,'owner');
 assert.equal(db.store.get('organizations/org').ownerTransferredTo,'staff');assert.equal(db.store.get('accountOrganizations/owner').state,'released');
 assert.equal((await db.runTransaction(tx=>accountPolicy(db,tx,'owner'))).canCreate,true);
 assert.deepEqual((await db.runTransaction(tx=>accountPolicy(db,tx,'staff'))).organizationIds,['org']);
});
test('cancelled, expired, revoked and suspended offers cannot be accepted',async()=>{
 for(const kind of ['cancelled','expired','revoked','suspended']){
  const {db,call}=fixture();await call('owner',offer);
  if(kind==='cancelled'){await call('owner',{action:'cancel',proposalId:'offer'});await call('owner',{action:'cancel',proposalId:'offer'});}
  else if(kind==='expired')db.store.get('organizationTransfers/org').expiresAt=Ts.fromMillis(Ts.now().toMillis()-1);
  else db.store.get('memberships/staff_org').status=kind;
  await assert.rejects(call('staff',{action:'accept',proposalId:'offer'}));
  assert.equal(db.store.get('memberships/owner_org').status,'active');assert.equal(db.store.get('memberships/owner_org').role,'owner');
 }
});
test('staff cannot offer ownership and multi-org/deleting recipients cannot receive it',async()=>{
 const {db,call}=fixture();await assert.rejects(call('other',offer),/org_transfer_owner_only/);
 db.store.set('accountDeletions/staff',{status:'pending'});await assert.rejects(call('owner',offer),/org_single_organization_review/);
 db.store.delete('accountDeletions/staff');db.store.set('organizations/another',{createdBy:'staff',accessVersion:2});
 await assert.rejects(call('owner',offer),/org_single_organization_review/);
 assert.equal(db.store.has('organizationTransfers/org'),false);
});
