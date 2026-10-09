'use strict';
// B6 period invoices (PERIOD_INVOICES.md): one invoice per lease payment
// period = rent and service fees for the period (paid ahead) + meter
// readings not billed yet (usage paid behind) + manual lines (late fee,
// discount, damage, other). Every charge is priced by the server and linked so
// it is never billed twice; void releases the links.
const {proratedRent}=require('./invoice_math');
const {rentForDate}=require('./tenant_rent');
const {readReferenceRates,convertCalculation,convertMinor}=require('./reference_rates');
const {validDate}=require('./property_contract');
const {utilityInvoiceSource,meterId}=require('./utility_invoice');
const {serviceInvoiceSource,roomPeople}=require('./service_fee_invoice');
const {monthsBetween}=require('./service_fee_math');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const MAX=1e12;
const LINE_KINDS=['late','discount','damage','other'];

function addMonths(date,months){
 const [y,m,d]=date.split('-').map(Number);
 const target=new Date(Date.UTC(y,m-1+months,1)),last=new Date(Date.UTC(target.getUTCFullYear(),target.getUTCMonth()+1,0)).getUTCDate();
 return new Date(Date.UTC(target.getUTCFullYear(),target.getUTCMonth(),Math.min(d,last))).toISOString().slice(0,10);
}

/** Throws 'invalid-argument' style messages; returns the normalized extras. */
function validatePeriodInput(d){
 if(typeof d.includeRent!=='boolean')throw Error('period_invalid');
 if(!Array.isArray(d.serviceFeeIds)||d.serviceFeeIds.length>30||d.serviceFeeIds.some(v=>!id(v))||new Set(d.serviceFeeIds).size!==d.serviceFeeIds.length)throw Error('period_invalid');
 if(!Array.isArray(d.readings)||d.readings.length>24)throw Error('period_invalid');
 const seen=new Set();
 for(const r of d.readings){
  if(!r||typeof r!=='object'||Object.keys(r).some(k=>!['roomId','kind','readingId'].includes(k))||!id(r.roomId)||!['electricity','water'].includes(r.kind)||!id(r.readingId))throw Error('period_invalid');
  const key=`${r.roomId}/${r.kind}/${r.readingId}`;if(seen.has(key))throw Error('period_invalid');seen.add(key);
 }
 if(!Array.isArray(d.lines)||d.lines.length>20)throw Error('period_invalid');
 for(const l of d.lines){
  if(!l||typeof l!=='object'||Object.keys(l).some(k=>!['kind','label','amountMinor','percent'].includes(k))||!LINE_KINDS.includes(l.kind)||typeof l.label!=='string'||!l.label.trim()||l.label.length>80)throw Error('period_invalid_line');
  if(l.kind==='discount'&&l.percent!==undefined){
   if(l.amountMinor!==undefined||!Number.isSafeInteger(l.percent)||l.percent<1||l.percent>100)throw Error('period_invalid_line');
  }else{
   if(l.percent!==undefined||!Number.isSafeInteger(l.amountMinor)||l.amountMinor===0||Math.abs(l.amountMinor)>MAX)throw Error('period_invalid_line');
   // Late fees and damages add; discounts subtract; "other" may be either.
   if(['late','damage'].includes(l.kind)&&l.amountMinor<0)throw Error('period_invalid_line');
   if(l.kind==='discount'&&l.amountMinor<0)throw Error('period_invalid_line');
  }
 }
 // 2026-10-04: the lease's surcharges for this period; the amount may differ from the lease's.
 if(d.surcharges!==undefined){
  if(!Array.isArray(d.surcharges)||d.surcharges.length>20)throw Error('period_invalid');
  const ids=new Set();
  for(const x of d.surcharges){
   if(!x||typeof x!=='object'||Object.keys(x).some(k=>!['id','amountMinor'].includes(k))||!id(x.id)||ids.has(x.id)||!Number.isSafeInteger(x.amountMinor)||x.amountMinor<=0||x.amountMinor>MAX)throw Error('period_invalid_line');
   ids.add(x.id);
  }
 }
 if(!d.includeRent&&!d.serviceFeeIds.length&&!d.readings.length&&!d.lines.length&&!d.surcharges?.length)throw Error('period_empty');
}

/** The lease's rent for [startDate, endDate), when the lease covers it all
 * and the rent does not change inside it: its own period price for one whole
 * lease period, otherwise the monthly rent × months (1 Oct–1 Nov = 1 month,
 * 2 Oct–2 Nov = 1 month, partial months by days of that month). With a rent
 * change or a lease boundary inside, day by day like rent invoices. */
