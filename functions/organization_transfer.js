'use strict';
const {accountPolicy,policyLocks,prepareBinding}=require('./account_policy');
const {hasRole}=require('./team_access');
function createOrganizationTransferHandler({db,Timestamp,HttpsError}){
 const fail=key=>{throw new HttpsError('failed-precondition',key);};
 const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
 return async request=>{
  const uid=request.auth?.uid,d=request.data??{};
  if(!id(uid))throw new HttpsError('unauthenticated','team_sign_in_required');
  if(!id(d.organizationId)||!['read','propose','accept','cancel'].includes(d.action)||Object.keys(d).some(k=>!['action','organizationId','recipientId','proposalId'].includes(k))||
    (d.action==='propose'&&(!id(d.recipientId)||!id(d.proposalId)))||(['accept','cancel'].includes(d.action)&&!id(d.proposalId)))throw new HttpsError('invalid-argument','org_invalid_input');
  return db.runTransaction(async tx=>{
   const orgRef=db.doc(`organizations/${d.organizationId}`),org=await tx.get(orgRef),o=org.data();
   const people=await tx.get(db.collection('memberships').where('organizationId','==',d.organizationId));
   const actor=people.docs.find(m=>m.id===`${uid}_${d.organizationId}`)?.data();
   const proposalRef=db.doc(`organizationTransfers/${d.organizationId}`),proposal=(await tx.get(proposalRef)).data();
   if(!o||o.accessVersion!==2||o.closedAt||o.mergedInto||actor?.status!=='active'||actor.ownerId!==uid)fail('team_no_access');
   if(people.docs.some(m=>m.data().role==='coOwner'&&m.data().status!=='revoked')||people.docs.filter(m=>m.data().role==='owner'&&m.data().status==='active').length!==1)fail('org_single_organization_review');
   const ownerDoc=people.docs.find(m=>m.data().role==='owner'&&m.data().status==='active'),owner=ownerDoc.data();
   if(ownerDoc.id!==`${owner.ownerId}_${d.organizationId}`)fail('org_single_organization_review');
   if((o.ownerTransferredTo??o.createdBy)!==owner.ownerId)fail('org_single_organization_review');
   const pending=proposal?.status==='pending'&&proposal.expiresAt.toMillis()>Timestamp.now().toMillis();
   if(d.action==='read')return {
    owner:owner.ownerId===uid,
    candidates:owner.ownerId===uid?people.docs.filter(m=>m.data().ownerId!==uid&&m.data().status==='active'&&hasRole(m.data())).map(m=>({id:m.data().ownerId,name:m.data().displayName??m.data().email??'Staff'})):[],
    proposal:pending&&(owner.ownerId===uid||proposal.recipientId===uid)?{id:proposal.id,recipientName:proposal.recipientName,canAccept:proposal.recipientId===uid}:null,
   };
   if(d.action==='accept'&&proposal?.status==='complete'&&proposal.id===d.proposalId&&owner.ownerId===uid)return {status:'complete'};
   if(d.action==='cancel'){
    if(owner.ownerId===uid&&proposal?.status==='cancelled'&&proposal.id===d.proposalId)return {status:'cancelled'};
    if(owner.ownerId!==uid||!pending||proposal.id!==d.proposalId)fail('org_transfer_changed');
    tx.set(proposalRef,{...proposal,status:'cancelled',updatedAt:Timestamp.now()});return {status:'cancelled'};
   }
   const recipientId=d.action==='propose'?d.recipientId:proposal?.recipientId;
   const target=people.docs.find(m=>m.id===`${recipientId}_${d.organizationId}`)?.data();
   if(!target||target.status!=='active'||!hasRole(target)||recipientId===owner.ownerId)fail('org_transfer_changed');
   if(d.action==='accept'&&(!pending||proposal.id!==d.proposalId||proposal.ownerId!==owner.ownerId||recipientId!==uid))fail('org_transfer_changed');
   if(d.action==='propose'&&owner.ownerId!==uid)fail('org_transfer_owner_only');
   const ownerLocks=await policyLocks(db,tx,owner.ownerId,owner.email),targetLocks=await policyLocks(db,tx,recipientId,target.email);
   for(const user of [owner.ownerId,recipientId]){
    const p=await accountPolicy(db,tx,user);if(p.deleting||p.organizationIds.some(orgId=>orgId!==d.organizationId))fail('org_single_organization_review');
   }
   const bind=await prepareBinding(db,tx,recipientId,d.organizationId,{source:'ownershipTransfer'},(code,key)=>fail(key));
   const release=await prepareBinding(db,tx,owner.ownerId,d.organizationId,{release:true},(code,key)=>fail(key));
   ownerLocks();targetLocks();const now=Timestamp.now();
   if(d.action==='propose'){
    if(pending&&proposal.id===d.proposalId&&proposal.recipientId===recipientId)return {status:'pending'};
    if(pending)fail('org_transfer_pending');
    tx.set(proposalRef,{id:d.proposalId,organizationId:d.organizationId,ownerId:uid,recipientId,recipientName:target.displayName??target.email??'Staff',status:'pending',createdAt:now,expiresAt:Timestamp.fromMillis(now.toMillis()+7*86400000)});
    return {status:'pending'};
   }
   bind();release();
   tx.set(db.doc(`memberships/${owner.ownerId}_${d.organizationId}`),{...owner,status:'revoked',revokedReason:'ownershipTransferred',updatedAt:now});
   tx.set(db.doc(`memberships/${recipientId}_${d.organizationId}`),{...target,role:'owner',buildingScope:'all',buildingIds:[],permissionOverrides:{},updatedAt:now});
   tx.set(orgRef,{...o,ownerTransferredTo:recipientId,ownerTransferredAt:now,updatedAt:now});
   tx.set(proposalRef,{...proposal,status:'complete',updatedAt:now});
   tx.set(db.doc(`teamActivity/transfer_${d.organizationId}_${d.proposalId}`),{organizationId:d.organizationId,actorId:uid,action:'transferOwnership',createdAt:now,before:{owner:owner.ownerId},after:{owner:recipientId}});
   return {status:'complete'};
  });
 };
}
module.exports={createOrganizationTransferHandler};
