'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const TYPES={buildings:'deleteBuildings',rooms:'deleteRooms',bookings:'deleteBookings',tenants:'deleteTenants',technicalProblems:'deleteProblems',staffProfiles:'deleteStaffProfiles'};
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
function retainDeletedRecord(tx,db,{type,recordId,data,actorId,Timestamp,operationId,children=[]}){
 const key=createHash('sha256').update(JSON.stringify([data.organizationId,type,recordId,operationId])).digest('hex');
 const now=Timestamp.now();
 tx.create(db.doc(`deletedRecords/${key}`),{organizationId:data.organizationId,type,recordId,data,children,deletedBy:actorId,deletedAt:now,purgeAfter:Timestamp.fromMillis(now.toMillis()+30*86400000),status:'deleted'});
 return key;
}
function createDeletedRecordsHandler({db,Timestamp,HttpsError}){
 const fail=key=>{throw new HttpsError('failed-precondition',key);};
 return async request=>{
  const uid=request.auth?.uid,d=request.data??{};
  if(!uid)throw new HttpsError('unauthenticated','team_sign_in_required');
  if(!id(d.organizationId)||!['list','restore','delete','inventory'].includes(d.action)||Object.keys(d).some(k=>!['action','organizationId','deletedRecordId','operationId','type','recordId','buildingId','revision'].includes(k))||
   (d.action==='delete'&&(!TYPES[d.type]||!id(d.recordId)||!id(d.operationId)))||
   (d.action==='restore'&&(!id(d.deletedRecordId)||!id(d.operationId))))fail('record_recovery_invalid');
  if(d.action==='delete'&&['buildings','rooms'].includes(d.type)){
   const payload={action:'delete',organizationId:d.organizationId,operationId:d.operationId,revision:d.revision,
     buildingId:d.type==='buildings'?d.recordId:d.buildingId,...(d.type==='rooms'?{roomId:d.recordId}:{})};
   const factory=d.type==='buildings'?require('./property_details').createPropertyDetailsHandler:require('./room_details').createRoomDetailsHandler;
   return factory({db,Timestamp,HttpsError})({...request,data:payload});
  }
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
   const m=member.data();
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||org.data().mergedInto||m?.status!=='active')throw new HttpsError('permission-denied','record_recovery_denied');
   const permitted=(row)=>allows(m,TYPES[row.type],{organizationId:d.organizationId,userId:uid,buildingId:row.type==='buildings'?row.recordId:row.data.buildingId,record:row.data});
   let buildingNames=new Map(),roomNames=new Map();
   if(['list','inventory'].includes(d.action)){
    const buildings=await tx.get(db.collection('buildings').where('organizationId','==',d.organizationId));
    const rooms=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId));
    buildingNames=new Map(buildings.docs.map(r=>[r.id,r.data()]));roomNames=new Map(rooms.docs.map(r=>[r.id,r.data().roomNumber]));
   }
   const contextFor=(type,data)=>{
    const building=buildingNames.get(data.buildingId),parts=[building?.name,type==='rooms'?null:roomNames.get(data.roomId)];
    if(type==='staffProfiles')parts.push(data.code);
    if(type==='bookings'&&building?.timeZone&&data.startTime?.toMillis&&data.endTime?.toMillis){
     try{const format=new Intl.DateTimeFormat('en-GB',{timeZone:building.timeZone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
      parts.push(format.format(data.startTime.toDate())+' – '+format.format(data.endTime.toDate()));
     }catch{}
    }
    if(type==='tenants')parts.push(data.moveInLocalDate);
    return parts.filter(Boolean).join(' · ');
   };
   if(d.action==='inventory'){
    const rows=[];
    for(const type of Object.keys(TYPES)){
     const q=await tx.get(db.collection(type).where('organizationId','==',d.organizationId));
     for(const record of q.docs){const data=record.data();if(permitted({type,recordId:record.id,data}))rows.push({id:record.id,type,context:contextFor(type,data),buildingId:data.buildingId??record.id,revision:`${record.updateTime.seconds}:${record.updateTime.nanoseconds}`,name:data.name??data.roomNumber??data.guestName??data.fullName??data.title??data.displayName??record.id});}
    }
    return {records:rows};
   }
   if(d.action==='delete'){
    // Buildings/rooms keep their existing empty-record checks and editors.
    const key=createHash('sha256').update(JSON.stringify([d.organizationId,d.type,d.recordId,d.operationId])).digest('hex');
    const prior=await tx.get(db.doc(`deletedRecords/${key}`));
    if(prior.exists){if(prior.data().deletedBy!==uid)fail('record_recovery_changed');return {deleted:true};}
    const ref=db.doc(`${d.type}/${d.recordId}`),record=await tx.get(ref),data=record.data();
    if(!data||data.organizationId!==d.organizationId||!permitted({type:d.type,recordId:d.recordId,data}))throw new HttpsError('permission-denied','record_recovery_denied');
    if(d.type==='bookings'&&(!['cancelled','noShow','checkedOut'].includes(data.status)||['paidAmount','depositPaidAmount','depositAmount'].some(k=>(data[k]??0)>0)))fail('record_recovery_financial');
    if(d.type==='tenants'&&(data.status!=='moveOut'||(data.depositMinor??0)>0||data.settlementId))fail('record_recovery_financial');
    if(d.type==='technicalProblems'&&(data.status!=='fixed'||data.expenseId||(data.photos??[]).length))fail('record_recovery_review');
    if(d.type==='staffProfiles'){
     if(data.accountId)fail('record_recovery_review');
     for(const collection of ['bookings','tenants','housekeepingTasks','payments']){
      const q=await tx.get(db.collection(collection).where('staffInChargeId','==',d.recordId).limit(1));if(!q.empty)fail('record_recovery_dependencies');
     }
     const accounts=await tx.get(db.collection('memberships').where('staffId','==',d.recordId).limit(1));if(!accounts.empty)fail('record_recovery_review');
    }
    const foreign=d.type==='bookings'?'bookingId':d.type==='tenants'?'tenantId':'problemId';
    for(const collection of ['payments','invoices']){
     const q=await tx.get(db.collection(collection).where(foreign,'==',d.recordId).limit(1));if(!q.empty)fail('record_recovery_financial');
    }
    if(d.type==='tenants'){
     const children=await tx.get(db.collection('tenants').where('mainTenantId','==',d.recordId).limit(1));if(!children.empty)fail('record_recovery_dependencies');
    }
    const children=[];
    async function walk(parent){for(const collection of await parent.listCollections()){
     const q=await tx.get(db.collection(`${parent.path}/${collection.id}`));
     for(const doc of q.docs){children.push({ref:doc.ref,path:doc.ref.path.slice(ref.path.length+1),data:doc.data()});if(children.length>350)fail('record_recovery_review');await walk(doc.ref);}
    }}
    await walk(ref);
    if(Buffer.byteLength(JSON.stringify({data,children:children.map(c=>({path:c.path,data:c.data}))}))>700*1024)fail('record_recovery_review');
    let room=null;
    if(data.roomId){room=await tx.get(db.doc(`rooms/${data.roomId}`));if(!room.exists||room.data().organizationId!==d.organizationId)fail('record_recovery_parent');}
    retainDeletedRecord(tx,db,{type:d.type,recordId:d.recordId,data,actorId:uid,Timestamp,operationId:d.operationId,children:children.map(c=>({path:c.path,data:c.data}))});
    for(const child of children)tx.delete(child.ref);
    tx.delete(ref);
    if(room)tx.update(room.ref,{bookingRevision:(room.data().bookingRevision??0)+1});
    tx.create(db.collection('teamActivity').doc(),{organizationId:d.organizationId,actorId:uid,action:'record_deleted',targetId:d.recordId,createdAt:Timestamp.now(),after:{type:d.type}});
    return {deleted:true};
   }
   if(d.action==='list'){
    const rows=await tx.get(db.collection('deletedRecords').where('organizationId','==',d.organizationId));
    return {records:rows.docs.filter(r=>{const x=r.data();return TYPES[x.type]&&x.status==='deleted'&&x.purgeAfter?.toMillis()>Timestamp.now().toMillis()&&permitted(x);}).map(r=>{const x=r.data();return {id:r.id,type:x.type,context:contextFor(x.type,x.data),name:x.data.name??x.data.roomNumber??x.data.guestName??x.data.fullName??x.data.title??x.data.displayName??x.recordId,deleteAt:x.purgeAfter.toDate().toISOString()};})};
   }
   const ref=db.doc(`deletedRecords/${d.deletedRecordId}`),saved=await tx.get(ref),x=saved.data();
   if(!x||x.organizationId!==d.organizationId||!TYPES[x.type])throw new HttpsError('permission-denied','record_recovery_denied');
   if(x.status==='purged')fail('org_restore_expired');
   if(!permitted(x))throw new HttpsError('permission-denied','record_recovery_denied');
   if(x.status==='restored'){if(x.restoredBy!==uid||x.restoreOperationId!==d.operationId)fail('record_recovery_changed');return {restored:true,recordId:x.recordId};}
   if(x.status!=='deleted'||!(x.purgeAfter?.toMillis()>Timestamp.now().toMillis()))fail('org_restore_expired');
   const target=db.doc(`${x.type}/${x.recordId}`),existing=await tx.get(target);
   if(existing.exists)fail('record_recovery_collision');
   let parent=null;
   if(x.type!=='buildings'&&x.type!=='staffProfiles'){
    parent=await tx.get(db.doc(`buildings/${x.data.buildingId}`));
    if(!parent.exists||parent.data().organizationId!==d.organizationId)fail('record_recovery_parent');
   }
   if(x.type==='rooms'){
    const rooms=await tx.get(db.collection('rooms').where('buildingId','==',x.data.buildingId));
    const norm=v=>String(v??'').trim().normalize('NFKC').toLowerCase();
    if(rooms.docs.some(r=>norm(r.data().roomNumber)===norm(x.data.roomNumber)))fail('record_recovery_collision');
   }
   let roomSnapshot=null;
   if(['bookings','tenants','technicalProblems'].includes(x.type)){
    const room=await tx.get(db.doc(`rooms/${x.data.roomId}`));
    roomSnapshot=room;
    if(!room.exists||room.data().organizationId!==d.organizationId||room.data().buildingId!==x.data.buildingId)fail('record_recovery_parent');
    if(x.type==='bookings'&&!['cancelled','noShow','checkedOut'].includes(x.data.status))fail('record_recovery_review');
    if(x.type==='tenants'&&x.data.status!=='moveOut')fail('record_recovery_review');
    if(x.type==='technicalProblems'&&x.data.status!=='fixed')fail('record_recovery_review');
    if(['bookings','tenants'].includes(x.type)){
     const ms=v=>v?.toMillis?v.toMillis():null;
     const interval=(type,data)=>type==='bookings'?[ms(data.startTime),ms(data.endTime)]:[ms(data.moveInDate),ms(data.moveOutDate)];
     const [start,end]=interval(x.type,x.data);
     if(start===null||end===null||end<=start)fail('record_recovery_review');
     for(const collection of ['bookings','tenants']){
      const peers=await tx.get(db.collection(collection).where('roomId','==',x.data.roomId));
      for(const peer of peers.docs){const data=peer.data();
       if(collection==='bookings'&&['cancelled','noShow'].includes(data.status))continue;
       if(collection==='tenants'&&data.isMainTenant===false)continue;
       const [a,b]=interval(collection,data);
       if(a!==null&&a<end&&(b??Infinity)>start&&!(x.type==='bookings'&&['cancelled','noShow'].includes(x.data.status)))fail('record_recovery_overlap');
      }
     }
    }
   }
   if(x.type==='staffProfiles'&&x.data.accountId)fail('record_recovery_review');
   if(x.type==='staffProfiles'&&x.data.code){
    const staff=await tx.get(db.collection('staffProfiles').where('organizationId','==',d.organizationId).where('code','==',x.data.code).limit(1));
    if(!staff.empty)fail('record_recovery_collision');
   }
   if(x.type==='rooms'&&x.data.currency&&(parent.data().currency??'VND')!==x.data.currency)fail('record_recovery_review');
   const children=[];
   for(const child of x.children??[]){
    if(typeof child.path!=='string'||child.path.split('/').length%2!==0)fail('record_recovery_review');
    const childRef=db.doc(`${target.path}/${child.path}`),existingChild=await tx.get(childRef);if(existingChild.exists)fail('record_recovery_collision');children.push({ref:childRef,data:child.data});
   }
   const now=Timestamp.now();
   tx.create(target,{...x.data,updatedAt:now,restoredAt:now,restoredBy:uid});
   for(const child of children)tx.create(child.ref,child.data);
   if(parent&&x.type==='rooms')tx.update(parent.ref,{roomInventoryUpdatedAt:now});
   if(roomSnapshot)tx.update(roomSnapshot.ref,{bookingRevision:(roomSnapshot.data().bookingRevision??0)+1});
   if(x.type==='staffProfiles')tx.update(org.ref,{staffInventoryUpdatedAt:now});
   tx.update(ref,{status:'restored',restoredAt:now,restoredBy:uid,restoreOperationId:d.operationId});
   tx.create(db.collection('teamActivity').doc(),{organizationId:d.organizationId,actorId:uid,action:'record_restored',targetId:x.recordId,createdAt:now,after:{type:x.type}});
   return {restored:true,recordId:x.recordId};
  });
 };
}
async function purgeDeletedRecords({db,Timestamp,max=200}){
 const due=await db.collection('deletedRecords').where('purgeAfter','<=',Timestamp.now()).limit(max).get();
 for(const doc of due.docs)await db.runTransaction(async tx=>{
  const latest=await tx.get(doc.ref),x=latest.data();
  if(!x||x.status==='purged'||x.purgeAfter?.toMillis()>Timestamp.now().toMillis())return;
  tx.set(doc.ref,{organizationId:x.organizationId,type:x.type,recordId:x.recordId,status:'purged',purgedAt:Timestamp.now()});
 });
}
module.exports={TYPES,retainDeletedRecord,createDeletedRecordsHandler,purgeDeletedRecords};
