const functions = require('firebase-functions');
const {initializeApp,getApps,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp,FieldValue}=require('firebase-admin/firestore');
initializeApp();

const db = getFirestore();
const {createSecureCallable}=require('./request_security');
const secureCallable=createSecureCallable({onCall:functions.https.onCall,db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
const {createPropertyLayoutHandler}=require('./property_layout');
const propertyLayoutHandler=createPropertyLayoutHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.propertyLayout = secureCallable('propertyLayout',{maxInstances:5},request=>propertyLayoutHandler(request));
const {createInvoiceHandler}=require('./invoices');
const invoiceHandler=createInvoiceHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.invoices = secureCallable('invoices',{maxInstances:5},request=>invoiceHandler(request));
const {createLeaseLifecycleHandler}=require('./lease_lifecycle');
const leaseLifecycleHandler=createLeaseLifecycleHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.leaseLifecycle = secureCallable('leaseLifecycle',{maxInstances:5},request=>leaseLifecycleHandler(request));
const {createTenantRentHandler}=require('./tenant_rent');
const tenantRentHandler=createTenantRentHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.tenantRent = secureCallable('tenantRent',{maxInstances:5},request=>tenantRentHandler(request));
const {createTenantRoommatesHandler}=require('./tenant_roommates');
const tenantRoommatesHandler=createTenantRoommatesHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.tenantRoommates = secureCallable('tenantRoommates',{maxInstances:5},request=>tenantRoommatesHandler(request));
const {createTenantLeasesHandler}=require('./tenant_leases');
const tenantLeasesHandler=createTenantLeasesHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.tenantLeases = secureCallable('tenantLeases',{maxInstances:5},request=>tenantLeasesHandler(request));
const {createTenantContactsHandler}=require('./tenant_contacts');
const tenantContactsHandler=createTenantContactsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.tenantContacts = secureCallable('tenantContacts',{maxInstances:5},request=>tenantContactsHandler(request));
const {createPropertyContractHandler}=require('./property_contract');
const propertyContractHandler=createPropertyContractHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.propertyContract = secureCallable('propertyContract',{maxInstances:5},request=>propertyContractHandler(request));
const {createBookingSettingsHandler}=require('./booking_settings');
const bookingSettingsHandler=createBookingSettingsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.roomBookingSettings = secureCallable('roomBookingSettings',{maxInstances:5},request=>bookingSettingsHandler(request));
const {createRoomRatesHandler}=require('./room_rates');
const roomRatesHandler=createRoomRatesHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.roomRates = secureCallable('roomRates',{maxInstances:5},request=>roomRatesHandler(request));
const {createRoomDetailsHandler}=require('./room_details');
const roomDetailsHandler=createRoomDetailsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.roomDetails = secureCallable('roomDetails',{maxInstances:5},request=>roomDetailsHandler(request));
const {createPropertyDetailsHandler}=require('./property_details');
const propertyDetailsHandler=createPropertyDetailsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.propertyDetails = secureCallable('propertyDetails',{maxInstances:5},request=>propertyDetailsHandler(request));
const {createHousekeepingHandler}=require('./housekeeping');
const housekeepingHandler=createHousekeepingHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.mutateHousekeepingTask = secureCallable('mutateHousekeepingTask',{maxInstances:5},request=>housekeepingHandler(request));
const {createOrganizationDirectory}=require('./organization_directory');
const organizationDirectory=createOrganizationDirectory({db,HttpsError:functions.https.HttpsError});
exports.listMyOrganizations = secureCallable('listMyOrganizations',{maxInstances:5},request=>organizationDirectory(request));
const {createOrganizationSettingsHandler}=require('./organization_settings');
const organizationSettingsHandler=createOrganizationSettingsHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
// Copy can walk a whole organization, so it gets the long timeout.
exports.organizationSettings = secureCallable('organizationSettings',{maxInstances:5,timeoutSeconds:540,memory:'512MiB'},request=>organizationSettingsHandler(request));
const {createAccountDeletionHandler}=require('./account_deletion');
const accountDeletionHandler=createAccountDeletionHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
// Walks every membership of one account; long timeout like organization copy.
exports.deleteMyAccount = secureCallable('deleteMyAccount',{maxInstances:3,timeoutSeconds:540,memory:'512MiB'},request=>accountDeletionHandler(request));
const {createMyProfileHandler}=require('./my_profile');
const myProfileHandler=createMyProfileHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
// Personal information in Settings: name/phone, and copying a confirmed new sign-in email.
exports.myProfile = secureCallable('myProfile',{maxInstances:3},request=>myProfileHandler(request));
const {createOrganizationPurge}=require('./organization_purge');
const purgeClosedOrganizations=createOrganizationPurge({db,Timestamp:Timestamp,logger:functions.logger});
// Daily, server-only: permanently removes closed organizations after their 30-day retention.
exports.purgeClosedOrganizations = functions.scheduler.onSchedule({schedule:'15 3 * * *',timeZone:'Asia/Ho_Chi_Minh',timeoutSeconds:540,memory:'512MiB',maxInstances:1,retryCount:0},async()=>{await purgeClosedOrganizations();});
const {createPaymentHandler}=require('./payments');
const paymentHandler=createPaymentHandler({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError});
exports.mutateStandalonePayment = secureCallable('mutateStandalonePayment',{maxInstances:5},request=>paymentHandler(request));
const {createWorkspaceHandler}=require('./workspace');
const workspaceHandler=createWorkspaceHandler({db,HttpsError:functions.https.HttpsError});
exports.readWorkspace = secureCallable('readWorkspace',{maxInstances:5},request=>workspaceHandler(request));
const {createTeamHandler} = require('./team');
const teamHandler = createTeamHandler({db, Timestamp: Timestamp,
  HttpsError: functions.https.HttpsError});
exports.mutateTeam = secureCallable('mutateTeam',{maxInstances:5}, request => teamHandler(request));
const {createTeamReadHandler,createInvitationLookupHandler} = require('./team_read');
const teamReadHandler = createTeamReadHandler({db,HttpsError:functions.https.HttpsError});
exports.readTeam = secureCallable('readTeam',{maxInstances:5}, request => teamReadHandler(request));
const invitationLookup = createInvitationLookupHandler({db,HttpsError:functions.https.HttpsError});
exports.lookupTeamInvitation = secureCallable('lookupTeamInvitation',{maxInstances:5}, request => invitationLookup(request));

// Get current user's memberships
exports.getMyMemberships = secureCallable('getMyMemberships',async request => {
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
exports.getOrganizationMembers = secureCallable('getOrganizationMembers',async request => {
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
exports.bookingWorkspace = secureCallable('bookingWorkspace',{maxInstances:5},request=>bookingWorkspaceHandler(request));

// Second-generation callable handlers receive data and auth in one request.
exports.mutateCalendarBooking = secureCallable('mutateCalendarBooking',request => calendarBookingHandler(request.data, {auth: request.auth}));
exports.mutateCalendarTenant = secureCallable('mutateCalendarTenant',request => calendarTenantHandler(request.data, {auth: request.auth}));

const {defineSecret}=require('firebase-functions/params');
const geminiSecret=defineSecret('GEMINI_API_KEY');
const {createAI}=require('./ai');
const {createImport}=require('./ai_import');
async function generateAI(body) {
 const key=geminiSecret.value();
 if(!key)throw new functions.https.HttpsError('failed-precondition','ai_not_configured');
 const model=process.env.AI_MODEL||'gemini-2.5-flash';
 let response;
 try{
  response=await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,{
   method:'POST',headers:{'Content-Type':'application/json','x-goog-api-key':key},body:JSON.stringify(body),signal:AbortSignal.timeout(25000),
  });
 }catch(error){
  functions.logger.error('Gemini request error',{model});
  throw new functions.https.HttpsError('unavailable','ai_unavailable');
 }
 if(!response.ok){
  functions.logger.error('Gemini request failed',{status:response.status,model});
  throw new functions.https.HttpsError('unavailable','ai_unavailable');
 }
 return response.json();
}
const ai=createAI({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError,generate:generateAI});
const imports=createImport({db,Timestamp:Timestamp,FieldValue:FieldValue,ai,generate:generateAI});
const aiOptions={secrets:[geminiSecret],timeoutSeconds:120,memory:'512MiB',maxInstances:5};
exports.aiChat = secureCallable('aiChat',aiOptions,request=>ai.chat(request));
exports.aiUsage = secureCallable('aiUsage',request=>ai.usage(request));
exports.aiImportPreview = secureCallable('aiImportPreview',aiOptions,request=>imports.preview(request));
exports.aiImportCommit = secureCallable('aiImportCommit',{timeoutSeconds:120,maxInstances:5},request=>imports.commit(request));

const revenueCatKey=defineSecret('REVENUECAT_SECRET_KEY');
const revenueCatWebhookSecret=defineSecret('REVENUECAT_WEBHOOK_AUTH');
const {createSubscriptions}=require('./subscriptions');
const billing=createSubscriptions({db,Timestamp:Timestamp,HttpsError:functions.https.HttpsError,getKey:()=>revenueCatKey.value(),getWebhookSecret:()=>revenueCatWebhookSecret.value()});
exports.aiSyncSubscription = secureCallable('aiSyncSubscription',{secrets:[revenueCatKey],maxInstances:3},request=>billing.sync(request));
exports.revenueCatWebhook=functions.https.onRequest({secrets:[revenueCatKey,revenueCatWebhookSecret],maxInstances:3},billing.webhook);
