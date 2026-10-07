'use strict';
const {createHash}=require('node:crypto');
const {parseGrants,effectiveGrants}=require('./team_access');
const {accountPolicy,policyLocks,emailOf}=require('./account_policy');
const {ownerMember,controlNames,control,owners,companyOf,shareKey}=require('./governance_access');
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const emailOk=v=>typeof v==='string'&&v.length<=254&&/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);
const cleanControls=v=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===controlNames.length&&controlNames.every(k=>['off','alone','joint'].includes(v[k]))?Object.fromEntries(controlNames.map(k=>[k,v[k]])):null;
function createGovernanceHandler({db,Timestamp,HttpsError,organizationSettings}){
 const fail=(c,m)=>{throw new HttpsError(c,m);};
 return async request=>{
  const uid=request.auth?.uid;if(!id(uid))fail('unauthenticated','team_sign_in_required');
  // Preserve the published route, but never activate historical co-owner or
  // cross-organization sharing agreements after the single-owner cutover.
  fail('failed-precondition','organization_governance_retired');
  const email=request.auth.token?.email_verified===true?emailOf(request.auth.token.email):'';
  const d=request.data??{};
  if(!['list','propose','approve','decline','revokeShare','execute'].includes(d.action))fail('invalid-argument','agreement_invalid');
  if(d.action!=='list'&&!id(d.operationId))fail('invalid-argument','agreement_invalid');
  if(d.organizationId!=null&&!id(d.organizationId))fail('invalid-argument','agreement_invalid');
  if(d.action==='execute'){
   if(!id(d.agreementId))fail('invalid-argument','agreement_invalid');
   const a=(await db.collection('ownershipAgreements').doc(d.agreementId).get()).data();
   if(!a||a.proposedBy!==uid||a.kind!=='closeOrganization'||a.status!=='approved')fail('permission-denied','agreement_control_denied');
   return organizationSettings({...request,data:{action:'close',organizationId:a.organizationId,operationId:'agreement_'+d.agreementId,confirmName:a.confirmName,agreementId:d.agreementId}});
  }
  return db.runTransaction(async tx=>{
   const now=Timestamp.now(),expires=Timestamp.fromMillis(now.toMillis()+7*86400000);
   const orgId=d.organizationId;
   const org=orgId?await tx.get(db.collection('organizations').doc(orgId)):null;
   const actor=orgId?(await tx.get(db.collection('memberships').doc(`${uid}_${orgId}`))).data():null;
   if(orgId&&(!org.exists||org.data().accessVersion!==2||org.data().closedAt))fail('failed-precondition','team_migration_required');
   if(d.action==='list'){
    const docs=new Map();
    // Recipient inbox is available before joining; exposes only the agreement.
    if(email){const q=await tx.get(db.collection('ownershipAgreements').where('recipientEmail','==',email));for(const x of q.docs)docs.set(x.id,x);}
    if(orgId){
     if(!ownerMember(actor))fail('permission-denied','agreement_control_denied');
     for(const field of ['organizationId','targetOrganizationId']){
      const q=await tx.get(db.collection('ownershipAgreements').where(field,'==',orgId));for(const x of q.docs)docs.set(x.id,x);
     }
    }
    const all=orgId?await owners(db,tx,orgId):[];
    const records=[...docs.values()].map(x=>({id:x.id,...x.data(),expiresAt:x.data().expiresAt.toDate().toISOString()})).sort((a,b)=>b.createdAt.toMillis()-a.createdAt.toMillis()).slice(0,100).map(x=>({...x,createdAt:x.createdAt.toDate().toISOString()}));
    for(const a of records){
     if(a.status==='pending'){
      const current=await tx.get(db.collection('organizations').doc(a.organizationId));
      if(!current.exists||current.data().closedAt||a.baseRevision!==(current.data().governanceRevision??0))a.status='changed';
      else if(Date.parse(a.expiresAt)<=now.toMillis())a.status='expired';
      if(a.targetOrganizationId){const target=await tx.get(db.collection('organizations').doc(a.targetOrganizationId));if(!target.exists||target.data().closedAt||a.targetRevision!==(target.data().governanceRevision??0))a.status='changed';}
     }
     if(a.kind==='shareStaff'&&a.status==='active'){
      const share=(await tx.get(db.collection('staffShares').doc(shareKey(a.organizationId,a.targetOrganizationId,a.staffEmail)))).data();
      a.sharingUntil=share?.expiresAt?.toDate().toISOString()??null;
      if(share?.expiresAt?.toMillis()<=now.toMillis())a.displayStatus='expired';
     }
    }
    const ownerOptions=[];for(const userId of all){const m=(await tx.get(db.collection('memberships').doc(`${userId}_${orgId}`))).data();ownerOptions.push({userId,role:m.role,name:m.displayName||m.email||userId});}
    return {myUserId:uid,ownerOptions,organizationCode:org?.data()?.inviteCode??'',records:records.map(a=>({...a,canApprove:a.status==='pending'&&(!a.approvals.includes(uid)||a.required.every(x=>a.approvals.includes(x)))&&(a.required.includes(uid)||a.recipientEmail===email),canDecline:a.status==='pending',canRevoke:a.kind==='shareStaff'&&a.status==='active'&&control(actor,'shareStaff')!=='off',canExecute:a.kind==='closeOrganization'&&a.status==='approved'&&a.proposedBy===uid})),controls:Object.fromEntries(controlNames.map(k=>[k,control(actor,k,all.length)])),owners:all};
   }
   const opRef=db.collection('governanceOperations').doc(hash([uid,d.operationId])),fingerprint=hash(d),prior=await tx.get(opRef);
   if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('already-exists','team_operation_reused');return prior.data().result;}
   const writes=[],commits=[];let result;let auditOrg=orgId;
   const save=(r,v)=>writes.push(()=>tx.set(r,v));
   const update=(r,v)=>writes.push(()=>tx.update(r,v));
   if(d.action==='propose'){
    if(!orgId||!ownerMember(actor))fail('permission-denied','agreement_control_denied');
    const all=await owners(db,tx,orgId),kind=d.kind;
    if(!['coOwner','removeCoOwner','shareStaff','closeOrganization','transferOwnership'].includes(kind))fail('invalid-argument','agreement_invalid');
    const capability=['coOwner','removeCoOwner'].includes(kind)?'manageCoOwners':kind;
    if(control(actor,capability,all.length)==='off')fail('permission-denied','agreement_control_denied');
    let proposal={organizationId:orgId,organizationName:org.data().name??orgId,kind,proposedBy:uid,status:'pending',baseRevision:org.data().governanceRevision??0,ownerSnapshot:all,required:['closeOrganization','transferOwnership'].includes(kind)&&control(actor,capability,all.length)==='alone'?[uid]:all,approvals:[uid],createdAt:now,expiresAt:expires};
    if(kind==='coOwner'){
     const grants=parseGrants(d.grants),controls=cleanControls(d.controls),recipientEmail=emailOf(d.recipientEmail);
     if(!grants||!controls||!emailOk(recipientEmail)||all.length>=10)fail('invalid-argument','agreement_invalid');
     proposal={...proposal,grants,controls,recipientEmail};
     // Recipient UID and account policy are verified on explicit acceptance.
    }else if(kind==='removeCoOwner'||kind==='transferOwnership'){
     if(!id(d.targetUserId)||!all.includes(d.targetUserId)||d.targetUserId===uid)fail('invalid-argument','agreement_invalid');
     const target=(await tx.get(db.collection('memberships').doc(`${d.targetUserId}_${orgId}`))).data();
     if(kind==='removeCoOwner'&&target.role!=='coOwner')fail('failed-precondition','agreement_last_owner');
     proposal.targetUserId=d.targetUserId;
    }else if(kind==='closeOrganization'){
     if(d.confirmName!==org.data().name)fail('invalid-argument','org_confirm_name');proposal.confirmName=d.confirmName;
    }else{
     let destination=d.targetOrganizationId;
     if(d.targetOrganizationCode){const code=String(d.targetOrganizationCode).trim();if(!id(code))fail('invalid-argument','agreement_invalid');destination=(await tx.get(db.collection('invite_codes').doc(code))).data()?.orgId;}
     if(!id(destination)||destination===orgId||!emailOk(d.staffEmail)||!Number.isInteger(d.durationDays)||d.durationDays<1||d.durationDays>365)fail('invalid-argument','agreement_invalid');
     const target=await tx.get(db.collection('organizations').doc(destination));
     if(!target.exists||target.data().accessVersion!==2||target.data().closedAt)fail('invalid-argument','agreement_invalid');
     const staffEmail=emailOf(d.staffEmail),staffRows=await tx.get(db.collection('memberships').where('email','==',staffEmail));
     const home=staffRows.docs.find(x=>x.id===`${x.data().ownerId}_${orgId}`&&x.data().organizationId===orgId&&x.data().status==='active'&&!['owner','coOwner'].includes(x.data().role));
     if(!home||home.data().employerShareId)fail('failed-precondition','agreement_staff_required');
     const targetOwners=await owners(db,tx,target.id);if(!targetOwners.length)fail('failed-precondition','agreement_invalid');
     proposal={...proposal,targetOrganizationId:target.id,targetOrganizationName:target.data().name??target.id,targetRevision:target.data().governanceRevision??0,required:[...new Set([...all,...targetOwners])],sourceOwners:all,targetOwners,staffEmail,staffUserId:home.data().ownerId,durationDays:d.durationDays,companies:{[orgId]:companyOf(org.data()),[target.id]:companyOf(target.data())}};
    }
    const agreementId=hash([uid,d.operationId]);save(db.collection('ownershipAgreements').doc(agreementId),proposal);result={agreementId,status:'pending'};
   }else{
    if(!id(d.agreementId))fail('invalid-argument','agreement_invalid');
    const ref=db.collection('ownershipAgreements').doc(d.agreementId),snap=await tx.get(ref),a=snap.data();
    if(!a)fail('not-found','agreement_not_found');auditOrg=a.organizationId;
    const source=await tx.get(db.collection('organizations').doc(a.organizationId));
    if(!source.exists||source.data().closedAt)fail('failed-precondition','org_closed');
    const sourceOwners=await owners(db,tx,a.organizationId);
    const recipient=!!email&&a.recipientEmail===email;
    if(!sourceOwners.includes(uid)&&!recipient&&!(a.targetOwners??[]).includes(uid))fail('permission-denied','agreement_control_denied');
    if(d.action==='revokeShare'){
     if(a.kind!=='shareStaff'||a.status!=='active')fail('failed-precondition','agreement_changed');
     const myOrg=sourceOwners.includes(uid)?a.organizationId:a.targetOrganizationId;
     const mine=(await tx.get(db.collection('memberships').doc(`${uid}_${myOrg}`))).data();
     if(control(mine,'shareStaff')==='off')fail('permission-denied','agreement_control_denied');
     const shareRef=db.collection('staffShares').doc(shareKey(a.organizationId,a.targetOrganizationId,a.staffEmail));
     const share=await tx.get(shareRef);
     if(!share.exists||share.data().agreementId!==snap.id)fail('failed-precondition','agreement_changed');
     commits.push(await policyLocks(db,tx,a.staffUserId,a.staffEmail));
     const targetMember=db.collection('memberships').doc(`${a.staffUserId}_${a.targetOrganizationId}`),targetSnap=await tx.get(targetMember);
     const invites=await tx.get(db.collection('teamInvitations').where('email','==',a.staffEmail));
     if(targetSnap.exists)update(targetMember,{status:'revoked',revokedReason:'sharingEnded',updatedAt:now});
     for(const i of invites.docs)if(i.data().organizationId===a.targetOrganizationId&&i.data().status==='pending')update(i.ref,{status:'revoked',revokedAt:now});
     update(shareRef,{status:'revoked',revokedBy:uid,revokedAt:now});update(ref,{status:'revoked',revokedBy:uid,revokedAt:now});result={status:'revoked'};
    }else{
     if(a.status!=='pending'||a.expiresAt.toMillis()<=now.toMillis()||a.baseRevision!==(source.data().governanceRevision??0))fail('failed-precondition','agreement_changed');
     if(JSON.stringify(sourceOwners)!==JSON.stringify(a.ownerSnapshot))fail('failed-precondition','agreement_changed');
     let target;
     if(a.kind==='shareStaff'){
      target=await tx.get(db.collection('organizations').doc(a.targetOrganizationId));
      const currentTargetOwners=await owners(db,tx,a.targetOrganizationId);
      if(!target.exists||target.data().closedAt||a.targetRevision!==(target.data().governanceRevision??0)||JSON.stringify(currentTargetOwners)!==JSON.stringify(a.targetOwners))fail('failed-precondition','agreement_changed');
      if(!sourceOwners.includes(uid)&&!currentTargetOwners.includes(uid))fail('permission-denied','agreement_control_denied');
     }
     if(d.action==='decline'){update(ref,{status:'declined',declinedBy:uid});result={status:'declined'};}
     else{
      if(!a.required.includes(uid)&&!recipient)fail('permission-denied','agreement_control_denied');
      const approvals=[...new Set([...a.approvals,uid])];let recipientUserId=a.recipientUserId??null;
      if(recipient)recipientUserId=uid;
      const ready=a.required.every(x=>approvals.includes(x))&&(a.kind!=='coOwner'||recipientUserId);
      let status='pending';
      if(ready){
       const actorNow=(await tx.get(db.collection('memberships').doc(`${a.proposedBy}_${a.organizationId}`))).data();
       const capability=['coOwner','removeCoOwner'].includes(a.kind)?'manageCoOwners':a.kind;
       if(control(actorNow,capability,sourceOwners.length)==='off')fail('permission-denied','agreement_control_denied');
       if(a.kind==='coOwner'){
        commits.push(await policyLocks(db,tx,recipientUserId,a.recipientEmail));
        if((await accountPolicy(db,tx,recipientUserId,a.recipientEmail)).hasStaff)fail('failed-precondition','org_staff_account');
        const memberRef=db.collection('memberships').doc(`${recipientUserId}_${a.organizationId}`),existing=(await tx.get(memberRef)).data();
        if(a.controls.manageCoOwners==='off'){
         let recovery=false;
         for(const ownerId of sourceOwners){if(ownerId===recipientUserId)continue;const member=(await tx.get(db.collection('memberships').doc(`${ownerId}_${a.organizationId}`))).data();if(control(member,'manageCoOwners',sourceOwners.length)!=='off')recovery=true;}
         if(!recovery)fail('failed-precondition','agreement_last_owner');
        }
        if(existing?.ownershipAgreementId){const oldRef=db.collection('ownershipAgreements').doc(existing.ownershipAgreementId);if((await tx.get(oldRef)).exists)update(oldRef,{status:'superseded'});}
        save(memberRef,{...(existing??{}),ownerId:recipientUserId,organizationId:a.organizationId,email:a.recipientEmail,accessVersion:2,role:existing?.role==='owner'?'owner':'coOwner',roleGrants:a.grants,ownershipControls:a.controls,ownershipAgreementId:snap.id,status:'active',buildingScope:'all',buildingIds:[],permissionOverrides:{},updatedAt:now});
        update(source.ref,{governanceRevision:(source.data().governanceRevision??0)+1,companyId:companyOf(source.data())});status='active';
       }else if(a.kind==='removeCoOwner'){
        const targetRef=db.collection('memberships').doc(`${a.targetUserId}_${a.organizationId}`),m=(await tx.get(targetRef)).data();
        if(m?.role!=='coOwner')fail('failed-precondition','agreement_last_owner');
        commits.push(await policyLocks(db,tx,a.targetUserId,m.email));update(targetRef,{status:'revoked',revokedReason:'ownershipAgreement',updatedAt:now});update(source.ref,{governanceRevision:(source.data().governanceRevision??0)+1});status='completed';
       }else if(a.kind==='shareStaff'){
        commits.push(await policyLocks(db,tx,a.staffUserId,a.staffEmail));
        const home=(await tx.get(db.collection('memberships').doc(`${a.staffUserId}_${a.organizationId}`))).data();
        if(home?.status!=='active'||home.employerShareId||['owner','coOwner'].includes(home.role))fail('failed-precondition','agreement_staff_required');
        if((await accountPolicy(db,tx,a.staffUserId,a.staffEmail)).hasOwned)fail('failed-precondition','team_owner_account');
        const sharedRef=db.collection('staffShares').doc(shareKey(a.organizationId,a.targetOrganizationId,a.staffEmail)),oldShare=(await tx.get(sharedRef)).data();
        if(oldShare?.agreementId){const oldRef=db.collection('ownershipAgreements').doc(oldShare.agreementId);if((await tx.get(oldRef)).exists)update(oldRef,{status:'superseded'});}
        save(sharedRef,{organizationId:a.targetOrganizationId,sourceOrganizationId:a.organizationId,email:a.staffEmail,staffUserId:a.staffUserId,agreementId:snap.id,status:'active',expiresAt:Timestamp.fromMillis(now.toMillis()+a.durationDays*86400000),companies:a.companies,approvers:{[a.organizationId]:a.sourceOwners,[a.targetOrganizationId]:a.targetOwners}});status='active';
       }else if(a.kind==='transferOwnership'){
        const fromId=source.data().ownerTransferredTo??source.data().createdBy;
        const fromRef=db.collection('memberships').doc(`${fromId}_${a.organizationId}`),toRef=db.collection('memberships').doc(`${a.targetUserId}_${a.organizationId}`);
        const from=(await tx.get(fromRef)).data(),to=(await tx.get(toRef)).data();
        if(!ownerMember(to)||!ownerMember(from))fail('failed-precondition','agreement_changed');
        // Preserve each person's negotiated authority while moving the primary role.
        update(fromRef,{role:'coOwner',roleGrants:effectiveGrants(from),ownershipControls:Object.fromEntries(controlNames.map(k=>[k,control(from,k,sourceOwners.length)])),updatedAt:now});
        update(toRef,{role:'owner',roleGrants:effectiveGrants(to),updatedAt:now});
        update(source.ref,{ownerTransferredTo:a.targetUserId,companyId:companyOf(source.data()),governanceRevision:(source.data().governanceRevision??0)+1,ownerTransferredAt:now});status='completed';
       }else status='approved';
      }
      update(ref,{approvals,recipientUserId,status,updatedAt:now});result={status};
     }
    }
   }
   const eventId=hash([uid,d.operationId]);
   save(db.collection('governanceOperations').doc(eventId),{organizationId:auditOrg??null,actorId:uid,fingerprint,result,createdAt:now});
   save(db.collection('teamActivity').doc(eventId),{organizationId:auditOrg??null,actorId:uid,action:'ownershipAgreement_'+d.action,targetId:result.agreementId??d.agreementId,before:null,after:result,createdAt:now});
   for(const commit of commits)commit();for(const write of writes)write();return result;
  });
 };
}
module.exports={createGovernanceHandler};
