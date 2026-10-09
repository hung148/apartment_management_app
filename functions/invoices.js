'use strict';
const {createHash}=require('node:crypto');
const {readReferenceRates,convertCalculation,convertMinor}=require('./reference_rates');
const {utilityInvoiceSource}=require('./utility_invoice');
const {serviceInvoiceSource,markBilled,markBilledAll,feesId,roomFeesId}=require('./service_fee_invoice');
const {validatePeriodInput,periodInvoiceSource,periodConflict,addMonths,leasePeople,surchargeBilled}=require('./period_invoice');
const {resolveFee}=require('./service_fee_math');
const {rentForDate}=require('./tenant_rent');
const {allows}=require('./team_access');
const {validDate,validContract}=require('./property_contract');
const {validZone}=require('./booking_settings');
const {propertyDate,propertyDayStart}=require('./lease_dates');
const {proratedRent,nextDate}=require('./invoice_math');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const revision=d=>`${d.updateTime.seconds}:${d.updateTime.nanoseconds}`;
const feeKeys=['internetFee','cableTVFee','hotWaterFee','lateFee','taxAmount'];
function createInvoiceHandler({db,Timestamp,HttpsError}){
 const fail=(code,key='invoice_'+code)=>{throw new HttpsError(code,key);};
 return async request=>{
  const {ratesId,inputCurrency,...d}=request.data||{},uid=request.auth?.uid,write=['create','edit','void','payExpense','reverseExpense'].includes(d.action);
  if(!uid)fail('unauthenticated');
  if(inputCurrency!==undefined&&(!['quote','create'].includes(d.action)||!['VND','USD'].includes(inputCurrency)))fail('invalid-argument');
  if(ratesId!==undefined&&(!['quote','create','periodPreview'].includes(d.action)||typeof ratesId!=='string'||! /^[a-f0-9]{64}$/.test(ratesId)))fail('invalid-argument');
  const keys=['action','organizationId','buildingId',...(['read','history','edit','void','payExpense','reverseExpense'].includes(d.action)?['invoiceId']:[]),...(['list','history'].includes(d.action)?['cursor']:[]),...(['quote','create'].includes(d.action)?['kind','tenantId','startDate','endDate','dueDate','feesMinor','reason',...(d.kind==='charge'?['chargeType','unitPriceMinor','quantityMilli']:d.kind==='utility'?['chargeType','roomId','readingId']:d.kind==='service'?['feeId','roomId','quantityMilli']:d.kind==='period'?['includeRent','serviceFeeIds','readings','lines','surcharges']:[])]:[]),...(d.action==='periodPreview'?['tenantId']:[]),...(write?['operationId']:[]),...(['edit','void','payExpense','reverseExpense'].includes(d.action)?['revision','reason']:[]),...(d.action==='create'?['quoteRevision']:[]),...(d.action==='edit'?['feesMinor','dueDate']:[]),...(['payExpense','reverseExpense'].includes(d.action)?['amountMinor','paymentMethod']:[])];
  if(!['list','read','history','quote','create','edit','void','payExpense','reverseExpense','tenants','periodPreview'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||Object.keys(d).some(k=>!keys.includes(k))||(keys.includes('invoiceId')&&!id(d.invoiceId))||(d.cursor!=null&&!id(d.cursor))||(write&&!id(d.operationId)))fail('invalid-argument');
  if(d.action==='periodPreview'&&!id(d.tenantId))fail('invalid-argument');
  if(keys.includes('reason')&&(typeof d.reason!=='string'||!d.reason.trim()||d.reason.length>1000))fail('invalid-argument');
  if(keys.includes('revision')&&(typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))fail('invalid-argument');
  if(keys.includes('feesMinor')&&(!d.feesMinor||Object.keys(d.feesMinor).length!==feeKeys.length||feeKeys.some(k=>!Number.isSafeInteger(d.feesMinor[k])||d.feesMinor[k]<0||d.feesMinor[k]>1e12)))fail('invalid-argument');
  if(keys.includes('dueDate')&&!validDate(d.dueDate))fail('invalid-argument');
  if(['quote','create'].includes(d.action)&&(!['tenantRent','buildingRent','charge','utility','service','period'].includes(d.kind)||(d.kind==='buildingRent'?d.tenantId!==null:!id(d.tenantId))||!validDate(d.startDate)||!validDate(d.endDate)||d.endDate<=d.startDate))fail('invalid-argument');
  if(d.kind==='utility'&&(!['electricity','water'].includes(d.chargeType)||!id(d.roomId)||!id(d.readingId)))fail('invalid-argument');
  if(['quote','create'].includes(d.action)&&d.kind==='period')try{validatePeriodInput(d);}catch(e){fail('invalid-argument',e.message);}
  if(d.kind==='service'&&(!id(d.feeId)||!id(d.roomId)||(d.quantityMilli!==null&&(!Number.isSafeInteger(d.quantityMilli)||d.quantityMilli<=0||d.quantityMilli>1e9))))fail('invalid-argument');
  if(d.kind==='charge'&&(!['electricity','water','internet','parking','maintenance','deposit','penalty','other'].includes(d.chargeType)||!Number.isSafeInteger(d.unitPriceMinor)||d.unitPriceMinor<=0||d.unitPriceMinor>1e12||!Number.isSafeInteger(d.quantityMilli)||d.quantityMilli<=0||d.quantityMilli>1e9))fail('invalid-argument');
  if(['payExpense','reverseExpense'].includes(d.action)&&(!Number.isSafeInteger(d.amountMinor)||d.amountMinor<=0||!['cash','bankTransfer','momo','zalopay','creditCard','other'].includes(d.paymentMethod)))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),m=member.data(),scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||!allows(m,'readFinancialReports',scope))fail('permission-denied');
   if((write||d.action==='quote')&&!allows(m,'collectPayments',scope))fail('permission-denied');
   if(['edit','void'].includes(d.action)&&!allows(m,'overridePrices',scope))fail('permission-denied');
   if(d.action==='reverseExpense'&&!allows(m,'refundPayments',scope))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),b=building.data();if(!b||b.organizationId!==d.organizationId)fail('not-found');
   const zone=b.timeZone,now=Timestamp.now(),today=propertyDate(now.toMillis(),zone);if(!validZone(zone)||!today)fail('failed-precondition','lease_property_timezone_required');
   const key=write?hash(['invoice',d.organizationId,uid,d.operationId]):null,op=write?db.doc(`invoiceOperations/${key}`):null,prior=write?await tx.get(op):null,fingerprint=hash([...keys.map(k=>d[k]),...(ratesId===undefined?[]:[ratesId]),...(inputCurrency===undefined?[]:[inputCurrency])]);
   if(prior?.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
   const projection=doc=>{const x=doc.data();return {id:doc.id,revision:revision(doc),kind:x.invoiceKind??null,direction:x.direction??'income',tenantId:x.tenantId??null,tenantName:x.tenantName??'',currency:x.currency,status:x.status,amountMinor:x.amountMinor??null,totalMinor:x.totalMinor??null,paidMinor:Math.round(x.paidAmount*(x.currency==='USD'?100:1)),startDate:x.billingStartLocalDate??null,endDate:x.billingEndLocalDate??null,dueDate:x.dueLocalDate??null,feesMinor:x.feesMinor??null,calculation:x.calculation??null,notes:x.description??'',roomId:x.roomId??null,overdue:['pending','partial','overdue'].includes(x.status)&&x.direction!=='expense'&&typeof x.dueLocalDate==='string'&&x.dueLocalDate<today,canEdit:x.invoiceVersion===2&&x.invoiceKind!=='repair'&&allows(m,'overridePrices',scope),canSettle:x.direction==='expense'&&allows(m,'collectPayments',scope),canReverse:x.direction==='expense'&&allows(m,'refundPayments',scope)};};
   if(d.action==='list'){
    let q=db.collection('payments').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId).orderBy('__name__');if(d.cursor)q=q.startAfter(d.cursor);const page=await tx.get(q.limit(26)),rows=page.docs.slice(0,25);return {records:rows.map(projection),nextCursor:page.size>25?rows.at(-1).id:null,canCreate:allows(m,'collectPayments',scope),canPrice:allows(m,'overridePrices',scope)};
   }
   if(d.action==='tenants'){
    const rows=await tx.get(db.collection('tenants').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
    const past=await tx.get(db.collection('leaseOccupancy').where('buildingId','==',d.buildingId));const known=new Map(rows.docs.map(v=>[v.id,v]));
    for(const h of past.docs){if(h.data().organizationId!==d.organizationId||known.has(h.data().tenantId))continue;const tenant=await tx.get(db.doc(`tenants/${h.data().tenantId}`));if(tenant.exists&&tenant.data().organizationId===d.organizationId)known.set(tenant.id,tenant);}
    return {records:[...known.values()].filter(v=>v.data().isMainTenant===true).map(v=>({id:v.id,fullName:v.data().fullName??'',roomId:v.data().roomId,currency:org.data().displayCurrency??v.data().currency??'VND'})),today,timeZone:zone,currency:org.data().displayCurrency??b.currency??'VND'};
   }
   const datePolicy=date=>{if(date<today&&!allows(m,'backdateRecords',{organizationId:d.organizationId,userId:uid}))fail('permission-denied','invoice_backdate_owner_required');};
   let ref,snapshot,old,patch,result,utilitySource,serviceSource,periodSource;
   const leaseOf=async tenantId=>{
    const tenant=await tx.get(db.doc(`tenants/${tenantId}`)),t=tenant.data();if(!t||t.organizationId!==d.organizationId||t.isMainTenant!==true)fail('not-found');
    const history=await tx.get(db.collection('leaseOccupancy').where('tenantId','==',tenantId));
    const intervals=history.docs.filter(v=>v.data().organizationId===d.organizationId&&v.data().buildingId===d.buildingId).map(v=>({roomId:v.data().roomId,startDate:propertyDate(v.data().start.toMillis(),zone),endDate:propertyDate(v.data().end.toMillis(),zone)}));
    if(t.buildingId===d.buildingId)intervals.push({roomId:t.roomId,startDate:propertyDate((t.occupancyStartDate??t.moveInDate).toMillis(),zone),endDate:t.moveOutDate?propertyDate(t.moveOutDate.toMillis(),zone):null});
    if(!intervals.length)fail('not-found');
    const room=t.buildingId===d.buildingId?t.roomId:history.docs.find(v=>v.data().buildingId===d.buildingId)?.data().roomId??'';
    return {tenant,t,intervals,room};
   };
   if(d.action==='periodPreview'){
    // B6: suggest the next period and list what can go on it.
    if(!allows(m,'collectPayments',scope))fail('permission-denied');
    const {t,intervals,room}=await leaseOf(d.tenantId);
    const existing=await tx.get(db.collection('payments').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
    let lastRent=null;
    for(const v of existing.docs){const x=v.data();if(x.status==='cancelled'||(x.tenantId??null)!==d.tenantId)continue;if((x.invoiceKind==='tenantRent'||(x.invoiceKind==='period'&&x.calculation?.includeRent===true))&&(!lastRent||x.billingEndLocalDate>lastRent))lastRent=x.billingEndLocalDate;}
    const leaseStart=intervals.map(i=>i.startDate).sort()[0];
    const leaseEnd=t.moveOutDate?propertyDate(t.moveOutDate.toMillis(),zone):typeof t.contractEndLocalDate==='string'?nextDate(t.contractEndLocalDate):null;
    const startDate=lastRent&&lastRent>leaseStart?lastRent:leaseStart;
    let endDate=addMonths(startDate,t.paymentPeriodMonths??1);if(leaseEnd&&leaseEnd<endDate)endDate=leaseEnd;
    const finished=!(endDate>startDate);
    let dueDate=startDate;
    if(Number.isSafeInteger(t.paymentDueDay)){const y=Number(startDate.slice(0,4)),mo=Number(startDate.slice(5,7)),last=new Date(Date.UTC(y,mo,0)).getUTCDate(),day=String(Math.min(t.paymentDueDay,last)).padStart(2,'0'),c=`${startDate.slice(0,8)}${day}`;dueDate=c>startDate?c:startDate;}
    const defs=(await tx.get(db.doc(`serviceFees/${feesId(d.organizationId,d.buildingId)}`))).data();
    const rates=room?(await tx.get(db.doc(`serviceFeeRooms/${roomFeesId(d.organizationId,room)}`))).data():null;
    // How far each fee is already billed for this tenant in this room (single fee or period invoices).
    const feeUntil={};
    for(const v of existing.docs){const x=v.data();if(x.status==='cancelled'||(x.tenantId??null)!==d.tenantId)continue;const ids=x.invoiceKind==='service'&&x.calculation?.basis!=='quantity'&&x.roomId===room?[x.calculation?.feeId]:x.invoiceKind==='period'?(x.calculation?.services??[]).filter(s=>s.roomId===room).map(s=>s.feeId):[];for(const fid of ids)if(fid&&(!feeUntil[fid]||x.billingEndLocalDate>feeUntil[fid]))feeUntil[fid]=x.billingEndLocalDate;}
    const fees=(defs?.organizationId===d.organizationId?defs.fees??[]:[]).filter(f=>f.basis!=='quantity'&&!finished&&resolveFee(f,rates?.organizationId===d.organizationId?rates.overrides?.[f.id]??[]:[],startDate)).map(f=>({id:f.id,name:f.name,basis:f.basis,billedUntil:feeUntil[f.id]??null}));
    const readings=[],{meterId}=require('./utility_invoice');let lastElectricity=null;
    for(const roomId of [...new Set(intervals.map(i=>i.roomId))])for(const kind of ['electricity','water']){
     const rows=await tx.get(db.collection(`utilityMeters/${meterId(d.organizationId,roomId,kind)}/readings`));
     for(const v of rows.docs){const r=v.data();
      // 2026-10-04 (Tom): the latest electricity reading of the lease, billed or
      // not, so the form can say why there is no electricity line.
      if(kind==='electricity'&&r.organizationId===d.organizationId&&!r.reversedAt&&typeof r.date==='string'&&intervals.some(i=>i.roomId===roomId&&i.startDate<=r.date&&(!i.endDate||i.endDate>=r.date))&&(!lastElectricity||r.date>lastElectricity.date))lastElectricity={date:r.date,status:r.invoiceId?'invoiced':r.calculation&&r.calculation.amountMinor>0?'unbilled':'noCharge'};
      if(r.organizationId!==d.organizationId||r.reversedAt||r.invoiceId||!r.calculation||!(r.calculation.amountMinor>0))continue;if(!intervals.some(i=>i.roomId===roomId&&i.startDate<=r.startDate&&(!i.endDate||i.endDate>=r.date)))continue;readings.push({roomId,kind,readingId:v.id,startDate:r.startDate,date:r.date,usageMilli:r.calculation.usageMilli,amountMinor:r.calculation.amountMinor,currency:r.calculation.currency});}
    }
    readings.sort((a,b)=>a.date.localeCompare(b.date)||a.kind.localeCompare(b.kind));
    // 2026-10-04: the lease's surcharges, with what this period would charge.
    const defsHere=Array.isArray(t.surcharges)?t.surcharges.filter(x=>x&&id(x.id)):[];
    const people=defsHere.some(x=>x.basis==='person')&&!finished&&room?await leasePeople({tx,db,organizationId:d.organizationId,buildingId:d.buildingId,roomId:room,tenantId:d.tenantId,startDate,endDate,zone}):1;
    const viewCurrency=org.data().displayCurrency??t.currency??'VND',sourceCurrency=t.currency??'VND';
    let rateSnapshot=null;
    if(viewCurrency!==sourceCurrency){try{rateSnapshot=await readReferenceRates(tx,db,ratesId);}catch(e){fail('failed-precondition',e.message);}}
    const viewMinor=value=>Number.isSafeInteger(value)&&rateSnapshot?convertMinor(value,sourceCurrency,viewCurrency,rateSnapshot):value;
    const surcharges=defsHere.map(x=>({id:x.id,label:x.label,amountMinor:viewMinor(x.amountMinor),basis:x.basis,frequency:x.frequency,...(x.kind?{kind:x.kind}:{}),count:x.basis==='person'?people:1,billed:x.frequency==='once'&&existing.docs.some(v=>surchargeBilled(v.data(),{tenantId:d.tenantId,surchargeId:x.id,frequency:'once'}))}));
    return {record:{tenantName:t.fullName??'',currency:viewCurrency,roomId:room,today,periodMonths:t.paymentPeriodMonths??1,dueDay:t.paymentDueDay??null,periodRentMinor:viewMinor(t.periodRentMinor??null),monthlyRentMinor:viewMinor(rentForDate(t,startDate)),finished,suggestion:finished?null:{startDate,endDate,dueDate},fees,readings,lastElectricity,surcharges,canPrice:allows(m,'overridePrices',scope),canBackdate:allows(m,'backdateRecords',{organizationId:d.organizationId,userId:uid})}};
   }
   if(['quote','create'].includes(d.action)){
    datePolicy(d.startDate);datePolicy(d.dueDate);
    if(feeKeys.some(k=>d.feesMinor[k]>0)&&!allows(m,'overridePrices',scope))fail('permission-denied');
    let calculation,currency,roomId='',tenantName='',sourceRevision,direction='income',contractSnapshot=null;
    const selectCurrency=source=>{const selected=org.data().displayCurrency??source;if((inputCurrency??source)!==selected)fail('aborted');return selected;};
    if(['tenantRent','charge','utility','service','period'].includes(d.kind)){
     const tenant=await tx.get(db.doc(`tenants/${d.tenantId}`)),t=tenant.data();if(!t||t.organizationId!==d.organizationId||t.isMainTenant!==true)fail('not-found');
     currency=selectCurrency(t.currency??'VND');
     const history=await tx.get(db.collection('leaseOccupancy').where('tenantId','==',d.tenantId));
     const intervals=history.docs.filter(v=>v.data().organizationId===d.organizationId&&v.data().buildingId===d.buildingId).map(v=>({roomId:v.data().roomId,startDate:propertyDate(v.data().start.toMillis(),zone),endDate:propertyDate(v.data().end.toMillis(),zone)}));
     if(t.buildingId===d.buildingId)intervals.push({roomId:t.roomId,startDate:propertyDate((t.occupancyStartDate??t.moveInDate).toMillis(),zone),endDate:t.moveOutDate?propertyDate(t.moveOutDate.toMillis(),zone):null});
     if(!intervals.length)fail('not-found');
     if(d.kind==='utility'){
      try{utilitySource=await utilityInvoiceSource({tx,db,organizationId:d.organizationId,buildingId:d.buildingId,roomId:d.roomId,kind:d.chargeType,readingId:d.readingId,startDate:d.startDate,endDate:d.endDate,ratesId,currency,intervals});}catch(e){fail('failed-precondition',e.message);}
      calculation={...utilitySource.calculation,timeZone:zone};
     }else if(d.kind==='service'){
      try{serviceSource=await serviceInvoiceSource({tx,db,organizationId:d.organizationId,buildingId:d.buildingId,roomId:d.roomId,feeId:d.feeId,tenantId:d.tenantId,startDate:d.startDate,endDate:d.endDate,quantityMilli:d.quantityMilli,ratesId,currency,zone});}catch(e){fail('failed-precondition',e.message);}
      calculation=serviceSource.calculation;
     }else if(d.kind==='period'){
      // Manual lines (discounts, late fees, other) change the price.
      if(d.lines.length&&!allows(m,'overridePrices',scope))fail('permission-denied','period_lines_need_price_authority');
      const leaseRoom=t.buildingId===d.buildingId?t.roomId:history.docs.find(v=>v.data().buildingId===d.buildingId)?.data().roomId??'';
      try{periodSource=await periodInvoiceSource({tx,db,d:{...d,ratesId},tenant:t,intervals,roomId:leaseRoom,ratesId,currency,zone});}catch(e){fail('failed-precondition',e.message);}
      // A surcharge priced differently from the lease is a price change too.
      if(periodSource.surchargeChanged&&!allows(m,'overridePrices',scope))fail('permission-denied','period_lines_need_price_authority');
      calculation=periodSource.calculation;
     }else if(d.kind==='charge'){
      if(!allows(m,'overridePrices',scope))fail('permission-denied');
      const amountMinor=Number((BigInt(d.unitPriceMinor)*BigInt(d.quantityMilli)+500n)/1000n);if(!Number.isSafeInteger(amountMinor)||amountMinor<=0||amountMinor>1e12)fail('invalid-argument');
      calculation={amountMinor,days:0,lines:[],timeZone:zone,startDate:d.startDate,endDate:d.endDate,chargeType:d.chargeType,unitPriceMinor:d.unitPriceMinor,quantityMilli:d.quantityMilli};
     }else{try{calculation=proratedRent({tenant:t,startDate:d.startDate,endDate:d.endDate,intervals,timeZone:zone});}catch(e){fail('failed-precondition',e.message);}}
     if(['tenantRent'].includes(d.kind)&&currency!==(t.currency??'VND')){try{calculation=convertCalculation({...calculation,currency:t.currency??'VND'},currency,await readReferenceRates(tx,db,ratesId));}catch(e){fail('failed-precondition',e.message);}}
     tenantName=t.fullName??'';roomId=['utility','service'].includes(d.kind)?d.roomId:t.buildingId===d.buildingId?t.roomId:history.docs.find(v=>v.data().buildingId===d.buildingId)?.data().roomId??'';sourceRevision=revision(tenant);
    }else{
     const c=b.rentalContract;if(!validContract(c))fail('failed-precondition','invoice_contract_required');contractSnapshot=c;const sourceCurrency=b.currency??'VND';currency=selectCurrency(sourceCurrency);direction=c.direction==='rentIn'?'expense':'income';tenantName=c.partyName;
     try{calculation=proratedRent({tenant:{currency:sourceCurrency,monthlyRentMinor:c.amountMinor},startDate:d.startDate,endDate:d.endDate,intervals:[{startDate:c.startDate,endDate:c.endDate?nextDate(c.endDate):null}],timeZone:zone});}catch(e){fail('failed-precondition',e.message);}
     if(currency!==sourceCurrency){try{calculation=convertCalculation({...calculation,currency:sourceCurrency},currency,await readReferenceRates(tx,db,ratesId));}catch(e){fail('failed-precondition',e.message);}}
     sourceRevision=revision(building);
    }
    if(!['VND','USD'].includes(currency))fail('failed-precondition');
    const totalMinor=calculation.amountMinor+feeKeys.reduce((n,k)=>n+d.feesMinor[k],0);if(!Number.isSafeInteger(totalMinor)||totalMinor>1e12)fail('invalid-argument');
    const quoteRevision=hash([sourceRevision,revision(building),calculation,d.feesMinor,d.dueDate,direction]);
    // Checked at review too, so double billing is explained before anyone presses Create.
    const existing=await tx.get(db.collection('payments').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
    // Quantity extras are separate one-off services; every other kind is billed once per period.
    // Rent and service fees may also sit on a period invoice (B6), and the reverse.
    if(['tenantRent','service','period'].includes(d.kind)&&existing.docs.some(v=>periodConflict(v.data(),{kind:d.kind,tenantId:d.tenantId,roomId,startDate:d.startDate,endDate:d.endDate,includeRent:d.includeRent===true,feeIds:d.kind==='period'?d.serviceFeeIds:d.kind==='service'&&serviceSource.fee.basis!=='quantity'?[d.feeId]:[]})))fail('already-exists','invoice_period_exists');
    if(d.kind==='period'&&calculation.lines.some(l=>l.type==='surcharge'&&existing.docs.some(v=>surchargeBilled(v.data(),{tenantId:d.tenantId,surchargeId:l.surchargeId,frequency:l.frequency,startDate:d.startDate,endDate:d.endDate}))))fail('already-exists','period_surcharge_billed');
    if(d.kind!=='period'&&!(d.kind==='service'&&serviceSource.fee.basis==='quantity')&&existing.docs.some(v=>{const x=v.data();return x.status!=='cancelled'&&x.invoiceKind===d.kind&&(!['charge','utility'].includes(d.kind)||x.type===d.chargeType)&&(d.kind!=='service'||(x.calculation?.feeId===d.feeId&&x.roomId===d.roomId))&&(x.tenantId??null)===d.tenantId&&x.billingStartLocalDate<d.endDate&&x.billingEndLocalDate>d.startDate;}))fail('already-exists','invoice_period_exists');
    if(d.action==='quote')return {record:{...calculation,totalMinor,currency,direction,tenantName,quoteRevision,feesMinor:d.feesMinor,dueDate:d.dueDate}};
    if(d.quoteRevision!==quoteRevision)fail('aborted');
    // Serialize invoice creation against concurrent overlapping periods and property deletion.
    const scale=currency==='USD'?100:1,invoiceId='invoice_'+key;ref=db.doc(`payments/${invoiceId}`);
    const due=propertyDayStart(d.dueDate,zone);if(due===null)fail('invalid-argument');
    patch={organizationId:d.organizationId,buildingId:d.buildingId,roomId,tenantId:d.tenantId,tenantName,invoiceVersion:2,invoiceKind:d.kind,type:d.kind==='tenantRent'?'rent':['charge','utility'].includes(d.kind)?d.chargeType:d.kind==='service'?'service':d.kind==='period'?'period':'buildingRent',direction,currency,amount:calculation.amountMinor/scale,amountMinor:calculation.amountMinor,totalMinor,paidAmount:0,status:'pending',feesMinor:d.feesMinor,...Object.fromEntries(feeKeys.map(k=>[k,d.feesMinor[k]/scale])),billingStartLocalDate:d.startDate,billingEndLocalDate:d.endDate,dueLocalDate:d.dueDate,dueDate:Timestamp.fromMillis(due),timeZone:zone,calculation,contractSnapshot,description:d.reason.trim(),createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid};result={invoiceId};
    if(utilitySource)tx.update(utilitySource.ref,{invoiceId});
    if(periodSource){for(const s of periodSource.utilitySources)tx.update(s.ref,{invoiceId});markBilledAll(tx,periodSource.serviceSources,{organizationId:d.organizationId,buildingId:d.buildingId,roomId,endDate:d.endDate,now});}
    if(serviceSource)markBilled(tx,serviceSource,{organizationId:d.organizationId,buildingId:d.buildingId,roomId:d.roomId,endDate:d.endDate,now});
    tx.create(ref,patch);tx.update(building.ref,{invoiceRevision:(b.invoiceRevision??0)+1});
   }else{
    ref=db.doc(`payments/${d.invoiceId}`);snapshot=await tx.get(ref);old=snapshot.data();if(!old||old.organizationId!==d.organizationId||old.buildingId!==d.buildingId)fail('not-found');
    if(d.action==='read')return {record:projection(snapshot)};
    if(d.action==='history'){
      let q=ref.collection('invoiceHistory').orderBy('createdAt','desc').orderBy('__name__','desc');
      if(d.cursor){const cursor=await tx.get(ref.collection('invoiceHistory').doc(d.cursor));if(!cursor.exists)fail('invalid-argument');q=q.startAfter(cursor);}
      const page=await tx.get(q.limit(21)),rows=page.docs.slice(0,20);return {records:rows.map(doc=>{const x=doc.data();return {id:doc.id,action:x.action,actorId:x.actorId,createdAt:x.createdAt.toDate().toISOString(),reason:x.reason,before:x.before,after:x.after};}),nextCursor:page.size>20?rows.at(-1).id:null};
    }
    if(old.invoiceVersion!==2||d.revision!==revision(snapshot))fail('aborted');
    if(old.status==='cancelled')fail('failed-precondition');
    // B7: a repair expense belongs to its technical problem; only paying/reversing applies.
    if(old.invoiceKind==='repair'&&['edit','void'].includes(d.action))fail('failed-precondition','repair_expense_locked');
    const scale=old.currency==='USD'?100:1,paidMinor=Math.round(old.paidAmount*scale);
    if(d.action==='void'){
     if(paidMinor!==0)fail('failed-precondition','invoice_refund_first');
     // A move-out settlement is final (B6b): its invoice cannot be voided.
     if(old.invoiceKind==='settlement')fail('failed-precondition','settlement_invoice_locked');
     if(old.invoiceKind==='utility'){
      const {meterId}=require('./utility_invoice');
      const readingRef=db.doc(`utilityMeters/${meterId(d.organizationId,old.roomId,old.type)}/readings/${old.calculation.readingId}`),reading=await tx.get(readingRef);
      if(!reading.exists||reading.data().invoiceId!==d.invoiceId)fail('failed-precondition','utility_invoice_link_changed');
      tx.update(readingRef,{invoiceId:null});
     }
     if(old.invoiceKind==='period'){
      // Read every linked reading first, then release them all.
      const {meterId}=require('./utility_invoice');
      const refs=(old.calculation?.utilities??[]).map(u=>db.doc(`utilityMeters/${meterId(d.organizationId,u.roomId,u.kind)}/readings/${u.readingId}`));
      const snaps=[];for(const r of refs)snaps.push(await tx.get(r));
      if(snaps.some(s=>!s.exists||s.data().invoiceId!==d.invoiceId))fail('failed-precondition','utility_invoice_link_changed');
      for(const r of refs)tx.update(r,{invoiceId:null});
     }
     patch={status:'cancelled'};
    }
    if(d.action==='edit'){
     datePolicy(d.dueDate);const totalMinor=old.amountMinor+feeKeys.reduce((n,k)=>n+d.feesMinor[k],0);if(!Number.isSafeInteger(totalMinor)||totalMinor>1e12||totalMinor<paidMinor)fail('failed-precondition');
     const due=propertyDayStart(d.dueDate,old.timeZone);if(due===null)fail('invalid-argument');patch={feesMinor:d.feesMinor,...Object.fromEntries(feeKeys.map(k=>[k,d.feesMinor[k]/scale])),totalMinor,dueLocalDate:d.dueDate,dueDate:Timestamp.fromMillis(due),status:paidMinor===totalMinor?'paid':paidMinor===0?'pending':'partial'};
    }
    if(['payExpense','reverseExpense'].includes(d.action)){
     if(old.direction!=='expense')fail('failed-precondition');const paying=d.action==='payExpense';if(d.amountMinor>(paying?old.totalMinor-paidMinor:paidMinor))fail('failed-precondition');const next=paidMinor+(paying?d.amountMinor:-d.amountMinor);patch={paidAmount:next/scale,status:next===old.totalMinor?'paid':next===0?'pending':'partial',...(paying?{paidAt:now,paidBy:uid,paymentMethod:d.paymentMethod}:{lastRefundedAt:now,lastRefundedBy:uid})};
    }
    result={invoiceId:d.invoiceId};tx.update(ref,{...patch,updatedAt:now,updatedBy:uid});
   }
   tx.create(op,{organizationId:d.organizationId,buildingId:d.buildingId,actorId:uid,action:d.action,createdAt:now,reason:d.reason,fingerprint,result,before:old?{totalMinor:old.totalMinor,paidAmount:old.paidAmount,status:old.status,feesMinor:old.feesMinor,dueDate:old.dueLocalDate}:null,after:{totalMinor:patch.totalMinor??old?.totalMinor,paidAmount:patch.paidAmount??old?.paidAmount??0,status:patch.status??old?.status},...(d.amountMinor?{amountMinor:d.amountMinor,paymentMethod:d.paymentMethod}:{})});
   tx.create(ref.collection('invoiceHistory').doc(key),{organizationId:d.organizationId,actorId:uid,createdAt:now,action:d.action,reason:d.reason,before:old?{totalMinor:old.totalMinor,paidAmount:old.paidAmount,status:old.status,feesMinor:old.feesMinor,dueDate:old.dueLocalDate}:null,after:{totalMinor:patch.totalMinor??old?.totalMinor,paidAmount:patch.paidAmount??old?.paidAmount??0,status:patch.status??old?.status}});
   tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'invoice_'+d.action,targetId:result.invoiceId,createdAt:now,before:null,after:{buildingId:d.buildingId,direction:patch.direction??old.direction,status:patch.status}});
   return result;
  });
 };
}
module.exports={createInvoiceHandler};
