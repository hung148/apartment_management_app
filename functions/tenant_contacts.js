'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
function createTenantContactsHandler({db,Timestamp,HttpsError}){
 const fail=code=>{throw new HttpsError(code,'tenant_contact_'+code);};
 return async request=>{
  const uid=request.auth?.uid,d=request.data||{},write=d.action==='update',list=d.action==='list';
  if(!uid)fail('unauthenticated');
  const keys=['action','organizationId','buildingId',...(list?['cursor']:['tenantId']),...(write?['operationId','revision','fullName','phoneNumber']:[])];
  if(!['list','read','update'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||(!list&&!id(d.tenantId))||Object.keys(d).some(k=>!keys.includes(k))||(list&&d.cursor!=null&&!id(d.cursor)))fail('invalid-argument');
  if(write&&(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)||typeof d.fullName!=='string'||!d.fullName.trim()||d.fullName.length>160||typeof d.phoneNumber!=='string'||d.phoneNumber.length>80))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||!allows(member.data(),'manageLease',scope))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`));
   if(!building.exists||building.data().organizationId!==d.organizationId)fail('not-found');
   const projection=doc=>{const v=doc.data();return {id:doc.id,fullName:v.fullName??'',phoneNumber:v.phoneNumber??'',roomId:v.roomId??'',status:v.status??'unknown',canAddRoommate:v.isMainTenant===true&&v.status==='active'&&v.moveOutDate==null,canReadRentHistory:allows(member.data(),'overridePrices',scope),canEditRent:v.isMainTenant===true&&['active','suspended'].includes(v.status)&&v.moveOutDate==null&&allows(member.data(),'overridePrices',scope),mainTenantId:v.isMainTenant===false?v.mainTenantId??null:null};};
   if(list){
    let query=db.collection('tenants').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId).orderBy('__name__');
    if(d.cursor!=null)query=query.startAfter(d.cursor);
    const page=await tx.get(query.limit(26)),docs=page.docs.slice(0,25);
    return {records:docs.map(projection),nextCursor:page.size>25?docs.at(-1).id:null};
   }
   const ref=db.doc(`tenants/${d.tenantId}`),doc=await tx.get(ref),old=doc.data();
   if(!old||old.organizationId!==d.organizationId||old.buildingId!==d.buildingId)fail('not-found');
   const revision=`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
   if(!write)return {record:{...projection(doc),revision}};
   const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex'),key=hash(['tenantContacts',d.organizationId,uid,d.operationId]);
   const op=db.doc(`tenantContactOperations/${key}`),prior=await tx.get(op),fingerprint=hash(keys.map(k=>d[k]));
   if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
   if(d.revision!==revision)fail('aborted');
   const patch={fullName:d.fullName.trim(),phoneNumber:d.phoneNumber.trim()},now=Timestamp.now(),result={tenantId:d.tenantId};
   const changedFields=Object.keys(patch).filter(k=>patch[k]!==(old[k]??''));
   tx.update(ref,{...patch,updatedAt:now,updatedBy:uid});
   tx.create(op,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'tenant_contact_updated',targetId:d.tenantId,createdAt:now,before:null,after:{buildingId:d.buildingId,roomId:old.roomId??null,changedFields}});
   return result;
  });
 };
}
module.exports={createTenantContactsHandler};
