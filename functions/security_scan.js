'use strict';
// Heuristic scan: report only category, location and object ID, never matched text.
// Does not establish that arbitrary/custom secrets or remote artifacts are clean.
const fs=require('node:fs'),path=require('node:path'),{execFileSync}=require('node:child_process');
const root=path.resolve(__dirname,'..');
const git=(args)=>execFileSync('git',args,{cwd:root,maxBuffer:256*1024*1024});
const patterns=[
 ['private-key',/-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----/],
 ['google-server-key',/"type"\s*:\s*"service_account"[\s\S]{0,2000}"private_key"\s*:/],
 ['github-token',/\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{60,})\b/],
 ['google-oauth-client-secret',/\bGOCSPX-[A-Za-z0-9_-]{20,}\b/],
 ['aws-access-key',/\b(?:AKIA|ASIA)[A-Z0-9]{16}\b/],
 ['stripe-secret',/\bsk_live_[A-Za-z0-9]{20,}\b/],
 ['revenuecat-secret',/\bsk_[A-Za-z0-9]{32,}\b/],
 ['embedded-provider-secret',/(?:GEMINI_API_KEY|geminiApiKey|REVENUECAT_SECRET_KEY)\s*[:=]\s*['"][A-Za-z0-9_-]{20,}['"]/],
];
const findings=[],skipped=[];let blobs=0,files=0,artifacts=0;
function scan(bytes,location,objectId){
 if(bytes.length>20*1024*1024){skipped.push({location,reason:'over_20MiB'});return;}
 const text=bytes.toString('utf8');
 for(const [kind,pattern] of patterns)if(pattern.test(text))findings.push({kind,location,...(objectId?{objectId}:{})});
}
for(const file of git(['ls-files','--cached','--others','--exclude-standard','-z']).toString().split('\0').filter(Boolean)){
 const name=path.join(root,file);if(fs.existsSync(name)&&fs.statSync(name).isFile()){files++;scan(fs.readFileSync(name),file);}
}
const objects=git(['rev-list','--objects','--all']).toString().trim().split('\n').filter(Boolean);
const batch=execFileSync('git',['cat-file','--batch'],{cwd:root,input:objects.map(x=>x.split(' ')[0]).join('\n')+'\n',maxBuffer:512*1024*1024});
let offset=0;
for(const entry of objects){
 const newline=batch.indexOf(10,offset),header=batch.subarray(offset,newline).toString().split(' '),size=Number(header[2]);
 if(!Number.isFinite(size))throw Error('Unexpected git object response');
 offset=newline+1;
 if(header[1]==='blob'){blobs++;scan(batch.subarray(offset,offset+size),entry.slice(entry.indexOf(' ')+1),header[0]);}
 offset+=size+1;
}
function walk(dir){if(!fs.existsSync(dir))return;for(const item of fs.readdirSync(dir,{withFileTypes:true})){
 const file=path.join(dir,item.name);if(item.isDirectory())walk(file);else if(item.isFile()){artifacts++;scan(fs.readFileSync(file),path.relative(root,file));}
}}
walk(path.join(root,'build/web'));
console.log(JSON.stringify({scope:'working tree, reachable Git history, existing build/web',files,blobs,artifacts,findings,skipped},null,2));
process.exitCode=findings.length?1:0;
