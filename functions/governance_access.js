'use strict';
const {createHash}=require('node:crypto');
const ownerMember=m=>!!m&&m.role==='owner'&&m.accessVersion===2&&m.status==='active';
const controlNames=['manageCoOwners','shareStaff','closeOrganization','transferOwnership'];
const companyOf=o=>o.companyId??`owner_${o.ownerTransferredTo??o.createdBy}`;
const shareKey=(source,target,email)=>createHash('sha256').update(JSON.stringify([source,target,email.trim().toLowerCase()])).digest('hex');
async function owners(db,tx,orgId){
 const rows=await tx.get(db.collection('memberships').where('organizationId','==',orgId));
 return rows.docs.filter(d=>d.id===`${d.data().ownerId}_${orgId}`&&ownerMember(d.data())).map(d=>d.data().ownerId).sort();
}
function control(m,key,ownerCount=1){
 if(!ownerMember(m)||!controlNames.includes(key))return 'off';
 if(m.ownershipControls&&Object.hasOwn(m.ownershipControls,key))return m.ownershipControls[key];
 return m.role==='owner'?(ownerCount>1&&key!=='shareStaff'?'joint':'alone'):'off';
}
async function validShare(db,tx,source,target,email){
 const doc=await tx.get(db.collection('staffShares').doc(shareKey(source,target,email)));
 const s=doc.data();
 if(!s||s.status!=='active'||s.sourceOrganizationId!==source||s.organizationId!==target||s.email!==email||s.expiresAt.toMillis()<=Date.now())return false;
 for(const orgId of [source,target]){
  const org=await tx.get(db.collection('organizations').doc(orgId));
  if(!org.exists||org.data().closedAt||companyOf(org.data())!==s.companies[orgId])return false;
  for(const uid of s.approvers[orgId]??[]){
   const m=(await tx.get(db.collection('memberships').doc(`${uid}_${orgId}`))).data();
   if(!ownerMember(m))return false;
  }
  if(!(s.approvers[orgId]?.length))return false;
 }
 const home=(await tx.get(db.collection('memberships').doc(`${s.staffUserId}_${source}`))).data();
 return home?.status==='active'&&!['owner','coOwner'].includes(home.role);
}
async function authorizeSensitive(db,tx,{orgId,uid,member,kind},fail){
 if(!ownerMember(member)||member.ownerId!==uid||member.organizationId!==orgId||!['closeOrganization','transferOwnership'].includes(kind))fail('permission-denied','org_owner_required');
 const members=await tx.get(db.collection('memberships').where('organizationId','==',orgId));
 if(members.docs.some(d=>d.data().role==='coOwner'&&d.data().status!=='revoked'))fail('failed-precondition','org_single_organization_review');
 if(members.docs.filter(d=>d.data().role==='owner'&&d.data().status==='active').length!==1)fail('failed-precondition','org_single_organization_review');
}
module.exports={ownerMember,controlNames,control,owners,companyOf,shareKey,validShare,authorizeSensitive};
