'use strict';
// Fresh STAGING backend release using the restricted build/runtime accounts.
// The Firebase CLI cannot set the build account, so this uses the Cloud
// Functions REST API. It never touches the existing app project.
// Run from the repository root, in this order:
//   node tool/staging_release.cjs prepare    bundle the current source + new journal
//   node tool/staging_release.cjs deploy     start up to 3 deployments (repeat until all started)
//   node tool/staging_release.cjs poll       check running deployments (repeat until all done)
//   node tool/staging_release.cjs finish     invoker access + daily purge schedule
//   node tool/staging_release.cjs run-purge  run the purge schedule once, now
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const project='apartment-management-staging',region='us-central1';
const fnDir=path.resolve('functions'),dep=require('node:module').createRequire(path.join(fnDir,'package.json'));
const base=path.join(fnDir,'node_modules/firebase-tools/lib/');
const root='.dart_tool/staging-release',currentPath=path.join(root,'current.json');
const build=`app-functions-build@${project}.iam.gserviceaccount.com`;
const fail=m=>{throw Error(m);};

function loadJournal(){
 if(!fs.existsSync(currentPath))fail('No release prepared. Run: node tool/staging_release.cjs prepare');
 const {id}=JSON.parse(fs.readFileSync(currentPath,'utf8')),file=path.join(root,id,'journal.json');
 return {file,dir:path.join(root,id),j:JSON.parse(fs.readFileSync(file,'utf8'))};
}
const save=(file,j)=>fs.writeFileSync(file,JSON.stringify(j,null,2));

