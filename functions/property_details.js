'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validZone}=require('./booking_settings');
const {retainDeletedRecord}=require('./deleted_records');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const revision=doc=>`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
const priceFields=['roomPrice','nightlyPrice','hourlyPrice'];
const validAmount=v=>Number.isSafeInteger(v)&&v>=0&&v<=1e12;
const normalized=v=>v.trim().normalize('NFKC').toLowerCase();
function validInitialRooms(rooms){
  if(!Array.isArray(rooms)||rooms.length>50)return false;
  const names=new Set();
  return rooms.every(r=>{
    if(!r||typeof r!=='object'||Array.isArray(r)||Object.keys(r).length!==4||
      !['roomNumber','roomType','area','ratesMinor'].every(k=>Object.hasOwn(r,k))||
      typeof r.roomNumber!=='string'||!r.roomNumber.trim()||r.roomNumber.length>80||
      typeof r.roomType!=='string'||r.roomType.length>160||
      (r.area!==null&&(typeof r.area!=='number'||!Number.isFinite(r.area)||r.area<=0||r.area>100000))||
      !r.ratesMinor||typeof r.ratesMinor!=='object'||Array.isArray(r.ratesMinor)||Object.keys(r.ratesMinor).length!==3||
      !priceFields.every(k=>Object.hasOwn(r.ratesMinor,k)&&(r.ratesMinor[k]===null||validAmount(r.ratesMinor[k])&&r.ratesMinor[k]>0)))return false;
    const name=normalized(r.roomNumber);if(names.has(name))return false;names.add(name);return true;
  });
}
function createPropertyDetailsHandler({db,Timestamp,HttpsError}) {
  const fail=(code)=>{throw new HttpsError(code,'property_'+code);};
  return async request=>{
    const uid=request.auth?.uid,d=request.data||{};
    if(!uid)fail('unauthenticated');
    const deleting=d.action==='delete';
    const creating=d.action==='create',preparing=d.action==='prepareCreate',editing=d.action==='update'||creating;
    const keys=['action','organizationId','buildingId',...(deleting?['operationId','revision']:[]),...(editing?['operationId',...(!creating?['revision']:[]),'name','address',...(Object.hasOwn(d,'timeZone')?['timeZone']:[]),...(Object.hasOwn(d,'exploitationCostMinor')?['exploitationCostMinor']:[]),...(creating?['currency',...(Object.hasOwn(d,'rooms')?['rooms']:[])]:[])]:[])];
    if(editing&&Object.hasOwn(d,'exploitationCostMinor')&&d.exploitationCostMinor!==null&&!validAmount(d.exploitationCostMinor))fail('invalid-argument');
    if(creating&&Object.hasOwn(d,'rooms')&&!validInitialRooms(d.rooms))fail('invalid-argument');
    if(Object.hasOwn(d,'timeZone')&&d.timeZone!==null&&!validZone(d.timeZone))fail('invalid-argument');
    if(!['read','update','prepareCreate','create','delete'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
    if(editing&&(!id(d.operationId)||(!creating&&(typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))||typeof d.name!=='string'||!d.name.trim()||d.name.length>160||typeof d.address!=='string'||!d.address.trim()||d.address.length>500))fail('invalid-argument');
    if(deleting&&(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))fail('invalid-argument');
    if(creating&&(!validZone(d.timeZone)||!['VND','USD'].includes(d.currency)))fail('invalid-argument');
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`));
      const member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      if(!org.exists||org.data().accessVersion!==2||!allows(member.data(),deleting?'deleteBuildings':'manageProperty',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId}))fail('permission-denied');
      if((creating||preparing)&&member.data().buildingScope!=='all')fail('permission-denied');
      const canSetRoomPrices=allows(member.data(),'overridePrices',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId});
      if(creating&&(d.rooms??[]).some(r=>priceFields.some(k=>r.ratesMinor[k]!==null))&&!canSetRoomPrices)fail('permission-denied');
      if(preparing)return {record:{id:d.buildingId,name:'',address:'',timeZone:'Asia/Ho_Chi_Minh',currency:'VND',exploitationCostMinor:null,canSetRoomPrices,revision:'new'}};
      const ref=db.doc(`buildings/${d.buildingId}`),doc=await tx.get(ref),old=doc.data();
      if(!creating&&!deleting&&(!old||old.organizationId!==d.organizationId))fail('not-found');
      if(!editing&&!deleting)return {record:{id:doc.id,name:old.name??'',address:old.address??'',timeZone:old.timeZone??null,currency:old.currency??'VND',exploitationCostMinor:old.exploitationCostMinor??null,revision:revision(doc)}};
      const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
      const key=hash(['propertyDetails',d.organizationId,uid,d.operationId]);
      const operation=db.doc(`propertyOperations/${key}`),prior=await tx.get(operation);
      const fingerprint=hash(keys.map(k=>d[k]));
      if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('already-exists');return prior.data().result;}
      if(deleting&&(!old||old.organizationId!==d.organizationId))fail('not-found');
      if(creating&&old)fail('already-exists');
      if(!creating&&revision(doc)!==d.revision)fail('aborted');
      if(deleting){
        if(old.rentalContract!=null||old.managementType==='rented'||['renterName','renterPhone','rentAmount','rentDueDay','rentContractStart','rentContractEnd','renterNotes'].some(field=>old[field]!=null&&old[field]!==''))throw new HttpsError('failed-precondition','property_not_empty');
        // Never cascade: even cancelled/completed operational history blocks removal.
        for(const collection of ['rooms','tenants','bookings','payments','housekeepingTasks','utilityMeters','utilityTariffs','serviceFees','serviceFeeRooms']){
          const linked=await tx.get(db.collection(collection).where('buildingId','==',d.buildingId).limit(1));
          if(!linked.empty)throw new HttpsError('failed-precondition','property_not_empty');
        }
        const members=await tx.get(db.collection('memberships').where('buildingIds','array-contains',d.buildingId).limit(1));
        const invites=await tx.get(db.collection('teamInvitations').where('access.buildingIds','array-contains',d.buildingId).limit(1));
        if(!members.empty||!invites.empty)throw new HttpsError('failed-precondition','property_has_assignments');
        if((await ref.listCollections()).length)throw new HttpsError('failed-precondition','property_not_empty');
        const now=Timestamp.now(),result={buildingId:d.buildingId,deleted:true};
        retainDeletedRecord(tx,db,{type:'buildings',recordId:d.buildingId,data:old,actorId:uid,Timestamp,operationId:d.operationId});
        tx.delete(ref);
        tx.create(operation,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
        tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'property_deleted',targetId:d.buildingId,createdAt:now,before:{name:old.name??'',address:old.address??''},after:null});
        return result;
      }
      if(!creating&&Object.hasOwn(d,'timeZone')&&d.timeZone!==(old.timeZone??null)){
        const rooms=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
        if(rooms.docs.some(r=>r.data().operatingSchedule!=null||r.data().operatingHoursStartMin!=null||r.data().operatingHoursEndMin!=null))throw new HttpsError('failed-precondition','property_timezone_in_use');
      }
      const now=Timestamp.now(),patch={name:d.name.trim(),address:d.address.trim()},result={buildingId:d.buildingId};
      if(Object.hasOwn(d,'timeZone'))patch.timeZone=d.timeZone;
      if(Object.hasOwn(d,'exploitationCostMinor')){
        if(!['VND','USD'].includes(creating?d.currency:old.currency??'VND'))fail('failed-precondition');
        patch.exploitationCostMinor=d.exploitationCostMinor;
      }
      const initialRooms=creating?(d.rooms??[]):[];
      const roomRefs=initialRooms.map((_,index)=>db.doc(`rooms/${hash(['propertyRoom',d.organizationId,d.buildingId,d.operationId,index])}`));
      // Read every target before writing; a collision must never overwrite data.
      for(const roomRef of roomRefs)if((await tx.get(roomRef)).exists)fail('already-exists');
      if(creating) {
        patch.currency=d.currency;
        tx.create(ref,{...patch,organizationId:d.organizationId,createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid});
        for(const [index,r] of initialRooms.entries()){
          const room={roomNumber:r.roomNumber.trim(),roomType:r.roomType.trim(),area:r.area??0,currency:d.currency,rentalMode:'both',...Object.fromEntries(priceFields.map(k=>[k,r.ratesMinor[k]===null?null:r.ratesMinor[k]/(d.currency==='USD'?100:1)]))};
          tx.create(roomRefs[index],{...room,organizationId:d.organizationId,buildingId:d.buildingId,createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid});
          tx.create(db.doc(`teamActivity/${key}_room_${index}`),{organizationId:d.organizationId,actorId:uid,action:'room_created',targetId:roomRefs[index].id,createdAt:now,before:null,after:{buildingId:d.buildingId,...room}});
        }
      } else tx.update(ref,{...patch,updatedAt:now,updatedBy:uid});
      tx.create(operation,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
      tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:creating?'property_created':'property_details_updated',targetId:d.buildingId,createdAt:now,before:creating?null:{name:old.name??'',address:old.address??'',timeZone:old.timeZone??null,exploitationCostMinor:old.exploitationCostMinor??null,currency:old.currency??'VND'},after:patch});
      return result;
    });
  };
}
module.exports={createPropertyDetailsHandler,validInitialRooms};
