'use strict';
// B7a technical problems (sự cố kỹ thuật), TECHNICAL_PROBLEMS.md.
// A problem belongs to one room. Anyone who works on the property can report
// one; a property manager edits it, marks it fixed (who fixed it, when, cost,
// optionally recorded as a paid building expense in "Thu chi") or reopens it.
// "Room unavailable while open" (blocksRoom) puts the problem id on the room
// (rooms/{id}.openProblemBlocks); new bookings, new leases and lease moves
// into that room are refused while the list is not empty. Existing bookings
// and leases are only listed as a warning, never cancelled.
// B7b photos: stored in the owner's Google Drive (drive.js); the problem keeps
// the Drive file ids. Staff who can report add photos while the problem is open;
// a manager adds or removes any photo; whoever added a photo may remove it.
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {validDate}=require('./property_contract');
const {propertyDate,propertyDayStart}=require('./lease_dates');
const {driveAccess,driveSummary,driveConnectionFor}=require('./drive');

const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const revision=d=>`${d.updateTime.seconds}:${d.updateTime.nanoseconds}`;
const text=(v,max)=>typeof v==='string'&&v.trim().length>0&&v.length<=max;
const optText=(v,max)=>typeof v==='string'&&v.length<=max;
const MAX=1e12;
const ACTIVE_BOOKING=['pending','confirmed','checkedIn'];
const ms=v=>v?.toMillis?.()??(typeof v?.__timestamp==='number'?v.__timestamp:null);

const KEYS={
 list:['status'],
 report:['operationId','roomId','title','description','blocksRoom'],
 update:['operationId','problemId','revision','title','description','blocksRoom'],
 fix:['inputCurrency','operationId','problemId','revision','fixedByName','fixedDate','costMinor','recordExpense','paymentMethod','accountId','note'],
 reopen:['operationId','problemId','revision','note'],
 addPhoto:['operationId','problemId','mimeType','dataBase64'],
 photo:['problemId','photoId'],
 removePhoto:['operationId','problemId','photoId'],
};
const MAX_PHOTOS=6,MAX_PHOTO_BYTES=2*1024*1024;
const PHOTO_TYPES={'image/jpeg':b=>b[0]===0xff&&b[1]===0xd8&&b[2]===0xff,'image/png':b=>b[0]===0x89&&b.toString('latin1',1,4)==='PNG',
 'image/webp':b=>b.toString('latin1',0,4)==='RIFF'&&b.toString('latin1',8,12)==='WEBP'};
const EXT={'image/jpeg':'jpg','image/png':'png','image/webp':'webp'};

