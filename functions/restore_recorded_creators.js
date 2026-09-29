'use strict';
// Explicitly authorized recovery of missing legacy owner memberships. No v2 switch.
const fs=require('node:fs');
const {initializeApp,getApps,deleteApp}=require('firebase-admin/app');
const {getFirestore,Timestamp,FieldValue}=require('firebase-admin/firestore');
const {Firestore}=require('@google-cloud/firestore');
const {OAuth2Client}=require('google-auth-library');
const {getGlobalDefaultAccount}=require('firebase-tools/lib/auth');
const {requireAuth}=require('firebase-tools/lib/requireAuth');
const {getAccessToken}=require('firebase-tools/lib/apiv2');
async function main(){
  const [reportPath,mode,output]=process.argv.slice(2);
  if(!reportPath||!['--check','--apply'].includes(mode)||!output)throw Error('Usage: node restore_recorded_creators.js INVENTORY --check|--apply OUTPUT');
  if(process.env.FIRESTORE_EMULATOR_HOST)throw Error('Unexpected emulator environment');
  const report=JSON.parse(fs.readFileSync(reportPath,'utf8'));
  await requireAuth({project:report.project,...getGlobalDefaultAccount()});
  const app=initializeApp({projectId:report.project,credential:{getAccessToken:async()=>({access_token:await getAccessToken(),expires_in:300})}});
  const authClient=new OAuth2Client();
  authClient.setCredentials({access_token:await getAccessToken()});
  const db=new Firestore({projectId:report.project,authClient});
  try{
    const candidates=report.organizations.filter(o=>o.issues.some(i=>i.reason==='missingActiveOwner')&&o.memberships.length===0);
    const targets=[],blocked=[];
    const accounts=new Map();
    for(const target of candidates){
      try{
        const account=await require('firebase-admin/auth').getAuth(app).getUser(target.organization.createdBy);
        if(account.disabled){blocked.push({id:target.organization.id,name:target.organization.name,reason:'creatorDisabled'});continue;}
        accounts.set(account.uid,account);targets.push(target);
      }catch(error){
        if(error.code!=='auth/user-not-found')throw error;
        blocked.push({id:target.organization.id,name:target.organization.name,reason:'creatorAccountMissing'});
      }
    }
    const result=await db.runTransaction(async tx=>{
      const checked=[];
      for(const target of targets){
        const org=await tx.get(db.doc(`organizations/${target.organization.id}`));
        if(!org.exists||org.data().createdBy!==target.organization.createdBy||(org.data().accessVersion??1)!==1)throw Error('Organization changed; create a new inventory');
        const memberships=await tx.get(db.collection('memberships').where('organizationId','==',org.id));
        if(!memberships.empty)throw Error(`Membership exists; manual review needed: ${org.id}`);
        const uid=org.data().createdBy,ref=db.doc(`memberships/${uid}_${org.id}`);
        if((await tx.get(ref)).exists)throw Error(`Membership ID conflict: ${org.id}`);
        checked.push({org,uid,ref});
      }
      const summary=checked.map(({org,uid,ref})=>({organizationId:org.id,name:org.data().name,creatorId:uid,membershipId:ref.id,previousMembership:null,role:'admin',accessVersion:1}));
      // Recovery evidence must be saved before any write. Does not include credentials.
      fs.writeFileSync(output,JSON.stringify({project:report.project,mode,checkedAt:new Date().toISOString(),records:summary,blocked},null,2));
      if(mode==='--apply')for(const {org,uid,ref} of checked){
        const account=accounts.get(uid);
        tx.create(ref,{organizationId:org.id,ownerId:uid,role:'admin',status:'active',
          displayName:account.displayName??'',email:account.email??'',joinedAt:FieldValue.serverTimestamp()});
        tx.create(db.doc(`teamActivity/restore-creator-${org.id}`),{organizationId:org.id,actorId:'administrative-recovery',action:'restoreRecordedCreator',
          targetId:ref.id,createdAt:FieldValue.serverTimestamp(),before:null,after:{role:'admin',status:'active'},
          reason:'User-authorized restoration to the organization recorded creator; access version unchanged'});
      }
      return summary;
    });
    console.log(JSON.stringify({mode,organizations:result.map(r=>({id:r.organizationId,name:r.name})),count:result.length,blocked}));
  }finally{await db.terminate();await deleteApp(app);}
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});

