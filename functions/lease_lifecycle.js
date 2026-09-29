'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validDate}=require('./property_contract');
const {validZone}=require('./booking_settings');
const {propertyDate,propertyDayStart}=require('./lease_dates');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const revision=d=>`${d.updateTime.seconds}:${d.updateTime.nanoseconds}`;
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const active=t=>['active','suspended'].includes(t.status)&&t.moveOutDate==null;
function createLeaseLifecycleHandler({db,Timestamp,HttpsError}){
 const fail=(code,key='lease_lifecycle_'+code)=>{throw new HttpsError(code,key);};
 return async request=>{
  const d=request.data||{},uid=request.auth?.uid,write=['terms','move','moveOut'].includes(d.action);
  if(!uid)fail('unauthenticated');
  const keys=['action','organizationId','buildingId','tenantId',...(write?['operationId','revision','timeZone','reason']:[]),...(d.action==='terms'?['contractEndDate']:[]),...(['move','moveOut'].includes(d.action)?['effectiveDate']:[]),...(d.action==='move'?['destinationRoomId','destinationMainTenantId']:[])];
  if(!['read','terms','move','moveOut','history','destinations'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||!id(d.tenantId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
  if(write&&(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)||!validZone(d.timeZone)||typeof d.reason!=='string'||!d.reason.trim()||d.reason.length>1000))fail('invalid-argument');
  if(d.action==='terms'&&d.contractEndDate!==null&&!validDate(d.contractEndDate))fail('invalid-argument');
  if(['move','moveOut'].includes(d.action)&&!validDate(d.effectiveDate))fail('invalid-argument');
  if(d.action==='move'&&(!id(d.destinationRoomId)||(d.destinationMainTenantId!==null&&!id(d.destinationMainTenantId))))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),membership=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),m=membership.data();
   const scope=buildingId=>({organizationId:d.organizationId,userId:uid,buildingId});
   if(!org.exists||org.data().accessVersion!==2||!allows(m,'manageLease',scope(d.buildingId)))fail('permission-denied');
   const key=write?hash(['leaseLifecycle',d.organizationId,uid,d.operationId]):null,op=write?db.doc(`leaseLifecycleOperations/${key}`):null,prior=write?await tx.get(op):null,fingerprint=hash(keys.map(k=>d[k]));
   if(prior?.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');if(!allows(m,'manageLease',scope(prior.data().result.buildingId)))fail('permission-denied');return prior.data().result;}
   const ref=db.doc(`tenants/${d.tenantId}`),doc=await tx.get(ref),t=doc.data(),building=await tx.get(db.doc(`buildings/${d.buildingId}`));
   if(!t||t.organizationId!==d.organizationId||t.buildingId!==d.buildingId||!building.exists||building.data().organizationId!==d.organizationId)fail('not-found');
   if(d.action==='history'){
    const history=await tx.get(ref.collection('leaseHistory').orderBy('createdAt','desc').limit(100));
    return {records:history.docs.map(v=>{const x=v.data();return {id:v.id,action:x.action,actorId:x.actorId,createdAt:x.createdAt.toDate().toISOString(),reason:x.reason,before:x.before,after:x.after};})};
   }
   const zone=building.data().timeZone,now=Timestamp.now(),today=propertyDate(now.toMillis(),zone);
   if(!validZone(zone)||!today)fail('failed-precondition','lease_property_timezone_required');
   const linked=await tx.get(db.collection('tenants').where('mainTenantId','==',d.tenantId));
   const roommates=linked.docs.filter(v=>active(v.data())).map(v=>({id:v.id,fullName:v.data().fullName??'',roomId:v.data().roomId}));
   const start=t.occupancyStartDate??t.moveInDate,startMillis=start?.toMillis?.(),startDate=Number.isFinite(startMillis)?propertyDate(startMillis,zone):null;
   if(!startDate)fail('failed-precondition');
   if(d.action==='read')return {record:{fullName:t.fullName??'',roomId:t.roomId,isMainTenant:t.isMainTenant===true,status:t.status,revision:revision(doc),timeZone:zone,today,startDate,contractEndDate:t.contractEndLocalDate??(t.contractEndDate?propertyDate(t.contractEndDate.toMillis(),zone):null),roommates,canBackdate:['owner','administrator'].includes(m.role)}};
   if(d.action==='destinations'){
    const rooms=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId));
    const mains=await tx.get(db.collection('tenants').where('organizationId','==',d.organizationId));
    return {records:rooms.docs.filter(v=>v.id!==t.roomId&&allows(m,'manageLease',scope(v.data().buildingId))&&['monthly','both'].includes(v.data().rentalMode??'monthly')).map(v=>({id:v.id,buildingId:v.data().buildingId,roomNumber:v.data().roomNumber??v.id,mainTenants:mains.docs.filter(x=>x.data().roomId===v.id&&x.data().isMainTenant===true&&active(x.data())).map(x=>({id:x.id,fullName:x.data().fullName??''}))}))};
   }
   if(!active(t))fail('failed-precondition');
   if(d.revision!==revision(doc)||d.timeZone!==zone)fail('aborted');
   const summary=v=>({buildingId:v.buildingId,roomId:v.roomId,status:v.status,mainTenantId:v.mainTenantId??null,contractEndDate:v.contractEndLocalDate??null,occupancyStartDate:v.occupancyStartDate?.toDate?.().toISOString()??v.moveInDate?.toDate?.().toISOString()??null,moveOutDate:v.moveOutDate?.toDate?.().toISOString()??null});
   let patch={},room,source,destinationBuilding,at;
   if(d.action==='terms'){
    if(t.isMainTenant!==true)fail('failed-precondition');
    if(d.contractEndDate!==null){
     if(d.contractEndDate<propertyDate(t.moveInDate.toMillis(),zone))fail('invalid-argument');
     if(d.contractEndDate<today&&!['owner','administrator'].includes(m.role))fail('permission-denied');
     const end=propertyDayStart(d.contractEndDate,zone);if(end===null)fail('invalid-argument');
     patch={contractEndDate:Timestamp.fromMillis(end),contractEndLocalDate:d.contractEndDate,contractEndTimeZone:zone};
    }else patch={contractEndDate:null,contractEndLocalDate:null,contractEndTimeZone:zone};
   }else{
    // A move is a recorded actual event. Future occupancy changes need a separate scheduling workflow.
    if(d.effectiveDate>today||d.effectiveDate<startDate)fail('invalid-argument','lease_actual_date_required');
    if(d.effectiveDate<today&&!['owner','administrator'].includes(m.role))fail('permission-denied');
    at=propertyDayStart(d.effectiveDate,zone);if(at===null||at<=startMillis)fail('invalid-argument');
    if(t.isMainTenant===true&&roommates.length)fail('failed-precondition','lease_handle_roommates_first');
    source=await tx.get(db.doc(`rooms/${t.roomId}`));if(!source.exists||source.data().organizationId!==d.organizationId||source.data().buildingId!==d.buildingId)fail('failed-precondition');
    if(d.action==='moveOut')patch={moveOutDate:Timestamp.fromMillis(at),moveOutLocalDate:d.effectiveDate,moveOutTimeZone:zone,status:'moveOut'};
    else{
     room=await tx.get(db.doc(`rooms/${d.destinationRoomId}`));const r=room.data();
     if(!r||r.organizationId!==d.organizationId||!allows(m,'manageLease',scope(r.buildingId)))fail('permission-denied');
     if(room.id===t.roomId||!['monthly','both'].includes(r.rentalMode??'monthly')||(r.currency??'VND')!==(t.currency??'VND'))fail('failed-precondition');
     destinationBuilding=await tx.get(db.doc(`buildings/${r.buildingId}`));
     if(!destinationBuilding.exists||destinationBuilding.data().organizationId!==d.organizationId||!validZone(destinationBuilding.data().timeZone))fail('failed-precondition');
     const occupants=await tx.get(db.collection('tenants').where('roomId','==',room.id));
     let parent;
     if(t.isMainTenant===false){
      if(!d.destinationMainTenantId)fail('invalid-argument');parent=occupants.docs.find(v=>v.id===d.destinationMainTenantId)?.data();
      if(!parent||parent.organizationId!==d.organizationId||parent.isMainTenant!==true||!active(parent)||(parent.occupancyStartDate??parent.moveInDate).toMillis()>at)fail('failed-precondition');
     }else if(d.destinationMainTenantId!==null)fail('invalid-argument');
     if(t.isMainTenant===true&&occupants.docs.some(v=>{const x=v.data();return (x.moveOutDate?.toMillis?.()??(['active','suspended'].includes(x.status)?Infinity:0))>at;}))fail('already-exists','lease_room_occupied');
     const historical=await tx.get(db.collection('leaseOccupancy').where('roomId','==',room.id));
     if(t.isMainTenant===true&&historical.docs.some(v=>v.data().end.toMillis()>at))fail('already-exists','lease_room_occupied');
     const bookings=await tx.get(db.collection('bookings').where('roomId','==',room.id));
     if(bookings.docs.some(v=>['pending','confirmed','checkedIn'].includes(v.data().status)&&v.data().endTime.toMillis()>at))fail('already-exists','booking_conflict');
     patch={buildingId:r.buildingId,roomId:room.id,occupancyStartDate:Timestamp.fromMillis(at),mainTenantId:t.isMainTenant===false?d.destinationMainTenantId:null};
    }
   }
   const next={...t,...patch},result={tenantId:d.tenantId,buildingId:next.buildingId,roomId:next.roomId};
   tx.update(ref,{...patch,updatedAt:now,updatedBy:uid});
   if(source){
    tx.update(source.ref,{bookingRevision:(source.data().bookingRevision??0)+1});
    if(room)tx.update(room.ref,{bookingRevision:(room.data().bookingRevision??0)+1});
    tx.create(db.doc(`leaseOccupancy/${key}`),{organizationId:d.organizationId,tenantId:d.tenantId,buildingId:d.buildingId,roomId:t.roomId,start:Timestamp.fromMillis(startMillis),end:Timestamp.fromMillis(at),timeZone:zone,isMainTenant:t.isMainTenant===true,createdAt:now});
   }
   tx.create(op,{organizationId:d.organizationId,actorId:uid,createdAt:now,fingerprint,result});
   tx.create(ref.collection('leaseHistory').doc(key),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:d.action,reason:d.reason.trim(),before:summary(t),after:summary(next)});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'lease_'+d.action,targetId:d.tenantId,before:{buildingId:t.buildingId,roomId:t.roomId},after:{buildingId:next.buildingId,roomId:next.roomId,status:next.status}});
   return result;
  });
 };
}
module.exports={createLeaseLifecycleHandler};
