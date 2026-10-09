// How long each staging function takes ON THE SERVER (2026-10-06, speed step 5).
// Read-only: reads Cloud Run request logs and each function's CPU/memory.
// Run: node tool/function_times.cjs [minutes=60]
// The time measured in the browser minus this = network + sign-in checks.
const base='../functions/node_modules/firebase-tools/lib/';
const project='apartment-management-staging';
const {REGION}=require('../functions/region');
async function main(){
 const minutes=Number(process.argv[2]??60);
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const headers={Authorization:'Bearer '+await require(base+'apiv2').getAccessToken(),'x-goog-user-project':project,'Content-Type':'application/json'};
 const call=async(url,body)=>{const r=await fetch(url,{method:body?'POST':'GET',headers,body:body&&JSON.stringify(body),signal:AbortSignal.timeout(60000)});const v=await r.json();if(!r.ok)throw Error(`${r.status} ${v.error?.message}`);return v;};
 const fns=await call(`https://cloudfunctions.googleapis.com/v2/projects/${project}/locations/${REGION}/functions?pageSize=200`);
 const size={};
 for(const f of fns.functions??[]){const s=f.serviceConfig??{};size[f.name.split('/').pop().toLowerCase()]={memory:s.availableMemory,cpu:s.availableCpu,minInstances:s.minInstanceCount??0,maxInstances:s.maxInstanceCount,concurrency:s.maxInstanceRequestConcurrency};}
 const database=await call(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)`);
 console.log(JSON.stringify({databaseLocation:database.locationId,project,functionsRegion:REGION}));
 const since=new Date(Date.now()-minutes*60000).toISOString();
 const filter=`resource.type="cloud_run_revision" AND resource.labels.location="${REGION}" AND log_name="projects/${project}/logs/run.googleapis.com%2Frequests" AND timestamp>="${since}"`;
 const times={};let pageToken,pages=0;
 do{
  const r=await call('https://logging.googleapis.com/v2/entries:list',{resourceNames:[`projects/${project}`],filter,orderBy:'timestamp asc',pageSize:1000,pageToken});
  for(const e of r.entries??[]){
   const name=e.resource?.labels?.service_name,lat=parseFloat(e.httpRequest?.latency??'');
   if(!name||!Number.isFinite(lat))continue;
   (times[name]??=[]).push({ms:Math.round(lat*1000),at:e.timestamp.slice(11,19),status:e.httpRequest?.status,method:e.httpRequest?.requestMethod});
  }
  pageToken=r.nextPageToken;
 }while(pageToken&&++pages<10);
 for(const [name,list] of Object.entries(times).sort()){
  const work=list.filter(x=>x.method!=='OPTIONS');
  const ms=work.map(x=>x.ms).sort((a,b)=>a-b);
  if(!ms.length)continue;
  console.log(JSON.stringify({fn:name,...size[name],calls:ms.length,preflights:list.length-work.length,p95:ms[Math.ceil(ms.length*.95)-1],fastest:ms[0],middle:ms[Math.floor(ms.length/2)],slowest:ms.at(-1),last:work.slice(-6).map(x=>`${x.at} ${x.ms}ms ${x.status}`)}));
 }
 if(!Object.keys(times).length)console.log(JSON.stringify({note:'no requests in the last '+minutes+' minutes'}));
 // Google's limit on the CPU of all running copies in this region (the staging
 // deploy of 2026-10-06 stopped on it).
 try{
  const q=await call(`https://serviceusage.googleapis.com/v1beta1/projects/${project}/services/run.googleapis.com/consumerQuotaMetrics?view=FULL`);
  for(const m of q.metrics??[]){
   if(!/cpu/i.test(m.metric+' '+m.displayName))continue;
   for(const l of m.consumerQuotaLimits??[])for(const b of l.quotaBuckets??[]){
    const where=b.dimensions?.region;
    if(where&&where!==REGION)continue;
    console.log(JSON.stringify({quota:m.displayName,unit:l.unit,region:where??'all',limit:b.effectiveLimit}));
   }
  }
 }catch(e){console.log(JSON.stringify({quota:'unreadable',error:e.message}));}
}
main().catch(e=>{console.log(JSON.stringify({error:e.message}));process.exitCode=1;});
