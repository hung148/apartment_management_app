'use strict';
// Narrow administrative cleanup authorized for the five inventoried orphans.
// Planning backs up typed Firestore document values; apply checks update times.
const fs=require('node:fs');
const {Firestore}=require('@google-cloud/firestore');
const {OAuth2Client}=require('google-auth-library');
const {getGlobalDefaultAccount}=require('firebase-tools/lib/auth');
const {requireAuth}=require('firebase-tools/lib/requireAuth');
const {getAccessToken,Client}=require('firebase-tools/lib/apiv2');
const allowed=['AuUfqlIpHobznCVAzmBu','JjZ8f2dKujZ9yXiG2BRZ','KN7oHOhrCsnUK6qWHqos','VsHkVmENTGsKaD1CrSTk','gUFubM109vKetqhnAuC7'];
async function main(){
  const [mode,file]=process.argv.slice(2),project='apartment-management-app-776b9';
  if(!['--plan','--apply','--verify'].includes(mode)||!file||process.env.FIRESTORE_EMULATOR_HOST)throw Error('Expected --plan|--apply|--verify BACKUP.json and production environment');
  await requireAuth({project,...getGlobalDefaultAccount()});
  const authClient=new OAuth2Client();authClient.setCredentials({access_token:await getAccessToken()});
  const db=new Firestore({projectId:project,authClient});
  const rest=new Client({urlPrefix:'https://firestore.googleapis.com',apiVersion:'v1'});
  const base=`projects/${project}/databases/(default)/documents`;
  try{
    if(mode==='--plan'){
      const paths=new Set(),organizations=[];
      const collections=await db.listCollections();
      async function include(doc){
        if(paths.has(doc.ref.path))return;
        paths.add(doc.ref.path);
        for(const collection of await doc.ref.listCollections())for(const child of (await collection.get()).docs)await include(child);
      }
      for(const id of allowed){
        const org=await db.doc(`organizations/${id}`).get();
        if(!org.exists)throw Error(`Organization missing: ${id}`);
        if(!(await db.collection('memberships').where('organizationId','==',id).get()).empty)throw Error(`Membership now exists: ${id}`);
        organizations.push({id,name:org.data().name});await include(org);
        for(const collection of collections){
          if(['owners','organizations'].includes(collection.id))continue;
          for(const field of ['organizationId','orgId'])for(const doc of (await collection.where(field,'==',id).get()).docs)await include(doc);
        }
      }
      // Include old linked records without organizationId, but never another org.
      for(const [parent,child,field] of [['buildings','rooms','buildingId'],['rooms','tenants','roomId'],['rooms','bookings','roomId'],['rooms','payments','roomId'],['tenants','payments','tenantId']]){
        for(const p of [...paths].filter(p=>p.startsWith(parent+'/')&&p.split('/').length===2)){
          for(const doc of (await db.collection(child).where(field,'==',p.split('/')[1]).get()).docs){
            if(doc.data().organizationId&&!allowed.includes(doc.data().organizationId))throw Error(`Cross-organization link: ${doc.ref.path}`);
            await include(doc);
          }
        }
      }
      const documents=[];
      for(const p of [...paths].sort())documents.push((await rest.get(`/${base}/${p}`)).body);
      const counts={};for(const p of paths)counts[p.split('/')[0]]=(counts[p.split('/')[0]]??0)+1;
      fs.writeFileSync(file,JSON.stringify({project,createdAt:new Date().toISOString(),organizations,counts,documents},null,2),{flag:'wx'});
      console.log(JSON.stringify({organizations,counts,total:documents.length,backup:file}));
    }else{
      const backup=JSON.parse(fs.readFileSync(file,'utf8'));
      if(backup.project!==project||backup.organizations.length!==5||backup.organizations.some(o=>!allowed.includes(o.id))||backup.documents.length>450)throw Error('Invalid or oversized backup');
      if(mode==='--verify'){
        const refs=backup.documents.map(document=>{
          if(!document.name.startsWith(base+'/'))throw Error('Wrong project');
          return db.doc(document.name.slice(base.length+1));
        });
        const remaining=(await db.getAll(...refs)).filter(d=>d.exists);
        if(remaining.length)throw Error(`${remaining.length} backed-up documents still exist`);
        console.log(JSON.stringify({verifiedAbsent:refs.length}));return;
      }
      const collections=await db.listCollections();
      const known=new Set(backup.documents.map(d=>d.name));
      await db.runTransaction(async tx=>{
        for(const id of allowed){
          const members=await tx.get(db.collection('memberships').where('organizationId','==',id));
          if(!members.empty)throw Error('Membership added since planning');
          for(const collection of collections){
            if(['owners','organizations'].includes(collection.id))continue;
            for(const field of ['organizationId','orgId']){
              const records=await tx.get(collection.where(field,'==',id));
              if(records.docs.some(d=>!known.has(`${base}/${d.ref.path}`)))throw Error('Records added since backup; re-plan');
            }
          }
        }
        const refs=[];
        for(const document of backup.documents){
          if(!document.name.startsWith(base+'/'))throw Error('Wrong project');
          const ref=db.doc(document.name.slice(base.length+1));
          const current=await tx.get(ref);
          const nanos=Number((document.updateTime.match(/\.(\d+)Z$/)?.[1]??'').padEnd(9,'0'));
          if(!current.exists||current.updateTime.seconds!==Math.floor(Date.parse(document.updateTime)/1000)||current.updateTime.nanoseconds!==nanos)throw Error('Data changed since backup; re-plan');
          refs.push(ref);
        }
        for(const ref of refs)tx.delete(ref);
      });
      console.log(JSON.stringify({deleted:backup.documents.length,organizations:backup.organizations,backup:file}));
    }
  }finally{await db.terminate();}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
