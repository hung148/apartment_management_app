'use strict';

// Read-only migration inventory. Uses the existing Firebase CLI login without
// exporting credentials. Outputs access metadata only, never tenant/payment data.
const fs=require('node:fs');
const path=require('node:path');
const {getGlobalDefaultAccount}=require('firebase-tools/lib/auth');
const {requireAuth}=require('firebase-tools/lib/requireAuth');
const {Client}=require('firebase-tools/lib/apiv2');
const {migrationProposal}=require('./team_access');
const decode=value=>{
  if(value.stringValue!==undefined)return value.stringValue;
  if(value.integerValue!==undefined)return Number(value.integerValue);
  if(value.booleanValue!==undefined)return value.booleanValue;
  if(value.nullValue!==undefined)return null;
  if(value.arrayValue)return (value.arrayValue.values??[]).map(decode);
  if(value.mapValue)return Object.fromEntries(Object.entries(value.mapValue.fields??{}).map(([k,v])=>[k,decode(v)]));
  if(value.timestampValue)return value.timestampValue;
  return null;
};
async function main(){
  const [project,output]=process.argv.slice(2);
  if(!project||!output||!/^[a-z0-9-]+$/.test(project))throw Error('Usage: node team_inventory.js PROJECT OUTPUT.json');
  const account=getGlobalDefaultAccount();
  await requireAuth({project,...account});
  const client=new Client({urlPrefix:'https://firestore.googleapis.com',apiVersion:'v1'});
  async function list(collection,fields){
    const documents=[];let pageToken;
    do{
      const queryParams=new URLSearchParams({pageSize:'300'});
      for(const field of fields)queryParams.append('mask.fieldPaths',field);
      if(pageToken)queryParams.append('pageToken',pageToken);
      const response=await client.get(`/projects/${project}/databases/(default)/documents/${collection}`,
        {queryParams});
      for(const doc of response.body.documents??[]){
        documents.push({id:doc.name.split('/').at(-1),...Object.fromEntries(Object.entries(doc.fields??{}).map(([k,v])=>[k,decode(v)]))});
      }
      pageToken=response.body.nextPageToken;
    }while(pageToken);
    return documents;
  }
  const organizations=await list('organizations',['name','createdBy','accessVersion']);
  const memberships=await list('memberships',['organizationId','ownerId','role','status','accessVersion','buildingScope','buildingIds','permissionOverrides','staffId']);
  const buildings=await list('buildings',['organizationId']);
  const staff=await list('staffProfiles',['organizationId','accountId','employmentStatus']);
  const report={project,generatedAt:new Date().toISOString(),readOnly:true,
    warning:'Review inventory only, not a backup, snapshot, approved manifest or migration. Concurrent changes may occur during reads.',
    organizations:organizations.map(org=>({organization:org,
      ...migrationProposal(org,memberships.filter(m=>m.organizationId===org.id)),
      memberships:memberships.filter(m=>m.organizationId===org.id),
      buildingIds:buildings.filter(b=>b.organizationId===org.id).map(b=>b.id),
      staff:staff.filter(s=>s.organizationId===org.id)})),
    orphanMemberships:memberships.filter(m=>!organizations.some(o=>o.id===m.organizationId))};
  fs.mkdirSync(path.dirname(path.resolve(output)),{recursive:true});
  fs.writeFileSync(output,JSON.stringify(report,null,2),{flag:'wx'});
  console.log(JSON.stringify({organizations:organizations.length,memberships:memberships.length,
    alreadyV2:organizations.filter(o=>o.accessVersion===2).length,
    organizationsWithIssues:report.organizations.filter(o=>o.issues.length).length,
    unassignedLegacy:report.organizations.flatMap(o=>o.proposals).filter(p=>p.proposed?.status==='assignmentRequired').length,
    output:path.resolve(output)}));
}
if(require.main===module)main().catch(error=>{console.error(error.message);process.exitCode=1;});
