'use strict';
const {createHash}=require('node:crypto');
const {allows,roles}=require('./team_access');
const {serialize}=require('./team_read');
const {collectOrganization}=require('./org_data');

// Organization settings for version-2 organizations. Legacy organizations keep
// their existing rules-based dialogs until migration.
const LIMITS=Object.freeze({name:120,address:300,phone:40,email:254,taxCode:40,bankName:120,bankAccountNumber:40,bankAccountName:120});
const PRIVATE=Object.freeze(['taxCode','bankName','bankAccountNumber','bankAccountName']);
const RETENTION_DAYS=30;
const ACTIONS=Object.freeze({
 read:['action','organizationId'],
 update:['action','organizationId','operationId','fields'],
 leave:['action','organizationId','operationId'],
 close:['action','organizationId','operationId','confirmName'],
 copyPreview:['action','organizationId','targetOrganizationId'],
 copy:['action','organizationId','operationId','targetOrganizationId'],
 closedList:['action'],
 restore:['action','organizationId','operationId'],
});
// Copy moves the operating records and their history. Team, staff, activity,
// housekeeping assignments and operation ledgers stay with the source.
const COPY=Object.freeze(['buildings','rooms','tenants','bookings','payments','leaseOccupancy','leaseDateCorrections']);
const SUB=Object.freeze({buildings:['rentalContractHistory'],tenants:['rentHistory','leaseHistory'],payments:['invoiceHistory']});
const plain=v=>v!==null&&typeof v==='object'&&Object.getPrototypeOf(v)===Object.prototype;

