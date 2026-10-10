'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validZone}=require('./booking_settings');
const {roomBlocked}=require('./technical_problems');
const {validDate}=require('./property_contract');
const {propertyDate,propertyDayStart,leaseDatePolicy}=require('./lease_dates');
const {meterId}=require('./utility_invoice');
const {addTariff}=require('./utility_tariffs');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const revision=doc=>`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
// B3 (2026-10-01) lease details. All optional, so older app versions keep working.
const DETAILS=['nationalId','residenceRegistered','residenceDate','coTenants','staffInChargeId','periodMonths','dueDay','periodAmountMinor','depositMinor','depositMethod','depositAccountId','depositNote'];
const plain=v=>!!v&&typeof v==='object'&&!Array.isArray(v);
const text=(v,max)=>v==null||(typeof v==='string'&&v.length<=max);
// One person's papers: CCCD and temporary residence (tạm trú) registration.
const validPerson=p=>text(p.nationalId,30)&&(p.residenceRegistered==null||typeof p.residenceRegistered==='boolean')&&
 (p.residenceDate==null||(p.residenceRegistered===true&&validDate(p.residenceDate)));
function validDetails(d){
 if(!validPerson(d))return false;
 if(d.coTenants!=null&&(!Array.isArray(d.coTenants)||d.coTenants.length>10||d.coTenants.some(c=>!plain(c)||
  Object.keys(c).some(k=>!['fullName','phoneNumber','nationalId','residenceRegistered','residenceDate'].includes(k))||
  typeof c.fullName!=='string'||!c.fullName.trim()||c.fullName.length>160||!text(c.phoneNumber,80)||!validPerson(c))))return false;
 if(d.staffInChargeId!=null&&!id(d.staffInChargeId))return false;
 if(d.periodMonths!=null&&(!Number.isSafeInteger(d.periodMonths)||d.periodMonths<1||d.periodMonths>12))return false;
 if(d.dueDay!=null&&(!Number.isSafeInteger(d.dueDay)||d.dueDay<1||d.dueDay>31))return false;
 if(d.periodAmountMinor!=null&&(!Number.isSafeInteger(d.periodAmountMinor)||d.periodAmountMinor<=0||d.periodAmountMinor>1e12))return false;
 if(d.depositMinor!=null&&(!Number.isSafeInteger(d.depositMinor)||d.depositMinor<0||d.depositMinor>1e12))return false;
 if(d.depositMethod!=null&&!['cash','bankTransfer'].includes(d.depositMethod))return false;
 if(d.depositAccountId!=null&&(!id(d.depositAccountId)||d.depositMethod!=='bankTransfer'))return false;
 return text(d.depositNote,500);
}
// 2026-10-04: surcharges on a lease (phụ thu), billed on period invoices. Each
// line is per room or per person (main tenant + roommates), and every period
// or once; the amount can still be changed on one period's invoice.
// 2026-10-04 (Tom): water (tiền nước) is one such line with kind 'water':
// per person, per month (a 3-month period charges 3 months).
function validSurcharges(v,withIds){
 if(!Array.isArray(v)||v.length>20)return false;
 const ids=new Set();let water=0;
 for(const s of v){
  if(!plain(s)||Object.keys(s).some(k=>!['id','label','amountMinor','basis','frequency','kind'].includes(k)))return false;
  if(s.kind!==undefined&&(s.kind!=='water'||s.frequency!=='month'||++water>1))return false;
  if(s.id!==undefined&&(!withIds||!id(s.id)||ids.has(s.id)))return false;
  if(s.id!==undefined)ids.add(s.id);
  if(typeof s.label!=='string'||!s.label.trim()||s.label.length>80||!Number.isSafeInteger(s.amountMinor)||s.amountMinor<=0||s.amountMinor>1e12||!['room','person'].includes(s.basis)||!['period','once','month'].includes(s.frequency))return false;
 }
 return true;
}
const surchargeRows=(v,seed)=>v.map((s,i)=>({id:s.id??`sc_${createHash('sha256').update(JSON.stringify([seed,i])).digest('hex').slice(0,20)}`,label:s.label.trim(),amountMinor:s.amountMinor,basis:s.basis,frequency:s.frequency,...(s.kind?{kind:s.kind}:{})}));
const person=p=>({nationalId:typeof p.nationalId==='string'&&p.nationalId.trim()?p.nationalId.trim():null,residenceRegistered:p.residenceRegistered===true,residenceRegisteredLocalDate:p.residenceRegistered===true?p.residenceDate??null:null});
function createTenantLeasesHandler({db,Timestamp,HttpsError}){
 const fail=(code,key='lease_'+code)=>{throw new HttpsError(code,key);};
 return async request=>{
  const uid=request.auth?.uid,d=request.data||{},create=d.action==='create',list=d.action==='rooms';
  if(!uid)fail('unauthenticated');
  if(d.action==='surcharges')return editSurcharges(d,uid);
  const keys=['action','organizationId','buildingId',...(list?['cursor']:['roomId']),...(create?['operationId','roomRevision','timeZone','currency','fullName','phoneNumber','moveInDate','contractEndDate','rentMinor','backdateReason',...DETAILS,'periodAmountReason','surcharges','electricityPriceMinor']:[])];
  if(!['rooms','prepare','create'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||(!list&&!id(d.roomId))||Object.keys(d).some(k=>!keys.includes(k))||(list&&d.cursor!=null&&!id(d.cursor)))fail('invalid-argument');
  if(create&&(!id(d.operationId)||typeof d.roomRevision!=='string'||!/^\d+:\d+$/.test(d.roomRevision)||!validZone(d.timeZone)||!['VND','USD'].includes(d.currency)||typeof d.fullName!=='string'||!d.fullName.trim()||d.fullName.length>160||typeof d.phoneNumber!=='string'||d.phoneNumber.length>80||!validDate(d.moveInDate)||!validDate(d.contractEndDate)||d.contractEndDate<=d.moveInDate||!Number.isSafeInteger(d.rentMinor)||d.rentMinor<=0||d.rentMinor>1e12||typeof d.backdateReason!=='string'||d.backdateReason.length>1000||!validDetails(d)||(d.surcharges!==undefined&&!validSurcharges(d.surcharges,false))||(d.electricityPriceMinor!==undefined&&(!Number.isSafeInteger(d.electricityPriceMinor)||d.electricityPriceMinor<=0||d.electricityPriceMinor>1e9))))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),membership=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),member=membership.data(),scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||!allows(member,'manageLease',scope))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`));
   if(!building.exists||building.data().organizationId!==d.organizationId)fail('not-found');
   if(list){
    let q=db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId).orderBy('__name__');
    if(d.cursor!=null)q=q.startAfter(d.cursor);
    const page=await tx.get(q.limit(26)),rows=page.docs.slice(0,25);
    return {records:rows.map(doc=>({id:doc.id,roomNumber:doc.data().roomNumber??'',monthly:true,blocked:roomBlocked(doc.data())})),nextCursor:page.size>25?rows.at(-1).id:null};
   }
   const roomRef=db.doc(`rooms/${d.roomId}`),room=await tx.get(roomRef),r=room.data();
   if(!r||r.organizationId!==d.organizationId||r.buildingId!==d.buildingId)fail('not-found');
   const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex'),key=create?hash(['tenantLease',d.organizationId,uid,d.operationId]):null;
   const op=create?db.doc(`tenantLeaseOperations/${key}`):null,prior=create?await tx.get(op):null,fingerprint=create?hash(keys.map(k=>d[k])):null;
   if(prior?.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
   const zone=building.data().timeZone,currency=org.data().displayCurrency??r.currency??'VND',now=Timestamp.now();
   if(!validZone(zone))fail('failed-precondition','lease_property_timezone_required');
   if(!['VND','USD'].includes(currency))fail('failed-precondition','lease_room_not_monthly');
   // B7: a room with an open "room unavailable" problem takes no new lease.
   if(roomBlocked(r))fail('failed-precondition','room_has_open_problem');
   if(!create){
    const staffDocs=await tx.get(db.collection('staffProfiles').where('organizationId','==',d.organizationId));
    const staff=staffDocs.docs.filter(v=>v.data().employmentStatus!=='inactive').map(v=>({id:v.id,displayName:String(v.data().displayName??'')})).sort((a,b)=>a.displayName.localeCompare(b.displayName));
    const accounts=(Array.isArray(org.data().paymentAccounts)?org.data().paymentAccounts:[]).filter(plain).map(a=>({id:a.id,label:a.label}));
    const roomCurrency=r.currency??'VND';
    const roomRent=Number.isFinite(r.roomPrice)&&r.roomPrice>0?{amountMinor:Math.round(r.roomPrice*(roomCurrency==='USD'?100:1)),currency:roomCurrency}:null;
    // Old clients must not treat a VND room price as a USD lease price.
    return {record:{roomNumber:r.roomNumber??'',roomRevision:revision(room),currency,timeZone:zone,today:propertyDate(now.toMillis(),zone),canBackdate:allows(member,'backdateRecords',{organizationId:d.organizationId,userId:uid}),staff,accounts,canPrice:allows(member,'overridePrices',scope),monthlyRentMinor:roomCurrency===currency?roomRent?.amountMinor??null:null,roomRent}};
   }
   if(d.roomRevision!==revision(room)||d.currency!==currency||d.timeZone!==zone)fail('aborted');
   const start=propertyDayStart(d.moveInDate,zone),end=d.contractEndDate===null?null:propertyDayStart(d.contractEndDate,zone);
   if(start===null||(d.contractEndDate!==null&&end===null))fail('invalid-argument');
   const policy=leaseDatePolicy({moveInMillis:start,nowMillis:now.toMillis(),timeZone:zone,canBackdate:allows(member,'backdateRecords',{organizationId:d.organizationId,userId:uid}),reason:d.backdateReason});
   if(policy.error)fail(policy.error,policy.key);
   // An own amount per period (Fix 5, 2026-10-09, Tom): another amount than rent × months needs "Đổi giá" and a reason;
   // the lease keeps it with the calculated amount, the reason and who changed it (periodRentOverride).
   const calculatedPeriod=d.rentMinor*(d.periodMonths??1),ownPeriod=d.periodAmountMinor!=null&&d.periodAmountMinor!==calculatedPeriod;
   if(d.periodAmountReason!==undefined&&(typeof d.periodAmountReason!=='string'||d.periodAmountReason.length>1000))fail('invalid-argument');
   if(ownPeriod&&(!allows(member,'overridePrices',scope)||!d.periodAmountReason?.trim()))fail('permission-denied','lease_price_authority');
   // The lease is open-ended occupancy until an explicit move-out. Roommates
   // cannot be silently displaced, including legacy rows missing main-tenant flags.
   const tenants=await tx.get(db.collection('tenants').where('roomId','==',d.roomId));
   for(const doc of tenants.docs){const t=doc.data();if((['active','suspended'].includes(t.status)||t.moveOutDate)&&(t.moveOutDate?.toMillis?.()??Infinity)>start)fail('already-exists','lease_room_occupied');}
   const historical=await tx.get(db.collection('leaseOccupancy').where('roomId','==',d.roomId));
   if(historical.docs.some(v=>v.data().end.toMillis()>start))fail('already-exists','lease_room_occupied');
   const bookings=await tx.get(db.collection('bookings').where('roomId','==',d.roomId));
   for(const doc of bookings.docs){const b=doc.data();if(['pending','confirmed','checkedIn'].includes(b.status)&&(b.endTime?.toMillis?.()??Infinity)>start)fail('already-exists','booking_conflict');}
   if(d.staffInChargeId!=null){const s=await tx.get(db.doc(`staffProfiles/${d.staffInChargeId}`));if(!s.exists||s.data().organizationId!==d.organizationId||s.data().employmentStatus==='inactive')fail('invalid-argument','booking_staff_invalid');}
   let account=null;
   if(d.depositAccountId!=null){const a=(Array.isArray(org.data().paymentAccounts)?org.data().paymentAccounts:[]).find(x=>plain(x)&&x.id===d.depositAccountId);if(!a)fail('invalid-argument','booking_account_invalid');account={id:a.id,label:a.label};}
   // 2026-10-04: the electricity price (per kWh) typed with the lease becomes the
   // room's meter price from the move-in day (or its last reading, if later).
   let meter=null;
   if(d.electricityPriceMinor!==undefined){
    if(!allows(member,'overridePrices',scope))fail('permission-denied','lease_price_authority');
    const meterRef=db.doc(`utilityMeters/${meterId(d.organizationId,d.roomId,'electricity')}`),snap=await tx.get(meterRef),old=snap.data()??{revision:0};
    const effectiveDate=old.lastDate&&old.lastDate>d.moveInDate?old.lastDate:d.moveInDate;
    const tariff={currency,bands:[{throughMilli:null,priceMinor:d.electricityPriceMinor}]};
    let tariffHistory;try{tariffHistory=addTariff((old.tariffHistory??[]).filter(x=>x.effectiveDate!==effectiveDate),{effectiveDate,tariff},old.lastDate??null);}catch(e){fail('failed-precondition',e.message);}
    meter={ref:meterRef,exists:snap.exists,patch:{organizationId:d.organizationId,buildingId:d.buildingId,roomId:d.roomId,kind:'electricity',revision:(old.revision??0)+1,tariff,tariffHistory,updatedAt:now,updatedBy:uid}};
   }
   const scale=currency==='USD'?100:1,months=d.periodMonths??1;
   // Lease details (B3). Without the new fields the stored lease is exactly as before.
   const details=DETAILS.some(k=>d[k]!==undefined)?{...person(d),staffInChargeId:d.staffInChargeId??null,paymentPeriodMonths:months,paymentDueDay:d.dueDay??null,
    periodRentMinor:d.periodAmountMinor??d.rentMinor*months,...(d.depositMinor!=null?{deposit:d.depositMinor/scale,depositMinor:d.depositMinor}:{}),
    depositMethod:d.depositMethod??null,depositAccountId:account?.id??null,depositAccountLabel:account?.label??null,depositNote:typeof d.depositNote==='string'?d.depositNote.trim()||null:null}:{};
   const tenantId=`lease_${key}`,result={tenantId},moveIn=Timestamp.fromMillis(start);
   tx.create(db.doc(`tenants/${tenantId}`),{organizationId:d.organizationId,buildingId:d.buildingId,roomId:d.roomId,fullName:d.fullName.trim(),phoneNumber:d.phoneNumber.trim(),status:'active',isMainTenant:true,mainTenantId:null,moveInDate:moveIn,moveInLocalDate:d.moveInDate,moveInTimeZone:zone,moveOutDate:null,contractStartDate:moveIn,contractEndDate:end===null?null:Timestamp.fromMillis(end),contractEndLocalDate:d.contractEndDate,monthlyRent:d.rentMinor/(currency==='USD'?100:1),monthlyRentMinor:d.rentMinor,currency,...details,...(ownPeriod?{periodRentOverride:{totalMinor:d.periodAmountMinor,calculatedTotalMinor:calculatedPeriod,reason:d.periodAmountReason.trim(),byId:uid,byName:String(member.displayName||member.email||uid).slice(0,160),at:now}}:{}),...(d.surcharges?.length?{surcharges:surchargeRows(d.surcharges,key)}:{}),createdAt:now,updatedAt:now,createdBy:uid,updatedBy:uid});
   // Co-tenants entered in the same form become roommates of this lease, from the same day.
   const coTenants=(d.coTenants??[]).map((c,i)=>({id:`roommate_${hash([key,i])}`,c}));
   for(const {id:rid,c} of coTenants)tx.create(db.doc(`tenants/${rid}`),{organizationId:d.organizationId,buildingId:d.buildingId,roomId:d.roomId,mainTenantId:tenantId,isMainTenant:false,fullName:c.fullName.trim(),phoneNumber:(c.phoneNumber??'').trim(),...person(c),status:'active',moveInDate:moveIn,moveInLocalDate:d.moveInDate,moveInTimeZone:zone,moveOutDate:null,currency,createdAt:now,updatedAt:now,createdBy:uid,updatedBy:uid});
   if(coTenants.length)result.coTenantIds=coTenants.map(v=>v.id);
   tx.update(roomRef,{bookingRevision:(r.bookingRevision??0)+1});
   if(meter){if(meter.exists)tx.update(meter.ref,meter.patch);else tx.set(meter.ref,meter.patch);}
   tx.create(op,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
   if(policy.backdated)tx.create(db.doc(`leaseDateCorrections/${key}`),{organizationId:d.organizationId,buildingId:d.buildingId,tenantId,actorId:uid,createdAt:now,previousMoveInDate:null,moveInDate:moveIn,localDate:d.moveInDate,timeZone:zone,reason:policy.reason});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'lease_create',targetId:tenantId,createdAt:now,before:null,after:{buildingId:d.buildingId,roomId:d.roomId,status:'active',moveInDate:moveIn,currency,...(coTenants.length?{coTenants:coTenants.length}:{})}});
   return result;
  });
 };
 // Edit a lease's surcharges later. Lines keep their id so invoices that
 // already billed a one-time line still know it.
 async function editSurcharges(d,uid){
  if(Object.keys(d).some(k=>!['action','organizationId','buildingId','tenantId','surcharges','revision'].includes(k))||!id(d.organizationId)||!id(d.buildingId)||!id(d.tenantId)||!validSurcharges(d.surcharges,true)||(d.revision!=null&&(typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision))))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),membership=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||!allows(membership.data(),'manageLease',scope))fail('permission-denied');
   const ref=db.doc(`tenants/${d.tenantId}`),tenant=await tx.get(ref),t=tenant.data();
   if(!t||t.organizationId!==d.organizationId||t.buildingId!==d.buildingId||t.isMainTenant!==true)fail('not-found');
   if(d.revision!=null&&d.revision!==revision(tenant))fail('aborted');
   const now=Timestamp.now(),rows=surchargeRows(d.surcharges,[d.tenantId,now.toMillis()]);
   tx.update(ref,{surcharges:rows,updatedAt:now,updatedBy:uid});
   tx.create(db.doc(`teamActivity/${createHash('sha256').update(JSON.stringify(['leaseSurcharges',d.tenantId,uid,now.toMillis()])).digest('hex')}`),{organizationId:d.organizationId,actorId:uid,action:'lease_surcharges',targetId:d.tenantId,createdAt:now,before:{count:(t.surcharges??[]).length},after:{count:rows.length}});
   return {surcharges:rows};
  });
 }
}
module.exports={createTenantLeasesHandler};
