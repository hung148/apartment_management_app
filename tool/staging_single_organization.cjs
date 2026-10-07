'use strict';
// STAGING ONLY. Plans by default. --apply merges every organization of the
// explicit owner into one; this tool offers no deletion and no production mode.
const path=require('node:path');
const dep=require('node:module').createRequire(path.resolve('functions/package.json'));
const {createOrganizationMergeHandler}=require('../functions/organization_merge');
const arg=k=>{const i=process.argv.indexOf(k);return i<0?null:process.argv[i+1];};
async function main(){
 const uid=arg('--owner-id'),name=arg('--name');
 if(!uid||!name)throw Error('--owner-id and --name required');
 if(process.env.FIRESTORE_EMULATOR_HOST)throw Error('Staging tool cannot use emulator environment');
 const project='apartment-management-staging',base='../functions/node_modules/firebase-tools/lib/';
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const access=await require(base+'apiv2').getAccessToken();
 const gax=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
 const {OAuth2Client}=gax('google-auth-library'),authClient=new OAuth2Client();authClient.setCredentials({access_token:access,expiry_date:Date.now()+50*60000});
 const {Firestore,Timestamp}=dep('@google-cloud/firestore'),db=new Firestore({projectId:project,authClient});
 class E extends Error{constructor(code,message){super(message);this.code=code;}}
 try{
  const preview=await createOrganizationMergeHandler({db,Timestamp,HttpsError:E})({auth:{uid},data:{action:'preview'}});
  const ids=preview.organizations.map(o=>o.id);
  const result=await createOrganizationMergeHandler({db,Timestamp,HttpsError:E,dryRun:!process.argv.includes('--apply')})({auth:{uid},data:{action:'merge',organizationIds:ids,mergeIds:ids,name,operationId:'single-organization-staging-'+uid,confirmDelete:false}});
  console.log(JSON.stringify({project,...result},null,2));
 }finally{await db.terminate();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