async function prepare(){
 if(fs.existsSync(currentPath)){
  const {j}=loadJournal();
  const open=Object.values(j.operations).filter(o=>!o.done||o.error).length;
  if(!j.finishedAt&&(open||Object.keys(j.operations).length)&&!process.argv.includes('--replace'))
   fail(`Release ${j.id} is not finished. Finish it, or pass --replace to abandon it (its journal is kept).`);
 }
 const ignore=JSON.parse(fs.readFileSync('firebase.json','utf8')).functions[0].ignore;
 const files=fs.readdirSync(fnDir).filter(f=>f.endsWith('.js')&&!ignore.includes(f)).sort();
 files.push('staging_index.js');
 const pkg=JSON.parse(fs.readFileSync(path.join(fnDir,'package.json'),'utf8'));pkg.main='staging_index.js';
 // Endpoint metadata straight from the staging entrypoint (identities, memory, triggers).
 const endpoints=JSON.parse(execFileSync(process.execPath,['-e',
  "console.log(JSON.stringify(Object.fromEntries(Object.entries(require('./staging_index')).map(([n,f])=>[n,f.__endpoint]))))"],
  {cwd:fnDir,env:{...process.env,GCLOUD_PROJECT:project},encoding:'utf8'}));
 const plan={};
 for(const [name,e] of Object.entries(endpoints)){
  if(!e.serviceAccountEmail?.endsWith(`@${project}.iam.gserviceaccount.com`))fail('Missing explicit staging identity: '+name);
  if(e.secretEnvironmentVariables?.length)fail('Staging endpoint must not bind secrets: '+name);
  const kind=e.scheduleTrigger?'schedule':e.callableTrigger?'callable':e.httpsTrigger?'https':fail('Unsupported trigger: '+name);
  plan[name]={kind,serviceAccount:e.serviceAccountEmail,memoryMb:e.availableMemoryMb??256,timeoutSeconds:e.timeoutSeconds??60,
   maxInstances:Math.min(e.maxInstances??2,2),...(kind==='schedule'?{schedule:e.scheduleTrigger.schedule,timeZone:e.scheduleTrigger.timeZone??'UTC'}:{})};
 }
 const id=new Date().toISOString().replace(/[:.]/g,'-').toLowerCase(),dir=path.join(root,id);
 fs.mkdirSync(dir,{recursive:true});
 const archiver=dep('archiver'),zipPath=path.join(dir,'source.zip');
 await new Promise((resolve,reject)=>{
  const out=fs.createWriteStream(zipPath),zip=archiver('zip',{zlib:{level:9}});
  out.on('close',resolve);zip.on('error',reject);zip.pipe(out);
  for(const f of new Set(files))zip.append(fs.readFileSync(path.join(fnDir,f)),{name:f});
  zip.append(JSON.stringify(pkg,null,2),{name:'package.json'});
  zip.append(fs.readFileSync(path.join(fnDir,'package-lock.json')),{name:'package-lock.json'});
  zip.finalize();
 });
 let commit=null;try{commit=execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8',stdio:['ignore','pipe','ignore']}).trim();}catch{}
 const j={id,createdAt:new Date().toISOString(),gitCommit:commit,note:'Working tree may contain uncommitted changes; the hash identifies the exact bundle.',
  sourceSha256:crypto.createHash('sha256').update(fs.readFileSync(zipPath)).digest('hex'),files:[...new Set(files)],endpoints:plan,source:null,operations:{}};
 save(path.join(dir,'journal.json'),j);fs.writeFileSync(currentPath,JSON.stringify({id}));
 console.log(JSON.stringify({prepared:id,functions:Object.keys(plan).length,scheduled:Object.entries(plan).filter(([,p])=>p.kind==='schedule').map(([n])=>n),sha256:j.sourceSha256}));
}

async function session(){
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const headers={Authorization:'Bearer '+await require(base+'apiv2').getAccessToken(),'Content-Type':'application/json','x-goog-user-project':project};
 return async function api(url,method='GET',body,allowed=[]){
  const r=await fetch(url,{headers,method,...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(60000)});
  const text=await r.text();let v={};try{v=JSON.parse(text);}catch{}
  if(!r.ok&&!allowed.includes(r.status))fail(`${method} ${new URL(url).pathname}: ${r.status} ${v.error?.message??''}`);
  return {status:r.status,data:v};
 };
}
// Adds one member to one role, preserving every other binding.
async function bind(api,getUrl,setUrl,role,member,bucket=false){
 const policy=(await api(getUrl,'GET')).data;
 policy.bindings??=[];let b=policy.bindings.find(x=>x.role===role&&!x.condition);
 if(!b){b={role,members:[]};policy.bindings.push(b);}
 if(b.members.includes(member))return false;
 b.members.push(member);await api(setUrl,bucket?'PUT':'POST',bucket?policy:{policy});return true;
}
const fnRoot=`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/${region}`;

async function deploy(){
 const {file,dir,j}=loadJournal(),api=await session();
 const sha=crypto.createHash('sha256').update(fs.readFileSync(path.join(dir,'source.zip'))).digest('hex');
 if(sha!==j.sourceSha256)fail('source.zip changed after prepare; run prepare again');
 const repo=`https://artifactregistry.googleapis.com/v1/projects/${project}/locations/${region}/repositories/gcf-artifacts`;
 await bind(api,repo+':getIamPolicy',repo+':setIamPolicy','roles/artifactregistry.writer','serviceAccount:'+build);
 if(!j.source){
  const upload=(await api(fnRoot+'/functions:generateUploadUrl','POST',{})).data;
  const put=await fetch(upload.uploadUrl,{method:'PUT',headers:{'Content-Type':'application/zip'},body:fs.readFileSync(path.join(dir,'source.zip')),signal:AbortSignal.timeout(120000)});
  if(!put.ok)fail('Upload '+put.status);
  j.source=upload.storageSource;save(file,j);
 }
 const buckets=(await api(`https://storage.googleapis.com/storage/v1/b?project=${project}`)).data.items??[];
 for(const b of buckets.filter(b=>b.name.startsWith('gcf-v2-'))){const url=`https://storage.googleapis.com/storage/v1/b/${b.name}/iam`;await bind(api,url,url,'roles/storage.objectViewer','serviceAccount:'+build,true);}
 let started=0;
 for(const [name,e] of Object.entries(j.endpoints)){
  const op=j.operations[name];
  if(op&&!op.error)continue;
  if(started>=3)break;
  const body={name:`projects/${project}/locations/${region}/functions/${name}`,
   buildConfig:{runtime:'nodejs22',entryPoint:name,serviceAccount:`projects/${project}/serviceAccounts/${build}`,source:{storageSource:j.source},environmentVariables:{GOOGLE_NODE_RUN_SCRIPTS:''}},
   serviceConfig:{serviceAccountEmail:e.serviceAccount,availableMemory:`${e.memoryMb}Mi`,timeoutSeconds:e.timeoutSeconds,maxInstanceCount:e.maxInstances,minInstanceCount:0,
    environmentVariables:{GCLOUD_PROJECT:project,FUNCTION_REGION:region}},
   labels:{environment:'staging','deployment-tool':'restricted-rest',release:j.id.slice(0,63),...(e.kind==='schedule'?{'deployment-scheduled':'true'}:{})}};
  const existing=await api(fnRoot+'/functions/'+name,'GET',null,[404]);
  const result=existing.status===404?await api(fnRoot+'/functions?functionId='+name,'POST',body)
   :await api(fnRoot+'/functions/'+name+'?updateMask=buildConfig,serviceConfig,labels','PATCH',body);
  j.operations[name]={name:result.data.name,startedAt:new Date().toISOString()};started++;save(file,j);
 }
 const ops=Object.values(j.operations);
 console.log(JSON.stringify({started,startedTotal:ops.length,functions:Object.keys(j.endpoints).length,next:ops.length<Object.keys(j.endpoints).length?'poll, then deploy again':'poll until all done, then finish'}));
}

async function poll(){
 const {file,j}=loadJournal(),api=await session();
 for(const op of Object.values(j.operations)){
  if(op.done&&!op.error)continue;
  const r=(await api('https://cloudfunctions.googleapis.com/v2/'+op.name)).data;
  if(r.done){op.done=true;op.error=r.error??null;op.uri=r.response?.serviceConfig?.uri??null;op.service=r.response?.serviceConfig?.service??null;}
 }
 save(file,j);
 const ops=Object.entries(j.operations);
 console.log(JSON.stringify({done:ops.filter(([,o])=>o.done&&!o.error).length,running:ops.filter(([,o])=>!o.done).length,
  failed:ops.filter(([,o])=>o.error).map(([n,o])=>({name:n,error:o.error.message??o.error})),notStarted:Object.keys(j.endpoints).length-ops.length}));
}

async function finish(){
 const {file,j}=loadJournal(),api=await session();
 const names=Object.keys(j.endpoints);
 const pending=names.filter(n=>!j.operations[n]?.done||j.operations[n].error);
 if(pending.length)fail('Not all deployments succeeded yet: '+pending.join(', '));
 const summary={public:0,private:[],schedules:[]};
 for(const name of names){
  const e=j.endpoints[name],f=(await api(fnRoot+'/functions/'+name)).data;
  const service='https://run.googleapis.com/v2/'+f.serviceConfig.service;
  const policy=(await api(service+':getIamPolicy')).data;policy.bindings??=[];
  let invoker=policy.bindings.find(b=>b.role==='roles/run.invoker'&&!b.condition);
  if(!invoker){invoker={role:'roles/run.invoker',members:[]};policy.bindings.push(invoker);}
  if(e.kind==='schedule'){
   // Server-only: only its own runtime identity (used by Cloud Scheduler) may call it.
   const member='serviceAccount:'+e.serviceAccount;
   invoker.members=invoker.members.filter(m=>m!=='allUsers'&&m!=='allAuthenticatedUsers');
   if(!invoker.members.includes(member))invoker.members.push(member);
   await api(service+':setIamPolicy','POST',{policy});
   await api(`https://serviceusage.googleapis.com/v1/projects/${project}/services/cloudscheduler.googleapis.com:enable`,'POST',{});
   const jobName=`projects/${project}/locations/${region}/jobs/firebase-schedule-${name}-${region}`;
   const url='https://cloudscheduler.googleapis.com/v1/'+jobName;
   // A newly enabled API can take a few minutes to become usable.
   let existing;
   for(let attempt=1;;attempt++){
    existing=await api(url,'GET',null,[403,404]);
    if(existing.status!==403)break;
    if(attempt>=10)fail('Cloud Scheduler API is still not ready; wait a few minutes and run finish again');
    console.log(JSON.stringify({waitingForCloudSchedulerApi:attempt}));
    await new Promise(r=>setTimeout(r,30000));
   }
   const job={name:jobName,schedule:e.schedule,timeZone:e.timeZone,attemptDeadline:`${Math.min(e.timeoutSeconds+60,1800)}s`,retryConfig:{retryCount:0},
    httpTarget:{uri:f.serviceConfig.uri,httpMethod:'POST',headers:{'Content-Type':'application/json'},body:Buffer.from('{}').toString('base64'),
     oidcToken:{serviceAccountEmail:e.serviceAccount,audience:f.serviceConfig.uri}}};
   if(existing.status===404)await api(`https://cloudscheduler.googleapis.com/v1/projects/${project}/locations/${region}/jobs`,'POST',job);
   else await api(url+'?updateMask=schedule,timeZone,attemptDeadline,retryConfig,httpTarget','PATCH',job);
   summary.private.push(name);summary.schedules.push({name,schedule:e.schedule,timeZone:e.timeZone});
  }else{
   // Firebase callable SDKs need public transport; Auth/App Check inside are the boundary.
   if(!invoker.members.includes('allUsers')){invoker.members.push('allUsers');await api(service+':setIamPolicy','POST',{policy});}
   summary.public++;
  }
 }
 j.finishedAt=new Date().toISOString();save(file,j);
 console.log(JSON.stringify({finished:j.id,...summary,next:'node tool/staging_verify.cjs'}));
}

async function runPurge(){
 const api=await session();
 const job=`https://cloudscheduler.googleapis.com/v1/projects/${project}/locations/${region}/jobs/firebase-schedule-purgeClosedOrganizations-${region}`;
 await api(job+':run','POST',{});
 console.log(JSON.stringify({triggered:'purgeClosedOrganizations',next:'wait ~1 minute, then node tool/staging_seed_v2.cjs status'}));
}

const steps={prepare,deploy,poll,finish,'run-purge':runPurge};
const step=steps[process.argv[2]];
if(!step){console.error('Usage: node tool/staging_release.cjs prepare|deploy|poll|finish|run-purge');process.exitCode=1;}
else step().catch(e=>{console.error(e.message);process.exitCode=1;});
