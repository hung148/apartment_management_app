'use strict';
const {createHash,randomUUID}=require('node:crypto');
const validId=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const emailOf=v=>typeof v==='string'?v.trim().toLowerCase():'';
// Read and later write the SAME locks in every ownership/staff transition.
// Reads alone do not serialize concurrent empty-query results.
async function policyLocks(db,tx,uid,email){
 const keys=[...(uid?['uid:'+uid]:[]),...(emailOf(email)?['email:'+emailOf(email)]:[])];
 const refs=keys.map(k=>db.collection('accountPolicyLocks').doc(createHash('sha256').update(k).digest('hex')));
 for(const r of refs)await tx.get(r);
 return ()=>{for(const r of refs)tx.set(r,{revision:randomUUID()});};
}
async function accountPolicy(db,tx,uid,email='',ignoreStaffOrg=null){
 // Independent reads share the same transaction snapshot. Start them together;
 // retain every policy check without making each request wait four round trips.
 const [memberships,created,bindingDoc,deletionDoc]=await Promise.all([
  tx.get(db.collection('memberships').where('ownerId','==',uid)),
  tx.get(db.collection('organizations').where('createdBy','==',uid)),
  tx.get(db.collection('accountOrganizations').doc(uid)),
  tx.get(db.collection('accountDeletions').doc(uid)),
 ]);
 // Request-local snapshots only: never retain authorization data across calls.
 // A membership, binding and invitation often point at the same organization.
 const orgSnapshots=new Map(created.docs.map(doc=>[doc.id,Promise.resolve(doc)]));
 const readOrg=organizationId=>{
  if(!orgSnapshots.has(organizationId))orgSnapshots.set(organizationId,tx.get(db.collection('organizations').doc(organizationId)));
  return orgSnapshots.get(organizationId);
 };
 const owned=new Set(),organizations=new Set(),states=new Map(); let hasStaff=false,hasCoOwner=false;
 for(const d of created.docs){
  const o=d.data();
  if(o.mergedInto)continue;
  if((o.ownerTransferredTo??o.createdBy)!==uid)continue;
  const m=memberships.docs.find(x=>x.id===`${uid}_${d.id}`)?.data();
  if(!o.closedAt&&m?.status==='revoked'&&m.revokedReason!=='organizationClosed')continue;
  owned.add(d.id);organizations.add(d.id);
 }
 for(const doc of memberships.docs){
  const m=doc.data();
  if(!validId(m.organizationId)||doc.id!==`${uid}_${m.organizationId}`||(m.status==='revoked'&&m.revokedReason!=='organizationClosed'))continue;
  const org=await readOrg(m.organizationId);if(!org.exists||org.data().mergedInto)continue;
  organizations.add(org.id);states.set(org.id,org.data().closedAt?'closed':m.status==='suspended'?'suspended':m.status==='assignmentRequired'?'waiting':'ready');
  const o=org.data(),owner=['owner','coOwner'].includes(m.role)||(o.accessVersion!==2&&(o.ownerTransferredTo??o.createdBy)===uid);
  if(owner)owned.add(org.id);else if(org.id!==ignoreStaffOrg)hasStaff=true;
  if(m.role==='coOwner')hasCoOwner=true;
 }
 const binding=bindingDoc.data();
 if(binding?.organizationId&&binding.state!=='released'){
  const org=await readOrg(binding.organizationId);
  if(org.exists&&!org.data().mergedInto)organizations.add(org.id);
 }
 const address=emailOf(email);
 if(address){
  const invites=await tx.get(db.collection('teamInvitations').where('email','==',address));
  for(const doc of invites.docs){
   const inv=doc.data();if(inv.status!=='pending'||(inv.expiresAt!=null&&inv.expiresAt.toMillis()<=Date.now())||!validId(inv.organizationId)||inv.organizationId===ignoreStaffOrg)continue;
   const org=await readOrg(inv.organizationId);if(org.exists&&!org.data().closedAt&&!org.data().mergedInto)hasStaff=true;
  }
 }
 const deletion=deletionDoc.data();
 const deletionBlocked=['pending','complete'].includes(deletion?.status)||binding?.state==='deleting';
 const organizationIds=[...organizations].sort(),conflict=organizations.size>1||hasCoOwner||(owned.size>0&&hasStaff);
 return {mode:conflict?'conflict':owned.size?'owner':hasStaff?'staff':'normal',canCreate:organizations.size===0&&!hasStaff&&!deletionBlocked,hasStaff,hasOwned:owned.size>0,organizationIds,
  entryState:conflict?'conflict':deletionBlocked?'deleting':organizationIds.length?states.get(organizationIds[0])??'review':hasStaff?'invited':'none',
  ...(conflict?{staffConflict:'org_single_organization_review'}:{}),...(deletionBlocked?{deleting:true}:{} )};
}
// Read now, commit later: callers keep all Firestore reads before writes.
async function prepareBinding(db,tx,uid,organizationId,{release=false,state='bound',email='',source='membership'}={},fail){
 const ref=db.collection('accountOrganizations').doc(uid),old=(await tx.get(ref)).data();
 if(!release){
  const p=await accountPolicy(db,tx,uid,email,organizationId);
  if(p.deleting)fail('failed-precondition','account_deletion_in_progress');
  if(p.organizationIds.some(id=>id!==organizationId)||old?.state==='deleting')fail('failed-precondition','org_single_organization');
 }
 return ()=>{
  if(release&&old?.organizationId!==organizationId)return;
  tx.set(ref,{organizationId:release?null:organizationId,state:release?'released':state,revision:(old?.revision??0)+1,source,updatedAtMs:Date.now()});
 };
}
async function emailOwnsOrganizations(db,tx,email){
 // Server-managed membership emails are kept current by myProfile. Acceptance
 // always checks the authenticated UID again, including legacy creator records.
 const rows=await tx.get(db.collection('memberships').where('email','==',emailOf(email)));
 const users=new Set(rows.docs.map(d=>d.data().ownerId).filter(validId));
 for(const uid of users)if((await accountPolicy(db,tx,uid)).hasOwned)return true;
 return false;
}
module.exports={accountPolicy,policyLocks,emailOwnsOrganizations,emailOf};
// No owner/delegate/share exception: every staff account has one workplace.
async function checkEmployer(db,tx,{uid,email,orgId},fail){
 const rows=new Map(),address=emailOf(email);
 if(uid){const q=await tx.get(db.collection('memberships').where('ownerId','==',uid));for(const d of q.docs)rows.set(d.id,d);}
 if(address){const q=await tx.get(db.collection('memberships').where('email','==',address));for(const d of q.docs)rows.set(d.id,d);}
 for(const d of rows.values()){
  const m=d.data();if(!validId(m.organizationId)||d.id!==`${m.ownerId}_${m.organizationId}`||(m.status==='revoked'&&m.revokedReason!=='organizationClosed'))continue;
  const org=await tx.get(db.collection('organizations').doc(m.organizationId));
  if(org.exists&&(m.organizationId!==orgId||m.employerShareId))fail('failed-precondition','team_other_employer');
 }
 if(uid){const p=await accountPolicy(db,tx,uid);if(p.deleting)fail('failed-precondition','account_deletion_in_progress');if(p.organizationIds.some(id=>id!==orgId))fail('failed-precondition','team_other_employer');}
 if(address){
  const invites=await tx.get(db.collection('teamInvitations').where('email','==',address));
  for(const d of invites.docs){const i=d.data();if(i.organizationId!==orgId&&validId(i.organizationId)&&i.status==='pending'&&(i.expiresAt==null||i.expiresAt.toMillis()>Date.now())){
   const org=await tx.get(db.collection('organizations').doc(i.organizationId));if(org.exists&&!org.data().closedAt)fail('failed-precondition','team_other_employer');
  }}
 }
 return true;
}
module.exports.checkEmployer=checkEmployer;
module.exports.prepareBinding=prepareBinding;
