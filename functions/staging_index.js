'use strict';
// Isolated staging deployment entrypoint. Never package for the existing app.
const functions=require('firebase-functions');
if(process.env.GCLOUD_PROJECT!=='apartment-management-staging')throw Error('Staging project required');
functions.setGlobalOptions({serviceAccount:'app-functions-runtime@apartment-management-staging.iam.gserviceaccount.com',maxInstances:2,minInstances:0});
const app=require('./index');
for(const [name,handler] of Object.entries(app)){
 if(['aiChat','aiImportPreview','aiSyncSubscription','revenueCatWebhook'].includes(name))continue;
 exports[name]=handler;
}
const unavailable=()=>{throw new functions.https.HttpsError('failed-precondition','staging_provider_not_configured');};
exports.aiChat=functions.https.onCall({enforceAppCheck:true,serviceAccount:'app-ai-runtime@apartment-management-staging.iam.gserviceaccount.com'},unavailable);
exports.aiImportPreview=functions.https.onCall({enforceAppCheck:true,serviceAccount:'app-ai-runtime@apartment-management-staging.iam.gserviceaccount.com'},unavailable);
exports.aiSyncSubscription=functions.https.onCall({enforceAppCheck:true,serviceAccount:'app-billing-runtime@apartment-management-staging.iam.gserviceaccount.com'},unavailable);
exports.revenueCatWebhook=functions.https.onRequest({serviceAccount:'app-billing-runtime@apartment-management-staging.iam.gserviceaccount.com'},(_req,res)=>res.status(503).send('Staging provider not configured'));