function periodRent({tenant,startDate,endDate,intervals,timeZone}){
 const months=tenant.paymentPeriodMonths??1,whole=addMonths(startDate,months)===endDate;
 const changes=(tenant.rentSchedule??[]).filter(c=>c.effectiveDate>startDate&&c.effectiveDate<endDate);
 const base=rentForDate(tenant,startDate),lease=intervals.find(i=>i.startDate<=startDate&&(i.endDate==null||i.endDate>=endDate));
 if(lease&&!changes.length&&Number.isSafeInteger(base)&&base>0){
  if(whole&&!(tenant.rentSchedule??[]).some(c=>c.effectiveDate<endDate)&&Number.isSafeInteger(tenant.periodRentMinor)&&tenant.periodRentMinor>0&&base===tenant.monthlyRentMinor){
   return {amountMinor:tenant.periodRentMinor,months,basis:'period',startDate,endDate};
  }
  const [n,d]=monthsBetween(startDate,endDate),amountMinor=Number((BigInt(base)*n*2n+d)/(2n*d));
  if(amountMinor>0&&Number.isSafeInteger(amountMinor))return {amountMinor,monthsFraction:[Number(n),Number(d)],basis:'months',startDate,endDate};
 }
 const prorated=proratedRent({tenant,startDate,endDate,intervals,timeZone});
 return {amountMinor:prorated.amountMinor,days:prorated.days,lines:prorated.lines,basis:'days',startDate,endDate};
}

/**
 * Prices a period invoice inside the invoice transaction. All reads; the
 * caller writes links (readings, billed markers) after its own reads.
 */
/** People of the lease in its room at any time in [startDate, endDate): at least 1. */
async function leasePeople({tx,db,organizationId,buildingId,roomId,tenantId,startDate,endDate,zone}){
 const people=await roomPeople({tx,db,organizationId,buildingId,roomId,tenantId,zone});
 return Math.max(1,people.filter(p=>p.intervals.some(i=>i.startDate<endDate&&(i.endDate==null||i.endDate>startDate))).length);
}

/** Has another live invoice of this lease already billed this surcharge? */
function surchargeBilled(x,{tenantId,surchargeId,frequency,startDate,endDate}){
 if(x.status==='cancelled'||(x.tenantId??null)!==tenantId||!['period','settlement'].includes(x.invoiceKind))return false;
 if(!(x.calculation?.lines??[]).some(l=>l.type==='surcharge'&&l.surchargeId===surchargeId))return false;
 return frequency==='once'||(x.billingStartLocalDate<endDate&&x.billingEndLocalDate>startDate);
}

