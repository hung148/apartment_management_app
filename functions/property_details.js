'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {organizationCurrency}=require('./organization_currency');
const {validZone}=require('./booking_settings');
const {retainDeletedRecord}=require('./deleted_records');
// Optional combined form payload; old clients retain their existing defaults.
const layoutFields=['floors','roomPrefix','roomType','roomArea','floorRoomCounts'];
function validLayout(v) {
  if (!v || typeof v !== 'object' || Array.isArray(v) ||
      !Object.keys(v).every(k => [...layoutFields, 'floorDefaults', 'uniformRooms'].includes(k)) ||
      !layoutFields.every(k => Object.hasOwn(v, k))) return false;
  if (!Number.isInteger(v.floors) || v.floors < 1 || v.floors > 200 ||
      typeof v.roomPrefix !== 'string' || v.roomPrefix.length > 20 ||
      typeof v.roomType !== 'string' || v.roomType.length > 160 ||
      !Number.isFinite(v.roomArea) || v.roomArea < 0 || v.roomArea > 100000 ||
      !Array.isArray(v.floorRoomCounts) || v.floorRoomCounts.length !== v.floors ||
      !v.floorRoomCounts.every(n => Number.isInteger(n) && n >= 0 && n <= 500) ||
      v.floorRoomCounts.reduce((a, b) => a + b, 0) > 10000) return false;
  if (Object.hasOwn(v, 'uniformRooms') && typeof v.uniformRooms !== 'boolean') return false;
  if (Object.hasOwn(v, 'floorDefaults') &&
      (!Array.isArray(v.floorDefaults) || v.floorDefaults.length !== v.floors ||
       !v.floorDefaults.every(f => f && Object.keys(f).length === 2 &&
         typeof f.roomType === 'string' && f.roomType.length <= 160 &&
         Number.isFinite(f.roomArea) && f.roomArea >= 0 && f.roomArea <= 100000))) return false;
  return true;
}
const layoutOf = b => ({
  ...('uniformRooms' in b ? {uniformRooms: b.uniformRooms} : {}),
  ...('floorDefaults' in b ? {floorDefaults: b.floorDefaults} : {}),
  floors: b.floors ?? 1,
  roomPrefix: b.roomPrefix ?? '',
  roomType: b.roomType ?? '',
  roomArea: b.roomArea ?? 0,
  floorRoomCounts: b.floorRoomCounts ?? Array(b.floors ?? 1).fill(0),
});
const {createBuildingPrices,validDefaults,defaultsOf,followsFor,initialElectricity,withBuildingPrices}=require('./building_prices');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const revision=doc=>`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
const priceFields=['roomPrice','nightlyPrice','hourlyPrice'];
const validAmount=v=>Number.isSafeInteger(v)&&v>=0&&v<=1e12;
const normalized=v=>v.trim().normalize('NFKC').toLowerCase();
function validInitialRooms(rooms){
  if(!Array.isArray(rooms)||rooms.length>200)return false;
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
  const prices=createBuildingPrices({db,Timestamp,HttpsError});
  return async request=>{
    const uid=request.auth?.uid,d=request.data||{};
    if(!uid)fail('unauthenticated');
    // Building price defaults (PRICE_DEFAULTS.md, 2026-10-26).
    if(d.action==='readPrices'||d.action==='savePrices')return prices(d,uid);
    const deleting=d.action==='delete';
    const creating=d.action==='create',preparing=d.action==='prepareCreate',editing=d.action==='update'||creating;
    const keys=['action','organizationId','buildingId',...(deleting?['operationId','revision']:[]),...(editing?['operationId',...(!creating?['revision']:[]),'name','address',...(Object.hasOwn(d,'timeZone')?['timeZone']:[]),...(Object.hasOwn(d,'exploitationCostMinor')?['exploitationCostMinor']:[]),...(creating?['currency',...(Object.hasOwn(d,'defaultPrices')?['defaultPrices']:[]),...(Object.hasOwn(d,'electricityPriceMinor')?['electricityPriceMinor']:[])]:[]),...(Object.hasOwn(d,'rooms')?['rooms']:[]),...(Object.hasOwn(d,'layout')?['layout']:[]),...(Object.hasOwn(d,'roomCurrency')?['roomCurrency']:[])]:[])];
    if(editing&&Object.hasOwn(d,'exploitationCostMinor')&&d.exploitationCostMinor!==null&&!validAmount(d.exploitationCostMinor))fail('invalid-argument');
    if(editing&&Object.hasOwn(d,'rooms')&&!validInitialRooms(d.rooms))fail('invalid-argument');
    if(editing&&Object.hasOwn(d,'roomCurrency')&&!['VND','USD'].includes(d.roomCurrency))fail('invalid-argument');
    if(editing&&Object.hasOwn(d,'layout')&&!validLayout(d.layout))fail('invalid-argument');
    if(Object.hasOwn(d,'timeZone')&&d.timeZone!==null&&!validZone(d.timeZone))fail('invalid-argument');
    if(!['read','update','prepareCreate','create','delete'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
    if(editing&&(!id(d.operationId)||(!creating&&(typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))||typeof d.name!=='string'||!d.name.trim()||d.name.length>160||typeof d.address!=='string'||d.address.length>500))fail('invalid-argument');
    if(deleting&&(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))fail('invalid-argument');
    if(creating&&(!validZone(d.timeZone)||!['VND','USD'].includes(d.currency)))fail('invalid-argument');
    if(creating&&Object.hasOwn(d,'defaultPrices')&&!validDefaults(d.defaultPrices))fail('invalid-argument');
    if(creating&&Object.hasOwn(d,'electricityPriceMinor')&&d.electricityPriceMinor!==null&&(!Number.isSafeInteger(d.electricityPriceMinor)||d.electricityPriceMinor<=0||d.electricityPriceMinor>1e9))fail('invalid-argument');
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`));
      const member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      if(!org.exists||org.data().accessVersion!==2||!allows(member.data(),deleting?'deleteBuildings':'manageProperty',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId}))fail('permission-denied');
      if((creating||preparing)&&member.data().buildingScope!=='all')fail('permission-denied');
      const canSetRoomPrices=allows(member.data(),'overridePrices',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId});
      if(editing&&(d.rooms??[]).some(r=>priceFields.some(k=>r.ratesMinor[k]!==null))&&!canSetRoomPrices)fail('permission-denied');
      // Building prices are prices too (2026-10-26).
      if(creating&&(Object.values(d.defaultPrices??{}).some(v=>typeof v==='number')||d.electricityPriceMinor!=null)&&!canSetRoomPrices)fail('permission-denied');
      if(preparing)return {record:{id:d.buildingId,name:'',address:'',timeZone:'Asia/Ho_Chi_Minh',currency:organizationCurrency(org.data()),exploitationCostMinor:null,canSetRoomPrices,roomCurrency:organizationCurrency(org.data()),layout:layoutOf({}),revision:'new'}};
      const ref=db.doc(`buildings/${d.buildingId}`),doc=await tx.get(ref),old=doc.data();
      if(!creating&&!deleting&&(!old||old.organizationId!==d.organizationId))fail('not-found');
      if(!editing&&!deleting)return {record:{id:doc.id,name:old.name??'',address:old.address??'',timeZone:old.timeZone??null,currency:old.currency??'VND',exploitationCostMinor:old.exploitationCostMinor??null,canSetRoomPrices,roomCurrency:org.data().displayCurrency??old.currency??'VND',layout:layoutOf(old),revision:revision(doc)}};
      const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
      const key=hash(['propertyDetails',d.organizationId,uid,d.operationId]);
      const operation=db.doc(`propertyOperations/${key}`),prior=await tx.get(operation);
      const fingerprint=hash(keys.map(k=>d[k]));
      if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('already-exists');return prior.data().result;}
      if(deleting&&(!old||old.organizationId!==d.organizationId))fail('not-found');
      if(creating&&old)fail('already-exists');
      if(creating&&d.currency!==organizationCurrency(org.data()))fail('aborted');
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
      if(Object.hasOwn(d,'layout'))Object.assign(patch,d.layout,{roomType:d.layout.roomType.trim()});
      const initialRooms=d.rooms??[];
      if(!creating&&initialRooms.length){
        const peers=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
        const taken=new Set(peers.docs.map(r=>normalized(String(r.data().roomNumber??''))));
        if(initialRooms.some(r=>taken.has(normalized(r.roomNumber))))fail('already-exists');
      }
      const roomCurrency=d.roomCurrency??(creating?d.currency:old.currency??'VND');
      if(initialRooms.length&&roomCurrency!==(org.data().displayCurrency??(creating?d.currency:old.currency??'VND')))fail('aborted');
      if(initialRooms.length&&!['VND','USD'].includes(roomCurrency))fail('failed-precondition');
      const roomRefs=initialRooms.map((_,index)=>db.doc(`rooms/${hash(['propertyRoom',d.organizationId,d.buildingId,d.operationId,index])}`));
      // create() preconditions reject collisions atomically without one read per new room.
      if(creating) {
        patch.currency=d.currency;
        if(d.defaultPrices)patch.defaultPrices={...d.defaultPrices};
        tx.create(ref,{...patch,organizationId:d.organizationId,createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid});
        initialElectricity(tx,db,{organizationId:d.organizationId,buildingId:d.buildingId,priceMinor:d.electricityPriceMinor??null,currency:d.currency,timeZone:d.timeZone,now,uid});
      } else tx.update(ref,{...patch,updatedAt:now,updatedBy:uid});
      const buildingDefaults=defaultsOf(creating?{defaultPrices:d.defaultPrices}:old),sameCurrency=roomCurrency===(creating?d.currency:old.currency??'VND');
      for(const [index,r0] of initialRooms.entries()){
          // A room left without a price takes the building's (2026-10-28).
          const r=sameCurrency?{...r0,ratesMinor:withBuildingPrices(r0.ratesMinor,buildingDefaults)}:r0;
          const room={roomNumber:r.roomNumber.trim(),roomType:r.roomType.trim(),area:r.area??0,currency:roomCurrency,rentalMode:'both',...Object.fromEntries(priceFields.map(k=>[k,r.ratesMinor[k]==null?null:r.ratesMinor[k]/(roomCurrency==='USD'?100:1)])),
            // A price equal to the building's follows it (2026-10-26).
            priceFollows:sameCurrency?followsFor(r.ratesMinor,buildingDefaults):{roomPrice:false,nightlyPrice:false}};
          tx.create(roomRefs[index],{...room,organizationId:d.organizationId,buildingId:d.buildingId,createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid});
          tx.create(db.doc(`teamActivity/${key}_room_${index}`),{organizationId:d.organizationId,actorId:uid,action:'room_created',targetId:roomRefs[index].id,createdAt:now,before:null,after:{buildingId:d.buildingId,...room}});
        }
      tx.create(operation,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
      tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:creating?'property_created':'property_details_updated',targetId:d.buildingId,createdAt:now,before:creating?null:{...(d.layout?layoutOf(old):{}),name:old.name??'',address:old.address??'',timeZone:old.timeZone??null,exploitationCostMinor:old.exploitationCostMinor??null,currency:old.currency??'VND'},after:patch});
      return result;
    }).catch(error=>{if(error.code===6)fail('already-exists');throw error;});
  };
}
module.exports={createPropertyDetailsHandler,validInitialRooms};
