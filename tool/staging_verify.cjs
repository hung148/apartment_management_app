const fs=require('node:fs'),base='../functions/node_modules/firebase-tools/lib/';
async function main(){
const project='apartment-management-staging';await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
const headers={Authorization:'Bearer '+await require(base+'apiv2').getAccessToken(),'Content-Type':'application/json','x-goog-user-project':project};
async function api(url,method='GET',body){const r=await fetch(url,{headers,method,...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)}),v=await r.json();if(!r.ok)throw Error(`${r.status} ${v.error?.message}`);return v;}
const list=await api(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/us-central1/functions?pageSize=100`);
const results=[];
for(const f of list.functions??[]){
if(f.state!=='ACTIVE'){results.push({name:f.name.split('/').at(-1),state:f.state});continue;}
const name=f.name.split('/').at(-1),expected=['aiChat','aiImportPreview'].includes(name)?'app-ai-runtime':['aiSyncSubscription','revenueCatWebhook'].includes(name)?'app-billing-runtime':'app-functions-runtime';
if(f.serviceConfig.serviceAccountEmail!==`${expected}@${project}.iam.gserviceaccount.com`)throw Error('Unexpected runtime identity: '+name);
if(!f.buildConfig.serviceAccount.endsWith(`/app-functions-build@${project}.iam.gserviceaccount.com`))throw Error('Unexpected build identity: '+name);
const service='https://run.googleapis.com/v2/'+f.serviceConfig.service;
const policy=await api(service+':getIamPolicy');policy.bindings??=[];
const invoker=policy.bindings.find(b=>b.role==='roles/run.invoker'&&!b.condition);
const scheduled=f.labels?.['deployment-scheduled']==='true';
if(scheduled){
 // Scheduled jobs are server-only: never public, invoked by their own runtime identity.
 if(invoker?.members.some(m=>m==='allUsers'||m==='allAuthenticatedUsers'))throw Error('Scheduled function is public: '+name);
 if(!invoker?.members.includes('serviceAccount:'+f.serviceConfig.serviceAccountEmail))throw Error('Scheduler identity cannot invoke: '+name);
}else if(!invoker?.members.includes('allUsers'))throw Error('Missing callable transport invoker: '+name);
// Public transport is required for Firebase callable SDKs; Auth/App Check inside
// the callable are the access boundary, not a Cloud Run IAM bearer token.
const response=await fetch(f.serviceConfig.uri,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({data:{}}),signal:AbortSignal.timeout(30000)});
const body=await response.text();
if(scheduled){results.push({name,state:f.state,runtime:expected,build:'app-functions-build',scheduled:true,unauthenticatedStatus:response.status,publicAccessDenied:response.status===403});continue;}
results.push({name,state:f.state,runtime:expected,build:'app-functions-build',unauthenticatedStatus:response.status,callableDenied:body.includes('UNAUTHENTICATED'),providerDisabled:body.includes('staging_provider_not_configured')||body.includes('Staging provider not configured')});
}
const indexes=await api(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/collectionGroups/-/indexes`);
const policy=await api(`https://cloudresourcemanager.googleapis.com/v1/projects/${project}:getIamPolicy`,'POST',{options:{requestedPolicyVersion:3}});
const customRoles=policy.bindings?.filter(b=>b.members?.some(m=>m.includes('app-functions-')||m.includes('app-ai-runtime')||m.includes('app-billing-runtime')));
fs.writeFileSync('.dart_tool/staging-verification.json',JSON.stringify({functions:results,indexes:indexes.indexes?.map(i=>({name:i.name,state:i.state})),customRoles},null,2));
console.log(JSON.stringify({functions:results.length,active:results.filter(r=>r.state==='ACTIVE').length,denied:results.filter(r=>r.callableDenied).length,indexStates:[...new Set(indexes.indexes?.map(i=>i.state))]}));
}main().catch(e=>{console.error(e.message);process.exitCode=1;});


