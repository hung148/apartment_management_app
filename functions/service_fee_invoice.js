'use strict';
const {createHash}=require('node:crypto');
const {readReferenceRates,convertCalculation}=require('./reference_rates');
const {propertyDate}=require('./lease_dates');
const {resolvePeriod,serviceCharge,nextDate}=require('./service_fee_math');
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
// Lookup IDs derive from scope so copies and reads find the same documents.
const feesId=(organizationId,buildingId)=>hash(['serviceFees',organizationId,buildingId]);
const roomFeesId=(organizationId,roomId)=>hash(['serviceFeeRooms',organizationId,roomId]);

// Dated presence of the lease's people in one room: the main tenant and the
// roommates linked to that lease, from their current record and past moves.
async function roomPeople({tx,db,organizationId,buildingId,roomId,tenantId,zone}){
 const date=ts=>ts?.toMillis?propertyDate(ts.toMillis(),zone):null;
 const main=await tx.get(db.doc(`tenants/${tenantId}`));
 const roommates=await tx.get(db.collection('tenants').where('mainTenantId','==',tenantId));
 const docs=[main,...roommates.docs].filter(v=>v.exists&&v.data().organizationId===organizationId);
 const people=[];
 for(const doc of docs){
  const t=doc.data(),intervals=[];
  if(t.roomId===roomId&&t.buildingId===buildingId){const start=date(t.occupancyStartDate??t.moveInDate);if(start)intervals.push({startDate:start,endDate:date(t.moveOutDate)});}
  const past=await tx.get(db.collection('leaseOccupancy').where('tenantId','==',doc.id));
  for(const h of past.docs){const x=h.data();if(x.organizationId!==organizationId||x.roomId!==roomId)continue;const s=date(x.start),e=date(x.end);if(s&&e&&e>s)intervals.push({startDate:s,endDate:e});}
  if(intervals.length)people.push({id:doc.id,name:t.fullName??'',isMain:doc.id===tenantId,intervals});
 }
 return people;
}

/** Server-priced service charge for one fee, room, lease and period. */
async function serviceInvoiceSource({tx,db,organizationId,buildingId,roomId,feeId,tenantId,startDate,endDate,quantityMilli,currency,zone,ratesId}){
 const feesRef=db.doc(`serviceFees/${feesId(organizationId,buildingId)}`),feesDoc=await tx.get(feesRef),defs=feesDoc.data();
 const fee=defs?.organizationId===organizationId&&defs.buildingId===buildingId?(defs.fees??[]).find(f=>f.id===feeId):null;
 if(!fee)throw Error('service_fee_not_found');

 if(fee.basis==='quantity'){if(endDate!==nextDate(startDate))throw Error('service_invalid_period');}
 else if(quantityMilli!==null)throw Error('service_invalid_quantity');
 const roomRef=db.doc(`serviceFeeRooms/${roomFeesId(organizationId,roomId)}`),roomDoc=await tx.get(roomRef),room=roomDoc.data();
 const overrides=room?.organizationId===organizationId?room.overrides?.[feeId]??[]:[];
 let terms;try{terms=resolvePeriod({...fee,currency:defs.currency??'VND'},overrides,startDate,endDate);}catch(e){throw e;}
 const sourceCurrency=terms.currency??defs.currency??'VND';
 if(sourceCurrency!==currency&&!ratesId)throw Error('service_currency_mismatch');
 const people=await roomPeople({tx,db,organizationId,buildingId,roomId,tenantId,zone});
 const original=serviceCharge({basis:fee.basis,terms,startDate,endDate,people,quantityMilli,currency:sourceCurrency});
 const calculation=sourceCurrency===currency?original:convertCalculation(original,currency,await readReferenceRates(tx,db,ratesId));
 return {feesRef,feesDoc:defs,roomRef,room,fee,calculation:{...calculation,chargeType:'service',feeId,feeName:fee.name,unitLabel:fee.unitLabel??'',roomId,timeZone:zone}};
}

// Record what was billed so earlier prices can no longer be changed under it.
function markBilled(tx,{feesRef,feesDoc,roomRef,room,fee},{organizationId,buildingId,roomId,endDate,now}){
 const fees=feesDoc.fees.map(f=>f.id===fee.id?{...f,billedThrough:f.billedThrough&&f.billedThrough>endDate?f.billedThrough:endDate}:f);
 tx.set(feesRef,{...feesDoc,fees,revision:(feesDoc.revision??0)+1,updatedAt:now});
 const billed={...(room?.billedThrough??{})};if(!billed[fee.id]||billed[fee.id]<endDate)billed[fee.id]=endDate;
 tx.set(roomRef,{organizationId,buildingId,roomId,overrides:room?.overrides??{},revision:(room?.revision??0)+1,...(room?.updatedAt?{updatedAt:room.updatedAt}:{}),billedThrough:billed});
}
// Several fees of one room billed together (a period invoice): one write per
// document, so later fees do not overwrite earlier markers.
function markBilledAll(tx,sources,{organizationId,buildingId,roomId,endDate,now}){
 if(!sources.length)return;
 const {feesRef,feesDoc,roomRef,room}=sources[0],ids=new Set(sources.map(s=>s.fee.id));
 const later=(a,b)=>a&&a>b?a:b;
 const fees=feesDoc.fees.map(f=>ids.has(f.id)?{...f,billedThrough:later(f.billedThrough,endDate)}:f);
 tx.set(feesRef,{...feesDoc,fees,revision:(feesDoc.revision??0)+1,updatedAt:now});
 const billed={...(room?.billedThrough??{})};for(const fid of ids)billed[fid]=later(billed[fid],endDate);
 tx.set(roomRef,{organizationId,buildingId,roomId,overrides:room?.overrides??{},revision:(room?.revision??0)+1,...(room?.updatedAt?{updatedAt:room.updatedAt}:{}),billedThrough:billed});
}
module.exports={serviceInvoiceSource,markBilled,markBilledAll,roomPeople,feesId,roomFeesId};