function createOrganizationSettingsHandler({db,Timestamp,HttpsError}){
 const fail=(code,key)=>{throw new HttpsError(code,key);};
 const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
 const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
 const clean=fields=>{
  // All fields are required so a missing key can never silently clear a value.
  if(!fields||typeof fields!=='object'||Array.isArray(fields)||Object.keys(fields).some(k=>!Object.hasOwn(LIMITS,k))||
    Object.keys(LIMITS).some(k=>!Object.hasOwn(fields,k)))fail('invalid-argument','org_invalid_input');
  const out={};
  for(const [k,max] of Object.entries(LIMITS)){
   const v=fields[k]??'';
   if(typeof v!=='string'||v.length>max)fail('invalid-argument','org_invalid_input');
   out[k]=v.trim()||null;
  }
  if(!out.name)fail('invalid-argument','org_name_required');
  if(out.email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(out.email))fail('invalid-argument','org_invalid_email');
  return out;
 };
 const validMember=(m,uid,orgId)=>m&&m.ownerId===uid&&m.organizationId===orgId&&m.accessVersion===2&&
  m.status==='active'&&Object.hasOwn(roles,m.role)&&['all','selected'].includes(m.buildingScope);
 // Waiting: no supported role yet (migrated members, removed roles). May only leave.
 const waitingMember=(m,uid,orgId)=>m&&m.ownerId===uid&&m.organizationId===orgId&&m.accessVersion===2&&
  (m.status==='assignmentRequired'||(m.status==='active'&&!Object.hasOwn(roles,m.role)));

 return async request=>{
  const uid=request.auth?.uid;
  if(!uid)fail('unauthenticated','team_sign_in_required');
  const d=request.data||{};
  if(!Object.hasOwn(ACTIONS,d.action)||(d.action!=='closedList'&&!id(d.organizationId))||Object.keys(d).some(k=>!ACTIONS[d.action].includes(k))||
    (!['read','copyPreview','closedList'].includes(d.action)&&!id(d.operationId)))fail('invalid-argument','org_invalid_input');
  // Organizations this account closed that can still be restored.
  if(d.action==='closedList'){
   const now=Timestamp.now().toMillis();
   const page=await db.collection('organizations').where('closedBy','==',uid).limit(50).get();
   return {records:page.docs.filter(o=>{const x=o.data();return x.accessVersion===2&&x.closedAt&&!x.purgeStartedAt&&x.purgeAfter?.toMillis()>now;})
    .map(o=>({id:o.id,name:o.data().name??'',closedAt:o.data().closedAt.toDate().toISOString(),purgeAfter:o.data().purgeAfter.toDate().toISOString()}))};
  }
  const copying=d.action.startsWith('copy');
  if(copying&&(!id(d.targetOrganizationId)||d.targetOrganizationId===d.organizationId))fail('invalid-argument','org_copy_target');
  const fields=d.action==='update'?clean(d.fields):null;
  const orgId=d.organizationId,context={organizationId:orgId,userId:uid};
  const orgRef=db.collection('organizations').doc(orgId),memberRef=db.collection('memberships').doc(`${uid}_${orgId}`);
  const key=hash([orgId,uid,d.operationId??null]),fingerprint=hash(d);
  const opRef=db.collection('organizationOperations').doc(key),eventRef=db.collection('teamActivity').doc(key);
  // Reads happen before writes in every transaction.
  const load=async(tx,allowClosedBy=null,allowWaiting=false)=>{
   const [org,member]=await Promise.all([tx.get(orgRef),tx.get(memberRef)]);
   if(!org.exists||org.data().accessVersion!==2)fail('failed-precondition','team_migration_required');
   if(org.data().closedAt&&org.data().closedBy!==allowClosedBy)fail('failed-precondition','org_closed');
   const m=member.exists?member.data():null;
   if(!validMember(m,uid,orgId)&&!(allowWaiting&&waitingMember(m,uid,orgId)))fail('permission-denied','team_access_denied');
   return {org,m};
  };
  const replay=prior=>{
   if(!prior.exists)return null;
   if(prior.data().fingerprint!==fingerprint||prior.data().actorId!==uid)fail('already-exists','org_operation_reused');
   return prior.data().status==='pending'?null:{result:prior.data().result};
  };

  if(d.action==='read'){
   return db.runTransaction(async tx=>{
    const {org,m}=await load(tx),data=org.data(),manage=allows(m,'manageOrganization',context);
    const keys=['name','createdBy','createdAt','updatedAt','address','phone','email',...(manage?PRIVATE:[])];
    return {id:orgId,accessVersion:2,...serialize(Object.fromEntries(keys.filter(k=>data[k]!==undefined).map(k=>[k,data[k]]))),
     role:m.role,canManage:manage,canClose:m.role==='owner',canLeave:m.role!=='owner'};
   });
  }

  if(d.action==='update'){
   return db.runTransaction(async tx=>{
    const done=replay(await tx.get(opRef));if(done)return done.result;
    const {org,m}=await load(tx);
    if(!allows(m,'manageOrganization',context))fail('permission-denied','team_access_denied');
    const old=org.data(),changed=Object.keys(fields).filter(k=>(old[k]??null)!==fields[k]);
    const now=Timestamp.now(),result={status:'updated',changedFields:changed};
    if(changed.length)tx.update(orgRef,{...fields,updatedAt:now,updatedBy:uid});
    // Field names only: bank and contact values stay out of activity history.
    tx.create(eventRef,{organizationId:orgId,actorId:uid,action:'updateOrganization',targetId:orgId,before:null,after:{changedFields:changed},createdAt:now});
    tx.create(opRef,{organizationId:orgId,actorId:uid,fingerprint,status:'complete',result,createdAt:now});
    return result;
   });
  }

  if(d.action==='leave'){
   return db.runTransaction(async tx=>{
    const done=replay(await tx.get(opRef));if(done)return done.result;
    const {m}=await load(tx,null,true);
    if(m.role==='owner')fail('failed-precondition','org_owner_cannot_leave');
    const now=Timestamp.now(),result={status:'left'};
    tx.update(memberRef,{status:'revoked',revokedReason:'left',updatedAt:now,updatedBy:uid});
    tx.create(eventRef,{organizationId:orgId,actorId:uid,action:'leaveOrganization',targetId:memberRef.id,before:{status:m.status},after:{status:'revoked'},createdAt:now});
    tx.create(opRef,{organizationId:orgId,actorId:uid,fingerprint,status:'complete',result,createdAt:now});
    return result;
   });
  }

  if(copying){
   const targetId=d.targetOrganizationId,targetContext={organizationId:targetId,userId:uid};
   // Owner/administrator with all properties in BOTH organizations, plus
   // export on the source and import on the target (overridable permissions).
   const checkAccess=async tx=>{
    const [src,tgt,sm,tm]=await Promise.all([tx.get(orgRef),tx.get(db.collection('organizations').doc(targetId)),
     tx.get(memberRef),tx.get(db.collection('memberships').doc(`${uid}_${targetId}`))]);
    for(const org of [src,tgt]){
     if(!org.exists||org.data().accessVersion!==2)fail('failed-precondition','team_migration_required');
     if(org.data().closedAt)fail('failed-precondition','org_closed');
    }
    const s=sm.exists?sm.data():null,t=tm.exists?tm.data():null;
    if(!validMember(s,uid,orgId)||!validMember(t,uid,targetId)||s.buildingScope!=='all'||t.buildingScope!=='all'||
     !allows(s,'manageOrganization',context)||!allows(s,'exportData',context)||
     !allows(t,'manageOrganization',targetContext)||!allows(t,'importData',targetContext))fail('permission-denied','org_copy_access_required');
   };
   const crossLink=()=>fail('failed-precondition','org_copy_cross_link');
   if(d.action==='copyPreview'){
    await db.runTransaction(checkAccess);
    const found=await collectOrganization(db,orgId,COPY,{onCrossLink:crossLink});
    return Object.fromEntries([...found].map(([c,docs])=>[c,docs.size]));
   }
   const started=await db.runTransaction(async tx=>{
    const prior=await tx.get(opRef),done=replay(prior);if(done)return done;
    await checkAccess(tx);
    if(!prior.exists)tx.set(opRef,{organizationId:orgId,actorId:uid,fingerprint,status:'pending',createdAt:Timestamp.now()});
    return null;
   });
   if(started)return started.result;
   // New IDs are derived from the operation, so a retry after an interruption
   // overwrites the same documents instead of creating duplicates.
   const found=await collectOrganization(db,orgId,COPY,{onCrossLink:crossLink});
   const newId=old=>hash([key,old]).slice(0,28);
   const idMap=new Map([[orgId,targetId]]);
   for(const docs of found.values())for(const old of docs.keys())idMap.set(old,newId(old));
   // Every exact reference to a copied ID (or the source organization) is rewired.
   const remap=v=>typeof v==='string'?(idMap.get(v)??v):Array.isArray(v)?v.map(remap):
    plain(v)?Object.fromEntries(Object.entries(v).map(([k,x])=>[k,remap(x)])):v;
   let batch=db.batch(),pending=0;
   const flush=async()=>{if(pending){await batch.commit();batch=db.batch();pending=0;}};
   const put=async(ref,data)=>{batch.set(ref,data);if(++pending>=400)await flush();};
   const counts={};
   for(const [collection,docs] of found){
    counts[collection]=docs.size;
    for(const [old,doc] of docs){
     const ref=db.collection(collection).doc(idMap.get(old));
     // Old legacy children may lack organizationId; every copy belongs to the target.
     await put(ref,{...remap(doc.data()),organizationId:targetId});
     for(const sub of SUB[collection]??[]){
      for(const child of (await doc.ref.collection(sub).get()).docs){
       await put(ref.collection(sub).doc(hash([key,child.ref.path]).slice(0,28)),remap(child.data()));
       counts[sub]=(counts[sub]??0)+1;
      }
     }
    }
   }
   await flush();
   return db.runTransaction(async tx=>{
    const op=await tx.get(opRef);
    if(op.exists&&op.data().status==='complete')return op.data().result;
    const now=Timestamp.now(),result={status:'copied',targetOrganizationId:targetId,counts};
    tx.create(eventRef,{organizationId:orgId,actorId:uid,action:'copyOrganizationOut',targetId,before:null,after:{counts},createdAt:now});
    tx.create(db.collection('teamActivity').doc(hash([key,'in'])),{organizationId:targetId,actorId:uid,action:'copyOrganizationIn',targetId:orgId,before:null,after:{counts},createdAt:now});
    tx.update(opRef,{status:'complete',result,completedAt:now});
    return result;
   });
  }

  // restore: the owner who closed it, before the purge date. Phase 1 marks
  // the organization as restoring (the purge job skips it from then on),
  // phase 2 returns each member revoked by the close to their previous status,
  // phase 3 reopens it. Resumable with the same or a new operationId.
  if(d.action==='restore'){
   const started=await db.runTransaction(async tx=>{
    const prior=await tx.get(opRef),done=replay(prior);if(done)return done;
    const [org,member]=await Promise.all([tx.get(orgRef),tx.get(memberRef)]);
    if(!org.exists||org.data().accessVersion!==2)fail('failed-precondition','team_migration_required');
    const o=org.data(),m=member.exists?member.data():null;
    if(!o.closedAt||o.closedBy!==uid)fail('failed-precondition','org_not_closed');
    if(o.purgeStartedAt||!(o.purgeAfter?.toMillis()>Timestamp.now().toMillis()))fail('failed-precondition','org_restore_expired');
    if(!m||m.ownerId!==uid||m.organizationId!==orgId||m.role!=='owner'||
     !(m.status==='active'||(m.status==='revoked'&&m.revokedReason==='organizationClosed')))fail('permission-denied','org_owner_required');
    const now=Timestamp.now();
    if(!o.restoringAt)tx.update(orgRef,{restoringAt:now,restoringBy:uid});
    if(!prior.exists)tx.set(opRef,{organizationId:orgId,actorId:uid,fingerprint,status:'pending',createdAt:now});
    return null;
   });
   if(started)return started.result;
   const now=Timestamp.now();let cursor=null,restored=0;
   for(;;){
    let q=db.collection('memberships').where('organizationId','==',orgId).orderBy('__name__').limit(300);
    if(cursor)q=q.startAfter(cursor);
    const page=await q.get();
    // Only memberships the close revoked; people who left or were revoked earlier stay out.
    const closed=page.docs.filter(doc=>doc.data().status==='revoked'&&doc.data().revokedReason==='organizationClosed');
    if(closed.length){
     const batch=db.batch();
     for(const doc of closed)batch.update(doc.ref,{status:doc.data().statusBeforeClose??'active',revokedReason:null,statusBeforeClose:null,updatedAt:now,updatedBy:uid});
     await batch.commit();restored+=closed.length;
    }
    if(page.size<300)break;
    cursor=page.docs[page.docs.length-1];
   }
   return db.runTransaction(async tx=>{
    const [org,op]=await Promise.all([tx.get(orgRef),tx.get(opRef)]);
    if(op.exists&&op.data().status==='complete')return op.data().result;
    if(!org.exists||org.data().restoringBy!==uid)fail('aborted','org_restore_incomplete');
    const result={status:'restored'};
    tx.update(orgRef,{closedAt:null,closedBy:null,purgeAfter:null,restoringAt:null,restoringBy:null,updatedAt:now,updatedBy:uid});
    tx.create(eventRef,{organizationId:orgId,actorId:uid,action:'restoreOrganization',targetId:orgId,before:{status:'closed'},after:{status:'active',members:restored},createdAt:now});
    tx.update(opRef,{status:'complete',result,completedAt:now});
    return result;
   });
  }

  // close: owner only. Phase 1 marks the organization closed, phase 2 revokes
  // every other membership, phase 3 revokes the owner. The owner stays active
  // until the end, so an interrupted close is resumed with the same operationId.
  // Records are retained until purgeAfter; purging is a separate reviewed job.
  const phase1=await db.runTransaction(async tx=>{
   const prior=await tx.get(opRef),done=replay(prior);if(done)return done;
   const {org,m}=await load(tx,uid);
   if(m.role!=='owner')fail('permission-denied','org_owner_required');
   const now=Timestamp.now();
   if(!org.data().closedAt){
    if(typeof d.confirmName!=='string'||d.confirmName.trim()!==String(org.data().name??'').trim())fail('invalid-argument','org_confirm_name');
    tx.update(orgRef,{closedAt:now,closedBy:uid,purgeAfter:Timestamp.fromMillis(now.toMillis()+RETENTION_DAYS*86400000)});
    tx.create(eventRef,{organizationId:orgId,actorId:uid,action:'closeOrganization',targetId:orgId,before:null,after:{status:'closed'},createdAt:now});
   }
   // A resumed close may use a new operationId; it still needs its own ledger entry.
   if(!prior.exists)tx.set(opRef,{organizationId:orgId,actorId:uid,fingerprint,status:'pending',createdAt:now});
   return null;
  });
  if(phase1)return phase1.result;
  const now=Timestamp.now();
  let cursor=null;
  for(;;){
   let q=db.collection('memberships').where('organizationId','==',orgId).orderBy('__name__').limit(300);
   if(cursor)q=q.startAfter(cursor);
   const page=await q.get();
   const open=page.docs.filter(doc=>doc.id!==memberRef.id&&doc.data().status!=='revoked');
   if(open.length){
    const batch=db.batch();
    for(const doc of open)batch.update(doc.ref,{status:'revoked',revokedReason:'organizationClosed',statusBeforeClose:doc.data().status,updatedAt:now,updatedBy:uid});
    await batch.commit();
   }
   if(page.size<300)break;
   cursor=page.docs[page.docs.length-1];
  }
  return db.runTransaction(async tx=>{
   const [org,op]=await Promise.all([tx.get(orgRef),tx.get(opRef)]);
   if(!org.exists||org.data().closedBy!==uid||!op.exists)fail('aborted','org_close_incomplete');
   if(op.data().status==='complete')return op.data().result;
   const result={status:'closed',purgeAfter:org.data().purgeAfter.toDate().toISOString()};
   tx.update(memberRef,{status:'revoked',revokedReason:'organizationClosed',statusBeforeClose:'active',updatedAt:now,updatedBy:uid});
   tx.update(opRef,{status:'complete',result,completedAt:now});
   return result;
  });
 };
}
module.exports={createOrganizationSettingsHandler,LIMITS,RETENTION_DAYS};
