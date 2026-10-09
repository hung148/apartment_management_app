'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {accountPolicy}=require('../account_policy');
const {fakeDb}=require('./fake_firestore');

test('account policy starts independent reads together while retaining deletion denial',async()=>{
 const db=fakeDb({'accountDeletions/user':{status:'pending'}}),events=[];
 const tx={get:async ref=>{
  events.push('start');
  const value=await ref.get();
  events.push('finish');
  return value;
 }};
 const result=await accountPolicy(db,tx,'user');
 assert.equal(result.deleting,true);
 assert.equal(result.canCreate,false);
 assert.deepEqual(events.slice(0,4),['start','start','start','start'],
  'membership, created organizations, binding and deletion reads must not add four serial network waits');
});

test('policy reuses an organization snapshot across membership binding and invitation checks',async()=>{
 const db=fakeDb({
  'organizations/work':{accessVersion:2,createdBy:'boss'},
  'memberships/user_work':{ownerId:'user',organizationId:'work',role:'receptionist',status:'active'},
  'accountOrganizations/user':{organizationId:'work',state:'bound'},
  'teamInvitations/pending':{email:'user@example.com',organizationId:'work',status:'pending'},
 });
 let reads=0;
 const tx={get:async ref=>{
  if(ref.path==='organizations/work')reads++;
  return ref.get();
 }};
 const result=await accountPolicy(db,tx,'user','user@example.com');
 assert.equal(result.mode,'staff');
 assert.equal(result.canCreate,false);
 assert.deepEqual(result.organizationIds,['work']);
 assert.equal(reads,1,'same policy check must not reread the same organization three times');
 // Snapshot reuse must stop at the request boundary: revocation/merge is fresh.
 db.store.set('organizations/work',{accessVersion:2,createdBy:'boss',mergedInto:'destination'});
 const next=await accountPolicy(db,tx,'user','user@example.com');
 assert.deepEqual(next.organizationIds,[]);
 assert.equal(next.hasStaff,false);
 assert.equal(reads,2);
});
