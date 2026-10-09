'use strict';
// B6b move-out settlement (PERIOD_INVOICES.md "B6b"). One flow that ends the
// lease when it is still open and settles the money:
//  - final charges up to the move-out day (rent and service fees not billed
//    yet, unbilled meter readings, manual lines incl. a kept deposit);
//  - optionally a credit for rent paid ahead beyond the move-out day, and
//    separately for service fees paid ahead (each prepaid invoice is reduced;
//    money already paid above the new total is returned);
//  - the deposit (plus that returned money) pays every unpaid invoice of the
//    lease, oldest first, then the final invoice; the rest is refunded to the
//    tenant, or what is still unpaid stays owed on the invoices.
// One settlement per lease; there is no undo.
const {createHash}=require('node:crypto');
const {readReferenceRates,convertMinor}=require('./reference_rates');
const {allows}=require('./team_access');
const {validDate}=require('./property_contract');
const {validZone}=require('./booking_settings');
const {propertyDate,propertyDayStart}=require('./lease_dates');
const {proratedRent}=require('./invoice_math');
const {utilityInvoiceSource,meterId}=require('./utility_invoice');
const {serviceInvoiceSource,markBilledAll,feesId,roomFeesId,roomPeople}=require('./service_fee_invoice');
const {resolveFee,serviceCharge}=require('./service_fee_math');

const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const revision=d=>`${d.updateTime.seconds}:${d.updateTime.nanoseconds}`;
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const active=t=>['active','suspended'].includes(t.status)&&t.moveOutDate==null;
const MAX=1e12;
const LINE_KINDS=['late','damage','other','discount','keepDeposit'];
const FEE_KEYS=['internetFee','cableTVFee','hotWaterFee','lateFee','taxAmount'];
const scaleOf=c=>c==='USD'?100:1;
const paidOf=x=>Math.round((x.paidAmount??0)*scaleOf(x.currency));
const rentBearing=x=>x.invoiceKind==='tenantRent'||(x.invoiceKind==='period'&&x.calculation?.includeRent===true);
const rentAmount=x=>x.invoiceKind==='tenantRent'?(x.amountMinor??0):(x.calculation?.lines??[]).filter(l=>l.type==='rent').reduce((n,l)=>n+l.amountMinor,0);
const statusFor=(paid,total)=>paid>=total?'paid':paid===0?'pending':'partial';

/** Input check for quote/settle. Returns an error key or null. */
function invalidSettlementInput(d){
 if(!validDate(d.effectiveDate)||!validDate(d.dueDate))return 'settlement_invalid';
 if(typeof d.includeRent!=='boolean'||typeof d.creditRent!=='boolean'||typeof d.creditFees!=='boolean')return 'settlement_invalid';
 if(!Array.isArray(d.serviceFeeIds)||d.serviceFeeIds.length>30||d.serviceFeeIds.some(v=>!id(v))||new Set(d.serviceFeeIds).size!==d.serviceFeeIds.length)return 'settlement_invalid';
 if(!Array.isArray(d.readings)||d.readings.length>24)return 'settlement_invalid';
 const seen=new Set();
 for(const r of d.readings){
  if(!r||typeof r!=='object'||Object.keys(r).some(k=>!['roomId','kind','readingId'].includes(k))||!id(r.roomId)||!['electricity','water'].includes(r.kind)||!id(r.readingId))return 'settlement_invalid';
  const k=`${r.roomId}/${r.kind}/${r.readingId}`;if(seen.has(k))return 'settlement_invalid';seen.add(k);
 }
 if(!Array.isArray(d.lines)||d.lines.length>20)return 'settlement_invalid';
 for(const l of d.lines){
  if(!l||typeof l!=='object'||Object.keys(l).some(k=>!['kind','label','amountMinor','percent'].includes(k))||!LINE_KINDS.includes(l.kind)||typeof l.label!=='string'||!l.label.trim()||l.label.length>80)return 'settlement_invalid_line';
  if(l.kind==='discount'&&l.percent!==undefined){
   if(l.amountMinor!==undefined||!Number.isSafeInteger(l.percent)||l.percent<1||l.percent>100)return 'settlement_invalid_line';
  }else{
   if(l.percent!==undefined||!Number.isSafeInteger(l.amountMinor)||l.amountMinor===0||Math.abs(l.amountMinor)>MAX)return 'settlement_invalid_line';
   if(l.kind!=='other'&&l.amountMinor<0)return 'settlement_invalid_line';
  }
 }
 if(d.refundMethod!==null&&!['cash','bankTransfer'].includes(d.refundMethod))return 'settlement_invalid';
 if(d.refundAccountId!==null&&(!id(d.refundAccountId)||d.refundMethod!=='bankTransfer'))return 'settlement_invalid';
 if(typeof d.reason!=='string'||!d.reason.trim()||d.reason.length>1000)return 'settlement_invalid';
 return null;
}

