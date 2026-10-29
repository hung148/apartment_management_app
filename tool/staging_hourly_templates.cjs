'use strict';
// STAGING. Turns rooms' flat hourly prices into building hourly templates
// (PRICE_DEFAULTS.md, Tom 2026-10-26): each different price → one template
// with the same price every hour. Rooms' old hourlyPrice is left in place
// (older app versions still read it); the new app no longer shows or uses it.
// Shows the plan and changes NOTHING unless --apply is given. From the repo root:
//   node tool/staging_hourly_templates.cjs *> logs/hourly_plan.txt
//   node tool/staging_hourly_templates.cjs --apply *> logs/hourly_apply.txt
const path=require('node:path'),base='../functions/node_modules/firebase-tools/lib/';
const project='apartment-management-staging';
const dep=require('node:module').createRequire(path.resolve('functions/package.json'));
const {planHourlyTemplates}=require('../functions/hourly_migration');
const apply=process.argv.includes('--apply');

async function main(){
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const access=await require(base+'apiv2').getAccessToken();
 const {Firestore}=dep('@google-cloud/firestore');
 const gaxRequire=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
 const {OAuth2Client}=gaxRequire('google-auth-library');
 const authClient=new OAuth2Client();authClient.setCredentials({access_token:access,expiry_date:Date.now()+50*60000});
 const db=new Firestore({projectId:project,authClient});
 const orgs=new Map();
 const v2=async id=>{if(!orgs.has(id)){const o=await db.doc('organizations/'+id).get();orgs.set(id,o.exists&&o.data().accessVersion===2?o.data().name??id:null);}return orgs.get(id);};
 let total=0;
 for(const b of (await db.collection('buildings').get()).docs){
  const x=b.data(),org=await v2(x.organizationId);if(!org)continue;
  const rooms=(await db.collection('rooms').where('organizationId','==',x.organizationId).where('buildingId','==',b.id).get()).docs.map(v=>v.data());
  const ref=db.doc('buildingHourTemplates/'+b.id),snap=await ref.get();
  const existing=snap.exists&&snap.data().organizationId===x.organizationId?snap.data().templates??[]:[];
  const plan=planHourlyTemplates({buildingCurrency:x.currency,rooms,existing});
  if(!plan.add.length&&!plan.skipped.length&&!plan.otherCurrencyRooms)continue;
  console.log(`\n${org} · ${x.name??b.id}`);
  for(const t of plan.add)console.log(`  + ${t.name}`);
  for(const t of plan.skipped)console.log(`  ! not added (20 templates max): ${t.name}`);
  if(plan.otherCurrencyRooms)console.log(`  ! ${plan.otherCurrencyRooms} room(s) in another currency: not converted`);
  total+=plan.add.length;
  if(apply&&plan.add.length){
   await db.runTransaction(async tx=>{
    const now=await tx.get(ref),cur=now.exists?now.data().templates??[]:[];
    const again=planHourlyTemplates({buildingCurrency:x.currency,rooms,existing:cur});
    tx.set(ref,{organizationId:x.organizationId,buildingId:b.id,templates:[...cur,...again.add]});
   });
   console.log('  applied');
  }
 }
 console.log(`\n${total} template(s) ${apply?'added':'would be added (run again with --apply)'}.`);
}
main().then(()=>process.exit(0),e=>{console.error(e.message||e);process.exit(1);});
