const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,deleteDoc,getDoc}=require('firebase/firestore');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp}=require('firebase-admin/firestore');
const {createTeamHandler}=require('../team');
const {createOrganizationSettingsHandler}=require('../organization_settings');
let env,app,db;
class E extends Error{constructor(code,message){super(message);this.code=code;}}
const auth=uid=>({uid,token:{email:uid+'@example.com',email_verified:true}});
const member=(uid,org,role)=>({ownerId:uid,organizationId:org,role,status:'active',accessVersion:2,buildingScope:'all',buildingIds:[],email:uid+'@example.com'});
const fields={name:'New',address:'',phone:'',email:'',taxCode:'',bankName:'',bankAccountNumber:'',bankAccountName:''};

test('recovery and purge race: retained data moves completely or recovery is refused',async()=>{
 await db.doc('organizations/a').update({name:'Current organization'});
 const expiry=Date.now()+60000;
 await db.doc('organizations/deleted').set({createdBy:'a',closedBy:'a',name:'Deleted',accessVersion:2,closedAt:Timestamp.now(),excludedFromMerge:true,mergedInto:'a',purgeAfter:Timestamp.fromMillis(expiry)});
 await db.doc('memberships/a_deleted').set({...member('a','deleted','owner'),status:'revoked',revokedReason:'organizationDeletedAtMerge'});
 await db.doc('buildings/recoverBuilding').set({organizationId:'deleted',name:'Recovered'});
 const recover=require('../organization_merge').createOrganizationMergeHandler({db,Timestamp,HttpsError:E});
 const purge=require('../organization_purge').createOrganizationPurge({db,Timestamp,now:()=>expiry+1,logger:{info(){},warn(){},error(){}}});
 const [r]=await Promise.allSettled([recover({auth:auth('a'),data:{action:'recover',sourceOrganizationId:'deleted',operationId:'race'}}),purge()]);
 const building=await db.doc('buildings/recoverBuilding').get();
 if(r.status==='fulfilled'){
  assert.equal(building.data().organizationId,'a');assert.equal((await db.doc('organizations/deleted').get()).data().purgeAfter,undefined);
 }else{assert.equal(r.reason.message,'org_restore_expired');assert.equal(building.exists,false);}
 assert.equal((await db.doc('memberships/a_a').get()).data().role,'owner');
});
before(async()=>{
 if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator only');
 env=await initializeTestEnvironment({projectId:'demo-apartment-calendar',firestore:{rules:require('node:fs').readFileSync('../firestore.rules','utf8')}});
 app=initializeApp({projectId:'demo-apartment-calendar'},'account-policy');db=getFirestore(app);
});
after(async()=>{await db?.terminate();await env?.cleanup();if(app)await deleteApp(app);});
beforeEach(async()=>{await env.clearFirestore();for(const owner of ['a','b']){await db.doc('organizations/'+owner).set({createdBy:owner,accessVersion:2});await db.doc(`memberships/${owner}_${owner}`).set(member(owner,owner,'owner'));}});
const invite=(owner)=>createTeamHandler({db,Timestamp,HttpsError:E})({auth:auth(owner),data:{organizationId:owner,operationId:'invite',action:'addStaff',profile:{displayName:'Worker',email:'worker@example.com'},access:{role:'receptionist',buildingScope:'all',buildingIds:[],permissionOverrides:{}}}});
test('two owners racing to reserve one email: exactly one company wins',async()=>{
 const result=await Promise.allSettled([invite('a'),invite('b')]);assert.equal(result.filter(r=>r.status==='fulfilled').length,1);assert.equal(result.find(r=>r.status==='rejected').reason.message,'team_other_employer');assert.equal((await db.collection('teamInvitations').get()).size,1);
});
test('organization creation racing staff invitation cannot create mixed ownership',async()=>{
 const create=createOrganizationSettingsHandler({db,Timestamp,HttpsError:E,allowCreate:true});
 const result=await Promise.allSettled([invite('a'),create({auth:auth('worker'),data:{action:'create',operationId:'create',fields}})]);
 assert.equal(result.filter(r=>r.status==='fulfilled').length,1);assert.ok(['team_owner_account','org_staff_account'].includes(result.find(r=>r.status==='rejected').reason.message));
});
test('clients cannot create legacy organizations or forge policy locks',async()=>{
 const client=env.authenticatedContext('worker').firestore();await assertFails(setDoc(doc(client,'organizations/bypass'),{createdBy:'worker'}));await assertFails(setDoc(doc(client,'accountPolicyLocks/forged'),{revision:'mine'}));
});
test('legacy administrator staff cannot delete the organization; deleting or foreign bindings block direct inventory reads',async()=>{
 await db.doc('organizations/legacy').set({createdBy:'a',accessVersion:1});
 await db.doc('memberships/worker_legacy').set({ownerId:'worker',organizationId:'legacy',role:'admin',status:'active'});
 await db.doc('buildings/legacyBuilding').set({organizationId:'legacy'});
 const client=env.authenticatedContext('worker').firestore();
 await assertFails(deleteDoc(doc(client,'organizations/legacy')));
 assert.equal((await db.doc('organizations/legacy').get()).exists,true);
 for(const binding of [{organizationId:'legacy',state:'deleting'},{organizationId:'elsewhere',state:'bound'}]){
  await db.doc('accountOrganizations/worker').set(binding);
  await assertFails(getDoc(doc(client,'buildings/legacyBuilding')));
 }
});
test('concurrent merge retries commit one result and old clients cannot reopen archived sources',async()=>{
 const {createOrganizationMergeHandler}=require('../organization_merge');
 await db.doc('organizations/b').set({createdBy:'a',name:'Second',accessVersion:2});
 await db.doc('memberships/b_b').delete();await db.doc('memberships/a_b').set(member('a','b','owner'));
 await db.doc('buildings/property').set({organizationId:'b',name:'Building'});
 await db.doc('rooms/room').set({organizationId:'b',buildingId:'property'});
 const merge=createOrganizationMergeHandler({db,Timestamp,HttpsError:E});
 const request={auth:auth('a'),data:{action:'merge',name:'Unified',operationId:'retry',organizationIds:['a','b'],mergeIds:['a','b'],confirmDelete:false}};
 const results=await Promise.all([merge(request),merge(request)]);assert.deepEqual(results[0],results[1]);
 assert.equal((await db.doc('rooms/room').get()).data().organizationId,'a');
 assert.equal((await db.doc('memberships/a_b').get()).data().status,'revoked');
 const client=env.authenticatedContext('a').firestore();
 await assertFails(setDoc(doc(client,'organizations/b'),{createdBy:'a',accessVersion:1}));
 await assertFails(setDoc(doc(client,'memberships/a_b'),{ownerId:'a',organizationId:'b',role:'admin',status:'active'}));
});

