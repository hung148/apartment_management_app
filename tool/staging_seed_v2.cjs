'use strict';
// Synthetic version-2 organizations in STAGING for manual testing of
// organization settings, copy, close and purge. Never touches the existing
// app project. Run from the repository root:
//   node tool/staging_seed_v2.cjs create --owner you@example.com --staff other@example.com [--waiting third@example.com]
//   (--staff is a Receptionist in the source; --waiting has no role yet, like a migrated member)
//   node tool/staging_seed_v2.cjs status
//   node tool/staging_seed_v2.cjs expire   make a CLOSED test organization due for purge now
//   node tool/staging_seed_v2.cjs delete   remove everything this tool created
// Both emails must already be registered in the staging web app.
const path=require('node:path'),base='../functions/node_modules/firebase-tools/lib/';
const project='apartment-management-staging';
const dep=require('node:module').createRequire(path.resolve('functions/package.json'));
const {collectOrganization}=require(path.resolve('functions/org_data.js'));
const SOURCE='stagingSeedSource',TARGET='stagingSeedTarget',ORGS=[SOURCE,TARGET];
const arg=name=>{const i=process.argv.indexOf('--'+name);return i>0?process.argv[i+1]:null;};

async function main(){
 const action=process.argv[2];
 if(!['create','status','expire','delete'].includes(action))throw Error('Usage: node tool/staging_seed_v2.cjs create|status|expire|delete');
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const access=await require(base+'apiv2').getAccessToken();
 const {initializeApp,deleteApp}=dep('firebase-admin/app'),{getAuth}=dep('firebase-admin/auth');
 // Admin Firestore needs a certificate or ADC, so Firestore uses the CLI login
 // token directly (same approach as delete_orphan_organizations.js).
 const {Firestore,Timestamp}=dep('@google-cloud/firestore');
 // Use the auth library copy that Firestore's transport (google-gax) loads; the
 // hoisted older copy returns headers in a shape the transport cannot read.
 const gaxRequire=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
 const {OAuth2Client}=gaxRequire('google-auth-library');
 const authClient=new OAuth2Client();authClient.setCredentials({access_token:access,expiry_date:Date.now()+50*60000});
 const db=new Firestore({projectId:project,authClient});
 const app=initializeApp({projectId:project,credential:{getAccessToken:async()=>({access_token:access,expires_in:1800})}},'staging-seed');
 const auth=getAuth(app);
 if(app.options.projectId!==project)throw Error('Wrong project');
 try{
  if(action==='create'){
   // --viewer is accepted for older notes; the viewer role itself no longer exists.
   const ownerEmail=arg('owner'),staffEmail=arg('staff')??arg('viewer'),waitingEmail=arg('waiting');
   const emails=[ownerEmail,staffEmail,waitingEmail].filter(Boolean);
   if(!ownerEmail||!staffEmail||new Set(emails).size!==emails.length)throw Error('Pass different staging accounts: --owner EMAIL --staff EMAIL [--waiting EMAIL]');
   // Say which email is missing and which similar accounts staging does have.
   const find=async(email,flag)=>{
    try{return await auth.getUserByEmail(email);}catch(e){
     if(e.code!=='auth/user-not-found')throw e;
     const stem=email.toLowerCase().split('@')[0].split('+')[0],seen=[];
     let page;do{page=await auth.listUsers(1000,page?.pageToken);for(const u of page.users)if(u.email?.toLowerCase().startsWith(stem))seen.push(u.email);}while(page.pageToken&&seen.length<50);
     throw Error(`--${flag} ${email} is not registered in STAGING (${project}).\n`+
      (seen.length?`Staging accounts starting with "${stem}": ${seen.sort().join(', ')}`:`No staging accounts start with "${stem}".`)+
      `\nRegister it in the staging web app (build/staging-web), not the normal app.`);
    }
   };
   const owner=await find(ownerEmail,'owner'),staff=await find(staffEmail,'staff');
   const waiting=waitingEmail?await find(waitingEmail,'waiting'):null;
   const now=Timestamp.now(),day=86400000;
   const staffName=(await db.doc('owners/'+staff.uid).get()).data()?.name||staff.displayName||staff.email;
   const member=(user,org,role)=>[`memberships/${user.uid}_${org}`,{ownerId:user.uid,organizationId:org,accessVersion:2,role,status:'active',
    buildingScope:'all',buildingIds:[],permissionOverrides:{},displayName:user.displayName??user.email,email:user.email,joinedAt:now}];
   const docs=[
    [`organizations/${SOURCE}`,{name:'Staging Test Source',accessVersion:2,createdBy:owner.uid,createdAt:now,address:'1 Test Street',phone:'0900000000',
     email:'source@example.invalid',taxCode:'0123456789',bankName:'Test Bank',bankAccountNumber:'0123456789',bankAccountName:'STAGING TEST'}],
    [`organizations/${TARGET}`,{name:'Staging Test Target',accessVersion:2,createdBy:owner.uid,createdAt:now}],
    member(owner,SOURCE,'owner'),member(owner,TARGET,'owner'),
    // Like a real invitation: the receptionist's account is linked to a staff profile.
    [member(staff,SOURCE,'receptionist')[0],{...member(staff,SOURCE,'receptionist')[1],staffId:'stagingSeedStaff1',displayName:staffName}],
    ['staffProfiles/stagingSeedStaff1',{organizationId:SOURCE,code:'S01',displayName:staffName,email:staff.email,phone:'',color:'#2563EB',
     employmentStatus:'active',accountId:staff.uid,createdAt:now,updatedAt:now}],
    ...(waiting?[[`memberships/${waiting.uid}_${SOURCE}`,{...member(waiting,SOURCE,null)[1],role:null,status:'assignmentRequired',buildingScope:'selected'}]]:[]),
    ['buildings/stagingSeedB1',{organizationId:SOURCE,name:'Seed Tower',address:'1 Test Street',timeZone:'Asia/Ho_Chi_Minh',currency:'VND'}],
    ['rooms/stagingSeedR101',{organizationId:SOURCE,buildingId:'stagingSeedB1',roomNumber:'101',currency:'VND',roomPrice:5000000}],
    ['tenants/stagingSeedT1',{organizationId:SOURCE,buildingId:'stagingSeedB1',roomId:'stagingSeedR101',fullName:'Seed Tenant',phoneNumber:'0911111111',
     status:'active',isMainTenant:true,moveInDate:Timestamp.fromMillis(now.toMillis()-30*day),monthlyRent:5000000,currency:'VND'}],
    ['tenants/stagingSeedT2',{organizationId:SOURCE,buildingId:'stagingSeedB1',roomId:'stagingSeedR101',fullName:'Seed Roommate',phoneNumber:'0922222222',
     status:'active',isMainTenant:false,mainTenantId:'stagingSeedT1',moveInDate:Timestamp.fromMillis(now.toMillis()-30*day),currency:'VND'}],
    ['payments/stagingSeedP1',{organizationId:SOURCE,buildingId:'stagingSeedB1',roomId:'stagingSeedR101',tenantId:'stagingSeedT1',type:'rent',status:'pending',
     amount:5000000,paidAmount:0,currency:'VND',dueDate:Timestamp.fromMillis(now.toMillis()+5*day)}],
   ];
   for(const org of ORGS){const d=(await db.doc('organizations/'+org).get()).data();if(d?.closedAt)throw Error(`${org} is closed; run delete first, then create`);}
   const batch=db.batch();for(const [p,v] of docs)batch.set(db.doc(p),v);await batch.commit();
   console.log(JSON.stringify({created:ORGS,owner:owner.email,staff:staff.email,waiting:waiting?.email??null,copyTargetId:TARGET,records:{staffProfiles:1,buildings:1,rooms:1,tenants:2,payments:1}}));
  }else if(action==='status'){
   const out={};
   for(const org of ORGS){
    const d=(await db.doc('organizations/'+org).get()).data(),purged=(await db.doc('purgedOrganizations/'+org).get()).data();
    const members=(await db.collection('memberships').where('organizationId','==',org).get()).docs.map(m=>`${m.data().role}:${m.data().status}`);
    const counts={};for(const c of ['staffProfiles','buildings','rooms','tenants','payments'])counts[c]=(await db.collection(c).where('organizationId','==',org).get()).size;
    out[org]={exists:!!d,name:d?.name??null,closedAt:d?.closedAt?.toDate().toISOString()??null,purgeAfter:d?.purgeAfter?.toDate().toISOString()??null,
     members,counts,purgedAt:purged?.purgedAt?.toDate().toISOString()??null};
   }
   console.log(JSON.stringify(out,null,1));
  }else if(action==='expire'){
   const done=[];
   for(const org of ORGS){
    const ref=db.doc('organizations/'+org),d=(await ref.get()).data();
    if(!d?.closedAt)continue;
    await ref.update({purgeAfter:Timestamp.fromMillis(Date.now()-60000)});done.push(org);
   }
   if(!done.length)throw Error('No closed test organization. Close one in the app first (owner > Delete organization).');
   console.log(JSON.stringify({dueNow:done,next:'node tool/staging_release.cjs run-purge'}));
  }else{
   const counts={};
   const collections=(await db.listCollections()).map(c=>c.id).filter(c=>!['organizations','owners','purgedOrganizations'].includes(c));
   const writer=db.bulkWriter();
   for(const org of ORGS){
    const found=await collectOrganization(db,org,collections,{fields:['organizationId','orgId'],onCrossLink:doc=>{throw Error('Unexpected cross-organization record: '+doc.ref.path);}});
    for(const [c,docs] of found)for(const doc of docs.values()){await db.recursiveDelete(doc.ref,writer);counts[c]=(counts[c]??0)+1;}
    await db.recursiveDelete(db.doc('organizations/'+org),writer);
    await db.recursiveDelete(db.doc('purgedOrganizations/'+org),writer);
   }
   await writer.close();
   console.log(JSON.stringify({deleted:ORGS,counts}));
  }
 }finally{await deleteApp(app);await db.terminate();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
