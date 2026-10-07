'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createOrganizationMergeHandler}=require('../organization_merge');
const {accountPolicy}=require('../account_policy');
const {meterId}=require('../utility_invoice');
test('meter readings and billed intervals remain reachable under the unified organization key',async()=>{
 const oldId=meterId('b','room','electricity'),newId=meterId('a','room','electricity');
 const {db,call}=fixture({
  [`utilityMeters/${oldId}`]:{organizationId:'b',roomId:'room',buildingId:'house',kind:'electricity',lastReadingId:'reading',billedUntil:'2026-10-01'},
  [`utilityMeters/${oldId}/readings/reading`]:{organizationId:'b',roomId:'room',invoiceId:'invoice',readingMilli:123000},
 });
 await call(merge);
 assert.equal(db.store.get(`utilityMeters/${newId}`)?.billedUntil,'2026-10-01');
 assert.equal(db.store.get(`utilityMeters/${newId}/readings/reading`)?.invoiceId,'invoice');
 assert.equal(db.store.get(`utilityMeters/${newId}/readings/reading`)?.organizationId,'a');
});
function fixture(extra={}){
 const db=fakeDb({
  'organizations/a':{name:'Alpha',createdBy:'owner',accessVersion:2},
  'organizations/b':{name:'Beta',createdBy:'owner',accessVersion:2},
  'memberships/owner_a':{ownerId:'owner',organizationId:'a',role:'owner',status:'active',accessVersion:2,buildingScope:'all'},
  'memberships/owner_b':{ownerId:'owner',organizationId:'b',role:'owner',status:'active',accessVersion:2,buildingScope:'all'},
  'buildings/house':{organizationId:'b',name:'House'},
  'rooms/room':{organizationId:'b',buildingId:'house'},
  'tenants/tenant':{roomId:'room',name:'Tenant'},
  'tenants/tenant/rentHistory/history':{organizationId:'b',amount:100},
  'payments/payment':{organizationId:'b',tenantId:'tenant',amount:100},
  ...extra});
 const handler=createOrganizationMergeHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const call=(data,uid='owner')=>handler({auth:{uid},data});
 return {db,call};
}
const merge={action:'merge',operationId:'merge1',name:'Unified',organizationIds:['a','b'],mergeIds:['a','b'],confirmDelete:false};

test('recover excluded data into current organization without reviving deleted staff or a second organization',async()=>{
 const {db,call}=fixture();await call({...merge,mergeIds:['a'],confirmDelete:true});
 const list=await call({action:'recoveryList'});assert.equal(list.organizations[0].id,'b');
 const payload={action:'recover',sourceOrganizationId:'b',operationId:'recover1'};
 const result=await call(payload);assert.equal(result.organizationId,'a');
 assert.equal(db.store.get('rooms/room').organizationId,'a');
 assert.equal(db.store.get('tenants/tenant/rentHistory/history').organizationId,'a');
 assert.equal(db.store.get('organizations/b').purgeAfter,undefined);
 assert.equal(db.store.get('organizations/b').excludedFromMerge,false);
 assert.deepEqual((await db.runTransaction(tx=>accountPolicy(db,tx,'owner'))).organizationIds,['a']);
 assert.deepEqual(await call({...payload}),result);
 assert.equal((await call({action:'recoveryList'})).organizations.length,0);
});

test('recovery refuses expired retention or a claimed purge without moving data',async()=>{
 for(const patch of [{purgeStartedAt:Ts.now()},{purgeAfter:Ts.fromMillis(0)}]){
  const {db,call}=fixture();await call({...merge,mergeIds:['a'],confirmDelete:true});
  db.store.set('organizations/b',{...db.store.get('organizations/b'),...patch});
  const before=JSON.stringify([...db.store]);
  await assert.rejects(call({action:'recover',sourceOrganizationId:'b',operationId:'recover1'}),/org_restore_expired/);
  assert.equal(JSON.stringify([...db.store]),before);
 }
});

test('recovery fails without writes when current organization metadata needs repair',async()=>{
 const {db,call}=fixture();await call({...merge,mergeIds:['a'],confirmDelete:true});
 const target={...db.store.get('organizations/a')};delete target.name;db.store.set('organizations/a',target);
 const before=JSON.stringify([...db.store]);
 await assert.rejects(call({action:'recover',sourceOrganizationId:'b',operationId:'repair'}),/org_merge_changed/);
 assert.equal(JSON.stringify([...db.store]),before);
});

