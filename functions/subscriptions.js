const crypto=require('node:crypto');
function createSubscriptions({db,Timestamp,HttpsError,getKey,getWebhookSecret,fetcher=fetch}) {
 async function syncUser(uid) {
  if(typeof uid!=='string'||!/^[A-Za-z0-9_-]{1,128}$/.test(uid))throw new HttpsError('invalid-argument','ai_invalid_request');
  const started=Timestamp.now();
  const response=await fetcher('https://api.revenuecat.com/v1/subscribers/'+encodeURIComponent(uid),{headers:{Authorization:'Bearer '+getKey()},signal:AbortSignal.timeout(20000)});
  if(!response.ok)throw new HttpsError('unavailable','ai_billing_unavailable');
  const body=await response.json(),subscriber=body.subscriber||{},entitlement=subscriber.entitlements?.ai_pro;
  const subscription=entitlement?subscriber.subscriptions?.[entitlement.product_identifier]:null;
  const expires=Date.parse(entitlement?.expires_date||''),start=Date.parse(entitlement?.purchase_date||'');
  const sandbox=subscription?.is_sandbox===true;
  const active=!!entitlement&&!!subscription&&typeof subscription.is_sandbox==='boolean'&&Number.isFinite(expires)&&expires>Date.now()&&Number.isFinite(start)&&(!sandbox||process.env.ALLOW_SANDBOX_BILLING==='true');
  const ref=db.doc('aiEntitlements/'+uid);
  await db.runTransaction(async tx=>{const old=await tx.get(ref);if(old.exists&&old.data().checkedAt?.toMillis()>started.toMillis())return;tx.set(ref,{ownerId:uid,verified:true,status:active?'active':'inactive',expiresAt:Timestamp.fromMillis(Number.isFinite(expires)?expires:0),periodStart:Timestamp.fromMillis(Number.isFinite(start)?start:0),checkedAt:started,provider:'revenuecat',sandbox});});
  return {active};
 }
 async function sync(request){if(!request.auth)throw new HttpsError('unauthenticated','ai_sign_in');return syncUser(request.auth.uid);}
 async function webhook(req,res){
  const expected=Buffer.from(getWebhookSecret()||''),actual=Buffer.from(req.get('authorization')||'');
  if(req.method!=='POST'||!expected.length||expected.length!==actual.length||!crypto.timingSafeEqual(expected,actual)){res.status(401).send('Unauthorized');return;}
  const event=req.body?.event;if(!event){res.status(400).send('Invalid event');return;}
  if(event.type==='TEST'){res.status(200).send('OK');return;}
  // Refresh authoritative subscriber state, including both sides of transfers.
  // Never grant access from client claims or from an out-of-order webhook payload.
  const users=new Set([event.app_user_id,...(event.transferred_from||[]),...(event.transferred_to||[])].filter(v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v)));
  if(users.size>20){res.status(400).send('Invalid event');return;}
  try{for(const user of users)await syncUser(user);res.status(200).send('OK');}catch(_){res.status(503).send('Retry');}
 }
 return {sync,webhook,syncUser};
}
module.exports={createSubscriptions};
