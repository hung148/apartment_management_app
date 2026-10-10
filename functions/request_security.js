'use strict';
const {createHash}=require('node:crypto');
const {sessionCheck}=require('./account_sessions');
const {hasRole}=require('./team_access');
const {accountPolicy,checkEmployer}=require('./account_policy');

// Server-clock token buckets. Fixed document IDs bound storage growth per account;
// neither request timestamps nor operation IDs select/reset a bucket.
const policies=Object.freeze({
 general:{capacity:120,perMinute:120,orgCapacity:1200,orgPerMinute:1200},
 lookup:{capacity:12,perMinute:6,orgCapacity:120,orgPerMinute:60},
 costly:{capacity:4,perMinute:2,orgCapacity:20,orgPerMinute:10},
});
// Organization/account checks remembered per server copy (2026-10-10, Tom).
const POLICY_CACHE_MS=15_000,POLICY_CACHE_MAX=5000;
// The general limit counted in memory (2026-10-10, Tom: fewer writes). Saved
// to Firestore at most every 10 s per bucket, re-read every 60 s.
const LOCAL_SAVE_MS=10_000,LOCAL_RELOAD_MS=60_000,LOCAL_MAX=20000;
function category(name,data){
 if(['importSheet','mergeMyOrganizations'].includes(name)||(name==='organizationSettings'&&['create','createLegacy'].includes(data?.action)))return 'costly';
 if(name==='lookupTeamInvitation'||name==='claimMyInvitations'||(name==='mutateTeam'&&['invite','requestAccess','acceptInvitation'].includes(data?.action)))return 'lookup';
 return 'general';
}
// Local emulator only (tool/local.ps1): App Check has no emulator, so it is not
// required there. Both conditions are needed: the Functions emulator sets
// FUNCTIONS_EMULATOR, and local runs use a demo- project that has no cloud resources.
const localEmulator=()=>process.env.FUNCTIONS_EMULATOR==='true'&&/^demo-/.test(process.env.GCLOUD_PROJECT??'');
// Speed (2026-10-09): one account's calls take turns at the rate-limit write on
// this server copy. A screen starts 4-5 calls at once; their transactions all
// read then write the same account (and organization) bucket documents, so
// Firestore aborted all but one and the client library retried them after a
// back-off of about a second (seen as 1-2.4 s calls). Taking turns here costs
// one short transaction each instead. The limits are unchanged and still kept
// in Firestore; other server copies are not affected by this.
function createKeyedTurns(){
 const tails=new Map();
 return async(keys,run)=>{
  const releases=[];
  // Always in the same (sorted) order, so two calls never wait on each other.
  for(const key of [...new Set(keys)].sort()){
   const previous=tails.get(key)??Promise.resolve();
   let release;const done=new Promise(resolve=>release=resolve);
   const tail=previous.then(()=>done);
   tails.set(key,tail);
   releases.push(()=>{release();if(tails.get(key)===tail)tails.delete(key);});
   await previous;
  }
  try{return await run();}finally{for(const release of releases.reverse())release();}
 };
}
function createRequestGuard({db,Timestamp,HttpsError,now=Date.now,policyCacheMs=POLICY_CACHE_MS}){
 const turns=createKeyedTurns();
 const fail=(code,message)=>{throw new HttpsError(code,message);};
 const hash=value=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
 // One transaction charges every waiting call of an account (2026-10-10,
 // speed): a screen starts 4-5 calls at once, and they used to take turns,
 // one transaction each (seen as answers arriving 0.3 s apart). Now the calls
 // that arrive while a charge is being written wait for the next one together.
 // Same buckets, same limits, same rule per call: a call is all-or-nothing
 // (refused = nothing taken for it), and calls are charged in arrival order.
 // The organization's shared bucket still takes turns across accounts.
 const chargeBatch=(uid,items)=>{
  const orgIds=[...new Set(items.map(i=>i.orgId).filter(Boolean))];
  return turns(['user:'+uid,...orgIds.map(o=>'organization:'+o)],()=>db.runTransaction(async tx=>{
   const time=now();
   const plans=items.map(({userGroups,orgId,orgGroup})=>({
    orgId,
    buckets:userGroups.map(g=>({key:['user',uid,g],capacity:policies[g].capacity,rate:policies[g].perMinute})),
    candidate:orgId?{key:['organization',orgId,orgGroup],capacity:policies[orgGroup].orgCapacity,rate:policies[orgGroup].orgPerMinute}:null,
   }));
   const ids=[...new Set(plans.flatMap(p=>[...p.buckets,...(p.candidate?[p.candidate]:[])].map(b=>hash(b.key))))];
   // Membership and bucket reads start together, in the same transaction.
   const [members,records]=await Promise.all([
    Promise.all(orgIds.map(o=>tx.get(db.doc(`memberships/${uid}_${o}`)))),
    Promise.all(ids.map(id=>tx.get(db.doc(`requestLimits/${id}`)))),
   ]);
   const memberOf=new Map(orgIds.map((o,i)=>[o,members[i].data()]));
   const state=new Map(ids.map((id,i)=>[id,{ref:records[i].ref,old:records[i].data(),tokens:null,updatedAtMs:0,touched:false}]));
   const tokensOf=(id,b)=>{
    const s=state.get(id);
    if(s.tokens===null){
     const old=s.old;
     s.tokens=old&&Number.isFinite(old.tokens)&&Number.isFinite(old.updatedAtMs)
      ?Math.min(b.capacity,old.tokens+Math.max(0,time-old.updatedAtMs)*b.rate/60000):b.capacity;
     s.updatedAtMs=Math.max(time,old?.updatedAtMs??0);
    }
    return s.tokens;
   };
   const refusedCalls=plans.map(p=>{
    const buckets=[...p.buckets];
    if(p.orgId){
     const m=memberOf.get(p.orgId);
     // An outsider cannot exhaust another organization's shared budget by naming it.
     if(m?.ownerId===uid&&m.organizationId===p.orgId&&m.status==='active'&&m.accessVersion===2&&hasRole(m))
      buckets.push(p.candidate);
    }
    const bucketIds=buckets.map(b=>hash(b.key));
    if(bucketIds.some((id,i)=>tokensOf(id,buckets[i])<1))return true;
    for(const id of bucketIds){const s=state.get(id);s.tokens-=1;s.touched=true;}
    return false;
   });
   for(const s of state.values())if(s.touched)
    tx.set(s.ref,{tokens:s.tokens,updatedAtMs:s.updatedAtMs,expiresAt:Timestamp.fromMillis(time+86400000)});
   return refusedCalls;
  }));
 };
 const queues=new Map();
 const drain=async(uid,queue)=>{
  try{
   while(queue.length){
    const batch=queue.splice(0,50);
    let refusedCalls;
    try{refusedCalls=await chargeBatch(uid,batch);}
    catch(error){for(const c of batch)c.reject(error);continue;}
    batch.forEach((c,i)=>refusedCalls[i]?c.reject(new HttpsError('resource-exhausted','request_rate_limited')):c.resolve());
   }
  }finally{queues.delete(uid);}
 };
 const consume=(uid,userGroups,orgId=null,orgGroup='general')=>new Promise((resolve,reject)=>{
  let queue=queues.get(uid);
  const start=!queue;
  if(start){queue=[];queues.set(uid,queue);}
  queue.push({userGroups,orgId,orgGroup,resolve,reject});
  if(start)drain(uid,queue);
 });
 // The general limit (120 a minute per account, 1200 per organization) is an
 // anti-spam limit, counted in memory on this server copy (2026-10-10, Tom):
 // each call used to write 1-2 Firestore documents (free plan: 20,000 writes
 // a day) and wait for them. Now a bucket is read when first used (again after
 // 60 s), counted here, and saved at most every 10 s, so other server copies
 // and restarts still see it. With several copies running, one account can
 // briefly get a little more than the limit; the strict limits (invitation
 // lookups, costly actions) are still counted in Firestore on every call.
 const local=new Map();
 const loadLocal=b=>{
  const id=hash(b.key),t=now(),seen=local.get(id);
  if(seen&&(seen.loading||seen.dirty||t-seen.loadedAt<LOCAL_RELOAD_MS))return seen.loading??Promise.resolve(seen);
  const entry={b,ref:db.doc(`requestLimits/${id}`),tokens:b.capacity,updatedAtMs:t,loadedAt:t,savedAt:t,dirty:false,exists:false,loading:null};
  entry.loading=entry.ref.get().then(d=>{
   const old=d.data();
   if(old&&Number.isFinite(old.tokens)&&Number.isFinite(old.updatedAtMs)){entry.tokens=old.tokens;entry.updatedAtMs=old.updatedAtMs;entry.exists=true;}
   entry.loading=null;
   return entry;
  },e=>{if(local.get(id)===entry)local.delete(id);throw e;});
  if(local.size>=LOCAL_MAX)local.clear();
  local.set(id,entry);
  return entry.loading;
 };
 const consumeLocal=async(uid,orgId,member)=>{
  const buckets=[{key:['user',uid,'general'],capacity:policies.general.capacity,rate:policies.general.perMinute}];
  if(orgId){
   const m=(await member)?.data();
   // An outsider cannot exhaust another organization's shared budget by naming it.
   if(m?.ownerId===uid&&m.organizationId===orgId&&m.status==='active'&&m.accessVersion===2&&hasRole(m))
    buckets.push({key:['organization',orgId,'general'],capacity:policies.general.orgCapacity,rate:policies.general.orgPerMinute});
  }
  const states=await Promise.all(buckets.map(loadLocal));
  // From here to the end nothing waits, so two calls cannot take the same token.
  const t=now();
  for(const s of states){
   s.tokens=Math.min(s.b.capacity,s.tokens+Math.max(0,t-s.updatedAtMs)*s.b.rate/60000);
   s.updatedAtMs=Math.max(t,s.updatedAtMs);
  }
  if(states.some(s=>s.tokens<1))fail('resource-exhausted','request_rate_limited');
  const saves=[];
  for(const s of states){
   s.tokens-=1;s.dirty=true;
   if(!s.exists||t-s.savedAt>=LOCAL_SAVE_MS){
    s.savedAt=t;s.dirty=false;s.exists=true;
    saves.push(s.ref.set({tokens:s.tokens,updatedAtMs:s.updatedAtMs,expiresAt:Timestamp.fromMillis(t+86400000)}).catch(()=>{s.dirty=true;}));
   }
  }
  // A save happens at most every 10 s per bucket; waiting for it keeps it from
  // being cut off when the server copy pauses between calls.
  await Promise.all(saves);
 };
 // Organization, membership and account checks remembered for 15 s on this
 // server copy (2026-10-10, Tom). Concurrent calls share one read. Only the
 // checks below use them; every call's own work still reads the caller's
 // membership itself, so a removed staff member is refused at once. What can
 // lag up to 15 s: organization merged, owner conflict, account deletion,
 // another employer. A write on this server copy clears its organization and
 // caller (forget). Failed reads are never kept.
 const cache=new Map();
 const remembered=(key,load)=>{
  if(!(policyCacheMs>0))return load();
  const hit=cache.get(key);
  if(hit&&(hit.pending||now()-hit.at<policyCacheMs))return hit.value;
  const entry={value:null,at:0,pending:true};
  entry.value=Promise.resolve().then(load).then(v=>{entry.pending=false;entry.at=now();return v;},e=>{if(cache.get(key)===entry)cache.delete(key);throw e;});
  if(cache.size>=POLICY_CACHE_MAX)cache.clear();
  cache.set(key,entry);
  return entry.value;
 };
 const guard=async(name,request)=>{
  const uid=request.auth?.uid;
  if(typeof uid!=='string'||!uid||uid.length>128||uid.includes('/'))fail('unauthenticated','sign_in_required');
  if(!request.app?.appId&&!localEmulator())fail('unauthenticated','app_check_required');
  // Charge every authenticated attempt, including invalid/forbidden input.
  let encoded;
  try{encoded=JSON.stringify(request.data??null);}catch{await consumeLocal(uid,null);fail('invalid-argument','invalid_request');}
  // B7b problem photos: one photo of at most 2 MiB, base64 encoded.
  // Sheet import (2026-10-05): the old app's rows (a few MB at most), or the new .xlsx for Drive.
  const limit=name==='importSheet'?8*1024*1024:name==='technicalProblems'&&request.data?.action==='addPhoto'?3*1024*1024:128*1024;
  if(Buffer.byteLength(encoded,'utf8')>limit){await consumeLocal(uid,null);fail('invalid-argument','request_too_large');}
  let org=request.data?.organizationId??request.data?.orgId;
  if(['mutateCalendarBooking','mutateCalendarTenant'].includes(name)){
   const booking=name==='mutateCalendarBooking',key=booking?request.data?.bookingId:request.data?.tenantId;
   const saved=typeof key==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(key)
    ?(await db.doc(`${booking?'bookings':'tenants'}/${key}`).get()).data():null;
   org=saved?.organizationId??(booking?(request.data?.booking??request.data?.changes)?.organizationId:request.data?.tenant?.organizationId);
  }
  const orgId=typeof org==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(org)?org:null;
  const group=category(name,request.data);
  // "Sign out everywhere" (2026-10-06): a sign-in made before the account's
  // cut-off is refused. Read alongside the charge below (no added wait).
  const revokedCheck=sessionCheck.revoked(db,uid,Number(request.auth.token?.auth_time),now());
  // Speed (2026-10-10): the organization checks' reads also start alongside
  // the charge; they are only looked at after the charge and the cut-off
  // passed, in the same order as before, so the answers are the same.
  const member=orgId?remembered(`member|${uid}|${orgId}`,()=>db.doc(`memberships/${uid}_${orgId}`).get()):null;
  member?.catch(()=>{});
  const checks=orgId?Promise.all([
   remembered(`org|${orgId}`,()=>db.doc(`organizations/${orgId}`).get()),
   member,
   // Read-only: takes no locks (it only reads), same consistent snapshot.
   remembered(`policy|${uid}`,()=>db.runTransaction(tx=>accountPolicy(db,tx,uid),{readOnly:true})),
   remembered(`members|${orgId}`,()=>db.collection('memberships').where('organizationId','==',orgId).get()),
  ]):null;
  checks?.catch(()=>{});
  // Charge before policy checks so forbidden/conflicted attempts are limited too.
  try{
   // The general limit in memory; a strict limit (and its general charge)
   // in one Firestore transaction, as before.
   if(group==='general')await consumeLocal(uid,orgId,member);
   else await consume(uid,['general',group],orgId,group);
  }catch(error){
   revokedCheck.catch(()=>{});
   if(error?.code==='resource-exhausted'&&group!=='general')await consumeLocal(uid,null).catch(()=>{});
   throw error;
  }
  if(await revokedCheck)fail('unauthenticated','session_revoked');
  // Binding is identity, membership remains authorization. Recovery actions
  // can resolve historical conflicts; operational reads/writes fail closed.
  if(orgId){
   const [organizationDoc,memberDoc,policy,coOwners]=await checks;
   const organization=organizationDoc.data();
   if(organization?.mergedInto)fail('failed-precondition','org_organization_merged');
   const m=memberDoc.data();
   if(m?.ownerId===uid&&m.organizationId===orgId){
    const recovery=name==='organizationSettings'&&['read','close','leave','closedList'].includes(request.data?.action)||name==='mutateTeam'&&request.data?.action==='setAccess'&&request.data?.status==='revoked';
    if(policy.deleting)fail('failed-precondition','account_deletion_in_progress');
    const historicalCoOwner=coOwners.docs.some(d=>d.data().role==='coOwner'&&d.data().status!=='revoked');
    const activeOwners=coOwners.docs.filter(d=>d.data().role==='owner'&&d.data().status==='active');
    const currentOwner=organization?.ownerTransferredTo??organization?.createdBy;
    const ownershipConflict=activeOwners.length>1||(organization?.accessVersion===2&&currentOwner&&(activeOwners.length!==1||activeOwners[0].data().ownerId!==currentOwner));
    if(!recovery&&(historicalCoOwner||ownershipConflict||policy.mode==='conflict'||policy.organizationIds.some(id=>id!==orgId)||m.role==='coOwner'||m.employerShareId))fail('permission-denied','org_single_organization_review');
    if(!recovery&&m.role!=='owner'&&m.accessVersion===2&&m.status==='active'){
     if(policy.hasOwned)fail('failed-precondition','team_owner_account');
     const email=request.auth.token?.email??m.email;
     // Only a passed check is remembered; a refusal is checked again each time.
     await remembered(`employer|${uid}|${email}|${orgId}`,()=>db.runTransaction(tx=>checkEmployer(db,tx,{uid,email,orgId},fail)));
    }
   }
  }
 };
 // A write on this server copy may change what is remembered: forget the
 // caller and the organization the call named.
 guard.forget=(uid,orgId)=>{
  for(const key of [...cache.keys()]){
   const parts=key.split('|');
   if((uid&&parts.includes(uid))||(orgId&&parts.includes(orgId)))cache.delete(key);
  }
 };
 return guard;
}
function createSecureCallable({onCall,...dependencies}){
 const guard=createRequestGuard(dependencies);
 const {REGION}=require('./region');
 return (name,options,handler)=>{
  if(typeof options==='function'){handler=options;options={};}
  return onCall({region:REGION,...options,enforceAppCheck:!localEmulator()},async request=>{
   await guard(name,request);
   try{return await handler(request);}finally{guard.forget(request.auth?.uid,organizationOf(request.data));}
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
const isRead=(entry,inner)=>{
 try{return entry.readOnly===true||(typeof entry.readOnly==='function'&&entry.readOnly(inner.data)===true);}catch{return false;}
};
const organizationOf=data=>{
 const org=data?.organizationId??data?.orgId;
 return typeof org==='string'?org:null;
};
function createCallableGroups({onCall,observe,...dependencies}){
 const guard=createRequestGuard(dependencies);
 const {REGION}=require('./region');
 const handlers=new Map();
 const register=(name,options,handler)=>{
  if(typeof options==='function'){handler=options;options={};}
  if(!NAME.test(name)||handlers.has(name))throw Error('Bad or repeated call name: '+name);
  const readOnly=options.readOnly??false;
  if(readOnly!==false&&readOnly!==true&&typeof readOnly!=='function')throw Error('Bad readOnly for '+name);
  handlers.set(name,{group:options.group??'app',handler,readOnly});
 };
 // Speed (2026-10-09): a call that only READS starts its work alongside the
 // guard, and its answer is held until the guard has passed: the guard's
 // refusal (rate limit, session cut-off, account policy) is still what the app
 // gets, and nothing is returned before it passes. Writes still wait for the
 // guard. An account this server copy refused for the rate limit in the last
 // minute waits for the guard again, so refused calls do not keep reading.
 const refused=new Map(),REFUSED_MS=60_000;
 const startsEarly=(entry,inner)=>{
  const uid=inner.auth?.uid;
  if(!uid||!entry)return false;
  const until=refused.get(uid);
  if(until!==undefined){if(until>Date.now())return false;refused.delete(uid);}
  return isRead(entry,inner);
 };
 const noteRefusal=(uid,error)=>{
  if(uid&&error?.code==='resource-exhausted'){
   if(refused.size>10_000)refused.clear();
   refused.set(uid,Date.now()+REFUSED_MS);
  }
 };
 const group=(groupName,options={})=>onCall({region:REGION,...options,enforceAppCheck:!localEmulator()},async request=>{
  const outer=request.data,fn=outer&&typeof outer==='object'?outer.fn:undefined;
  const entry=typeof fn==='string'&&NAME.test(fn)?handlers.get(fn):undefined;
  // Only {fn, data}: anything else around the data would skip the size limit.
  const known=entry?.group===groupName&&Object.keys(outer).every(k=>k==='fn'||k==='data');
  const inner={...request,data:known?outer.data??null:null};
  const run=async()=>{
   if(!known)throw new dependencies.HttpsError('not-found','unknown_call');
   try{return await entry.handler(inner);}
   finally{if(!isRead(entry,inner))guard.forget(inner.auth?.uid,organizationOf(inner.data));}
  };
  const early=known&&startsEarly(entry,inner);
  const guarded=async()=>{
   try{await guard(known?fn:'unknownCall',inner);}
   catch(error){noteRefusal(inner.auth?.uid,error);throw error;}
  };
  if(observe)return require('./request_timing').timeRequest({
   name:known?fn:'unknownCall',guard:guarded,handler:run,observe,early,
  });
  if(early){
   const pending=run();
   pending.catch(()=>{});
   await guarded();
   return pending;
  }
  await guarded();
  return run();
 });
 const names=groupName=>[...handlers].filter(([,e])=>e.group===groupName).map(([n])=>n);
 return {register,group,names};
}
module.exports={createKeyedTurns,createRequestGuard,createSecureCallable,createCallableGroups,policies,localEmulator};
