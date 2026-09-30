'use strict';
// Shared by organization copy and purge: finds every document that belongs to
// one organization. Old legacy children can lack organizationId, so they are
// also found through their parent. A child owned by another organization is
// a data problem: the caller's onCrossLink decides (copy aborts, purge skips).
const LINKED=Object.freeze([
 ['rooms','tenants','roomId'],['rooms','bookings','roomId'],
 ['rooms','payments','roomId'],['tenants','payments','tenantId'],
]);
const PAGE=300;

async function forEachMatch(db,collection,field,value,visit){
 let cursor=null;
 for(;;){
  let q=db.collection(collection).where(field,'==',value).orderBy('__name__').limit(PAGE);
  if(cursor)q=q.startAfter(cursor);
  const page=await q.get();
  for(const doc of page.docs)await visit(doc);
  if(page.size<PAGE)return;
  cursor=page.docs[page.docs.length-1];
 }
}

/** Returns Map(collection -> Map(docId -> snapshot)). */
async function collectOrganization(db,orgId,collections,{fields=['organizationId'],onCrossLink}){
 const found=new Map(collections.map(c=>[c,new Map()]));
 for(const c of collections)for(const f of fields)await forEachMatch(db,c,f,orgId,doc=>{found.get(c).set(doc.id,doc);});
 for(const [parent,child,field] of LINKED){
  if(!found.has(parent)||!found.has(child))continue;
  const ids=[...found.get(parent).keys()];
  for(let i=0;i<ids.length;i+=30){
   const page=await db.collection(child).where(field,'in',ids.slice(i,i+30)).get();
   for(const doc of page.docs){
    const owner=doc.data().organizationId;
    if(owner!=null&&owner!==orgId){onCrossLink(doc);continue;}
    found.get(child).set(doc.id,doc);
   }
  }
 }
 return found;
}
module.exports={collectOrganization,forEachMatch,LINKED};
