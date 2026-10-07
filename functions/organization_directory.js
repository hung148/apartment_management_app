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
    return db.runTransaction(async tx=>{
      const policy=await accountPolicy(db,tx,uid,request.auth.token?.email_verified===true?request.auth.token.email:'');
      let query=db.collection('memberships').where('ownerId','==',uid).orderBy('__name__');
      if(cursor)query=query.startAfter(cursor);
      const page=await tx.get(query.limit(51));
      const records=[];
      for(const membership of page.docs.slice(0,50)){
        const m=membership.data();
        // Waiting members (no supported role yet) still see the organization, marked waiting.
        const waitingStatus=m.status==='assignmentRequired';
        if((m.status!=='active'&&!waitingStatus)||typeof m.organizationId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(m.organizationId)||membership.id!==`${uid}_${m.organizationId}`)continue;
        const org=await tx.get(db.collection('organizations').doc(m.organizationId));
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
        if(policy.mode==='conflict')continue;
        if(!isOwner){
          try { await checkEmployer(db,tx,{uid,email:m.email,orgId:org.id,approvedBy:m.employerApprovedBy,primary:m.employerPrimary===true},(code,message)=>{throw new HttpsError(code,message);}); }
          catch(e){ if(!['team_other_employer','team_same_owner_approval'].includes(e.message))throw e; policy.staffConflict=e.message; continue; }
        }
        records.push({id:org.id,accessVersion:version,...(waiting?{waiting:true}:{}),...(isOwner&&!waiting?{owner:true}:{}),...serialize(Object.fromEntries(
          ['name','createdBy','createdAt','updatedAt'].filter(k=>data[k]!==undefined).map(k=>[k,data[k]])))});
      }
      return {accountPolicy:{...policy,canMerge:policy.organizationIds.length>1&&policy.hasOwned&&!policy.hasStaff&&!policy.deleting},records,nextCursor:page.docs.length>50?page.docs[49].id:null};
    });
  };
}
module.exports={createOrganizationDirectory};
