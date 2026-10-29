'use strict';
// READ-ONLY. Lists the Hóa đơn kỳ on STAGING that match no kỳ of their lease's
// payment table (PAYMENT_SCHEDULE.md, 2026-10-26). Tom decided these old
// invoices are removed — staging first — but only after he has seen this list.
// Changes nothing. Run from the repo root:
//   node tool/staging_schedule_unmatched.cjs *> logs/unmatched.txt
const path=require('node:path'),base='../functions/node_modules/firebase-tools/lib/';
const project='apartment-management-staging';
const dep=require('node:module').createRequire(path.resolve('functions/package.json'));
const {buildSchedule}=require('../functions/lease_schedule');
const {scheduleInvoices}=require('../functions/lease_schedule_io');
const {propertyDate}=require('../functions/lease_dates');

async function main(){
 await require(base+'requireAuth').requireAuth({project,...require(base+'auth').getGlobalDefaultAccount()});
 const access=await require(base+'apiv2').getAccessToken();
 const {Firestore}=dep('@google-cloud/firestore');
 const gaxRequire=require('node:module').createRequire(dep.resolve('google-gax',{paths:[path.dirname(dep.resolve('@google-cloud/firestore'))]}));
 const {OAuth2Client}=gaxRequire('google-auth-library');
 const authClient=new OAuth2Client();authClient.setCredentials({access_token:access,expiry_date:Date.now()+50*60000});
 const db=new Firestore({projectId:project,authClient});
 if(db.projectId!==project&&db._settings?.projectId!==project)throw Error('Wrong project');
 const periodInvoices=(await db.collection('payments').where('invoiceKind','==','period').get()).docs;
 const byTenant=new Map();
 for(const v of periodInvoices){const x=v.data();if(!x.tenantId)continue;if(!byTenant.has(x.tenantId))byTenant.set(x.tenantId,[]);byTenant.get(x.tenantId).push(v);}
 const names=new Map(),zones=new Map();
 const orgName=async id=>{if(!names.has(id)){const o=await db.doc('organizations/'+id).get();names.set(id,o.exists?o.data().name??id:id);}return names.get(id);};
 const zoneOf=async id=>{if(!zones.has(id)){const b=await db.doc('buildings/'+id).get();zones.set(id,b.exists?{zone:b.data().timeZone,name:b.data().name??id}:null);}return zones.get(id);};
 let count=0,leases=0;
 for(const [tenantId,docs] of byTenant){
  const tenant=await db.doc('tenants/'+tenantId).get();
  const live=docs.filter(v=>v.data().status!=='cancelled'&&v.data().calculation?.includeRent===true);
  if(!live.length)continue;
  const x0=live[0].data(),b=await zoneOf(x0.buildingId);
  let unmatched,why='';
  if(!tenant.exists){unmatched=live.map(v=>v.id);why=' (lease no longer exists)';}
  else if(!b?.zone){unmatched=live.map(v=>v.id);why=' (building has no time zone)';}
  else{
   const t=tenant.data(),start=t.moveInLocalDate??(t.moveInDate?propertyDate(t.moveInDate.toMillis(),b.zone):null);
   const s=buildSchedule({t,zone:b.zone,stored:t.paymentSchedule,invoices:scheduleInvoices(live,tenantId),people:1,intervals:[{roomId:t.roomId,startDate:start,endDate:null}]});
   if(s.needsEnd){unmatched=live.filter(v=>!v.data().scheduleRowId).map(v=>v.id);why=' (lease has no contract end date: no kỳ)';}
   else unmatched=s.unmatched??[];
  }
  if(!unmatched.length)continue;
  leases++;
  console.log(`\n${await orgName(x0.organizationId)} · ${b?.name??x0.buildingId} · ${tenant.exists?tenant.data().fullName:tenantId}${why}`);
  for(const id of unmatched){
   const x=live.find(v=>v.id===id).data(),paid=Math.round((x.paidAmount??0)*(x.currency==='USD'?100:1));
   console.log(`  ${id}  ${x.billingStartLocalDate} .. ${x.billingEndLocalDate} (last day excluded)  total ${x.totalMinor??x.amountMinor} ${x.currency}  paid ${paid}  status ${x.status}`);
   count++;
  }
 }
 console.log(`\n${count} invoice(s) in ${leases} lease(s) match no kỳ. Nothing was changed.`);
}
main().then(()=>process.exit(0),e=>{console.error(e.message||e);process.exit(1);});
