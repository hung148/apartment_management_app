const functions = require('firebase-functions');
const {initializeApp,getApps,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp,FieldValue}=require('firebase-admin/firestore');
initializeApp();

const db = getFirestore();
// preferRest (2026-10-10, speed): talk to Firestore over plain HTTPS instead of
// gRPC. A cold start then skips loading the gRPC libraries (a few hundred ms).
// Only snapshot listeners (onSnapshot) need gRPC, and the server uses none; if
// one is ever added, the library switches to gRPC by itself. Settings can only
// be set once, before the first read; if that ever fails, gRPC stays in use.
try{db.settings({preferRest:true});}catch(e){console.warn('preferRest not applied');}
const {createCallableGroups}=require('./request_security');
// Calls are registered by name and served by a few grouped functions (see
// createCallableGroups and the exports at the end of this file).
const callables=createCallableGroups({onCall:functions.https.onCall,db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError,
 observe:timing=>console.info(JSON.stringify(timing))});
const secureCallable=callables.register;
// readOnly (2026-10-09, speed): calls that only read start alongside the request
// guard; their answer is held until the guard passes (request_security.js).
const {createDeletedRecordsHandler}=require('./deleted_records');
const deletedRecords=createDeletedRecordsHandler({db,Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('deletedRecords',request=>deletedRecords(request));
// Always-running copies (minInstances): OFF (Tom, 2026-10-06) so the app stays
// free. Grouped functions are called often enough to stay warm on their own;
// turning this on ({minInstances:1}) costs money every month.
const HOT={};
const {createPropertyLayoutHandler}=require('./property_layout');
const propertyLayoutHandler=createPropertyLayoutHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('propertyLayout',request=>propertyLayoutHandler(request));
const {createInvoiceHandler}=require('./invoices');
const invoiceHandler=createInvoiceHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('invoices',{readOnly:d=>['list','read','history'].includes(d?.action)},request=>invoiceHandler(request));
const {createUtilityReadingsHandler}=require('./utility_readings');
// Meter photos (2026-10-04) use the Drive set up below; looked up when a request comes in.
const utilityReadingsHandler=createUtilityReadingsHandler({db,Timestamp,HttpsError:functions.https.HttpsError,getDrive:()=>drive});
secureCallable('utilityReadings',request=>utilityReadingsHandler(request));
const {createServiceFeesHandler}=require('./service_fees');
const serviceFeesHandler=createServiceFeesHandler({db,Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('serviceFees',request=>serviceFeesHandler(request));
const {createLeaseLifecycleHandler}=require('./lease_lifecycle');
const leaseLifecycleHandler=createLeaseLifecycleHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('leaseLifecycle',request=>leaseLifecycleHandler(request));
const {createTenantRentHandler}=require('./tenant_rent');
const tenantRentHandler=createTenantRentHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('tenantRent',request=>tenantRentHandler(request));
const {createTenantRoommatesHandler}=require('./tenant_roommates');
const tenantRoommatesHandler=createTenantRoommatesHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('tenantRoommates',request=>tenantRoommatesHandler(request));
const {createTenantLeasesHandler}=require('./tenant_leases');
const tenantLeasesHandler=createTenantLeasesHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('tenantLeases',request=>tenantLeasesHandler(request));
const {createTenantContactsHandler}=require('./tenant_contacts');
const tenantContactsHandler=createTenantContactsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('tenantContacts',{readOnly:d=>['list','read'].includes(d?.action)},request=>tenantContactsHandler(request));
const {createPropertyContractHandler}=require('./property_contract');
const propertyContractHandler=createPropertyContractHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('propertyContract',request=>propertyContractHandler(request));
const {createBookingSettingsHandler}=require('./booking_settings');
const bookingSettingsHandler=createBookingSettingsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('roomBookingSettings',request=>bookingSettingsHandler(request));
const {createRoomRatesHandler}=require('./room_rates');
const roomRatesHandler=createRoomRatesHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('roomRates',request=>roomRatesHandler(request));
const {createRoomDetailsHandler}=require('./room_details');
const roomDetailsHandler=createRoomDetailsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('roomDetails',request=>roomDetailsHandler(request));
const {createPropertyDetailsHandler}=require('./property_details');
const propertyDetailsHandler=createPropertyDetailsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('propertyDetails',request=>propertyDetailsHandler(request));
const {createHousekeepingHandler}=require('./housekeeping');
const housekeepingHandler=createHousekeepingHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('mutateHousekeepingTask',request=>housekeepingHandler(request));
const {createTechnicalProblemsHandler}=require('./technical_problems');
// B7b: problem photos in the owner's Google Drive. Local emulator runs use a
// stand-in kept in the emulator's Firestore (nothing reaches Google).
const {createGoogleDriveHandler,googleDrive,fakeDrive}=require('./drive');
const drive=require('./request_security').localEmulator()?fakeDrive(db):googleDrive();
const technicalProblemsHandler=createTechnicalProblemsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError,drive});
secureCallable('technicalProblems',request=>technicalProblemsHandler(request));
const googleDriveHandler=createGoogleDriveHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError,drive});
secureCallable('googleDrive',request=>googleDriveHandler(request));
// 2026-10-05: import the old app's .xlsx export (owner only), see IMPORT_SHEET.md.
const {createSheetImportHandler}=require('./sheet_import');
const sheetImportHandler=createSheetImportHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError,driveAccess:require('./drive').driveAccess({db,drive,HttpsError:functions.https.HttpsError})});
secureCallable('importSheet',{group:'heavy'},request=>sheetImportHandler(request));
const {createOrganizationDirectory}=require('./organization_directory');
const organizationDirectory=createOrganizationDirectory({db,HttpsError:functions.https.HttpsError});
secureCallable('listMyOrganizations',{readOnly:true},request=>organizationDirectory(request));
const {createOrganizationMergeHandler}=require('./organization_merge');
const organizationMerge=createOrganizationMergeHandler({db,Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('mergeMyOrganizations',request=>organizationMerge(request));
const {createOrganizationTransferHandler}=require('./organization_transfer');
const organizationTransfer=createOrganizationTransferHandler({db,Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('transferOrganization',request=>organizationTransfer(request));
const {createOrganizationSettingsHandler}=require('./organization_settings');
// G8 release switch: new organizations are version 2 only in staging for now.
// Production: set to true once v2 has the calendar and statistics.
const V2_ORG_CREATION=process.env.GCLOUD_PROJECT==='apartment-management-staging'||require('./request_security').localEmulator();
const organizationSettingsHandler=createOrganizationSettingsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError,allowCreate:V2_ORG_CREATION});
// Copy can walk a whole organization, so it gets the long timeout.
secureCallable('organizationSettings',{readOnly:d=>['read','readCurrency'].includes(d?.action)},request=>organizationSettingsHandler(request));
const {createGovernanceHandler}=require('./governance');
const governanceHandler=createGovernanceHandler({db,Timestamp,HttpsError:functions.https.HttpsError,organizationSettings:organizationSettingsHandler});
secureCallable('ownershipAgreements',request=>governanceHandler(request));
const {createAccountDeletionHandler}=require('./account_deletion');
const accountDeletionHandler=createAccountDeletionHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
// Walks every membership of one account; long timeout like organization copy.
secureCallable('deleteMyAccount',request=>accountDeletionHandler(request));
const {createMyProfileHandler}=require('./my_profile');
const myProfileHandler=createMyProfileHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
// Personal information in Settings: name/phone, and copying a confirmed new sign-in email.
// Sign out everywhere (2026-10-06): ends every sign-in of the account.
const {createSessionsHandler}=require('./account_sessions');
const sessionsHandler=createSessionsHandler({db,getAuth:()=>require('firebase-admin/auth').getAuth(),HttpsError:functions.https.HttpsError});
secureCallable('accountSessions',request=>sessionsHandler(request));
secureCallable('myProfile',request=>myProfileHandler(request));
const {createOrganizationPurge}=require('./organization_purge');
const purgeClosedOrganizations=createOrganizationPurge({db,Timestamp:Timestamp,logger:functions.logger});
// Daily, server-only: permanently removes closed organizations after their 30-day retention.
exports.purgeClosedOrganizations = functions.scheduler.onSchedule({region:require('./region').REGION,schedule:'15 3 * * *',timeZone:'Asia/Ho_Chi_Minh',timeoutSeconds:540,memory:'512MiB',maxInstances:1,retryCount:0},async()=>{await require('./deleted_records').purgeDeletedRecords({db,Timestamp});await purgeClosedOrganizations();});
const {createPaymentHandler}=require('./payments');
const paymentHandler=createPaymentHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('mutateStandalonePayment',request=>paymentHandler(request));
// C1–C3 calendar screen: one read for every visible property (CALENDAR.md).
const {createCalendarViewHandler}=require('./calendar_view');
const calendarViewHandler=createCalendarViewHandler({db,Timestamp,HttpsError:functions.https.HttpsError});
secureCallable('calendarView',{readOnly:true},request=>calendarViewHandler(request));
const {createWorkspaceHandler}=require('./workspace');
const workspaceHandler=createWorkspaceHandler({db,HttpsError:functions.https.HttpsError});
secureCallable('readWorkspace',{readOnly:true},request=>workspaceHandler(request));
const {createTeamHandler} = require('./team');
const teamHandler = createTeamHandler({db, Timestamp: Timestamp,
  HttpsError: functions.https.HttpsError});
secureCallable('mutateTeam', request => teamHandler(request));
// R2: join every organization that pre-approved this account's verified email.
const {createClaimInvitationsHandler} = require('./team_claim');
const claimInvitationsHandler = createClaimInvitationsHandler({db, HttpsError: functions.https.HttpsError, team: teamHandler});
secureCallable('claimMyInvitations', request => claimInvitationsHandler(request));
// Organization roles (R1): list / save / delete, with grants copied to every holder.
const {createRolesHandler} = require('./roles');
const rolesHandler = createRolesHandler({db, Timestamp: Timestamp, HttpsError: functions.https.HttpsError});
secureCallable('orgRoles', request => rolesHandler(request));
const {createTeamReadHandler,createInvitationLookupHandler} = require('./team_read');
const teamReadHandler = createTeamReadHandler({db,HttpsError:functions.https.HttpsError});
secureCallable('readTeam',{readOnly:true}, request => teamReadHandler(request));
const invitationLookup = createInvitationLookupHandler({db,HttpsError:functions.https.HttpsError});
secureCallable('lookupTeamInvitation', request => invitationLookup(request));

// Get current user's memberships
secureCallable('getMyMemberships',async request => {
  const context = request;
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  }

  const snapshot = await db.collection('memberships')
    .where('ownerId', '==', context.auth.uid)
    .get();

  return snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
});

// Get all members of an organization (admin only)
secureCallable('getOrganizationMembers',async request => {
  const context = request;
  const data = request.data || {};
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  }

  const { orgId } = data;
  if (typeof orgId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(orgId)) {
    throw new functions.https.HttpsError('invalid-argument', 'orgId is required');
  }

  const organization = await db.collection('organizations').doc(orgId).get();
  if (!organization.exists || organization.data().accessVersion === 2) {
    throw new functions.https.HttpsError('permission-denied', 'Use readTeam for migrated organizations');
  }

  // Verify caller is admin
  const adminDoc = await db.collection('memberships')
    .doc(context.auth.uid + '_' + orgId)
    .get();

  if (!adminDoc.exists || adminDoc.data().role !== 'admin' ||
      adminDoc.data().status !== 'active' || adminDoc.data().ownerId !== context.auth.uid ||
      adminDoc.data().organizationId !== orgId) {
    throw new functions.https.HttpsError('permission-denied', 'Must be org admin');
  }

  const snapshot = await db.collection('memberships')
    .where('organizationId', '==', orgId)
    .get();

  return snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
});
// Authoritative calendar writes. The shared room revision makes overlap checks atomic.
const {createCalendarHandler} = require('./calendar');
const calendarBookingHandler = createCalendarHandler({
  db, Timestamp: Timestamp, FieldValue: FieldValue,
  HttpsError: functions.https.HttpsError,
});
const {createTenantHandler} = require('./calendar');
const calendarTenantHandler = createTenantHandler({
  db, Timestamp: Timestamp, FieldValue: FieldValue,
  HttpsError: functions.https.HttpsError,
});

