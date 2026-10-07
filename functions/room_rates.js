'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
// 2026-10-04: a room has a monthly price, a price per night and a price per hour.
// Day and overnight prices (and the day-price hour threshold) are gone; an older
// day price is shown as the night price until the room is saved again.
const fields=['roomPrice','nightlyPrice','hourlyPrice'];
const stored=(room,k)=>k==='nightlyPrice'?room.nightlyPrice??room.dailyPrice:room[k];
const revision=doc=>`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
function createRoomRatesHandler({db,Timestamp,HttpsError}) {
  const fail=(code,message='room_rates_'+code)=>{throw new HttpsError(code,message);};
  return async request=>{
    const uid=request.auth?.uid,d=request.data||{},editing=d.action==='update';
    if(!uid)fail('unauthenticated');
    const keys=['action','organizationId','buildingId','roomId',...(editing?['operationId','revision','rentalMode','ratesMinor']:[])];
    if(!['read','update'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||!id(d.roomId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
    if(editing) {
      if(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)||d.rentalMode!==undefined&&!['monthly','hourly','both'].includes(d.rentalMode)||!d.ratesMinor||typeof d.ratesMinor!=='object'||Array.isArray(d.ratesMinor)||Object.keys(d.ratesMinor).length!==fields.length||fields.some(k=>!Object.hasOwn(d.ratesMinor,k)||d.ratesMinor[k]!==null&&(!Number.isSafeInteger(d.ratesMinor[k])||d.ratesMinor[k]<=0||d.ratesMinor[k]>1e12)))fail('invalid-argument');
      // 2026-10-04: every room takes short stays and leases; each price is optional
      // (a booking or a lease without a room price asks for one). rentalMode from older apps is ignored.
    }
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`));
      const membership=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
      if(!org.exists||org.data().accessVersion!==2||!allows(membership.data(),'manageProperty',scope)||!allows(membership.data(),'overridePrices',scope))fail('permission-denied');
      const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),ref=db.doc(`rooms/${d.roomId}`),doc=await tx.get(ref),old=doc.data();
      if(!building.exists||building.data().organizationId!==d.organizationId||!old||old.organizationId!==d.organizationId||old.buildingId!==d.buildingId)fail('not-found');
      const currency=old.currency??'VND',mode=old.rentalMode??'monthly';
      if(!['VND','USD'].includes(currency))fail('failed-precondition');
      const factor=currency==='USD'?100:1;
      const ratesMinor=Object.fromEntries(fields.map(k=>{
        const value=stored(old,k);if(value==null)return [k,null];
        const minor=Math.round(value*factor);
        if(typeof value!=='number'||!Number.isFinite(value)||value<0||!Number.isSafeInteger(minor)||Math.abs(value*factor-minor)>0.000001||minor>1e12)fail('failed-precondition');
        return [k,minor===0?null:minor];
      }));
      if(!editing)return {record:{roomId:d.roomId,roomNumber:old.roomNumber??'',currency,rentalMode:'both',ratesMinor,revision:revision(doc)}};
      const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
      const key=hash(['roomRates',d.organizationId,uid,d.operationId]),fingerprint=hash([d.buildingId,d.roomId,d.revision,fields.map(k=>d.ratesMinor[k])]);
      const op=db.doc(`roomRateOperations/${key}`),prior=await tx.get(op);
      if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
      if(revision(doc)!==d.revision)fail('aborted');
      const now=Timestamp.now(),patch={rentalMode:'both',...Object.fromEntries(fields.map(k=>[k,d.ratesMinor[k]===null?null:d.ratesMinor[k]/factor])),dailyPrice:null,overnightPrice:null,dailyPriceThresholdHours:null},result={roomId:d.roomId};
      tx.update(ref,{...patch,updatedAt:now,updatedBy:uid});
      tx.create(op,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
      tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'room_rates_updated',targetId:d.roomId,createdAt:now,before:{buildingId:d.buildingId,currency,rentalMode:mode,...Object.fromEntries(['roomPrice','nightlyPrice','hourlyPrice','dailyPrice','overnightPrice','dailyPriceThresholdHours'].map(k=>[k,old[k]??null]))},after:{buildingId:d.buildingId,currency,...patch}});
      return result;
    });
  };
}
module.exports={createRoomRatesHandler};
