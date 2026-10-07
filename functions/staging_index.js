'use strict';
// Isolated staging deployment entrypoint. Never package for the existing app.
const functions=require('firebase-functions');
if(process.env.GCLOUD_PROJECT!=='apartment-management-staging')throw Error('Staging project required');
functions.setGlobalOptions({serviceAccount:'app-functions-runtime@apartment-management-staging.iam.gserviceaccount.com',maxInstances:2,minInstances:0});
const app=require('./index');
Object.assign(exports,app);
