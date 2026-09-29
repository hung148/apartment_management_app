'use strict';
const {createHash}=require('node:crypto');
const {roles}=require('./team_access');
const knownRole=role=>Object.hasOwn(roles,role);

// Server-clock token buckets. Fixed document IDs bound storage growth per account;
// neither request timestamps nor operation IDs select/reset a bucket.
const policies=Object.freeze({
 general:{capacity:120,perMinute:120,orgCapacity:1200,orgPerMinute:1200},
 lookup:{capacity:12,perMinute:6,orgCapacity:120,orgPerMinute:60},
 costly:{capacity:4,perMinute:2,orgCapacity:20,orgPerMinute:10},
});
function category(name,data){
 if(['aiChat','aiImportPreview','aiImportCommit','aiSyncSubscription'].includes(name))return 'costly';
 if(name==='lookupTeamInvitation'||(name==='mutateTeam'&&['invite','requestAccess','acceptInvitation'].includes(data?.action)))return 'lookup';
 return 'general';
}
function createRequestGuard({db,Timestamp,HttpsError,now=Date.now}){
 const fail=(code,message)=>{throw new HttpsError(code,message);};
 const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
 const consume=async(uid,group,orgId)=>db.runTransaction(async tx=>{
  const policy=policies[group],time=now();
  const buckets=[{key:['user',uid,group],capacity:policy.capacity,rate:policy.perMinute}];
  if(orgId){
   const member=await tx.get(db.doc(`memberships/${uid}_${orgId}`));
   const m=member.data();
   // An outsider cannot exhaust another organization's shared budget by naming it.
   if(m?.ownerId===uid&&m.organizationId===orgId&&m.status==='active'&&m.accessVersion===2&&knownRole(m.role))
    buckets.push({key:['organization',orgId,group],capacity:policy.orgCapacity,rate:policy.orgPerMinute});
  }
  const records=await Promise.all(buckets.map(b=>tx.get(db.doc(`requestLimits/${hash(b.key)}`))));
  const updates=buckets.map((b,i)=>{
   const old=records[i].data();
   const tokens=old&&Number.isFinite(old.tokens)&&Number.isFinite(old.updatedAtMs)
    ?Math.min(b.capacity,old.tokens+Math.max(0,time-old.updatedAtMs)*b.rate/60000):b.capacity;
   if(tokens<1)fail('resource-exhausted','request_rate_limited');
   return {tokens:tokens-1,updatedAtMs:Math.max(time,old?.updatedAtMs??0),expiresAt:Timestamp.fromMillis(time+86400000)};
  });
  buckets.forEach((b,i)=>tx.set(records[i].ref,updates[i]));
 });
 return async(name,request)=>{
  const uid=request.auth?.uid;
  if(typeof uid!=='string'||!uid||uid.length>128||uid.includes('/'))fail('unauthenticated','sign_in_required');
  if(!request.app?.appId)fail('unauthenticated','app_check_required');
  // Charge every authenticated attempt, including invalid/forbidden input.
  await consume(uid,'general');
  let encoded;
  try{encoded=JSON.stringify(request.data??null);}catch{fail('invalid-argument','invalid_request');}
  // Existing import validation permits a 5 MiB file encoded as base64.
  const limit=name==='aiImportPreview'?8*1024*1024:128*1024;
  if(Buffer.byteLength(encoded,'utf8')>limit)fail('invalid-argument','request_too_large');
  let org=request.data?.organizationId??request.data?.orgId;
  if(['mutateCalendarBooking','mutateCalendarTenant'].includes(name)){
   const booking=name==='mutateCalendarBooking',key=booking?request.data?.bookingId:request.data?.tenantId;
   const saved=typeof key==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(key)
    ?(await db.doc(`${booking?'bookings':'tenants'}/${key}`).get()).data():null;
   org=saved?.organizationId??(booking?(request.data?.booking??request.data?.changes)?.organizationId:request.data?.tenant?.organizationId);
  }
  const orgId=typeof org==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(org)?org:null;
  const group=category(name,request.data);
  if(group!=='general')await consume(uid,group,orgId);
  else if(orgId){
   // Shared organizational budget uses a separate group key, avoiding a second
   // debit to the user's general bucket.
   await db.runTransaction(async tx=>{
    const m=(await tx.get(db.doc(`memberships/${uid}_${orgId}`))).data();
    if(!m||m.ownerId!==uid||m.organizationId!==orgId||m.accessVersion!==2||m.status!=='active'||!knownRole(m.role))return;
    const ref=db.doc(`requestLimits/${hash(['organization',orgId,'general'])}`),old=(await tx.get(ref)).data(),time=now(),p=policies.general;
    const tokens=old?Math.min(p.orgCapacity,old.tokens+Math.max(0,time-old.updatedAtMs)*p.orgPerMinute/60000):p.orgCapacity;
    if(tokens<1)fail('resource-exhausted','request_rate_limited');
    tx.set(ref,{tokens:tokens-1,updatedAtMs:Math.max(time,old?.updatedAtMs??0),expiresAt:Timestamp.fromMillis(time+86400000)});
   });
  }
 };
}
function createSecureCallable({onCall,...dependencies}){
 const guard=createRequestGuard(dependencies);
 return (name,options,handler)=>{
  if(typeof options==='function'){handler=options;options={};}
  return onCall({...options,enforceAppCheck:true},async request=>{
   await guard(name,request);
   return handler(request);
  });
 };
}
module.exports={createRequestGuard,createSecureCallable,policies};
