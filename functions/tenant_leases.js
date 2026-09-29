'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validZone}=require('./booking_settings');
const {validDate}=require('./property_contract');
const {propertyDate,propertyDayStart,leaseDatePolicy}=require('./lease_dates');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const revision=doc=>`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
function createTenantLeasesHandler({db,Timestamp,HttpsError}){
 const fail=(code,key='lease_'+code)=>{throw new HttpsError(code,key);};
 return async request=>{
  const uid=request.auth?.uid,d=request.data||{},create=d.action==='create',list=d.action==='rooms';
  if(!uid)fail('unauthenticated');
  const keys=['action','organizationId','buildingId',...(list?['cursor']:['roomId']),...(create?['operationId','roomRevision','timeZone','currency','fullName','phoneNumber','moveInDate','contractEndDate','rentMinor','backdateReason']:[])];
  if(!['rooms','prepare','create'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||(!list&&!id(d.roomId))||Object.keys(d).some(k=>!keys.includes(k))||(list&&d.cursor!=null&&!id(d.cursor)))fail('invalid-argument');
  if(create&&(!id(d.operationId)||typeof d.roomRevision!=='string'||!/^\d+:\d+$/.test(d.roomRevision)||!validZone(d.timeZone)||!['VND','USD'].includes(d.currency)||typeof d.fullName!=='string'||!d.fullName.trim()||d.fullName.length>160||typeof d.phoneNumber!=='string'||d.phoneNumber.length>80||!validDate(d.moveInDate)||(d.contractEndDate!==null&&(!validDate(d.contractEndDate)||d.contractEndDate<d.moveInDate))||!Number.isSafeInteger(d.rentMinor)||d.rentMinor<=0||d.rentMinor>1e12||typeof d.backdateReason!=='string'||d.backdateReason.length>1000))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),membership=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),member=membership.data(),scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||!allows(member,'manageLease',scope))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`));
   if(!building.exists||building.data().organizationId!==d.organizationId)fail('not-found');
   if(list){
    let q=db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId).orderBy('__name__');
    if(d.cursor!=null)q=q.startAfter(d.cursor);
    const page=await tx.get(q.limit(26)),rows=page.docs.slice(0,25);
    return {records:rows.map(doc=>({id:doc.id,roomNumber:doc.data().roomNumber??'',monthly:['monthly','both'].includes(doc.data().rentalMode??'monthly')})),nextCursor:page.size>25?rows.at(-1).id:null};
   }
   const roomRef=db.doc(`rooms/${d.roomId}`),room=await tx.get(roomRef),r=room.data();
   if(!r||r.organizationId!==d.organizationId||r.buildingId!==d.buildingId)fail('not-found');
   const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex'),key=create?hash(['tenantLease',d.organizationId,uid,d.operationId]):null;
   const op=create?db.doc(`tenantLeaseOperations/${key}`):null,prior=create?await tx.get(op):null,fingerprint=create?hash(keys.map(k=>d[k])):null;
   if(prior?.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
   const zone=building.data().timeZone,currency=r.currency??'VND',now=Timestamp.now();
   if(!validZone(zone))fail('failed-precondition','lease_property_timezone_required');
   if(!['VND','USD'].includes(currency)||!['monthly','both'].includes(r.rentalMode??'monthly'))fail('failed-precondition','lease_room_not_monthly');
   if(!create)return {record:{roomNumber:r.roomNumber??'',roomRevision:revision(room),currency,timeZone:zone,today:propertyDate(now.toMillis(),zone),canBackdate:['owner','administrator'].includes(member.role)}};
   if(d.roomRevision!==revision(room)||d.currency!==currency||d.timeZone!==zone)fail('aborted');
   const start=propertyDayStart(d.moveInDate,zone),end=d.contractEndDate===null?null:propertyDayStart(d.contractEndDate,zone);
   if(start===null||(d.contractEndDate!==null&&end===null))fail('invalid-argument');
   const policy=leaseDatePolicy({moveInMillis:start,nowMillis:now.toMillis(),timeZone:zone,role:member.role,reason:d.backdateReason});
   if(policy.error)fail(policy.error,policy.key);
   // The lease is open-ended occupancy until an explicit move-out. Roommates
   // cannot be silently displaced, including legacy rows missing main-tenant flags.
   const tenants=await tx.get(db.collection('tenants').where('roomId','==',d.roomId));
   for(const doc of tenants.docs){const t=doc.data();if((['active','suspended'].includes(t.status)||t.moveOutDate)&&(t.moveOutDate?.toMillis?.()??Infinity)>start)fail('already-exists','lease_room_occupied');}
   const historical=await tx.get(db.collection('leaseOccupancy').where('roomId','==',d.roomId));
   if(historical.docs.some(v=>v.data().end.toMillis()>start))fail('already-exists','lease_room_occupied');
   const bookings=await tx.get(db.collection('bookings').where('roomId','==',d.roomId));
   for(const doc of bookings.docs){const b=doc.data();if(['pending','confirmed','checkedIn'].includes(b.status)&&(b.endTime?.toMillis?.()??Infinity)>start)fail('already-exists','booking_conflict');}
   const tenantId=`lease_${key}`,result={tenantId},moveIn=Timestamp.fromMillis(start);
   tx.create(db.doc(`tenants/${tenantId}`),{organizationId:d.organizationId,buildingId:d.buildingId,roomId:d.roomId,fullName:d.fullName.trim(),phoneNumber:d.phoneNumber.trim(),status:'active',isMainTenant:true,mainTenantId:null,moveInDate:moveIn,moveInLocalDate:d.moveInDate,moveInTimeZone:zone,moveOutDate:null,contractStartDate:moveIn,contractEndDate:end===null?null:Timestamp.fromMillis(end),contractEndLocalDate:d.contractEndDate,monthlyRent:d.rentMinor/(currency==='USD'?100:1),monthlyRentMinor:d.rentMinor,currency,createdAt:now,updatedAt:now,createdBy:uid,updatedBy:uid});
   tx.update(roomRef,{bookingRevision:(r.bookingRevision??0)+1});
   tx.create(op,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
   if(policy.backdated)tx.create(db.doc(`leaseDateCorrections/${key}`),{organizationId:d.organizationId,buildingId:d.buildingId,tenantId,actorId:uid,createdAt:now,previousMoveInDate:null,moveInDate:moveIn,localDate:d.moveInDate,timeZone:zone,reason:policy.reason});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'lease_create',targetId:tenantId,createdAt:now,before:null,after:{buildingId:d.buildingId,roomId:d.roomId,status:'active',moveInDate:moveIn,currency}});
   return result;
  });
 };
}
module.exports={createTenantLeasesHandler};
