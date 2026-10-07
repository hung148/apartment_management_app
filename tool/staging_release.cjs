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
//   node tool/staging_release.cjs remove-old-region  list the functions still in us-central1
//   node tool/staging_release.cjs remove-old-region --delete  delete them and their schedule (asks nothing)
//   node tool/staging_release.cjs remove-unused  list functions here that the code no longer has
//   node tool/staging_release.cjs remove-unused --delete  delete them (asks nothing)
// Or all in one (prepare, deploy/poll until done, finish, verify):
//   node tool/staging_release.cjs all            resumes an unfinished release if there is one
//   node tool/staging_release.cjs all --replace  abandons an unfinished release and bundles the current source
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
// Region: the one the functions declare (functions/region.js, 2026-10-06: next
// to the Singapore database). OLD_REGION: where they ran before (remove-old-region).
const project='apartment-management-staging',region=require('../functions/region').REGION,OLD_REGION='us-central1';
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
 // Data files the code loads (e.g. role_templates.json since R1). Without them
 // every function crashes on start ("container failed to start").
 for(const f of [...files])for(const m of fs.readFileSync(path.join(fnDir,f),'utf8').matchAll(/require\(\s*['"]\.\/([A-Za-z0-9_.-]+\.json)['"]\s*\)/g)){
  if(!fs.existsSync(path.join(fnDir,m[1])))fail(`${f} needs ${m[1]}, which is missing`);
  if(!files.includes(m[1]))files.push(m[1]);
 }
 const pkg=JSON.parse(fs.readFileSync(path.join(fnDir,'package.json'),'utf8'));pkg.main='staging_index.js';
 // Endpoint metadata straight from the staging entrypoint (identities, memory, triggers).
 const endpoints=JSON.parse(execFileSync(process.execPath,['-e',
  "console.log(JSON.stringify(Object.fromEntries(Object.entries(require('./staging_index')).map(([n,f])=>[n,f.__endpoint]))))"],
  {cwd:fnDir,env:{...process.env,GCLOUD_PROJECT:project},encoding:'utf8'}));
 const plan={};
 const onlyArg=process.argv.find(a=>a.startsWith('--only='));
 const selected=onlyArg?new Set(onlyArg.slice(7).split(',')):null;
 if(selected)for(const name of selected)if(!endpoints[name])fail('Unknown selected endpoint: '+name);
 for(const [name,e] of Object.entries(endpoints)){
  if(selected&&!selected.has(name))continue;
  if(!e.serviceAccountEmail?.endsWith(`@${project}.iam.gserviceaccount.com`))fail('Missing explicit staging identity: '+name);
  if(e.secretEnvironmentVariables?.length)fail('Staging endpoint must not bind secrets: '+name);
  const kind=e.scheduleTrigger?'schedule':e.callableTrigger?'callable':e.httpsTrigger?'https':fail('Unsupported trigger: '+name);
  // CPU (2026-10-06, speed): passed through so staging matches production; a
  // full CPU also lets one instance serve several requests (concurrency).
  // Always sent: Google keeps the old CPU when it is left out (2026-10-06,
  // deleteMyAccount/importSheet kept a full CPU). Default = Google's CPU for
  // that memory size, which then serves one request at a time.
  const memoryMb=typeof e.availableMemoryMb==='number'?e.availableMemoryMb:256;
  const cpu=typeof e.cpu==='number'?e.cpu:({128:0.0833,256:0.1666,512:0.3333,1024:0.5833,2048:1,4096:2,8192:2})[memoryMb]??0.1666;
  plan[name]={kind,serviceAccount:e.serviceAccountEmail,memoryMb,timeoutSeconds:e.timeoutSeconds??60,
   cpu,concurrency:cpu<1?1:typeof e.concurrency==='number'?e.concurrency:80,
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
 // A new region has no image repository yet (2026-10-06): create it, as Cloud Functions would.
 if((await api(repo,'GET',null,[404])).status===404){
  await api(`https://artifactregistry.googleapis.com/v1/projects/${project}/locations/${region}/repositories?repositoryId=gcf-artifacts`,'POST',{format:'DOCKER',description:'Cloud Functions images (staging)'},[409]);
  for(let i=0;(await api(repo,'GET',null,[404])).status===404;i++){if(i>=20)fail('Image repository not ready yet; run deploy again');await new Promise(r=>setTimeout(r,5000));}
 }
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
    ...(e.cpu?{availableCpu:String(e.cpu),maxInstanceRequestConcurrency:e.concurrency}:{}),
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

// One command for a whole backend release. Starts 3 deployments at a time (as the
// manual steps do), polls every 20 s, retries a failed function up to 2 times,
// then runs finish and staging_verify. Safe to stop and run again: it resumes.
async function all(){
 let resume=false;
 if(fs.existsSync(currentPath)&&!process.argv.includes('--replace')){
  const {j}=loadJournal();resume=!j.finishedAt&&Object.keys(j.operations).length>0;
 }
 if(resume)console.log(JSON.stringify({resuming:loadJournal().j.id}));else await prepare();
 const retries={},started=Date.now();
 for(;;){
  const {j}=loadJournal(),names=Object.keys(j.endpoints),ops=j.operations;
  const failed=names.filter(n=>ops[n]?.error),running=names.filter(n=>ops[n]&&!ops[n].done).length,notStarted=names.filter(n=>!ops[n]).length;
  if(!running&&!notStarted&&!failed.length)break;
  if(!running){
   for(const n of failed){
    retries[n]=(retries[n]??0)+1;
    if(retries[n]>2)fail(`${n} failed 3 times: ${ops[n].error.message??JSON.stringify(ops[n].error)}`);
   }
   await deploy();
  }
  if(Date.now()-started>90*60000)fail('Still deploying after 90 minutes. Run the same command again to resume.');
  await new Promise(r=>setTimeout(r,20000));
  await poll();
 }
 await finish();
 execFileSync(process.execPath,[path.join('tool','staging_verify.cjs')],{stdio:'inherit'});
}

// After moving region (2026-10-06): the functions left in the old region keep
// running (and the purge schedule keeps firing) until removed. Lists them;
// --delete removes them and the old schedule. Only run --delete when Tom says so.
async function removeOldRegion(){
 const api=await session(),old=`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/${OLD_REGION}`;
 if(OLD_REGION===region)fail('The functions already run in '+region);
 const list=(await api(old+'/functions?pageSize=200')).data.functions??[];
 const names=list.map(f=>f.name.split('/').pop());
 if(!process.argv.includes('--delete')){console.log(JSON.stringify({region:OLD_REGION,functions:names,next:names.length?'node tool/staging_release.cjs remove-old-region --delete':'nothing to remove'}));return;}
 const job=`https://cloudscheduler.googleapis.com/v1/projects/${project}/locations/${OLD_REGION}/jobs/firebase-schedule-purgeClosedOrganizations-${OLD_REGION}`;
 await api(job,'DELETE',null,[404]);
 const removed=[];
 for(const name of names){await api(old+'/functions/'+name,'DELETE',null,[404]);removed.push(name);}
 console.log(JSON.stringify({removedFrom:OLD_REGION,functions:removed.length,schedule:'removed',note:'deletions finish in the background (a few minutes)'}));
}

// After grouping (2026-10-06, speed step 4): the 43 one-call functions are no
// longer in the code but keep existing (and count toward the region's CPU
// limit) until removed. Lists the functions in this region that the last
// finished release does not have; --delete removes them. Only when Tom says so.
async function removeUnused(){
 const {j}=loadJournal();
 if(!j.finishedAt)fail(`Release ${j.id} is not finished; finish it first so the new functions are in place.`);
 const keep=new Set(Object.keys(j.endpoints)),api=await session();
 const list=(await api(fnRoot+'/functions?pageSize=200')).data.functions??[];
 const names=list.map(f=>f.name.split('/').pop()).filter(n=>!keep.has(n));
 if(!process.argv.includes('--delete')){console.log(JSON.stringify({region,keep:[...keep],unused:names,next:names.length?'node tool/staging_release.cjs remove-unused --delete':'nothing to remove'}));return;}
 const removed=[];
 for(const name of names){await api(fnRoot+'/functions/'+name,'DELETE',null,[404]);removed.push(name);}
 console.log(JSON.stringify({region,removed:removed.length,kept:[...keep],note:'deletions finish in the background (a few minutes)'}));
}

const steps={prepare,deploy,poll,finish,all,'run-purge':runPurge,'remove-old-region':removeOldRegion,'remove-unused':removeUnused};
const step=steps[process.argv[2]];
if(!step){console.error('Usage: node tool/staging_release.cjs prepare|deploy|poll|finish|all|run-purge|remove-old-region|remove-unused');process.exitCode=1;}
else step().catch(e=>{console.error(e.message);process.exitCode=1;});
