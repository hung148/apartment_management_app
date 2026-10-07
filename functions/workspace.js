'use strict';
const {allows,hasRole,reachesAllProperties}=require('./team_access');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,256}$/.test(v);
const specs={
  rooms:{collection:'rooms',permission:'manageProperty',fields:['roomNumber','roomType','area','rentalMode']},
  taskRooms:{collection:'rooms',permission:'manageProperty',fields:['roomNumber']},
  taskAssignees:{collection:'memberships',permission:'manageProperty',fields:['ownerId','displayName']},
  tasks:{collection:'housekeepingTasks',permission:'readAssignedTasks',fields:['roomId','title','status','assigneeId','plannedStart','plannedEnd']},
  properties:{collection:'buildings',fields:['name']},
  bookings:{collection:'bookings',permission:'readBookings',fields:['roomId','guestName','startTime','endTime','status']},
  financial:{collection:'payments',permission:'readFinancialReports',fields:['roomId','type','status','amount','paidAmount','currency','direction']},
  paymentActions:{collection:'payments',permission:'collectPayments',fields:['roomId','type','status','amount','paidAmount','currency','internetFee','cableTVFee','hotWaterFee','lateFee','taxAmount']},
};
function createWorkspaceHandler({db,HttpsError}) {
  const fail=(code)=>{throw new HttpsError(code,'workspace_unavailable');};
  return async request=>{
    const uid=request.auth?.uid,d=request.data||{},spec=Object.hasOwn(specs,d.view)?specs[d.view]:null;
    if(!uid)fail('unauthenticated');
    if(!id(d.organizationId)||!spec||!Number.isInteger(d.limit??25)||(d.limit??25)<1||(d.limit??25)>100||(d.cursor!==undefined&&!id(d.cursor))||(d.view!=='properties'&&!id(d.buildingId)))fail('invalid-argument');
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`));
      const memberDoc=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      const m=memberDoc.data();
      if(!org.exists||org.data().accessVersion!==2||!m||m.organizationId!==d.organizationId||m.ownerId!==uid||m.accessVersion!==2||m.status!=='active'||!hasRole(m)||!['all','selected'].includes(m.buildingScope))fail('permission-denied');
      let query=db.collection(spec.collection).where('organizationId','==',d.organizationId);
      if(d.view==='properties') {
        // A grant set to "All properties" (e.g. view bookings) lists every property.
        if(!reachesAllProperties(m)) {
          const ids=Array.isArray(m.buildingIds)?[...new Set(m.buildingIds.filter(id))].sort():[];
          if(ids.length>100)fail('permission-denied');
          const snapshots=await Promise.all(ids.filter(v=>!d.cursor||v>d.cursor).map(v=>tx.get(db.doc(`buildings/${v}`))));
          const docs=snapshots.filter(v=>v.exists&&v.data().organizationId===d.organizationId),limit=d.limit??25;
          return {records:docs.slice(0,limit).map(v=>({id:v.id,name:v.data().name??''})),nextCursor:docs.length>limit?docs[limit-1].id:null};
        }
      } else {
        const context={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
        if(!allows(m,spec.permission,{...context,anyRecord:true}) && !(d.view==='paymentActions'&&allows(m,'refundPayments',context)) && !(d.view==='tasks'&&allows(m,'manageProperty',context)))fail('permission-denied');
        const building=await tx.get(db.doc(`buildings/${d.buildingId}`));
        if(!building.exists||building.data().organizationId!==d.organizationId)fail('permission-denied');
        if(d.view!=='taskAssignees')query=query.where('buildingId','==',d.buildingId);
        if(d.view==='tasks'&&!allows(m,'manageProperty',context))query=query.where('assigneeId','==',uid);
      }
      query=query.orderBy('__name__');
      if(d.cursor)query=query.startAfter(d.cursor);
      const limit=d.limit??25,snapshot=await tx.get(query.limit(limit+1));
      const docs=snapshot.docs.slice(0,limit);
      const visible=docs.filter(doc=>{
        if(d.view==='taskAssignees')return doc.id===`${doc.data().ownerId}_${d.organizationId}`&&allows(doc.data(),'updateAssignedTasks',{organizationId:d.organizationId,userId:doc.data().ownerId,buildingId:d.buildingId});
        // "Own records only": bookings the member created or is in charge of.
        if(d.view==='bookings')return allows(m,'readBookings',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId,record:doc.data()});
        return d.view!=='properties'||reachesAllProperties(m)||(Array.isArray(m.buildingIds)&&m.buildingIds.includes(doc.id));
      });
      const serialize=v=>v?.toDate?v.toDate().toISOString():v;
      // Room numbers for lists that show a room, so screens never show internal IDs.
      let numbers=new Map();
      if(spec.fields.includes('roomId')){
        const rooms=await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
        numbers=new Map(rooms.docs.map(v=>[v.id,String(v.data().roomNumber??'')]));
      }
      // Task lists show who a task is for by name, not account ID.
      const names=new Map();
      if(d.view==='tasks'){
        const ids=[...new Set(visible.map(v=>v.data().assigneeId).filter(id))];
        const people=await Promise.all(ids.map(u=>tx.get(db.doc(`memberships/${u}_${d.organizationId}`))));
        people.forEach((p,i)=>{const x=p.data();names.set(ids[i],typeof x?.displayName==='string'&&x.displayName.trim()?x.displayName.trim():(typeof x?.email==='string'?x.email:''));});
      }
      // Booking times in the property's own time zone (same as the booking screen).
      const zone=d.view==='bookings'||d.view==='tasks'?(await tx.get(db.doc(`buildings/${d.buildingId}`))).data()?.timeZone:null;
      const local=v=>{
        if(!v?.toDate)return '';
        try{
          const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(v.toDate()).map(x=>[x.type,x.value]));
          return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}`;
        }catch{return '';}
      };
      return {records:visible.map(doc=>{
        const data=doc.data();
        const record={id:doc.id,...Object.fromEntries(spec.fields.filter(k=>data[k]!==undefined).map(k=>[k,serialize(data[k])]))};
        if(d.view==='tasks')record.assigneeName=names.get(data.assigneeId)??'';
        // Real work time (Bắt đầu → Xong), in the property's time zone.
        if(d.view==='tasks'&&zone){if(data.startedAt)record.startedLocal=local(data.startedAt);if(data.completedAt)record.completedLocal=local(data.completedAt);}
        if(spec.fields.includes('roomId'))record.roomNumber=numbers.get(data.roomId)??'';
        if(d.view==='bookings'&&zone){record.startLocal=local(data.startTime);record.endLocal=local(data.endTime);record.timeZone=zone;}
        if(d.view==='rooms')record.canReadUtilities=allows(m,'manageLease',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId});
        if(d.view==='rooms')record.canEditRates=allows(m,'overridePrices',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId});
        if(d.view==='paymentActions'){
          const context={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
          const supported=data.direction!=='expense'&&!doc.id.startsWith('booking_')&&data.bookingId==null&&data.type!=='hourlyRent'&&['VND','USD'].includes(data.currency)&&['pending','partial','overdue','paid','refunded'].includes(data.status);
          record.canCollect=supported&&allows(m,'collectPayments',context);
          record.canRefund=supported&&allows(m,'refundPayments',context);
        }
        return record;
      }),nextCursor:snapshot.docs.length>limit?docs.at(-1).id:null};
    });
  };
}
module.exports={createWorkspaceHandler};
