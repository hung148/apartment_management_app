'use strict';
const {createHash}=require('node:crypto');
const {readReferenceRates,convertMinor}=require('./reference_rates');
const {allows}=require('./team_access');const {validZone}=require('./booking_settings');const {localTime,bookingPrice}=require('./booking_quote');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v),revision=d=>`${d.updateTime.seconds}:${d.updateTime.nanoseconds}`;
// B2: per-night prices and surcharges change the quote; the rest are booking details passed to calendar.js,
// which validates them. A detail left out of a save keeps its stored value (older app versions).
const PRICE_EXTRA=['nightPricesMinor','surcharges','hourlyPriceMinor'],DETAILS=['guestIdNumber','guests','numberOfGuests','staffInChargeId','platform','contactChannel','depositNote'];
const plain=v=>!!v&&typeof v==='object'&&!Array.isArray(v);
// Deposit taken when the booking is made (2026-10-04): part of the total, paid in cash, by bank transfer or by card on a day.
const DEPOSIT_METHODS=['cash','bankTransfer','creditCard'];
const localDay=(instant,zone)=>{const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(instant)).map(x=>[x.type,x.value]));return `${p.year}-${p.month}-${p.day}`;};
// CCCD numbers: shown in full only with "Xem số CCCD" (readGuestIds).
const masked=v=>v.length>4?`•••• ${v.slice(-4)}`:'••••';
function createBookingWorkspaceHandler({db,Timestamp,HttpsError,calendar}){const fail=(code,key='booking_'+code)=>{throw new HttpsError(code,key);};return async request=>{
 const d=request.data||{},uid=request.auth?.uid;if(!uid)fail('unauthenticated');
 const identity=['action','organizationId','buildingId'];let extra=[];
 if(d.action==='list')extra=['cursor'];else if(d.action==='read')extra=['bookingId'];else if(d.action==='quote')extra=['roomId','startLocal','endLocal','occurrence','pricingType','overrideMinor','overrideReason','numberOfGuests',...PRICE_EXTRA];else if(d.action==='save')extra=['bookingId','operationId','revision','roomId','roomRevision','startLocal','endLocal','occurrence','pricingType','guestName','guestPhone','notes','depositMinor','deposit','overrideMinor','overrideReason',...PRICE_EXTRA,...DETAILS];else if(d.action==='command')extra=['bookingId','operationId','revision','command','amountMinor','paymentMethod','status','reason','accountId'];else if(d.action!=='rooms')fail('invalid-argument');
 if(['quote','save'].includes(d.action))extra.push('inputCurrency','ratesId',...(d.action==='quote'?['bookingId']:[]));
 if(d.action==='command')extra.push('inputCurrency','inputAmountMinor','ratesId');
 if(d.inputCurrency!==undefined&&!['VND','USD'].includes(d.inputCurrency))fail('invalid-argument');
 const workspaceFingerprint=d.action==='save'&&d.inputCurrency?createHash('sha256').update(JSON.stringify(d)).digest('hex'):null;
 if(!id(d.organizationId)||!id(d.buildingId)||Object.keys(d).some(k=>![...identity,...extra].includes(k)))fail('invalid-argument');
 const prepared=await db.runTransaction(async tx=>{
 const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),m=member.data(),scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};if(!org.exists||org.data().accessVersion!==2||!allows(m,'readBookings',{...scope,anyRecord:true}))fail('permission-denied');
 const own=x=>({...scope,record:x});// "own records only" grants are checked per booking
 const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),b=building.data();if(!b||b.organizationId!==d.organizationId)fail('not-found');const zone=b.timeZone;if(!validZone(zone))fail('failed-precondition','lease_property_timezone_required');
 if(d.action==='rooms'){const rows=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));const staffDocs=await tx.get(db.collection('staffProfiles').where('organizationId','==',d.organizationId));const staff=staffDocs.docs.filter(v=>v.data().employmentStatus!=='inactive').map(v=>({id:v.id,displayName:String(v.data().displayName??'')})).sort((a,b)=>a.displayName.localeCompare(b.displayName));const accounts=(Array.isArray(org.data().paymentAccounts)?org.data().paymentAccounts:[]).filter(plain).map(a=>({id:a.id,label:a.label}));return {canPrice:allows(m,'overridePrices',scope),canCollect:allows(m,'collectPayments',scope),canReadGuestIds:allows(m,'readGuestIds',scope),staff,accounts,// 2026-10-04: every room takes short stays and leases.
 records:rows.docs.filter(v=>!v.data().deletedAt).map(v=>{const x=v.data(),nightly=x.nightlyPrice??x.dailyPrice;return {id:v.id,roomNumber:x.roomNumber??v.id,currency:x.currency??'VND',nightlyPriceMinor:typeof nightly==='number'&&nightly>0?Math.round(nightly*((x.currency??'VND')==='USD'?100:1)):null,hourlyPriceMinor:typeof x.hourlyPrice==='number'&&x.hourlyPrice>0?Math.round(x.hourlyPrice*((x.currency??'VND')==='USD'?100:1)):null};}),timeZone:zone,today:localDay(Date.now(),zone)};}
 const seeIds=allows(m,'readGuestIds',scope),idText=v=>typeof v==='string'&&v?(seeIds?v:masked(v)):'';
 const projection=(doc,numbers=new Map(),staffNames=new Map())=>{const x=doc.data(),iso=v=>v?.toDate?.().toISOString()??null;const local=v=>{if(!v?.toDate)return '';const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(v.toDate()).map(p=>[p.type,p.value]));return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}`;};return {id:doc.id,revision:revision(doc),roomId:x.roomId,roomNumber:numbers.get(x.roomId)??'',guestName:x.guestName??'',guestPhone:x.guestPhone??'',notes:x.notes??'',status:x.status,startTime:iso(x.startTime),endTime:iso(x.endTime),startLocal:local(x.startTime),endLocal:local(x.endTime),currency:x.currency,totalPrice:x.totalPrice,paidAmount:x.paidAmount,depositAmount:x.depositAmount??0,depositPaidAmount:x.depositPaidAmount??0,depositRefundedAmount:x.depositRefundedAmount??0,pricingType:x.pricingType,timeZone:zone,guestIdNumber:idText(x.guestIdNumber),guests:(Array.isArray(x.guests)?x.guests:[]).filter(plain).map(g=>({id:g.id,name:g.name??'',idNumber:idText(g.idNumber)})),numberOfGuests:x.numberOfGuests??null,staffInChargeId:x.staffInChargeId??null,staffName:staffNames.get(x.staffInChargeId)??'',platform:x.platform??null,contactChannel:x.contactChannel??null,depositNote:x.depositNote??'',depositPayment:plain(x.depositPayment)?{amount:x.depositPayment.amount,paymentMethod:x.depositPayment.paymentMethod,paidOn:x.depositPayment.paidOn??''}:null,surcharges:(Array.isArray(x.surcharges)?x.surcharges:[]).filter(plain).map(s=>({label:s.label,amount:s.amount,...(s.basis==='person'?{basis:'person',unitAmount:s.unitAmount,count:s.count}:{})})),nightPrices:Array.isArray(x.nightPrices)?x.nightPrices:null,hourlyPrice:typeof x.hourlyPrice==='number'?x.hourlyPrice:null,canReadGuestIds:seeIds,canManage:allows(m,'manageBookings',own(x)),canCollect:allows(m,'collectPayments',scope),canRefund:allows(m,'refundPayments',scope)};};
 if(d.action==='list'){if(d.cursor!=null&&!id(d.cursor))fail('invalid-argument');let q=db.collection('bookings').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId).orderBy('__name__');if(d.cursor)q=q.startAfter(d.cursor);const page=await tx.get(q.limit(26)),rows=page.docs.slice(0,25);const roomDocs=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));const numbers=new Map(roomDocs.docs.map(v=>[v.id,String(v.data().roomNumber??'')]));const staffDocs=await tx.get(db.collection('staffProfiles').where('organizationId','==',d.organizationId));const names=new Map(staffDocs.docs.map(v=>[v.id,String(v.data().displayName??'')]));return {records:rows.filter(v=>allows(m,'readBookings',own(v.data()))).map(v=>projection(v,numbers,names)),nextCursor:page.size>25?rows.at(-1).id:null,canManage:allows(m,'manageBookings',{...scope,anyRecord:true}),canCreate:allows(m,'createBookings',scope),timeZone:zone};}
 let current=null;
 if(['read','command'].includes(d.action)||d.action==='save'&&d.revision!=null||d.action==='quote'&&d.bookingId!=null){if(!id(d.bookingId))fail('invalid-argument');const doc=await tx.get(db.doc(`bookings/${d.bookingId}`));if(!doc.exists||doc.data().organizationId!==d.organizationId||doc.data().buildingId!==d.buildingId||!allows(m,'readBookings',own(doc.data())))fail('not-found');current=doc.data();if(d.action==='read'){const room=doc.data().roomId&&id(doc.data().roomId)?await tx.get(db.doc(`rooms/${doc.data().roomId}`)):null;const n=room?.exists&&room.data().organizationId===d.organizationId?String(room.data().roomNumber??''):'';const sid=doc.data().staffInChargeId,staffDoc=id(sid)?await tx.get(db.doc(`staffProfiles/${sid}`)):null;const names=new Map(staffDoc?.exists&&staffDoc.data().organizationId===d.organizationId?[[sid,String(staffDoc.data().displayName??'')]]:[]);return {record:projection(doc,new Map([[doc.data().roomId,n]]),names)};}if(d.action==='save'&&(d.roomId!==doc.data().roomId||!allows(m,'manageBookings',own(doc.data()))))fail(d.roomId!==doc.data().roomId?'invalid-argument':'permission-denied');}
 if(d.action==='command'){
  if(typeof d.reason!=='string'||!d.reason.trim()||d.reason.length>1000)fail('invalid-argument');
  if(!id(d.operationId)||!['status','payment','deposit','refund','refundRent','checkout'].includes(d.command)||typeof d.revision!=='string')fail('invalid-argument');
  if(['payment','deposit','refund','refundRent'].includes(d.command)&&(!Number.isSafeInteger(d.amountMinor)||d.amountMinor<=0))fail('invalid-argument');
  const doc=await tx.get(db.doc(`bookings/${d.bookingId}`)),currency=doc.data().currency;
  return {command:{...(d.inputCurrency!==undefined||d.inputAmountMinor!==undefined||d.ratesId!==undefined?{inputCurrency:d.inputCurrency,inputAmountMinor:d.inputAmountMinor,...(d.ratesId!==undefined?{ratesId:d.ratesId}:{})}:{}),action:d.command,bookingId:d.bookingId,operationId:d.operationId,revision:d.revision,...(d.amountMinor!=null?{amount:d.amountMinor/(currency==='USD'?100:1)}:{}),paymentMethod:d.paymentMethod,...(d.accountId!==undefined?{accountId:d.accountId}:{}),status:d.status,reason:d.reason}};
 }
 // New booking: createBookings. Edit: manageBookings (the booking itself was checked above). Quote: either.
 const editing=(d.action==='save'&&d.revision!=null)||(d.action==='quote'&&current!=null),canEditSome=allows(m,'manageBookings',{...scope,anyRecord:true}),canCreate=allows(m,'createBookings',scope);
 if(!(editing?canEditSome:d.action==='quote'?canCreate||canEditSome:canCreate))fail('permission-denied');
 // No room chosen (e.g. no room in this property takes short stays) is an input problem, not an access one.
 if(!id(d.roomId))fail('invalid-argument','booking_room_required');const room=await tx.get(db.doc(`rooms/${d.roomId}`));let r=room.data();if(!r||r.organizationId!==d.organizationId||r.buildingId!==d.buildingId||r.deletedAt)fail('not-found');
 // The receipt binds the original workspace request, not a recomputed quote.
 if(d.deposit!=null&&!allows(m,'collectPayments',scope))fail('permission-denied');
 if(workspaceFingerprint&&id(d.operationId)){
  const key=createHash('sha256').update(JSON.stringify(['booking',d.organizationId,uid,d.operationId])).digest('hex');
  const prior=await tx.get(db.doc(`bookingOperations/${key}`));
  if(prior.exists){if(prior.data().workspaceFingerprint!==workspaceFingerprint)fail('failed-precondition','booking_operation_reused');return prior.data().result;}
 }
 const sourceCurrency=r.currency??'VND',targetCurrency=current?.currency??d.inputCurrency??sourceCurrency;
 if(!current&&targetCurrency!==(org.data().displayCurrency??sourceCurrency))fail('failed-precondition','booking_currency_changed');
 if(current&&d.inputCurrency&&d.inputCurrency!==current.currency)fail('failed-precondition','booking_currency_changed');
 let sourceRates=null;
 if(sourceCurrency!==targetCurrency){
  try{
   const rates=await readReferenceRates(tx,db,d.ratesId);sourceRates={currency:sourceCurrency,exchangeRateSnapshotId:d.ratesId};
   r={...r,currency:targetCurrency};
   for(const key of ['nightlyPrice','hourlyPrice','dailyPrice','overnightPrice'])if(typeof r[key]==='number'){
    sourceRates[key]=r[key];const converted=convertMinor(Math.round(r[key]*(sourceCurrency==='USD'?100:1)),sourceCurrency,targetCurrency,rates);
    if(converted<=0)throw Error('booking_rate_required');r[key]=converted/(targetCurrency==='USD'?100:1);
   }
  }catch(e){fail('failed-precondition',e.message);}
 }
 if(d.overrideMinor!=null&&(!allows(m,'overridePrices',scope)||!Number.isSafeInteger(d.overrideMinor)||d.overrideMinor<=0||d.overrideMinor>1e12||typeof d.overrideReason!=='string'||!d.overrideReason.trim()||d.overrideReason.length>1000))fail('permission-denied');
 const start=localTime(d.startLocal,zone,d.occurrence),end=localTime(d.endLocal,zone,d.occurrence);if(start===null||end===null||!['hourly','daily','overnight','nightly'].includes(d.pricingType))fail('invalid-argument','booking_invalid_dates');
 const scale=(r.currency??'VND')==='USD'?100:1;
 // Custom night prices need "Đổi giá". Left out on an edit, prices already on the booking are kept while the night count still fits.
 if(d.nightPricesMinor!=null&&(d.pricingType!=='nightly'||!allows(m,'overridePrices',scope)))fail('permission-denied');
 const keptNights=d.nightPricesMinor===undefined&&d.pricingType==='nightly'&&current?.pricingType==='nightly'&&Array.isArray(current.nightPrices)?current.nightPrices.map(v=>Math.round(v*scale)):null;
 // Price per hour (2026-10-03): another price than the room's needs "Đổi giá". Left out on an edit, the booking's own hourly price is kept.
 if(d.hourlyPriceMinor!=null){const roomHourMinor=typeof r.hourlyPrice==='number'?Math.round(r.hourlyPrice*scale):null;if(d.pricingType!=='hourly'||!Number.isSafeInteger(d.hourlyPriceMinor)||d.hourlyPriceMinor<=0||d.hourlyPriceMinor>1e12)fail('invalid-argument','booking_invalid_amount');if(d.hourlyPriceMinor!==roomHourMinor&&!allows(m,'overridePrices',scope))fail('permission-denied');}
 const hourlyMinor=d.hourlyPriceMinor??(d.hourlyPriceMinor===undefined&&d.pricingType==='hourly'&&current?.pricingType==='hourly'&&typeof current.hourlyPrice==='number'?Math.round(current.hourlyPrice*scale):undefined);
 let quote;try{quote=bookingPrice(r,start,end,d.pricingType,{zone,nightPricesMinor:d.nightPricesMinor??undefined,hourlyPriceMinor:hourlyMinor});if(keptNights&&keptNights.length===quote.nights)quote=bookingPrice(r,start,end,'nightly',{zone,nightPricesMinor:keptNights});}catch(e){fail('failed-precondition',e.message);}
 if(d.overrideMinor!=null)quote.totalMinor=d.overrideMinor;
 // Surcharges are added on top of the room price (or the custom total). Left out on an edit, stored ones are kept.
 // 2026-10-04: a line is per room (once) or per person (its price × the number of guests, once).
 const guestCount=Number.isSafeInteger(d.numberOfGuests)&&d.numberOfGuests>=1&&d.numberOfGuests<=100?d.numberOfGuests:Number.isSafeInteger(current?.numberOfGuests)&&current.numberOfGuests>=1?current.numberOfGuests:1;
 const surcharges=d.surcharges!==undefined?d.surcharges:(Array.isArray(current?.surcharges)?current.surcharges.filter(plain).map(s=>s.basis==='person'?{label:s.label,amountMinor:Math.round((typeof s.unitAmount==='number'?s.unitAmount:s.amount)*scale),basis:'person'}:{label:s.label,amountMinor:Math.round(s.amount*scale)}):[]);
 if(!Array.isArray(surcharges)||surcharges.length>20||surcharges.some(s=>!plain(s)||Object.keys(s).some(k=>!['label','amountMinor','basis'].includes(k))||typeof s.label!=='string'||!s.label.trim()||s.label.length>80||!Number.isSafeInteger(s.amountMinor)||s.amountMinor<=0||s.amountMinor>1e12||s.basis!==undefined&&!['room','person'].includes(s.basis)))fail('invalid-argument','booking_invalid_surcharge');
 const lineMinor=s=>s.basis==='person'?s.amountMinor*guestCount:s.amountMinor;
 const baseMinor=quote.totalMinor,surchargesMinor=surcharges.reduce((a,s)=>a+lineMinor(s),0);quote.totalMinor=baseMinor+surchargesMinor;if(quote.totalMinor>1e12)fail('invalid-argument','booking_invalid_amount');
 if(d.action==='quote')return {record:{...quote,baseMinor,surchargesMinor,guests:guestCount,surchargeLines:surcharges.map(s=>({label:s.label.trim(),basis:s.basis==='person'?'person':'room',unitMinor:s.amountMinor,count:s.basis==='person'?guestCount:1,totalMinor:lineMinor(s)})),roomRevision:revision(room),startTime:new Date(start).toISOString(),endTime:new Date(end).toISOString(),timeZone:zone}};
 if(!id(d.bookingId)||!id(d.operationId)||!Number.isSafeInteger(d.depositMinor)||d.depositMinor<0||d.depositMinor>1e12)fail('invalid-argument');
 if(d.guests!==undefined&&(!Array.isArray(d.guests)||d.guests.some(g=>!plain(g))))fail('invalid-argument');
 // Deposit paid now: needs "Thu tiền", at most the total, on a day up to today (property time). Once recorded it is not changed here.
 let depositPayment;
 if(d.deposit!=null){
  const x=d.deposit;if(!plain(x)||Object.keys(x).some(k=>!['amountMinor','method','paidOn','inputCurrency','inputAmountMinor','ratesId'].includes(k))||!Number.isSafeInteger(x.amountMinor)||x.amountMinor<=0||!DEPOSIT_METHODS.includes(x.method)||typeof x.paidOn!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(x.paidOn))fail('invalid-argument','booking_invalid_amount');
  if(!allows(m,'collectPayments',scope))fail('permission-denied');
  if(plain(current?.depositPayment))fail('failed-precondition','booking_deposit_recorded');
  if(x.amountMinor>quote.totalMinor)fail('invalid-argument','booking_deposit_too_large');
  const today=localDay(Date.now(),zone),noon=localTime(`${x.paidOn} 12:00`,zone);
  if(noon===null||x.paidOn>today||Date.now()-noon>400*86400000)fail('invalid-argument','booking_deposit_date');
  let originalInput;
  if(x.inputCurrency!==undefined){
   if(x.inputCurrency!==(org.data().displayCurrency??targetCurrency)||!Number.isSafeInteger(x.inputAmountMinor)||x.inputAmountMinor<=0)fail('failed-precondition','booking_currency_changed');
   let amount=x.inputAmountMinor;
   if(x.inputCurrency!==targetCurrency)amount=convertMinor(amount,x.inputCurrency,targetCurrency,await readReferenceRates(tx,db,x.ratesId));
   if(amount!==x.amountMinor)fail('invalid-argument','booking_invalid_conversion');
   originalInput={currency:x.inputCurrency,amountMinor:x.inputAmountMinor,...(x.ratesId?{exchangeRateSnapshotId:x.ratesId}:{})};
  }
  depositPayment={...(originalInput?{originalInput}:{}),amount:x.amountMinor/scale,paymentMethod:x.method,paidOn:x.paidOn,paidAt:{__timestamp:x.paidOn===today?Date.now():noon}};
 }
 // Co-guest CCCD: left out = keep the stored number (people without "Xem số CCCD" only ever see it masked).
 const oldGuests=Array.isArray(current?.guests)?current.guests.filter(plain):[];
 const details={};for(const k of DETAILS)if(d[k]!==undefined)details[k]=typeof d[k]==='string'?(d[k].trim()||null):d[k];
 if(d.guests!==undefined)details.guests=d.guests.map(g=>({id:g.id,name:typeof g.name==='string'?g.name.trim():g.name,idNumber:g.idNumber!==undefined?(typeof g.idNumber==='string'?(g.idNumber.trim()||null):g.idNumber):(oldGuests.find(o=>o.id===g.id)?.idNumber??null)}));
 const priced={surcharges:surcharges.map(s=>({label:s.label.trim(),amount:lineMinor(s)/scale,...(s.basis==='person'?{basis:'person',unitAmount:s.amountMinor/scale,count:guestCount}:{})})),nightPrices:quote.pricingType==='nightly'?quote.nightPricesMinor.map(v=>v/scale):null,hourlyPrice:quote.pricingType==='hourly'&&quote.hourlyPriceMinor!=null?quote.hourlyPriceMinor/scale:null};
 return {workspaceFingerprint,serverQuote:{currency:targetCurrency,...(sourceRates?{sourceRates}:{}),total:quote.totalMinor/scale,pricingType:quote.pricingType},command:{action:d.revision==null?'create':'edit',bookingId:d.bookingId,operationId:d.operationId,...(d.revision!=null?{revision:d.revision}:{}),roomRevision:d.roomRevision,propertyRevision:revision(building),serverPricing:d.overrideMinor==null,...(depositPayment?{depositPayment}:{}),...(d.overrideMinor!=null?{priceOverrideReason:d.overrideReason}:{}),booking:{...(d.overrideMinor!=null?{totalPrice:d.overrideMinor/(quote.currency==='USD'?100:1)}:{}),organizationId:d.organizationId,roomId:d.roomId,guestName:d.guestName,guestPhone:d.guestPhone,notes:d.notes,pricingType:d.pricingType,...details,...priced,startTime:{__timestamp:start},endTime:{__timestamp:end},depositAmount:d.depositMinor/(quote.currency==='USD'?100:1)}}};
 });
 if(prepared.command){const c=prepared.command;if(c.action==='edit'){c.changes=c.booking;delete c.booking;}return calendar(c,{auth:request.auth,serverQuote:prepared.serverQuote??null,workspaceFingerprint:prepared.workspaceFingerprint??null});}return prepared;
};}
module.exports={createBookingWorkspaceHandler};