/** Input check. Returns an error key or null. */
function invalidProblemInput(d){
 if(!d||!Object.hasOwn(KEYS,d.action))return 'problem_invalid';
 const keys=['action','organizationId','buildingId',...KEYS[d.action]];
 if(Object.keys(d).some(k=>!keys.includes(k))||!id(d.organizationId)||!id(d.buildingId))return 'problem_invalid';
 if(d.action==='list')return d.status===undefined||['open','fixed','all'].includes(d.status)?null:'problem_invalid';
 if(d.action==='photo')return id(d.problemId)&&id(d.photoId)?null:'problem_invalid';
 if(!id(d.operationId))return 'problem_invalid';
 if(d.action==='addPhoto'){
  if(!id(d.problemId)||!Object.hasOwn(PHOTO_TYPES,d.mimeType)||typeof d.dataBase64!=='string'||d.dataBase64.length>Math.ceil(MAX_PHOTO_BYTES/3)*4+4||!/^[A-Za-z0-9+/]+={0,2}$/.test(d.dataBase64))return 'problem_photo_invalid';
  return null;
 }
 if(d.action==='removePhoto')return id(d.problemId)&&id(d.photoId)?null:'problem_invalid';
 if(d.action!=='report'&&(!id(d.problemId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))return 'problem_invalid';
 if(d.action==='report'&&!id(d.roomId))return 'problem_invalid';
 if(['report','update'].includes(d.action)){
  if(!text(d.title,120)||!optText(d.description,2000)||typeof d.blocksRoom!=='boolean')return 'problem_invalid_text';
 }
 if(d.action==='fix'){
  if(d.inputCurrency!==undefined&&!['VND','USD'].includes(d.inputCurrency))return 'problem_invalid_cost';
  if(!text(d.fixedByName,120)||!validDate(d.fixedDate)||!optText(d.note,1000))return 'problem_invalid_fix';
  if(d.costMinor!==null&&(!Number.isSafeInteger(d.costMinor)||d.costMinor<0||d.costMinor>MAX))return 'problem_invalid_cost';
  if(typeof d.recordExpense!=='boolean')return 'problem_invalid_fix';
  if(d.recordExpense){
   if(!(d.costMinor>0))return 'problem_expense_needs_cost';
   if(!['cash','bankTransfer'].includes(d.paymentMethod))return 'problem_expense_needs_method';
   if(d.accountId!==null&&(!id(d.accountId)||d.paymentMethod!=='bankTransfer'))return 'problem_invalid_fix';
  }else if(d.paymentMethod!==null||d.accountId!==null)return 'problem_invalid_fix';
 }
 if(d.action==='reopen'&&!text(d.note,1000))return 'problem_reopen_needs_reason';
 return null;
}

function createTechnicalProblemsHandler({db,Timestamp,HttpsError,drive=null}){
 const fail=(code,key)=>{throw new HttpsError(code,key);};
 const drives=drive?driveAccess({db,drive,HttpsError}):null;
 return async request=>{
  const d=request.data||{},uid=request.auth?.uid;
  if(!uid)fail('unauthenticated','problem_sign_in_required');
  const bad=invalidProblemInput(d);if(bad)fail('invalid-argument',bad);
  if(['addPhoto','photo','removePhoto'].includes(d.action))return photos(d,uid,request);
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),m=member.data();
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt)fail('failed-precondition','team_migration_required');
   const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId},can=p=>allows(m,p,scope);
   const canManage=can('manageProperty');
   const canReport=canManage||can('createBookings')||can('manageBookings')||can('manageLease')||can('updateAssignedTasks');
   const canRead=canReport||can('readBookings')||can('readAssignedTasks');
   const canExpense=canManage&&can('collectPayments');
   if(!canRead)fail('permission-denied','problem_access_denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),b=building.data();
   if(!b||b.organizationId!==d.organizationId)fail('not-found','problem_property_not_found');
   const zone=b.timeZone,now=Timestamp.now(),today=zone?propertyDate(now.toMillis(),zone):null;
   const currency=org.data().displayCurrency??(b.currency==='USD'?'USD':'VND'),scale=currency==='USD'?100:1;

   if(d.action==='list'){
    const rows=(await tx.get(db.collection('technicalProblems').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId))).docs;
    const status=d.status??'all';
    const records=rows.filter(v=>status==='all'||v.data().status===status).map(v=>{const x=v.data();return {
     id:v.id,revision:revision(v),roomId:x.roomId,roomNumber:x.roomNumber??'',title:x.title,description:x.description??'',status:x.status,blocksRoom:x.blocksRoom===true,
     reportedByName:x.reportedByName??'',reportedLocalDate:x.reportedLocalDate??null,occupant:x.occupant??null,fixedByName:x.fixedByName??null,fixedLocalDate:x.fixedLocalDate??null,
     costMinor:x.costMinor??null,currency:x.currency??(b.currency==='USD'?'USD':'VND'),expenseId:x.expenseId??null,note:x.note??'',
     photos:(x.photos??[]).map(p=>({id:p.id,mimeType:p.mimeType,addedBy:p.addedBy,addedByName:p.addedByName??'',addedLocalDate:p.addedLocalDate??null}))};})
     .sort((a,b2)=>(a.status===b2.status?0:a.status==='open'?-1:1)||String(b2.reportedLocalDate).localeCompare(String(a.reportedLocalDate))||a.id.localeCompare(b2.id)).slice(0,300);
    const rooms=(await tx.get(db.collection('rooms').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId))).docs
     .map(v=>({id:v.id,roomNumber:v.data().roomNumber??'',blocked:(v.data().openProblemBlocks??[]).length>0})).sort((a,b2)=>String(a.roomNumber).localeCompare(String(b2.roomNumber),undefined,{numeric:true}));
    const accounts=canExpense?(Array.isArray(org.data().paymentAccounts)?org.data().paymentAccounts:[]).filter(a=>a&&id(a.id)).map(a=>({id:a.id,label:a.label??''})):[];
    const driveState=driveSummary((await driveConnectionFor(db,d.organizationId,r=>tx.get(r))).data);
    return {records,rooms,accounts,currency,today,canReport,canManage,canExpense,uid,drive:{state:driveState.state,email:driveState.email}};
   }

   if(d.action==='report'?!canReport:!canManage)fail('permission-denied','problem_access_denied');
   if(d.blocksRoom===true&&!canManage)fail('permission-denied','problem_block_needs_manager');
   const key=hash(['problem',d.organizationId,uid,d.operationId]),op=db.doc(`problemOperations/${key}`),prior=await tx.get(op);
   const fingerprint=hash(['action','organizationId','buildingId',...KEYS[d.action].filter(k=>k!=='inputCurrency'||d.inputCurrency!==undefined)].map(k=>d[k]));
   if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition','problem_operation_reused');return prior.data().result;}
   if(d.action==='fix'&&d.costMinor!==null&&(d.inputCurrency??b.currency??'VND')!==currency)fail('failed-precondition','problem_currency_changed');
   if(!today)fail('failed-precondition','lease_property_timezone_required');

   // The problem (existing or new) and its room.
   let ref,old=null;
   if(d.action==='report'){ref=db.doc(`technicalProblems/problem_${key}`);}
   else{
    ref=db.doc(`technicalProblems/${d.problemId}`);const snap=await tx.get(ref);old=snap.data();
    if(!old||old.organizationId!==d.organizationId||old.buildingId!==d.buildingId)fail('not-found','problem_not_found');
    if(revision(snap)!==d.revision)fail('aborted','problem_changed');
   }
   const roomId=old?.roomId??d.roomId,roomRef=db.doc(`rooms/${roomId}`),roomDoc=await tx.get(roomRef),room=roomDoc.data();
   if(!room||room.organizationId!==d.organizationId||room.buildingId!==d.buildingId)fail('failed-precondition','problem_room_not_found');

   // Who lives there or is booked now/later: shown as a warning when the room is blocked.
   const occupancy=async()=>{
    const out=[],nowMs=now.toMillis();
    for(const v of (await tx.get(db.collection('bookings').where('roomId','==',roomId))).docs){const x=v.data();if(x.organizationId===d.organizationId&&ACTIVE_BOOKING.includes(x.status)&&(ms(x.endTime)??Infinity)>nowMs)out.push({kind:'booking',id:v.id,name:x.guestName??'',status:x.status,start:x.startTime?propertyDate(ms(x.startTime),zone):null,end:x.endTime?propertyDate(ms(x.endTime),zone):null});}
    for(const v of (await tx.get(db.collection('tenants').where('roomId','==',roomId))).docs){const x=v.data();if(x.organizationId===d.organizationId&&x.isMainTenant!==false&&['active','suspended'].includes(x.status)&&!(x.moveOutDate&&ms(x.moveOutDate)<=nowMs))out.push({kind:'lease',id:v.id,name:x.fullName??'',status:x.status,start:(x.occupancyStartDate??x.moveInDate)?propertyDate(ms(x.occupancyStartDate??x.moveInDate),zone):null,end:x.moveOutDate?propertyDate(ms(x.moveOutDate),zone):null});}
    return out.sort((a,b2)=>String(a.start).localeCompare(String(b2.start)));
   };
   const people=await occupancy();

   // Writes (all reads above, except the expense account list from org).
   const blocks=new Set(room.openProblemBlocks??[]);
   const name=String(m?.displayName||request.auth?.token?.email||'').slice(0,120);
   let patch,historyAction,result;
   if(d.action==='report'){
    const current=people.find(p=>p.kind==='lease'||(p.kind==='booking'&&p.status==='checkedIn'));
    patch={organizationId:d.organizationId,buildingId:d.buildingId,roomId,roomNumber:room.roomNumber??'',title:d.title.trim(),description:d.description.trim(),status:'open',blocksRoom:d.blocksRoom,
     reportedBy:uid,reportedByName:name,reportedAt:now,reportedLocalDate:today,occupant:current?{kind:current.kind,id:current.id,name:current.name}:null,
     fixedByName:null,fixedLocalDate:null,costMinor:null,currency,expenseId:null,note:'',photos:[],createdAt:now,updatedAt:now,updatedBy:uid};
    tx.create(ref,patch);historyAction='report';
    if(d.blocksRoom)blocks.add(ref.id);
    result={problemId:ref.id,warnings:d.blocksRoom?people:[]};
   }else if(d.action==='update'){
    if(old.status!=='open'&&d.blocksRoom)fail('failed-precondition','problem_not_open');
    patch={title:d.title.trim(),description:d.description.trim(),blocksRoom:d.blocksRoom,updatedAt:now,updatedBy:uid};
    tx.update(ref,patch);historyAction='update';
    if(old.status==='open'){if(d.blocksRoom)blocks.add(ref.id);else blocks.delete(ref.id);}
    result={problemId:ref.id,warnings:d.blocksRoom&&!old.blocksRoom?people:[]};
   }else if(d.action==='fix'){
    if(old.status!=='open')fail('failed-precondition','problem_not_open');
    if(d.fixedDate>today)fail('invalid-argument','problem_fixed_in_future');
    if(d.fixedDate<old.reportedLocalDate)fail('invalid-argument','problem_fixed_before_report');
    let expenseId=null;
    if(d.recordExpense){
     if(!canExpense)fail('permission-denied','problem_expense_needs_permission');
     const accounts=Array.isArray(org.data().paymentAccounts)?org.data().paymentAccounts:[];
     const account=d.accountId?accounts.find(a=>a?.id===d.accountId):null;if(d.accountId&&!account)fail('invalid-argument','problem_invalid_fix');
     expenseId='invoice_'+key;const due=propertyDayStart(d.fixedDate,zone);
     // tenantName is the list title: here, who was paid for the repair.
     const expense={organizationId:d.organizationId,buildingId:d.buildingId,roomId,tenantId:null,tenantName:d.fixedByName.trim(),invoiceVersion:2,invoiceKind:'repair',type:'repair',direction:'expense',currency,
      amount:d.costMinor/scale,amountMinor:d.costMinor,totalMinor:d.costMinor,paidAmount:d.costMinor/scale,status:'paid',paidAt:now,paidBy:uid,paymentMethod:d.paymentMethod,
      ...(account?{paymentAccountId:account.id,paymentAccountLabel:account.label??''}:{}),
      billingStartLocalDate:d.fixedDate,billingEndLocalDate:d.fixedDate,dueLocalDate:d.fixedDate,dueDate:Timestamp.fromMillis(due),timeZone:zone,
      calculation:{chargeType:'repair',amountMinor:d.costMinor,currency,problemId:ref.id,roomNumber:room.roomNumber??'',title:old.title,fixedByName:d.fixedByName.trim()},
      problemId:ref.id,description:`${old.title} — ${d.fixedByName.trim()}`.slice(0,1000),createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid};
     const eref=db.doc(`payments/${expenseId}`);tx.create(eref,expense);
     tx.create(eref.collection('invoiceHistory').doc(key),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'create',reason:`Sự cố: ${old.title}`.slice(0,1000),before:null,after:{totalMinor:d.costMinor,paidAmount:d.costMinor/scale,status:'paid'},problemId:ref.id});
     tx.update(building.ref,{invoiceRevision:(b.invoiceRevision??0)+1});
    }
    patch={status:'fixed',fixedByName:d.fixedByName.trim(),fixedLocalDate:d.fixedDate,fixedAt:now,fixedBy:uid,costMinor:d.costMinor,currency,expenseId,note:d.note.trim(),updatedAt:now,updatedBy:uid};
    tx.update(ref,patch);historyAction='fix';blocks.delete(ref.id);
    result={problemId:ref.id,expenseId,warnings:[]};
   }else{ // reopen
    if(old.status!=='fixed')fail('failed-precondition','problem_not_fixed');
    patch={status:'open',fixedByName:null,fixedLocalDate:null,fixedAt:null,fixedBy:null,note:d.note.trim(),reopenedAt:now,updatedAt:now,updatedBy:uid};
    // A recorded expense stays in Thu chi (money already spent); the link is kept for history.
    tx.update(ref,patch);historyAction='reopen';
    if(old.blocksRoom)blocks.add(ref.id);
    result={problemId:ref.id,warnings:old.blocksRoom?people:[]};
   }
   const before=new Set(room.openProblemBlocks??[]);
   if(before.size!==blocks.size||[...blocks].some(x=>!before.has(x))){
    // Same shared write as bookings: a booking racing with this block serializes on the room.
    tx.update(roomRef,{openProblemBlocks:[...blocks].sort(),bookingRevision:(room.bookingRevision??0)+1});
   }
   tx.create(ref.collection('problemHistory').doc(key),{organizationId:d.organizationId,actorId:uid,actorName:name,createdAt:now,action:historyAction,
    before:old?{status:old.status,title:old.title,blocksRoom:old.blocksRoom===true,costMinor:old.costMinor??null}:null,after:{status:patch.status??old?.status,title:patch.title??old?.title,blocksRoom:patch.blocksRoom??old?.blocksRoom===true,costMinor:patch.costMinor??old?.costMinor??null}});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'problem_'+historyAction,targetId:ref.id,after:{buildingId:d.buildingId,roomId,status:patch.status??old?.status}});
   tx.create(op,{organizationId:d.organizationId,actorId:uid,createdAt:now,fingerprint,result});
   return result;
  });
 };

 // Photos talk to Google Drive, which cannot be part of a Firestore
 // transaction: check first, do the Drive step, then record it in one
 // transaction that checks again (and undoes the Drive step if it lost).
 async function photos(d,uid,request){
  const load=async()=>{
   const org=(await db.doc(`organizations/${d.organizationId}`).get()).data(),m=(await db.doc(`memberships/${uid}_${d.organizationId}`).get()).data();
   if(!org||org.accessVersion!==2||org.closedAt)fail('failed-precondition','team_migration_required');
   const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId},can=p=>allows(m,p,scope);
   const canManage=can('manageProperty');
   const canReport=canManage||can('createBookings')||can('manageBookings')||can('manageLease')||can('updateAssignedTasks');
   const canRead=canReport||can('readBookings')||can('readAssignedTasks');
   if(!canRead)fail('permission-denied','problem_access_denied');
   const b=(await db.doc(`buildings/${d.buildingId}`).get()).data();
   if(!b||b.organizationId!==d.organizationId)fail('not-found','problem_property_not_found');
   const p=(await db.doc(`technicalProblems/${d.problemId}`).get()).data();
   if(!p||p.organizationId!==d.organizationId||p.buildingId!==d.buildingId)fail('not-found','problem_not_found');
   return {m,b,p,canManage,canReport};
  };
  const {m,b,p,canManage,canReport}=await load();
  if(!drives)fail('failed-precondition','drive_not_configured');
  const list=p.photos??[];
  if(d.action==='photo'){
   if(!list.some(x=>x.id===d.photoId))fail('not-found','problem_photo_missing');
   const session=await drives.open(d.organizationId),file=await session.download(d.photoId);
   return {photoId:d.photoId,mimeType:file.mimeType,dataBase64:file.bytes.toString('base64')};
  }
  const key=hash(['problem',d.organizationId,uid,d.operationId]),op=db.doc(`problemOperations/${key}`);
  const fingerprint=hash(['action','organizationId','buildingId',...KEYS[d.action]].map(k=>k==='dataBase64'?hash(d[k]):d[k]));
  const prior=(await op.get()).data();
  if(prior){if(prior.fingerprint!==fingerprint)fail('failed-precondition','problem_operation_reused');return prior.result;}
  const ref=db.doc(`technicalProblems/${d.problemId}`),now=Timestamp.now();
  const today=b.timeZone?propertyDate(now.toMillis(),b.timeZone):null;
  const name=String(m?.displayName||request.auth?.token?.email||'').slice(0,120);
  if(d.action==='addPhoto'){
   if(!(canManage||(canReport&&p.status==='open')))fail('permission-denied',canReport?'problem_not_open':'problem_access_denied');
   if(list.length>=MAX_PHOTOS)fail('failed-precondition','problem_photo_limit');
   const bytes=Buffer.from(d.dataBase64,'base64');
   if(!bytes.length||bytes.length>MAX_PHOTO_BYTES||!PHOTO_TYPES[d.mimeType](bytes))fail('invalid-argument','problem_photo_invalid');
   const session=await drives.open(d.organizationId);
   const folder=await session.problemsFolder(d.buildingId,b.name);
   const fileName=`${p.roomNumber||'Phong'} ${today??''} ${p.title}`.replace(/[\\/:*?"<>|]+/g,' ').replace(/\s+/g,' ').trim().slice(0,90)+` (${list.length+1}).${EXT[d.mimeType]}`;
   const file=await session.upload({name:fileName,mimeType:d.mimeType,parent:folder,bytes});
   const photo={id:file.id,mimeType:d.mimeType,sizeBytes:bytes.length,addedBy:uid,addedByName:name,addedLocalDate:today,addedAt:now};
   let lost=false;
   const result=await db.runTransaction(async tx=>{
    const again=await tx.get(op);if(again.exists){lost=true;return again.data().result;}
    const cur=(await tx.get(ref)).data();
    if(!cur)fail('not-found','problem_not_found');
    if((cur.photos??[]).length>=MAX_PHOTOS){lost=true;fail('failed-precondition','problem_photo_limit');}
    tx.update(ref,{photos:[...(cur.photos??[]),photo],updatedAt:now,updatedBy:uid});
    const out={problemId:ref.id,photo:{id:photo.id,mimeType:photo.mimeType,addedBy:uid,addedByName:name,addedLocalDate:today}};
    tx.create(ref.collection('problemHistory').doc(key),{organizationId:d.organizationId,actorId:uid,actorName:name,createdAt:now,action:'photo_add',before:null,after:{photoId:photo.id}});
    tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'problem_photo_add',targetId:ref.id,after:{buildingId:d.buildingId,roomId:cur.roomId}});
    tx.create(op,{organizationId:d.organizationId,actorId:uid,createdAt:now,fingerprint,result:out});
    return out;
   }).catch(async e=>{await session.trash(file.id).catch(()=>{});throw e;});
   if(lost)await session.trash(file.id).catch(()=>{});
   return result;
  }
  // removePhoto: off the problem first, then into the Drive trash (never deleted for good).
  const photo=list.find(x=>x.id===d.photoId);
  if(!photo)fail('not-found','problem_photo_missing');
  if(!(canManage||(photo.addedBy===uid&&p.status==='open')))fail('permission-denied','problem_access_denied');
  const result=await db.runTransaction(async tx=>{
   const again=await tx.get(op);if(again.exists)return again.data().result;
   const cur=(await tx.get(ref)).data();
   tx.update(ref,{photos:(cur?.photos??[]).filter(x=>x.id!==d.photoId),updatedAt:now,updatedBy:uid});
   const out={problemId:ref.id,photoId:d.photoId,trashed:false};
   tx.create(ref.collection('problemHistory').doc(key),{organizationId:d.organizationId,actorId:uid,actorName:name,createdAt:now,action:'photo_remove',before:{photoId:d.photoId},after:null});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'problem_photo_remove',targetId:ref.id,after:{buildingId:d.buildingId,roomId:cur?.roomId??null}});
   tx.create(op,{organizationId:d.organizationId,actorId:uid,createdAt:now,fingerprint,result:out});
   return out;
  });
  // A disconnected or failing Drive keeps the file; the photo is already gone from the app.
  try{const session=await drives.open(d.organizationId);await session.trash(d.photoId);return {...result,trashed:true};}catch{return result;}
 }
}

/** True when a room may not take a new booking, lease or move in. */
const roomBlocked=room=>Array.isArray(room?.openProblemBlocks)&&room.openProblemBlocks.length>0;

module.exports={createTechnicalProblemsHandler,invalidProblemInput,roomBlocked};
