'use strict';
// Reads what a lease's payment schedule needs inside a transaction (all reads,
// no writes): room history, the lease's live period invoices, people now.
const {buildSchedule}=require('./lease_schedule');
const {leasePeople}=require('./period_invoice');
const {propertyDate}=require('./lease_dates');
const {nextDate}=require('./invoice_math');

async function leaseIntervals({tx,db,t,tenantId,organizationId,buildingId,zone}){
 const history=await tx.get(db.collection('leaseOccupancy').where('tenantId','==',tenantId));
 const intervals=history.docs.filter(v=>v.data().organizationId===organizationId&&v.data().buildingId===buildingId).map(v=>({roomId:v.data().roomId,startDate:propertyDate(v.data().start.toMillis(),zone),endDate:propertyDate(v.data().end.toMillis(),zone)}));
 if(t.buildingId===buildingId)intervals.push({roomId:t.roomId,startDate:propertyDate((t.occupancyStartDate??t.moveInDate).toMillis(),zone),endDate:t.moveOutDate?propertyDate(t.moveOutDate.toMillis(),zone):null});
 return intervals;
}

/** Live period invoices with rent, as the schedule sees them. */
const scheduleInvoices=(docs,tenantId)=>docs.map(v=>({id:v.id,x:v.data()})).filter(({x})=>x.status!=='cancelled'&&(x.tenantId??null)===tenantId&&x.invoiceKind==='period'&&x.calculation?.includeRent===true)
 .map(({id,x})=>({id,scheduleRowId:typeof x.scheduleRowId==='string'?x.scheduleRowId:null,startDate:x.billingStartLocalDate,endDate:x.billingEndLocalDate,totalMinor:x.totalMinor??x.amountMinor??0,paidMinor:Math.round((x.paidAmount??0)*(x.currency==='USD'?100:1))}));

async function loadSchedule({tx,db,tenant,organizationId,buildingId,zone,today,invoiceDocs}){
 const t=tenant.data();
 const intervals=await leaseIntervals({tx,db,t,tenantId:tenant.id,organizationId,buildingId,zone});
 const docs=invoiceDocs??(await tx.get(db.collection('payments').where('organizationId','==',organizationId).where('buildingId','==',buildingId).where('tenantId','==',tenant.id))).docs;
 // People today (per-person phụ thu); the invoice counts each kỳ exactly.
 const room=t.buildingId===buildingId?t.roomId:intervals.at(-1)?.roomId;
 const people=room&&(t.surcharges??[]).some(s=>s?.basis==='person')?await leasePeople({tx,db,organizationId,buildingId,roomId:room,tenantId:tenant.id,startDate:today,endDate:nextDate(today),zone}):1;
 return {...buildSchedule({t,zone,stored:t.paymentSchedule,invoices:scheduleInvoices(docs,tenant.id),people,intervals}),intervals,people};
}
module.exports={loadSchedule,leaseIntervals,scheduleInvoices};
