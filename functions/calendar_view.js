'use strict';
// C1–C3 calendar (CALENDAR.md): one read for the calendar screen. Rooms of
// every property the member can see, grouped by property, and one "bar" per
// short stay / lease that overlaps the requested days. Read-only; every write
// still goes through the existing booking / lease / problem callables.
//
// Privacy: a member who may not open a record (no lease access, or bookings
// limited to their own) still sees that the room is taken — as an anonymous
// bar with no name, phone or money — so nobody double-books by mistake.
const {allows,hasRole,reachesAllProperties}=require('./team_access');
const {validZone}=require('./booking_settings');
const {validDate}=require('./property_contract');
const {propertyDate,propertyDayStart}=require('./lease_dates');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
// One property per call (2026-10-10, scale): no cap on how many an
// organization has; the app loads the one on screen.
const MAX_DAYS=100;
const ACTIVE_BOOKING=['pending','confirmed','checkedIn','checkedOut'];
const RENT_KINDS=x=>x.invoiceKind==='tenantRent'||(['period','settlement'].includes(x.invoiceKind)&&x.calculation?.includeRent===true);
const ms=v=>v?.toMillis?.()??null;
const dayMs=86400000;
const daysBetween=(a,b)=>Math.round((Date.parse(b+'T00:00:00Z')-Date.parse(a+'T00:00:00Z'))/dayMs);

