'use strict';
const fs=require('node:fs');
// Send public package names and locked versions only, never repository content.
async function main(){
 const lock=fs.readFileSync(require('node:path').join(__dirname,'../pubspec.lock'),'utf8');
 const packages=[];
 for(const block of lock.split(/^  (?=[A-Za-z0-9_]+:)/m).slice(1)){
  const name=block.match(/^([A-Za-z0-9_]+):/)?.[1],version=block.match(/\n    version: "([^"]+)"/)?.[1];
  if(name&&version&&block.includes('source: hosted'))packages.push({package:{name,ecosystem:'Pub'},version});
 }
 const response=await fetch('https://api.osv.dev/v1/querybatch',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({queries:packages}),signal:AbortSignal.timeout(60000)});
 if(!response.ok)throw Error(`OSV returned ${response.status}`);
 const body=await response.json();if(body.results?.length!==packages.length)throw Error('Incomplete OSV response');
 const findings=body.results.flatMap((r,i)=>(r.vulns??[]).map(v=>({package:packages[i].package.name,version:packages[i].version,id:v.id})));
 console.log(JSON.stringify({source:'https://api.osv.dev',checked:packages.length,findings},null,2));
 process.exitCode=findings.length?1:0;
}
main().catch(e=>{console.error(e.message);process.exitCode=2;});
