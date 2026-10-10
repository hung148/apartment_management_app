'use strict';
const {createHash}=require('node:crypto');
const {forEachMatch}=require('./org_data');
const {canRunOrganization}=require('./team_access');
const {owners,authorizeSensitive,companyOf,control}=require('./governance_access');
const {accountPolicy,policyLocks,prepareBinding}=require('./account_policy');

// Account deletion ("delete my account") for version-2 and legacy members.
// preview: what happens to each organization. delete: carries it out, after a
// recent sign-in, with the owner's per-organization choices (hand over to an
// administrator, or close). The client deletes the Firebase login last, so the
// runtime identity needs no Auth administration permission.
const RETENTION_DAYS=30,RECENT_LOGIN_SECONDS=300;

function createAccountDeletionHandler({db,Timestamp,HttpsError}){
 const fail=(code,key)=>{throw new HttpsError(code,key);};
 const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
 const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex').slice(0,40);
 const recentLogin=request=>{
  const at=Number(request.auth?.token?.auth_time);
  return Number.isFinite(at)&&Timestamp.now().toMillis()/1000-at<=RECENT_LOGIN_SECONDS;
 };

 /** One row per organization the account still belongs to. */
 async function plan(uid){
  const rows=[];
  const mine=[];
  await forEachMatch(db,'memberships','ownerId',uid,doc=>{mine.push(doc);});
  for(const m of mine){
   const d=m.data(),orgId=d.organizationId;
   const row={membershipId:m.id,organizationId:typeof orgId==='string'?orgId:null,name:'',accessVersion:1,role:d.role??null,
    status:d.status??null,plan:'leave',otherMembers:0,candidates:[]};
   rows.push(row);
   if(!id(orgId)||m.id!==`${uid}_${orgId}`||d.status==='revoked')continue;
   const org=await db.collection('organizations').doc(orgId).get();
   if(!org.exists||org.data().closedAt)continue;
   const o=org.data();row.name=o.name??'';row.accessVersion=o.accessVersion??1;
   const others=[];
   await forEachMatch(db,'memberships','organizationId',orgId,doc=>{if(doc.id!==m.id&&doc.data().status!=='revoked')others.push(doc.data());});
   row.otherMembers=others.length;
   if(row.accessVersion===2&&d.role==='owner'){
    row.candidates=others.filter(x=>canRunOrganization(x))
     .map(x=>({userId:x.ownerId,name:x.displayName||x.email||''}));
    row.plan=row.candidates.length?'decide':'close';
   }else if(row.accessVersion!==2&&d.role==='admin'&&d.status==='active'){
    // Legacy: another active admin keeps it running; otherwise it closes.
    row.plan=others.some(x=>x.role==='admin'&&x.status==='active')?'leave':'close';
   }
  }
  return rows;
 }
 const publicRow=r=>({organizationId:r.organizationId,name:r.name,accessVersion:r.accessVersion,role:r.role,plan:r.plan,
  otherMembers:r.otherMembers,candidates:r.candidates});

 const scrub={displayName:null,email:null};
 async function removeMembership(row,now,uid){
  const ref=db.collection('memberships').doc(row.membershipId);
  const cur=await ref.get();if(!cur.exists)return;
  // Legacy member lists show every membership record, so legacy ones are
  // deleted as the old app did; version-2 ones keep a scrubbed revoked record.
  if(row.accessVersion!==2){await ref.delete();return;}
  await db.runTransaction(async tx=>{
   const current=(await tx.get(ref)).data();
   if(current?.role==='coOwner'&&current.status==='active'){
    const all=await owners(db,tx,row.organizationId);let recovery=false;
    for(const other of all){if(other===uid)continue;const m=(await tx.get(db.collection('memberships').doc(`${other}_${row.organizationId}`))).data();if(control(m,'manageCoOwners',all.length)!=='off')recovery=true;}
    if(!recovery)fail('failed-precondition','agreement_last_owner');
   }
   tx.update(ref,{status:'revoked',revokedReason:'accountDeleted',...scrub,updatedAt:now,updatedBy:uid});
  });
 }
 async function closeOrganization(row,now,uid){
  const orgRef=db.collection('organizations').doc(row.organizationId);
  await db.runTransaction(async tx=>{
   const org=await tx.get(orgRef);
   if(!org.exists||org.data().closedAt)return;
   if(org.data().accessVersion===2){const m=(await tx.get(db.collection('memberships').doc(`${uid}_${row.organizationId}`))).data();await authorizeSensitive(db,tx,{orgId:row.organizationId,uid,member:m,kind:'closeOrganization'},fail);}
   tx.update(orgRef,{closedAt:now,closedBy:uid,closedReason:'accountDeleted',purgeAfter:Timestamp.fromMillis(now.toMillis()+RETENTION_DAYS*86400000)});
   tx.set(db.collection('teamActivity').doc(hash([uid,'accountDeletedClose',row.organizationId])),{organizationId:row.organizationId,actorId:uid,
    action:'closeOrganization',targetId:row.organizationId,before:null,after:{status:'closed',reason:'accountDeleted'},createdAt:now});
  });
  const open=[];
  await forEachMatch(db,'memberships','organizationId',row.organizationId,doc=>{if(doc.id!==row.membershipId&&doc.data().status!=='revoked')open.push(doc);});
  for(let i=0;i<open.length;i+=400){
   const batch=db.batch();
   for(const doc of open.slice(i,i+400))batch.update(doc.ref,{status:'revoked',revokedReason:'organizationClosed',statusBeforeClose:doc.data().status,updatedAt:now,updatedBy:uid});
   await batch.commit();
  }
 }
 async function transferOwnership(row,to,now,uid){
  const orgRef=db.collection('organizations').doc(row.organizationId);
  const mineRef=db.collection('memberships').doc(row.membershipId),targetRef=db.collection('memberships').doc(`${to}_${row.organizationId}`);
  await db.runTransaction(async tx=>{
   const [org,mine,target]=await Promise.all([tx.get(orgRef),tx.get(mineRef),tx.get(targetRef)]);
   const t=target.exists?target.data():null;
   if(t&&t.role==='owner'&&t.status==='active'&&mine.exists&&mine.data().status==='revoked')return; // already done
   if(!org.exists||org.data().closedAt||!t||t.ownerId!==to||t.organizationId!==row.organizationId||t.accessVersion!==2||
    !canRunOrganization(t))fail('failed-precondition','account_deletion_plan_changed');
   const allMembers=await tx.get(db.collection('memberships').where('organizationId','==',row.organizationId));
   if(allMembers.docs.some(d=>d.data().role==='coOwner'&&d.data().status!=='revoked'))fail('failed-precondition','org_single_organization_review');
   const commitPolicy=await policyLocks(db,tx,to,t.email);
   const bind=await prepareBinding(db,tx,to,row.organizationId,{email:t.email,source:'ownershipTransfer'},fail);
   if((await accountPolicy(db,tx,to,t.email,row.organizationId)).hasStaff)fail('failed-precondition','org_staff_account');
   const staff=await tx.get(db.collection('memberships').where('organizationId','==',row.organizationId));
   for(const doc of staff.docs){
    const m=doc.data();if(m.ownerId===uid||m.ownerId===to||m.status==='revoked')continue;
    // Fail closed until employees with other workplace assignments are removed
    // from this organization; the owner can then retry the normal handover.
    const p=await accountPolicy(db,tx,m.ownerId,m.email,row.organizationId);
    if(p.hasStaff)fail('failed-precondition','account_deletion_plan_changed');
   }
   commitPolicy();bind();
   tx.update(targetRef,{role:'owner',roleGrants:null,roleRevision:null,roleName:null,buildingScope:'all',buildingIds:[],permissionOverrides:{},updatedAt:now,updatedBy:uid});
   tx.update(mineRef,{status:'revoked',revokedReason:'accountDeleted',...scrub,updatedAt:now,updatedBy:uid});
   tx.update(orgRef,{ownerTransferredAt:now,ownerTransferredTo:to,companyId:companyOf(org.data())});
   tx.set(db.collection('teamActivity').doc(hash([uid,'transferOwnership',row.organizationId])),{organizationId:row.organizationId,actorId:uid,
    action:'transferOwnership',targetId:targetRef.id,before:{owner:uid},after:{owner:to},createdAt:now});
  });
 }
 async function deleteWhere(collection,field,value){
  const refs=[];await forEachMatch(db,collection,field,value,doc=>{refs.push(doc.ref);});
  for(let i=0;i<refs.length;i+=400){const batch=db.batch();for(const r of refs.slice(i,i+400))batch.delete(r);await batch.commit();}
  return refs.length;
 }

 return async request=>{
  const uid=request.auth?.uid;
  if(!uid)fail('unauthenticated','team_sign_in_required');
  const d=request.data||{};
  const keys={preview:['action'],delete:['action','operationId','decisions']}[d.action];
  if(!keys||Object.keys(d).some(k=>!keys.includes(k))||(d.action==='delete'&&!id(d.operationId)))fail('invalid-argument','account_deletion_invalid');
  if(d.action==='preview'){
   return {recentLogin:recentLogin(request),organizations:(await plan(uid)).filter(r=>r.plan!=='leave'||r.name).filter(r=>r.status!=='revoked').map(publicRow)};
  }
  if(!recentLogin(request))fail('failed-precondition','recent_login_required');
  const decisions=d.decisions??{};
  if(typeof decisions!=='object'||Array.isArray(decisions)||Object.entries(decisions).some(([k,v])=>!id(k)||!v||typeof v!=='object'||
   !(v.action==='close'&&Object.keys(v).length===1)&&!(v.action==='transfer'&&id(v.to)&&Object.keys(v).length===2)))fail('invalid-argument','account_deletion_invalid');
  const ledgerRef=db.collection('accountDeletions').doc(uid);
  let rows=await plan(uid);
  // The first attempt fixes the choices; a resumed attempt reuses them.
  const chosen=await db.runTransaction(async tx=>{
   const prior=await tx.get(ledgerRef);
   const lock=await policyLocks(db,tx,uid,request.auth.token?.email);
   const bindingRef=db.collection('accountOrganizations').doc(uid),binding=(await tx.get(bindingRef)).data();
   if(prior.exists&&prior.data().status==='pending')return prior.data().decisions;
   for(const r of rows){
    const c=decisions[r.organizationId];
    // A hand-over chosen in the preview must still be possible; never turn it
    // into a close for everyone without asking again.
    if(c?.action==='transfer'&&!(r.plan==='decide'&&r.candidates.some(x=>x.userId===c.to)))fail('failed-precondition','account_deletion_plan_changed');
    if(r.plan==='decide'&&!c)fail('failed-precondition','account_deletion_decision_required');
   }
   lock();tx.set(bindingRef,{...(binding??{}),state:'deleting',revision:(binding?.revision??0)+1});
   tx.set(ledgerRef,{status:'pending',decisions,operationId:d.operationId,startedAt:Timestamp.now()});
   return decisions;
  });
  const now=Timestamp.now();
  try{
   for(const r of rows){
    if(!r.organizationId||r.status==='revoked'){await removeMembership(r,now,uid);continue;}
    if(r.plan==='decide'||r.plan==='close'){
     const c=chosen[r.organizationId]??{action:'close'};
     if(c.action==='transfer'&&r.plan==='decide')await transferOwnership(r,c.to,now,uid);
     else{await closeOrganization(r,now,uid);await removeMembership(r,now,uid);}
    }else await removeMembership(r,now,uid);
   }
  }catch(error){
   // A changed situation (e.g. the chosen administrator lost the role): start over from a new preview.
   if(error?.message==='account_deletion_plan_changed')await ledgerRef.delete();
   throw error;
  }
  const counts={requests:await deleteWhere('teamRequests','userId',uid)};
  const staff=[];await forEachMatch(db,'staffProfiles','accountId',uid,doc=>{staff.push(doc.ref);});
  for(const ref of staff)await ref.update({accountId:null,updatedAt:now});
  counts.staffUnlinked=staff.length;
  for(const c of ['aiUsage','aiRequests','aiDrafts'])counts[c]=await deleteWhere(c,'ownerId',uid);
  await db.collection('aiEntitlements').doc(uid).delete();
  await db.collection('accountSessions').doc(uid).delete(); // sign-out-everywhere cut-off
  await db.collection('owners').doc(uid).delete();
  const result={status:'dataDeleted',organizations:rows.length,counts};
  await db.runTransaction(async tx=>{
   const lock=await policyLocks(db,tx,uid,request.auth.token?.email);
   const ref=db.collection('accountOrganizations').doc(uid),b=(await tx.get(ref)).data();
   lock();tx.set(ref,{organizationId:null,state:'released',revision:(b?.revision??0)+1,source:'accountDeletion',updatedAtMs:Date.now()});
   tx.set(ledgerRef,{status:'complete',completedAt:Timestamp.now(),result});
  });
  return result;
 };
}
module.exports={createAccountDeletionHandler,RECENT_LOGIN_SECONDS};
