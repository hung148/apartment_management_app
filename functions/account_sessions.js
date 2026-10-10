'use strict';
// "Sign out everywhere" (2026-10-06, Tom). Ends every sign-in of the account:
// Firebase stops refreshing them (revokeRefreshTokens), and the request guard
// refuses any sign-in made before that moment straight away (sessionCheck),
// instead of waiting up to an hour for the current ID token to expire.
// accountSessions/{uid} is server-only (no rule allows clients).

/** The callable: revoke this account's sign-ins and record from when. */
function createSessionsHandler({db,getAuth,HttpsError}){
 return async request=>{
  const uid=request.auth?.uid;
  if(typeof uid!=='string'||!uid)throw new HttpsError('unauthenticated','sign_in_required');
  if(request.data?.action!=='signOutEverywhere')throw new HttpsError('invalid-argument','invalid_request');
  const auth=getAuth();
  await auth.revokeRefreshTokens(uid);
  // Firebase's own cut-off (whole seconds): sign-ins at or after it stay valid.
  const user=await auth.getUser(uid);
  const validAfterSec=Math.floor(new Date(user.tokensValidAfterTime).getTime()/1000);
  if(!Number.isFinite(validAfterSec))throw new HttpsError('internal','session_revoke_failed');
  await db.doc(`accountSessions/${uid}`).set({validAfterSec});
  sessionCheck.remember(uid,validAfterSec);
  return {status:'signedOutEverywhere'};
 };
}

// Per server copy: the cut-off of each account, re-read at most every 30 s (so
// another server copy refuses old sign-ins within 30 s). Concurrent requests of
// one account share one read. Bounded so it cannot grow without limit.
const TTL_MS=30000,MAX=5000;
const known=new Map();
const sessionCheck={
 remember(uid,validAfterSec){known.set(uid,{validAfterSec,readAt:Date.now(),pending:null});},
 async validAfterSec(db,uid,now=Date.now()){
  const hit=known.get(uid);
  if(hit?.pending)return hit.pending;
  if(hit&&now-hit.readAt<TTL_MS)return hit.validAfterSec;
  const pending=db.doc(`accountSessions/${uid}`).get().then(d=>{
   const v=d.data()?.validAfterSec;
   const value=Number.isFinite(v)?v:null;
   if(known.size>=MAX)known.delete(known.keys().next().value);
   known.set(uid,{validAfterSec:value,readAt:now,pending:null});
   return value;
  },e=>{known.delete(uid);throw e;});
  known.set(uid,{validAfterSec:hit?.validAfterSec??null,readAt:hit?.readAt??0,pending});
  return pending;
 },
 /** True when this sign-in was made before the account's cut-off. */
 async revoked(db,uid,authTimeSec,now){
  const cutoff=await sessionCheck.validAfterSec(db,uid,now);
  if(cutoff===null)return false;
  return !Number.isFinite(authTimeSec)||authTimeSec<cutoff;
 },
 clearForTests(){known.clear();},
};
module.exports={createSessionsHandler,sessionCheck};