/** "YYYY-MM-DD HH:MM" in the property's zone. */
function localStamp(millis,zone){
 if(!Number.isFinite(millis))return null;
 try{
  const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(millis).map(x=>[x.type,x.value]));
  return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute}`;
 }catch{return null;}
}
const dateStamp=(date,time='12:00')=>date&&validDate(date)?`${date} ${time}`:null;

/** Booking payment: green paid in full, orange only the deposit paid, red still owed. */
function bookingPay(x){
 const cents=v=>Math.round((Number(v)||0)*100),total=cents(x.totalPrice),paid=cents(x.paidAmount),deposit=cents(x.depositPaidAmount)-cents(x.depositRefundedAmount);
 // A deposit taken with the booking (2026-10-04) is in paidAmount: only that paid still reads "Đã cọc".
 const taken=x.depositPayment&&typeof x.depositPayment==='object'?cents(x.depositPayment.amount):0;
 const pay=total>0&&paid>=total?'paid':(paid===0&&deposit>0)||(taken>0&&paid>0&&paid<=taken)?'deposit':total===0?'paid':'due';
 return {pay,fraction:total>0?Math.min(1,paid/total):1};
}

/** Lease payment from its rent invoices (rent is paid ahead per period). */
function leasePay(t,invoices,today,status){
 let paidUntil=null,unpaid=false;
 for(const x of invoices){
  if(x.status==='cancelled'||!RENT_KINDS(x)||typeof x.billingEndLocalDate!=='string')continue;
  if(x.status==='paid'){if(!paidUntil||x.billingEndLocalDate>paidUntil)paidUntil=x.billingEndLocalDate;}
  else if(typeof x.billingStartLocalDate==='string'&&x.billingStartLocalDate<=today)unpaid=true;
 }
 let pay;
 if(status==='out')pay=t.settlementId?'paid':'due';
 else if(status==='upcoming')pay=(t.depositMinor??0)>0||(t.deposit??0)>0?'deposit':'due';
 else pay=!unpaid&&paidUntil&&paidUntil>today?'paid':'due';
 return {pay,paidUntil};
}

function createCalendarViewHandler({db,Timestamp,HttpsError}){
 const fail=(code,key='calendar_'+code)=>{throw new HttpsError(code,key);};
 return async request=>{
  const uid=request.auth?.uid,d=request.data||{};
  if(!uid)fail('unauthenticated');
  if(!id(d.organizationId)||!validDate(d.from)||!validDate(d.to)||Object.keys(d).some(k=>!['organizationId','from','to','buildingId','list'].includes(k)))fail('invalid-argument');
  if(d.buildingId!==undefined&&!id(d.buildingId))fail('invalid-argument');
  if(d.list!==undefined&&typeof d.list!=='boolean')fail('invalid-argument');
  const span=daysBetween(d.from,d.to);
  if(span<1||span>MAX_DAYS)fail('invalid-argument');
  const O=d.organizationId;
  const [org,memberDoc]=await Promise.all([db.doc(`organizations/${O}`).get(),db.doc(`memberships/${uid}_${O}`).get()]);
  const m=memberDoc.data();
  if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||!m||m.organizationId!==O||m.ownerId!==uid||m.accessVersion!==2||m.status!=='active'||!hasRole(m)||!['all','selected'].includes(m.buildingScope))fail('permission-denied');

  // What this member may do in one property (no reads: permissions only).
  const rights=buildingId=>{
   const scope={organizationId:O,userId:uid,buildingId},can=p=>allows(m,p,scope);
   const readBookings=allows(m,'readBookings',{...scope,anyRecord:true}),canLease=can('manageLease');
   const canCreateBookings=can('createBookings'),canManageProperty=can('manageProperty');
   // 2026-10-05 (Tom): cleaners get the calendar too, with cleaning only: their
   // own cleaning bars and which rooms need cleaning (no guests, no money).
   const readTasks=can('readAssignedTasks');
   const cleaningOnly=!readBookings&&!canLease&&!canCreateBookings&&!canManageProperty;
   return {scope,can,readBookings,canLease,canCreateBookings,canManageProperty,readTasks,cleaningOnly,shown:!(cleaningOnly&&!readTasks)};
  };
  const ids=Array.isArray(m.buildingIds)?[...new Set(m.buildingIds.filter(id))]:[];
  const reaches=buildingId=>reachesAllProperties(m)||ids.includes(buildingId);
  const usable=doc=>doc.exists&&doc.data().organizationId===O&&!doc.data().deletedAt&&reaches(doc.id)&&rights(doc.id).shown;
  const byName=(a,b)=>String(a.data().name??'').localeCompare(String(b.data().name??''),undefined,{numeric:true})||a.id.localeCompare(b.id);

  // Scale (2026-10-10, Tom: 100+ buildings): one property per call. The list
  // of properties (names only) is read when the app asks for it (first open,
  // after a property page) or when the asked property cannot be shown; no
  // cap on how many there are.
  let list=null,building=null;
  if(d.buildingId&&d.list!==true){
   const doc=await db.doc(`buildings/${d.buildingId}`).get();
   if(usable(doc))building=doc;
  }
  if(!building){
   let docs;
   if(reachesAllProperties(m))docs=(await db.collection('buildings').where('organizationId','==',O).get()).docs;
   else docs=await Promise.all(ids.map(v=>db.doc(`buildings/${v}`).get()));
   list=docs.filter(usable).sort(byName);
   building=list.find(v=>v.id===d.buildingId)??list[0]??null;
  }
  const staffCache=new Map(),memberCache=new Map();
  // Names by id (2026-10-10, scale): only the staff on the shown bars, not
  // the whole staff list.
  const staffName=v=>staffCache.get(v)??'';
  const readNames=(staffIds,accountIds)=>Promise.all([
   ...[...staffIds].filter(v=>id(v)&&!staffCache.has(v)).map(async v=>{const x=(await db.doc(`staffProfiles/${v}`).get()).data();staffCache.set(v,x?.organizationId===O?String(x.displayName??''):'');}),
   ...[...accountIds].filter(v=>id(v)&&!memberCache.has(v)).map(async u=>{const x=(await db.doc(`memberships/${u}_${O}`).get()).data();memberCache.set(u,x?.organizationId!==O?'':typeof x?.displayName==='string'&&x.displayName.trim()?x.displayName.trim():(typeof x?.email==='string'?x.email:''));}),
  ]);

  const loadBuilding=async building=>{
   const b=building.data(),zone=b.timeZone,B=building.id;
   const {scope,can,readBookings,canLease,canCreateBookings,canManageProperty,readTasks,cleaningOnly}=rights(B);
   if(!validZone(zone))return {id:B,name:b.name??'',timeZone:null,today:null,needsTimeZone:true,rooms:[],bars:[]};
   const today=propertyDate(Timestamp.now().toMillis(),zone),from=propertyDayStart(d.from,zone),to=propertyDayStart(d.to,zone);
   if(from===null||to===null)fail('invalid-argument');
   const canReport=canManageProperty||canCreateBookings||can('manageBookings')||canLease||can('updateAssignedTasks');
   const canReadProblems=canReport||readBookings||can('readAssignedTasks');
   // Scale (2026-10-10): only what reaches into the asked days, never the
   // property's whole history. Open stays and cleanings are always read.
   const fromTs=Timestamp.fromMillis(from),none={docs:[]};
   const where=c=>db.collection(c).where('organizationId','==',O).where('buildingId','==',B);
   const [rooms,bookings,tenantsNow,tenantsOut,history,problems,tasksOpen,tasksDone]=await Promise.all([
    where('rooms').get(),
    cleaningOnly?none:where('bookings').where('endTime','>',fromTs).get(),
    cleaningOnly?none:where('tenants').where('status','in',['active','suspended']).get(),
    cleaningOnly?none:where('tenants').where('moveOutDate','>',fromTs).get(),
    cleaningOnly?none:db.collection('leaseOccupancy').where('buildingId','==',B).where('end','>',fromTs).get(),
    canReadProblems?db.collection('technicalProblems').where('organizationId','==',O).where('buildingId','==',B).where('status','==','open').get():null,
    where('housekeepingTasks').where('status','in',['assigned','inProgress']).get(),
    where('housekeepingTasks').where('completedAt','>',fromTs).get(),
   ]);
   const seen=new Set(),merge=(...lists)=>lists.flatMap(q=>q.docs).filter(v=>!seen.has(v.ref?.path??v.id)&&seen.add(v.ref?.path??v.id));
   const tenantList=merge(tenantsNow,tenantsOut),taskList=merge(tasksOpen,tasksDone);
   const liveRooms=rooms.docs.filter(v=>!v.data().deletedAt);
   const roomIds=new Set(rooms.docs.map(v=>v.id));
   const nowMs=Timestamp.now().toMillis();

   // Needs cleaning (2026-10-05, Tom): a guest left (check-out, lease
   // move-out) after the room's last finished cleaning. Scale (2026-10-10):
   // each room's latest of each, whatever month is shown.
   const latest=(c,status,field,n)=>r=>db.collection(c).where('organizationId','==',O).where('roomId','==',r).where('status','==',status).orderBy(field,'desc').limit(n).get();
   const lastCheckout=latest('bookings','checkedOut','endTime',3),lastMoveOut=latest('tenants','moveOut','moveOutDate',3),lastCleaning=latest('housekeepingTasks','completed','completedAt',1);
   const cleaningRead=Promise.all(liveRooms.map(async r=>{
    const [out,moved,clean]=await Promise.all([lastCheckout(r.id),lastMoveOut(r.id),lastCleaning(r.id)]);
    const last=values=>Math.max(-Infinity,...values.filter(v=>Number.isFinite(v)&&v<=nowMs));
    const left=Math.max(last(out.docs.map(v=>v.data()).map(x=>ms(x.checkedOutAt)??ms(x.endTime))),
     last(moved.docs.map(v=>v.data()).filter(x=>x.isMainTenant!==false).map(x=>ms(x.moveOutDate))));
    const cleaned=last(clean.docs.map(v=>ms(v.data().completedAt)));
    return [r.id,left>-Infinity&&!(cleaned>=left)];
   }));
   cleaningRead.catch(()=>{});

   const open=new Map();
   for(const p of problems?.docs??[]){const x=p.data();if(!open.has(x.roomId))open.set(x.roomId,[]);open.get(x.roomId).push({id:p.id,title:String(x.title??''),blocksRoom:x.blocksRoom===true});}
   const overlaps=(start,end)=>start!==null&&start<to&&(end===null||end>from);
   const bars=[];

   // Rent invoices (leases), former tenants (room moves), names and the
   // rooms' cleaning state are all read at the same time.
   const mainsEarly=tenantList.filter(v=>v.data().isMainTenant!==false);
   const leaseIdsEarly=new Set(mainsEarly.map(v=>v.id));
   for(const h of history.docs){const x=h.data();if(x.organizationId===O&&x.isMainTenant!==false&&id(x.tenantId))leaseIdsEarly.add(x.tenantId);}
   const invoicePages=[];
   if(canLease){
    const list=[...leaseIdsEarly];
    for(let i=0;i<list.length;i+=30)invoicePages.push(db.collection('payments').where('organizationId','==',O).where('tenantId','in',list.slice(i,i+30)).get());
   }
   const formerIds=cleaningOnly?[]:[...new Set(history.docs.map(h=>h.data()).filter(x=>x.organizationId===O&&x.isMainTenant!==false&&roomIds.has(x.roomId)&&id(x.tenantId)&&!mainsEarly.some(v=>v.id===x.tenantId)).map(x=>x.tenantId))];
   const formerRead=Promise.all(formerIds.map(t=>db.doc(`tenants/${t}`).get()));
   const pagesRead=Promise.all(invoicePages);
   pagesRead.catch(()=>{});formerRead.catch(()=>{});
   const assignees=new Set(taskList.map(v=>v.data().assigneeId).filter(v=>typeof v==='string'&&v));
   await readNames(new Set([...bookings.docs,...tenantList].map(v=>v.data().staffInChargeId).concat([...assignees])),assignees);
   const cleaning=new Map(await cleaningRead);
   const roomRows=liveRooms.map(v=>{const x=v.data();/* 2026-10-04: every room takes both */return {id:v.id,roomNumber:String(x.roomNumber??''),shortStay:true,monthly:true,blocked:(x.openProblemBlocks??[]).length>0,problems:open.get(v.id)??[],needsCleaning:cleaning.get(v.id)===true};})
    .sort((a,c)=>a.roomNumber.localeCompare(c.roomNumber,undefined,{numeric:true})||a.id.localeCompare(c.id));

   // Cleaning bars: the planned window and the real work time (Bắt đầu → Xong).
   // Managers and reception see all; a cleaner only their own.
   const allTasks=canManageProperty||readBookings||canCreateBookings||canLease;
   const winFrom=`${d.from} 00:00`,winTo=`${d.to} 00:00`,nowLocal=localStamp(nowMs,zone);
   const addMinutes=(s,n)=>localStamp(Date.parse(s.replace(' ','T')+':00Z')+n*60000,'UTC');
   for(const doc of taskList){
    const x=doc.data();
    if(x.organizationId!==O||!roomIds.has(x.roomId)||!['assigned','inProgress','completed'].includes(x.status))continue;
    if(!allTasks&&!(readTasks&&x.assigneeId===uid))continue;
    const planned=typeof x.plannedStart==='string'&&typeof x.plannedEnd==='string';
    const started=localStamp(ms(x.startedAt),zone),done=localStamp(ms(x.completedAt),zone);
    let start,end;
    if(x.status==='completed'&&done){
     // Finished (2026-10-05, Tom): the bar shrinks to the real work time.
     // Marked done without Bắt đầu: from the planned start if it was before,
     // else a short 30 min block ending when it was done.
     start=started&&started<done?started:planned&&x.plannedStart<done?x.plannedStart:addMinutes(done,-30);
     end=done;
    }else{
     const firsts=[planned?x.plannedStart:null,started].filter(Boolean).sort();
     start=firsts[0]??localStamp(ms(x.createdAt),zone);
     if(!start)continue;
     const ends=[planned?x.plannedEnd:null,done,x.status==='inProgress'?nowLocal:null].filter(Boolean).sort();
     end=ends.at(-1)??addMinutes(start,60);
    }
    if(end<=start)end=addMinutes(start,30);
    if(!(start<winTo&&end>winFrom))continue;
    const own=x.assigneeId===uid;
    bars.push({id:`cleaning:${doc.id}`,type:'cleaning',kind:'cleaning',roomId:x.roomId,start,end,recordId:doc.id,
     // Its own states, not a stay's (2026-10-05, Tom).
     status:x.status,taskStatus:x.status,
     canOpen:canManageProperty||own,name:staffName(x.assigneeId)||memberCache.get(x.assigneeId)||'',title:String(x.title??''),
     plannedStart:planned?x.plannedStart:null,plannedEnd:planned?x.plannedEnd:null,actualStart:started,actualEnd:done,
     // The solid part: the work done so far.
     pay:x.status==='completed'?'paid':'due',paidUntil:done??(x.status==='inProgress'?nowLocal:null),problem:false});
   }

   // Short stays.
   for(const doc of bookings.docs){
    if(cleaningOnly)break;
    const x=doc.data();
    if(!ACTIVE_BOOKING.includes(x.status)||!roomIds.has(x.roomId))continue;
    const start=ms(x.startTime),end=ms(x.endTime);
    if(!Number.isFinite(start)||!Number.isFinite(end)||!overlaps(start,end))continue;
    const visible=readBookings&&allows(m,'readBookings',{...scope,record:x});
    const status=x.status==='checkedIn'?'staying':x.status==='checkedOut'?'out':'upcoming';
    const bar={id:`booking:${doc.id}`,type:'booking',roomId:x.roomId,start:localStamp(start,zone),end:localStamp(end,zone),status,canOpen:visible,problem:open.has(x.roomId)&&status!=='out'};
    if(!visible){bars.push({...bar,kind:'short',name:'',anonymous:true});continue;}
    const {pay,fraction}=bookingPay(x);
    // 2026-10-04: two colours (short/long); a paid deposit is a flag for the status circle.
    const deposit=(x.depositPayment&&typeof x.depositPayment==='object')||Math.round((Number(x.depositPaidAmount)||0)*100)>Math.round((Number(x.depositRefundedAmount)||0)*100);
    bars.push({...bar,recordId:doc.id,kind:'short',deposit,name:String(x.guestName??''),
     phone:typeof x.guestPhone==='string'&&x.guestPhone.trim()!=='',channel:x.contactChannel??null,platform:x.platform&&x.platform!=='direct'?x.platform:null,
     guests:Number.isSafeInteger(x.numberOfGuests)?x.numberOfGuests:null,staffName:staffName(x.staffInChargeId),
     pay,paidFraction:fraction,paidUntil:localStamp(start+Math.round((end-start)*fraction),zone),
     currency:x.currency??'VND',totalPrice:x.totalPrice??0,paidAmount:x.paidAmount??0});
   }

   // Leases (main tenants) in their current room.
   const tenantDocs=tenantList.filter(v=>v.data().organizationId===O);
   const mains=tenantDocs.filter(v=>v.data().isMainTenant!==false);
   const leaseIds=new Set(mains.map(v=>v.id));
   for(const h of history.docs){const x=h.data();if(x.organizationId===O&&x.isMainTenant!==false&&id(x.tenantId))leaseIds.add(x.tenantId);}
   // Rent invoices of these leases (by tenant, so a lease billed in another property still counts).
   const invoices=new Map();
   for(const page of await pagesRead){
    for(const v of page.docs){const x=v.data();if(!invoices.has(x.tenantId))invoices.set(x.tenantId,[]);invoices.get(x.tenantId).push(x);}
   }
   const roommates=new Map();
   for(const v of tenantDocs){const x=v.data();if(x.isMainTenant===false&&['active','suspended'].includes(x.status)&&x.moveOutDate==null)roommates.set(x.mainTenantId,(roommates.get(x.mainTenantId)??0)+1);}
   const leaseBar=(tenantId,x,roomId,start,end,status,planned)=>{
    const visible=canLease&&allows(m,'manageLease',{...scope,record:x});
    const bar={id:`lease:${tenantId}:${roomId}:${start}`,type:'lease',roomId,kind:'long',start:localStamp(start,zone)?.slice(0,10)+' 12:00',end:end===null?null:localStamp(end,zone)?.slice(0,10)+' 12:00',plannedEnd:end===null&&validDate(planned)?planned:null,status,canOpen:visible,problem:open.has(roomId)&&status!=='out'};
    if(!visible)return {...bar,name:'',anonymous:true};
    const {pay,paidUntil}=leasePay(x,invoices.get(tenantId)??[],today,status);
    return {...bar,recordId:tenantId,deposit:(Number(x.depositMinor)||0)>0||(Number(x.deposit)||0)>0,name:String(x.fullName??''),phone:typeof x.phoneNumber==='string'&&x.phoneNumber.trim()!=='',
     roommates:roommates.get(tenantId)??0,periodMonths:Number.isSafeInteger(x.paymentPeriodMonths)?x.paymentPeriodMonths:1,
     staffName:staffName(x.staffInChargeId),pay,paidUntil:dateStamp(paidUntil,'00:00')};
   };
   for(const doc of mains){
    if(cleaningOnly)break;
    const x=doc.data();
    if(!roomIds.has(x.roomId)||!['active','suspended','moveOut'].includes(x.status))continue;
    const start=ms(x.occupancyStartDate)??ms(x.moveInDate),end=ms(x.moveOutDate);
    if(!Number.isFinite(start)||(x.status==='moveOut'&&!Number.isFinite(end))||!overlaps(start,end))continue;
    const status=x.status==='moveOut'||end!==null?'out':propertyDate(start,zone)>today?'upcoming':'staying';
    bars.push(leaseBar(doc.id,x,x.roomId,start,end,status,x.contractEndLocalDate));
   }
   // Rooms a lease lived in before a room move.
   const extra=new Map();
   const former=await formerRead;
   formerIds.forEach((t,i)=>extra.set(t,former[i].exists&&former[i].data().organizationId===O?former[i].data():{}));
   for(const h of history.docs){
    if(cleaningOnly)break;
    const x=h.data();
    if(x.organizationId!==O||x.isMainTenant===false||!roomIds.has(x.roomId)||!id(x.tenantId))continue;
    const start=ms(x.start),end=ms(x.end);
    if(!Number.isFinite(start)||!Number.isFinite(end)||!overlaps(start,end))continue;
    let t=mains.find(v=>v.id===x.tenantId)?.data()??extra.get(x.tenantId);
    if(!t){const doc=await db.doc(`tenants/${x.tenantId}`).get();t=doc.exists&&doc.data().organizationId===O?doc.data():{};extra.set(x.tenantId,t);}
    bars.push(leaseBar(x.tenantId,t,x.roomId,start,end,'out',null));
   }
   bars.sort((a,c)=>a.roomId.localeCompare(c.roomId)||String(a.start).localeCompare(String(c.start)));
   return {id:building.id,name:String(b.name??''),timeZone:zone,today,now:localStamp(Timestamp.now().toMillis(),zone),canCreateBookings,canLease,canReadProblems,canReportProblems:canReport,
    cleaningOnly,canAssignCleaning:canManageProperty,canReadCleaning:canManageProperty||readTasks,rooms:roomRows,bars};
  };
  const property=building?await loadBuilding(building):null;
  return {from:d.from,to:d.to,properties:property?[property]:[],
   ...(list?{buildings:list.map(v=>({id:v.id,name:String(v.data().name??'')}))}:{})};
 };
}
module.exports={createCalendarViewHandler,bookingPay,leasePay};
