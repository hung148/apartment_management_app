'use strict';
// Deliberately read-only. No tenant records, OAuth tokens or contact details.
async function auditSingleOrganization(db){
 const [orgs,members,bindings,invites,agreements,shares,drive]=await Promise.all(
  ['organizations','memberships','accountOrganizations','teamInvitations','ownershipAgreements','staffShares','driveConnections'].map(c=>db.collection(c).get()));
 const organizations=new Map(orgs.docs.map(d=>[d.id,d.data()])),accounts=new Map(),issues=[];
 const account=uid=>{if(!accounts.has(uid))accounts.set(uid,{uid,organizationIds:new Set(),roles:[],binding:null});return accounts.get(uid);};
 for(const d of orgs.docs){const o=d.data(),uid=o.ownerTransferredTo??o.createdBy;
  if(o.mergedInto)continue;
  const m=members.docs.find(m=>m.id===`${uid}_${d.id}`)?.data();
  if(!o.closedAt&&m?.status==='revoked'&&m.revokedReason!=='organizationClosed')continue;
  if(uid)account(uid).organizationIds.add(d.id);}
 for(const d of members.docs){const m=d.data();
  if(!m.ownerId||d.id!==`${m.ownerId}_${m.organizationId}`){issues.push({kind:'malformedMembership',membershipId:d.id});continue;}
  if(!organizations.has(m.organizationId)){issues.push({kind:'missingOrganization',membershipId:d.id});continue;}
  if(organizations.get(m.organizationId).mergedInto)continue;
  if(m.status==='revoked'&&m.revokedReason!=='organizationClosed')continue;
  const a=account(m.ownerId);a.organizationIds.add(m.organizationId);a.roles.push({organizationId:m.organizationId,role:m.role??null,status:m.status??null,shared:!!m.employerShareId});
 }
 for(const d of bindings.docs){const b=d.data(),a=account(d.id);a.binding={organizationId:b.organizationId??null,state:b.state??null};if(b.organizationId&&b.state!=='released')a.organizationIds.add(b.organizationId);}
 const accountRows=[...accounts.values()].map(a=>({...a,organizationIds:[...a.organizationIds].sort(),needsReview:a.organizationIds.size>1||a.roles.some(r=>r.role==='coOwner'||r.shared)}));
 const organizationRows=orgs.docs.map(d=>{const o=d.data(),owners=members.docs.filter(m=>m.data().organizationId===d.id&&m.data().status!=='revoked'&&['owner','coOwner'].includes(m.data().role)).map(m=>({uid:m.data().ownerId,role:m.data().role}));return {organizationId:d.id,name:typeof o.name==='string'?o.name:'',accessVersion:o.accessVersion??1,currentOwnerId:o.ownerTransferredTo??o.createdBy??null,closed:!!o.closedAt,restoring:!!o.restoringAt,purging:!!o.purgeStartedAt,owners,needsReview:owners.some(m=>m.role==='coOwner')||(!o.closedAt&&o.accessVersion===2&&owners.filter(m=>m.role==='owner').length!==1)};});
 const countPending=docs=>docs.filter(d=>d.data().status==='pending').length;
 return {schemaVersion:1,readOnly:true,totals:{accounts:accountRows.length,organizations:organizationRows.length,accountsNeedingReview:accountRows.filter(a=>a.needsReview).length,organizationsNeedingReview:organizationRows.filter(o=>o.needsReview).length,pendingInvitations:countPending(invites.docs),pendingAgreements:countPending(agreements.docs),activeShares:shares.docs.filter(d=>d.data().status==='active').length,organizationDriveConnections:drive.size},accounts:accountRows,organizations:organizationRows,issues};
}
module.exports={auditSingleOrganization};
