const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fakeDb,Ts,CodeError}=require('./fake_firestore');
const {createOrganizationSettingsHandler}=require('../organization_settings');
const {createTeamHandler}=require('../team');
const fields={name:'New business',address:'',phone:'',email:'',taxCode:'',bankName:'',bankAccountNumber:'',bankAccountName:''};
const member=(uid,org,role,status='active')=>({ownerId:uid,organizationId:org,accessVersion:2,role,status,buildingScope:'all',buildingIds:[],email:uid+'@example.com'});
const seed=()=>({'organizations/work':{accessVersion:2,createdBy:'boss'},'memberships/boss_work':member('boss','work','owner'),'memberships/staff_work':member('staff','work','receptionist')});
const auth=uid=>({uid,token:{email:uid+'@example.com',email_verified:true}});
const create=(db,uid='staff',action='create')=>createOrganizationSettingsHandler({db,Timestamp:Ts,HttpsError:CodeError,allowCreate:true})({auth:auth(uid),data:{action,operationId:'new',fields}});
const grant={role:'receptionist',buildingScope:'all',buildingIds:[],permissionOverrides:{}};
const add=(db,email)=>createTeamHandler({db,Timestamp:Ts,HttpsError:CodeError})({auth:auth('boss'),data:{organizationId:'work',operationId:'add',action:'addStaff',profile:{displayName:'Worker',email},access:grant}});
for(const status of ['active','suspended','assignmentRequired'])test(status+' staff cannot create an organization',async()=>{
 const data=seed();data['memberships/staff_work'].status=status;const db=fakeDb(data);
 await assert.rejects(create(db),/org_staff_account/);assert.equal([...db.store.keys()].filter(k=>k.startsWith('organizations/')).length,1);
});
test('cannot add another organization owner as staff',async()=>{
 const data=seed();data['organizations/business']={accessVersion:2,createdBy:'other'};data['memberships/other_business']=member('other','business','owner');
 await assert.rejects(add(fakeDb(data),'other@example.com'),/team_owner_account/);
});

test('staff email cannot be invited by another company owner',async()=>{
 const data=seed();data['organizations/other']={accessVersion:2,createdBy:'else'};data['memberships/worker_other']=member('worker','other','receptionist');
 await assert.rejects(add(fakeDb(data),'worker@example.com'),/team_other_employer/);
});
test('the common owner cannot authorize a second workplace',async()=>{
 const data=seed();data['organizations/other']={accessVersion:2,createdBy:'boss'};data['memberships/worker_other']=member('worker','other','receptionist');
 await assert.rejects(add(fakeDb(data),'worker@example.com'),/team_other_employer/);
});

