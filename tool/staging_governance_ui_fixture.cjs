'use strict';
// Isolated UI fixture, owned by the already signed-in staging tester.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const project='apartment-management-staging',manifest='.dart_tool/governance-ui-fixture.json';
const dep=require('node:module').createRequire(path.resolve('functions/package.json'));
async function main(){
 const base='../functions/node_modules/firebase-tools/lib/';await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const token=await require(base+'apiv2').getAccessToken();const {initializeApp,deleteApp}=dep('firebase-admin/app'),{getAuth}=dep('firebase-admin/auth'),{getFirestore,Timestamp}=dep('firebase-admin/firestore');
 const app=initializeApp({projectId:project,credential:{getAccessToken:async()=>({access_token:token,expires_in:1800})}});
 const {Firestore}=dep('@google-cloud/firestore');
 const gaxRequire=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
 const {OAuth2Client}=gaxRequire('google-auth-library');
 const authClient=new OAuth2Client();authClient.setCredentials({access_token:token,expiry_date:Date.now()+50*60000});
 const db=new Firestore({projectId:project,authClient});
 try{
  if(process.argv[2]==='utilities'){
   const m=JSON.parse(fs.readFileSync(manifest,'utf8'));
   if(!/^governance_ui_[a-f0-9]{12}$/.test(m.orgId))throw Error('Invalid fixture identity');
   const org=await db.doc('organizations/'+m.orgId).get();
   if(!org.exists||org.data().verificationFixture!=='governance-ui-v1'||org.data().createdBy!==m.uid)throw Error('Fixture marker does not match');
   const buildingId=m.orgId+'_utilities',roomId=m.orgId+'_meter',tenantId=m.orgId+'_tenant';
   if(!(await db.doc('buildings/'+buildingId).get()).exists){
    const batch=db.batch();
    batch.set(db.doc('buildings/'+buildingId),{organizationId:m.orgId,name:'Utility verification — Tòa nhà kiểm tra điện nước',currency:'VND',timeZone:'Asia/Ho_Chi_Minh'});
    batch.set(db.doc('rooms/'+roomId),{organizationId:m.orgId,buildingId,roomNumber:'1201 — Phòng gia đình hướng biển',roomType:'Family apartment',area:65,rentalMode:'monthly',currency:'VND'});
    batch.set(db.doc('tenants/'+tenantId),{organizationId:m.orgId,buildingId,roomId,isMainTenant:true,fullName:'Khách kiểm tra điện nước',currency:'VND',moveInDate:Timestamp.fromDate(new Date('2026-08-01T00:00:00Z'))});
    await batch.commit();
   }
   console.log(JSON.stringify({orgId:m.orgId,buildingId,roomId,tenantId}));return;
  }
  if(process.argv[2]==='cleanup'){
   if(!fs.existsSync(manifest))return;
   const m=JSON.parse(fs.readFileSync(manifest,'utf8'));if(!/^governance_ui_[a-f0-9]{12}$/.test(m.orgId))throw Error('Invalid fixture identity');
   const org=await db.doc('organizations/'+m.orgId).get();if(!org.exists)return;
   if(org.data().verificationFixture!=='governance-ui-v1'||org.data().createdBy!==m.uid)throw Error('Fixture marker does not match');
   for(const c of await db.listCollections()){
    for(const field of ['organizationId','orgId','sourceOrganizationId','targetOrganizationId']){
     const rows=await c.where(field,'==',m.orgId).get();for(const d of rows.docs)await db.recursiveDelete(d.ref);
    }
   }
   await org.ref.delete();console.log('Removed only the isolated governance UI fixture.');
  }else{
   if(fs.existsSync(manifest)){const saved=JSON.parse(fs.readFileSync(manifest,'utf8'));if((await db.doc('organizations/'+saved.orgId).get()).exists){console.log(JSON.stringify({orgId:saved.orgId}));return;}}
   const email=process.argv[2];if(!email?.includes('@'))throw Error('Provide the staging tester email');const user=await getAuth(app).getUserByEmail(email);
   const orgId='governance_ui_'+crypto.randomBytes(6).toString('hex'),code=crypto.randomBytes(4).toString('hex').toUpperCase();
   const batch=db.batch();batch.set(db.doc('organizations/'+orgId),{name:'Agreement UI verification',createdBy:user.uid,createdAt:Timestamp.now(),accessVersion:2,companyId:'owner_'+user.uid,inviteCode:code,verificationFixture:'governance-ui-v1'});
   batch.set(db.doc('invite_codes/'+code),{orgId});batch.set(db.doc(`memberships/${user.uid}_${orgId}`),{organizationId:orgId,ownerId:user.uid,email:user.email,displayName:'Staging tester',role:'owner',accessVersion:2,status:'active',buildingScope:'all',buildingIds:[],permissionOverrides:{}});
   await batch.commit();fs.writeFileSync(manifest,JSON.stringify({orgId,uid:user.uid},null,2));console.log(JSON.stringify({orgId}));
  }
 }finally{await db.terminate();await deleteApp(app);}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