async function periodInvoiceSource({tx,db,d,tenant,intervals,roomId,currency,zone}){
 const lines=[];let rent=null;
 const sourceCurrency=tenant.currency??'VND';
 const snapshot=sourceCurrency===currency?null:await readReferenceRates(tx,db,d.ratesId);
 if(d.includeRent){
  try{rent=periodRent({tenant,startDate:d.startDate,endDate:d.endDate,intervals,timeZone:zone});}catch(e){throw Error(e.message==='invoice_empty_or_invalid_total'?'period_no_rent_days':e.message);}
  if(snapshot)rent=convertCalculation({...rent,currency:sourceCurrency},currency,snapshot);
  lines.push({type:'rent',amountMinor:rent.amountMinor,startDate:d.startDate,endDate:d.endDate,basis:rent.basis,...(rent.sourceCalculation?{sourceCalculation:rent.sourceCalculation,exchangeRateSnapshotId:rent.exchangeRateSnapshotId}:{}),...(rent.basis==='period'?{months:rent.months}:rent.basis==='months'?{monthsFraction:rent.monthsFraction}:{days:rent.days})});
 }
 const serviceSources=[];
 for(const feeId of d.serviceFeeIds){
  const source=await serviceInvoiceSource({tx,db,organizationId:d.organizationId,buildingId:d.buildingId,roomId,feeId,tenantId:d.tenantId,startDate:d.startDate,endDate:d.endDate,quantityMilli:null,ratesId:d.ratesId,currency,zone});
  if(source.fee.basis==='quantity')throw Error('period_quantity_fee');
  serviceSources.push(source);
  lines.push({type:'service',feeId,feeName:source.fee.name,amountMinor:source.calculation.amountMinor,people:source.calculation.lines,terms:source.calculation.terms,periodDays:source.calculation.periodDays,...(source.calculation.sourceCalculation?{sourceCalculation:source.calculation.sourceCalculation,exchangeRateSnapshotId:source.calculation.exchangeRateSnapshotId}:{})});
 }
 const utilitySources=[];
 for(const r of d.readings){
  // Usage is billed behind: any unbilled reading of a room this lease lived in
  // for the whole measured interval.
  const ref=db.doc(`utilityMeters/${meterId(d.organizationId,r.roomId,r.kind)}/readings/${r.readingId}`),snap=await tx.get(ref),reading=snap.data();
  if(!reading)throw Error('utility_reading_not_found');
  const source=await utilityInvoiceSource({tx,db,organizationId:d.organizationId,buildingId:d.buildingId,roomId:r.roomId,kind:r.kind,readingId:r.readingId,startDate:reading.startDate,endDate:reading.date,ratesId:d.ratesId,currency,intervals});
  utilitySources.push(source);
  lines.push({type:'utility',kind:r.kind,roomId:r.roomId,readingId:r.readingId,startDate:reading.startDate,endDate:reading.date,usageMilli:source.calculation.usageMilli,amountMinor:source.calculation.amountMinor,...(source.calculation.sourceCalculation?{sourceCalculation:source.calculation.sourceCalculation,exchangeRateSnapshotId:source.calculation.exchangeRateSnapshotId}:{})});
 }
 let surchargeChanged=false;
 if(d.surcharges?.length){
  const count=await leasePeople({tx,db,organizationId:d.organizationId,buildingId:d.buildingId,roomId,tenantId:d.tenantId,startDate:d.startDate,endDate:d.endDate,zone});
  for(const x of d.surcharges){
   const def=(Array.isArray(tenant.surcharges)?tenant.surcharges:[]).find(s=>s&&s.id===x.id);
   if(!def)throw Error('period_surcharge_unknown');
   const expected=snapshot?convertMinor(def.amountMinor,sourceCurrency,currency,snapshot):def.amountMinor;
   if(x.amountMinor!==expected)surchargeChanged=true;
   const n=def.basis==='person'?count:1;
   // Per month (water): the months of this invoice, part months by days.
   let amountMinor=x.amountMinor*n,months=null;
   if(def.frequency==='month'){const [mn,md]=monthsBetween(d.startDate,d.endDate);months=[Number(mn),Number(md)];amountMinor=Number((BigInt(x.amountMinor*n)*mn*2n+md)/(2n*md));}
   if(!Number.isSafeInteger(amountMinor)||amountMinor<=0)throw Error('period_invalid');
   lines.push({type:'surcharge',surchargeId:def.id,label:def.label,basis:def.basis,frequency:def.frequency,...(def.kind?{kind:def.kind}:{}),unitMinor:x.amountMinor,count:n,...(months?{monthsFraction:months}:{}),amountMinor,
    ...(snapshot?{sourceTerms:{currency:sourceCurrency,unitMinor:def.amountMinor},exchangeRateSnapshotId:snapshot.id}:{})});
  }
 }
 for(const l of d.lines){
  let amountMinor=l.kind==='discount'?-(l.amountMinor??0):l.amountMinor;
  if(l.percent!==undefined){
   if(!rent)throw Error('period_discount_needs_rent');
   amountMinor=-Math.round(rent.amountMinor*l.percent/100);
  }
  lines.push({type:'manual',kind:l.kind,label:l.label.trim(),amountMinor,...(l.percent!==undefined?{percent:l.percent}:{})});
 }
 const amountMinor=lines.reduce((n,l)=>n+l.amountMinor,0);
 if(!Number.isSafeInteger(amountMinor)||amountMinor>MAX)throw Error('period_total_too_large');
 if(amountMinor<=0)throw Error('period_total_not_positive');
 return {utilitySources,serviceSources,surchargeChanged,calculation:{chargeType:'period',amountMinor,currency,startDate:d.startDate,endDate:d.endDate,timeZone:zone,roomId,includeRent:d.includeRent,lines,
  ...(d.surcharges?.length?{surcharges:d.surcharges.map(x=>x.id)}:{}),
  services:serviceSources.map(s=>({feeId:s.fee.id,roomId})),utilities:d.readings.map(r=>({roomId:r.roomId,kind:r.kind,readingId:r.readingId}))}};
}

/** Does an existing invoice already bill what this one would? */
function periodConflict(x,{kind,tenantId,roomId,startDate,endDate,includeRent,feeIds}){
 if(x.status==='cancelled'||(x.tenantId??null)!==tenantId)return false;
 if(!(x.billingStartLocalDate<endDate&&x.billingEndLocalDate>startDate))return false;
 const rentHere=kind==='tenantRent'||(kind==='period'&&includeRent);
 const rentThere=x.invoiceKind==='tenantRent'||(['period','settlement'].includes(x.invoiceKind)&&x.calculation?.includeRent===true);
 if(rentHere&&rentThere)return true;
 const feesThere=x.invoiceKind==='service'?(x.calculation?.basis==='quantity'?[]:[`${x.roomId}/${x.calculation?.feeId}`]):['period','settlement'].includes(x.invoiceKind)?(x.calculation?.services??[]).map(s=>`${s.roomId}/${s.feeId}`):[];
 return (feeIds??[]).some(f=>feesThere.includes(`${roomId}/${f}`));
}

module.exports={leasePeople,surchargeBilled,validatePeriodInput,periodInvoiceSource,periodRent,periodConflict,addMonths};
