'use strict';
const {collectOrganization}=require('./org_data');

// Permanently removes organizations whose close retention period has ended.
// Runs from a daily schedule; each run handles a bounded number and the next
// run continues, so an interrupted purge is simply retried.
const KEEP=Object.freeze(['organizations','owners','purgedOrganizations']);

function createOrganizationPurge({db,Timestamp,logger,now=()=>Date.now(),maxOrganizations=5}){
 async function purgeOne(org){
  const id=org.id,data=org.data();
  // Only closed organizations past their date, with nobody left inside. Legacy
  // organizations are closed only by account deletion.
  if(!data.closedAt||!data.purgeAfter||data.purgeAfter.toMillis()>now())return {id,status:'skipped',reason:'not_due'};
  const active=await db.collection('memberships').where('organizationId','==',id).where('status','==','active').limit(1).get();
  if(active.size)return {id,status:'skipped',reason:'active_membership'};
  // Claim the organization atomically; a restore that has started wins.
  const claimed=await db.runTransaction(async tx=>{
   const cur=await tx.get(org.ref),x=cur.exists?cur.data():null;
   if(!x||!x.closedAt||x.restoringAt||!x.purgeAfter||x.purgeAfter.toMillis()>now())return false;
   tx.update(org.ref,{purgeStartedAt:Timestamp.fromMillis(now())});return true;
  });
  if(!claimed)return {id,status:'skipped',reason:'restoring_or_reopened'};
  const collections=(await db.listCollections()).map(c=>c.id).filter(c=>!KEEP.includes(c));
  let crossLinked=null;
  const found=await collectOrganization(db,id,collections,{fields:['organizationId','orgId'],onCrossLink:doc=>{crossLinked=doc.ref.path;}});
  if(crossLinked)return {id,status:'skipped',reason:'cross_link',path:crossLinked};
  const counts={},writer=db.bulkWriter();
  for(const [collection,docs] of found){
   if(!docs.size)continue;
   counts[collection]=docs.size;
   // recursiveDelete also removes history subcollections under each record.
   for(const doc of docs.values())await db.recursiveDelete(doc.ref,writer);
  }
  await db.recursiveDelete(org.ref,writer);
  await writer.close();
  // A minimal record that the purge happened; no names or contact details.
  await db.collection('purgedOrganizations').doc(id).set({closedBy:data.closedBy??null,closedAt:data.closedAt,
   purgeAfter:data.purgeAfter,purgedAt:Timestamp.fromMillis(now()),counts});
  return {id,status:'purged',counts};
 }
 return async()=>{
  const due=await db.collection('organizations').where('purgeAfter','<=',Timestamp.fromMillis(now())).orderBy('purgeAfter').limit(maxOrganizations).get();
  const results=[];
  for(const org of due.docs){
   try{results.push(await purgeOne(org));}
   catch(error){results.push({id:org.id,status:'failed'});logger.error('Organization purge failed',{organizationId:org.id,code:error?.code??null});}
  }
  for(const r of results)if(r.status!=='purged')logger.warn('Organization purge skipped',r);
  logger.info('Organization purge run',{due:due.size,purged:results.filter(r=>r.status==='purged').length});
  return results;
 };
}
module.exports={createOrganizationPurge};
