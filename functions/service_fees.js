'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {propertyDate}=require('./lease_dates');
const {validZone}=require('./booking_settings');
const {validateVersion,validateOverride,addDated,resolveFee,BASES}=require('./service_fee_math');
const {feesId,roomFeesId}=require('./service_fee_invoice');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const text=(v,max)=>typeof v==='string'&&v.trim().length>0&&v.length<=max;
const MAX_FEES=30;

function createServiceFeesHandler({db,Timestamp,HttpsError}){
 const fail=(code,key='service_'+code)=>{throw new HttpsError(code,key);};
 return async request=>{
  const uid=request.auth?.uid,d=request.data??{},write=['define','rename','roomRate'].includes(d.action);
  if(!uid)fail('unauthenticated');
  const keys=[...(d.inputCurrency!==undefined?['inputCurrency']:[]),'action','organizationId','buildingId',...(d.action==='read'?['roomId']:[]),...(write?['operationId','revision','reason']:[]),
   ...(d.action==='define'?['feeId','name','basis','unitLabel','version']:[]),...(d.action==='rename'?['feeId','name','unitLabel']:[]),...(d.action==='roomRate'?['roomId','feeId','override']:[])];
  if(!['read','define','rename','roomRate'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
  if(d.action==='read'&&d.roomId!=null&&!id(d.roomId))fail('invalid-argument');
  if(d.action==='roomRate'&&!id(d.roomId))fail('invalid-argument');
  if(write&&(!id(d.operationId)||!Number.isSafeInteger(d.revision)||d.revision<0||!text(d.reason,1000)))fail('invalid-argument');
  if(['rename','roomRate'].includes(d.action)&&!id(d.feeId))fail('invalid-argument');
  if(d.action==='define'&&(d.feeId!==null&&!id(d.feeId)))fail('invalid-argument');
  if(['define','rename'].includes(d.action)&&(!text(d.name,80)||typeof d.unitLabel!=='string'||d.unitLabel.length>20))fail('invalid-argument');
  if(d.action==='define'&&!BASES.includes(d.basis))fail('invalid-argument');
  let version,override;
  if(d.action==='define')try{version=validateVersion(d.version,d.basis);}catch(e){fail('invalid-argument',e.message);}
  if(d.action==='roomRate')try{override=validateOverride(d.override);}catch(e){fail('invalid-argument',e.message);}
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),m=member.data();
   const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt)fail('permission-denied');
   const canRead=allows(m,'manageLease',scope)||allows(m,'readFinancialReports',scope),canPrice=allows(m,'overridePrices',scope);
   if(!canRead||(write&&!canPrice))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),b=building.data();
   if(!b||b.organizationId!==d.organizationId)fail('not-found');
   const currency=b.currency??'VND';
   let room=null;
   const roomId=d.roomId??null;
   if(roomId){const r=await tx.get(db.doc(`rooms/${roomId}`));if(!r.exists||r.data().organizationId!==d.organizationId||r.data().buildingId!==d.buildingId)fail('not-found');room=r.data();}
   const feesRef=db.doc(`serviceFees/${feesId(d.organizationId,d.buildingId)}`),feesSnap=await tx.get(feesRef);
   const defs=feesSnap.data()??{organizationId:d.organizationId,buildingId:d.buildingId,currency,revision:0,fees:[]};
   const roomRef=roomId?db.doc(`serviceFeeRooms/${roomFeesId(d.organizationId,roomId)}`):null,roomSnap=roomRef?await tx.get(roomRef):null;
   const rates=roomSnap?.data()??(roomId?{organizationId:d.organizationId,buildingId:d.buildingId,roomId,revision:0,overrides:{},billedThrough:{}}:null);
   if(d.action==='read'){
    const today=validZone(b.timeZone)?propertyDate(Timestamp.now().toMillis(),b.timeZone):null;
    let tenants=[];
    if(roomId){
     // Leases that lived in this room (current and past), for billing.
     const current=await tx.get(db.collection('tenants').where('roomId','==',roomId)),past=await tx.get(db.collection('leaseOccupancy').where('roomId','==',roomId));
     const ids=new Map();
     for(const v of current.docs){const x=v.data();if(x.organizationId===d.organizationId&&x.isMainTenant===true)ids.set(v.id,{id:v.id,fullName:x.fullName??'',current:!x.moveOutDate,currency:x.currency??'VND'});}
     for(const h of past.docs){const x=h.data();if(x.organizationId!==d.organizationId||x.isMainTenant!==true||ids.has(x.tenantId))continue;const t=await tx.get(db.doc(`tenants/${x.tenantId}`));if(t.exists&&t.data().organizationId===d.organizationId)ids.set(t.id,{id:t.id,fullName:t.data().fullName??'',current:false,currency:t.data().currency??'VND'});}
     tenants=[...ids.values()].slice(0,20);
    }
    const fees=defs.fees.map(f=>({id:f.id,name:f.name,basis:f.basis,unitLabel:f.unitLabel??'',versions:f.versions,billedThrough:f.billedThrough??null,
     ...(roomId?{overrides:rates.overrides?.[f.id]??[],roomBilledThrough:rates.billedThrough?.[f.id]??null,current:today?resolveFee({...f,currency:defs.currency??currency},rates.overrides?.[f.id]??[],today):null}:{current:today?resolveFee({...f,currency:defs.currency??currency},[],today):null})}));
    return {record:{currency,today,revision:defs.revision,roomRevision:rates?.revision??null,roomNumber:room?.roomNumber??null,canPrice,canBill:allows(m,'readFinancialReports',scope)&&allows(m,'collectPayments',scope),fees,tenants}};
   }
   const opRef=db.doc(`serviceFeeOperations/${hash(['serviceFees',d.organizationId,uid,d.operationId])}`),prior=await tx.get(opRef),fingerprint=hash(keys.map(k=>d[k]??null));
   if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
   if(d.inputCurrency!==undefined&&(!['USD','VND'].includes(d.inputCurrency)||d.inputCurrency!==(org.data().displayCurrency??currency)))fail('failed-precondition','service_currency_mismatch');
   if(d.inputCurrency!==undefined){if(version?.active)version={...version,currency:d.inputCurrency};if(override?.mode==='rate')override={...override,currency:d.inputCurrency};}
   const now=Timestamp.now();let result,before=null,after;
   if(d.action==='roomRate'){
    if(rates.revision!==d.revision)fail('aborted','service_changed');

    const fee=defs.fees.find(f=>f.id===d.feeId);if(!fee)fail('not-found','service_fee_not_found');
    if(fee.basis==='quantity'&&override.mode==='off')fail('invalid-argument','service_invalid_override');
    let history;try{history=addDated(rates.overrides?.[d.feeId]??[],override,rates.billedThrough?.[d.feeId]??null);}catch(e){fail('failed-precondition',e.message);}
    tx.set(roomRef,{...rates,overrides:{...(rates.overrides??{}),[d.feeId]:history},revision:rates.revision+1,updatedAt:now,updatedBy:uid});
    result={revision:rates.revision+1};before={roomId,feeId:d.feeId};after={roomId,feeId:d.feeId,override};
   }else{
    if(defs.revision!==d.revision)fail('aborted','service_changed');
    if(defs.currency&&defs.currency!==currency)fail('failed-precondition','service_currency_mismatch');
    let fees=defs.fees,feeId=d.feeId;
    if(d.action==='rename'){
     const fee=fees.find(f=>f.id===feeId);if(!fee)fail('not-found','service_fee_not_found');
     if(fees.some(f=>f.id!==feeId&&f.name.trim().toLowerCase()===d.name.trim().toLowerCase()))fail('already-exists','service_fee_name_exists');
     before={feeId,name:fee.name};fees=fees.map(f=>f.id===feeId?{...f,name:d.name.trim(),unitLabel:d.unitLabel.trim()}:f);
    }else if(feeId===null){
     if(fees.length>=MAX_FEES)fail('failed-precondition','service_fee_limit');
     if(fees.some(f=>f.name.trim().toLowerCase()===d.name.trim().toLowerCase()))fail('already-exists','service_fee_name_exists');
     if(!version.active)fail('invalid-argument','service_invalid_fee');
     feeId='fee_'+hash([uid,d.operationId]).slice(0,20);
     fees=[...fees,{id:feeId,name:d.name.trim(),basis:d.basis,unitLabel:d.unitLabel.trim(),versions:[version],billedThrough:null,createdAt:now,createdBy:uid}];
    }else{
     const fee=fees.find(f=>f.id===feeId);if(!fee)fail('not-found','service_fee_not_found');
     if(fee.basis!==d.basis)fail('invalid-argument','service_basis_fixed');
     if(fees.some(f=>f.id!==feeId&&f.name.trim().toLowerCase()===d.name.trim().toLowerCase()))fail('already-exists','service_fee_name_exists');
     let versions;try{versions=addDated(fee.versions,version,fee.billedThrough);}catch(e){fail('failed-precondition',e.message);}
     before={feeId,name:fee.name};fees=fees.map(f=>f.id===feeId?{...f,name:d.name.trim(),unitLabel:d.unitLabel.trim(),versions}:f);
    }
    tx.set(feesRef,{...defs,currency,fees,revision:defs.revision+1,updatedAt:now,updatedBy:uid});
    result={revision:defs.revision+1,feeId};after={feeId,name:d.name.trim(),...(version?{version}:{})};
   }
   tx.create(opRef,{organizationId:d.organizationId,buildingId:d.buildingId,actorId:uid,action:d.action,fingerprint,result,reason:d.reason.trim(),createdAt:now});
   tx.create(db.doc(`teamActivity/${hash(['serviceFees',d.organizationId,uid,d.operationId])}`),{organizationId:d.organizationId,actorId:uid,action:'service_'+d.action,targetId:d.buildingId,createdAt:now,before,after:{buildingId:d.buildingId,...after},reason:d.reason.trim()});
   return result;
  });
 };
}
module.exports={createServiceFeesHandler};