for(const status of ['active','suspended','assignmentRequired'])test('other employer blocks '+status+' membership',async()=>{
 const data=seed();data['organizations/other']={accessVersion:2,createdBy:'else'};data['memberships/worker_other']=member('worker','other','receptionist',status);
 await assert.rejects(add(fakeDb(data),'worker@example.com'),/team_other_employer/);
});
test('pending invitation reserves employer; revocation and expiry release it',async()=>{
 for(const [status,expiresAt,blocked] of [['pending',null,true],['revoked',null,false],['pending',Ts.fromMillis(1),false]]){
  const data=seed();data['organizations/other']={accessVersion:2,createdBy:'else'};
  data['teamInvitations/reserved']={organizationId:'other',email:'worker@example.com',status,expiresAt};
  const db=fakeDb(data);if(blocked)await assert.rejects(add(db,'worker@example.com'),/team_other_employer/);else assert.ok((await add(db,'worker@example.com')).invitationId);
 }
});
test('former staff can create, remaining workplace still blocks, closed owner cannot join staff',async()=>{
 const data=seed();data['memberships/staff_work'].status='revoked';assert.ok((await create(fakeDb(data))).organizationId);
 data['organizations/other']={accessVersion:2,createdBy:'else'};data['memberships/staff_other']=member('staff','other','receptionist');await assert.rejects(create(fakeDb(data)),/org_staff_account/);
 data['organizations/business']={accessVersion:2,createdBy:'worker',closedAt:Ts.now()};data['memberships/worker_business']=member('worker','business','owner','revoked');
 await assert.rejects(add(fakeDb(data),'worker@example.com'),/team_owner_account/);
});
test('legacy creation uses same policy and creates a legacy admin, no direct-write bypass',async()=>{
 const fs=require('node:fs');assert.match(fs.readFileSync(require('node:path').join(__dirname,'../../firestore.rules'),'utf8'),/match \/organizations\/\{orgId\}[^]*?allow create: if false;/);
 const data=seed(),db=fakeDb(data),handler=createOrganizationSettingsHandler({db,Timestamp:Ts,HttpsError:CodeError,allowCreate:false});
 const call=uid=>handler({auth:auth(uid),data:{action:'createLegacy',operationId:'legacy',fields}});
 await assert.rejects(call('staff'),/org_staff_account/);
 const result=await call('normal');assert.equal(db.store.get('organizations/'+result.organizationId).accessVersion,undefined);assert.equal(db.store.get('memberships/normal_'+result.organizationId).role,'admin');
});
test('acceptance rechecks ownership and employer even after an invitation was issued',async()=>{
 const data=seed(),db=fakeDb(data),invite=await add(db,'worker@example.com');
 db.store.set('organizations/other',{accessVersion:2,createdBy:'else'});db.store.set('memberships/worker_other',member('worker','other','receptionist'));
 const team=createTeamHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const accept=()=>team({auth:auth('worker'),data:{organizationId:'work',operationId:'accept',action:'acceptInvitation',invitationId:invite.invitationId}});
 await assert.rejects(accept(),/team_other_employer/);assert.equal(db.store.get('teamInvitations/'+invite.invitationId).status,'pending');
 db.store.set('organizations/other',{accessVersion:2,createdBy:'worker'});db.store.set('memberships/worker_other',member('worker','other','owner'));await assert.rejects(accept(),/team_owner_account/);
});
test('ownership transfer does not permit an extra staff workplace',async()=>{
 const data=seed();data['organizations/other']={accessVersion:2,createdBy:'else',ownerTransferredTo:'boss'};data['memberships/worker_other']=member('worker','other','receptionist');
 await assert.rejects(add(fakeDb(data),'worker@example.com'),/team_other_employer/);
});

test('AI import cannot create an organization for staff',async()=>{
 const {createImport}=require('../ai_import');const data=seed();const records=[{key:'o',type:'organization',fields:{name:'Bypass'}}];
 data['aiDrafts/draft']={ownerId:'staff',status:'review',expiresAt:Ts.fromMillis(Date.now()+100000),records};const db=fakeDb(data);
 const handler=createImport({db,Timestamp:Ts,FieldValue:{},ai:{uid:r=>r.auth.uid,fail:(code,message)=>{throw new CodeError(code,message);}}});
 await assert.rejects(handler.commit({auth:auth('staff'),data:{draftId:'draft',records}}),/org_staff_account/);assert.equal(db.store.get('aiDrafts/draft').status,'review');
});

test('directory blocks unresolved mixed accounts without choosing an organization',async()=>{
 const {createOrganizationDirectory}=require('../organization_directory');const data=seed();
 data['organizations/business']={name:'Owned business',accessVersion:2,createdBy:'staff'};data['memberships/staff_business']=member('staff','business','owner');
 const result=await createOrganizationDirectory({db:fakeDb(data),HttpsError:CodeError})({auth:auth('staff'),data:{}});
 assert.equal(result.accountPolicy.mode,'conflict');assert.deepEqual(result.records.map(r=>r.id),[]);assert.equal(result.accountPolicy.canCreate,false);
});
test('two unrelated existing employers produce an actionable conflict and no workplace access',async()=>{
 const {createOrganizationDirectory}=require('../organization_directory');const data=seed();data['organizations/other']={accessVersion:2,createdBy:'else'};data['memberships/staff_other']=member('staff','other','receptionist');
 const result=await createOrganizationDirectory({db:fakeDb(data),HttpsError:CodeError})({auth:auth('staff'),data:{}});
 assert.equal(result.accountPolicy.staffConflict,'org_single_organization_review');assert.equal(result.records.length,0);
});
test('reactivating an old staff membership cannot bypass ownership or employer checks',async()=>{
 const data=seed();data['memberships/worker_work']=member('worker','work','receptionist','revoked');data['organizations/other']={accessVersion:2,createdBy:'else'};data['memberships/worker_other']=member('worker','other','receptionist');
 const db=fakeDb(data),team=createTeamHandler({db,Timestamp:Ts,HttpsError:CodeError});
 const call=status=>team({auth:auth('boss'),data:{organizationId:'work',operationId:status,action:'setAccess',userId:'worker',access:grant,status,reason:'Employment review'}});
 await assert.rejects(call('active'),/team_other_employer/);assert.equal((await call('revoked')).status,'revoked');
});

