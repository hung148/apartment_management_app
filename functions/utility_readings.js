'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validDate}=require('./property_contract');
const {propertyDate}=require('./lease_dates');
const {validZone}=require('./booking_settings');
const {validateTariff,utilityCharge,meterUsage}=require('./utility_math');
const {addTariff,resolveTariff}=require('./utility_tariffs');
const {driveAccess}=require('./drive');
// 2026-10-04: a photo of the meter with a reading, kept in the owner's Google Drive.
const MAX_PHOTOS=3,MAX_PHOTO_BYTES=2*1024*1024;
const PHOTO_TYPES={'image/jpeg':b=>b[0]===0xff&&b[1]===0xd8&&b[2]===0xff,'image/png':b=>b[0]===0x89&&b.toString('latin1',1,4)==='PNG','image/webp':b=>b.toString('latin1',0,4)==='RIFF'&&b.toString('latin1',8,12)==='WEBP'};
const EXT={'image/jpeg':'jpg','image/png':'png','image/webp':'webp'};
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
function createUtilityReadingsHandler({db,Timestamp,HttpsError,drive,getDrive}){
 const fail=(code,key='utility_'+code)=>{throw new HttpsError(code,key);};
 let drives=null;const driveFor=()=>{const dr=drive??getDrive?.();if(!dr)return null;drives??=driveAccess({db,drive:dr,HttpsError});return drives;};
 return async request=>{
  const uid=request.auth?.uid,d=request.data??{},write=['tariff','record','reverse'].includes(d.action);
  if(!uid)fail('unauthenticated');
  if(['addPhoto','photo'].includes(d.action))return photos(d,uid,request);
  const base=['action','organizationId','buildingId','roomId','kind'];
  const keys=[...base,...(d.action==='read'?['cursor']:[]),...(write?['operationId','revision','reason']:[]),...(d.action==='tariff'?['tariff','effectiveDate','tariffScope','propertyRevision']:[]),...(d.action==='reverse'?['readingId']:[]),...(d.action==='record'?['date','readingMilli','oldFinalMilli','newStartMilli']:[])];
  if(!['read','tariff','record','reverse'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||!id(d.roomId)||!['electricity','water'].includes(d.kind)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
  if(d.action==='reverse'&&!id(d.readingId))fail('invalid-argument');
  if(d.cursor!=null&&!id(d.cursor))fail('invalid-argument');
  if(write&&(!id(d.operationId)||!Number.isSafeInteger(d.revision)||d.revision<0||typeof d.reason!=='string'||!d.reason.trim()||d.reason.length>1000))fail('invalid-argument');
  if(d.action==='tariff'){
   if(!validDate(d.effectiveDate)||!['room','property'].includes(d.tariffScope)||!Number.isSafeInteger(d.propertyRevision)||d.propertyRevision<0||(d.tariffScope==='property'&&d.tariff===null))fail('invalid-argument');
   if(d.tariff!==null)try{validateTariff(d.tariff);}catch(e){fail('invalid-argument',e.message);}
  }
  if(d.action==='record'&&(!validDate(d.date)||!Number.isSafeInteger(d.readingMilli)||d.readingMilli<0||d.readingMilli>1e12))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
   const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId},m=member.data();
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||!allows(m,'manageLease',scope)||(['tariff','reverse'].includes(d.action)&&!allows(m,'overridePrices',scope)))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),room=await tx.get(db.doc(`rooms/${d.roomId}`));
   if(!building.exists||building.data().organizationId!==d.organizationId||!room.exists||room.data().organizationId!==d.organizationId||room.data().buildingId!==d.buildingId)fail('not-found');
   const currency=room.data().currency??building.data().currency??'VND',zone=building.data().timeZone;
   const meterId=hash([d.organizationId,d.roomId,d.kind]),ref=db.doc(`utilityMeters/${meterId}`),meter=await tx.get(ref),old=meter.data()??{revision:0};
   const propertyRef=db.doc(`utilityTariffs/${hash([d.organizationId,d.buildingId,d.kind])}`),propertySnapshot=await tx.get(propertyRef),property=propertySnapshot.data()??{revision:0,history:[]};
   if(d.action==='read'){
    let query=ref.collection('readings').orderBy('date');
    if(d.cursor){const cursor=await tx.get(ref.collection('readings').doc(d.cursor));if(!cursor.exists)fail('invalid-argument');query=query.startAfter(cursor);}
    const page=await tx.get(query.limit(51)),rows=page.docs.slice(0,50);
    return {record:{roomNumber:room.data().roomNumber??'',currency,revision:old.revision,propertyRevision:property.revision,tariff:old.tariff??null,roomTariffs:old.tariffHistory??[],propertyTariffs:property.history,lastReadingId:old.lastReadingId??null,lastDate:old.lastDate??null,lastReadingMilli:old.lastReadingMilli??null,canBill:allows(m,'readFinancialReports',scope)&&allows(m,'collectPayments',scope),canPrice:allows(m,'overridePrices',scope),today:validZone(zone)?propertyDate(Timestamp.now().toMillis(),zone):null},records:rows.map(x=>({id:x.id,...x.data(),createdAt:x.data().createdAt?.toDate().toISOString(),reversedAt:x.data().reversedAt?.toDate().toISOString()??null})),nextCursor:page.size>50?rows.at(-1).id:null};
   }
   const operation=ref.collection('operations').doc(hash([uid,d.operationId])),prior=await tx.get(operation),fingerprint=hash(keys.map(k=>d[k]??null));
   if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
   if(old.revision!==d.revision)fail('aborted','utility_changed');
   const now=Timestamp.now(),patch={organizationId:d.organizationId,buildingId:d.buildingId,roomId:d.roomId,kind:d.kind,revision:old.revision+1,updatedAt:now,updatedBy:uid};
   let result={revision:patch.revision};
   if(d.action==='reverse'){
    const readingRef=ref.collection('readings').doc(d.readingId),snapshot=await tx.get(readingRef),reading=snapshot.data();
    if(!reading||old.lastReadingId!==d.readingId||reading.reversedAt)fail('failed-precondition','utility_reverse_latest_only');
    if(reading.invoiceId)fail('failed-precondition','utility_void_invoice_first');
    tx.update(readingRef,{reversedAt:now,reversedBy:uid,reversalReason:d.reason.trim()});
    patch.lastDate=reading.startDate;patch.lastReadingMilli=reading.previousReadingMilli;patch.lastReadingId=reading.previousReadingId??null;
   }else if(d.action==='tariff'){
    if(property.revision!==d.propertyRevision)fail('aborted','utility_changed');
    const expectedCurrency=d.tariffScope==='property'?(building.data().currency??'VND'):currency;
    if(d.tariff!==null&&d.tariff.currency!==expectedCurrency)fail('failed-precondition','utility_currency_changed');
    const tariff=d.tariff===null?null:{currency:expectedCurrency,bands:d.tariff.bands.map(b=>({throughMilli:b.throughMilli,priceMinor:b.priceMinor}))};
    if(d.tariffScope==='property'){
     // Do not introduce prices into intervals that any room already measured.
     const meters=await tx.get(db.collection('utilityMeters').where('buildingId','==',d.buildingId).where('kind','==',d.kind));
     const latest=meters.docs.filter(x=>x.data().organizationId===d.organizationId).map(x=>x.data().lastDate??'').sort().at(-1)??null;
     let history;try{history=addTariff(property.history,{effectiveDate:d.effectiveDate,tariff},latest);}catch(e){fail('failed-precondition',e.message);}
     tx.set(propertyRef,{organizationId:d.organizationId,buildingId:d.buildingId,kind:d.kind,revision:property.revision+1,history,updatedAt:now,updatedBy:uid});
    }else{
     try{patch.tariffHistory=addTariff(old.tariffHistory??[],{effectiveDate:d.effectiveDate,tariff},old.lastDate);}catch(e){fail('failed-precondition',e.message);}
     patch.tariff=tariff;
    }
   }else{
    if(!validZone(zone))fail('failed-precondition','utility_timezone_required');
    const today=propertyDate(now.toMillis(),zone);
    if(!today)fail('failed-precondition','utility_timezone_required');
    if(d.date>today)fail('invalid-argument','utility_future_reading');
    if(d.date<today&&!allows(m,'backdateRecords',{organizationId:d.organizationId,userId:uid}))fail('permission-denied','utility_backdate_denied');
    if(old.lastDate&&d.date<=old.lastDate)fail('failed-precondition','utility_reading_order');
    const baseline=old.lastReadingMilli==null;
    if(baseline&&(d.oldFinalMilli!=null||d.newStartMilli!=null))fail('invalid-argument','utility_invalid_reset');
    let tariff=null;
    if(!baseline)try{tariff=resolveTariff(old.tariffHistory??[],property.history,old.lastDate,d.date,currency);}catch(e){fail('failed-precondition',e.message);}
    let calculation=null;
    if(!baseline)try{calculation=utilityCharge(meterUsage(old.lastReadingMilli,d.readingMilli,{oldFinalMilli:d.oldFinalMilli??null,newStartMilli:d.newStartMilli??null}),tariff);}catch(e){fail('invalid-argument',e.message);}
    const readingId=hash([uid,d.operationId]);
    tx.create(ref.collection('readings').doc(readingId),{organizationId:d.organizationId,buildingId:d.buildingId,roomId:d.roomId,kind:d.kind,date:d.date,readingMilli:d.readingMilli,startDate:old.lastDate??null,previousReadingId:old.lastReadingId??null,previousReadingMilli:old.lastReadingMilli??null,oldFinalMilli:d.oldFinalMilli??null,newStartMilli:d.newStartMilli??null,tariff,calculation,reason:d.reason.trim(),createdAt:now,createdBy:uid,invoiceId:null});
    patch.lastReadingId=readingId;patch.lastDate=d.date;patch.lastReadingMilli=d.readingMilli;result={...result,readingId,calculation};
   }
   tx.set(ref,{...old,...patch});tx.create(operation,{organizationId:d.organizationId,fingerprint,result,action:d.action,reason:d.reason.trim(),actorId:uid,createdAt:now});
   tx.create(db.doc(`teamActivity/${hash(['utility',d.organizationId,d.roomId,d.kind,uid,d.operationId])}`),{organizationId:d.organizationId,actorId:uid,action:'utility_'+d.action,targetId:meterId,createdAt:now,before:{roomId:d.roomId,buildingId:d.buildingId,lastDate:old.lastDate??null},after:{roomId:d.roomId,buildingId:d.buildingId,revision:patch.revision,kind:d.kind},reason:d.reason.trim()});return result;
  });
 };

 // Meter photos talk to Google Drive, which cannot be part of a Firestore
 // transaction: check, upload, then record in one transaction (undo the upload if it lost).
 async function photos(d,uid,request){
  const keys=['action','organizationId','buildingId','roomId','kind','readingId',...(d.action==='addPhoto'?['operationId','mimeType','dataBase64']:['photoId'])];
  if(!id(d.organizationId)||!id(d.buildingId)||!id(d.roomId)||!['electricity','water'].includes(d.kind)||!id(d.readingId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
  if(d.action==='photo'&&typeof d.photoId!=='string')fail('invalid-argument');
  if(d.action==='addPhoto'&&(!id(d.operationId)||!Object.hasOwn(PHOTO_TYPES,d.mimeType)||typeof d.dataBase64!=='string'||d.dataBase64.length>Math.ceil(MAX_PHOTO_BYTES/3)*4+4||!/^[A-Za-z0-9+/]+={0,2}$/.test(d.dataBase64)))fail('invalid-argument','utility_photo_invalid');
  const org=(await db.doc(`organizations/${d.organizationId}`).get()).data(),m=(await db.doc(`memberships/${uid}_${d.organizationId}`).get()).data();
  const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
  if(!org||org.accessVersion!==2||org.closedAt||!allows(m,'manageLease',scope))fail('permission-denied');
  const b=(await db.doc(`buildings/${d.buildingId}`).get()).data(),room=(await db.doc(`rooms/${d.roomId}`).get()).data();
  if(!b||b.organizationId!==d.organizationId||!room||room.organizationId!==d.organizationId||room.buildingId!==d.buildingId)fail('not-found');
  const ref=db.doc(`utilityMeters/${hash([d.organizationId,d.roomId,d.kind])}/readings/${d.readingId}`),reading=(await ref.get()).data();
  if(!reading||reading.organizationId!==d.organizationId)fail('not-found','utility_reading_not_found');
  const list=reading.photos??[];
  const access=driveFor();if(!access)fail('failed-precondition','drive_not_configured');
  if(d.action==='photo'){
   if(!list.some(x=>x.id===d.photoId))fail('not-found','utility_photo_missing');
   const session=await access.open(d.organizationId),file=await session.download(d.photoId);
   return {photoId:d.photoId,mimeType:file.mimeType,dataBase64:file.bytes.toString('base64')};
  }
  const key=hash(['utilityPhoto',d.organizationId,uid,d.operationId]),op=db.doc(`utilityPhotoOperations/${key}`);
  const fingerprint=hash([d.roomId,d.kind,d.readingId,d.mimeType,hash(d.dataBase64)]);
  const prior=(await op.get()).data();
  if(prior){if(prior.fingerprint!==fingerprint)fail('failed-precondition');return prior.result;}
  if(list.length>=MAX_PHOTOS)fail('failed-precondition','utility_photo_limit');
  const bytes=Buffer.from(d.dataBase64,'base64');
  if(!bytes.length||bytes.length>MAX_PHOTO_BYTES||!PHOTO_TYPES[d.mimeType](bytes))fail('invalid-argument','utility_photo_invalid');
  const now=Timestamp.now(),today=b.timeZone?propertyDate(now.toMillis(),b.timeZone):null;
  const session=await access.open(d.organizationId),folder=await session.metersFolder(d.buildingId,b.name);
  const label=d.kind==='electricity'?'Điện':'Nước';
  const fileName=`${room.roomNumber||'Phong'} ${label} ${reading.date} (${list.length+1}).${EXT[d.mimeType]}`.replace(/[\\/:*?"<>|]+/g,' ').replace(/\s+/g,' ').trim();
  const file=await session.upload({name:fileName,mimeType:d.mimeType,parent:folder,bytes});
  const photo={id:file.id,mimeType:d.mimeType,sizeBytes:bytes.length,addedBy:uid,addedLocalDate:today,addedAt:now};
  let lost=false;
  const result=await db.runTransaction(async tx=>{
   const again=await tx.get(op);if(again.exists){lost=true;return again.data().result;}
   const cur=(await tx.get(ref)).data();
   if(!cur)fail('not-found','utility_reading_not_found');
   if((cur.photos??[]).length>=MAX_PHOTOS){lost=true;fail('failed-precondition','utility_photo_limit');}
   tx.update(ref,{photos:[...(cur.photos??[]),photo]});
   const out={readingId:d.readingId,photo:{id:photo.id,mimeType:photo.mimeType,addedLocalDate:today}};
   tx.create(op,{organizationId:d.organizationId,actorId:uid,createdAt:now,fingerprint,result:out});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'utility_photo_add',targetId:d.readingId,after:{buildingId:d.buildingId,roomId:d.roomId,kind:d.kind}});
   return out;
  }).catch(async e=>{await session.trash(file.id).catch(()=>{});throw e;});
  if(lost)await session.trash(file.id).catch(()=>{});
  return result;
 }
}
module.exports={createUtilityReadingsHandler};
