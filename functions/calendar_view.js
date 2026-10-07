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
const MAX_DAYS=100,MAX_PROPERTIES=50;
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
  if(!id(d.organizationId)||!validDate(d.from)||!validDate(d.to)||Object.keys(d).some(k=>!['organizationId','from','to'].includes(k)))fail('invalid-argument');
  const span=daysBetween(d.from,d.to);
  if(span<1||span>MAX_DAYS)fail('invalid-argument');
  const [org,memberDoc]=await Promise.all([db.doc(`organizations/${d.organizationId}`).get(),db.doc(`memberships/${uid}_${d.organizationId}`).get()]);
  const m=memberDoc.data();
  if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||!m||m.organizationId!==d.organizationId||m.ownerId!==uid||m.accessVersion!==2||m.status!=='active'||!hasRole(m)||!['all','selected'].includes(m.buildingScope))fail('permission-denied');

  // Properties the member reaches (same rule as the workspace property list).
  let buildings;
  if(reachesAllProperties(m)){
   buildings=(await db.collection('buildings').where('organizationId','==',d.organizationId).get()).docs;
  }else{
   const ids=Array.isArray(m.buildingIds)?[...new Set(m.buildingIds.filter(id))]:[];
   buildings=(await Promise.all(ids.map(v=>db.doc(`buildings/${v}`).get()))).filter(v=>v.exists&&v.data().organizationId===d.organizationId);
  }
  buildings=buildings.filter(b=>!b.data().deletedAt).sort((a,b)=>String(a.data().name??'').localeCompare(String(b.data().name??''),undefined,{numeric:true})||a.id.localeCompare(b.id));
  if(buildings.length>MAX_PROPERTIES)buildings=buildings.slice(0,MAX_PROPERTIES);
  const staffDocs=(await db.collection('staffProfiles').where('organizationId','==',d.organizationId).get()).docs;
  const staffNames=new Map(staffDocs.map(v=>[v.id,String(v.data().displayName??'')]));
  // Cleaning is assigned to an account; show the member's name (as the task list does).
  const assigneeNames=new Map();

  const properties=[];
  for(const building of buildings){
   const b=building.data(),zone=b.timeZone,scope={organizationId:d.organizationId,userId:uid,buildingId:building.id},can=p=>allows(m,p,scope);
   const readBookings=allows(m,'readBookings',{...scope,anyRecord:true}),canLease=can('manageLease');
   const canCreateBookings=can('createBookings'),canManageProperty=can('manageProperty');
   // 2026-10-05 (Tom): cleaners get the calendar too, with cleaning only: their
   // own cleaning bars and which rooms need cleaning (no guests, no money).
   const readTasks=can('readAssignedTasks');
   const cleaningOnly=!readBookings&&!canLease&&!canCreateBookings&&!canManageProperty;
   if(cleaningOnly&&!readTasks)continue;
   if(!validZone(zone)){properties.push({id:building.id,name:b.name??'',timeZone:null,today:null,needsTimeZone:true,rooms:[],bars:[]});continue;}
   const today=propertyDate(Timestamp.now().toMillis(),zone),from=propertyDayStart(d.from,zone),to=propertyDayStart(d.to,zone);
   if(from===null||to===null)fail('invalid-argument');
   const canReport=canManageProperty||canCreateBookings||can('manageBookings')||canLease||can('updateAssignedTasks');
   const canReadProblems=canReport||readBookings||can('readAssignedTasks');
   const where=c=>db.collection(c).where('organizationId','==',d.organizationId).where('buildingId','==',building.id).get();
   const [rooms,bookings,tenants,history,problems,tasks]=await Promise.all([
    where('rooms'),where('bookings'),where('tenants'),
    db.collection('leaseOccupancy').where('buildingId','==',building.id).get(),
    canReadProblems?db.collection('technicalProblems').where('organizationId','==',d.organizationId).where('buildingId','==',building.id).where('status','==','open').get():null,
    where('housekeepingTasks'),
   ]);
   const roomIds=new Set(rooms.docs.map(v=>v.id));
   const newAssignees=[...new Set(tasks.docs.map(v=>v.data().assigneeId).filter(v=>typeof v==='string'&&v&&!assigneeNames.has(v)&&!staffNames.get(v)))];
   await Promise.all(newAssignees.map(async u=>{const x=(await db.doc(`memberships/${u}_${d.organizationId}`).get()).data();assigneeNames.set(u,typeof x?.displayName==='string'&&x.displayName.trim()?x.displayName.trim():(typeof x?.email==='string'?x.email:''));}));
   const open=new Map();
   for(const p of problems?.docs??[]){const x=p.data();if(!open.has(x.roomId))open.set(x.roomId,[]);open.get(x.roomId).push({id:p.id,title:String(x.title??''),blocksRoom:x.blocksRoom===true});}
   // Needs cleaning (2026-10-05, Tom): a guest left (check-out, lease move-out)
   // after the room's last finished cleaning.
   const nowMs=Timestamp.now().toMillis(),lastOut=new Map(),lastClean=new Map();
   const later=(map,k,v)=>{if(Number.isFinite(v)&&v<=nowMs&&!(map.get(k)>=v))map.set(k,v);};
   for(const v of bookings.docs){const x=v.data();if(x.status==='checkedOut')later(lastOut,x.roomId,ms(x.checkedOutAt)??ms(x.endTime));}
   for(const v of tenants.docs){const x=v.data();if(x.organizationId===d.organizationId&&x.isMainTenant!==false&&x.status==='moveOut')later(lastOut,x.roomId,ms(x.moveOutDate));}
   for(const v of tasks.docs){const x=v.data();if(x.organizationId===d.organizationId&&x.status==='completed')later(lastClean,x.roomId,ms(x.completedAt));}
   const needsCleaning=r=>lastOut.has(r)&&!(lastClean.get(r)>=lastOut.get(r));
   const roomRows=rooms.docs.filter(v=>!v.data().deletedAt).map(v=>{const x=v.data(),mode='both';/* 2026-10-04: every room takes both */return {id:v.id,roomNumber:String(x.roomNumber??''),shortStay:true,monthly:true,blocked:(x.openProblemBlocks??[]).length>0,problems:open.get(v.id)??[],needsCleaning:needsCleaning(v.id)};})
    .sort((a,c)=>a.roomNumber.localeCompare(c.roomNumber,undefined,{numeric:true})||a.id.localeCompare(c.id));
   const overlaps=(start,end)=>start!==null&&start<to&&(end===null||end>from);
   const bars=[];

   // Cleaning bars: the planned window and the real work time (Bắt đầu → Xong).
   // Managers and reception see all; a cleaner only their own.
   const allTasks=canManageProperty||readBookings||canCreateBookings||canLease;
   const winFrom=`${d.from} 00:00`,winTo=`${d.to} 00:00`,nowLocal=localStamp(nowMs,zone);
   const addMinutes=(s,n)=>localStamp(Date.parse(s.replace(' ','T')+':00Z')+n*60000,'UTC');
   for(const doc of tasks.docs){
    const x=doc.data();
    if(x.organizationId!==d.organizationId||!roomIds.has(x.roomId)||!['assigned','inProgress','completed'].includes(x.status))continue;
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
     canOpen:canManageProperty||own,name:staffNames.get(x.assigneeId)||assigneeNames.get(x.assigneeId)||'',title:String(x.title??''),
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
     guests:Number.isSafeInteger(x.numberOfGuests)?x.numberOfGuests:null,staffName:staffNames.get(x.staffInChargeId)??'',
     pay,paidFraction:fraction,paidUntil:localStamp(start+Math.round((end-start)*fraction),zone),
     currency:x.currency??'VND',totalPrice:x.totalPrice??0,paidAmount:x.paidAmount??0});
   }

   // Leases (main tenants) in their current room.
   const tenantDocs=tenants.docs.filter(v=>v.data().organizationId===d.organizationId);
   const mains=tenantDocs.filter(v=>v.data().isMainTenant!==false);
   const leaseIds=new Set(mains.map(v=>v.id));
   for(const h of history.docs){const x=h.data();if(x.organizationId===d.organizationId&&x.isMainTenant!==false&&id(x.tenantId))leaseIds.add(x.tenantId);}
   // Rent invoices of these leases (by tenant, so a lease billed in another property still counts).
   const invoices=new Map();
   if(canLease){
    const list=[...leaseIds];
    for(let i=0;i<list.length;i+=30){
     const page=await db.collection('payments').where('organizationId','==',d.organizationId).where('tenantId','in',list.slice(i,i+30)).get();
     for(const v of page.docs){const x=v.data();if(!invoices.has(x.tenantId))invoices.set(x.tenantId,[]);invoices.get(x.tenantId).push(x);}
    }
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
     staffName:staffNames.get(x.staffInChargeId)??'',pay,paidUntil:dateStamp(paidUntil,'00:00')};
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
   for(const h of history.docs){
    if(cleaningOnly)break;
    const x=h.data();
    if(x.organizationId!==d.organizationId||x.isMainTenant===false||!roomIds.has(x.roomId)||!id(x.tenantId))continue;
    const start=ms(x.start),end=ms(x.end);
    if(!Number.isFinite(start)||!Number.isFinite(end)||!overlaps(start,end))continue;
    let t=mains.find(v=>v.id===x.tenantId)?.data()??extra.get(x.tenantId);
    if(!t){const doc=await db.doc(`tenants/${x.tenantId}`).get();t=doc.exists&&doc.data().organizationId===d.organizationId?doc.data():{};extra.set(x.tenantId,t);}
    bars.push(leaseBar(x.tenantId,t,x.roomId,start,end,'out',null));
   }
   bars.sort((a,c)=>a.roomId.localeCompare(c.roomId)||String(a.start).localeCompare(String(c.start)));
   properties.push({id:building.id,name:String(b.name??''),timeZone:zone,today,now:localStamp(Timestamp.now().toMillis(),zone),canCreateBookings,canLease,canReadProblems,canReportProblems:canReport,
    cleaningOnly,canAssignCleaning:canManageProperty,canReadCleaning:canManageProperty||readTasks,rooms:roomRows,bars});
  }
  return {from:d.from,to:d.to,properties};
 };
}
module.exports={createCalendarViewHandler,bookingPay,leasePay};
