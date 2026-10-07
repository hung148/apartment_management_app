'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validDate}=require('./property_contract');
const {validZone}=require('./booking_settings');
const {propertyDate,propertyDayStart,leaseDatePolicy}=require('./lease_dates');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const revision=doc=>`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
// 2026-10-04 (Tom): CCCD and tạm trú for someone added later, like co-tenants
// typed with the lease. Optional, so older app versions keep working.
const text=(v,max)=>v==null||(typeof v==='string'&&v.length<=max);
const validPerson=p=>text(p.nationalId,30)&&(p.residenceRegistered==null||typeof p.residenceRegistered==='boolean')&&
 (p.residenceDate==null||(p.residenceRegistered===true&&validDate(p.residenceDate)));
function createTenantRoommatesHandler({db,Timestamp,HttpsError}){
 const fail=(code,key='roommate_'+code)=>{throw new HttpsError(code,key);};
 return async request=>{
  const uid=request.auth?.uid,d=request.data||{},write=d.action==='create';
  if(!uid)fail('unauthenticated');
  const keys=['action','organizationId','buildingId','mainTenantId',...(write?['operationId','mainRevision','roomRevision','timeZone','fullName','phoneNumber','moveInDate','backdateReason','nationalId','residenceRegistered','residenceDate']:[])];
  if(!['prepare','create'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||!id(d.mainTenantId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
  if(write&&(!id(d.operationId)||![d.mainRevision,d.roomRevision].every(v=>typeof v==='string'&&/^\d+:\d+$/.test(v))||!validZone(d.timeZone)||typeof d.fullName!=='string'||!d.fullName.trim()||d.fullName.length>160||typeof d.phoneNumber!=='string'||d.phoneNumber.length>80||!validDate(d.moveInDate)||typeof d.backdateReason!=='string'||d.backdateReason.length>1000||!validPerson(d)))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),membership=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),member=membership.data();
   if(!org.exists||org.data().accessVersion!==2||!allows(member,'manageLease',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId}))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),main=await tx.get(db.doc(`tenants/${d.mainTenantId}`)),m=main.data();
   if(!building.exists||building.data().organizationId!==d.organizationId||!m||m.organizationId!==d.organizationId||m.buildingId!==d.buildingId)fail('not-found');
   const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex'),key=write?hash(['roommate',d.organizationId,uid,d.operationId]):null,op=write?db.doc(`tenantRoommateOperations/${key}`):null,prior=write?await tx.get(op):null,fingerprint=write?hash(keys.map(k=>d[k])):null;
   if(prior?.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
   if(m.isMainTenant!==true||m.status!=='active'||m.moveOutDate!=null||!id(m.roomId)||!Number.isFinite(m.moveInDate?.toMillis?.()))fail('failed-precondition','roommate_main_unavailable');
   const roomRef=db.doc(`rooms/${m.roomId}`),room=await tx.get(roomRef),r=room.data();
   if(!r||r.organizationId!==d.organizationId||r.buildingId!==d.buildingId)fail('not-found');
   const zone=building.data().timeZone,now=Timestamp.now(),currency=m.currency??'VND';
   if(!validZone(zone))fail('failed-precondition','lease_property_timezone_required');
   if(!['VND','USD'].includes(currency))fail('failed-precondition');
   const earliestDate=propertyDate(m.moveInDate.toMillis(),zone),today=propertyDate(now.toMillis(),zone);
   if(!write)return {record:{mainName:m.fullName??'',mainRevision:revision(main),roomRevision:revision(room),roomNumber:r.roomNumber??'',timeZone:zone,today,earliestDate,canBackdate:allows(member,'backdateRecords',{organizationId:d.organizationId,userId:uid})}};
   if(d.mainRevision!==revision(main)||d.roomRevision!==revision(room)||d.timeZone!==zone)fail('aborted');
   const dayStart=propertyDayStart(d.moveInDate,zone);
   if(dayStart===null||d.moveInDate<earliestDate)fail('invalid-argument','roommate_before_main');
   // Older main tenancies can start midway through a day. A date-only roommate
   // entry on that same date starts at the parent's actual instant, never before.
   const start=Math.max(dayStart,m.moveInDate.toMillis()),policy=leaseDatePolicy({moveInMillis:start,nowMillis:now.toMillis(),timeZone:zone,canBackdate:allows(member,'backdateRecords',{organizationId:d.organizationId,userId:uid}),reason:d.backdateReason});
   if(policy.error)fail(policy.error,policy.key);
   const bookings=await tx.get(db.collection('bookings').where('roomId','==',m.roomId));
   if(bookings.docs.some(doc=>{const b=doc.data();return ['pending','confirmed','checkedIn'].includes(b.status)&&(b.endTime?.toMillis?.()??Infinity)>start;}))fail('already-exists','booking_conflict');
   const tenantId=`roommate_${key}`,result={tenantId},moveIn=Timestamp.fromMillis(start);
   tx.create(db.doc(`tenants/${tenantId}`),{organizationId:d.organizationId,buildingId:d.buildingId,roomId:m.roomId,mainTenantId:d.mainTenantId,isMainTenant:false,fullName:d.fullName.trim(),phoneNumber:d.phoneNumber.trim(),status:'active',moveInDate:moveIn,moveInLocalDate:d.moveInDate,moveInTimeZone:zone,moveOutDate:null,currency,
    ...(d.nationalId!==undefined||d.residenceRegistered!==undefined?{nationalId:typeof d.nationalId==='string'&&d.nationalId.trim()?d.nationalId.trim():null,residenceRegistered:d.residenceRegistered===true,residenceRegisteredLocalDate:d.residenceRegistered===true?d.residenceDate??null:null}:{}),
    createdAt:now,updatedAt:now,createdBy:uid,updatedBy:uid});
   tx.update(roomRef,{bookingRevision:(r.bookingRevision??0)+1});
   tx.create(op,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
   if(policy.backdated)tx.create(db.doc(`leaseDateCorrections/${key}`),{organizationId:d.organizationId,buildingId:d.buildingId,tenantId,actorId:uid,createdAt:now,previousMoveInDate:null,moveInDate:moveIn,localDate:d.moveInDate,timeZone:zone,reason:policy.reason});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'roommate_created',targetId:tenantId,createdAt:now,before:null,after:{buildingId:d.buildingId,roomId:m.roomId,mainTenantId:d.mainTenantId,status:'active'}});
   return result;
  });
 };
}
module.exports={createTenantRoommatesHandler};
