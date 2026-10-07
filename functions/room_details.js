'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {createBulkRoomsHandler}=require('./bulk_rooms');
const {retainDeletedRecord}=require('./deleted_records');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const revision=doc=>`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
const normalized=v=>String(v??'').trim().normalize('NFKC').toLowerCase();
function createRoomDetailsHandler({db,Timestamp,HttpsError}) {
  const bulk=createBulkRoomsHandler({db,Timestamp,HttpsError});
  const fail=code=>{throw new HttpsError(code,'room_'+code);};
  return async request=>{
    if(['prepareBulk','createBulk'].includes(request.data?.action))return bulk(request);
    const uid=request.auth?.uid,d=request.data||{},creating=d.action==='create',deleting=d.action==='delete',editing=d.action==='update'||creating;
    if(!uid)fail('unauthenticated');
    const keys=['action','organizationId','buildingId','roomId',...(deleting?['operationId','revision']:[]),...(editing?['operationId',...(!creating?['revision']:[]),'roomNumber','roomType','area']:[])];
    if(!['read','update','prepareCreate','create','delete'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||!id(d.roomId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
    if(editing&&(!id(d.operationId)||(!creating&&(typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))||typeof d.roomNumber!=='string'||!d.roomNumber.trim()||d.roomNumber.length>80||typeof d.roomType!=='string'||d.roomType.length>160||typeof d.area!=='number'||!Number.isFinite(d.area)||d.area<=0||d.area>100000))fail('invalid-argument');
    if(deleting&&(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))fail('invalid-argument');
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`));
      const member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      if(!org.exists||org.data().accessVersion!==2||!allows(member.data(),deleting?'deleteRooms':'manageProperty',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId}))fail('permission-denied');
      if(deleting){
        const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
        const key=hash(['roomDetails',d.organizationId,uid,d.operationId]),fingerprint=hash(keys.map(k=>d[k]));
        const operation=db.doc(`roomOperations/${key}`),prior=await tx.get(operation);
        // A successful retry must work even if its now-empty property was removed.
        if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
        const building=await tx.get(db.doc(`buildings/${d.buildingId}`));
        const ref=db.doc(`rooms/${d.roomId}`),doc=await tx.get(ref),old=doc.data();
        if(!building.exists||building.data().organizationId!==d.organizationId||!old||old.organizationId!==d.organizationId||old.buildingId!==d.buildingId)fail('not-found');
        if(revision(doc)!==d.revision)fail('aborted');
        for(const collection of ['tenants','bookings','payments','housekeepingTasks','utilityMeters','serviceFeeRooms']){
          if(!(await tx.get(db.collection(collection).where('roomId','==',d.roomId).limit(1))).empty)throw new HttpsError('failed-precondition','room_not_empty');
        }
        // A tenant/booking may have moved: its earlier room still has history.
        for(const field of ['before.roomId','after.roomId']){
          if(!(await tx.get(db.collection('teamActivity').where(field,'==',d.roomId).limit(1))).empty)throw new HttpsError('failed-precondition','room_not_empty');
        }
        if((await ref.listCollections()).length)throw new HttpsError('failed-precondition','room_not_empty');
        const now=Timestamp.now(),result={roomId:d.roomId,deleted:true};
        retainDeletedRecord(tx,db,{type:'rooms',recordId:d.roomId,data:old,actorId:uid,Timestamp,operationId:d.operationId});
        tx.delete(ref);
        tx.update(building.ref,{roomInventoryUpdatedAt:now});
        tx.create(operation,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
        tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'room_deleted',targetId:d.roomId,createdAt:now,before:{buildingId:d.buildingId,roomNumber:old.roomNumber??'',roomType:old.roomType??'',area:old.area??null},after:null});
        return result;
      }
      const building=await tx.get(db.doc(`buildings/${d.buildingId}`));
      if(!building.exists||building.data().organizationId!==d.organizationId)fail('not-found');
      const currency=building.data().currency??'VND';
      if((creating||d.action==='prepareCreate')&&!['VND','USD'].includes(currency))fail('failed-precondition');
      if(d.action==='prepareCreate')return {record:{id:d.roomId,roomNumber:building.data().roomPrefix??'',roomType:building.data().roomType??'',area:building.data().roomArea??0,revision:'new',currency}};
      const ref=db.doc(`rooms/${d.roomId}`),doc=await tx.get(ref),old=doc.data();
      if(!creating&&(!old||old.organizationId!==d.organizationId||old.buildingId!==d.buildingId))fail('not-found');
      const details=value=>({roomNumber:value.roomNumber??'',roomType:value.roomType??'',area:value.area??0});
      if(!editing)return {record:{id:doc.id,...details(old),revision:revision(doc)}};
      const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
      const key=hash(['roomDetails',d.organizationId,uid,d.operationId]),fingerprint=hash(keys.map(k=>d[k]));
      const operation=db.doc(`roomOperations/${key}`),prior=await tx.get(operation);
      if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
      if(creating&&old)fail('failed-precondition');
      if(!creating&&revision(doc)!==d.revision)fail('aborted');
      if(creating||normalized(d.roomNumber)!==normalized(old.roomNumber)) {
        // Include legacy labels without a normalized field. The transaction reads
        // peer rooms so concurrent renames cannot claim the same label.
        const peers=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
        if(peers.docs.some(peer=>peer.id!==d.roomId&&normalized(peer.data().roomNumber)===normalized(d.roomNumber)))fail('already-exists');
      }
      const now=Timestamp.now(),patch={roomNumber:d.roomNumber.trim(),roomType:d.roomType.trim(),area:d.area},result={roomId:d.roomId};
      if(creating) {
        tx.create(ref,{...patch,organizationId:d.organizationId,buildingId:d.buildingId,currency,rentalMode:'both',createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid});
        // Serialize creates even when the property has no rooms yet.
        tx.update(building.ref,{roomInventoryUpdatedAt:now});
      } else tx.update(ref,{...patch,updatedAt:now,updatedBy:uid});
      tx.create(operation,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
      tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:creating?'room_created':'room_details_updated',targetId:d.roomId,createdAt:now,before:creating?null:{buildingId:d.buildingId,...details(old)},after:{buildingId:d.buildingId,...patch,...(creating?{currency,rentalMode:'monthly'}:{})}});
      return result;
    });
  };
}
module.exports={createRoomDetailsHandler};
