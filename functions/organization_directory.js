'use strict';
const {hasRole}=require('./team_access');
const {accountPolicy,checkEmployer}=require('./account_policy');
const {serialize}=require('./team_read');

// Dashboard projection only. Never return bank details or shared join codes.
function createOrganizationDirectory({db,HttpsError}) {
  return async request=>{
    const uid=request.auth?.uid;
    if(!uid)throw new HttpsError('unauthenticated','team_sign_in_required');
    const cursor=request.data?.cursor;
    if(cursor!==undefined&&(typeof cursor!=='string'||!/^[A-Za-z0-9_-]{1,256}$/.test(cursor)))throw new HttpsError('invalid-argument','team_invalid_page');
    // Speed (2026-10-09): the first page also says whether invitations wait to
    // be claimed for this account's verified email, so the app asks to claim
    // only then (one call at start instead of two). Read beside the list.
    const token=request.auth.token??{},email=typeof token.email==='string'?token.email.trim().toLowerCase():'';
    const invitations=cursor!==undefined?null:!email?{pending:false,needsVerifiedEmail:false}:token.email_verified!==true?Promise.resolve({pending:false,needsVerifiedEmail:true}):
      db.collection('teamInvitations').where('email','==',email).where('status','==','pending').limit(20).get().then(q=>({needsVerifiedEmail:false,
        pending:q.docs.some(d=>{const v=d.data();return !(v.expiresAt!=null&&!(v.expiresAt.toMillis?.()>Date.now()))&&typeof v.organizationId==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v.organizationId);})}));
    invitations?.catch?.(()=>{});
    // Speed (2026-10-10): a read-only transaction (it never writes: no locks,
    // no commit wait), the account check and the membership page read
    // together, and the organizations read together. Same checks, same order
    // of records, same consistent snapshot.
    const listed=await db.runTransaction(async tx=>{
      let query=db.collection('memberships').where('ownerId','==',uid).orderBy('__name__');
      if(cursor)query=query.startAfter(cursor);
      const [policy,page]=await Promise.all([
        accountPolicy(db,tx,uid,request.auth.token?.email_verified===true?request.auth.token.email:''),
        tx.get(query.limit(51)),
      ]);
      const records=[];
      // Rows that can never be listed are skipped before any read, as before.
      const rows=page.docs.slice(0,50).filter(membership=>{
        const m=membership.data(),waitingStatus=m.status==='assignmentRequired';
        return !((m.status!=='active'&&!waitingStatus)||typeof m.organizationId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(m.organizationId)||membership.id!==`${uid}_${m.organizationId}`);
      });
      // An account in conflict lists nothing (every row was skipped below).
      const orgs=policy.mode==='conflict'?[]:await Promise.all(rows.map(r=>tx.get(db.collection('organizations').doc(r.data().organizationId))));
      for(let i=0;i<orgs.length;i++){
        const m=rows[i].data(),org=orgs[i];
        // Waiting members (no supported role yet) still see the organization, marked waiting.
        const waitingStatus=m.status==='assignmentRequired';
        // Closed organizations disappear from every dashboard immediately.
        if(!org.exists||org.data().closedAt)continue;
        const data=org.data(),version=data.accessVersion??1;
        if(version!==1&&version!==2)continue;
        let waiting=false;
        if(m.role==='coOwner'||m.employerShareId)continue;
        if(version===2){
          if(m.accessVersion!==2)continue;
          waiting=waitingStatus||!hasRole(m);
          if(!waiting&&!['all','selected'].includes(m.buildingScope))continue;
        }else if(waitingStatus)continue;
        const isOwner=['owner','coOwner'].includes(m.role)||(version===1&&(data.ownerTransferredTo??data.createdBy)===uid);
        if(!isOwner){
          try { await checkEmployer(db,tx,{uid,email:m.email,orgId:org.id,approvedBy:m.employerApprovedBy,primary:m.employerPrimary===true},(code,message)=>{throw new HttpsError(code,message);}); }
          catch(e){ if(!['team_other_employer','team_same_owner_approval'].includes(e.message))throw e; policy.staffConflict=e.message; continue; }
        }
        records.push({id:org.id,accessVersion:version,...(waiting?{waiting:true}:{}),...(isOwner&&!waiting?{owner:true}:{}),...serialize(Object.fromEntries(
          ['name','createdBy','createdAt','updatedAt'].filter(k=>data[k]!==undefined).map(k=>[k,data[k]])))});
      }
      return {accountPolicy:{...policy,canMerge:policy.organizationIds.length>1&&policy.hasOwned&&!policy.hasStaff&&!policy.deleting},records,nextCursor:page.docs.length>50?page.docs[49].id:null};
    },{readOnly:true});
    return invitations===null?listed:{...listed,invitations:await invitations};
  };
}
module.exports={createOrganizationDirectory};
