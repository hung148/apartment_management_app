'use strict';
// Staff names and choices without reading the whole staff list each time
// (2026-10-11, Tom: 100+ staff).
// - staffNames: only the profiles a list shows (by ID).
// - staffChoices: the active staff for a "Nhân viên phụ trách" picker,
//   remembered for 30 s on this server copy per organization. A change made
//   through this server copy forgets it at once (request_security.js); a
//   change through another copy shows within 30 s. Saving still checks the
//   chosen person on the server, so a stale choice can never be saved.
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const CHOICES_MS=30_000,MAX_ORGS=500;
const caches=new Set();
const cacheFor=new WeakMap();
function cacheOf(db){
 let c=cacheFor.get(db);
 if(!c){c=new Map();cacheFor.set(db,c);caches.add(new WeakRef(c));}
 return c;
}
/** Names of these staff profiles (others' or missing ones: ''), read by ID. */
async function staffNames(get,db,organizationId,ids){
 const list=[...new Set([...ids].filter(id))];
 const docs=await Promise.all(list.map(v=>get(db.doc(`staffProfiles/${v}`))));
 return new Map(list.map((v,i)=>{const x=docs[i].data();return [v,x?.organizationId===organizationId?String(x.displayName??''):''];}));
}
/** Active staff, sorted by name: [{id, displayName}]. */
async function staffChoices(get,db,organizationId,now=Date.now()){
 const cache=cacheOf(db),hit=cache.get(organizationId);
 if(hit&&now-hit.at<CHOICES_MS)return hit.list;
 const docs=(await get(db.collection('staffProfiles').where('organizationId','==',organizationId))).docs;
 const list=docs.filter(v=>v.data().employmentStatus!=='inactive').map(v=>({id:v.id,displayName:String(v.data().displayName??'')})).sort((a,b)=>a.displayName.localeCompare(b.displayName)||a.id.localeCompare(b.id));
 if(cache.size>=MAX_ORGS)cache.clear();
 cache.set(organizationId,{at:now,list});
 return list;
}
/** A change on this server copy: forget the organization's remembered staff. */
function forgetStaff(organizationId){
 for(const ref of caches){const c=ref.deref();if(!c){caches.delete(ref);continue;}if(organizationId)c.delete(organizationId);else c.clear();}
}
module.exports={staffNames,staffChoices,forgetStaff};
