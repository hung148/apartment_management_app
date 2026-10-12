'use strict';
// Scale test data in STAGING only (2026-10-10, Tom): one made-up organization
// with many properties, rooms, tenants, bookings, payments, cleaning tasks and
// staff, to measure how the app behaves when an organization grows. Every name,
// phone and amount is invented; nothing comes from real clients.
// Run from the repository root:
//   node tool/staging_scale_seed.cjs create --owner you+scale@example.com [--buildings 100]
//   node tool/staging_scale_seed.cjs status
//   node tool/staging_scale_seed.cjs delete     remove everything this tool created
// The owner must be a staging account that owns no other organization (one
// business per account). Register it in the staging web app first.
// Size per property: 6 rooms, 2 tenants with 6 paid months each, 20 short-stay
// bookings over about a year, 10 finished cleanings. Plus 100 staff.
// With 100 properties that is about 5,300 documents (free plan: 20,000 writes a day).
const path=require('node:path'),base='../functions/node_modules/firebase-tools/lib/';
const project='apartment-management-staging';
const dep=require('node:module').createRequire(path.resolve('functions/package.json'));
const {collectOrganization}=require(path.resolve('functions/org_data.js'));
const ORG='scaleTest100',NAME='Scale test – 100 tòa',STAFF=100;
const arg=name=>{const i=process.argv.indexOf('--'+name);return i>0?process.argv[i+1]:null;};
const pad=(n,w=3)=>String(n).padStart(w,'0');

