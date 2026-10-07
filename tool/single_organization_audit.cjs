'use strict';
// READ ONLY. Usage: node tool/single_organization_audit.cjs --project PROJECT
// Add --output PATH to save the restricted UID/organization report locally.
const path=require('node:path'),fs=require('node:fs');
const dep=require('node:module').createRequire(path.resolve('functions/package.json'));
const {auditSingleOrganization}=require('../functions/single_organization_audit');
async function main(){
 const args=process.argv.slice(2),project=args[args.indexOf('--project')+1],output=args.includes('--output')?args[args.indexOf('--output')+1]:null;
 if(!args.includes('--project')||!['demo-canho360','apartment-management-staging','apartment-management-app-776b9'].includes(project))throw Error('Explicit supported --project required');
 const {Firestore}=dep('@google-cloud/firestore');let db;
 if(project.startsWith('demo-')){
  if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Demo audit requires FIRESTORE_EMULATOR_HOST');
  db=new Firestore({projectId:project});
 }else{
  if(process.env.FIRESTORE_EMULATOR_HOST)throw Error('Remove emulator environment before a cloud audit');
  const base='../functions/node_modules/firebase-tools/lib/';
  await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
  const access=await require(base+'apiv2').getAccessToken();
  const gax=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
  const {OAuth2Client}=gax('google-auth-library'),authClient=new OAuth2Client();authClient.setCredentials({access_token:access,expiry_date:Date.now()+50*60000});
  db=new Firestore({projectId:project,authClient});
 }
 try{const report={project,...await auditSingleOrganization(db)};if(output)fs.writeFileSync(output,JSON.stringify(report,null,2));console.log(JSON.stringify(output?{project,...report.totals,reportPath:path.resolve(output)}:report,null,2));}finally{await db.terminate();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
