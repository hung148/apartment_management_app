const {test,before,after,beforeEach}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc,deleteDoc,Timestamp:ClientTimestamp}=require('firebase/firestore');
const {initializeApp,getApps,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp,FieldValue}=require('firebase-admin/firestore');
const {createTeamHandler}=require('../team');
const {createTeamReadHandler,createInvitationLookupHandler}=require('../team_read');
const {createCalendarHandler,createTenantHandler}=require('../calendar');
const {createAI}=require('../ai');
const {createWorkspaceHandler}=require('../workspace');
const {createPaymentHandler}=require('../payments');
const {createOrganizationDirectory}=require('../organization_directory');
const {createHousekeepingHandler}=require('../housekeeping');
const {createPropertyDetailsHandler}=require('../property_details');
const {createRoomDetailsHandler}=require('../room_details');
const {createRoomRatesHandler}=require('../room_rates');
const {createBookingSettingsHandler}=require('../booking_settings');
const {migrationProposal}=require('../team_access');
let env,db,handler,readHandler,invitationLookup,calendar,tenant,ai;
before(async()=>{
  if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required; production is forbidden');
  env=await initializeTestEnvironment({projectId:'demo-apartment-calendar',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
  initializeApp({projectId:'demo-apartment-calendar'});db=getFirestore();
  handler=createTeamHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const deps={db,Timestamp:Timestamp,FieldValue:FieldValue,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
  readHandler=createTeamReadHandler(deps);invitationLookup=createInvitationLookupHandler(deps);calendar=createCalendarHandler(deps);tenant=createTenantHandler(deps);
  ai=createAI({...deps,generate:()=>{throw Error('No provider calls permitted');}});
});
after(async()=>{await env?.cleanup();await Promise.all(getApps().map(a=>deleteApp(a)));});
beforeEach(async()=>{
  await env.clearFirestore();
  await db.doc('organizations/org').set({createdBy:'owner',accessVersion:2});
  await db.doc('memberships/owner_org').set({organizationId:'org',ownerId:'owner',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]});
  await db.doc('staffProfiles/staff').set({organizationId:'org',displayName:'Staff',code:'S1',accountId:null,employmentStatus:'active'});
  await db.doc('buildings/a').set({organizationId:'org'});
});
const call=(data,uid='owner')=>handler({auth:{uid,token:{email:`${uid}@example.com`,email_verified:true}},data:{organizationId:'org',...data}});
const invitation={action:'invite',operationId:'invite',staffId:'staff',email:'new@example.com',access:{role:'receptionist',buildingScope:'selected',buildingIds:['a']}};

test('future tenant rent schedules preserve invoices, enforce price permission, immutable history and server dates',async()=>{
 const {createTenantRentHandler,rentForDate}=require('../tenant_rent'),Stamp=Timestamp;let now=Date.parse('2026-09-27T00:00:00Z');
 const api=createTenantRentHandler({db,Timestamp:{now:()=>Stamp.fromMillis(now)},HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=(d,uid='owner')=>api({auth:{uid},data:{organizationId:'org',buildingId:'a',tenantId:'rent',...d}});
 await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});await db.doc('rooms/r').set({organizationId:'org',buildingId:'a'});
 await db.doc('tenants/rent').set({organizationId:'org',buildingId:'a',roomId:'r',fullName:'Tenant',isMainTenant:true,status:'active',currency:'USD',monthlyRent:100,moveInDate:Stamp.fromDate(new Date('2026-09-01'))});
 await db.doc('payments/original').set({tenantId:'rent',amount:100,paidAmount:30});
 await setMember('manager','manager',{permissionOverrides:{overridePrices:false}});await assert.rejects(run({action:'read'},'manager'),e=>e.code==='permission-denied');await setMember('manager','manager');
 const r=(await run({action:'read'})).record;
 const command={action:'schedule',operationId:'schedule',revision:r.revision,currency:'USD',timeZone:r.timeZone,effectiveDate:'2026-10-01',amountMinor:15001,reason:'Private reason'};
 for(const patch of [{effectiveDate:'2026-09-27'},{effectiveDate:'2026-09-26'},{amountMinor:1.5},{reason:''},{paidAmount:1}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
 const result=await run(command,'manager');assert.deepEqual(await run(command,'manager'),result);await assert.rejects(run({...command,amountMinor:20000},'manager'),e=>e.code==='failed-precondition');await assert.rejects(run({...command,operationId:'stale'}),e=>e.code==='aborted');
 let row=(await db.doc('tenants/rent').get()).data();assert.equal(row.monthlyRent,100);assert.equal(rentForDate(row,'2026-09-30'),10000);assert.equal(rentForDate(row,'2026-10-01'),15001);assert.deepEqual((await db.doc('payments/original').get()).data(),{tenantId:'rent',amount:100,paidAmount:30});
 let read=(await run({action:'read'})).record;assert.equal(read.currentMinor,10000);
 await run({...command,operationId:'replace',revision:read.revision,amountMinor:16000});
 read=(await run({action:'read'})).record;const {amountMinor,...cancel}=command;await run({...cancel,action:'cancel',operationId:'cancel',revision:read.revision});assert.equal((await run({action:'read'})).record.changes.length,0);
 read=(await run({action:'read'})).record;await run({...command,operationId:'again',revision:read.revision});now=Date.parse('2026-09-30T17:00:00Z');read=(await run({action:'read'})).record;assert.equal(read.currentMinor,15001);await assert.rejects(run({...cancel,action:'cancel',operationId:'too-late',revision:read.revision}),e=>e.code==='invalid-argument');
 assert.equal((await db.collection('tenants/rent/rentHistory').get()).size,4);assert.ok(!JSON.stringify((await db.collection('teamActivity').get()).docs.map(v=>v.data())).includes('Private'));
 await assert.rejects(tenant({tenantId:'rent',tenant:{monthlyRent:50}},{auth:{uid:'owner'}}),e=>e.message==='tenant_rent_dedicated_workflow_required');await assert.rejects(tenant({tenantId:'rent',tenant:{rentSchedule:[]}},{auth:{uid:'owner'}}),e=>e.message==='tenant_rent_dedicated_workflow_required');
 await db.doc('memberships/manager_org').update({status:'suspended'});await assert.rejects(run(command,'manager'),e=>e.code==='permission-denied');
 const client=env.authenticatedContext('owner').firestore();await assertFails(getDoc(doc(client,'tenants/rent/rentHistory/private')));
});

test('rent changes reject roommates, wrong scope and stale concurrent writes',async()=>{
 const {createTenantRentHandler}=require('../tenant_rent');const api=createTenantRentHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=(data,uid='owner')=>api({auth:{uid},data:{organizationId:'org',buildingId:'a',tenantId:'rent',...data}});
 await db.doc('buildings/a').update({timeZone:'UTC'});await db.doc('tenants/rent').set({organizationId:'org',buildingId:'a',roomId:'r',isMainTenant:false,status:'active',monthlyRent:100,currency:'VND',moveInDate:Timestamp.fromMillis(1000)});
 await assert.rejects(run({action:'read'}),e=>e.code==='failed-precondition');await db.doc('tenants/rent').update({isMainTenant:true});
 await setMember('manager','manager',{buildingIds:['b']});await assert.rejects(run({action:'read'},'manager'),e=>e.code==='permission-denied');
 const r=(await run({action:'read'})).record,c={action:'schedule',revision:r.revision,currency:r.currency,timeZone:r.timeZone,effectiveDate:'2100-01-01',amountMinor:200,reason:'Amendment'};
 const results=await Promise.allSettled(['one','two'].map(operationId=>run({...c,operationId})));assert.equal(results.filter(v=>v.status==='fulfilled').length,1);assert.equal(results.find(v=>v.status==='rejected').reason.code,'aborted');
});

test('roommates link to an active main tenant without charges, validate dates and protect legacy mutations',async()=>{
 const {createTenantRoommatesHandler}=require('../tenant_roommates'),Stamp=Timestamp,fixed=Date.parse('2026-09-27T00:00:00Z');
 const api=createTenantRoommatesHandler({db,Timestamp:{now:()=>Stamp.fromMillis(fixed),fromMillis:v=>Stamp.fromMillis(v)},HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=(data,uid='owner')=>api({auth:{uid},data:{organizationId:'org',buildingId:'a',mainTenantId:'main',...data}});
 await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});
 await db.doc('rooms/shared').set({organizationId:'org',buildingId:'a',rentalMode:'monthly',currency:'VND'});
 await db.doc('tenants/main').set({organizationId:'org',buildingId:'a',roomId:'shared',fullName:'Main',status:'active',isMainTenant:true,moveInDate:Stamp.fromDate(new Date('2026-09-01T05:00:00Z')),monthlyRent:1000,currency:'USD'});
 await setMember('manager','manager');
 const r=(await run({action:'prepare'})).record;
 const command={action:'create',operationId:'roommate',mainRevision:r.mainRevision,roomRevision:r.roomRevision,timeZone:r.timeZone,fullName:'Private roommate',phoneNumber:'Private phone',moveInDate:'2026-09-01',backdateReason:'Private reason'};
 await assert.rejects(run(command,'manager'),e=>e.code==='permission-denied');
 await assert.rejects(run({...command,moveInDate:'2026-08-31'}),e=>e.message==='roommate_before_main');
 await assert.rejects(run({...command,backdateReason:''}),e=>e.code==='invalid-argument');
 for(const patch of [{rentMinor:100},{roomId:'forged'},{isMainTenant:true},{fullName:' '},{phoneNumber:'x'.repeat(81)}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
 for(const role of ['receptionist','viewer','accountant','housekeeper']){await setMember(role,role);await assert.rejects(run({action:'prepare'},role),e=>e.code==='permission-denied');}
 const result=await run(command);assert.deepEqual(await run(command),result);await assert.rejects(run({...command,fullName:'changed'}),e=>e.code==='failed-precondition');
 const child=(await db.doc(`tenants/${result.tenantId}`).get()).data();assert.equal(child.mainTenantId,'main');assert.equal(child.isMainTenant,false);assert.equal(child.roomId,'shared');assert.equal(child.currency,'USD');assert.equal(child.moveInDate.toMillis(),Date.parse('2026-09-01T05:00:00Z'));assert.equal(child.monthlyRent,undefined);assert.equal(child.deposit,undefined);assert.equal(child.createdAt.toMillis(),fixed);
 assert.equal((await db.collection('payments').get()).size,0);assert.equal((await db.collection('leaseDateCorrections').get()).size,1);assert.ok(!JSON.stringify((await db.collection('teamActivity').get()).docs.map(v=>v.data())).includes('Private'));
 await tenant({tenantId:'main',tenant:{fullName:'Renamed'}},{auth:{uid:'owner'}});
 await assert.rejects(tenant({tenantId:'main',tenant:{status:'moveOut',moveOutDate:{__timestamp:fixed}}},{auth:{uid:'owner'}}),e=>e.message==='lease_linked_roommates_require_review');
 await assert.rejects(tenant({tenantId:result.tenantId,tenant:{monthlyRent:999}},{auth:{uid:'owner'}}),e=>e.message==='roommate_dedicated_workflow_required');
 await assert.rejects(tenant({tenantId:result.tenantId,tenant:{isMainTenant:true}},{auth:{uid:'owner'}}),e=>e.message==='roommate_dedicated_workflow_required');
 await assert.rejects(tenant({create:true,tenantId:'bypass',tenant:{organizationId:'org',roomId:'shared',isMainTenant:false,mainTenantId:'main',fullName:'Bad',status:'active',moveInDate:{__timestamp:fixed}}},{auth:{uid:'owner'}}),e=>e.message==='roommate_dedicated_workflow_required');
 await setMember('outsider','manager',{buildingIds:['b']});await assert.rejects(run({action:'prepare'},'outsider'),e=>e.code==='permission-denied');
 await db.doc('memberships/owner_org').update({status:'suspended'});await assert.rejects(run(command),e=>e.code==='permission-denied');
 const client=env.authenticatedContext('manager').firestore();await assertFails(getDoc(doc(client,'tenantRoommateOperations/private')));
});

test('roommate preparation rejects unusable parents and creation detects stale parents and concurrent occupancy writes',async()=>{
 const {createTenantRoommatesHandler}=require('../tenant_roommates'),Stamp=Timestamp;
 const api=createTenantRoommatesHandler({db,Timestamp:Stamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=data=>api({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'a',mainTenantId:'main',...data}});
 await db.doc('buildings/a').update({timeZone:'UTC'});await db.doc('rooms/shared').set({organizationId:'org',buildingId:'a',rentalMode:'both'});
 const parent={organizationId:'org',buildingId:'a',roomId:'shared',fullName:'Main',status:'active',isMainTenant:true,moveInDate:Stamp.fromDate(new Date('2100-01-01'))};
 for(const patch of [{status:'suspended'},{status:'moveOut'},{isMainTenant:false},{moveOutDate:Stamp.fromDate(new Date('2100-02-01'))}]){await db.doc('tenants/main').set({...parent,...patch});await assert.rejects(run({action:'prepare'}),e=>e.code==='failed-precondition');}
 await db.doc('tenants/main').set(parent);
 const command=async()=>{const r=(await run({action:'prepare'})).record;return {action:'create',operationId:'race',mainRevision:r.mainRevision,roomRevision:r.roomRevision,timeZone:r.timeZone,fullName:'Roommate',phoneNumber:'',moveInDate:'2100-01-02',backdateReason:''};};
 const stale=await command();await db.doc('tenants/main').update({fullName:'Changed'});await assert.rejects(run(stale),e=>e.code==='aborted');
 const c=await command(),results=await Promise.allSettled([run(c),run({...c,operationId:'other'})]);assert.equal(results.filter(v=>v.status==='fulfilled').length,1);assert.equal(results.find(v=>v.status==='rejected').reason.code,'aborted');
 const next={...await command(),operationId:'booking-check'};await db.doc('bookings/legacy').set({roomId:'shared',status:'confirmed',endTime:Stamp.fromDate(new Date('2100-03-01'))});await assert.rejects(run(next),e=>e.code==='already-exists');
 await db.doc('bookings/legacy').delete();await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});await assert.rejects(run(next),e=>e.code==='aborted');
});

test('new lease creation validates scoped room data, private dates, exact money and immutable retry',async()=>{
 const {createTenantLeasesHandler}=require('../tenant_leases');
 const Stamp=Timestamp,fixed=Date.parse('2026-09-27T00:30:00Z');
 const api=createTenantLeasesHandler({db,Timestamp:{now:()=>Stamp.fromMillis(fixed),fromMillis:v=>Stamp.fromMillis(v)},HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=(data,uid='owner')=>api({auth:{uid},data:{organizationId:'org',buildingId:'a',roomId:'new-room',...data}});
 await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});
 await db.doc('rooms/new-room').set({organizationId:'org',buildingId:'a',roomNumber:'101',currency:'USD',rentalMode:'both'});
 await setMember('manager','manager');
 const record=(await run({action:'prepare'},'manager')).record;assert.equal(record.today,'2026-09-27');assert.equal(record.canBackdate,false);
 const command={action:'create',operationId:'new-lease',roomRevision:record.roomRevision,currency:'USD',timeZone:record.timeZone,fullName:' Private Tenant ',phoneNumber:'+84 private',moveInDate:'2026-09-26',contractEndDate:'2027-09-26',rentMinor:12345,backdateReason:'Private reason'};
 for(const role of ['receptionist','housekeeper','accountant','viewer']){await setMember(role,role);await assert.rejects(run({action:'prepare'},role),e=>e.code==='permission-denied');}
 await assert.rejects(run(command,'manager'),e=>e.code==='permission-denied');
 for(const patch of [{rentMinor:1.1},{rentMinor:0},{status:'inactive'},{createdAt:1},{moveInDate:'2026-02-30'},{contractEndDate:'2020-01-01'},{fullName:' '},{phoneNumber:'x'.repeat(81)}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
 await assert.rejects(run({...command,backdateReason:''}),e=>e.code==='invalid-argument');
 await assert.rejects(run({...command,currency:'VND'}),e=>e.code==='aborted');
 await assert.rejects(run({...command,timeZone:'UTC'}),e=>e.code==='aborted');
 const result=await run(command);assert.deepEqual(await run(command),result);
 await assert.rejects(run({...command,fullName:'changed'}),e=>e.code==='failed-precondition');
 const row=(await db.doc(`tenants/${result.tenantId}`).get()).data();assert.equal(row.fullName,'Private Tenant');assert.equal(row.monthlyRent,123.45);assert.equal(row.monthlyRentMinor,12345);assert.equal(row.isMainTenant,true);assert.equal(row.moveOutDate,null);assert.equal(row.moveInDate.toMillis(),Date.parse('2026-09-25T17:00:00Z'));assert.equal(row.createdAt.toMillis(),fixed);assert.equal(row.backdateReason,undefined);assert.equal(row.deposit,undefined);
 assert.equal((await db.collection('payments').get()).size,0);assert.equal((await db.collection('leaseDateCorrections').get()).size,1);
 assert.ok(!JSON.stringify((await db.collection('teamActivity').get()).docs.map(v=>v.data())).includes('Private'));
 await db.doc('memberships/owner_org').update({status:'suspended'});await assert.rejects(run(command),e=>e.code==='permission-denied');
});

test('lease creation blocks occupancy and bookings, paginates rooms and serializes competing creates',async()=>{
 const {createTenantLeasesHandler}=require('../tenant_leases'),Stamp=Timestamp;
 const api=createTenantLeasesHandler({db,Timestamp:Stamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=data=>api({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'a',...data}});
 await db.doc('buildings/a').update({timeZone:'UTC'});
 const batch=db.batch();for(let i=0;i<27;i++)batch.set(db.doc(`rooms/r${String(i).padStart(2,'0')}`),{organizationId:'org',buildingId:'a',roomNumber:`${i}`,currency:'VND',rentalMode:i===26?'hourly':'monthly'});await batch.commit();
 const page=await run({action:'rooms'}),page2=await run({action:'rooms',cursor:page.nextCursor});assert.equal(page.records.length,25);assert.equal(page2.records.length,2);assert.equal(page2.records[1].monthly,true);
 assert.equal((await run({action:'prepare',roomId:'r26'})).record.roomNumber,'26');
 const command=async roomId=>({action:'create',roomId,operationId:roomId,roomRevision:(await run({action:'prepare',roomId})).record.roomRevision,currency:'VND',timeZone:'UTC',fullName:'Tenant',phoneNumber:'',moveInDate:'2100-01-01',contractEndDate:'2100-02-01',rentMinor:1000000,backdateReason:''});
 for(const status of ['active','suspended']){
  await db.doc('tenants/occupant').set({organizationId:'org',roomId:'r00',status,isMainTenant:false,moveInDate:Stamp.fromMillis(1)});
  await assert.rejects(run(await command('r00')),e=>e.message==='lease_room_occupied');
 }
 await db.doc('tenants/occupant').update({status:'moveOut'});
 await db.doc('bookings/future').set({organizationId:'org',roomId:'r00',status:'confirmed',startTime:Stamp.fromDate(new Date('2100-03-01')),endTime:Stamp.fromDate(new Date('2100-03-02'))});
 await assert.rejects(run(await command('r00')),e=>e.message==='booking_conflict'); // after contract expiry still blocks
 await db.doc('bookings/future').update({status:'cancelled'});
 const c=await command('r00'),results=await Promise.allSettled([run(c),run({...c,operationId:'competing'})]);assert.equal(results.filter(v=>v.status==='fulfilled').length,1);assert.equal(results.find(v=>v.status==='rejected').reason.code,'aborted');
 // The legacy endpoint must not add a competing main tenant after the new flow.
 await assert.rejects(tenant({create:true,tenantId:'legacy-competing',tenant:{organizationId:'org',roomId:'r00',fullName:'Competing',status:'active',moveInDate:{__timestamp:Date.parse('2100-01-02T00:00:00Z')}}},{auth:{uid:'owner'}}),e=>e.message==='lease_room_occupied');
 await db.doc('rooms/r03').update({rentalMode:'both'});
 const race=await command('r03'),competing=await Promise.allSettled([
  run(race),calendar({action:'create',bookingId:'new-lease-race',booking:{organizationId:'org',roomId:'r03',guestName:'Guest',startTime:{__timestamp:Date.parse('2100-01-02T00:00:00Z')},endTime:{__timestamp:Date.parse('2100-01-02T01:00:00Z')},totalPrice:100}},{auth:{uid:'owner'}}),
 ]);assert.equal(competing.filter(v=>v.status==='fulfilled').length,1);assert.ok(['aborted','already-exists'].includes(competing.find(v=>v.status==='rejected').reason.code));
 await setMember('manager','manager',{buildingIds:['b']});
 await assert.rejects(api({auth:{uid:'manager'},data:{action:'rooms',organizationId:'org',buildingId:'a'}}),e=>e.code==='permission-denied');
 await db.doc('rooms/foreign').set({organizationId:'elsewhere',buildingId:'a'});await assert.rejects(run({action:'prepare',roomId:'foreign'}),e=>e.code==='not-found');
 const stale=await command('r01');await db.doc('rooms/r01').update({currency:'USD'});await assert.rejects(run(stale),e=>e.code==='aborted');
 const fresh=await command('r02');await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});await assert.rejects(run(fresh),e=>e.code==='aborted');
});

test('lease dates enforce owner/admin backdating, private reasons and server metadata through the legacy callable',async()=>{
 const fixed=Date.parse('2026-09-27T00:30:00Z'),Stamp=Timestamp;
 const api=createTenantHandler({db,Timestamp:{now:()=>Stamp.fromMillis(fixed),fromMillis:v=>Stamp.fromMillis(v)},FieldValue:FieldValue,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=(tenantId,patch,uid='owner',create=true)=>api({tenantId,create,tenant:{organizationId:'org',roomId:'date-room',fullName:'Tenant',status:'inactive',moveInDate:{__timestamp:fixed},...patch}},{auth:{uid}});
 await setMember('manager','manager');await setMember('admin','administrator');
 await db.doc('rooms/date-room').set({organizationId:'org',buildingId:'a',rentalMode:'monthly'});
 await assert.rejects(run('no-zone',{}),e=>e.message==='lease_property_timezone_required');
 await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});
 const past={moveInDate:{__timestamp:Date.parse('2026-09-25T17:00:00Z')}};
 await assert.rejects(run('manager-past',{...past,backdateReason:'Reason',today:'2020-01-01',createdAt:{__timestamp:1}},'manager'),e=>e.message==='lease_backdate_owner_admin_required');
 await assert.rejects(run('owner-no-reason',past),e=>e.message==='lease_backdate_reason_required');
 await assert.rejects(run('owner-empty-reason',{...past,backdateReason:'  '}),e=>e.message==='lease_backdate_reason_required');
 await assert.rejects(run('owner-long-reason',{...past,backdateReason:'x'.repeat(1001)}),e=>e.message==='lease_backdate_reason_invalid');
 await run('today',{moveInDate:{__timestamp:Date.parse('2026-09-26T17:00:00Z')},moveInTimeZone:'UTC',moveInLocalDate:'1999-01-01',createdAt:{__timestamp:1},createdBy:'forged'},'manager');
 const today=(await db.doc('tenants/today').get()).data();assert.equal(today.moveInLocalDate,'2026-09-27');assert.equal(today.moveInTimeZone,'Asia/Ho_Chi_Minh');assert.equal(today.createdAt.toMillis(),fixed);assert.equal(today.createdBy,'manager');
 await run('future',{moveInDate:{__timestamp:Date.parse('2026-09-28T00:00:00Z')}},'manager');
 for(const uid of ['owner','admin']){
  const patch={...past,backdateReason:'  PRIVATE import reason  '};
  await run(uid,patch,uid);await run(uid,patch,uid);
  const stored=(await db.doc(`tenants/${uid}`).get()).data();assert.equal(stored.backdateReason,undefined);assert.equal(stored.createdAt.toMillis(),fixed);assert.equal(stored.moveInLocalDate,'2026-09-26');
 }
 assert.equal((await db.collection('leaseDateCorrections').get()).size,2);
 const correction=(await db.collection('leaseDateCorrections').get()).docs[0];
 assert.equal(correction.data().reason,'PRIVATE import reason');assert.equal(correction.data().createdAt.toMillis(),fixed);
 assert.ok(!JSON.stringify((await db.collection('teamActivity').get()).docs.map(v=>v.data())).includes('PRIVATE'));
 await assert.rejects(run('future',{...past,backdateReason:'Attempt'},'manager',false),e=>e.code==='permission-denied');
 await run('future',{...past,backdateReason:'Authorized correction'},'owner',false);
 assert.equal((await db.collection('leaseDateCorrections').get()).size,3);
 // A historical tenant remains editable without silently changing its date or evidence.
 await api({tenantId:'owner',tenant:{fullName:'Contact edit',moveInLocalDate:'forged',moveInTimeZone:'UTC'}},{auth:{uid:'manager'}});
 assert.equal((await db.doc('tenants/owner').get()).data().moveInLocalDate,'2026-09-26');
 assert.equal((await db.doc('tenants/owner').get()).data().moveInTimeZone,'Asia/Ho_Chi_Minh');
 assert.equal((await db.collection('leaseDateCorrections').get()).size,3);
 await assert.rejects(api({tenantId:'owner',tenant:{backdateReason:'Replace evidence'}},{auth:{uid:'owner'}}),e=>e.message==='lease_backdate_reason_without_date_change');
 await db.doc('memberships/admin_org').update({status:'suspended'});
 await assert.rejects(run('admin',{...past,backdateReason:'PRIVATE import reason'},'admin'),e=>e.code==='permission-denied');
 const client=env.authenticatedContext('owner').firestore();
 await assertFails(getDoc(doc(client,correction.ref.path)));
 await assertFails(setDoc(doc(client,correction.ref.path),{reason:'forged'}));
 await assertFails(updateDoc(doc(client,'tenants/owner'),{moveInDate:ClientTimestamp.fromMillis(1)}));
});

test('tenant contact directory scopes pages and edits only contact fields with private audit and exact retries',async()=>{
 const {createTenantContactsHandler}=require('../tenant_contacts');
 const handler=createTenantContactsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=(data,uid='owner',buildingId='a')=>handler({auth:{uid},data:{organizationId:'org',buildingId,...data}});
 const batch=db.batch();for(let i=0;i<27;i++)batch.set(db.doc(`tenants/t${String(i).padStart(2,'0')}`),{organizationId:'org',buildingId:'a',roomId:'room',fullName:'Private name',phoneNumber:'Private phone',status:i===0?'moveOut':'active',nationalId:'secret',monthlyRent:100,deposit:200,moveInDate:Timestamp.fromMillis(1000),currency:'USD'});await batch.commit();
 await db.doc('tenants/foreign').set({organizationId:'elsewhere',buildingId:'a',fullName:'foreign'});await db.doc('buildings/b').set({organizationId:'org'});
 await setMember('manager','manager');const first=await run({action:'list'},'manager');assert.equal(first.records.length,25);assert.equal(first.records[0].status,'moveOut');assert.ok(!JSON.stringify(first).includes('secret'));assert.equal(first.records[0].monthlyRent,undefined);assert.equal(first.records[0].monthlyRentMinor,null);assert.equal(first.records[0].nationalId,'•••• cret');assert.equal(first.records[0].canReadIds,false);
 const second=await run({action:'list',cursor:first.nextCursor},'manager');assert.equal(second.records.length,2);assert.equal(second.nextCursor,null);
 for(const role of ['receptionist','housekeeper','accountant','viewer']){await setMember(role,role);await assert.rejects(run({action:'list'},role),e=>e.code==='permission-denied');}
 await assert.rejects(run({action:'list'},'manager','b'),e=>e.code==='permission-denied');await assert.rejects(run({action:'read',tenantId:'foreign'}),e=>e.code==='not-found');
 const before=(await db.doc('tenants/t00').get()).data(),r=(await run({action:'read',tenantId:'t00'})).record;
 assert.deepEqual(Object.keys(r).sort(),['id','fullName','phoneNumber','roomId','roomNumber','status','revision','canAddRoommate','canEditRent','canReadRentHistory','canBill','canSettle','settled','mainTenantId','isMainTenant','mainTenantName','moveInLocalDate','contractEndLocalDate','currency','monthlyRentMinor','nationalId','residenceRegistered','residenceRegisteredLocalDate','paymentPeriodMonths','paymentDueDay','periodRentMinor','depositMinor','depositMethod','depositAccountLabel','depositNote','staffName','canReadIds','contractEnded','moveOutLocalDate','roommates','stayStatus','surcharges'].sort());
 assert.deepEqual(r.roommates,[]);assert.deepEqual(r.surcharges,[]);assert.equal(r.moveOutLocalDate,'');
 const command={action:'update',tenantId:'t00',operationId:'contact',revision:r.revision,fullName:'New name',phoneNumber:'+84 123'};
 for(const patch of [{status:'active'},{nationalId:'forged'},{monthlyRent:1},{fullName:' '},{phoneNumber:'x'.repeat(81)}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
 const result=await run(command,'manager');assert.deepEqual(await run(command,'manager'),result);
 await assert.rejects(run({...command,phoneNumber:'different'},'manager'),e=>e.code==='failed-precondition');
 await assert.rejects(run({...command,operationId:'stale'}),e=>e.code==='aborted');
 const after=(await db.doc('tenants/t00').get()).data();for(const k of ['status','roomId','monthlyRent','deposit','currency','nationalId'])assert.deepEqual(after[k],before[k]);assert.equal(after.moveInDate.toMillis(),1000);assert.equal(after.updatedBy,'manager');assert.ok(after.updatedAt.toMillis()>1000);
 const audit=(await db.collection('teamActivity').get()).docs[0].data();assert.ok(!JSON.stringify(audit).includes('New name'));assert.ok(!JSON.stringify(audit).includes('+84'));assert.deepEqual(audit.after.changedFields,['fullName','phoneNumber']);
 await db.doc('memberships/manager_org').update({status:'suspended'});await assert.rejects(run(command,'manager'),e=>e.code==='permission-denied');
 const client=env.authenticatedContext('owner').firestore();await assertFails(updateDoc(doc(client,'tenants/t00'),{fullName:'bypass'}));await assertFails(getDoc(doc(client,'tenantContactOperations/private')));
});

test('tenant contact concurrent edits serialize without losing a competing update',async()=>{
 const {createTenantContactsHandler}=require('../tenant_contacts');const handler=createTenantContactsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 await db.doc('tenants/contact-race').set({organizationId:'org',buildingId:'a',roomId:'room',fullName:'Original',phoneNumber:'',status:'active'});
 const run=data=>handler({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'a',tenantId:'contact-race',...data}});
 const revision=(await run({action:'read'})).record.revision;
 const results=await Promise.allSettled(['first','second'].map(operationId=>run({action:'update',operationId,revision,fullName:operationId,phoneNumber:''})));
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.code,'aborted');
});

test('contract history pages tied timestamps without ledger leakage and rechecks scope on every page',async()=>{
  const {createPropertyContractHandler}=require('../property_contract');
  const handler=createPropertyContractHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=(data={},uid='owner',buildingId='a')=>handler({auth:{uid},data:{action:'history',organizationId:'org',buildingId,...data}});
  assert.deepEqual(await run(),{records:[],nextCursor:null});
  const value={direction:'rentOut',status:'active',partyName:'Party',partyPhone:'Phone',amountMinor:12345,dueDay:1,startDate:'2030-01-01',endDate:null,notes:'Notes'};
  const batch=db.batch();
  for(let i=0;i<23;i++)batch.set(db.doc(`buildings/a/rentalContractHistory/${i.toString(16).padStart(64,'0')}`),{organizationId:'org',actorId:'manager',currency:'USD',createdAt:Timestamp.fromMillis(1000),before:null,after:{...value,unknown:'secret'},fingerprint:'secret',result:{secret:true}});
  await batch.commit();await setMember('manager','manager');
  const first=await run({},'manager');assert.equal(first.records.length,20);assert.ok(first.nextCursor);
  const second=await run({cursor:first.nextCursor},'manager');assert.equal(second.records.length,3);assert.equal(second.nextCursor,null);
  const ids=[...first.records,...second.records].map(r=>r.id);assert.equal(new Set(ids).size,23);assert.deepEqual(ids,[...ids].sort().reverse());
  assert.deepEqual(first.records[0].after,value);assert.equal(first.records[0].createdAt,'1970-01-01T00:00:01.000Z');assert.ok(!JSON.stringify(first).includes('secret'));
  await assert.rejects(run({cursor:'../bad'}),e=>e.code==='invalid-argument');
  await assert.rejects(run({cursor:'f'.repeat(64)}),e=>e.code==='invalid-argument');
  await db.doc('buildings/b').set({organizationId:'org'});
  await assert.rejects(run({cursor:first.nextCursor},'owner','b'),e=>e.code==='invalid-argument');
  await assert.rejects(run({},'manager','b'),e=>e.code==='permission-denied');
  await db.doc('memberships/manager_org').update({status:'suspended'});
  await assert.rejects(run({cursor:first.nextCursor},'manager'),e=>e.code==='permission-denied');
  await setMember('viewer','viewer');await assert.rejects(run({},'viewer'),e=>e.code==='permission-denied');
});

test('property contracts preserve legacy data, validate scope, store revisions and never create payments',async()=>{
  const {createPropertyContractHandler}=require('../property_contract');
  const deps={db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
  const contract=createPropertyContractHandler(deps),property=createPropertyDetailsHandler(deps);
  await db.doc('buildings/a').update({name:'A',currency:'USD',managementType:'rented',renterName:'Legacy',rentAmount:999});
  const run=(data,uid='owner',buildingId='a')=>contract({auth:{uid},data:{organizationId:'org',buildingId,...data}});
  const first=(await run({action:'read'})).record;
  assert.equal(first.contract,null);assert.equal(first.legacy.renterName,'Legacy');
  const value={direction:'rentIn',status:'active',partyName:'Landlord',partyPhone:'private phone',amountMinor:12345,dueDay:31,startDate:'2030-01-01',endDate:null,notes:'private notes'};
  const command={action:'update',operationId:'contract',revision:first.revision,currency:'USD',contract:value};
  for(const role of ['receptionist','housekeeper','accountant','viewer']){await setMember(role,role);await assert.rejects(run({action:'read'},role),e=>e.code==='permission-denied');await assert.rejects(run(command,role),e=>e.code==='permission-denied');}
  await setMember('manager','manager');await db.doc('buildings/b').set({organizationId:'org',currency:'USD'});
  await assert.rejects(run({action:'read'},'manager','b'),e=>e.code==='permission-denied');
  for(const patch of [{actorId:'fake'},{contract:{...value,endDate:'2030-02-30'}},{contract:{...value,direction:'rented'}}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
  await assert.rejects(run({...command,currency:'VND'}),e=>e.code==='aborted');
  const result=await run(command,'manager');assert.deepEqual(await run(command,'manager'),result);
  await assert.rejects(run({...command,contract:{...value,notes:'changed'}},'manager'),e=>e.code==='failed-precondition');
  assert.deepEqual((await run({action:'read'})).record.contract,value);
  assert.equal((await db.doc('buildings/a').get()).data().rentAmount,999);
  assert.equal((await db.collection('payments').get()).size,0);
  assert.equal((await db.collection('buildings/a/rentalContractHistory').get()).size,1);
  const audit=(await db.collection('teamActivity').get()).docs[0].data();
  assert.ok(!JSON.stringify(audit).includes('private'));assert.equal(audit.actorId,'manager');assert.ok(audit.createdAt.toMillis()>0);
  await assert.rejects(run({...command,operationId:'stale'}),e=>e.code==='aborted');
  const current=(await run({action:'read'})).record;
  await run({...command,operationId:'out',revision:current.revision,contract:{...value,direction:'rentOut',status:'ended',endDate:'2030-12-31'}});
  assert.equal((await db.collection('buildings/a/rentalContractHistory').get()).size,2);
  const p=(await property({auth:{uid:'owner'},data:{action:'read',organizationId:'org',buildingId:'a'}})).record;
  await assert.rejects(property({auth:{uid:'owner'},data:{action:'delete',organizationId:'org',buildingId:'a',operationId:'delete-contract',revision:p.revision}}),e=>e.message==='property_not_empty');
  await db.doc('memberships/manager_org').update({status:'suspended'});
  await assert.rejects(run(command,'manager'),e=>e.code==='permission-denied');
  const client=env.authenticatedContext('owner').firestore();
  await assertFails(getDoc(doc(client,'buildings/a/rentalContractHistory/private')));
  await assertFails(updateDoc(doc(client,'buildings/a'),{rentalContract:value}));
});

test('concurrent property contract changes accept only one revision',async()=>{
  const {createPropertyContractHandler}=require('../property_contract');
  const handler=createPropertyContractHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=data=>handler({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'a',...data}});
  const revision=(await run({action:'read'})).record.revision;
  const value={direction:'rentIn',status:'active',partyName:'Party',partyPhone:'',amountMinor:100,dueDay:1,startDate:'2030-01-01',endDate:null,notes:''};
  const result=await Promise.allSettled(['rentIn','rentOut'].map(direction=>run({action:'update',operationId:direction,revision,currency:'VND',contract:{...value,direction}})));
  assert.equal(result.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(result.find(r=>r.status==='rejected').reason.code,'aborted');
  assert.equal((await db.collection('buildings/a/rentalContractHistory').get()).size,1);
});

test('weekly room schedules persist, protect existing bookings, reject old-client erasure and enforce date exceptions',async()=>{
  const deps={db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
  const settings=createBookingSettingsHandler(deps),property=createPropertyDetailsHandler(deps);
  await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh',name:'A',address:'Address'});
  await db.doc('rooms/schedule').set({organizationId:'org',buildingId:'a',roomNumber:'101',rentalMode:'both',currency:'VND'});
  const run=(data,uid='owner')=>settings({auth:{uid},data:{organizationId:'org',buildingId:'a',roomId:'schedule',...data}});
  const book=(id,start,end)=>calendar({action:'create',bookingId:id,booking:{organizationId:'org',roomId:'schedule',guestName:'Guest',startTime:{__timestamp:Date.parse(start)},endTime:{__timestamp:Date.parse(end)},totalPrice:100000}},{auth:{uid:'owner'}});
  const schedule={week:Object.fromEntries(Array.from({length:7},(_,i)=>[i,[{start:480,end:720},{start:840,end:1320}]])),exceptions:{'2030-01-08':[{start:600,end:1020}],'2030-01-09':[]}};
  schedule.week[6]=[];
  const command={action:'update',operationId:'weekly',revision:(await run({action:'read'})).record.revision,timeZone:'Asia/Ho_Chi_Minh',minBookingHours:0,cleaningBufferMinutes:0,operatingHoursStartMin:null,operatingHoursEndMin:null,operatingSchedule:schedule};
  await setMember('worker','housekeeper');await assert.rejects(run(command,'worker'),e=>e.code==='permission-denied');
  await assert.rejects(run({...command,operatingHoursStartMin:480,operatingHoursEndMin:720}),e=>e.code==='invalid-argument');
  await assert.rejects(run({...command,operatingSchedule:{...schedule,extra:true}}),e=>e.code==='invalid-argument');
  const result=await run(command);assert.deepEqual(await run(command),result);
  assert.deepEqual((await run({action:'read'})).record.operatingSchedule,schedule);
  await book('mon-morning','2030-01-07T01:00Z','2030-01-07T05:00Z');
  await book('exception-open','2030-01-08T03:00Z','2030-01-08T10:00Z');
  for(const [id,a,b] of [['gap','2030-01-10T04:00Z','2030-01-10T08:00Z'],['sunday','2030-01-06T01:00Z','2030-01-06T02:00Z'],['late','2030-01-08T01:00Z','2030-01-08T02:00Z'],['closed-date','2030-01-09T01:00Z','2030-01-09T02:00Z']])await assert.rejects(book(id,a,b),e=>e.message==='booking_outside_operating_hours');
  const latest=(await run({action:'read'})).record;
  const oldClient={...command,operationId:'old-client',revision:latest.revision};delete oldClient.operatingSchedule;
  await assert.rejects(run(oldClient),e=>e.message==='settings_client_update_required');
  const incompatible=structuredClone(schedule);incompatible.exceptions['2030-01-07']=[];
  await assert.rejects(run({...command,operationId:'conflict',revision:latest.revision,operatingSchedule:incompatible}),e=>e.message==='settings_existing_conflict');
  const propertyCall=data=>property({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'a',...data}});
  const p=(await propertyCall({action:'read'})).record;
  await assert.rejects(propertyCall({action:'update',operationId:'zone-with-week',revision:p.revision,name:'A',address:'Address',timeZone:'UTC'}),e=>e.message==='property_timezone_in_use');
  await run({...command,operationId:'disable-week',revision:latest.revision,operatingSchedule:null});
  await book('formerly-closed','2030-01-09T01:00Z','2030-01-09T02:00Z');
});

test('date closure update cannot race a booking into the newly closed day',async()=>{
  const settings=createBookingSettingsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  await db.doc('buildings/a').update({timeZone:'UTC'});
  await db.doc('rooms/date-race').set({organizationId:'org',buildingId:'a',rentalMode:'both',currency:'VND'});
  const ctx={auth:{uid:'owner'}},identity={organizationId:'org',buildingId:'a',roomId:'date-race'};
  const revision=(await settings({...ctx,data:{action:'read',...identity}})).record.revision;
  const results=await Promise.allSettled([
    settings({...ctx,data:{action:'update',...identity,operationId:'close-date',revision,timeZone:'UTC',minBookingHours:0,cleaningBufferMinutes:0,operatingHoursStartMin:null,operatingHoursEndMin:null,operatingSchedule:{week:Object.fromEntries(Array.from({length:7},(_,i)=>[i,[{start:0,end:1440}]])),exceptions:{'2030-01-07':[]}}}}),
    calendar({action:'create',bookingId:'date-race',booking:{organizationId:'org',roomId:'date-race',guestName:'Guest',startTime:{__timestamp:Date.parse('2030-01-07T09:00Z')},endTime:{__timestamp:Date.parse('2030-01-07T10:00Z')},totalPrice:100000}},ctx),
  ]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
});

test('empty room deletion enforces authority, revision, identities and immutable retries while retaining audit',async()=>{
  const deps={db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
  const room=createRoomDetailsHandler(deps),property=createPropertyDetailsHandler(deps);
  await db.doc('rooms/empty').set({organizationId:'org',buildingId:'a',roomNumber:'101',roomType:'Suite',area:25});
  const run=(data,uid='owner')=>room({auth:{uid},data:{organizationId:'org',buildingId:'a',roomId:'empty',...data}});
  const revision=(await run({action:'read'})).record.revision;
  const command={action:'delete',operationId:'remove-room',revision};
  await assert.rejects(room({data:command}),e=>e.code==='unauthenticated');
  for(const role of ['manager','receptionist','housekeeper','accountant','viewer']){
    await setMember(role,role,{buildingScope:'all',buildingIds:[]});
    await assert.rejects(run(command,role),e=>e.code==='permission-denied');
  }
  await setMember('scoped','administrator');
  await assert.rejects(run(command,'scoped'),e=>e.code==='permission-denied');
  await db.doc('memberships/scoped_org').delete();
  for(const patch of [{createdAt:1},{actorId:'forged'},{revision:'invalid'},{roomId:'bad/id'}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
  await assert.rejects(run({...command,revision:'0:0'}),e=>e.code==='aborted');
  await assert.rejects(run({...command,organizationId:'foreign'}),e=>e.code==='permission-denied');
  await db.doc('buildings/b').set({organizationId:'org'});
  await assert.rejects(run({...command,buildingId:'b'}),e=>e.code==='not-found');
  await db.doc('teamActivity/room-created').set({organizationId:'org',targetId:'empty',action:'room_created',after:{buildingId:'a',roomNumber:'101'}});
  await assertFails(deleteDoc(doc(env.authenticatedContext('owner').firestore(),'rooms/empty')));
  const result=await run(command);assert.equal(result.deleted,true);assert.deepEqual(await run(command),result);
  assert.equal((await db.doc('rooms/empty').get()).exists,false);
  assert.equal((await db.doc('teamActivity/room-created').get()).exists,true);
  const audit=(await db.collection('teamActivity').where('action','==','room_deleted').get()).docs;
  assert.equal(audit.length,1);assert.equal(audit[0].data().actorId,'owner');assert.equal(audit[0].data().before.roomNumber,'101');assert.ok(audit[0].data().createdAt.toMillis()>0);
  assert.ok((await db.doc('buildings/a').get()).data().roomInventoryUpdatedAt.toMillis()>0);
  await assert.rejects(run({...command,roomId:'changed'}),e=>e.code==='failed-precondition');
  const propertyRevision=(await property({auth:{uid:'owner'},data:{action:'read',organizationId:'org',buildingId:'a'}})).record.revision;
  await property({auth:{uid:'owner'},data:{action:'delete',organizationId:'org',buildingId:'a',operationId:'remove-property',revision:propertyRevision}});
  assert.deepEqual(await run(command),result);
  await setMember('owner','owner',{buildingScope:'all',status:'suspended'});
  await assert.rejects(run(command),e=>e.code==='permission-denied');
});

test('room deletion blocks all linked history including moved records, legacy links and nested data',async()=>{
  const room=createRoomDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  await setMember('admin','administrator',{buildingScope:'all',buildingIds:[]});
  await db.doc('memberships/admin_org').update({roleGrants:{...require('../team_access').templates.administrator.grants,deleteRooms:'managed'}});
  await db.doc('rooms/empty').set({organizationId:'org',buildingId:'a',roomNumber:'101'});
  const run=data=>room({auth:{uid:'admin'},data:{organizationId:'org',buildingId:'a',roomId:'empty',...data}});
  const revision=(await run({action:'read'})).record.revision;
  const command={action:'delete',operationId:'history-room',revision};
  for(const collection of ['tenants','bookings','payments','housekeepingTasks']){
    const ref=db.doc(`${collection}/old`);await ref.set({roomId:'empty',status:'cancelled'});
    await assert.rejects(run(command),e=>e.message==='room_not_empty');assert.equal((await ref.get()).exists,true);await ref.delete();
  }
  for(const field of ['before','after']){
    const ref=db.doc('teamActivity/move');await ref.set({action:'lease_move',[field]:{roomId:'empty'}});
    await assert.rejects(run(command),e=>e.message==='room_not_empty');await ref.delete();
  }
  await db.doc('rooms/empty/readings/old').set({value:123});
  await assert.rejects(run(command),e=>e.message==='room_not_empty');
  assert.equal((await db.collection('roomOperations').get()).size,0);
  await db.doc('rooms/empty/readings/old').delete();
  assert.equal((await run(command)).deleted,true);
});

test('room deletion serializes with booking creation and tenant creation',async()=>{
  await db.doc('buildings/a').update({timeZone:'UTC'});
  const room=createRoomDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  for(const kind of ['booking','tenant']){
    const roomId=`race-${kind}`,identity={organizationId:'org',buildingId:'a',roomId},ctx={auth:{uid:'owner'}};
    await db.doc(`rooms/${roomId}`).set({organizationId:'org',buildingId:'a',rentalMode:'both',currency:'VND'});
    const revision=(await room({...ctx,data:{action:'read',...identity}})).record.revision;
    const results=await Promise.allSettled([
      room({...ctx,data:{action:'delete',...identity,operationId:kind,revision}}),
      kind==='booking'?calendar({action:'create',bookingId:'race-booking',booking:{organizationId:'org',roomId,guestName:'Guest',startTime:{__timestamp:10000000},endTime:{__timestamp:13600000},totalPrice:100000}},ctx):tenant({create:true,tenantId:'race-tenant',tenant:{organizationId:'org',roomId,fullName:'Tenant',status:'active',moveInDate:{__timestamp:1000},backdateReason:'Historical fixture'}},ctx),
    ]);
    assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
    const linkedExists=(await db.doc(kind==='booking'?'bookings/race-booking':'tenants/race-tenant').get()).exists;
    assert.equal((await db.doc(`rooms/${roomId}`).get()).exists,linkedExists);
  }
});

test('empty property deletion preserves audit, retries once and rechecks authority',async()=>{
  const property=createPropertyDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=(data,uid='owner')=>property({auth:{uid},data:{organizationId:'org',buildingId:'a',...data}});
  const revision=(await run({action:'read'})).record.revision;
  const command={action:'delete',operationId:'delete-empty',revision};
  for(const role of ['manager','receptionist','housekeeper','accountant','viewer']){
    await setMember(role,role,{buildingScope:'all',buildingIds:[]});
    await assert.rejects(run(command,role),e=>e.code==='permission-denied');
  }
  await setMember('scoped','administrator');
  await assert.rejects(run(command,'scoped'),e=>e.code==='permission-denied');
  await db.doc('memberships/scoped_org').delete();
  await assert.rejects(run({...command,createdAt:123}),e=>e.code==='invalid-argument');
  await assert.rejects(run({...command,revision:'0:0'}),e=>e.code==='aborted');
  await db.doc('teamActivity/prior').set({organizationId:'org',targetId:'a',action:'property_created'});
  const result=await run(command);assert.equal(result.deleted,true);assert.deepEqual(await run(command),result);
  assert.equal((await db.doc('buildings/a').get()).exists,false);
  assert.equal((await db.doc('teamActivity/prior').get()).exists,true);
  assert.equal((await db.collection('propertyOperations').get()).size,1);
  assert.equal((await db.collection('teamActivity').where('action','==','property_deleted').get()).size,1);
  await assert.rejects(run({...command,revision:'0:0'}),e=>e.code==='already-exists');
  await setMember('owner','owner',{buildingScope:'all',status:'suspended'});
  await assert.rejects(run(command),e=>e.code==='permission-denied');
});

test('property deletion blocks historical records, assignments and nested data without cascades',async()=>{
  const property=createPropertyDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=data=>property({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'a',...data}});
  const revision=(await run({action:'read'})).record.revision;
  const command={action:'delete',operationId:'delete-blocked',revision};
  for(const collection of ['rooms','tenants','bookings','payments','housekeepingTasks']){
    const ref=db.doc(`${collection}/history`);await ref.set({buildingId:'a',status:'completed'});
    await assert.rejects(run(command),e=>e.message==='property_not_empty');
    assert.equal((await ref.get()).exists,true);await ref.delete();
  }
  for(const [path,data] of [['memberships/assigned',{buildingIds:['a']}],['teamInvitations/pending',{access:{buildingIds:['a']}}]]){
    await db.doc(path).set(data);await assert.rejects(run(command),e=>e.message==='property_has_assignments');await db.doc(path).delete();
  }
  await db.doc('buildings/a/history/one').set({amount:10});
  await assert.rejects(run(command),e=>e.message==='property_not_empty');
  assert.equal((await db.doc('buildings/a').get()).exists,true);
  assert.equal((await db.collection('propertyOperations').get()).size,0);
});

test('property rental contract data blocks deletion and administrators can delete genuinely empty properties',async()=>{
  const property=createPropertyDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  await setMember('admin','administrator',{buildingScope:'all',buildingIds:[]});
  await db.doc('memberships/admin_org').update({roleGrants:{...require('../team_access').templates.administrator.grants,deleteBuildings:'managed'}});
  const run=data=>property({auth:{uid:'admin'},data:{organizationId:'org',buildingId:'a',...data}});
  await db.doc('buildings/a').update({rentAmount:500});
  let revision=(await run({action:'read'})).record.revision;
  await assert.rejects(run({action:'delete',operationId:'rental',revision}),e=>e.message==='property_not_empty');
  await db.doc('buildings/a').set({organizationId:'org',name:'Empty'});
  revision=(await run({action:'read'})).record.revision;
  assert.equal((await run({action:'delete',operationId:'empty',revision})).deleted,true);
});

test('property deletion serializes with room creation',async()=>{
  const deps={db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
  const property=createPropertyDetailsHandler(deps),room=createRoomDetailsHandler(deps);
  const ctx={auth:{uid:'owner'}},identity={organizationId:'org',buildingId:'a'};
  const revision=(await property({...ctx,data:{...identity,action:'read'}})).record.revision;
  const results=await Promise.allSettled([
    property({...ctx,data:{...identity,action:'delete',operationId:'delete-race',revision}}),
    room({...ctx,data:{...identity,action:'create',roomId:'race-room',operationId:'create-race',roomNumber:'101',roomType:'Suite',area:25}}),
  ]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const roomExists=(await db.doc('rooms/race-room').get()).exists;
  assert.equal((await db.doc('buildings/a').get()).exists,roomExists);
});

test('property creation requires organization-wide management, validates inputs and records one server-owned result',async()=>{
  const property=createPropertyDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=(data,uid='owner')=>property({auth:{uid},data:{organizationId:'org',buildingId:'new-property',...data}});
  const command={action:'create',operationId:'create-property',name:'  Riverside  ',address:'  Da Nang  ',timeZone:'Asia/Ho_Chi_Minh',currency:'USD'};
  await assert.rejects(property({data:command}),e=>e.code==='unauthenticated');
  for(const role of ['owner','administrator','manager']) {
    await setMember(role,role,{buildingScope:'all'});
    const prepared=await run({action:'prepareCreate'},role);
    assert.equal(prepared.record.timeZone,'Asia/Ho_Chi_Minh');
    await run({...command,operationId:role,buildingId:`created-${role}`},role);
  }
  for(const role of ['manager','administrator','owner']) {
    await setMember('selected',role,{buildingIds:['new-property']});
    await assert.rejects(run({action:'prepareCreate'},'selected'),e=>e.code==='permission-denied');
    await assert.rejects(run(command,'selected'),e=>e.code==='permission-denied');
  }
  for(const role of ['receptionist','housekeeper','accountant','viewer']) {
    await setMember(role,role,{buildingScope:'all'});
    await assert.rejects(run(command,role),e=>e.code==='permission-denied');
  }
  for(const patch of [{name:''},{address:' '},{name:'x'.repeat(161)},{address:'x'.repeat(501)},{timeZone:null},{timeZone:'Bad/Zone'},{currency:'EUR'},{createdAt:123},{createdBy:'forged'},{revision:'1:0'}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
  await assert.rejects(run({...command,organizationId:'foreign'}),e=>e.code==='permission-denied');
  const result=await run(command);assert.deepEqual(await run(command),result);
  await assert.rejects(run({...command,name:'Changed intent'}),e=>e.code==='already-exists');
  await assert.rejects(run({...command,operationId:'another'}),e=>e.code==='already-exists');
  const savedProperty=(await db.doc('buildings/new-property').get()).data();
  assert.equal(savedProperty.name,'Riverside');assert.equal(savedProperty.address,'Da Nang');assert.equal(savedProperty.currency,'USD');assert.equal(savedProperty.timeZone,'Asia/Ho_Chi_Minh');assert.equal(savedProperty.createdBy,'owner');assert.ok(savedProperty.createdAt.toMillis()>0);
  const events=(await db.collection('teamActivity').where('targetId','==','new-property').get()).docs;
  assert.equal(events.length,1);assert.equal(events[0].data().action,'property_created');assert.equal(events[0].data().after.currency,'USD');
  const rooms=createRoomDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  await rooms({auth:{uid:'owner'},data:{action:'create',organizationId:'org',buildingId:'new-property',roomId:'new-room',operationId:'room',roomNumber:'101',roomType:'Suite',area:40}});
  assert.equal((await db.doc('rooms/new-room').get()).data().currency,'USD');
  await assertFails(setDoc(docRefForClient('direct-property'),{organizationId:'org',name:'Bypass'}));
  await setMember('owner','owner',{buildingScope:'all',status:'suspended'});
  await assert.rejects(run(command),e=>e.code==='permission-denied');
  function docRefForClient(id){return doc(env.authenticatedContext('owner').firestore(),`buildings/${id}`);}
});

test('bulk building creation is atomic, exact on retry, scoped and race safe',async()=>{
 const api=createPropertyDetailsHandler({db,Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const command={action:'create',organizationId:'org',buildingId:'bulk',operationId:'bulk',name:'Bulk test',address:'Synthetic',timeZone:'UTC',currency:'USD',exploitationCostMinor:123456,
  rooms:[{roomNumber:'101',roomType:'Studio',area:25,ratesMinor:{roomPrice:125099,nightlyPrice:3500,hourlyPrice:null}},{roomNumber:'102',roomType:'',area:null,ratesMinor:{roomPrice:null,nightlyPrice:null,hourlyPrice:1050}}]};
 const run=(d=command,uid='owner')=>api({auth:{uid},data:d});
 await assert.rejects(run({...command,rooms:[command.rooms[0],{...command.rooms[1],roomNumber:' １０１ '}]}),e=>e.code==='invalid-argument');
 assert.equal((await db.doc('buildings/bulk').get()).exists,false);assert.equal((await db.collection('rooms').get()).size,0);
 const both=await Promise.all([run(),run()]);assert.deepEqual(both[0],both[1]);
 const rooms=(await db.collection('rooms').where('buildingId','==','bulk').get()).docs.map(r=>r.data());
 assert.equal(rooms.length,2);assert.equal(rooms.find(r=>r.roomNumber==='101').roomPrice,1250.99);assert.equal(rooms.find(r=>r.roomNumber==='102').hourlyPrice,10.5);
 assert.equal((await db.doc('buildings/bulk').get()).data().exploitationCostMinor,123456);
 await assert.rejects(run({...command,operationId:'other'}),e=>e.code==='already-exists');
 await setMember('manager','manager',{buildingScope:'all',permissionOverrides:{overridePrices:false}});
 await assert.rejects(run({...command,buildingId:'denied'},'manager'),e=>e.code==='permission-denied');
 await run({...command,buildingId:'no-prices',operationId:'no-prices',rooms:command.rooms.map(r=>({...r,ratesMinor:{roomPrice:null,nightlyPrice:null,hourlyPrice:null}}))},'manager');
 await db.doc('memberships/manager_org').update({status:'suspended'});
 await assert.rejects(run({...command,buildingId:'denied'},'manager'),e=>e.code==='permission-denied');
 const fresh={...command,buildingId:'race'};
 const raced=await Promise.allSettled([run({...fresh,operationId:'first'}),run({...fresh,operationId:'second'})]);
 assert.equal(raced.filter(r=>r.status==='fulfilled').length,1);assert.equal((await db.collection('rooms').where('buildingId','==','race').get()).size,2);
});

test('concurrent property creation cannot overwrite an existing or foreign property',async()=>{
  const property=createPropertyDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=operationId=>property({auth:{uid:'owner'},data:{action:'create',organizationId:'org',buildingId:'shared-id',operationId,name:operationId,address:'Address',timeZone:'UTC',currency:'VND'}});
  const results=await Promise.allSettled([run('one'),run('two')]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(results.find(r=>r.status==='rejected').reason.code,'already-exists');
  assert.equal((await db.collection('propertyOperations').get()).size,1);
  await db.doc('buildings/shared-id').update({organizationId:'foreign'});
  await assert.rejects(run('three'),e=>e.code==='already-exists');
  assert.equal((await db.doc('buildings/shared-id').get()).data().organizationId,'foreign');
});

test('v2 bookings outside configured property-local operating hours are rejected',async()=>{
  await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});
  await db.doc('rooms/hours').set({organizationId:'org',buildingId:'a',rentalMode:'both',currency:'VND',operatingHoursStartMin:540,operatingHoursEndMin:1020});
  await assert.rejects(calendar({action:'create',bookingId:'outside-hours',booking:{organizationId:'org',roomId:'hours',guestName:'Guest',startTime:{__timestamp:Date.parse('2030-01-01T00:00:00Z')},endTime:{__timestamp:Date.parse('2030-01-01T01:00:00Z')},totalPrice:100000}},{auth:{uid:'owner'}}),e=>e.code==='failed-precondition');
});

test('overnight settings accept existing overnight stays and enforce closing on subsequent bookings',async()=>{
  await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});
  await db.doc('rooms/night').set({organizationId:'org',buildingId:'a',rentalMode:'both',currency:'VND'});
  const book=(id,start,end)=>calendar({action:'create',bookingId:id,booking:{organizationId:'org',roomId:'night',guestName:'Night guest',startTime:{__timestamp:Date.parse(start)},endTime:{__timestamp:Date.parse(end)},totalPrice:100000}},{auth:{uid:'owner'}});
  await book('existing-night','2030-01-01T15:00Z','2030-01-01T23:00Z');
  const settings=createBookingSettingsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=data=>settings({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'a',roomId:'night',...data}});
  const row=(await run({action:'read'})).record;
  const command={action:'update',operationId:'night-settings',revision:row.revision,timeZone:'Asia/Ho_Chi_Minh',minBookingHours:0,cleaningBufferMinutes:0,operatingHoursStartMin:1320,operatingHoursEndMin:360};
  await assert.rejects(run({...command,operatingHoursEndMin:300}),e=>e.message==='settings_existing_conflict');
  const result=await run(command);assert.deepEqual(await run(command),result);
  await book('next-night','2030-01-02T15:00Z','2030-01-02T23:00Z');
  await book('early-only','2030-01-03T19:00Z','2030-01-03T23:00Z');
  await assert.rejects(book('closed-gap','2030-01-04T22:00Z','2030-01-05T16:00Z'),e=>e.message==='booking_outside_operating_hours');
  await assert.rejects(book('past-close','2030-01-06T15:00Z','2030-01-06T23:00:00.001Z'),e=>e.message==='booking_outside_operating_hours');
});

test('booking settings require scope, timezone and compatible schedules; preserve financial settings and retry atomically',async()=>{
  const deps={db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
  const settings=createBookingSettingsHandler(deps),property=createPropertyDetailsHandler(deps);
  await setMember('manager','manager',{permissionOverrides:{overridePrices:false}});await setMember('worker','housekeeper');
  await db.doc('buildings/a').update({name:'A',address:'Address'});
  await db.doc('rooms/s').set({organizationId:'org',buildingId:'a',roomNumber:'101',rentalMode:'both',roomPrice:1000000,currency:'VND'});
  const run=(data,uid='manager')=>settings({auth:{uid},data:{organizationId:'org',buildingId:'a',roomId:'s',...data}});
  const initial=(await run({action:'read'})).record;
  const command={action:'update',operationId:'settings',revision:initial.revision,timeZone:null,minBookingHours:1,cleaningBufferMinutes:30,operatingHoursStartMin:540,operatingHoursEndMin:1020};
  await assert.rejects(run(command,'worker'),e=>e.code==='permission-denied');
  await assert.rejects(run({...command,buildingId:'outside'}),e=>e.code==='permission-denied');
  await assert.rejects(run(command),e=>e.message==='settings_timezone_required');
  for(const patch of [{minBookingHours:-1},{cleaningBufferMinutes:1441},{operatingHoursEndMin:540},{operatingHoursEndMin:-1},{operatingHoursStartMin:1440},{operatingHoursStartMin:null},{updatedAt:123},{timeZone:'Bad/Zone'}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
  const propertyCall=data=>property({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'a',...data}});
  const before=(await propertyCall({action:'read'})).record;
  await assert.rejects(propertyCall({action:'update',operationId:'badzone',revision:before.revision,name:'A',address:'Address',timeZone:'No/Such_Zone'}),e=>e.code==='invalid-argument');
  await propertyCall({action:'update',operationId:'zone',revision:before.revision,name:'A',address:'Address',timeZone:'Asia/Ho_Chi_Minh'});
  await assert.rejects(run(command),e=>e.code==='aborted');
  const next={...command,timeZone:'Asia/Ho_Chi_Minh'};
  await db.doc('bookings/s1').set({roomId:'s',status:'confirmed',startTime:Timestamp.fromMillis(Date.parse('2030-01-01T02:00Z')),endTime:Timestamp.fromMillis(Date.parse('2030-01-01T03:00Z')),totalPrice:100});
  await db.doc('bookings/s2').set({roomId:'s',status:'confirmed',startTime:Timestamp.fromMillis(Date.parse('2030-01-01T03:30Z')),endTime:Timestamp.fromMillis(Date.parse('2030-01-01T04:30Z')),totalPrice:100});
  for(const patch of [{minBookingHours:2},{cleaningBufferMinutes:31},{operatingHoursStartMin:600}])await assert.rejects(run({...next,...patch}),e=>e.message==='settings_existing_conflict');
  const result=await run(next);assert.deepEqual(await run(next),result);
  assert.equal((await db.collection('bookingSettingOperations').get()).size,1);
  const saved=(await db.doc('rooms/s').get()).data();assert.equal(saved.roomPrice,1000000);assert.equal(saved.minBookingHours,1);assert.equal(saved.updatedBy,'manager');assert.ok(saved.updatedAt.toMillis()>0);
  assert.equal((await db.doc('bookings/s1').get()).data().totalPrice,100);
  const latest=(await propertyCall({action:'read'})).record;
  await assert.rejects(propertyCall({action:'update',operationId:'zone2',revision:latest.revision,name:'A',address:'Address',timeZone:'UTC'}),e=>e.message==='property_timezone_in_use');
  await assert.rejects(run({...next,operationId:'stale'}),e=>e.code==='aborted');
  await setMember('manager','manager',{status:'suspended'});await assert.rejects(run(next),e=>e.code==='permission-denied');
  const current=(await run({action:'read'},'owner')).record;
  await run({...next,operationId:'disable',revision:current.revision,operatingHoursStartMin:null,operatingHoursEndMin:null},'owner');
  const refreshed=(await propertyCall({action:'read'})).record;
  await propertyCall({action:'update',operationId:'zone3',revision:refreshed.revision,name:'A',address:'Address',timeZone:'UTC'});
});

test('booking settings changes serialize with conflicting booking creation',async()=>{
  const settings=createBookingSettingsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  await db.doc('rooms/race-settings').set({organizationId:'org',buildingId:'a',rentalMode:'both',currency:'VND'});
  const identity={organizationId:'org',buildingId:'a',roomId:'race-settings'},ctx={auth:{uid:'owner'}};
  const row=(await settings({...ctx,data:{action:'read',...identity}})).record;
  const results=await Promise.allSettled([
    settings({...ctx,data:{action:'update',...identity,operationId:'minimum',revision:row.revision,timeZone:null,minBookingHours:3,cleaningBufferMinutes:0,operatingHoursStartMin:null,operatingHoursEndMin:null}}),
    calendar({action:'create',bookingId:'too-short',booking:{organizationId:'org',roomId:'race-settings',guestName:'Guest',startTime:{__timestamp:10000000},endTime:{__timestamp:13600000},totalPrice:100000}},ctx),
  ]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.ok(['aborted','invalid-argument','failed-precondition'].includes(results.find(r=>r.status==='rejected').reason.code));
});

test('v2 active leases cannot be created in hourly-only rooms',async()=>{
  await db.doc('rooms/hourly-only').set({organizationId:'org',buildingId:'a',rentalMode:'hourly',currency:'VND'});
  await assert.rejects(tenant({create:true,tenantId:'hourly-tenant',tenant:{organizationId:'org',roomId:'hourly-only',fullName:'Tenant',status:'active',moveInDate:{__timestamp:1000}}},{auth:{uid:'owner'}}),e=>e.code==='failed-precondition');
  assert.equal((await db.doc('tenants/hourly-tenant').get()).exists,false);
});

test('room pricing uses exact minor units, preserves existing charges and enforces current price authority',async()=>{
  const deps={db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
  const rates=createRoomRatesHandler(deps),workspace=createWorkspaceHandler(deps);
  await setMember('manager','manager');await setMember('restricted','manager',{permissionOverrides:{overridePrices:false}});await setMember('reception','receptionist',{permissionOverrides:{overridePrices:true}});
  await db.doc('rooms/r').set({organizationId:'org',buildingId:'a',roomNumber:'101',currency:'USD',rentalMode:'both',roomPrice:500,hourlyPrice:10,minBookingHours:2,cleaningBufferMinutes:30});
  await db.doc('bookings/existing').set({organizationId:'org',buildingId:'a',roomId:'r',status:'confirmed',totalPrice:99,paidAmount:30});
  await db.doc('tenants/existing').set({organizationId:'org',buildingId:'a',roomId:'r',status:'active',monthlyRent:500});
  await db.doc('payments/existing').set({organizationId:'org',roomId:'r',amount:500});
  const run=(data,uid='manager')=>rates({auth:{uid},data:{organizationId:'org',buildingId:'a',roomId:'r',...data}});
  const row=(await run({action:'read'})).record;
  assert.equal(row.ratesMinor.roomPrice,50000);
  for(const uid of ['restricted','reception'])await assert.rejects(run({action:'read'},uid),e=>e.code==='permission-denied');
  const list=await workspace({auth:{uid:'restricted'},data:{organizationId:'org',buildingId:'a',view:'rooms'}});assert.equal(list.records[0].canEditRates,false);
  await assert.rejects(run({action:'read',buildingId:'outside'}),e=>e.code==='permission-denied');
  const command={action:'update',operationId:'rates',revision:row.revision,rentalMode:'both',ratesMinor:{roomPrice:60000,nightlyPrice:2000,hourlyPrice:29}};
  for(const patch of [{ratesMinor:{...command.ratesMinor,hourlyPrice:0.29}},{rentalMode:'weekly'},{ratesMinor:{roomPrice:60000,hourlyPrice:29,dailyPrice:2000,overnightPrice:null}},{dailyPriceThresholdHours:8},{currency:'VND'},{updatedAt:'forged'}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
  // 2026-10-04: every room takes both; a mode from an older app is ignored, active bookings/leases do not matter.
  const result=await run(command);assert.deepEqual(await run(command),result);
  const changed=(await db.doc('rooms/r').get()).data();assert.equal(changed.hourlyPrice,0.29);assert.equal(changed.nightlyPrice,20);assert.equal(changed.dailyPrice,null);assert.equal(changed.dailyPriceThresholdHours,null);assert.equal(changed.roomPrice,600);assert.equal(changed.cleaningBufferMinutes,30);assert.equal(changed.minBookingHours,2);assert.ok(changed.updatedAt.toMillis()>0);
  assert.equal((await db.doc('bookings/existing').get()).data().totalPrice,99);assert.equal((await db.doc('tenants/existing').get()).data().monthlyRent,500);assert.equal((await db.doc('payments/existing').get()).data().amount,500);
  assert.equal((await db.collection('roomRateOperations').get()).size,1);assert.equal((await db.collection('teamActivity').get()).size,1);
  await assert.rejects(run({...command,operationId:'stale'}),e=>e.code==='aborted');
  await assert.rejects(run({...command,ratesMinor:{...command.ratesMinor,hourlyPrice:30}}),e=>e.code==='failed-precondition');
  await setMember('manager','manager',{permissionOverrides:{overridePrices:false}});await assert.rejects(run(command),e=>e.code==='permission-denied');
  await db.doc('bookings/existing').update({status:'cancelled'});await db.doc('tenants/existing').update({status:'moveOut'});
  const latest=(await run({action:'read'},'owner')).record;
  await run({...command,operationId:'monthly',revision:latest.revision,rentalMode:'monthly',ratesMinor:{roomPrice:null,nightlyPrice:null,hourlyPrice:null}},'owner');
  assert.equal((await db.doc('rooms/r').get()).data().rentalMode,'both');assert.equal((await db.doc('rooms/r').get()).data().roomPrice,null);
});

// 'concurrent hourly-only switch and active lease' removed 2026-10-04: rooms no longer have a rental mode.

test('room creation inherits currency, rejects forged defaults and audits exactly once with current authorization',async()=>{
  const edit=createRoomDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  await setMember('manager','manager');await setMember('worker','housekeeper');
  await db.doc('buildings/a').update({currency:'USD'});
  const run=(data,uid='manager')=>edit({auth:{uid},data:{organizationId:'org',buildingId:'a',roomId:'new',...data}});
  assert.equal((await run({action:'prepareCreate'})).record.currency,'USD');
  assert.equal((await db.collection('rooms').get()).size,0);
  const command={action:'create',operationId:'create-room',roomNumber:'201',roomType:'Family',area:45.5};
  await assert.rejects(run(command,'worker'),e=>e.code==='permission-denied');
  await assert.rejects(run({...command,buildingId:'outside'}),e=>e.code==='permission-denied');
  for(const patch of [{createdAt:'forged'},{currency:'VND'},{rentalMode:'hourly'},{area:0},{roomType:7},{roomType:'x'.repeat(161)},{revision:'new'},{roomPrice:500}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
  const result=await run(command);assert.deepEqual(await run(command),result);
  assert.equal((await db.collection('rooms').get()).size,1);
  const row=(await db.doc('rooms/new').get()).data();assert.equal(row.currency,'USD');assert.equal(row.rentalMode,'both');assert.equal(row.roomPrice,undefined);assert.equal(row.createdBy,'manager');assert.ok(row.createdAt.toMillis()>0);assert.equal(row.organizationId,'org');assert.equal(row.buildingId,'a');
  const events=await db.collection('teamActivity').get();assert.equal(events.size,1);assert.equal(events.docs[0].data().action,'room_created');assert.equal(events.docs[0].data().before,null);
  await assert.rejects(run({...command,roomNumber:'different'}),e=>e.code==='failed-precondition');
  await assert.rejects(run({...command,operationId:'different'}),e=>e.code==='failed-precondition');
  await assert.rejects(run({...command,roomId:'duplicate',operationId:'duplicate',roomNumber:' ２０１ '}),e=>e.code==='already-exists');
  await db.doc('rooms/collision').set({organizationId:'other',buildingId:'elsewhere',roomNumber:'Private'});
  await assert.rejects(run({...command,roomId:'collision',operationId:'collision'}),e=>e.code==='failed-precondition');
  assert.equal((await db.doc('rooms/collision').get()).data().roomNumber,'Private');
  await setMember('manager','manager',{status:'suspended'});await assert.rejects(run(command),e=>e.code==='permission-denied');
  await assertFails(setDoc(doc(env.authenticatedContext('owner').firestore(),'rooms/direct'),{organizationId:'org',buildingId:'a',roomNumber:'Direct'}));
});

test('concurrent creates in an empty property cannot duplicate labels and unsupported currency blocks creation',async()=>{
  const edit=createRoomDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=roomId=>edit({auth:{uid:'owner'},data:{action:'create',organizationId:'org',buildingId:'a',roomId,operationId:roomId,roomNumber:'101',roomType:'Standard',area:25}});
  const results=await Promise.allSettled(['one','two'].map(run));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);assert.equal(results.find(r=>r.status==='rejected').reason.code,'already-exists');
  assert.equal((await db.collection('rooms').get()).docs[0].data().currency,'VND');
  await db.doc('buildings/a').update({currency:'INVALID'});
  await assert.rejects(run('blocked'),e=>e.code==='failed-precondition');
});

test('room details enforce scope, uniqueness, revision and preserve prices and references',async()=>{
  const deps={db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
  const edit=createRoomDetailsHandler(deps),workspace=createWorkspaceHandler(deps);
  const run=(data,uid='manager')=>edit({auth:{uid},data:{organizationId:'org',buildingId:'a',roomId:'r',...data}});
  await setMember('manager','manager');await setMember('reception','receptionist');
  await db.doc('rooms/r').set({organizationId:'org',buildingId:'a',roomNumber:'101',roomType:'Family',area:30,currency:'USD',roomPrice:500,rentalMode:'both',hourlyPrice:20,createdAt:Timestamp.fromMillis(1000)});
  await db.doc('rooms/other').set({organizationId:'org',buildingId:'a',roomNumber:'Suite A',roomType:'Standard',area:20});
  await db.doc('rooms/foreign').set({organizationId:'foreign',buildingId:'a',roomNumber:'secret'});
  await db.doc('tenants/t').set({organizationId:'org',buildingId:'a',roomId:'r',name:'Tenant'});
  await db.doc('bookings/bk').set({organizationId:'org',buildingId:'a',roomId:'r',status:'confirmed'});
  const row=(await run({action:'read'})).record;
  assert.deepEqual(Object.keys(row).sort(),['area','id','revision','roomNumber','roomType']);
  const list=await workspace({auth:{uid:'manager'},data:{organizationId:'org',view:'rooms',buildingId:'a',limit:1}});
  assert.equal(list.records.length,1);assert.ok(list.nextCursor);assert.equal(list.records[0].currency,undefined);
  assert.equal((await workspace({auth:{uid:'manager'},data:{organizationId:'org',view:'rooms',buildingId:'a',cursor:list.nextCursor}})).records.length,1);
  await assert.rejects(workspace({auth:{uid:'reception'},data:{organizationId:'org',view:'rooms',buildingId:'a'}}),e=>e.code==='permission-denied');
  await assert.rejects(run({action:'read'},'reception'),e=>e.code==='permission-denied');
  await assert.rejects(run({action:'read',buildingId:'outside'}),e=>e.code==='permission-denied');
  await assert.rejects(run({action:'read',roomId:'foreign'}),e=>e.code==='not-found');
  const command={action:'update',operationId:'edit-room',revision:row.revision,roomNumber:'102',roomType:'Family plus',area:35.5};
  for(const patch of [{area:0},{area:Infinity},{area:100001},{area:'25'},{roomNumber:''},{updatedAt:'forged'},{roomPrice:1}])await assert.rejects(run({...command,...patch}),e=>e.code==='invalid-argument');
  await assert.rejects(run({...command,roomNumber:'  Ｓｕｉｔｅ Ａ  '}),e=>e.code==='already-exists');
  const result=await run(command);assert.deepEqual(await run(command),result);
  await assert.rejects(run({...command,area:60}),e=>e.code==='failed-precondition');
  await assert.rejects(run({...command,operationId:'stale'}),e=>e.code==='aborted');
  const changed=(await db.doc('rooms/r').get()).data();assert.equal(changed.roomNumber,'102');assert.equal(changed.area,35.5);assert.equal(changed.roomPrice,500);assert.equal(changed.rentalMode,'both');assert.equal(changed.hourlyPrice,20);assert.equal(changed.createdAt.toMillis(),1000);assert.ok(changed.updatedAt.toMillis()>1000);
  assert.equal((await db.doc('tenants/t').get()).data().roomId,'r');assert.equal((await db.doc('bookings/bk').get()).data().roomId,'r');
  assert.equal((await db.collection('roomOperations').get()).size,1);assert.equal((await db.collection('teamActivity').get()).size,1);
  await setMember('manager','manager',{status:'suspended'});await assert.rejects(run(command),e=>e.code==='permission-denied');
  await assertFails(updateDoc(doc(env.authenticatedContext('owner').firestore(),'rooms/r'),{roomNumber:'forged'}));
});

test('concurrent room renames cannot claim the same label',async()=>{
  const edit=createRoomDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  for(const roomId of ['one','two'])await db.doc(`rooms/${roomId}`).set({organizationId:'org',buildingId:'a',roomNumber:roomId,roomType:'Standard',area:25});
  const read=roomId=>edit({auth:{uid:'owner'},data:{action:'read',organizationId:'org',buildingId:'a',roomId}});
  const [one,two]=await Promise.all(['one','two'].map(read));
  const results=await Promise.allSettled(['one','two'].map((roomId,i)=>edit({auth:{uid:'owner'},data:{action:'update',organizationId:'org',buildingId:'a',roomId,operationId:roomId,revision:[one,two][i].record.revision,roomNumber:'Shared',roomType:'Standard',area:25}})));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(results.find(r=>r.status==='rejected').reason.code,'already-exists');
});

test('property details preserve other fields, prevent stale edits and enforce scope on reads and retries',async()=>{
  const edit=createPropertyDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=(data,uid='owner')=>edit({auth:{uid},data:{organizationId:'org',buildingId:'a',...data}});
  await db.doc('buildings/a').update({name:'Before',address:'Old address',currency:'USD',rentAmount:900,createdAt:Timestamp.fromMillis(1000)});
  await setMember('manager','manager');await setMember('reception','receptionist');
  await db.doc('buildings/b').set({organizationId:'org',name:'Other'});
  await db.doc('buildings/foreign').set({organizationId:'other',name:'Secret'});
  const row=(await run({action:'read'},'manager')).record;
  assert.deepEqual(Object.keys(row).sort(),['address','currency','exploitationCostMinor','id','name','revision','timeZone']);
  assert.equal(row.currency,'USD');assert.equal(row.exploitationCostMinor,null);
  await assert.rejects(run({action:'read'},'reception'),e=>e.code==='permission-denied');
  await assert.rejects(run({action:'read',buildingId:'b'},'manager'),e=>e.code==='permission-denied');
  await assert.rejects(run({action:'read',buildingId:'foreign'}),e=>e.code==='not-found');
  const command={action:'update',operationId:'edit',revision:row.revision,name:'  New name  ',address:'New address'};
  await assert.rejects(run({...command,updatedAt:'forged'}),e=>e.code==='invalid-argument');
  await assert.rejects(run({...command,name:'  '}),e=>e.code==='invalid-argument');
  await assert.rejects(run({...command,currency:'VND'}),e=>e.code==='invalid-argument');
  const result=await run(command,'manager');assert.deepEqual(await run(command,'manager'),result);
  await assert.rejects(run({...command,name:'Different'},'manager'),e=>e.code==='already-exists');
  await assert.rejects(run({...command,operationId:'stale'},'manager'),e=>e.code==='aborted');
  const changed=(await db.doc('buildings/a').get()).data();
  assert.equal(changed.name,'New name');assert.equal(changed.currency,'USD');assert.equal(changed.rentAmount,900);assert.equal(changed.createdAt.toMillis(),1000);assert.equal(changed.updatedBy,'manager');assert.ok(changed.updatedAt.toMillis()>1000);
  assert.equal((await db.collection('propertyOperations').get()).size,1);
  const logs=await db.collection('teamActivity').get();assert.equal(logs.size,1);assert.equal(logs.docs[0].data().before.name,'Before');
  await setMember('manager','manager',{status:'suspended'});
  await assert.rejects(run(command,'manager'),e=>e.code==='permission-denied');
  await assertFails(updateDoc(doc(env.authenticatedContext('owner').firestore(),'buildings/a'),{name:'Direct'}));
});

test('housekeeping assignment and completion enforce current property and assignee access with atomic audits',async()=>{
  const deps={db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}};
  const tasks=createHousekeepingHandler(deps),workspace=createWorkspaceHandler(deps);
  await setMember('cleaner','housekeeper');await setMember('other','housekeeper');
  await db.doc('rooms/r').set({organizationId:'org',buildingId:'a'});
  const assign={organizationId:'org',operationId:'assign',taskId:'task',action:'assign',buildingId:'a',roomId:'r',assigneeId:'cleaner',title:'Clean room'};
  const run=(data,uid='owner')=>tasks({auth:{uid},data});
  const result=await run(assign);assert.deepEqual(await run(assign),result);
  const read=uid=>workspace({auth:{uid},data:{organizationId:'org',view:'tasks',buildingId:'a'}});
  const picker=(uid,view)=>workspace({auth:{uid},data:{organizationId:'org',view,buildingId:'a'}});
  assert.equal((await picker('owner','taskRooms')).records[0].id,'r');
  assert.ok((await picker('owner','taskAssignees')).records.some(r=>r.ownerId==='cleaner'));
  await assert.rejects(picker('cleaner','taskAssignees'),e=>e.code==='permission-denied');
  assert.equal((await read('cleaner')).records.length,1);assert.equal((await read('other')).records.length,0);
  const complete={organizationId:'org',operationId:'complete',taskId:'task',action:'status',status:'completed'};
  await assert.rejects(run(complete,'other'),e=>e.code==='permission-denied');
  await assert.rejects(run({...complete,completedAt:'forged'},'cleaner'),e=>e.code==='invalid-argument');
  await run(complete,'cleaner');await run(complete,'cleaner');
  const row=(await db.doc('housekeepingTasks/task').get()).data();
  assert.equal(row.completedBy,'cleaner');assert.ok(row.completedAt.toMillis()>0);
  assert.equal((await db.collection('taskOperations').get()).size,2);
  assert.equal((await db.collection('teamActivity').get()).size,2);
  await db.doc('memberships/cleaner_org').update({status:'suspended'});
  await assert.rejects(run(complete,'cleaner'),e=>e.code==='permission-denied');
  await assert.rejects(run({...assign,operationId:'bad',taskId:'bad',assigneeId:'cleaner'}),e=>e.code==='failed-precondition');
  const client=env.authenticatedContext('cleaner').firestore();
  await assertFails(setDoc(doc(client,'housekeepingTasks/forged'),{organizationId:'org',status:'completed'}));
});

test('payment action projection allows reception collection without financial reports and restricts refunds',async()=>{
  const read=createWorkspaceHandler({db,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  await db.doc('payments/invoice').set({organizationId:'org',buildingId:'a',type:'rent',currency:'VND',amount:100,paidAmount:20,status:'partial',taxAmount:5,tenantName:'PRIVATE',transactionId:'SECRET'});
  await db.doc('payments/booking_hidden').set({organizationId:'org',buildingId:'a',type:'rent',currency:'VND',amount:100,paidAmount:20,status:'partial'});
  await setMember('reception','receptionist');
  const run=(uid,view='paymentActions',buildingId='a')=>read({auth:{uid},data:{organizationId:'org',view,buildingId}});
  const result=await run('reception');
  const invoice=result.records.find(r=>r.id==='invoice');
  assert.equal(invoice.canCollect,true);assert.equal(invoice.canRefund,false);assert.equal(invoice.taxAmount,5);
  assert.equal(result.records.find(r=>r.id==='booking_hidden').canCollect,false);
  assert.ok(!JSON.stringify(result).includes('PRIVATE'));assert.ok(!JSON.stringify(result).includes('SECRET'));
  await assert.rejects(run('reception','financial'),e=>e.code==='permission-denied');
  await assert.rejects(run('reception','paymentActions','b'),e=>e.code==='permission-denied');
  await setMember('keeper','housekeeper');await assert.rejects(run('keeper'),e=>e.code==='permission-denied');
  await db.doc('memberships/keeper_org').update({permissionOverrides:{refundPayments:true}});
  const refundOnly=(await run('keeper')).records.find(r=>r.id==='invoice');
  assert.equal(refundOnly.canRefund,true);assert.equal(refundOnly.canCollect,false);
});

test('synthetic migration rehearsal preserves inventory and requires legacy assignment before access',async()=>{
  await db.doc('organizations/org').update({accessVersion:1});
  const legacy=[{id:'owner_org',ownerId:'owner',organizationId:'org',role:'admin',status:'active'},
    {id:'worker_org',ownerId:'worker',organizationId:'org',role:'member',status:'active'}];
  for(const {id,...data} of legacy)await db.doc(`memberships/${id}`).set(data);
  await db.doc('rooms/untouched').set({organizationId:'org',buildingId:'a',roomNumber:'101'});
  const inventory=(await db.doc('rooms/untouched').get()).data();
  const plan=migrationProposal({id:'org',createdBy:'owner'},legacy);
  assert.deepEqual(plan.issues,[]);
  assert.equal((await db.doc('organizations/org').get()).data().accessVersion,1);
  assert.equal((await db.doc('memberships/worker_org').get()).data().role,'member');
  // Rehearsal only: apply the reviewed synthetic proposal atomically in emulator.
  const batch=db.batch();
  for(const proposal of plan.proposals)batch.update(db.doc(`memberships/${proposal.membershipId}`),proposal.proposed);
  batch.update(db.doc('organizations/org'),{accessVersion:2});await batch.commit();
  assert.deepEqual((await db.doc('rooms/untouched').get()).data(),inventory);
  await assert.rejects(readHandler({auth:{uid:'worker'},data:{organizationId:'org',view:'staff'}}),e=>e.code==='permission-denied');
  const rows=(await readHandler({auth:{uid:'owner'},data:{organizationId:'org',view:'access'}})).records;
  assert.equal(rows.find(r=>r.ownerId==='worker').status,'assignmentRequired');
  await call({action:'setAccess',operationId:'reviewMigration',userId:'worker',status:'active',reason:'Explicit review',
    access:{role:'receptionist',buildingScope:'selected',buildingIds:['a']}});
  assert.equal((await db.doc('memberships/worker_org').get()).data().role,'receptionist');
  const client=env.authenticatedContext('worker').firestore();
  await assertFails(getDoc(doc(client,'rooms/untouched')));
});

test('dashboard lists only current authorized organizations and omits private fields',async()=>{
  const directory=createOrganizationDirectory({db,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  await db.doc('organizations/org').update({name:'Visible',bankAccountNumber:'PRIVATE',inviteCode:'SECRET'});
 const read=()=>directory({auth:{uid:'owner'},data:{}});
 assert.deepEqual((await read()).records.map(r=>r.id),['org']);
  await db.doc('organizations/foreign').set({name:'Hidden',accessVersion:2});
  await db.doc('memberships/owner_foreign').set({organizationId:'foreign',ownerId:'owner',role:'member',status:'active'});
  const result=await read();
 assert.deepEqual(result.records,[]);assert.equal(result.accountPolicy.mode,'conflict');
  assert.ok(!JSON.stringify(result).includes('PRIVATE'));assert.ok(!JSON.stringify(result).includes('SECRET'));
  await db.doc('memberships/owner_org').update({status:'suspended'});
  assert.deepEqual((await read()).records,[]);
  await assert.rejects(directory({data:{}}),e=>e.code==='unauthenticated');
});

test('account review includes unlinked legacy accounts with protected role hints and explicit assignment',async()=>{
  await db.doc('memberships/legacy_org').set({organizationId:'org',ownerId:'legacy',role:'member',status:'assignmentRequired'});
  await setMember('admin','administrator',{buildingScope:'all'});
  const read=uid=>readHandler({auth:{uid},data:{organizationId:'org',view:'access'}});
  const rows=(await read('admin')).records;
  assert.equal(rows.find(r=>r.ownerId==='legacy').canManageAccess,true);
  assert.equal(rows.find(r=>r.ownerId==='owner').canManageAccess,false);
  assert.equal(rows.find(r=>r.ownerId==='admin').canManageAccess,false);
  await call({action:'setAccess',operationId:'assign',userId:'legacy',status:'active',reason:'Reviewed legacy account',
    access:{role:'receptionist',buildingScope:'selected',buildingIds:['a']}},'admin');
  const member=(await db.doc('memberships/legacy_org').get()).data();
  assert.equal(member.accessVersion,2);assert.equal(member.role,'receptionist');
  assert.equal(typeof member.staffId,'string');
  const profile=(await db.doc('staffProfiles/'+member.staffId).get()).data();assert.equal(profile.accountId,'legacy');assert.equal(profile.organizationId,'org');
  assert.equal((await db.collection('staffProfiles').get()).size,2);
  await assert.rejects(read('legacy'),e=>e.code==='permission-denied');
});

const paymentTime = '2026-09-26T12:34:56.000Z';
async function paymentFixture(extra={}) {
  await db.doc('payments/invoice').set({organizationId:'org',buildingId:'a',roomId:'r',type:'rent',
    currency:'VND',amount:100,paidAmount:0,status:'pending',createdAt:Timestamp.fromMillis(1000),...extra});
  const mutate=createPaymentHandler({db,Timestamp:{now:()=>Timestamp.fromDate(new Date(paymentTime))},
    HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  return (extra={},uid='owner')=>mutate({auth:uid?{uid}:null,data:{organizationId:'org',paymentId:'invoice',
    operationId:'collect',action:'collect',amountMinor:40,paymentMethod:'cash',...extra}});
}

test('standalone collection uses server time and actor, with atomic retry-safe audit',async()=>{
  const run=await paymentFixture({tenantName:'PRIVATE'});
  const results=await Promise.all([run(),run()]);
  assert.deepEqual(results[0],results[1]);
  assert.equal(results[0].recordedAt,paymentTime);
  const invoice=(await db.doc('payments/invoice').get()).data();
  assert.equal(invoice.paidAmount,40);assert.equal(invoice.status,'partial');
  assert.equal(invoice.paidBy,'owner');assert.equal(invoice.updatedBy,'owner');
  assert.equal(invoice.createdAt.toMillis(),1000);
  assert.equal(invoice.paidAt.toDate().toISOString(),paymentTime);
  const events=await db.collection('teamActivity').get();
  const operations=await db.collection('paymentOperations').get();
  assert.equal(events.size,1);assert.equal(operations.size,1);
  assert.equal(events.docs[0].data().createdAt.toDate().toISOString(),paymentTime);
  assert.equal(events.docs[0].data().actorId,'owner');
  assert.ok(!JSON.stringify(events.docs[0].data()).includes('PRIVATE'));
  assert.equal(operations.docs[0].data().createdAt.toDate().toISOString(),paymentTime);
  await assert.rejects(run({amountMinor:41}),e=>e.code==='already-exists');
  assert.equal((await db.doc('payments/invoice').get()).data().paidAmount,40);
});

test('standalone payment rejects client timestamps, identity, balances and malformed commands',async()=>{
  const run=await paymentFixture();
  for(const extra of [{paidAt:'2025-09-26T00:00:00Z'},{paidAt:'2027-09-26T00:00:00Z'},
    {createdAt:0},{updatedAt:0},{paidBy:'other'},{actorId:'other'},{paidAmount:100},{status:'paid'},
    {amountMinor:0},{amountMinor:-1},{amountMinor:0.5},{amountMinor:Number.MAX_SAFE_INTEGER+1},
    {amountMinor:'40'},{paymentMethod:'unknown'},{paymentId:'../invoice'}]) {
    await assert.rejects(run(extra),e=>e.code==='invalid-argument');
  }
  await assert.rejects(run({},null),e=>e.code==='unauthenticated');
  assert.equal((await db.collection('teamActivity').get()).size,0);
  assert.equal((await db.collection('paymentOperations').get()).size,0);
  assert.equal((await db.doc('payments/invoice').get()).data().paidAmount,0);
});

test('standalone payments enforce roles, property scope, suspension and revocation on retries',async()=>{
  const run=await paymentFixture();
  for(const role of ['housekeeper','viewer']) {
    await setMember(role,role);
    await assert.rejects(run({},role),e=>e.code==='permission-denied');
  }
  await setMember('worker','receptionist',{buildingIds:['b']});
  await assert.rejects(run({},'worker'),e=>e.code==='permission-denied');
  await setMember('worker','receptionist');
  await run({},'worker');
  const refund={operationId:'refund',action:'refund',amountMinor:10,reason:'Correction'};
  // Refund must not include the collect-only paymentMethod field.
  const mutate=createPaymentHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const refundAs=uid=>mutate({auth:{uid},data:{organizationId:'org',paymentId:'invoice',...refund}});
  await assert.rejects(refundAs('worker'),e=>e.code==='permission-denied');
  await db.doc('memberships/worker_org').update({permissionOverrides:{refundPayments:true}});
  await refundAs('worker');
  await db.doc('memberships/worker_org').update({permissionOverrides:{refundPayments:false}});
  await assert.rejects(refundAs('worker'),e=>e.code==='permission-denied');
  await db.doc('memberships/worker_org').update({status:'suspended'});
  await assert.rejects(run({},'worker'),e=>e.code==='permission-denied');
  assert.equal((await db.doc('payments/invoice').get()).data().paidAmount,30);
});

test('concurrent distinct collections cannot overpay the invoice',async()=>{
  const run=await paymentFixture();
  const results=await Promise.allSettled([run({operationId:'one',amountMinor:70}),run({operationId:'two',amountMinor:70})]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  assert.equal(results.find(r=>r.status==='rejected').reason.code,'failed-precondition');
  assert.equal((await db.doc('payments/invoice').get()).data().paidAmount,70);
  assert.equal((await db.collection('paymentOperations').get()).size,1);
  assert.equal((await db.collection('teamActivity').get()).size,1);
});

test('USD cents and invoice fees are exact; refunds are bounded and retain collection timestamp',async()=>{
  const run=await paymentFixture({currency:'USD',amount:0.29,internetFee:0.1,cableTVFee:0.01,hotWaterFee:0.05,lateFee:0.02,taxAmount:0.03});
  assert.equal((await run({amountMinor:50})).status,'paid');
  const mutate=createPaymentHandler({db,Timestamp:{now:()=>Timestamp.fromMillis(2000000000000)},HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const refund=(operationId,amountMinor,reason='Customer refund')=>mutate({auth:{uid:'owner'},data:{organizationId:'org',paymentId:'invoice',operationId,action:'refund',amountMinor,reason}});
  await assert.rejects(refund('tooMuch',51),/payment_amount_exceeds_balance/);
  await assert.rejects(refund('noReason',10,''),e=>e.code==='invalid-argument');
  const partial=await refund('partial',20);assert.equal(partial.status,'partial');assert.equal(partial.paidMinor,30);
  assert.deepEqual(await refund('partial',20),partial);
  const full=await refund('full',30);assert.equal(full.status,'refunded');assert.equal(full.paidMinor,0);
  const invoice=(await db.doc('payments/invoice').get()).data();
  assert.equal(invoice.paidAt.toDate().toISOString(),paymentTime);
  assert.equal(invoice.lastRefundedAt.toMillis(),2000000000000);
  assert.equal(invoice.lastRefundedBy,'owner');assert.equal(invoice.createdAt.toMillis(),1000);
  assert.equal((await db.collection('paymentOperations').get()).size,3);
  assert.equal((await db.collection('teamActivity').get()).size,3);
});

test('unsafe invoice data and booking-linked payments fail closed without financial writes',async()=>{
  for(const extra of [{currency:'EUR'},{amount:0.1},{amount:-1},{paidAmount:101},{amount:NaN},
    {paidAmount:null},{internetFee:-1},{status:'cancelled'},{bookingId:'booking'},{type:'hourlyRent'}]) {
    const run=await paymentFixture(extra);
    await assert.rejects(run(),e=>e.code==='failed-precondition');
  }
  const run=await paymentFixture();
  await db.doc('payments/booking_reserved').set((await db.doc('payments/invoice').get()).data());
  await assert.rejects(run({paymentId:'booking_reserved'}),/payment_use_booking_workflow/);
  await db.doc('buildings/a').update({organizationId:'foreign'});
  await assert.rejects(run(),/payment_invalid_property/);
  await db.doc('payments/invoice').update({organizationId:'foreign'});
  await assert.rejects(run(),e=>e.code==='not-found');
  await db.doc('organizations/org').update({accessVersion:1});
  await assert.rejects(run(),/team_migration_required/);
  assert.equal((await db.collection('paymentOperations').get()).size,0);
  assert.equal((await db.collection('teamActivity').get()).size,0);
});

test('v2 clients cannot bypass payment commands or forge/delete their operation ledger',async()=>{
  await paymentFixture();
  const client=env.authenticatedContext('owner').firestore();
  for(const path of ['payments/invoice','paymentOperations/forged']) {
    const ref=doc(client,path);
    await assertFails(setDoc(ref,{organizationId:'org',paidAmount:100,paidAt:new Date(0)}));
    await assertFails(updateDoc(ref,{paidAmount:100}));
    await assertFails(deleteDoc(ref));
  }
});

test('workspace enforces all role projections, property boundaries and live suspension',async()=>{
  const read=createWorkspaceHandler({db,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const run=(uid,view,extra={})=>read({auth:{uid},data:{organizationId:'org',view,buildingId:'a',...extra}});
  await db.doc('buildings/b').set({organizationId:'org',name:'Hidden property',private:'secret'});
  await db.doc('buildings/foreign').set({organizationId:'other',name:'Foreign'});
  await db.doc('bookings/booking').set({organizationId:'org',buildingId:'a',guestName:'Guest',guestPhone:'secret',guestIdNumber:'secret',roomId:'r',status:'confirmed'});
  await db.doc('payments/payment').set({organizationId:'org',buildingId:'a',amount:10,currency:'VND',tenantName:'secret',transactionId:'secret'});
  // The removed viewer role (and any unknown role) is refused everywhere.
  await setMember('viewer','viewer',{buildingIds:['a']});
  for(const view of ['properties','bookings','financial'])await assert.rejects(run('viewer',view),e=>e.code==='permission-denied');
  for(const role of ['owner','administrator','manager','receptionist','housekeeper','accountant']){
    await setMember(role,role,{buildingIds:['a','foreign']});
    assert.deepEqual((await run(role,'properties')).records.map(r=>r.id),['a']);
    for(const view of ['bookings','financial']){
      const permitted=view==='bookings'?['owner','administrator','manager','receptionist','accountant'].includes(role):['owner','administrator','manager','accountant'].includes(role);
      if(permitted){
        const result=await run(role,view);
        assert.equal(result.records.length,1);
        assert.ok(!JSON.stringify(result).includes('secret'));
      }else await assert.rejects(run(role,view),e=>e.code==='permission-denied');
      await assert.rejects(run(role,view,{buildingId:'b'}),e=>e.code==='permission-denied');
      await assert.rejects(run(role,view,{buildingId:'foreign'}),e=>e.code==='permission-denied');
    }
    await db.doc(`memberships/${role}_org`).update({status:'suspended'});
    await assert.rejects(run(role,'properties'),e=>e.code==='permission-denied');
  }
  await setMember('empty','accountant',{buildingIds:[]});
  assert.deepEqual((await run('empty','properties')).records,[]);
  await assert.rejects(read({data:{}}),e=>e.code==='unauthenticated');
});
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
const read=(view,uid='owner',extra={})=>readHandler({auth:{uid},data:{organizationId:'org',view,...extra}});
const setMember=(uid,role='receptionist',extra={})=>db.doc(`memberships/${uid}_org`).set({organizationId:'org',ownerId:uid,accessVersion:2,role,status:'active',buildingScope:'selected',buildingIds:['a'],...extra});

test('security: independent client clocks cannot extend exact invitation expiry or resurrect revoked access',async()=>{
 const vm=require('node:vm'),Stamp=Timestamp;
 const {invitationId}=await call(invitation);
 const expiry=(await db.doc(`teamInvitations/${invitationId}`).get()).data().expiresAt.toMillis();
 const atExpiry=createTeamHandler({db,Timestamp:{now:()=>Stamp.fromMillis(expiry)},HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 for(const offset of [-366,366]){
  const clientTime=vm.runInNewContext(`new Date(${expiry}+${offset}*86400000).toISOString()`);
  await assert.rejects(atExpiry({auth:{uid:'new',token:{email:'new@example.com',email_verified:true}},data:{organizationId:'org',action:'acceptInvitation',operationId:`clock${offset}`,invitationId,clientTime}}),/team_invitation_closed/);
 }
 assert.equal((await db.doc('memberships/new_org').get()).exists,false);
 assert.equal((await db.collection('teamActivity').get()).size,1);
 const run=await paymentFixture();await setMember('cashier','receptionist');
 await db.doc('memberships/cashier_org').update({status:'revoked'});
 await assert.rejects(run({},'cashier'),e=>e.code==='permission-denied');
 assert.equal((await db.doc('payments/invoice').get()).data().paidAmount,0);
});

test('security: concurrent lookup limits are atomic and clients cannot edit rate buckets',async()=>{
 const {createRequestGuard}=require('../request_security');
 const guard=createRequestGuard({db,Timestamp:Timestamp,now:()=>1000000,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const result=await Promise.allSettled(Array.from({length:16},()=>guard('lookupTeamInvitation',{auth:{uid:'owner'},app:{appId:'test-app'},data:{}})));
 assert.equal(result.filter(x=>x.status==='fulfilled').length,12);
 assert(result.filter(x=>x.status==='rejected').every(x=>x.reason.code==='resource-exhausted'));
 const buckets=await db.collection('requestLimits').get();assert.equal(buckets.size,2);
 const client=env.authenticatedContext('owner').firestore();
 for(const bucket of buckets.docs){
  await assertFails(getDoc(doc(client,bucket.ref.path)));
  await assertFails(updateDoc(doc(client,bucket.ref.path),{tokens:100000}));
  await assertFails(deleteDoc(doc(client,bucket.ref.path)));
 }
});

test('recipient preview requires exact verified email and exposes only the invitation grant',async()=>{
  await db.doc('organizations/org').update({name:'Organization',privateBank:'hidden'});
  await db.doc('buildings/a').update({name:'Riverside',bankAccount:'hidden'});
  const {invitationId}=await call(invitation);
  const lookup=(uid='new',verified=true)=>invitationLookup({auth:{uid,token:{email:`${uid}@example.com`,email_verified:verified}},data:{invitationId}});
  await assert.rejects(lookup('wrong'),/team_invitation_unavailable/);
  await assert.rejects(lookup('new',false),/team_verified_email_required/);
  const preview=await lookup();
  assert.equal(preview.organizationName,'Organization');assert.equal(preview.canAccept,true);
  assert.deepEqual(preview.properties,[{id:'a',name:'Riverside'}]);
  assert(!('privateBank' in preview));assert(!('email' in preview));assert(!('invitedBy' in preview));
  assert.equal((await db.doc('memberships/new_org').get()).exists,false);
  await db.doc(`teamInvitations/${invitationId}`).update({expiresAt:Timestamp.fromMillis(1)});
  assert.equal((await lookup()).status,'expired');assert.equal((await lookup()).canAccept,false);
  await db.doc(`teamInvitations/${invitationId}`).update({expiresAt:Timestamp.fromMillis(Date.now()+60000)});
  await call({action:'revokeInvitation',operationId:'revoke',invitationId});
  assert.equal((await lookup()).canAccept,false);
  await assert.rejects(call({action:'acceptInvitation',operationId:'closed',invitationId},'new'),/team_invitation_closed/);
});

test('requests require explicit review and staff selection; rejection never grants membership',async()=>{
  await db.doc('invite_codes/CODE').set({orgId:'org'});
  const {requestId}=await call({action:'requestAccess',operationId:'request',inviteCode:'CODE',displayName:'Applicant'},'new');
  assert.equal((await db.doc('memberships/new_org').get()).exists,false);
  assert.equal((await read('requests')).records[0].canReview,true);
  const approval={action:'reviewRequest',operationId:'approve',requestId,decision:'approve',staffId:'staff',access:invitation.access};
  await call(approval);await call(approval);
  assert.equal((await db.doc('memberships/new_org').get()).data().staffId,'staff');
  assert.equal((await db.doc('staffProfiles/staff').get()).data().accountId,'new');
  assert.equal((await db.collection('teamActivity').get()).size,2);
  const second=await call({action:'requestAccess',operationId:'request',inviteCode:'CODE',displayName:'Other'},'other');
  await call({action:'reviewRequest',operationId:'reject',requestId:second.requestId,decision:'reject'});
  assert.equal((await db.doc('memberships/other_org').get()).exists,false);
  assert.equal((await db.doc(`teamRequests/${second.requestId}`).get()).data().status,'rejected');
  const events=(await db.collection('teamActivity').where('action','==','reviewRequest').get()).docs.map(d=>d.data());
  assert.deepEqual(events.map(e=>e.after.requestStatus).sort(),['approved','rejected']);
  assert.ok(events.every(e=>e.before.status==='pending'));
});

test('assignment property picker exposes only same-organization names to team administrators',async()=>{
  await db.doc('buildings/a').update({name:'Riverside',bankAccountNumber:'secret'});
  await db.doc('buildings/foreign').set({organizationId:'other',name:'Private'});
  assert.deepEqual((await read('buildings')).records,[{id:'a',organizationId:'org',name:'Riverside'}]);
  await setMember('worker');
  await assert.rejects(read('buildings','worker'),/team_access_denied/);
  await setMember('limited','administrator');
  await assert.rejects(read('buildings','limited'),/team_access_denied/);
});

test('account assignment hints exclude self and protected accounts and omit account policy for ordinary staff',async()=>{
  await setMember('worker');
  await setMember('admin','administrator',{buildingScope:'all',buildingIds:[]});
  await db.doc('staffProfiles/staff').update({accountId:'worker'});
  await db.doc('staffProfiles/admin').set({organizationId:'org',accountId:'admin'});
  const ownerPage=await read('staff');
  assert.equal(ownerPage.records.find(r=>r.id==='staff').canManageAccess,true);
  assert.equal(ownerPage.records.find(r=>r.id==='staff').accountAccess.role,'receptionist');
  const own=(await read('staff','worker')).records[0];
  assert.equal(own.canManageAccess,false);assert(!('accountAccess' in own));
  assert.equal((await read('staff','admin')).records.find(r=>r.id==='admin').canManageAccess,false);
  await db.doc('memberships/worker_org').update({organizationId:'other'});
  const broken=(await read('staff')).records.find(r=>r.id==='staff');
  assert.equal(broken.canManageAccess,false);assert(!('accountAccess' in broken));
});

test('staff edit hints protect owners and administrator peers and never grant staff editing',async()=>{
  await setMember('admin','administrator',{buildingScope:'all',buildingIds:[]});
  await setMember('worker');
  for(const accountId of ['owner','admin','worker'])await db.doc(`staffProfiles/${accountId}`).set({organizationId:'org',accountId,code:accountId,displayName:accountId,employmentStatus:'active'});
  const byId=page=>Object.fromEntries(page.records.map(r=>[r.id,r.canEditProfile]));
  assert.deepEqual(byId(await read('staff','admin')),{admin:false,owner:false,staff:true,worker:true});
  assert.deepEqual(byId(await read('staff','owner')),{admin:true,owner:false,staff:true,worker:true});
  assert.deepEqual(byId(await read('staff','worker')),{worker:false});
  await assert.rejects(call({action:'saveStaff',operationId:'protected',staffId:'owner',profile:{displayName:'Changed',code:'owner'}},'admin'),/team_role_protected/);
  // A hint is not a grant: revoking the actor between reading and saving is enforced.
  await db.doc('memberships/admin_org').update({status:'suspended'});
  await assert.rejects(call({action:'saveStaff',operationId:'revoked',staffId:'worker',profile:{displayName:'Changed',code:'worker'}},'admin'),/team_access_denied/);
});

test('profile saves retain login linkage, do not revoke account access and retry without duplicate audit',async()=>{
  await setMember('worker');
  await db.doc('staffProfiles/staff').update({accountId:'worker'});
  const input={action:'saveStaff',operationId:'edit-profile',staffId:'staff',profile:{displayName:'Updated',code:'S1',employmentStatus:'inactive',email:'',phone:''}};
  const first=await call(input); assert.deepEqual(await call(input),first);
  assert.equal((await db.doc('staffProfiles/staff').get()).data().accountId,'worker');
  assert.equal((await db.doc('staffProfiles/staff').get()).data().employmentStatus,'inactive');
  assert.equal((await db.doc('memberships/worker_org').get()).data().status,'active');
  assert.equal((await db.collection('teamActivity').get()).size,1);
  await assert.rejects(call({...input,staffId:undefined,operationId:'duplicate'}),/team_staff_code_exists/);
  assert.equal((await db.collection('teamActivity').get()).size,1);
});
test('team reads paginate, strip unlisted fields, and never cross organization boundaries',async()=>{
  await db.doc('staffProfiles/staff').update({secretToken:'not-returned'});
  await db.doc('staffProfiles/aaa').set({organizationId:'org',displayName:'First',createdAt:Timestamp.fromMillis(0)});
  await db.doc('staffProfiles/foreign').set({organizationId:'other',displayName:'Secret'});
  const first=await read('staff','owner',{limit:1});
  assert.equal(first.records[0].id,'aaa');assert.equal(first.records[0].createdAt,'1970-01-01T00:00:00.000Z');
  const second=await read('staff','owner',{limit:1,cursor:first.nextCursor});
  assert.equal(second.records[0].id,'staff');assert.equal(second.nextCursor,null);
  assert(!('secretToken' in second.records[0]));
  await assert.rejects(read('staff','owner',{limit:101}),/team_invalid_page/);
  await assert.rejects(read('staff','owner',{cursor:'../foreign'}),/team_invalid_page/);
});
test('staff see only their own profile/activity while administrators can filter activity',async()=>{
  await setMember('worker');await db.doc('staffProfiles/staff').update({accountId:'worker'});
  await db.doc('staffProfiles/other').set({organizationId:'org',accountId:'other',displayName:'Private'});
  for(const [id,actorId] of [['a','worker'],['b','other']])await db.doc(`teamActivity/${id}`).set({organizationId:'org',actorId,action:'test',createdAt:Timestamp.fromMillis(1000)});
  assert.equal((await read('staff','worker')).records.length,1);
  assert.deepEqual((await read('activity','worker')).records.map(r=>r.actorId),['worker']);
  assert.deepEqual((await read('activity','owner',{actorId:'other'})).records.map(r=>r.actorId),['other']);
  await assert.rejects(read('activity','worker',{actorId:'other'}),/team_access_denied/);
  for(const view of ['access','invitations','requests'])await assert.rejects(read(view,'worker'),/team_access_denied/);
});

test('activity pages use newest timestamp then descending ID and remain stable when new events arrive',async()=>{
  const event=async(id,millis,actorId='worker',organizationId='org')=>db.doc(`teamActivity/${id}`).set({organizationId,actorId,action:'saveStaff',createdAt:Timestamp.fromMillis(millis)});
  await event('z-oldest',1000);
  await event('b-tie',2000);
  await event('c-tie',2000);
  await event('a-newest',3000);
  await event('foreign',9000,'worker','other');
  await event('other-actor',2500,'other');
  await setMember('worker');
  const first=await read('activity','owner',{limit:2,actorId:'worker'});
  assert.deepEqual(first.records.map(r=>r.id),['a-newest','c-tie']);
  await event('inserted-later',4000);
  const second=await read('activity','owner',{limit:2,actorId:'worker',cursor:first.nextCursor});
  assert.deepEqual(second.records.map(r=>r.id),['b-tie','z-oldest']);
  assert.equal(second.nextCursor,null);
  assert.equal((await read('activity','worker',{limit:1})).records[0].id,'inserted-later');
  const all=await read('activity','owner');
  assert.deepEqual(all.records.map(r=>r.id),['inserted-later','a-newest','other-actor','c-tie','b-tie','z-oldest']);
});

test('activity cursors reject foreign, mismatched actor, missing and revoked access',async()=>{
  await setMember('worker');
  for(const [id,org,actor] of [['mine','org','worker'],['other','org','other'],['foreign','foreign-org','worker']]) {
    await db.doc(`teamActivity/${id}`).set({organizationId:org,actorId:actor,createdAt:Timestamp.fromMillis(1000)});
  }
  for(const cursor of ['missing','foreign','other']) {
    await assert.rejects(read('activity','worker',{cursor}),e=>e.code==='invalid-argument');
    await assert.rejects(read('activity','owner',{actorId:'worker',cursor}),e=>e.code==='invalid-argument');
  }
  await db.doc('memberships/worker_org').update({status:'revoked'});
  await assert.rejects(read('activity','worker',{cursor:'mine'}),e=>e.code==='permission-denied');
});
test('revoked users can read own access state but no directory or activity',async()=>{
  await setMember('worker','receptionist',{status:'revoked'});
  assert.equal((await read('myAccess','worker')).record.status,'revoked');
  assert.equal((await read('myAccess','outsider')).record,null);
  for(const view of ['staff','activity','access','invitations','requests'])await assert.rejects(read(view,'worker'),/team_access_denied/);
  await db.doc('teamRequests/one').set({organizationId:'org',userId:'worker',status:'pending'});
  await db.doc('teamRequests/two').set({organizationId:'org',userId:'other',status:'pending'});
  assert.deepEqual((await read('myRequests','worker')).records.map(r=>r.id),['one']);
});
test('v2 direct inventory reads, legacy join and policy tampering are denied',async()=>{
  await setMember('worker');
  await db.doc('invite_codes/CODE').set({orgId:'org'});
  for(const collection of ['buildings','rooms','tenants','bookings','payments']){
    await db.doc(`${collection}/sensitive`).set({organizationId:'org',buildingId:'a',secret:'private'});
    for(const uid of ['owner','worker'])await assertFails(getDoc(doc(env.authenticatedContext(uid).firestore(),`${collection}/sensitive`)));
  }
  const owner=env.authenticatedContext('owner').firestore();
  await assertFails(updateDoc(doc(owner,'organizations/org'),{accessVersion:1}));
  const outsider=env.authenticatedContext('outsider').firestore();
  await assertFails(setDoc(doc(outsider,'memberships/outsider_org'),{organizationId:'org',ownerId:'outsider',role:'member',status:'active',inviteCode:'CODE'}));
  await assertFails(updateDoc(doc(env.authenticatedContext('worker').firestore(),'memberships/worker_org'),{role:'owner'}));
  await assertFails(deleteDoc(doc(owner,'memberships/owner_org')));
});
test('legacy organization administrators cannot self-enable v2 or forge v2 memberships',async()=>{
  await db.doc('organizations/legacy').set({createdBy:'owner'});
  await db.doc('memberships/owner_legacy').set({organizationId:'legacy',ownerId:'owner',role:'admin',status:'active'});
  const client=env.authenticatedContext('owner').firestore();
  await assertFails(updateDoc(doc(client,'organizations/legacy'),{accessVersion:2}));
  await assertFails(updateDoc(doc(client,'memberships/owner_legacy'),{accessVersion:2,role:'owner'}));
});
test('v2 booking and lease functions enforce scope, price authority and suspension',async()=>{
  await db.doc('buildings/a').update({timeZone:'UTC'});
  await setMember('manager','manager');await setMember('reception','receptionist');
  await db.doc('rooms/r').set({organizationId:'org',buildingId:'a',rentalMode:'both',currency:'USD'});
  await db.doc('rooms/foreign').set({organizationId:'org',buildingId:'b',rentalMode:'both',currency:'USD'});
  const booking={organizationId:'org',roomId:'r',guestName:'Guest',startTime:{__timestamp:10000000},endTime:{__timestamp:20000000},totalPrice:100};
  const ctx=uid=>({auth:{uid}});
  await assert.rejects(calendar({action:'create',bookingId:'bad',booking:{...booking,roomId:'foreign'}},ctx('manager')),/booking_access_denied/);
  await assert.rejects(calendar({action:'create',bookingId:'price',booking},ctx('reception')),/booking_price_authority_required/);
  await calendar({action:'create',bookingId:'one',booking},ctx('manager'));
  await assert.rejects(calendar({action:'edit',bookingId:'one',changes:{totalPrice:50}},ctx('reception')),/booking_access_denied/);
  await calendar({action:'status',bookingId:'one',status:'confirmed'},ctx('reception'));
  await assert.rejects(calendar({action:'refund',bookingId:'one',operationId:'refund',amount:1,paymentMethod:'cash'},ctx('manager')),/booking_access_denied/);
  await db.doc('memberships/owner_org').update({status:'suspended'});
  await assert.rejects(calendar({action:'status',bookingId:'one',status:'checkedIn'},ctx('owner')),/booking_access_denied/);
  const lease={organizationId:'org',roomId:'foreign',fullName:'Tenant',status:'active',moveInDate:{__timestamp:Date.parse('2100-01-01T00:00:00Z')}};
  await assert.rejects(tenant({create:true,tenantId:'t',tenant:lease},ctx('manager')),/booking_access_denied/);
  await tenant({create:true,tenantId:'t',tenant:{...lease,roomId:'r'}},ctx('manager'));
  await assert.rejects(tenant({tenantId:'t',tenant:{roomId:'foreign'}},ctx('manager')),/booking_access_denied/);
});
test('legacy AI organization-wide reads/import permission is denied for v2',async()=>{
  await setMember('worker');
  await assert.rejects(ai.member('worker','org'),/ai_scoped_access_required/);
  await assert.rejects(ai.member('owner','org',true),/ai_scoped_access_required/);
});

test('operational audits commit with booking money and leases, omit private data and suppress retries',async()=>{
  await db.doc('buildings/a').update({timeZone:'UTC'});
  const ctx={auth:{uid:'owner'}};
  await db.doc('rooms/r').set({organizationId:'org',buildingId:'a',rentalMode:'both',currency:'USD'});
  const create={action:'create',bookingId:'audit-booking',booking:{organizationId:'org',roomId:'r',guestName:'PRIVATE-NAME',guestPhone:'PRIVATE-PHONE',notes:'PRIVATE-NOTES',startTime:{__timestamp:10000000},endTime:{__timestamp:20000000},totalPrice:100,depositAmount:20}};
  await calendar(create,ctx);await calendar(create,ctx);
  const pay={action:'payment',bookingId:'audit-booking',operationId:'audit-pay',amount:25,paymentMethod:'cash'};
  await calendar(pay,ctx);await calendar(pay,ctx);
  await assert.rejects(calendar({...pay,operationId:'bad',amount:200},ctx),/booking_overpayment/);
  await calendar({action:'status',bookingId:'audit-booking',status:'checkedIn'},ctx);
  await calendar({action:'checkout',bookingId:'audit-booking',paymentMethod:'cash'},ctx);
  await calendar({action:'checkout',bookingId:'audit-booking',paymentMethod:'cash'},ctx);
  const lease={create:true,tenantId:'audit-tenant',tenant:{organizationId:'org',roomId:'r',status:'active',fullName:'PRIVATE-TENANT',moveInDate:{__timestamp:Date.parse('2026-09-01T00:00:00Z')},isMainTenant:true,backdateReason:'PRIVATE-REASON'}};
  await tenant(lease,ctx);await tenant(lease,ctx);
  await assert.rejects(tenant({tenantId:'audit-tenant',tenant:{status:'moveOut',moveOutDate:{__timestamp:40000000}}},ctx),/lease_dedicated_workflow_required/);
  const {createLeaseLifecycleHandler}=require('../lease_lifecycle');const lifecycle=createLeaseLifecycleHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
  const identity={organizationId:'org',buildingId:'a',tenantId:'audit-tenant'},read=(await lifecycle({auth:ctx.auth,data:{...identity,action:'read'}})).record;
  const out={...identity,action:'moveOut',operationId:'audit-out',revision:read.revision,timeZone:'UTC',effectiveDate:'2026-09-27',reason:'PRIVATE-REASON'};await lifecycle({auth:ctx.auth,data:out});await lifecycle({auth:ctx.auth,data:out});
  const events=(await db.collection('teamActivity').get()).docs.map(d=>d.data());
  assert.equal(events.length,6);
  assert.ok(events.every(e=>e.actorId==='owner'&&e.organizationId==='org'));
  assert.ok(!JSON.stringify(events).includes('PRIVATE'));
  const payment=events.find(e=>e.action==='booking_payment');
  assert.equal(payment.before.paidAmount,0);assert.equal(payment.after.paidAmount,25);
  assert.equal(events.find(e=>e.action==='lease_moveOut').after.status,'moveOut');
});

test('rent history pages tied timestamps, protects projections and rechecks current access for former tenants',async()=>{
 const {createTenantRentHandler}=require('../tenant_rent');
 const api=createTenantRentHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=(data={},uid='owner')=>api({auth:{uid},data:{action:'history',organizationId:'org',buildingId:'a',tenantId:'past',...data}});
 await db.doc('tenants/past').set({organizationId:'org',buildingId:'a',isMainTenant:true,status:'moveOut'});
 const ids=Array.from({length:23},(_,i)=>i.toString(16).padStart(64,'0'));
 await Promise.all(ids.map((id,i)=>db.doc(`tenants/past/rentHistory/${id}`).set({organizationId:'org',actorId:'owner',createdAt:Timestamp.fromMillis(1000),currency:'USD',timeZone:'UTC',effectiveDate:'2026-10-01',reason:'Private reason',before:null,after:{effectiveDate:'2026-10-01',amountMinor:100+i,internal:'secret'},fingerprint:'secret',result:{private:'secret'}})));
 await setMember('manager','manager');
 const first=await run({},'manager');assert.equal(first.records.length,20);assert.equal(first.records[0].id,ids[22]);assert.equal(first.nextCursor,ids[3]);
 const last=await run({cursor:first.nextCursor},'manager');assert.deepEqual(last.records.map(v=>v.id),ids.slice(0,3).reverse());assert.equal(last.nextCursor,null);
 assert.equal(JSON.stringify(first).includes('secret'),false);assert.deepEqual(Object.keys(first.records[0]).sort(),['id','actorId','createdAt','currency','timeZone','effectiveDate','reason','before','after'].sort());assert.equal(first.records[0].reason,'Private reason');
 await assert.rejects(run({cursor:'bad'}),e=>e.code==='invalid-argument');await assert.rejects(run({cursor:'f'.repeat(64)}),e=>e.code==='invalid-argument');
 for(const patch of [{buildingIds:['b']},{permissionOverrides:{overridePrices:false}},{status:'suspended'}]){await setMember('manager','manager',patch);await assert.rejects(run({cursor:first.nextCursor},'manager'),e=>e.code==='permission-denied');}
 for(const role of ['receptionist','accountant','housekeeping']){await setMember('other',role);await assert.rejects(run({},'other'),e=>e.code==='permission-denied');}
 await db.doc('tenants/past').update({organizationId:'foreign'});await assert.rejects(run(),e=>e.code==='not-found');
});

test('lease lifecycle terms and individual moves preserve history, scope and actual occupancy',async()=>{
 const {createLeaseLifecycleHandler}=require('../lease_lifecycle'),Stamp=Timestamp;
 const api=createLeaseLifecycleHandler({db,Timestamp:{now:()=>Stamp.fromDate(new Date('2026-09-27T12:00:00Z')),fromMillis:v=>Stamp.fromMillis(v)},HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});await db.doc('buildings/b').set({organizationId:'org',timeZone:'UTC'});
 for(const [id,buildingId] of [['r','a'],['new','a'],['cross','b']])await db.doc(`rooms/${id}`).set({organizationId:'org',buildingId,currency:'USD',rentalMode:'monthly'});
 await db.doc('tenants/main').set({organizationId:'org',buildingId:'a',roomId:'r',isMainTenant:true,status:'active',moveInDate:Stamp.fromDate(new Date('2026-09-01')),monthlyRent:100,currency:'USD'});
 await assert.rejects(tenant({create:true,tenantId:'forged',tenant:{organizationId:'org',roomId:'r',fullName:'Forged',isMainTenant:true,status:'active',moveInDate:{__timestamp:Date.parse('2026-09-01')},occupancyStartDate:{__timestamp:Date.parse('2027-09-01')}}},{auth:{uid:'owner'}}),e=>e.message==='lease_dedicated_workflow_required');
 await db.doc('tenants/mate').set({organizationId:'org',buildingId:'a',roomId:'r',isMainTenant:false,mainTenantId:'main',status:'active',moveInDate:Stamp.fromDate(new Date('2026-09-02'))});
 const run=(data,uid='owner')=>api({auth:{uid},data:{organizationId:'org',buildingId:'a',tenantId:'main',...data}});
 const command=async(action,extras={})=>{const r=(await run({action:'read',tenantId:extras.tenantId??'main'})).record;return {action,operationId:action,revision:r.revision,timeZone:r.timeZone,reason:'Documented agreement',...extras};};
 await setMember('manager','manager');
 await run(await command('terms',{contractEndDate:'2026-12-31'}));assert.equal((await db.doc('tenants/main').get()).data().status,'active');
 const move=await command('move',{effectiveDate:'2026-09-27',destinationRoomId:'new',destinationMainTenantId:null});await assert.rejects(run(move),e=>e.message==='lease_handle_roommates_first');
 const out=await command('moveOut',{tenantId:'mate',effectiveDate:'2026-09-26'});await assert.rejects(run(out,'manager'),e=>e.code==='permission-denied');await run(out);assert.deepEqual(await run(out),{tenantId:'mate',buildingId:'a',roomId:'r'});
 await run(move);assert.equal((await db.doc('tenants/main').get()).data().roomId,'new');assert.equal((await db.collection('leaseOccupancy').get()).size,2);
 const oldRoomBooking={bookingId:'past-booking',action:'create',booking:{organizationId:'org',roomId:'r',guestName:'Guest',startTime:{__timestamp:Date.parse('2026-09-25T00:00:00Z')},endTime:{__timestamp:Date.parse('2026-09-25T02:00:00Z')},totalPrice:10}};
 await db.doc('rooms/r').update({rentalMode:'both'});await assert.rejects(calendar(oldRoomBooking,{auth:{uid:'owner'}}),e=>e.message==='booking_conflict');
 const cross=await command('move',{operationId:'cross',effectiveDate:'2026-09-27',destinationRoomId:'cross',destinationMainTenantId:null});await assert.rejects(run(cross,'manager'),e=>e.code==='invalid-argument'||e.code==='permission-denied');
 assert.equal((await run({action:'history'})).records.length,2);
 const client=env.authenticatedContext('owner').firestore();await assertFails(getDoc(doc(client,'leaseOccupancy/private')));
});

test('invoice quotes prorate saved rent and persist immutable income or expense amounts with strict financial authorization',async()=>{
 const {createInvoiceHandler}=require('../invoices'),Stamp=Timestamp;
 const api=createInvoiceHandler({db,Timestamp:{now:()=>Stamp.fromDate(new Date('2026-09-27T12:00:00Z')),fromMillis:v=>Stamp.fromMillis(v)},HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 const run=(data,uid='owner')=>api({auth:{uid},data:{organizationId:'org',buildingId:'a',...data}}),feesMinor={internetFee:0,cableTVFee:0,hotWaterFee:0,lateFee:0,taxAmount:0};
 await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh',currency:'VND',rentalContract:{direction:'rentIn',status:'active',partyName:'Landlord',partyPhone:'',amountMinor:3100000,dueDay:1,startDate:'2026-01-01',endDate:null,notes:''}});
 await db.doc('tenants/invoiced').set({organizationId:'org',buildingId:'a',roomId:'r',isMainTenant:true,status:'active',fullName:'Private',currency:'VND',monthlyRentMinor:3100000,moveInDate:Stamp.fromDate(new Date('2026-09-30T17:00:00Z')),rentSchedule:[{effectiveDate:'2026-10-16',amountMinor:6200000}]});
 const quote={kind:'tenantRent',tenantId:'invoiced',startDate:'2026-10-01',endDate:'2026-11-01',dueDate:'2026-10-05',feesMinor,reason:'Agreed billing'};
 const q=(await run({action:'quote',...quote})).record;assert.equal(q.amountMinor,4700000);
 const create={action:'create',...quote,operationId:'invoice',quoteRevision:q.quoteRevision};const result=await run(create);assert.deepEqual(await run(create),result);
 // An overlapping period is refused already at review (quote) and again at create.
 await assert.rejects(run({action:'quote',...quote}),e=>e.code==='already-exists');await assert.rejects(run({...create,operationId:'duplicate'}),e=>e.code==='already-exists');
 const original=(await db.doc(`payments/${result.invoiceId}`).get()).data();await db.doc('tenants/invoiced').update({monthlyRentMinor:9999999});assert.deepEqual((await db.doc(`payments/${result.invoiceId}`).get()).data(),original);
 const read=(await run({action:'read',invoiceId:result.invoiceId})).record;await setMember('manager','manager',{permissionOverrides:{overridePrices:false}});await assert.rejects(run({action:'edit',invoiceId:result.invoiceId,operationId:'edit',revision:read.revision,reason:'Fee',dueDate:'2026-10-05',feesMinor:{...feesMinor,taxAmount:1}},'manager'),e=>e.code==='permission-denied');
 const expenseQuote={...quote,kind:'buildingRent',tenantId:null};const eq=(await run({action:'quote',...expenseQuote})).record;assert.equal(eq.direction,'expense');const expense=await run({action:'create',...expenseQuote,quoteRevision:eq.quoteRevision,operationId:'expense'});
 const pay=createPaymentHandler({db,Timestamp:Stamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});await assert.rejects(pay({auth:{uid:'owner'},data:{organizationId:'org',paymentId:expense.invoiceId,operationId:'bad-income',action:'collect',amountMinor:1,paymentMethod:'cash'}}),e=>e.message==='payment_use_expense_workflow');
 assert.equal((await run({action:'history',invoiceId:expense.invoiceId})).records.length,1);
 let er=(await run({action:'read',invoiceId:expense.invoiceId})).record;await run({action:'payExpense',invoiceId:expense.invoiceId,revision:er.revision,operationId:'paid-expense',amountMinor:100,paymentMethod:'cash',reason:'Receipt'});er=(await run({action:'read',invoiceId:expense.invoiceId})).record;assert.equal(er.paidMinor,100);await assert.rejects(run({action:'void',invoiceId:expense.invoiceId,revision:er.revision,operationId:'void-paid',reason:'Wrong invoice'}),e=>e.message==='invoice_refund_first');
});

test('booking workspace calculates receptionist prices, replays exact operations and separates refunds',async()=>{
 const {createBookingWorkspaceHandler}=require('../booking_workspace');const api=createBookingWorkspaceHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}},calendar});
 await db.doc('buildings/a').update({timeZone:'Asia/Ho_Chi_Minh'});await db.doc('rooms/r').set({organizationId:'org',buildingId:'a',currency:'USD',rentalMode:'hourly',hourlyPrice:10,dailyPrice:40,dailyPriceThresholdHours:6});await setMember('reception','receptionist');
 const run=(data,uid='reception')=>api({auth:{uid},data:{organizationId:'org',buildingId:'a',...data}}),fields={roomId:'r',startLocal:'2026-10-01 09:00',endLocal:'2026-10-01 11:30',occurrence:'first',pricingType:'hourly'};
 const q=(await run({action:'quote',...fields})).record;assert.equal(q.totalMinor,2500);
 await assert.rejects(run({action:'quote',...fields,overrideMinor:100,overrideReason:'Discount'}),e=>e.code==='permission-denied');assert.equal((await run({action:'quote',...fields,overrideMinor:100,overrideReason:'Discount'},'owner')).record.totalMinor,100);
 const create={action:'save',...fields,bookingId:'workspace-booking',operationId:'book-create',revision:null,roomRevision:q.roomRevision,guestName:'Guest',guestPhone:'123',notes:'Private note',depositMinor:1000};await run(create);await run(create);assert.equal((await db.collection('bookings').get()).size,1);
 await assert.rejects(run({...create,guestName:'Other'}),e=>e.code==='failed-precondition');
 let r=(await run({action:'read',bookingId:create.bookingId})).record;const pay={action:'command',bookingId:create.bookingId,operationId:'pay',revision:r.revision,command:'payment',amountMinor:500,paymentMethod:'cash',status:null,reason:'Receipt'};await run(pay);await run(pay);r=(await run({action:'read',bookingId:create.bookingId})).record;assert.equal(r.paidAmount,5);
 await assert.rejects(run({...pay,operationId:'refund',revision:r.revision,command:'refundRent'}),e=>e.code==='permission-denied');await run({...pay,operationId:'refund',revision:r.revision,command:'refundRent'},'owner');r=(await run({action:'read',bookingId:create.bookingId})).record;assert.equal(r.paidAmount,0);assert.equal(r.depositRefundedAmount,0);
 await setMember('reception','receptionist',{buildingIds:['b']});await assert.rejects(run(pay),e=>e.code==='permission-denied');
});

test('property layout suggests new room defaults and preserves existing inventory',async()=>{
 const {createPropertyLayoutHandler}=require('../property_layout');const api=createPropertyLayoutHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});
 await db.doc('rooms/r').set({organizationId:'org',buildingId:'a',roomNumber:'Original',roomType:'Original',area:20});const before=(await db.doc('rooms/r').get()).data();
 const run=(data,uid='owner')=>api({auth:{uid},data:{organizationId:'org',buildingId:'a',...data}}),r=(await run({action:'read'})).record;
 const c={action:'update',revision:r.revision,operationId:'layout',layout:{floors:2,roomPrefix:'R',roomType:'Studio',roomArea:35.5,floorRoomCounts:[2,3]}};
 await run(c);await run(c);assert.deepEqual((await db.doc('rooms/r').get()).data(),before);await assert.rejects(run({...c,operationId:'bad',layout:{...c.layout,floorRoomCounts:[1]}}),e=>e.code==='invalid-argument');
 const room=createRoomDetailsHandler({db,Timestamp:Timestamp,HttpsError:class extends Error{constructor(code,message){super(message);this.code=code;}}});const defaults=(await room({auth:{uid:'owner'},data:{organizationId:'org',buildingId:'a',roomId:'new',action:'prepareCreate'}})).record;assert.equal(defaults.roomType,'Studio');assert.equal(defaults.area,35.5);assert.equal(defaults.roomNumber,'R');
});

test('organization settings: v2 update, leave and close against the emulator, closed organizations are hidden and unjoinable',async()=>{
 const {createOrganizationSettingsHandler}=require('../organization_settings');
 const E=class extends Error{constructor(code,message){super(message);this.code=code;}};
 const api=createOrganizationSettingsHandler({db,Timestamp:Timestamp,HttpsError:E});
 const directory=createOrganizationDirectory({db,HttpsError:E});
 const run=(data,uid='owner')=>api({auth:{uid},data:{organizationId:'org',...data}});
 await db.doc('organizations/org').update({name:'Sunrise',bankAccountNumber:'PRIVATE'});
 await setMember('viewer','receptionist');await setMember('admin','administrator',{buildingScope:'all',buildingIds:[]});
 assert.equal((await run({action:'read'},'viewer')).bankAccountNumber,undefined);
 assert.equal((await run({action:'read'},'admin')).bankAccountNumber,'PRIVATE');
 const fields={name:'Sunrise Homes',address:'',phone:'',email:'',taxCode:'',bankName:'',bankAccountNumber:'NEWBANK',bankAccountName:''};
 await assert.rejects(run({action:'update',operationId:'u0',fields},'viewer'),e=>e.code==='permission-denied');
 await run({action:'update',operationId:'u1',fields},'admin');
 assert.equal((await db.doc('organizations/org').get()).data().name,'Sunrise Homes');
 assert.ok(!JSON.stringify((await db.collection('teamActivity').get()).docs.map(d=>d.data())).includes('NEWBANK'));
 // Clients can never read or forge the ledger or organization fields directly.
 const client=env.authenticatedContext('owner').firestore();
 await assertFails(getDoc(doc(client,'organizationOperations/any')));
 await assertFails(updateDoc(doc(client,'organizations/org'),{name:'Direct'}));
 await run({action:'leave',operationId:'l1'},'viewer');
 assert.equal((await db.doc('memberships/viewer_org').get()).data().status,'revoked');
 await call(invitation);
 await assert.rejects(run({action:'close',operationId:'c1',confirmName:'Wrong'}),e=>e.code==='invalid-argument');
 const closed=await run({action:'close',operationId:'c1',confirmName:'Sunrise Homes'});
 assert.equal(closed.status,'closed');
 for(const id of ['owner_org','admin_org','viewer_org'])assert.equal((await db.doc(`memberships/${id}`).get()).data().status,'revoked');
 assert.ok((await db.doc('organizations/org').get()).exists,'records retained until purgeAfter');
 assert.deepEqual((await directory({auth:{uid:'owner'},data:{}})).records,[]);
 const pending=(await db.collection('teamInvitations').where('organizationId','==','org').get()).docs[0];
 await assert.rejects(call({action:'acceptInvitation',operationId:'accept',invitationId:pending.id},'new'),e=>e.message==='org_closed');
 await assert.rejects(invitationLookup({auth:{uid:'new',token:{email:'new@example.com',email_verified:true}},data:{invitationId:pending.id}}),e=>e.message==='org_closed');
});

test('retired copy refuses writes and purge preserves other organizations and their subcollections',async()=>{
 const {createOrganizationSettingsHandler}=require('../organization_settings');
 const {createOrganizationPurge}=require('../organization_purge');
 const E=class extends Error{constructor(code,message){super(message);this.code=code;}};
 const api=createOrganizationSettingsHandler({db,Timestamp:Timestamp,HttpsError:E});
 const run=(data,uid='owner')=>api({auth:{uid},data:{organizationId:'org',...data}});
 await db.doc('organizations/org').update({name:'Source'});
 await db.doc('organizations/dest').set({name:'Dest',createdBy:'owner',accessVersion:2});
 await db.doc('memberships/owner_dest').set({organizationId:'dest',ownerId:'owner',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]});
 await db.doc('rooms/r').set({organizationId:'org',buildingId:'a',roomNumber:'1'});
 await db.doc('tenants/t').set({organizationId:'org',buildingId:'a',roomId:'r',fullName:'Main'});
 await db.doc('tenants/t/rentHistory/h').set({organizationId:'org',tenantId:'t'});
 await db.doc('tenants/old').set({roomId:'r',fullName:'Legacy child'});
 await db.doc('payments/p').set({organizationId:'org',tenantId:'t',roomId:'r'});
 await assert.rejects(run({action:'copyPreview',targetOrganizationId:'dest'}),/org_copy_retired/);
 const copy={action:'copy',operationId:'copy1',targetOrganizationId:'dest'};
 await assert.rejects(run(copy),/org_copy_retired/);await assert.rejects(run(copy),/org_copy_retired/);
 assert.equal((await db.collection('tenants').where('organizationId','==','dest').get()).size,0);
 await db.doc('buildings/destProperty').set({organizationId:'dest'});
 await db.doc('rooms/destRoom').set({organizationId:'dest',buildingId:'destProperty'});
 await db.doc('tenants/destTenant').set({organizationId:'dest',buildingId:'destProperty',roomId:'destRoom',fullName:'Main'});
 await db.doc('tenants/destTenant/rentHistory/h').set({organizationId:'dest',tenantId:'destTenant'});
 await db.doc('payments/destPayment').set({organizationId:'dest',tenantId:'destTenant',roomId:'destRoom'});
 const main=await db.doc('tenants/destTenant').get();
 assert.equal((await main.ref.collection('rentHistory').get()).size,1);
 assert.equal((await db.collection('payments').where('tenantId','==',main.id).get()).docs[0].data().organizationId,'dest');
 assert.ok((await db.doc('tenants/t').get()).exists,'source kept');
 // Close the copy target, pass its purge date, then purge: only dest data goes.
 await run({action:'close',operationId:'close-dest',confirmName:'Dest',organizationId:'dest'});
 await db.doc('organizations/dest').update({purgeAfter:Timestamp.fromMillis(Date.now()-1000)});
 const logger={info(){},warn(){},error(){}};
 const results=await createOrganizationPurge({db,Timestamp:Timestamp,logger})();
 assert.equal(results.find(r=>r.id==='dest').status,'purged');
 assert.equal((await db.doc('organizations/dest').get()).exists,false);
 assert.equal((await db.collection('tenants').where('organizationId','==','dest').get()).size,0);
 assert.equal((await main.ref.collection('rentHistory').get()).size,0,'subcollections removed');
 assert.ok((await db.doc('tenants/t').get()).exists&&(await db.doc('tenants/t/rentHistory/h').get()).exists,'source untouched');
 assert.ok((await db.doc('purgedOrganizations/dest').get()).exists);
 const client=env.authenticatedContext('owner').firestore();
 await assertFails(getDoc(doc(client,'purgedOrganizations/dest')));
});

test('a closed organization can be restored by its owner and reappears with previous member status',async()=>{
 const {createOrganizationSettingsHandler}=require('../organization_settings');
 const E=class extends Error{constructor(code,message){super(message);this.code=code;}};
 const api=createOrganizationSettingsHandler({db,Timestamp:Timestamp,HttpsError:E});
 const directory=createOrganizationDirectory({db,HttpsError:E});
 const run=(data,uid='owner')=>api({auth:{uid},data:{organizationId:'org',...data}});
 await db.doc('organizations/org').update({name:'Sunrise'});
 await setMember('paused','manager',{status:'suspended'});
 await run({action:'close',operationId:'close',confirmName:'Sunrise'});
 assert.deepEqual((await directory({auth:{uid:'owner'},data:{}})).records,[]);
 assert.deepEqual((await api({auth:{uid:'owner'},data:{action:'closedList'}})).records.map(r=>r.id),['org']);
 assert.equal((await run({action:'restore',operationId:'restore'})).status,'restored');
 assert.deepEqual((await directory({auth:{uid:'owner'},data:{}})).records.map(r=>r.id),['org']);
 assert.equal((await db.doc('memberships/owner_org').get()).data().status,'active');
 assert.equal((await db.doc('memberships/paused_org').get()).data().status,'suspended');
 assert.equal((await db.doc('organizations/org').get()).data().closedAt,null);
});

test('waiting members see their organization marked waiting; removed-role invitations cannot be accepted',async()=>{
 const E=class extends Error{constructor(code,message){super(message);this.code=code;}};
 const directory=createOrganizationDirectory({db,HttpsError:E});
 await db.doc('organizations/org').update({name:'Visible'});
 await setMember('wait',null,{status:'assignmentRequired',buildingIds:[]});
 await setMember('old','viewer');
 for(const uid of ['wait','old']){
  const rows=(await directory({auth:{uid},data:{}})).records;
  assert.deepEqual(rows.map(r=>[r.id,r.waiting]),[['org',true]],uid);
 }
 assert.equal((await directory({auth:{uid:'owner'},data:{}})).records[0].waiting,undefined);
 await setMember('gone','manager',{status:'revoked'});
 assert.deepEqual((await directory({auth:{uid:'gone'},data:{}})).records,[]);
 // A pending invitation created before viewer was removed.
 await db.doc('teamInvitations/oldInvite').set({organizationId:'org',staffId:'staff',email:'new@example.com',
  access:{accessVersion:2,role:'viewer',buildingScope:'selected',buildingIds:['a'],permissionOverrides:{}},
  status:'pending',invitedBy:'owner',createdAt:Timestamp.now(),expiresAt:Timestamp.fromMillis(Date.now()+86400000)});
 const preview=await invitationLookup({auth:{uid:'new',token:{email:'new@example.com',email_verified:true}},data:{invitationId:'oldInvite'}});
 assert.equal(preview.roleRemoved,true);assert.equal(preview.canAccept,false);
 await assert.rejects(call({action:'acceptInvitation',operationId:'acc',invitationId:'oldInvite'},'new'),e=>e.message==='team_invitation_role_removed');
 assert.equal((await db.doc('memberships/new_org').get()).exists,false);
 await assert.rejects(call({...invitation,operationId:'viewer-invite',access:{...invitation.access,role:'viewer'}}),e=>e.code==='failed-precondition'&&e.message==='team_role_not_found');
});

test('account deletion hands over or closes owned organizations and removes personal records',async()=>{
 const {createAccountDeletionHandler}=require('../account_deletion');
 const E=class extends Error{constructor(code,message){super(message);this.code=code;}};
 const api=createAccountDeletionHandler({db,Timestamp:Timestamp,HttpsError:E});
 const run=(data,authTime=Math.floor(Date.now()/1000))=>api({auth:{uid:'owner',token:{auth_time:authTime}},data});
 await db.doc('organizations/org').update({name:'Main'});
 await setMember('admin','administrator',{buildingScope:'all',buildingIds:[]});
 await db.doc('organizations/second').set({name:'Second',accessVersion:2,createdBy:'owner'});
 await db.doc('memberships/owner_second').set({organizationId:'second',ownerId:'owner',accessVersion:2,role:'owner',status:'active',buildingScope:'all',buildingIds:[]});
 await db.doc('owners/owner').set({name:'Owner'});
 await db.doc('staffProfiles/staff').update({accountId:'owner'});
 const preview=await run({action:'preview'});
 assert.deepEqual(preview.organizations.map(o=>[o.organizationId,o.plan]).sort(),[['org','decide'],['second','close']]);
 await assert.rejects(run({action:'delete',operationId:'d',decisions:{}},Math.floor(Date.now()/1000)-3600),e=>e.message==='recent_login_required');
 const result=await run({action:'delete',operationId:'d',decisions:{org:{action:'transfer',to:'admin'}}});
 assert.equal(result.status,'dataDeleted');
 assert.equal((await db.doc('memberships/admin_org').get()).data().role,'owner');
 assert.equal((await db.doc('memberships/owner_org').get()).data().status,'revoked');
 assert.equal((await db.doc('memberships/owner_org').get()).data().email,null);
 assert.ok((await db.doc('organizations/second').get()).data().closedAt);
 assert.equal((await db.doc('owners/owner').get()).exists,false);
 assert.equal((await db.doc('staffProfiles/staff').get()).data().accountId,null);
 const client=env.authenticatedContext('owner').firestore();
 await assertFails(getDoc(doc(client,'accountDeletions/owner')));
});