function createSettlementHandler({db,Timestamp,HttpsError}){
 const fail=(code,key)=>{throw new HttpsError(code,key??'settlement_'+code);};
 return async request=>{
  const d=request.data||{},uid=request.auth?.uid;
  if(!uid)fail('unauthenticated');
  const write=d.action==='settle',quote=d.action==='settlementQuote';
  const body=['effectiveDate','includeRent','serviceFeeIds','readings','lines','creditRent','creditFees','refundMethod','refundAccountId','dueDate','reason'];
  const keys=[...(d.inputCurrency!==undefined?['inputCurrency']:[]),...(d.ratesId!==undefined?['ratesId']:[]),'action','organizationId','buildingId','tenantId',...(d.action==='settlementPreview'?['effectiveDate']:[]),...(quote||write?body:[]),...(write?['operationId','revision','timeZone','quoteRevision']:[])];
  if(!['settlementPreview','settlementQuote','settle'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||!id(d.tenantId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument','settlement_invalid');
  if(d.action==='settlementPreview'&&d.effectiveDate!=null&&!validDate(d.effectiveDate))fail('invalid-argument','settlement_invalid');
  if(quote||write){const bad=invalidSettlementInput(d);if(bad)fail('invalid-argument',bad);}
  if(write&&(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)||!validZone(d.timeZone)||typeof d.quoteRevision!=='string'))fail('invalid-argument','settlement_invalid');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),m=member.data();
   const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId},can=p=>allows(m,p,scope);
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||!can('manageLease')||!can('collectPayments'))fail('permission-denied','settlement_permission');
   const key=write?hash(['settlement',d.organizationId,uid,d.operationId]):null,op=write?db.doc(`settlementOperations/${key}`):null;
   const prior=write?await tx.get(op):null,fingerprint=hash(keys.map(k=>d[k]));
   if(prior?.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition','settlement_operation_reused');return prior.data().result;}
   const ref=db.doc(`tenants/${d.tenantId}`),doc=await tx.get(ref),t=doc.data();
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),b=building.data();
   if(!t||t.organizationId!==d.organizationId||t.buildingId!==d.buildingId||t.isMainTenant!==true||!b||b.organizationId!==d.organizationId)fail('not-found','settlement_not_found');
   const zone=b.timeZone,now=Timestamp.now(),today=propertyDate(now.toMillis(),zone);
   if(!validZone(zone)||!today)fail('failed-precondition','lease_property_timezone_required');
   if(t.settlementId)fail('already-exists','settlement_exists');
   const open=active(t);
   if(!open&&!(t.status==='moveOut'&&t.moveOutDate))fail('failed-precondition','settlement_lease_not_open');
   const start=t.occupancyStartDate??t.moveInDate,startDate=start?.toMillis?propertyDate(start.toMillis(),zone):null;
   if(!startDate)fail('failed-precondition','settlement_lease_not_open');
   const fixedMoveOut=open?null:propertyDate(t.moveOutDate.toMillis(),zone);
   if(fixedMoveOut&&d.effectiveDate!=null&&d.effectiveDate!==fixedMoveOut)fail('invalid-argument','settlement_date_fixed');
   const moveOut=fixedMoveOut??d.effectiveDate??today;
   const leaseCurrency=t.currency??'VND',currency=org.data().displayCurrency??leaseCurrency,scale=scaleOf(currency);
   if(!['VND','USD'].includes(currency))fail('failed-precondition','settlement_currency');
   if((quote||write)&&(d.inputCurrency??leaseCurrency)!==currency)fail('failed-precondition','settlement_currency_changed');
   const fx=d.ratesId!==undefined?await readReferenceRates(tx,db,d.ratesId):null;
   const convert=(amount,from,to=currency)=>{if(from===to)return amount;if(!fx)fail('failed-precondition','settlement_rates_required');try{return convertMinor(amount,from,to,fx);}catch(e){fail('failed-precondition',e.message);}};
   const canBackdate=allows(m,'backdateRecords',{organizationId:d.organizationId,userId:uid});
   const linked=open?await tx.get(db.collection('tenants').where('mainTenantId','==',d.tenantId)):null;
   const roommates=linked?linked.docs.filter(v=>active(v.data())).map(v=>({id:v.id,fullName:v.data().fullName??''})):[];
   // The move-out date rules of "Trả phòng" (lease_lifecycle.js), checked only when it is chosen here.
   let dateProblem=null;
   if(open){
    if(moveOut>today||moveOut<=startDate)dateProblem='lease_actual_date_required';
    else if(moveOut<today&&!canBackdate)dateProblem='invoice_backdate_owner_required';
    else if(roommates.length)dateProblem='lease_handle_roommates_first';
   }
   if((quote||write)&&dateProblem)fail(dateProblem==='invoice_backdate_owner_required'?'permission-denied':'failed-precondition',dateProblem);

   // Where the lease lived in this property (the open stay ends on the move-out day).
   const history=await tx.get(db.collection('leaseOccupancy').where('tenantId','==',d.tenantId));
   const intervals=history.docs.filter(v=>v.data().organizationId===d.organizationId&&v.data().buildingId===d.buildingId)
    .map(v=>({roomId:v.data().roomId,startDate:propertyDate(v.data().start.toMillis(),zone),endDate:propertyDate(v.data().end.toMillis(),zone)}));
   if(open)intervals.push({roomId:t.roomId,startDate,endDate:moveOut});
   const leaseStart=intervals.map(i=>i.startDate).sort()[0]??startDate;
   const room=t.roomId;

   // Every income invoice of this lease, with its current revision.
   const invoiceDocs=(await tx.get(db.collection('payments').where('organizationId','==',d.organizationId).where('tenantId','==',d.tenantId))).docs
    .filter(v=>{const x=v.data();return x.invoiceVersion===2&&x.status!=='cancelled'&&x.direction!=='expense';});

   // Rent not billed yet: from the end of the last rent invoice to the move-out day.
   let lastRent=null;
   for(const v of invoiceDocs){const x=v.data();if(rentBearing(x)&&(!lastRent||x.billingEndLocalDate>lastRent))lastRent=x.billingEndLocalDate;}
   const rentStart=lastRent&&lastRent>leaseStart?lastRent:leaseStart;
   let rentRemainder=null;
   if(rentStart<moveOut){try{const r=proratedRent({tenant:t,startDate:rentStart,endDate:moveOut,intervals,timeZone:zone});rentRemainder={startDate:rentStart,endDate:moveOut,days:r.days,amountMinor:convert(r.amountMinor,leaseCurrency),sourceAmountMinor:r.amountMinor,sourceCurrency:leaseCurrency};}catch{rentRemainder=null;}}

   // Rent paid ahead beyond the move-out day (only offered; the owner decides).
   const credits=[];
   for(const v of invoiceDocs){
    const x=v.data();if(!rentBearing(x)||!(x.billingEndLocalDate>moveOut))continue;
    const from=x.billingStartLocalDate>moveOut?x.billingStartLocalDate:moveOut,to=x.billingEndLocalDate;if(!(from<to))continue;
    // Credit = rent charged minus rent for the days actually stayed (priced
    // like any rent), so a period that does not follow calendar months still
    // leaves the tenant paying exactly the normal price for those days. A
    // period wholly after the move-out day gives back all its rent.
    const charged=rentAmount(x),sourceCurrency=x.currency??'VND';let used=0;
    if(x.billingStartLocalDate<moveOut){try{used=proratedRent({tenant:t,startDate:x.billingStartLocalDate,endDate:moveOut,intervals:[{roomId:room,startDate:x.billingStartLocalDate,endDate:null}],timeZone:zone}).amountMinor;}catch{continue;}}
    const originalRateId=x.calculation?.exchangeRateSnapshotId??(x.calculation?.lines??[]).find(l=>l.type==='rent')?.exchangeRateSnapshotId;
    if(sourceCurrency!==leaseCurrency&&used>0){
     if(!originalRateId)fail('failed-precondition','settlement_original_rates_required');
     used=convertMinor(used,leaseCurrency,sourceCurrency,await readReferenceRates(tx,db,originalRateId));
    }
    const sourceCreditMinor=Math.max(0,charged-used),creditMinor=convert(sourceCreditMinor,sourceCurrency);if(creditMinor<=0)continue;
    credits.push({doc:v,invoiceId:v.id,startDate:from,endDate:to,creditMinor,sourceCreditMinor,sourceCurrency});
   }

   // Service fees not billed yet for this room, from where billing stopped.
   const feeUntil={};
   for(const v of invoiceDocs){const x=v.data();const ids=x.invoiceKind==='service'&&x.calculation?.basis!=='quantity'&&x.roomId===room?[x.calculation?.feeId]:['period','settlement'].includes(x.invoiceKind)?(x.calculation?.services??[]).filter(s=>s.roomId===room).map(s=>s.feeId):[];for(const fid of ids)if(fid&&(!feeUntil[fid]||x.billingEndLocalDate>feeUntil[fid]))feeUntil[fid]=x.billingEndLocalDate;}
   const roomStart=intervals.filter(i=>i.roomId===room).map(i=>i.startDate).sort()[0]??startDate;
   const defs=(await tx.get(db.doc(`serviceFees/${feesId(d.organizationId,d.buildingId)}`))).data();
   const rates=(await tx.get(db.doc(`serviceFeeRooms/${roomFeesId(d.organizationId,room)}`))).data();
   const fees=[];
   for(const f of defs?.organizationId===d.organizationId?defs.fees??[]:[]){
    if(f.basis==='quantity')continue;
    const from=feeUntil[f.id]&&feeUntil[f.id]>roomStart?feeUntil[f.id]:roomStart;if(!(from<moveOut))continue;
    if(!resolveFee(f,rates?.organizationId===d.organizationId?rates.overrides?.[f.id]??[]:[],from))continue;
    fees.push({id:f.id,name:f.name,basis:f.basis,startDate:from});
   }

   // Service fees paid ahead beyond the move-out day (only offered; the owner
   // decides). Each fee on such an invoice is priced again with the price and
   // short-stay rule stored on that invoice, as if the lease left on the
   // move-out day; the difference is offered back. A rule like "full month if
   // there on the 1st" can mean nothing comes back - that is the owner's rule.
   const feeCredits=[],peopleOf={};
   for(const v of invoiceDocs){
    const x=v.data(),c=x.calculation??{};
    if(!(x.billingEndLocalDate>moveOut)||!x.billingStartLocalDate)continue;
    const items=x.invoiceKind==='period'?(c.lines??[]).filter(l=>l.type==='service').map(l=>({feeId:l.feeId,feeName:l.feeName,amountMinor:l.amountMinor,terms:l.terms,sourceCalculation:l.sourceCalculation,exchangeRateSnapshotId:l.exchangeRateSnapshotId,roomId:(c.services??[]).find(s=>s.feeId===l.feeId)?.roomId??c.roomId}))
     :x.invoiceKind==='service'&&c.basis!=='quantity'?[{feeId:c.feeId,feeName:c.feeName,amountMinor:c.amountMinor,terms:c.terms,sourceCalculation:c.sourceCalculation,exchangeRateSnapshotId:c.exchangeRateSnapshotId,roomId:c.roomId??x.roomId,basis:c.basis}]:[];
    for(const it of items){
     const basis=it.basis??(defs?.fees??[]).find(f=>f.id===it.feeId)?.basis;
     if(!['room','person'].includes(basis)||!it.terms||!it.roomId||!Number.isSafeInteger(it.amountMinor)||it.amountMinor<=0)continue;
     if(!peopleOf[it.roomId])peopleOf[it.roomId]=(await roomPeople({tx,db,organizationId:d.organizationId,buildingId:d.buildingId,roomId:it.roomId,tenantId:d.tenantId,zone}))
      .map(p=>({...p,intervals:p.intervals.map(i=>({startDate:i.startDate,endDate:i.endDate==null||i.endDate>moveOut?moveOut:i.endDate})).filter(i=>i.startDate<i.endDate)}));
     let used=0;
     try{used=serviceCharge({basis,terms:it.sourceCalculation?.terms??it.terms,startDate:x.billingStartLocalDate,endDate:x.billingEndLocalDate,people:peopleOf[it.roomId],currency:it.sourceCalculation?.currency??x.currency??'VND'}).amountMinor;}
     catch(e){if(!['service_no_billable_charge','service_tenant_not_in_room'].includes(e.message))continue;}
     if(it.sourceCalculation?.currency && it.sourceCalculation.currency!==(x.currency??'VND')){
      if(!it.exchangeRateSnapshotId)fail('failed-precondition','settlement_original_rates_required');
      used=convertMinor(used,it.sourceCalculation.currency,x.currency??'VND',await readReferenceRates(tx,db,it.exchangeRateSnapshotId));
     }
     const sourceCurrency=x.currency??'VND',sourceCreditMinor=Math.max(0,it.amountMinor-used),creditMinor=convert(sourceCreditMinor,sourceCurrency);if(creditMinor<=0)continue;
     feeCredits.push({invoiceId:v.id,feeId:it.feeId,feeName:it.feeName??'',startDate:x.billingStartLocalDate>moveOut?x.billingStartLocalDate:moveOut,endDate:x.billingEndLocalDate,creditMinor,sourceCreditMinor,sourceCurrency});
    }
   }

   // Meter readings not billed yet, measured while this lease lived there.
   const readings=[],lastReading={};
   for(const roomId of [...new Set(intervals.map(i=>i.roomId))])for(const kind of ['electricity','water']){
    const rows=await tx.get(db.collection(`utilityMeters/${meterId(d.organizationId,roomId,kind)}/readings`));
    for(const v of rows.docs){
     const r=v.data();if(r.organizationId!==d.organizationId||r.reversedAt)continue;
     if(roomId===room&&(!lastReading[kind]||r.date>lastReading[kind]))lastReading[kind]=r.date;
     if(r.invoiceId||!r.calculation||!(r.calculation.amountMinor>0))continue;
     if(!intervals.some(i=>i.roomId===roomId&&i.startDate<=r.startDate&&(!i.endDate||i.endDate>=r.date)))continue;
     readings.push({roomId,kind,readingId:v.id,startDate:r.startDate,date:r.date,usageMilli:r.calculation.usageMilli,amountMinor:convert(r.calculation.amountMinor,r.calculation.currency),sourceAmountMinor:r.calculation.amountMinor,sourceCurrency:r.calculation.currency});
    }
   }
   readings.sort((a,b)=>a.date.localeCompare(b.date)||a.kind.localeCompare(b.kind));

   const balanceOf=v=>{const x=v.data();return (x.totalMinor??0)-paidOf(x);};
   const openInvoices=invoiceDocs.filter(v=>balanceOf(v)>0).map(v=>{const x=v.data();return {id:v.id,kind:x.invoiceKind,startDate:x.billingStartLocalDate??null,endDate:x.billingEndLocalDate??null,dueDate:x.dueLocalDate??null,totalMinor:convert(x.totalMinor,x.currency??'VND'),paidMinor:convert(paidOf(x),x.currency??'VND'),balanceMinor:convert(balanceOf(v),x.currency??'VND'),sourceCurrency:x.currency??'VND',sourceBalanceMinor:balanceOf(v)};});
   const originalDepositMinor=Number.isSafeInteger(t.depositMinor)&&t.depositMinor>0?t.depositMinor:0;
   const depositMinor=convert(originalDepositMinor,leaseCurrency);
   const accounts=(Array.isArray(org.data().paymentAccounts)?org.data().paymentAccounts:[]).filter(a=>a&&id(a.id)).map(a=>({id:a.id,label:a.label??''}));

   if(d.action==='settlementPreview'){
    return {record:{tenantName:t.fullName??'',currency,today,startDate,open,moveOutDate:moveOut,dateFixed:!open,dateProblem,roommates,canBackdate,
     canPrice:can('overridePrices'),canRefund:can('refundPayments'),depositMinor,depositMethod:t.depositMethod??null,depositAccountLabel:t.depositAccountLabel??'',
     rent:rentRemainder,credits:credits.map(c=>({invoiceId:c.invoiceId,startDate:c.startDate,endDate:c.endDate,creditMinor:c.creditMinor})),feeCredits,
     fees:fees.map(f=>({id:f.id,name:f.name,basis:f.basis,startDate:f.startDate})),readings,lastReading,openInvoices,accounts,revision:revision(doc),timeZone:zone}};
   }

   // ---- quote / settle: price exactly what was chosen ----
   if((d.lines.length||d.creditRent||d.creditFees)&&!can('overridePrices'))fail('permission-denied','settlement_lines_need_price_authority');
   if(d.serviceFeeIds.some(f=>!fees.some(x=>x.id===f)))fail('failed-precondition','settlement_item_unavailable');
   if(d.readings.some(r=>!readings.some(x=>x.roomId===r.roomId&&x.kind===r.kind&&x.readingId===r.readingId)))fail('failed-precondition','settlement_item_unavailable');
   if(d.includeRent&&!rentRemainder)fail('failed-precondition','settlement_item_unavailable');
   const lines=[];
   if(d.includeRent)lines.push({type:'rent',basis:'days',startDate:rentRemainder.startDate,endDate:rentRemainder.endDate,days:rentRemainder.days,amountMinor:rentRemainder.amountMinor});
   const serviceSources=[];
   for(const feeId of d.serviceFeeIds){
    const f=fees.find(x=>x.id===feeId);let source;
    try{source=await serviceInvoiceSource({tx,db,organizationId:d.organizationId,buildingId:d.buildingId,roomId:room,feeId,tenantId:d.tenantId,startDate:f.startDate,endDate:moveOut,quantityMilli:null,currency,zone,ratesId:d.ratesId});}catch(e){fail('failed-precondition',e.message);}
    serviceSources.push(source);
    lines.push({type:'service',feeId,feeName:source.fee.name,startDate:f.startDate,endDate:moveOut,amountMinor:source.calculation.amountMinor,people:source.calculation.lines,...(source.calculation.sourceCalculation?{sourceCalculation:source.calculation.sourceCalculation,exchangeRateSnapshotId:d.ratesId}:{})});
   }
   const utilitySources=[];
   for(const r of d.readings){
    const reading=readings.find(x=>x.roomId===r.roomId&&x.kind===r.kind&&x.readingId===r.readingId);let source;
    try{source=await utilityInvoiceSource({tx,db,organizationId:d.organizationId,buildingId:d.buildingId,roomId:r.roomId,kind:r.kind,readingId:r.readingId,startDate:reading.startDate,endDate:reading.date,currency,intervals,ratesId:d.ratesId});}catch(e){fail('failed-precondition',e.message);}
    utilitySources.push(source);
    lines.push({type:'utility',kind:r.kind,roomId:r.roomId,readingId:r.readingId,startDate:reading.startDate,endDate:reading.date,usageMilli:source.calculation.usageMilli,amountMinor:source.calculation.amountMinor,...(source.calculation.sourceCalculation?{sourceCalculation:source.calculation.sourceCalculation,exchangeRateSnapshotId:d.ratesId}:{})});
   }
   const rentLine=lines.find(l=>l.type==='rent');
   let kept=0;
   for(const l of d.lines){
    let amountMinor=l.kind==='discount'?-(l.amountMinor??0):l.amountMinor;
    if(l.percent!==undefined){if(!rentLine)fail('failed-precondition','settlement_discount_needs_rent');amountMinor=-Math.round(rentLine.amountMinor*l.percent/100);}
    if(l.kind==='keepDeposit')kept+=amountMinor;
    lines.push({type:'manual',kind:l.kind,label:l.label.trim(),amountMinor,...(l.percent!==undefined?{percent:l.percent}:{})});
   }
   if(kept>depositMinor)fail('failed-precondition','settlement_keep_exceeds_deposit');
   const finalMinor=lines.reduce((n,l)=>n+l.amountMinor,0);
   if(!Number.isSafeInteger(finalMinor)||finalMinor>MAX)fail('invalid-argument','settlement_total_too_large');
   if(finalMinor<0)fail('failed-precondition','settlement_total_negative');

   // Credits reduce the prepaid invoices; paid money above the new total is returned.
   const state=new Map(invoiceDocs.map(v=>{const x=v.data();return [v.id,{doc:v,x,total:x.totalMinor??0,amountMinor:x.amountMinor??0,paid:paidOf(x),credit:0,returned:0,applied:0}];}));
   const creditPlan=[];
   const chosen=[...(d.creditRent?credits.map(c=>({kind:'rent',...c})):[]),...(d.creditFees?feeCredits.map(c=>({kind:'fee',...c})):[])];
   for(const c of chosen){
    const s=state.get(c.invoiceId);const sourceCredit=c.sourceCreditMinor??c.creditMinor;s.total-=sourceCredit;s.amountMinor-=sourceCredit;s.credit+=sourceCredit;
    let returned=0;if(s.paid>s.total){returned=s.paid-s.total;s.paid=s.total;s.returned+=returned;}
    creditPlan.push({kind:c.kind,invoiceId:c.invoiceId,...(c.kind==='fee'?{feeId:c.feeId,feeName:c.feeName}:{}),startDate:c.startDate,endDate:c.endDate,creditMinor:c.creditMinor,returnedMinor:convert(returned,s.x.currency??'VND'),sourceCurrency:s.x.currency??'VND',sourceCreditMinor:sourceCredit,sourceReturnedMinor:returned});
   }
   const returnedMinor=creditPlan.reduce((n,c)=>n+c.returnedMinor,0);
   if(returnedMinor>0&&!can('refundPayments'))fail('permission-denied','settlement_refund_needs_permission');

   // The deposit and returned money pay the unpaid invoices, oldest first, then the final one.
   let pool=depositMinor+returnedMinor;
   const order=[...state.values()].filter(s=>s.total-s.paid>0).sort((a,b)=>String(a.x.dueLocalDate??a.x.billingStartLocalDate??'').localeCompare(String(b.x.dueLocalDate??b.x.billingStartLocalDate??''))||a.doc.id.localeCompare(b.doc.id));
   const applications=[];
   for(const s of order){
    if(pool<=0)break;
    const sourceCurrency=s.x.currency??'VND',balance=s.total-s.paid,full=convert(balance,sourceCurrency);
    let sourceAmount;
    if(full<=pool)sourceAmount=balance;
    else { // Find the largest original-unit payment whose converted cost fits.
     let lo=0,hi=balance;
     while(lo<hi){const mid=Math.floor((lo+hi+1)/2);if(convert(mid,sourceCurrency)<=pool)lo=mid;else hi=mid-1;}sourceAmount=lo;
    }
    const amount=convert(sourceAmount,sourceCurrency);
    if(sourceAmount<=0||amount<=0)continue;
    s.paid+=sourceAmount;s.applied=sourceAmount;pool-=amount;
    applications.push({invoiceId:s.doc.id,amountMinor:amount,...(sourceCurrency!==currency?{sourceAmountMinor:sourceAmount,sourceCurrency}:{})});
   }
   let finalPaid=0;
   if(finalMinor>0&&pool>0){finalPaid=Math.min(pool,finalMinor);pool-=finalPaid;applications.push({invoiceId:'final',amountMinor:finalPaid});}
   const refundMinor=pool;
   const owedMinor=[...state.values()].reduce((n,s)=>n+convert(Math.max(0,s.total-s.paid),s.x.currency??'VND'),0)+(finalMinor-finalPaid);
   const refundAccount=d.refundAccountId?accounts.find(a=>a.id===d.refundAccountId):null;
   if(d.refundAccountId&&!refundAccount)fail('invalid-argument','settlement_invalid');

   const plan={sourceDeposit:{currency:leaseCurrency,amountMinor:originalDepositMinor},...(d.ratesId?{exchangeRateSnapshotId:d.ratesId}:{}),moveOutDate:moveOut,currency,lines,finalMinor,depositMinor,keptMinor:kept,credits:creditPlan,returnedMinor,applications,refundMinor,owedMinor};
   const quoteRevision=hash([revision(doc),invoiceDocs.map(v=>[v.id,revision(v)]),plan,d.dueDate,d.refundMethod,d.refundAccountId]);
   if(quote)return {record:{...plan,tenantName:t.fullName??'',quoteRevision}};
   if(d.quoteRevision!==quoteRevision)fail('aborted','settlement_changed');
   if(open&&(d.revision!==revision(doc)||d.timeZone!==zone))fail('aborted','settlement_changed');
   if(refundMinor>0&&!d.refundMethod)fail('invalid-argument','settlement_refund_method_required');
   const due=propertyDayStart(d.dueDate,zone);if(due===null)fail('invalid-argument','settlement_invalid');

   // ---- writes (every read is done above) ----
   const roomDoc=open?await tx.get(db.doc(`rooms/${room}`)):null;
   if(open&&(!roomDoc.exists||roomDoc.data().organizationId!==d.organizationId||roomDoc.data().buildingId!==d.buildingId))fail('failed-precondition','settlement_room');
   const settlementId='settlement_'+key,finalId=finalMinor>0?'invoice_'+key:null;
   const label=s=>({currency:s.x.currency??'VND',invoiceId:s.doc.id,kind:s.x.invoiceKind,startDate:s.x.billingStartLocalDate??null,endDate:s.x.billingEndLocalDate??null});
   // Prepaid / unpaid invoices: one update each with their final state and one history entry.
   for(const s of state.values()){
    if(!s.credit&&!s.applied)continue;
    const patch={totalMinor:s.total,paidAmount:s.paid/scaleOf(s.x.currency),status:statusFor(s.paid,s.total),updatedAt:now,updatedBy:uid,settlementId};
    if(s.credit){patch.amountMinor=s.amountMinor;patch.amount=s.amountMinor/scaleOf(s.x.currency);patch.moveOutCredit={creditMinor:s.credit,returnedMinor:s.returned,moveOutDate:moveOut};}
    if(s.applied){patch.paidAt=now;patch.paidBy=uid;patch.paymentMethod='deposit';}
    tx.update(s.doc.ref,patch);
    tx.create(s.doc.ref.collection('invoiceHistory').doc(key),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'moveOutSettlement',reason:d.reason.trim(),
     before:{totalMinor:s.x.totalMinor,paidAmount:s.x.paidAmount,status:s.x.status},after:{totalMinor:s.total,paidAmount:s.paid/scaleOf(s.x.currency),status:patch.status},creditMinor:s.credit,returnedMinor:s.returned,depositMinor:s.applied});
   }
   if(finalId){
    const fref=db.doc(`payments/${finalId}`);
    const starts=lines.filter(l=>l.startDate).map(l=>l.startDate).sort();
    tx.create(fref,{organizationId:d.organizationId,buildingId:d.buildingId,roomId:room,tenantId:d.tenantId,tenantName:t.fullName??'',invoiceVersion:2,invoiceKind:'settlement',type:'settlement',direction:'income',currency,
     amount:finalMinor/scale,amountMinor:finalMinor,totalMinor:finalMinor,paidAmount:finalPaid/scale,status:statusFor(finalPaid,finalMinor),feesMinor:Object.fromEntries(FEE_KEYS.map(k=>[k,0])),...Object.fromEntries(FEE_KEYS.map(k=>[k,0])),
     billingStartLocalDate:starts[0]&&starts[0]<moveOut?starts[0]:moveOut,billingEndLocalDate:moveOut,dueLocalDate:d.dueDate,dueDate:Timestamp.fromMillis(due),timeZone:zone,
     calculation:{chargeType:'settlement',amountMinor:finalMinor,currency,moveOutDate:moveOut,includeRent:d.includeRent,lines,services:serviceSources.map(s=>({feeId:s.fee.id,roomId:room})),utilities:d.readings.map(r=>({roomId:r.roomId,kind:r.kind,readingId:r.readingId}))},
     settlementId,description:d.reason.trim(),...(finalPaid>0?{paidAt:now,paidBy:uid,paymentMethod:'deposit'}:{}),createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid});
    tx.create(fref.collection('invoiceHistory').doc(key),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'create',reason:d.reason.trim(),before:null,after:{totalMinor:finalMinor,paidAmount:finalPaid/scale,status:statusFor(finalPaid,finalMinor)},depositMinor:finalPaid});
    for(const s of utilitySources)tx.update(s.ref,{invoiceId:finalId});
    if(serviceSources.length)markBilledAll(tx,serviceSources,{organizationId:d.organizationId,buildingId:d.buildingId,roomId:room,endDate:moveOut,now});
   }
   const moveOutPatch=open?{moveOutDate:Timestamp.fromMillis(propertyDayStart(moveOut,zone)),moveOutLocalDate:moveOut,moveOutTimeZone:zone,status:'moveOut'}:{};
   tx.update(ref,{...moveOutPatch,settlementId,settledAt:now,updatedAt:now,updatedBy:uid});
   if(open){
    // Same records as "Trả phòng" (lease_lifecycle.js moveOut).
    tx.update(roomDoc.ref,{bookingRevision:(roomDoc.data().bookingRevision??0)+1});
    tx.create(db.doc(`leaseOccupancy/${key}`),{organizationId:d.organizationId,tenantId:d.tenantId,buildingId:d.buildingId,roomId:room,start:start,end:Timestamp.fromMillis(propertyDayStart(moveOut,zone)),timeZone:zone,isMainTenant:true,createdAt:now});
    tx.create(ref.collection('leaseHistory').doc(key),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'moveOut',reason:d.reason.trim(),before:{status:t.status,moveOutDate:null},after:{status:'moveOut',moveOutDate:moveOut,settlementId}});
   }
   const record={...plan,applications:applications.map(a=>a.invoiceId==='final'?{...a,invoiceId:finalId}:a),settlementId,finalInvoiceId:finalId,refundMethod:refundMinor>0?d.refundMethod:null,refundAccount:refundMinor>0?refundAccount??null:null,dueDate:d.dueDate};
   tx.create(db.doc(`leaseSettlements/${settlementId}`),{organizationId:d.organizationId,buildingId:d.buildingId,roomId:room,tenantId:d.tenantId,tenantName:t.fullName??'',movedOutHere:open,reason:d.reason.trim(),
    invoices:[...state.values()].filter(s=>s.credit||s.applied).map(s=>({...label(s),creditMinor:s.credit,returnedMinor:s.returned,depositMinor:s.applied})),...record,createdAt:now,createdBy:uid});
   tx.update(building.ref,{invoiceRevision:(b.invoiceRevision??0)+1});
   const result={settlementId,finalInvoiceId:finalId,refundMinor,owedMinor,currency,tenantId:d.tenantId,buildingId:d.buildingId};
   tx.create(op,{organizationId:d.organizationId,actorId:uid,createdAt:now,fingerprint,result});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:'lease_settle',targetId:d.tenantId,before:{status:t.status},after:{status:'moveOut',settlementId,refundMinor,owedMinor}});
   return result;
  });
 };
}

module.exports={createSettlementHandler,invalidSettlementInput};
