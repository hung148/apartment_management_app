'use strict';
const {roles}=require('./team_access');
const {serialize}=require('./team_read');

// Dashboard projection only. Never return bank details or shared join codes.
function createOrganizationDirectory({db,HttpsError}) {
  return async request=>{
    const uid=request.auth?.uid;
    if(!uid)throw new HttpsError('unauthenticated','team_sign_in_required');
    const cursor=request.data?.cursor;
    if(cursor!==undefined&&(typeof cursor!=='string'||!/^[A-Za-z0-9_-]{1,256}$/.test(cursor)))throw new HttpsError('invalid-argument','team_invalid_page');
    return db.runTransaction(async tx=>{
      let query=db.collection('memberships').where('ownerId','==',uid).orderBy('__name__');
      if(cursor)query=query.startAfter(cursor);
      const page=await tx.get(query.limit(51));
      const records=[];
      for(const membership of page.docs.slice(0,50)){
        const m=membership.data();
        if(m.status!=='active'||typeof m.organizationId!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(m.organizationId)||membership.id!==`${uid}_${m.organizationId}`)continue;
        const org=await tx.get(db.collection('organizations').doc(m.organizationId));
        if(!org.exists)continue;
        const data=org.data(),version=data.accessVersion??1;
        if(version===2 && (m.accessVersion!==2||!Object.hasOwn(roles,m.role)||!['all','selected'].includes(m.buildingScope)))continue;
        if(version!==1&&version!==2)continue;
        records.push({id:org.id,accessVersion:version,...serialize(Object.fromEntries(
          ['name','createdBy','createdAt','updatedAt'].filter(k=>data[k]!==undefined).map(k=>[k,data[k]])))});
      }
      return {records,nextCursor:page.docs.length>50?page.docs[49].id:null};
    });
  };
}
module.exports={createOrganizationDirectory};