async function main(){
 const action=process.argv[2];
 if(!['create','status','delete'].includes(action))throw Error('Usage: node tool/staging_scale_seed.cjs create --owner EMAIL [--buildings 100] | status | delete');
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const access=await require(base+'apiv2').getAccessToken();
 const {initializeApp,deleteApp}=dep('firebase-admin/app'),{getAuth}=dep('firebase-admin/auth');
 // Same connection as staging_seed_v2.cjs: the CLI login token, staging only.
 const {Firestore,Timestamp}=dep('@google-cloud/firestore');
 const gaxRequire=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
 const {OAuth2Client}=gaxRequire('google-auth-library');
 const authClient=new OAuth2Client();authClient.setCredentials({access_token:access,expiry_date:Date.now()+50*60000});
 const db=new Firestore({projectId:project,authClient});
 const app=initializeApp({projectId:project,credential:{getAccessToken:async()=>({access_token:access,expires_in:1800})}},'staging-scale-seed');
 if(app.options.projectId!==project)throw Error('Wrong project');
 try{
  if(action==='create'){
   const ownerEmail=arg('owner'),buildings=Number(arg('buildings')??100);
   if(!ownerEmail)throw Error('Pass --owner EMAIL (a staging account that owns no organization yet)');
   if(!Number.isInteger(buildings)||buildings<1||buildings>200)throw Error('--buildings must be 1..200');
   let owner;
   try{owner=await getAuth(app).getUserByEmail(ownerEmail);}catch(e){
    if(e.code==='auth/user-not-found')throw Error(`${ownerEmail} is not registered in STAGING. Register it in the staging web app first.`);
    throw e;
   }
   const owned=await db.collection('memberships').where('ownerId','==',owner.uid).get();
   const other=owned.docs.filter(d=>d.data().organizationId!==ORG&&d.data().status!=='revoked');
   if(other.length)throw Error(`${ownerEmail} already belongs to another organization (${other.map(d=>d.data().organizationId).join(', ')}). Use an account with none.`);
   if((await db.doc('organizations/'+ORG).get()).exists)throw Error(`${ORG} already exists; run delete first, then create`);

   const now=Timestamp.now(),nowMs=now.toMillis(),day=86400000,hour=3600000;
   const at=v=>Timestamp.fromMillis(v);
   // "YYYY-MM-DD" and "YYYY-MM-DD HH:MM" in Vietnam time (UTC+7).
   const vn=v=>new Date(v+7*hour).toISOString();
   const date=v=>vn(v).slice(0,10),stamp=v=>vn(v).slice(0,16).replace('T',' ');
   const docs=[];
   const add=(p,v)=>docs.push([p,v]);
   add(`organizations/${ORG}`,{name:NAME,accessVersion:2,createdBy:owner.uid,createdAt:now,address:'Địa chỉ thử nghiệm',phone:'0900000000'});
   add(`memberships/${owner.uid}_${ORG}`,{ownerId:owner.uid,organizationId:ORG,accessVersion:2,role:'owner',status:'active',
    buildingScope:'all',buildingIds:[],permissionOverrides:{},displayName:owner.displayName??owner.email,email:owner.email,joinedAt:now});
   // Staff: made-up accounts (no sign-in) with profiles and memberships.
   for(let s=1;s<=STAFF;s++){
    const id=`scaleS${pad(s)}`,uid=`scaleU${pad(s)}`,name=`Nhân viên ${pad(s)}`,email=`staff${pad(s)}@scale.example.invalid`;
    add(`staffProfiles/${id}`,{organizationId:ORG,code:`S${pad(s)}`,displayName:name,email,phone:'',color:'#2563EB',employmentStatus:'active',accountId:uid,createdAt:now,updatedAt:now});
    add(`memberships/${uid}_${ORG}`,{ownerId:uid,organizationId:ORG,accessVersion:2,role:s%10===0?'manager':s%3===0?'housekeeper':'receptionist',status:'active',
     buildingScope:'all',buildingIds:[],permissionOverrides:{},displayName:name,email,staffId:id,joinedAt:now});
   }
   for(let b=1;b<=buildings;b++){
    const B=`scaleB${pad(b)}`;
    add(`buildings/${B}`,{organizationId:ORG,name:`Tòa ${pad(b)}`,address:`${b} Đường Thử`,timeZone:'Asia/Ho_Chi_Minh',currency:'VND'});
    const rooms=[];
    for(let r=1;r<=6;r++){
     const R=`${B}R${pad(r,2)}`;rooms.push(R);
     add(`rooms/${R}`,{organizationId:ORG,buildingId:B,roomNumber:`${100+r}`,currency:'VND',roomPrice:5000000,
      rentalMode:'both',hourlyPrice:100000,dailyPrice:500000,overnightPrice:400000});
    }
    // Two monthly tenants (rooms 1 and 2), six paid months each.
    for(let t=1;t<=2;t++){
     const T=`${B}T${t}`,moveIn=nowMs-180*day;
     add(`tenants/${T}`,{organizationId:ORG,buildingId:B,roomId:rooms[t-1],fullName:`Khách thuê ${pad(b)}-${t}`,phoneNumber:'0911111111',
      status:'active',isMainTenant:true,moveInDate:at(moveIn),occupancyStartDate:at(moveIn),monthlyRent:5000000,currency:'VND',paymentPeriodMonths:1,
      staffInChargeId:`scaleS${pad((b%STAFF)+1)}`});
     for(let m=0;m<6;m++){
      const start=moveIn+m*30*day,end=start+30*day;
      add(`payments/${T}P${m+1}`,{organizationId:ORG,buildingId:B,roomId:rooms[t-1],tenantId:T,type:'rent',invoiceKind:'tenantRent',status:'paid',
       amount:5000000,paidAmount:5000000,currency:'VND',billingStartLocalDate:date(start),billingEndLocalDate:date(end),dueDate:at(start),createdAt:at(start)});
     }
    }
    // Twenty short stays over the last ~300 days and the next ~20 (rooms 3-6).
    for(let k=0;k<20;k++){
     const start=nowMs-300*day+k*16*day+((b*7+k*5)%24)*hour,end=start+(1+(k%3))*day;
     const past=end<nowMs;
     add(`bookings/${B}K${pad(k+1,2)}`,{organizationId:ORG,buildingId:B,roomId:rooms[2+(k%4)],guestName:`Khách ngắn ngày ${pad(b)}-${k+1}`,guestPhone:'',
      startTime:at(start),endTime:at(end),status:past?'checkedOut':'confirmed',...(past?{checkedOutAt:at(end)}:{}),
      totalPrice:500000*(1+(k%3)),paidAmount:past?500000*(1+(k%3)):0,currency:'VND',numberOfGuests:2,createdAt:at(start-2*day)});
    }
    // Ten finished cleanings.
    for(let c=0;c<10;c++){
     const start=nowMs-280*day+c*28*day,end=start+hour;
     add(`housekeepingTasks/${B}C${pad(c+1,2)}`,{organizationId:ORG,buildingId:B,roomId:rooms[2+(c%4)],status:'completed',title:'Dọn phòng',
      assigneeId:`scaleU${pad(((b+c)%STAFF)+1)}`,plannedStart:stamp(start),plannedEnd:stamp(end),startedAt:at(start),completedAt:at(end),createdAt:at(start-day)});
    }
   }
   const writer=db.bulkWriter();
   for(const [p,v] of docs)writer.set(db.doc(p),v);
   await writer.close();
   const counts={};for(const [p] of docs){const c=p.split('/')[0];counts[c]=(counts[c]??0)+1;}
   console.log(JSON.stringify({created:ORG,name:NAME,owner:owner.email,documents:docs.length,counts}));
  }else if(action==='status'){
   const d=(await db.doc('organizations/'+ORG).get()).data(),counts={};
   for(const c of ['memberships','staffProfiles','buildings','rooms','tenants','payments','bookings','housekeepingTasks'])
    counts[c]=(await db.collection(c).where('organizationId','==',ORG).count().get()).data().count;
   console.log(JSON.stringify({exists:!!d,name:d?.name??null,counts},null,1));
  }else{
   const counts={};
   const collections=(await db.listCollections()).map(c=>c.id).filter(c=>!['organizations','owners','purgedOrganizations'].includes(c));
   console.log('Finding the records…');
   const found=await collectOrganization(db,ORG,collections,{fields:['organizationId','orgId'],onCrossLink:doc=>{throw Error('Unexpected cross-organization record: '+doc.ref.path);}});
   const docs=[];for(const [c,list] of found)for(const doc of list.values())docs.push([c,doc]);
   console.log(`Deleting ${docs.length} records…`);
   // Fast (2026-10-12, Tom: "the delete command is stucking"): one
   // recursiveDelete per record waited for a round trip to Singapore each
   // time (about 30 minutes for 5,300 records). Now 32 at a time: a record
   // with subcollections (none from this tool) gets them deleted first, then
   // every record goes into one bulk delete. Safe to stop and run again.
   const writer=db.bulkWriter();
   let next=0,done=0;
   await Promise.all(Array.from({length:32},async()=>{
    while(next<docs.length){
     const [c,doc]=docs[next++];
     for(const sub of await doc.ref.listCollections())await db.recursiveDelete(sub);
     writer.delete(doc.ref);
     counts[c]=(counts[c]??0)+1;
     if(++done%500===0)console.log(`  ${done} / ${docs.length}`);
    }
   }));
   await writer.close();
   await db.recursiveDelete(db.doc('organizations/'+ORG));
   console.log(JSON.stringify({deleted:ORG,counts}));
  }
 }finally{await deleteApp(app);await db.terminate();}
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
