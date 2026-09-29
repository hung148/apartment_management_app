'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validSchedule,withinSchedule}=require('./operating_schedule');
const ACTIVE=new Set(['pending','confirmed','checkedIn']);
const validZone=zone=>{
  if(typeof zone!=='string'||zone.length>100||! /^(UTC|[A-Za-z_]+\/[A-Za-z_+\/-]+)$/.test(zone))return false;
  try {new Intl.DateTimeFormat('en',{timeZone:zone}).format(0);return true;}catch{return false;}
};
function withinHours(start,end,settings,zone) {
  if(settings.operatingSchedule!=null)return validZone(zone)&&withinSchedule(start,end,settings.operatingSchedule,zone);
  const open=settings.operatingHoursStartMin,close=settings.operatingHoursEndMin;
  if(open==null&&close==null)return true;
  if(!Number.isInteger(open)||!Number.isInteger(close)||open<0||open>=1440||close<0||close>1440||close===open||!validZone(zone)||!Number.isFinite(start)||!Number.isFinite(end)||end<=start||end-start>26*3600000)return false;
  const fmt=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
  let date;
  const inside=instant=>{
    const p=Object.fromEntries(fmt.formatToParts(instant).map(v=>[v.type,v.value]));
    const minute=Number(p.hour)*60+Number(p.minute),overnight=close<open;
    if(overnight ? minute<open&&minute>=close : minute<open||minute>=close)return false;
    // Early morning belongs to the window opened on the previous local date.
    // Calendar arithmetic uses UTC solely to avoid the host machine's timezone.
    const day=new Date(Date.UTC(Number(p.year),Number(p.month)-1,Number(p.day)-(overnight&&minute<close?1:0))).toISOString().slice(0,10);
    date??=day;return day===date;
  };
  if(!inside(start)||!inside(end-1))return false;
  // Check every UTC minute boundary as well as endpoints, including a DST fold.
  for(let time=Math.floor(start/60000)*60000+60000;time<end;time+=60000)if(!inside(time))return false;
  return true;
}
function createBookingSettingsHandler({db,Timestamp,HttpsError}) {
  const fail=(code,message='settings_'+code)=>{throw new HttpsError(code,message);};
  const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
  const fields=['minBookingHours','cleaningBufferMinutes','operatingHoursStartMin','operatingHoursEndMin'];
  const snapshot=value=>Object.fromEntries(fields.map(k=>[k,value[k]??(k==='minBookingHours'||k==='cleaningBufferMinutes'?0:null)]));
  return async request=>{
    const uid=request.auth?.uid,d=request.data||{},write=d.action==='update';
    if(!uid)fail('unauthenticated');
    const keys=['action','organizationId','buildingId','roomId',...(write?['operationId','revision','timeZone',...fields,...(Object.hasOwn(d,'operatingSchedule')?['operatingSchedule']:[])]:[])];
    if(!['read','update'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||!id(d.roomId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
    if(write){
      if(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)||!Number.isInteger(d.minBookingHours)||d.minBookingHours<0||d.minBookingHours>168||!Number.isInteger(d.cleaningBufferMinutes)||d.cleaningBufferMinutes<0||d.cleaningBufferMinutes>1440||!(d.timeZone===null||validZone(d.timeZone)))fail('invalid-argument');
      if(d.operatingSchedule!=null&&(!validSchedule(d.operatingSchedule)||d.operatingHoursStartMin!==null||d.operatingHoursEndMin!==null))fail('invalid-argument');
      const a=d.operatingHoursStartMin,b=d.operatingHoursEndMin;
      if(!(a===null&&b===null)&&(!Number.isInteger(a)||!Number.isInteger(b)||a<0||a>=1440||b<0||b>1440||a===b))fail('invalid-argument');
    }
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      if(!org.exists||org.data().accessVersion!==2||!allows(member.data(),'manageProperty',{organizationId:d.organizationId,userId:uid,buildingId:d.buildingId}))fail('permission-denied');
      const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),ref=db.doc(`rooms/${d.roomId}`),doc=await tx.get(ref),old=doc.data();
      if(!building.exists||building.data().organizationId!==d.organizationId||!old||old.organizationId!==d.organizationId||old.buildingId!==d.buildingId)fail('not-found');
      const revision=`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`,zone=building.data().timeZone??null;
      if(!write)return {record:{roomNumber:old.roomNumber??'',revision,timeZone:zone,...snapshot(old),operatingSchedule:old.operatingSchedule??null}};
      const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
      const key=hash(['bookingSettings',d.organizationId,uid,d.operationId]),fingerprint=hash(keys.map(k=>d[k]));
      const op=db.doc(`bookingSettingOperations/${key}`),prior=await tx.get(op);
      if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
      if(old.operatingSchedule!=null&&!Object.hasOwn(d,'operatingSchedule'))fail('failed-precondition','settings_client_update_required');
      if(revision!==d.revision||d.timeZone!==zone)fail('aborted');
      if((d.operatingHoursStartMin!==null||d.operatingSchedule!=null)&&!validZone(zone))fail('failed-precondition','settings_timezone_required');
      const bookings=await tx.get(db.collection('bookings').where('roomId','==',d.roomId));
      const rows=bookings.docs.map(v=>v.data()).filter(v=>ACTIVE.has(v.status)).map(v=>({start:v.startTime?.toMillis?.(),end:v.endTime?.toMillis?.()})).sort((a,b)=>a.start-b.start);
      for(let i=0;i<rows.length;i++){
        const {start,end}=rows[i];
        if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start||end-start<d.minBookingHours*3600000||!withinHours(start,end,d,zone)||i>0&&start<rows[i-1].end+d.cleaningBufferMinutes*60000)fail('failed-precondition','settings_existing_conflict');
      }
      const patch={...snapshot(d),operatingSchedule:d.operatingSchedule??null},now=Timestamp.now(),result={roomId:d.roomId};
      tx.update(ref,{...patch,updatedAt:now,updatedBy:uid});
      // Property timezone edits and settings writes must serialize together.
      tx.update(building.ref,{bookingSettingsUpdatedAt:now});
      tx.create(op,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
      tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'room_booking_settings_updated',targetId:d.roomId,createdAt:now,before:{buildingId:d.buildingId,...snapshot(old),operatingSchedule:old.operatingSchedule??null},after:{buildingId:d.buildingId,timeZone:zone,...patch}});
      return result;
    });
  };
}
module.exports={createBookingSettingsHandler,validZone,withinHours};