test('historical delegate grants cannot authorize a second workplace',async()=>{
 const data=seed();data['organizations/other']={accessVersion:2,createdBy:'boss'};data['memberships/worker_other']=member('worker','other','receptionist');
 data['memberships/admin_work']={...member('admin','work','administrator'),roleGrants:{...require('../team_access').templates.administrator.grants,assignAdditionalWorkplace:'all'}};
 const team=createTeamHandler({db:fakeDb(data),Timestamp:Ts,HttpsError:CodeError});
 await assert.rejects(team({auth:auth('admin'),data:{organizationId:'work',operationId:'delegate',action:'addStaff',profile:{displayName:'Worker',email:'worker@example.com'},access:grant}}),/team_other_employer/);
});

test('nobody can grant or edit retired additional workplace authority',()=>{
 const {canAssignGrants,canEditRole,templates}=require('../team_access');
 const actor={...member('admin','work','administrator'),roleGrants:{...templates.owner.grants}};
 const grants={manageTeam:'all',assignAdditionalWorkplace:'all'};
 assert.equal(canAssignGrants(actor,grants),false);
 assert.equal(canEditRole(actor,null,grants),false);
 assert.equal(canEditRole(actor,grants,{}),false);
 assert.equal(canAssignGrants(member('boss','work','owner'),grants),false);
 assert.equal(canEditRole(member('boss','work','owner'),null,grants),false);
 for(const [role,template] of Object.entries(templates))assert.equal(!!template.grants.assignAdditionalWorkplace,false);
});

test('historical approved second-workplace invitation cannot activate',async()=>{
 const data=seed();data['organizations/other']={accessVersion:2,createdBy:'boss'};data['memberships/worker_other']=member('worker','other','receptionist');
 data['teamInvitations/old']={organizationId:'work',email:'worker@example.com',status:'pending',expiresAt:null,invitedBy:'boss',employerApprovedBy:'boss',employerPrimary:false};
 const db=fakeDb(data),team=createTeamHandler({db,Timestamp:Ts,HttpsError:CodeError});
 await assert.rejects(team({auth:auth('worker'),data:{organizationId:'work',operationId:'claim-old',action:'acceptInvitation',invitationId:'old'}}),/team_other_employer/);
 assert.equal(db.store.get('teamInvitations/old').status,'pending');
});

test('revoked original workplace cannot be reactivated by an ordinary manager after a second workplace is active',async()=>{
 const data=seed();data['organizations/other']={accessVersion:2,createdBy:'boss'};
 data['memberships/worker_other']=member('worker','other','receptionist');
 data['memberships/worker_work']={...member('worker','work','receptionist','revoked'),employerPrimary:true,employerApprovedBy:'admin'};
 data['memberships/admin_work']=member('admin','work','administrator');
 const db=fakeDb(data),team=createTeamHandler({db,Timestamp:Ts,HttpsError:CodeError});
 await assert.rejects(team({auth:auth('admin'),data:{organizationId:'work',operationId:'reactivate-primary',action:'setAccess',userId:'worker',access:grant,status:'active',reason:'Return'}}),/team_other_employer/);
});
