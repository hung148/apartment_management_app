'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validInitialRooms}=require('./property_details');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const normalized=v=>String(v??'').trim().normalize('NFKC').toLowerCase();
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const prices=['roomPrice','nightlyPrice','hourlyPrice'];
function createBulkRoomsHandler({db,Timestamp,HttpsError}) {
  return async request=>{
    const fail=code=>{throw new HttpsError(code,'room_'+code);};
    const uid=request.auth?.uid,d=request.data??{},creating=d.action==='createBulk';
    if(!uid)fail('unauthenticated');
    const keys=['action','organizationId','buildingId',...(creating?['operationId','rooms',...(Object.hasOwn(d,'currency')?['currency']:[])]:[])];
    if(!['prepareBulk','createBulk'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||Object.keys(d).some(k=>!keys.includes(k))||
      creating&&((Object.hasOwn(d,'currency')&&!['VND','USD'].includes(d.currency))||!id(d.operationId)||!validInitialRooms(d.rooms)||!d.rooms.length))fail('invalid-argument');
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`));
      const member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
      if(!org.exists||org.data().accessVersion!==2||!allows(member.data(),'manageProperty',scope))fail('permission-denied');
      const canSetRoomPrices=allows(member.data(),'overridePrices',scope);
      if(creating&&!canSetRoomPrices&&d.rooms.some(r=>prices.some(k=>r.ratesMinor[k]!==null)))fail('permission-denied');
      const building=await tx.get(db.doc(`buildings/${d.buildingId}`));
      if(!building.exists||building.data().organizationId!==d.organizationId)fail('not-found');
      const selected=org.data().displayCurrency??building.data().currency??'VND';
      const currency=creating?(d.currency??building.data().currency??'VND'):selected;
      if(!['VND','USD'].includes(currency))fail('failed-precondition');
      if(!creating)return {record:{currency,canSetRoomPrices}};
      const key=hash(['bulkRooms',d.organizationId,uid,d.operationId]),fingerprint=hash(keys.map(k=>d[k]));
      const operation=db.doc(`roomOperations/${key}`),prior=await tx.get(operation);
      if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
      // Old clients submit amounts in the building's currency. Never silently
      // reinterpret those amounts after the organization setting changes.
      // Committed retries above remain valid in their original currency.
      if(currency!==selected)fail('aborted');
      const peers=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
      const names=new Set(peers.docs.map(p=>normalized(p.data().roomNumber)));
      if(d.rooms.some(r=>names.has(normalized(r.roomNumber))))fail('already-exists');
      const refs=d.rooms.map((_,index)=>db.doc(`rooms/${hash(['bulkRoom',d.organizationId,uid,d.operationId,index])}`));
      for(const ref of refs)if((await tx.get(ref)).exists)fail('already-exists');
      const now=Timestamp.now(),result={roomIds:refs.map(r=>r.id)};
      for(const [index,r] of d.rooms.entries()){
        const data={organizationId:d.organizationId,buildingId:d.buildingId,roomNumber:r.roomNumber.trim(),roomType:r.roomType.trim(),area:r.area??0,currency,rentalMode:'both',
          ...Object.fromEntries(prices.map(k=>[k,r.ratesMinor[k]===null?null:r.ratesMinor[k]/(currency==='USD'?100:1)]))};
        tx.create(refs[index],{...data,createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid});
        tx.create(db.doc(`teamActivity/${key}_${index}`),{organizationId:d.organizationId,actorId:uid,action:'room_created',targetId:refs[index].id,createdAt:now,before:null,after:data});
      }
      // Same serialization point as single-room creation and property deletion.
      tx.update(building.ref,{roomInventoryUpdatedAt:now});
      tx.create(operation,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
      return result;
    });
  };
}
module.exports={createBulkRoomsHandler};
