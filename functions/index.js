const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

const db = admin.firestore();

// Get current user's memberships
exports.getMyMemberships = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  }

  const snapshot = await db.collection('memberships')
    .where('ownerId', '==', context.auth.uid)
    .get();

  return snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
});

// Get all members of an organization (admin only)
exports.getOrganizationMembers = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Must be logged in');
  }

  const { orgId } = data;
  if (!orgId) {
    throw new functions.https.HttpsError('invalid-argument', 'orgId is required');
  }

  // Verify caller is admin
  const adminDoc = await db.collection('memberships')
    .doc(context.auth.uid + '_' + orgId)
    .get();

  if (!adminDoc.exists || adminDoc.data().role !== 'admin') {
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
  db, Timestamp: admin.firestore.Timestamp, FieldValue: admin.firestore.FieldValue,
  HttpsError: functions.https.HttpsError,
});
const {createTenantHandler} = require('./calendar');
const calendarTenantHandler = createTenantHandler({
  db, Timestamp: admin.firestore.Timestamp, FieldValue: admin.firestore.FieldValue,
  HttpsError: functions.https.HttpsError,
});

// Second-generation callable handlers receive data and auth in one request.
exports.mutateCalendarBooking = functions.https.onCall(request => calendarBookingHandler(request.data, {auth: request.auth}));
exports.mutateCalendarTenant = functions.https.onCall(request => calendarTenantHandler(request.data, {auth: request.auth}));

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
  functions.logger.error('Gemini request error',{model,error:String(error)});
  throw new functions.https.HttpsError('unavailable','ai_unavailable');
 }
 if(!response.ok){
  let detail='';
  try{detail=(await response.text()).slice(0,1000);}catch(_){detail='unable to read provider response';}
  functions.logger.error('Gemini request failed',{status:response.status,statusText:response.statusText,model,detail});
  throw new functions.https.HttpsError('unavailable','ai_unavailable');
 }
 return response.json();
}
const ai=createAI({db,Timestamp:admin.firestore.Timestamp,HttpsError:functions.https.HttpsError,generate:generateAI});
const imports=createImport({db,Timestamp:admin.firestore.Timestamp,FieldValue:admin.firestore.FieldValue,ai,generate:generateAI});
const aiOptions={secrets:[geminiSecret],timeoutSeconds:120,memory:'512MiB',maxInstances:5};
exports.aiChat=functions.https.onCall(aiOptions,request=>ai.chat(request));
exports.aiUsage=functions.https.onCall(request=>ai.usage(request));
exports.aiImportPreview=functions.https.onCall(aiOptions,request=>imports.preview(request));
exports.aiImportCommit=functions.https.onCall({timeoutSeconds:120,maxInstances:5},request=>imports.commit(request));

const revenueCatKey=defineSecret('REVENUECAT_SECRET_KEY');
const revenueCatWebhookSecret=defineSecret('REVENUECAT_WEBHOOK_AUTH');
const {createSubscriptions}=require('./subscriptions');
const billing=createSubscriptions({db,Timestamp:admin.firestore.Timestamp,HttpsError:functions.https.HttpsError,getKey:()=>revenueCatKey.value(),getWebhookSecret:()=>revenueCatWebhookSecret.value()});
exports.aiSyncSubscription=functions.https.onCall({secrets:[revenueCatKey],maxInstances:3},request=>billing.sync(request));
exports.revenueCatWebhook=functions.https.onRequest({secrets:[revenueCatKey,revenueCatWebhookSecret],maxInstances:3},billing.webhook);
