'use strict';
// Building price defaults (PRICE_DEFAULTS.md, Tom 2026-10-26): monthly rent,
// nightly price, water per month (lease form prefill) and electricity.
// A room either FOLLOWS the building for a price (room.priceFollows[kind]) or
// has its OWN price. Rooms keep storing the actual price, so every reader
// (quotes, lease form, calendar) is unchanged: a building change writes the
// new price into each following room. Rooms with their own price change only
// when the user ticks them (one checklist per price); a ticked room follows.
// Electricity uses the existing dated tariffs: a room entry with tariff null
// means "use the building's price from that date".
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {addTariff}=require('./utility_tariffs');
const {meterId}=require('./utility_invoice');
const {propertyDate}=require('./lease_dates');
const {validDate}=require('./property_contract');
const {validZone}=require('./booking_settings');

const KINDS=['roomPrice','nightlyPrice'];
const DEFAULT_KEYS=['roomPriceMinor','nightlyPriceMinor','waterMonthMinor','waterBasis'];
const MAX_ROOMS=400;
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const revision=doc=>`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
const money=v=>v===null||(Number.isSafeInteger(v)&&v>0&&v<=1e12);
const scaleOf=currency=>currency==='USD'?100:1;
const toMinor=(value,currency)=>typeof value==='number'&&Number.isFinite(value)&&value>0?Math.round(value*scaleOf(currency)):null;
const plain=v=>!!v&&typeof v==='object'&&!Array.isArray(v);

/** {roomPriceMinor,nightlyPriceMinor,waterMonthMinor,waterBasis} — all keys. */
function validDefaults(p){
 return plain(p)&&Object.keys(p).length===DEFAULT_KEYS.length&&DEFAULT_KEYS.every(k=>Object.hasOwn(p,k))&&
  money(p.roomPriceMinor)&&money(p.nightlyPriceMinor)&&money(p.waterMonthMinor)&&['person','room'].includes(p.waterBasis);
}
const defaultsOf=b=>{const p=plain(b?.defaultPrices)?b.defaultPrices:{};return {roomPriceMinor:p.roomPriceMinor??null,nightlyPriceMinor:p.nightlyPriceMinor??null,waterMonthMinor:p.waterMonthMinor??null,waterBasis:p.waterBasis==='room'?'room':'person'};};
const followsOf=room=>({roomPrice:room?.priceFollows?.roomPrice===true,nightlyPrice:room?.priceFollows?.nightlyPrice===true});
const roomValue=(room,kind)=>kind==='nightlyPrice'?room.nightlyPrice??room.dailyPrice:room[kind];

/** New rooms (building creation, bulk add): a price equal to the building's
 * follows it (the form prefilled it and nobody changed it). */
function followsFor(ratesMinor,defaults){
 return Object.fromEntries(KINDS.map(k=>[k,defaults[k+'Minor']!=null&&ratesMinor?.[k]===defaults[k+'Minor']]));
}
/** A new room left without a price takes the building's (Tom, 2026-10-28),
 * and so follows it. Only for rooms in the building's currency. */
function withBuildingPrices(ratesMinor,defaults){
 return {...ratesMinor,...Object.fromEntries(KINDS.filter(k=>ratesMinor?.[k]==null&&defaults[k+'Minor']!=null).map(k=>[k,defaults[k+'Minor']]))};
}

const propertyTariffRef=(db,organizationId,buildingId,kind)=>db.doc(`utilityTariffs/${hash([organizationId,buildingId,kind])}`);
const tariffAt=(history,date)=>(history??[]).filter(x=>x.effectiveDate<=date).at(-1)?.tariff??null;
/** One price per kWh, or null for a tiered (bậc thang) or missing tariff. */
const flatPrice=t=>t&&Array.isArray(t.bands)&&t.bands.length===1&&t.bands[0].throughMilli==null?t.bands[0].priceMinor:null;
const flatTariff=(priceMinor,currency)=>({currency,bands:[{throughMilli:null,priceMinor}]});

/** A building's electricity tariff from its creation day (new building). */
function initialElectricity(tx,db,{organizationId,buildingId,priceMinor,currency,timeZone,now,uid}){
 if(priceMinor==null)return;
 const today=propertyDate(now.toMillis(),timeZone);
 tx.set(propertyTariffRef(db,organizationId,buildingId,'electricity'),{organizationId,buildingId,kind:'electricity',revision:1,history:[{effectiveDate:today,tariff:flatTariff(priceMinor,currency)}],updatedAt:now,updatedBy:uid});
}

function createBuildingPrices({db,Timestamp,HttpsError}){
 const fail=(code,key='price_'+code)=>{throw new HttpsError(code,key);};
 return async(d,uid)=>{
  const saving=d.action==='savePrices';
  const keys=['action','organizationId','buildingId',...(saving?['operationId','revision','defaults','electricity','apply']:[])];
  if(Object.keys(d).some(k=>!keys.includes(k))||!id(d.organizationId)||!id(d.buildingId))fail('invalid-argument');
  if(saving){
   if(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)||!validDefaults(d.defaults))fail('invalid-argument');
   if(d.electricity!==null&&(!plain(d.electricity)||Object.keys(d.electricity).some(k=>!['priceMinor','effectiveDate','propertyRevision'].includes(k))||!Number.isSafeInteger(d.electricity.priceMinor)||d.electricity.priceMinor<=0||d.electricity.priceMinor>1e9||!validDate(d.electricity.effectiveDate)||!Number.isSafeInteger(d.electricity.propertyRevision)||d.electricity.propertyRevision<0))fail('invalid-argument');
   if(!plain(d.apply)||Object.keys(d.apply).some(k=>![...KINDS,'electricity'].includes(k))||Object.values(d.apply).some(v=>!Array.isArray(v)||v.length>MAX_ROOMS||v.some(x=>!id(x))||new Set(v).size!==v.length))fail('invalid-argument');
  }
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),m=member.data();
   const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||!allows(m,'manageProperty',scope))fail('permission-denied');
   const canPrice=allows(m,'overridePrices',scope),canBackdate=allows(m,'backdateRecords',{organizationId:d.organizationId,userId:uid});
   if(saving&&!canPrice)fail('permission-denied','lease_price_authority');
   const ref=db.doc(`buildings/${d.buildingId}`),building=await tx.get(ref),b=building.data();
   if(!b||b.organizationId!==d.organizationId)fail('not-found');
   const zone=b.timeZone,currency=b.currency??'VND',now=Timestamp.now();
   if(!validZone(zone))fail('failed-precondition','lease_property_timezone_required');
   const today=propertyDate(now.toMillis(),zone);
   const roomDocs=(await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId))).docs.filter(v=>!v.data().deletedAt);
   if(roomDocs.length>MAX_ROOMS)fail('failed-precondition','price_too_many_rooms');
   const propRef=propertyTariffRef(db,d.organizationId,d.buildingId,'electricity'),propSnap=await tx.get(propRef),prop=propSnap.data()??{revision:0,history:[]};
   const meterRefs=roomDocs.map(r=>db.doc(`utilityMeters/${meterId(d.organizationId,r.id,'electricity')}`));
   const meters=await Promise.all(meterRefs.map(r=>tx.get(r)));
   const meterOf=new Map(roomDocs.map((r,i)=>[r.id,{ref:meterRefs[i],snap:meters[i],data:meters[i].data()??null}]));
   const lastReading=meters.map(s=>s.data()?.lastDate??'').filter(Boolean).sort().at(-1)??null;
   const defaults=defaultsOf(b);
   const roomView=r=>{
    const x=r.data(),c=x.currency??'VND',meter=meterOf.get(r.id).data,own=tariffAt(meter?.tariffHistory,today);
    return {id:r.id,roomNumber:x.roomNumber??'',currency:c,roomPriceMinor:toMinor(roomValue(x,'roomPrice'),c),nightlyPriceMinor:toMinor(roomValue(x,'nightlyPrice'),c),follows:followsOf(x),
     electricity:{own:own!==null,ownPriceMinor:flatPrice(own),lastReadingDate:meter?.lastDate??null}};
   };
   if(!saving){
    const current=tariffAt(prop.history,today),upcoming=(prop.history??[]).filter(x=>x.effectiveDate>today);
    // The building's hourly templates (managed here too, 2026-10-26).
    const tpl=await tx.get(db.doc(`buildingHourTemplates/${d.buildingId}`));
    const hourTemplates=tpl.exists&&tpl.data().organizationId===d.organizationId?tpl.data().templates??[]:[];
    return {record:{revision:revision(building),currency,today,canPrice,canBackdate,defaults,hourTemplates,canSaveTemplates:allows(m,'saveRoomPrices',scope),
     electricity:{priceMinor:flatPrice(current),tiered:current!==null&&flatPrice(current)===null,from:(prop.history??[]).filter(x=>x.effectiveDate<=today).at(-1)?.effectiveDate??null,upcoming:upcoming.map(x=>({effectiveDate:x.effectiveDate,priceMinor:flatPrice(x.tariff)})),propertyRevision:prop.revision??0,earliestDate:lastReading},
     rooms:roomDocs.map(roomView).sort((a,c)=>a.roomNumber.localeCompare(c.roomNumber,'vi',{numeric:true}))}};
   }
   const key=hash(['buildingPrices',d.organizationId,uid,d.operationId]),fingerprint=hash(keys.map(k=>d[k]));
   const op=db.doc(`propertyOperations/${key}`),prior=await tx.get(op);
   if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('already-exists');return prior.data().result;}
   if(revision(building)!==d.revision)fail('aborted','price_changed');
   const known=new Set(roomDocs.map(r=>r.id));
   for(const list of Object.values(d.apply))if(list.some(x=>!known.has(x)))fail('not-found','price_room_not_found');
   for(const kind of KINDS)if(d.apply[kind]?.length&&d.defaults[kind+'Minor']==null)fail('invalid-argument','price_apply_without_price');
   if(d.apply.electricity?.length&&!d.electricity)fail('invalid-argument','price_apply_without_price');
   const next=d.defaults,result={buildingId:d.buildingId,rooms:0};
   // Rooms: followers get the new price; ticked rooms get it and follow.
   const roomWrites=[];
   for(const r of roomDocs){
    const x=r.data(),c=x.currency??'VND',follows=followsOf(x),patch={},nextFollows={...follows};
    for(const kind of KINDS){
     // A room with no price of this kind takes the building's without being
     // asked, and follows it (Tom, 2026-10-28).
     const price=next[kind+'Minor'],ticked=d.apply[kind]?.includes(r.id)||(price!=null&&c===currency&&roomValue(x,kind)==null);
     if(!ticked&&!(follows[kind]&&price!=null))continue;
     if(c!==currency){if(ticked)fail('failed-precondition','price_room_currency');continue;}
     if(toMinor(roomValue(x,kind),c)!==price)patch[kind]=price/scaleOf(c);
     if(kind==='nightlyPrice'&&x.dailyPrice!=null&&patch[kind]!==undefined)patch.dailyPrice=null;
     if(ticked&&!follows[kind]){nextFollows[kind]=true;patch.priceFollows=nextFollows;}
    }
    if(Object.keys(patch).length)roomWrites.push({ref:r.ref,patch,before:{roomPrice:x.roomPrice??null,nightlyPrice:roomValue(x,'nightlyPrice')??null}});
   }
   // Electricity: a new building price from a date; ticked rooms drop their own.
   let propWrite=null;const meterWrites=[];
   if(d.electricity){
    const e=d.electricity;
    if((prop.revision??0)!==e.propertyRevision)fail('aborted','price_changed');
    if(e.effectiveDate<today&&!canBackdate)fail('permission-denied','lease_backdate_owner_admin_required');
    const tariff=flatTariff(e.priceMinor,currency);
    // Do not put a new price into days any room already measured (as utility_readings does).
    let history;try{history=addTariff(prop.history??[],{effectiveDate:e.effectiveDate,tariff},lastReading);}catch(err){fail('failed-precondition',err.message);}
    propWrite={organizationId:d.organizationId,buildingId:d.buildingId,kind:'electricity',revision:(prop.revision??0)+1,history,updatedAt:now,updatedBy:uid};
    for(const roomId of d.apply.electricity??[]){
     const meter=meterOf.get(roomId);if(!meter.data||tariffAt(meter.data.tariffHistory,e.effectiveDate)===null)continue; // already follows
     let roomHistory;try{roomHistory=addTariff(meter.data.tariffHistory??[],{effectiveDate:e.effectiveDate,tariff:null},meter.data.lastDate??null);}catch(err){fail('failed-precondition',err.message==='utility_tariff_past_reading'?'price_electricity_before_reading':err.message);}
     meterWrites.push({ref:meter.ref,patch:{tariffHistory:roomHistory,tariff:null,revision:(meter.data.revision??0)+1,updatedAt:now,updatedBy:uid}});
    }
   }
   tx.update(ref,{defaultPrices:{...next},updatedAt:now,updatedBy:uid});
   for(const w of roomWrites)tx.update(w.ref,{...w.patch,updatedAt:now,updatedBy:uid});
   if(propWrite)tx.set(propRef,propWrite);
   for(const w of meterWrites)tx.update(w.ref,w.patch);
   result.rooms=roomWrites.length;
   tx.create(op,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'building_prices_updated',targetId:d.buildingId,createdAt:now,
    before:{defaults,electricityPriceMinor:flatPrice(tariffAt(prop.history,today))},
    after:{defaults:next,...(d.electricity?{electricity:{priceMinor:d.electricity.priceMinor,effectiveDate:d.electricity.effectiveDate}}:{}),rooms:roomWrites.length,ticked:Object.fromEntries(Object.entries(d.apply).map(([k,v])=>[k,v.length]))}});
   return result;
  });
 };
}

module.exports={createBuildingPrices,validDefaults,defaultsOf,followsFor,followsOf,initialElectricity,withBuildingPrices,KINDS};
