'use strict';
// Compatibility endpoints for installed older clients. No provider, database,
// purchase SDK or secret is loaded; repeated requests cannot spend or write.
const callableNames=Object.freeze(['aiChat','aiUsage','aiImportPreview','aiImportCommit','aiSyncSubscription']);
function retiredCallable(HttpsError){return ()=>{throw new HttpsError('failed-precondition','feature_retired');};}
function retiredWebhook(_request,response){return response.status(410).json({error:'feature_retired'});}
module.exports={callableNames,retiredCallable,retiredWebhook};