test('recovery rejects ambiguous current ownership before moving retained data',async()=>{
 const {db,call}=fixture();await call({...merge,mergeIds:['a'],confirmDelete:true});
 db.store.set('memberships/other_a',{ownerId:'other',organizationId:'a',role:'owner',status:'active',accessVersion:2,buildingScope:'all'});
 const before=JSON.stringify([...db.store]);
 await assert.rejects(call({action:'recover',sourceOrganizationId:'b',operationId:'ambiguous'}),/org_merge_owner_only/);
 assert.equal(JSON.stringify([...db.store]),before);
});
test('preview is read-only and exposes only organization names/ids',async()=>{
 const {db,call}=fixture(),before=JSON.stringify([...db.store]);
 assert.deepEqual(await call({action:'preview'}),{organizations:[{id:'a',name:'Alpha'},{id:'b',name:'Beta'}]});
 assert.equal(JSON.stringify([...db.store]),before);
});
test('atomic merge keeps IDs, legacy linked records, histories and one active owner; retry is unchanged',async()=>{
 const {db,call}=fixture();const result=await call(merge);
 assert.equal(result.organizationId,'a');
 for(const p of ['buildings/house','rooms/room','tenants/tenant','tenants/tenant/rentHistory/history','payments/payment'])assert.equal(db.store.get(p).organizationId,'a',p);
 assert.equal(db.store.get('organizations/a').name,'Unified');assert.equal(db.store.get('organizations/b').mergedInto,'a');
 assert.equal(db.store.get('memberships/owner_b').status,'revoked');
 assert.equal(db.store.get('memberships/owner_a').role,'owner');
 assert.deepEqual((await db.runTransaction(tx=>accountPolicy(db,tx,'owner'))).organizationIds,['a']);
 const snapshot=JSON.stringify([...db.store]);assert.deepEqual(await call(merge),result);assert.equal(JSON.stringify([...db.store]),snapshot);
 await assert.rejects(call({...merge,name:'Other'}),/org_operation_reused/);
});
test('delete choice requires confirmation and keeps excluded data out of unified org until purge',async()=>{
 const {db,call}=fixture();const choice={...merge,mergeIds:['a']};
 await assert.rejects(call(choice),/org_merge_delete_confirmation/);
 assert.equal(db.store.get('organizations/b').closedAt,undefined);
 await call({...choice,confirmDelete:true});
 assert.equal(db.store.get('organizations/b').excludedFromMerge,true);
 assert.equal(db.store.get('organizations/b').purgeAfter.toMillis(),Ts.now().toMillis()+30*86400000);
 assert.equal(db.store.get('rooms/room').organizationId,'b');
 assert.equal(db.store.get('tenants/tenant').organizationId,undefined);
 assert.equal(db.store.get('memberships/owner_b').status,'revoked');
 assert.deepEqual((await db.runTransaction(tx=>accountPolicy(db,tx,'owner'))).organizationIds,['a']);
});
test('staff all-property scope stays limited to original properties',async()=>{
 const {db,call}=fixture({'memberships/staff_b':{ownerId:'staff',organizationId:'b',role:'manager',status:'active',accessVersion:2,buildingScope:'all'}});
 await call(merge);
 assert.equal(db.store.get('memberships/staff_b').status,'revoked');
 assert.equal(db.store.get('memberships/staff_a').buildingScope,'selected');
 assert.deepEqual(db.store.get('memberships/staff_a').buildingIds,['house']);
 assert.equal(db.store.get('accountOrganizations/staff').organizationId,'a');
});
test('explicit all grants cannot bypass original property limits; global management needs reassignment',async()=>{
 const {allows}=require('../team_access');
 const {db,call}=fixture({'memberships/staff_b':{ownerId:'staff',organizationId:'b',role:'custom',roleGrants:{readBookings:'all',manageTeam:'all',exportData:'all'},permissionOverrides:{exportData:true},status:'active',accessVersion:2,buildingScope:'all'}});
 await call(merge);const m=db.store.get('memberships/staff_a');
 assert.equal(allows(m,'readBookings',{buildingId:'house'}),true);
 assert.equal(allows(m,'readBookings',{buildingId:'otherHouse'}),false);
 assert.equal(allows(m,'manageTeam'),false);assert.equal(allows(m,'exportData'),false);
});
test('oversized merge fails atomically and leaves every record unchanged',async()=>{
 const extra=Object.fromEntries(Array.from({length:460},(_,i)=>[`buildings/p${i}`,{organizationId:'b'}]));
 const {db,call}=fixture(extra),before=JSON.stringify([...db.store]);
 await assert.rejects(call(merge),/org_merge_maintenance_required/);assert.equal(JSON.stringify([...db.store]),before);
});
test('deleted organization purge does not remove records in the unified organization',async()=>{
 const {createOrganizationPurge}=require('../organization_purge');
 const {db,call}=fixture({'buildings/keep':{organizationId:'a'}});
 await call({...merge,mergeIds:['a'],confirmDelete:true});
 await createOrganizationPurge({db,Timestamp:Ts,logger:{info(){},warn(){},error(){}},now:()=>Ts.now().toMillis()+31*86400000})();
 assert.equal(db.store.has('organizations/b'),false);assert.equal(db.store.has('rooms/room'),false);
 assert.equal(db.store.has('tenants/tenant/rentHistory/history'),false);
 assert.equal(db.store.has('buildings/keep'),true);assert.equal(db.store.get('accountOrganizations/owner').organizationId,'a');
});
test('forged identities, stale lists, empty selection and coowners fail without writes',async()=>{
 for(const [extra,data,uid,key] of [
  [{},merge,'staff','org_merge_not_needed'],
  [{},{...merge,organizationIds:['a']},'owner','org_merge_changed'],
  [{},{...merge,mergeIds:[]},'owner','org_merge_changed'],
  [{'memberships/co_b':{ownerId:'co',organizationId:'b',status:'active',role:'coOwner'}},merge,'owner','org_merge_access_review'],
  [{'memberships/other_b':{ownerId:'other',organizationId:'b',status:'active',role:'owner'}},merge,'owner','org_merge_access_review'],
 ]){const {db,call}=fixture(extra),before=JSON.stringify([...db.store]);await assert.rejects(call(data,uid),new RegExp(key));assert.equal(JSON.stringify([...db.store]),before);}
});
