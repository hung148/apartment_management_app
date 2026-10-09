'use strict';
const {createHash}=require('node:crypto');
const {hasRole}=require('./team_access');
const {accountPolicy,checkEmployer}=require('./account_policy');

// Server-clock token buckets. Fixed document IDs bound storage growth per account;
// neither request timestamps nor operation IDs select/reset a bucket.
const policies=Object.freeze({
 general:{capacity:120,perMinute:120,orgCapacity:1200,orgPerMinute:1200},
 lookup:{capacity:12,perMinute:6,orgCapacity:120,orgPerMinute:60},
 costly:{capacity:4,perMinute:2,orgCapacity:20,orgPerMinute:10},
});
function category(name,data){
 if(['aiChat','aiImportPreview','aiImportCommit','aiSyncSubscription','importSheet','mergeMyOrganizations'].includes(name)||(name==='organizationSettings'&&['create','createLegacy'].includes(data?.action)))return 'costly';
 if(name==='lookupTeamInvitation'||name==='claimMyInvitations'||(name==='mutateTeam'&&['invite','requestAccess','acceptInvitation'].includes(data?.action)))return 'lookup';
 return 'general';
}
// Local emulator only (tool/local.ps1): App Check has no emulator, so it is not
// required there. Both conditions are needed: the Functions emulator sets
// FUNCTIONS_EMULATOR, and local runs use a demo- project that has no cloud resources.
const localEmulator=()=>process.env.FUNCTIONS_EMULATOR==='true'&&/^demo-/.test(process.env.GCLOUD_PROJECT??'');
function createRequestGuard({db,Timestamp,HttpsError,now=Date.now}){
 const fail=(code,message)=>{throw new HttpsError(code,message);};
 const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
 // One transaction per request (2026-10-01; was two): the user's buckets plus,
 // for an identity-matched active member, the organization's shared bucket.
 // All-or-nothing inside; the caller charges a refused attempt separately.
 const consume=async(uid,userGroups,orgId=null,orgGroup='general')=>db.runTransaction(async tx=>{
  const time=now();
  const buckets=userGroups.map(g=>({key:['user',uid,g],capacity:policies[g].capacity,rate:policies[g].perMinute}));
  if(orgId){
   const member=await tx.get(db.doc(`memberships/${uid}_${orgId}`));
   const m=member.data();
   // An outsider cannot exhaust another organization's shared budget by naming it.
   if(m?.ownerId===uid&&m.organizationId===orgId&&m.status==='active'&&m.accessVersion===2&&hasRole(m))
    buckets.push({key:['organization',orgId,orgGroup],capacity:policies[orgGroup].orgCapacity,rate:policies[orgGroup].orgPerMinute});
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
  if(!request.app?.appId&&!localEmulator())fail('unauthenticated','app_check_required');
  // Charge every authenticated attempt, including invalid/forbidden input.
  let encoded;
  try{encoded=JSON.stringify(request.data??null);}catch{await consume(uid,['general']);fail('invalid-argument','invalid_request');}
  // Existing import validation permits a 5 MiB file encoded as base64.
  // B7b problem photos: one photo of at most 2 MiB, base64 encoded.
  // Sheet import (2026-10-05): the old app's rows (a few MB at most), or the new .xlsx for Drive.
  const limit=name==='aiImportPreview'||name==='importSheet'?8*1024*1024:name==='technicalProblems'&&request.data?.action==='addPhoto'?3*1024*1024:128*1024;
  if(Buffer.byteLength(encoded,'utf8')>limit){await consume(uid,['general']);fail('invalid-argument','request_too_large');}
  let org=request.data?.organizationId??request.data?.orgId;
  if(['mutateCalendarBooking','mutateCalendarTenant'].includes(name)){
   const booking=name==='mutateCalendarBooking',key=booking?request.data?.bookingId:request.data?.tenantId;
   const saved=typeof key==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(key)
    ?(await db.doc(`${booking?'bookings':'tenants'}/${key}`).get()).data():null;
   org=saved?.organizationId??(booking?(request.data?.booking??request.data?.changes)?.organizationId:request.data?.tenant?.organizationId);
  }
  const orgId=typeof org==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(org)?org:null;
  const group=category(name,request.data);
  // Charge before policy scans so forbidden/conflicted attempts are limited too.
  try{
   await consume(uid,group==='general'?['general']:['general',group],orgId,group);
  }catch(error){
   if(error?.code==='resource-exhausted'&&(group!=='general'||orgId))await consume(uid,['general']).catch(()=>{});
   throw error;
  }
  // Binding is identity, membership remains authorization. Recovery actions
  // can resolve historical conflicts; operational reads/writes fail closed.
  if(orgId){
   const [organizationDoc,memberDoc]=await Promise.all([
    db.doc(`organizations/${orgId}`).get(),
    db.doc(`memberships/${uid}_${orgId}`).get(),
   ]);
   const organization=organizationDoc.data();
   if(organization?.mergedInto)fail('failed-precondition','org_organization_merged');
   const m=memberDoc.data();
   if(m?.ownerId===uid&&m.organizationId===orgId){
    const recovery=name==='organizationSettings'&&['read','close','leave','closedList'].includes(request.data?.action)||name==='mutateTeam'&&request.data?.action==='setAccess'&&request.data?.status==='revoked';
    const [policy,coOwners]=await Promise.all([
     db.runTransaction(tx=>accountPolicy(db,tx,uid)),
     db.collection('memberships').where('organizationId','==',orgId).get(),
    ]);
    if(policy.deleting)fail('failed-precondition','account_deletion_in_progress');
    const historicalCoOwner=coOwners.docs.some(d=>d.data().role==='coOwner'&&d.data().status!=='revoked');
    const activeOwners=coOwners.docs.filter(d=>d.data().role==='owner'&&d.data().status==='active');
    const currentOwner=organization?.ownerTransferredTo??organization?.createdBy;
    const ownershipConflict=activeOwners.length>1||(organization?.accessVersion===2&&currentOwner&&(activeOwners.length!==1||activeOwners[0].data().ownerId!==currentOwner));
    if(!recovery&&(historicalCoOwner||ownershipConflict||policy.mode==='conflict'||policy.organizationIds.some(id=>id!==orgId)||m.role==='coOwner'||m.employerShareId))fail('permission-denied','org_single_organization_review');
    if(!recovery&&m.role!=='owner'&&m.accessVersion===2&&m.status==='active'){
     if(policy.hasOwned)fail('failed-precondition','team_owner_account');
     await db.runTransaction(tx=>checkEmployer(db,tx,{uid,email:request.auth.token?.email??m.email,orgId},fail));
    }
   }
  }
 };
}
function createSecureCallable({onCall,...dependencies}){
 const guard=createRequestGuard(dependencies);
 const {REGION}=require('./region');
 return (name,options,handler)=>{
  if(typeof options==='function'){handler=options;options={};}
  return onCall({region:REGION,...options,enforceAppCheck:!localEmulator()},async request=>{
   await guard(name,request);
   return handler(request);
  });
 };
}
// Function groups (2026-10-06, speed step 4). Instead of one deployed function
// per call (43), calls are registered by name and served by a few grouped
// functions: fewer copies to start, so they stay warm without paying for
// always-running copies, and a full CPU fits in the region's CPU limit.
// The app sends {fn:<call name>, data:<the call's data>} to its group. Every
// call still goes through the same guard under its own name (App Check, sign-in,
// size and rate limits), and only reaches the handler registered for it in that
// group. An unknown name is charged like any request, then refused.
const NAME=/^[A-Za-z][A-Za-z0-9]{0,63}$/;
function createCallableGroups({onCall,observe,...dependencies}){
 const guard=createRequestGuard(dependencies);
 const {REGION}=require('./region');
 const handlers=new Map();
 const register=(name,options,handler)=>{
  if(typeof options==='function'){handler=options;options={};}
  if(!NAME.test(name)||handlers.has(name))throw Error('Bad or repeated call name: '+name);
  handlers.set(name,{group:options.group??'app',handler});
 };
 const group=(groupName,options={})=>onCall({region:REGION,...options,enforceAppCheck:!localEmulator()},async request=>{
  const outer=request.data,fn=outer&&typeof outer==='object'?outer.fn:undefined;
  const entry=typeof fn==='string'&&NAME.test(fn)?handlers.get(fn):undefined;
  // Only {fn, data}: anything else around the data would skip the size limit.
  const known=entry?.group===groupName&&Object.keys(outer).every(k=>k==='fn'||k==='data');
  const inner={...request,data:known?outer.data??null:null};
  const run=async()=>{
   if(!known)throw new dependencies.HttpsError('not-found','unknown_call');
   return entry.handler(inner);
  };
  if(observe)return require('./request_timing').timeRequest({
   name:known?fn:'unknownCall',guard:()=>guard(known?fn:'unknownCall',inner),handler:run,observe,
  });
  await guard(known?fn:'unknownCall',inner);
  return run();
 });
 const names=groupName=>[...handlers].filter(([,e])=>e.group===groupName).map(([n])=>n);
 return {register,group,names};
}
module.exports={createRequestGuard,createSecureCallable,createCallableGroups,policies,localEmulator};