test('retired governance and direct binding/permission forgery are refused',async()=>{
 const {createGovernanceHandler}=require('../governance');const g=createGovernanceHandler({db,Timestamp,HttpsError:E});
 await assert.rejects(g({auth:auth('a'),data:{action:'propose',organizationId:'a',operationId:'joint',kind:'coOwner'}}),e=>e.message==='organization_governance_retired');
 const client=env.authenticatedContext('worker').firestore();
 for(const path of ['accountOrganizations/worker','ownershipAgreements/forged','staffShares/forged'])await assertFails(setDoc(doc(client,path),{organizationId:'a',status:'active'}));
});
test('two concurrent creates produce one organization and one matching binding',async()=>{
 const create=createOrganizationSettingsHandler({db,Timestamp,HttpsError:E,allowCreate:true});
 const result=await Promise.allSettled(['first','second'].map(operationId=>create({auth:auth('worker'),data:{action:'create',operationId,fields}})));
 assert.equal(result.filter(x=>x.status==='fulfilled').length,1);assert.equal(result.find(x=>x.status==='rejected').reason.message,'org_single_organization');
 const id=result.find(x=>x.status==='fulfilled').value.organizationId;
 assert.equal((await db.doc('accountOrganizations/worker').get()).data().organizationId,id);
 assert.equal((await db.collection('organizations').where('createdBy','==','worker').get()).size,1);
});
test('accepting historical invites in two workplaces cannot attach the account twice',async()=>{
 const team=createTeamHandler({db,Timestamp,HttpsError:E});
 for(const organizationId of ['a','b']){
  await db.doc(`staffProfiles/${organizationId}`).set({organizationId,displayName:'Worker',accountId:null,employmentStatus:'active'});
  await db.doc(`teamInvitations/${organizationId}`).set({organizationId,staffId:organizationId,email:'worker@example.com',status:'pending',expiresAt:null,invitedBy:organizationId,access:{accessVersion:2,role:'receptionist',buildingScope:'all',buildingIds:[],permissionOverrides:{}}});
 }
 const result=await Promise.allSettled(['a','b'].map(organizationId=>team({auth:auth('worker'),data:{organizationId,action:'acceptInvitation',operationId:organizationId,invitationId:organizationId}})));
 // Historical ambiguous invitations remain pending for explicit resolution.
 assert.equal(result.filter(x=>x.status==='fulfilled').length,0);
 assert.equal((await db.collection('memberships').where('ownerId','==','worker').get()).size,0);
});