const {createBookingWorkspaceHandler}=require('./booking_workspace');
const bookingWorkspaceHandler=createBookingWorkspaceHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError,calendar:calendarBookingHandler});
secureCallable('bookingWorkspace',{readOnly:d=>['list','read','rooms','quote'].includes(d?.action)},request=>bookingWorkspaceHandler(request));

// Second-generation callable handlers receive data and auth in one request.
secureCallable('mutateCalendarBooking',request => calendarBookingHandler(request.data, {auth: request.auth}));
secureCallable('mutateCalendarTenant',request => calendarTenantHandler(request.data, {auth: request.auth}));

// Retired features remain inert for older installed clients.
const {callableNames,retiredCallable,retiredWebhook}=require('./retired_ai');
for(const name of callableNames)secureCallable(name,retiredCallable(functions.https.HttpsError));
exports.revenueCatWebhook=functions.https.onRequest({region:require('./region').REGION,maxInstances:1},retiredWebhook);

// The grouped functions (2026-10-06, speed step 4). 'app' serves every normal
// call with a full CPU and many calls at once per copy; 'heavy' is the sheet
// import (large files, long runs). Google limits the total CPU of all running
// copies to 20 per region, so: app 5 + heavy 3 + the two below stay under it.
exports.app=callables.group('app',{maxInstances:5,timeoutSeconds:540,cpu:1,memory:'512MiB',concurrency:80,...HOT});
exports.heavy=callables.group('heavy',{maxInstances:3,timeoutSeconds:540,cpu:1,memory:'1GiB',concurrency:4});
