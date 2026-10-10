'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {propertyDate}=require('./lease_dates');
const {validZone}=require('./booking_settings');
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
   // CCCD numbers: full only with "Xem số CCCD" (readGuestIds), else masked.
   const seeIds=allows(member.data(),'readGuestIds',scope),idText=v=>typeof v==='string'&&v?(seeIds?v:(v.length>4?`•••• ${v.slice(-4)}`:'••••')):'';
   // Lease details (B3) for the tenant page; names instead of internal IDs.
   const details=(v,names,staff)=>({isMainTenant:v.isMainTenant===true,mainTenantName:v.isMainTenant===false?names.get(v.mainTenantId)??'':'',
    moveInLocalDate:v.moveInLocalDate??'',contractEndLocalDate:v.contractEndLocalDate??'',currency:v.currency??'VND',monthlyRentMinor:v.monthlyRentMinor??null,
    nationalId:idText(v.nationalId),residenceRegistered:v.residenceRegistered===true,residenceRegisteredLocalDate:v.residenceRegisteredLocalDate??'',
    paymentPeriodMonths:v.paymentPeriodMonths??null,paymentDueDay:v.paymentDueDay??null,periodRentMinor:v.periodRentMinor??null,periodRentOverride:v.periodRentOverride&&typeof v.periodRentOverride==='object'&&Number.isSafeInteger(v.periodRentOverride.totalMinor)?{totalMinor:v.periodRentOverride.totalMinor,calculatedTotalMinor:v.periodRentOverride.calculatedTotalMinor??null,reason:String(v.periodRentOverride.reason??''),byName:String(v.periodRentOverride.byName??''),at:v.periodRentOverride.at?.toDate?.().toISOString()??null}:null,
    depositMinor:v.depositMinor??null,depositMethod:v.depositMethod??null,depositAccountLabel:v.depositAccountLabel??'',depositNote:v.depositNote??'',
    staffName:staff.get(v.staffInChargeId)??'',canReadIds:seeIds,
    // 2026-10-04: lease surcharges and the stay status pill.
    surcharges:Array.isArray(v.surcharges)?v.surcharges:[],moveOutLocalDate:v.moveOutDate?.toMillis?propertyDate(v.moveOutDate.toMillis(),zone)??'':'',
    stayStatus:stayStatus(v),contractEnded:typeof v.contractEndLocalDate==='string'&&!!today&&v.contractEndLocalDate<today&&!v.settlementId});
   const zone=building.data().timeZone,nowMillis=Timestamp.now().toMillis(),today=validZone(zone)?propertyDate(nowMillis,zone):null;
   const stayStatus=v=>{
    if(v.status==='moveOut'||(v.moveOutDate?.toMillis&&v.moveOutDate.toMillis()<=nowMillis))return 'checkedOut';
    if(today&&typeof v.moveInLocalDate==='string'&&v.moveInLocalDate>today)return (v.depositMinor??0)>0?'deposited':'notCheckedIn';
    return 'staying';
   };
   const nameMaps=async(docs)=>{
    const names=new Map(docs.map(x=>[x.id,String(x.data().fullName??'')]));
    for(const m of new Set(docs.map(x=>x.data()).filter(v=>v.isMainTenant===false&&id(v.mainTenantId)&&!names.has(v.mainTenantId)).map(v=>v.mainTenantId))){
     const main=await tx.get(db.doc(`tenants/${m}`));if(main.exists&&main.data().organizationId===d.organizationId)names.set(m,String(main.data().fullName??''));
    }
    const staffDocs=await tx.get(db.collection('staffProfiles').where('organizationId','==',d.organizationId));
    return {names,staff:new Map(staffDocs.docs.map(x=>[x.id,String(x.data().displayName??'')]))};
   };
   const projection=(doc,numbers=new Map(),maps={names:new Map(),staff:new Map()})=>{const v=doc.data();return {...details(v,maps.names,maps.staff),id:doc.id,fullName:v.fullName??'',phoneNumber:v.phoneNumber??'',roomId:v.roomId??'',roomNumber:numbers.get(v.roomId)??'',status:v.status??'unknown',canAddRoommate:v.isMainTenant===true&&v.status==='active'&&v.moveOutDate==null,canReadRentHistory:allows(member.data(),'overridePrices',scope),canEditRent:v.isMainTenant===true&&['active','suspended'].includes(v.status)&&v.moveOutDate==null&&allows(member.data(),'overridePrices',scope),mainTenantId:v.isMainTenant===false?v.mainTenantId??null:null,canBill:v.isMainTenant===true&&allows(member.data(),'collectPayments',scope),canSettle:v.isMainTenant===true&&!v.settlementId&&((['active','suspended'].includes(v.status)&&v.moveOutDate==null)||(v.status==='moveOut'&&v.moveOutDate!=null))&&allows(member.data(),'manageLease',scope)&&allows(member.data(),'collectPayments',scope),settled:!!v.settlementId};};
   if(list){
    let query=db.collection('tenants').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId).orderBy('__name__');
    if(d.cursor!=null)query=query.startAfter(d.cursor);
    const page=await tx.get(query.limit(26)),docs=page.docs.slice(0,25);
    // Room numbers so the list never shows internal room IDs.
    const rooms=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
    const numbers=new Map(rooms.docs.map(r=>[r.id,String(r.data().roomNumber??'')]));
    const maps=await nameMaps(docs);
    return {records:docs.map(x=>projection(x,numbers,maps)),nextCursor:page.size>25?docs.at(-1).id:null};
   }
   const ref=db.doc(`tenants/${d.tenantId}`),doc=await tx.get(ref),old=doc.data();
   if(!old||old.organizationId!==d.organizationId||old.buildingId!==d.buildingId)fail('not-found');
   const revision=`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
   if(!write){
    const maps=await nameMaps([doc]),room=id(old.roomId)?await tx.get(db.doc(`rooms/${old.roomId}`)):null;
    const numbers=new Map(room?.exists&&room.data().organizationId===d.organizationId?[[old.roomId,String(room.data().roomNumber??'')]]:[]);
    // 2026-10-04 (Tom): the people living with a main tenant, on its page.
    let roommates=[];
    if(old.isMainTenant===true){
     const linked=await tx.get(db.collection('tenants').where('mainTenantId','==',d.tenantId));
     roommates=linked.docs.map(v=>({id:v.id,...v.data()})).filter(v=>v.organizationId===d.organizationId&&['active','suspended'].includes(v.status)&&!v.moveOutDate)
      .map(v=>({id:v.id,fullName:v.fullName??'',moveInLocalDate:v.moveInLocalDate??''})).sort((a,b)=>a.moveInLocalDate.localeCompare(b.moveInLocalDate)||a.fullName.localeCompare(b.fullName));
    }
    return {record:{...projection(doc,numbers,maps),roommates,revision}};
   }
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
