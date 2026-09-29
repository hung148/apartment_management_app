'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validDate}=require('./property_contract');
const {validZone}=require('./booking_settings');
const {propertyDate,propertyDayStart}=require('./lease_dates');
const amount=v=>Number.isSafeInteger(v)&&v>0&&v<=1e12;
function rentPlan(tenant){
 const currency=tenant.currency??'VND',factor=currency==='USD'?100:1;
 if(!['USD','VND'].includes(currency))return null;
 const raw=tenant.monthlyRentMinor??tenant.monthlyRent*factor,base=Math.round(raw);
 if(!amount(base)||Math.abs(base-raw)>1e-6)return null;
 const changes=tenant.rentSchedule??[];
 if(!Array.isArray(changes)||changes.length>60||changes.some((v,i)=>!v||!validDate(v.effectiveDate)||!amount(v.amountMinor)||(i>0&&changes[i-1].effectiveDate>=v.effectiveDate)))return null;
 return {currency,baseMinor:base,changes:changes.map(v=>({effectiveDate:v.effectiveDate,amountMinor:v.amountMinor}))};
}
function rentForDate(tenant,date){
 const plan=rentPlan(tenant);if(!plan||!validDate(date))return null;
 let value=plan.baseMinor;for(const c of plan.changes){if(c.effectiveDate>date)break;value=c.amountMinor;}return value;
}
function createTenantRentHandler({db,Timestamp,HttpsError}){
 const fail=(code,key='tenant_rent_'+code)=>{throw new HttpsError(code,key);};
 const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
 return async request=>{
  const uid=request.auth?.uid,d=request.data||{},write=['schedule','cancel'].includes(d.action),history=d.action==='history';
  if(!uid)fail('unauthenticated');
  const keys=['action','organizationId','buildingId','tenantId',...(history?['cursor']:[]),...(write?['operationId','revision','currency','timeZone','effectiveDate','reason',...(d.action==='schedule'?['amountMinor']:[])]:[])];
  if(!['read','schedule','cancel','history'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||!id(d.tenantId)||Object.keys(d).some(k=>!keys.includes(k))||(history&&d.cursor!=null&&(typeof d.cursor!=='string'||! /^[a-f0-9]{64}$/.test(d.cursor))))fail('invalid-argument');
  if(write&&(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)||!['USD','VND'].includes(d.currency)||!validZone(d.timeZone)||!validDate(d.effectiveDate)||typeof d.reason!=='string'||!d.reason.trim()||d.reason.length>1000||(d.action==='schedule'&&!amount(d.amountMinor))))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||!allows(member.data(),'manageLease',scope)||!allows(member.data(),'overridePrices',scope))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),ref=db.doc(`tenants/${d.tenantId}`),doc=await tx.get(ref),t=doc.data();
   if(!building.exists||building.data().organizationId!==d.organizationId||!t||t.organizationId!==d.organizationId||t.buildingId!==d.buildingId)fail('not-found');
   if(history){
    let query=ref.collection('rentHistory').orderBy('createdAt','desc').orderBy('__name__','desc');
    if(d.cursor!=null){const cursor=await tx.get(ref.collection('rentHistory').doc(d.cursor));if(!cursor.exists||cursor.data().organizationId!==d.organizationId)fail('invalid-argument');query=query.startAfter(cursor);}
    const page=await tx.get(query.limit(21)),docs=page.docs.slice(0,20);
    const snapshot=v=>v==null?null:{effectiveDate:v.effectiveDate,amountMinor:v.amountMinor};
    return {records:docs.map(doc=>{const v=doc.data();if(v.organizationId!==d.organizationId)fail('failed-precondition');return {id:doc.id,actorId:v.actorId,createdAt:v.createdAt.toDate().toISOString(),currency:v.currency,timeZone:v.timeZone,effectiveDate:v.effectiveDate,reason:v.reason,before:snapshot(v.before),after:snapshot(v.after)};}),nextCursor:page.size>20?docs.at(-1).id:null};
   }
   const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex'),key=write?hash(['tenantRent',d.organizationId,uid,d.operationId]):null,op=write?ref.collection('rentHistory').doc(key):null,prior=write?await tx.get(op):null,fingerprint=write?hash(keys.map(k=>d[k])):null;
   if(prior?.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
   if(t.isMainTenant!==true||!['active','suspended'].includes(t.status)||t.moveOutDate!=null)fail('failed-precondition');
   const plan=rentPlan(t),zone=t.rentTimeZone??building.data().timeZone,now=Timestamp.now(),today=propertyDate(now.toMillis(),zone),revision=`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
   if(!plan||!validZone(zone)||!today||!Number.isFinite(t.moveInDate?.toMillis?.()))fail('failed-precondition');
   const startDate=propertyDate(t.moveInDate.toMillis(),zone);
   if(!write)return {record:{fullName:t.fullName??'',roomId:t.roomId??'',revision,currency:plan.currency,timeZone:zone,today,startDate,baseMinor:plan.baseMinor,currentMinor:rentForDate(t,today),changes:plan.changes}};
   if(d.revision!==revision||d.currency!==plan.currency||d.timeZone!==zone)fail('aborted');
   if(d.effectiveDate<=today||d.effectiveDate<startDate||propertyDayStart(d.effectiveDate,zone)===null)fail('invalid-argument','tenant_rent_future_required');
   const before=plan.changes.find(v=>v.effectiveDate===d.effectiveDate)??null;
   if(d.action==='cancel'&&!before)fail('failed-precondition');
   const changes=plan.changes.filter(v=>v.effectiveDate!==d.effectiveDate),after=d.action==='schedule'?{effectiveDate:d.effectiveDate,amountMinor:d.amountMinor}:null;
   if(after)changes.push(after);changes.sort((a,b)=>a.effectiveDate.localeCompare(b.effectiveDate));if(changes.length>60)fail('failed-precondition','tenant_rent_schedule_full');
   const result={tenantId:d.tenantId};
   tx.update(ref,{rentSchedule:changes,rentTimeZone:zone,updatedAt:now,updatedBy:uid});
   tx.create(op,{organizationId:d.organizationId,actorId:uid,createdAt:now,currency:plan.currency,timeZone:zone,effectiveDate:d.effectiveDate,reason:d.reason.trim(),before,after,fingerprint,result});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:d.action==='cancel'?'tenant_rent_cancelled':'tenant_rent_scheduled',targetId:d.tenantId,createdAt:now,before:null,after:{buildingId:d.buildingId,roomId:t.roomId,effectiveDate:d.effectiveDate}});
   return result;
  });
 };
}
module.exports={createTenantRentHandler,rentPlan,rentForDate};
