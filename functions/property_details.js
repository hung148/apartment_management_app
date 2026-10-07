'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validZone}=require('./booking_settings');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const revision=doc=>`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`;
function createPropertyDetailsHandler({db,Timestamp,HttpsError}) {
  const fail=(code)=>{throw new HttpsError(code,'property_'+code);};
  return async request=>{
    const uid=request.auth?.uid,d=request.data||{};
    if(!uid)fail('unauthenticated');
    const deleting=d.action==='delete';
    const creating=d.action==='create',preparing=d.action==='prepareCreate',editing=d.action==='update'||creating;
    const keys=['action','organizationId','buildingId',...(deleting?['operationId','revision']:[]),...(editing?['operationId',...(!creating?['revision']:[]),'name','address',...(Object.hasOwn(d,'timeZone')?['timeZone']:[]),...(creating?['currency']:[])]:[])];
    if(Object.hasOwn(d,'timeZone')&&d.timeZone!==null&&!validZone(d.timeZone))fail('invalid-argument');
    if(!['read','update','prepareCreate','create','delete'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
    if(editing&&(!id(d.operationId)||(!creating&&(typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))||typeof d.name!=='string'||!d.name.trim()||d.name.length>160||typeof d.address!=='string'||!d.address.trim()||d.address.length>500))fail('invalid-argument');
    if(deleting&&(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))fail('invalid-argument');
    if(creating&&(!validZone(d.timeZone)||!['VND','USD'].includes(d.currency)))fail('invalid-argument');
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`));
      const member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      if(!org.exists||org.data().accessVersion!==2||!allows(member.data(),'manageProperty',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId}))fail('permission-denied');
      if((creating||preparing)&&member.data().buildingScope!=='all')fail('permission-denied');
      if(deleting&&(member.data().buildingScope!=='all'||!allows(member.data(),'manageOrganization',{organizationId:d.organizationId,userId:uid})))fail('permission-denied');
      if(preparing)return {record:{id:d.buildingId,name:'',address:'',timeZone:'Asia/Ho_Chi_Minh',currency:'VND',revision:'new'}};
      const ref=db.doc(`buildings/${d.buildingId}`),doc=await tx.get(ref),old=doc.data();
      if(!creating&&!deleting&&(!old||old.organizationId!==d.organizationId))fail('not-found');
      if(!editing&&!deleting)return {record:{id:doc.id,name:old.name??'',address:old.address??'',timeZone:old.timeZone??null,revision:revision(doc)}};
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
      if(creating) {
        patch.currency=d.currency;
        tx.create(ref,{...patch,organizationId:d.organizationId,createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid});
      } else tx.update(ref,{...patch,updatedAt:now,updatedBy:uid});
      tx.create(operation,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
      tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:creating?'property_created':'property_details_updated',targetId:d.buildingId,createdAt:now,before:creating?null:{name:old.name??'',address:old.address??'',timeZone:old.timeZone??null},after:patch});
      return result;
    });
  };
}
module.exports={createPropertyDetailsHandler};
