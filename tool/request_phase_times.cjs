// Read-only, staging-only aggregate timings. No request contents or identity data.
// node tool/request_phase_times.cjs [minutes=60]
const base='../functions/node_modules/firebase-tools/lib/';
const project='apartment-management-staging';
async function main(){
 const minutes=Number(process.argv[2]??60);
 if(!Number.isFinite(minutes)||minutes<1||minutes>10080)throw Error('Minutes must be 1..10080');
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const token=await require(base+'apiv2').getAccessToken();
 const since=new Date(Date.now()-minutes*60000).toISOString(),groups=new Map();
 let pageToken,pages=0;
 do{
  const response=await fetch('https://logging.googleapis.com/v2/entries:list',{
   method:'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},
   signal:AbortSignal.timeout(30000),
   body:JSON.stringify({resourceNames:[`projects/${project}`],
    filter:`resource.type="cloud_run_revision" AND jsonPayload.event="app_request_timing" AND timestamp>="${since}"`,
    orderBy:'timestamp desc',pageSize:1000,pageToken}),
  });
  const data=await response.json();
  if(!response.ok)throw Error(`${response.status}: ${data.error?.message??'Log query failed'}`);
  for(const entry of data.entries??[]){
   const p=entry.jsonPayload;
   if(!/^[A-Za-z][A-Za-z0-9]{0,63}$/.test(p?.fn??''))continue;
   if(!groups.has(p.fn))groups.set(p.fn,[]);
   groups.get(p.fn).push(p);
  }
  pageToken=data.nextPageToken;
 }while(pageToken&&++pages<10);
 const stats=(rows,key)=>{
  const values=rows.map(r=>r[key]).filter(v=>typeof v==='number'&&Number.isFinite(v)&&v>=0).sort((a,b)=>a-b);
  return values.length?{medianMs:values[Math.floor(values.length/2)],p95Ms:values[Math.ceil(values.length*.95)-1],maxMs:values.at(-1)}:null;
 };
 for(const [fn,rows] of [...groups].sort())console.log(JSON.stringify({fn,calls:rows.length,
  errors:rows.filter(r=>r.outcome!=='ok').length,total:stats(rows,'totalMs'),guard:stats(rows,'guardMs'),handler:stats(rows,'handlerMs')}));
 if(!groups.size)console.log('No phase timings yet. Deploy the instrumented app function and exercise the affected pages.');
 if(pageToken)console.log('Limited to the newest 10,000 entries; shorten the time range.');
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
