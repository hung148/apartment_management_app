const fs=require('node:fs'),base='../functions/node_modules/firebase-tools/lib/';
const project='apartment-management-staging',region=require('../functions/region').REGION,number='933030543017';
async function main(){
await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
const headers={Authorization:'Bearer '+await require(base+'apiv2').getAccessToken(),'Content-Type':'application/json','x-goog-user-project':project};
async function api(url,method='GET',body,allowed=[]){const r=await fetch(url,{headers,method,...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(30000)}),v=await r.json();if(!r.ok&&!allowed.includes(r.status))throw Error(`${method} ${new URL(url).pathname}: ${r.status} ${v.error?.message}`);return {status:r.status,data:v};}
const root=`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/${region}`;
const statePath='.dart_tool/staging-deployment.json';
const state=fs.existsSync(statePath)?JSON.parse(fs.readFileSync(statePath)):{operations:{}};
if(process.argv.includes('--poll')){
 for(const [name,op] of Object.entries(state.operations)){if(op.done)continue;const result=(await api('https://cloudfunctions.googleapis.com/v2/'+op.name)).data;if(result.done){op.done=true;op.error=result.error;op.service=result.response?.serviceConfig?.service;op.uri=result.response?.serviceConfig?.uri;}}
 fs.writeFileSync(statePath,JSON.stringify(state,null,2));console.log(JSON.stringify(state.operations));return;
}
const build=`serviceAccount:app-functions-build@${project}.iam.gserviceaccount.com`;
async function bind(getUrl,setUrl,role,member,bucket=false){
 const policy=(await api(getUrl,'GET')).data;
 policy.bindings??=[];let binding=policy.bindings.find(b=>b.role===role&&!b.condition);if(!binding){binding={role,members:[]};policy.bindings.push(binding);}if(binding.members.includes(member))return;binding.members.push(member);
 await api(setUrl,bucket?'PUT':'POST',bucket?policy:{policy});
}
const repo=`https://artifactregistry.googleapis.com/v1/projects/${project}/locations/${region}/repositories/gcf-artifacts`;
await bind(repo+':getIamPolicy',repo+':setIamPolicy','roles/artifactregistry.writer',build);
if(!state.source){
 const upload=(await api(root+'/functions:generateUploadUrl','POST',{})).data;
 const bytes=fs.readFileSync('.dart_tool/staging-functions.zip');
 const put=await fetch(upload.uploadUrl,{method:'PUT',headers:{'Content-Type':'application/zip'},body:bytes,signal:AbortSignal.timeout(60000)});if(!put.ok)throw Error(`Upload ${put.status}`);
 state.source=upload.storageSource;fs.writeFileSync(statePath,JSON.stringify(state,null,2));
}
const buckets=(await api(`https://storage.googleapis.com/storage/v1/b?project=${project}`)).data.items??[];
for(const b of buckets.filter(b=>b.name.startsWith('gcf-v2-'))){const url=`https://storage.googleapis.com/storage/v1/b/${b.name}/iam`;await bind(url,url,'roles/storage.objectViewer',build,true);}
const endpoints=JSON.parse(fs.readFileSync('.dart_tool/staging-endpoints.json'));
let started=0;
for(const [name,e] of Object.entries(endpoints)){
 if(state.operations[name]&&!state.operations[name].error)continue;
 if(started>=3)break;
 const account='app-functions-runtime';
 const body={name:`projects/${project}/locations/${region}/functions/${name}`,buildConfig:{runtime:'nodejs22',entryPoint:name,serviceAccount:`projects/${project}/serviceAccounts/app-functions-build@${project}.iam.gserviceaccount.com`,source:{storageSource:state.source},environmentVariables:{GOOGLE_NODE_RUN_SCRIPTS:''}},serviceConfig:{serviceAccountEmail:`${account}@${project}.iam.gserviceaccount.com`,availableMemory:e.availableMemoryMb===512?'512Mi':'256Mi',timeoutSeconds:e.timeoutSeconds??60,maxInstanceCount:2,minInstanceCount:0,environmentVariables:{GCLOUD_PROJECT:project,FUNCTION_REGION:region}},labels:{environment:'staging','deployment-tool':'restricted-rest'}};
 const existing=await api(root+'/functions/'+name,'GET',null,[404]); const result=existing.status===404?await api(root+'/functions?functionId='+name,'POST',body):await api(root+'/functions/'+name+'?updateMask=buildConfig,serviceConfig,labels','PATCH',body);state.operations[name]={name:result.data.name};started++;fs.writeFileSync(statePath,JSON.stringify(state,null,2));
}
console.log(JSON.stringify({started,total:Object.keys(state.operations).length}));
}main().catch(e=>{console.error(e.message);process.exitCode=1;});


