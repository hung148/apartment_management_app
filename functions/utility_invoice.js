'use strict';
const {createHash}=require('node:crypto');
const meterId=(organizationId,roomId,kind)=>createHash('sha256').update(JSON.stringify([organizationId,roomId,kind])).digest('hex');
async function utilityInvoiceSource({tx,db,organizationId,buildingId,roomId,kind,readingId,startDate,endDate,currency,intervals}){
 const ref=db.doc(`utilityMeters/${meterId(organizationId,roomId,kind)}/readings/${readingId}`);
 const snapshot=await tx.get(ref),reading=snapshot.data();
 if(!reading||reading.organizationId!==organizationId||reading.buildingId!==buildingId||reading.roomId!==roomId||reading.kind!==kind)throw Error('utility_reading_not_found');
 if(reading.reversedAt)throw Error('utility_reading_reversed');
 if(reading.invoiceId)throw Error('utility_already_billed');
 if(!reading.calculation||reading.calculation.currency!==currency||reading.calculation.amountMinor<=0)throw Error('utility_no_billable_charge');
 if(reading.startDate!==startDate||reading.date!==endDate)throw Error('utility_invoice_dates');
 // Only a continuous occupancy in the same room may receive the full interval.
 // Split-tenant allocations require separate readings at the handover boundary.
 if(!intervals.some(x=>x.roomId===roomId&&x.startDate<=startDate&&(!x.endDate||x.endDate>=endDate)))throw Error('utility_tenant_boundary_required');
 return {ref,reading,calculation:{...reading.calculation,startDate,endDate,chargeType:kind,roomId,readingId,tariff:reading.tariff}};
}
module.exports={utilityInvoiceSource,meterId};
