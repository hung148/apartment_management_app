'use strict';
const {createHash}=require('node:crypto');
const {allows,hasRole}=require('./team_access');
const {normalizeRates,fetchReferenceRates}=require('./reference_rates');
const organizationCurrency=org=>org.displayCurrency??'VND';
function createOrganizationCurrencyHandler({db,Timestamp,HttpsError,fetchRates=fetchReferenceRates}){
 const fail=code=>{throw new HttpsError(code,'currency_'+code);};
 let fetching,fetchedSnapshot,fetchedAt=0;
 const check=async(tx,uid,orgId)=>{
  const [org,memberDoc]=await Promise.all([tx.get(db.doc(`organizations/${orgId}`)),tx.get(db.doc(`memberships/${uid}_${orgId}`))]);
  const member=memberDoc.data();
  if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||org.data().mergedInto||!member||member.accessVersion!==2||member.status!=='active'||member.ownerId!==uid||member.organizationId!==orgId||!hasRole(member)||!['all','selected'].includes(member.buildingScope))fail('permission-denied');
 };
 return async request=>{
  const uid=request.auth?.uid,d=request.data??{},write=d.action==='updateCurrency';
  const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
  if(!uid)fail('unauthenticated');
  if(d.action==='readRates'){
   if(!id(d.organizationId)||Object.keys(d).some(k=>!['action','organizationId'].includes(k)))fail('invalid-argument');
   const latestRef=db.doc('referenceExchangeRateCache/latest');
   const cached=await db.runTransaction(async tx=>{
    await check(tx,uid,d.organizationId);
    return (await tx.get(latestRef)).data();
   });
   if(cached?.snapshot&&Number.isFinite(cached.fetchedAtMs)&&Date.now()-cached.fetchedAtMs>=0&&Date.now()-cached.fetchedAtMs<6*60*60*1000)return cached.snapshot;
   let snapshot;
   try{
    if(fetchedSnapshot&&Date.now()-fetchedAt>=0&&Date.now()-fetchedAt<6*60*60*1000){
     snapshot=fetchedSnapshot;
    }else{
     fetching??=Promise.resolve().then(fetchRates).then(normalizeRates).then(value=>{
      fetchedSnapshot=value;fetchedAt=Date.now();return value;
     }).finally(()=>{fetching=null;});
     snapshot=await fetching;
    }
   }catch(_){fail('unavailable');}
   return db.runTransaction(async tx=>{
    // A role may have been revoked while the provider was responding.
    await check(tx,uid,d.organizationId);
    const ref=db.doc(`referenceExchangeRates/${snapshot.id}`),old=await tx.get(ref);
    if(!old.exists)tx.create(ref,snapshot);
    tx.set(latestRef,{snapshot,fetchedAtMs:Date.now()});
    return snapshot;
   });
  }
  const keys=['action','organizationId',...(write?['operationId','revision','currency']:[])];
  if(!['readCurrency','updateCurrency'].includes(d.action)||!id(d.organizationId)||Object.keys(d).some(k=>!keys.includes(k))||
    (write&&(!id(d.operationId)||!Number.isSafeInteger(d.revision)||d.revision<0||!['VND','USD'].includes(d.currency))))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const orgRef=db.doc(`organizations/${d.organizationId}`),org=await tx.get(orgRef);
   const member=(await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`))).data();
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||org.data().mergedInto||!member||member.accessVersion!==2||member.status!=='active'||member.ownerId!==uid||member.organizationId!==d.organizationId||!hasRole(member)||!['all','selected'].includes(member.buildingScope))fail('permission-denied');
   const canChange=allows(member,'changeOrganizationCurrency',{organizationId:d.organizationId,userId:uid});
   const currency=organizationCurrency(org.data()),revision=org.data().currencyRevision??0;
   if(!write)return {currency,revision,canChange};
   if(!canChange)fail('permission-denied');
   const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
   const key=hash(['currency',uid,d.organizationId,d.operationId]),op=db.doc(`organizationOperations/${key}`),prior=await tx.get(op);
   const fingerprint=hash([d.revision,d.currency]);
   if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('already-exists');return prior.data().result;}
   if(revision!==d.revision)fail('aborted');
   const now=Timestamp.now(),result={currency:d.currency,revision:revision+1,canChange:true};
   tx.update(orgRef,{displayCurrency:d.currency,currencyRevision:revision+1,updatedAt:now,updatedBy:uid});
   tx.create(op,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'organization_currency_updated',targetId:d.organizationId,createdAt:now,before:{currency},after:{currency:d.currency}});
   return result;
  });
 };
}
module.exports={createOrganizationCurrencyHandler,organizationCurrency};
