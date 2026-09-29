'use strict';
const {createHash}=require('node:crypto');
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
  const d=request.data||{},uid=request.auth?.uid,write=['create','edit','void','payExpense','reverseExpense'].includes(d.action);
  if(!uid)fail('unauthenticated');
  const keys=['action','organizationId','buildingId',...(['read','history','edit','void','payExpense','reverseExpense'].includes(d.action)?['invoiceId']:[]),...(['list','history'].includes(d.action)?['cursor']:[]),...(['quote','create'].includes(d.action)?['kind','tenantId','startDate','endDate','dueDate','feesMinor','reason',...(d.kind==='charge'?['chargeType','unitPriceMinor','quantityMilli']:[])]:[]),...(write?['operationId']:[]),...(['edit','void','payExpense','reverseExpense'].includes(d.action)?['revision','reason']:[]),...(d.action==='create'?['quoteRevision']:[]),...(d.action==='edit'?['feesMinor','dueDate']:[]),...(['payExpense','reverseExpense'].includes(d.action)?['amountMinor','paymentMethod']:[])];
  if(!['list','read','history','quote','create','edit','void','payExpense','reverseExpense','tenants'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||Object.keys(d).some(k=>!keys.includes(k))||(keys.includes('invoiceId')&&!id(d.invoiceId))||(d.cursor!=null&&!id(d.cursor))||(write&&!id(d.operationId)))fail('invalid-argument');
  if(keys.includes('reason')&&(typeof d.reason!=='string'||!d.reason.trim()||d.reason.length>1000))fail('invalid-argument');
  if(keys.includes('revision')&&(typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)))fail('invalid-argument');
  if(keys.includes('feesMinor')&&(!d.feesMinor||Object.keys(d.feesMinor).length!==feeKeys.length||feeKeys.some(k=>!Number.isSafeInteger(d.feesMinor[k])||d.feesMinor[k]<0||d.feesMinor[k]>1e12)))fail('invalid-argument');
  if(keys.includes('dueDate')&&!validDate(d.dueDate))fail('invalid-argument');
  if(['quote','create'].includes(d.action)&&(!['tenantRent','buildingRent','charge'].includes(d.kind)||(d.kind==='buildingRent'?d.tenantId!==null:!id(d.tenantId))||!validDate(d.startDate)||!validDate(d.endDate)||d.endDate<=d.startDate))fail('invalid-argument');
  if(d.kind==='charge'&&(!['electricity','water','internet','parking','maintenance','deposit','penalty','other'].includes(d.chargeType)||!Number.isSafeInteger(d.unitPriceMinor)||d.unitPriceMinor<=0||d.unitPriceMinor>1e12||!Number.isSafeInteger(d.quantityMilli)||d.quantityMilli<=0||d.quantityMilli>1e9))fail('invalid-argument');
  if(['payExpense','reverseExpense'].includes(d.action)&&(!Number.isSafeInteger(d.amountMinor)||d.amountMinor<=0||!['cash','bankTransfer','momo','zalopay','creditCard','other'].includes(d.paymentMethod)))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),m=member.data(),scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||!allows(m,'readFinancialReports',scope))fail('permission-denied');
   if((write||d.action==='quote')&&!allows(m,'collectPayments',scope))fail('permission-denied');
   if(['edit','void'].includes(d.action)&&!allows(m,'overridePrices',scope))fail('permission-denied');
   if(d.action==='reverseExpense'&&!allows(m,'refundPayments',scope))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`)),b=building.data();if(!b||b.organizationId!==d.organizationId)fail('not-found');
   const zone=b.timeZone,now=Timestamp.now(),today=propertyDate(now.toMillis(),zone);if(!validZone(zone)||!today)fail('failed-precondition','lease_property_timezone_required');
   const key=write?hash(['invoice',d.organizationId,uid,d.operationId]):null,op=write?db.doc(`invoiceOperations/${key}`):null,prior=write?await tx.get(op):null,fingerprint=hash(keys.map(k=>d[k]));
   if(prior?.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
   const projection=doc=>{const x=doc.data();return {id:doc.id,revision:revision(doc),kind:x.invoiceKind??null,direction:x.direction??'income',tenantId:x.tenantId??null,tenantName:x.tenantName??'',currency:x.currency,status:x.status,amountMinor:x.amountMinor??null,totalMinor:x.totalMinor??null,paidMinor:Math.round(x.paidAmount*(x.currency==='USD'?100:1)),startDate:x.billingStartLocalDate??null,endDate:x.billingEndLocalDate??null,dueDate:x.dueLocalDate??null,feesMinor:x.feesMinor??null,calculation:x.calculation??null,notes:x.description??'',canEdit:x.invoiceVersion===2&&allows(m,'overridePrices',scope),canSettle:x.direction==='expense'&&allows(m,'collectPayments',scope),canReverse:x.direction==='expense'&&allows(m,'refundPayments',scope)};};
   if(d.action==='list'){
    let q=db.collection('payments').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId).orderBy('__name__');if(d.cursor)q=q.startAfter(d.cursor);const page=await tx.get(q.limit(26)),rows=page.docs.slice(0,25);return {records:rows.map(projection),nextCursor:page.size>25?rows.at(-1).id:null,canCreate:allows(m,'collectPayments',scope),canPrice:allows(m,'overridePrices',scope)};
   }
   if(d.action==='tenants'){
    const rows=await tx.get(db.collection('tenants').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
    const past=await tx.get(db.collection('leaseOccupancy').where('buildingId','==',d.buildingId));const known=new Map(rows.docs.map(v=>[v.id,v]));
    for(const h of past.docs){if(h.data().organizationId!==d.organizationId||known.has(h.data().tenantId))continue;const tenant=await tx.get(db.doc(`tenants/${h.data().tenantId}`));if(tenant.exists&&tenant.data().organizationId===d.organizationId)known.set(tenant.id,tenant);}
    return {records:[...known.values()].filter(v=>v.data().isMainTenant===true).map(v=>({id:v.id,fullName:v.data().fullName??'',roomId:v.data().roomId,currency:v.data().currency??'VND'})),today,timeZone:zone,currency:b.currency??'VND'};
   }
   const datePolicy=date=>{if(date<today&&!['owner','administrator'].includes(m.role))fail('permission-denied','invoice_backdate_owner_required');};
   let ref,snapshot,old,patch,result;
   if(['quote','create'].includes(d.action)){
    datePolicy(d.startDate);datePolicy(d.dueDate);
    if(feeKeys.some(k=>d.feesMinor[k]>0)&&!allows(m,'overridePrices',scope))fail('permission-denied');
    let calculation,currency,roomId='',tenantName='',sourceRevision,direction='income',contractSnapshot=null;
    if(d.kind==='tenantRent'||d.kind==='charge'){
     const tenant=await tx.get(db.doc(`tenants/${d.tenantId}`)),t=tenant.data();if(!t||t.organizationId!==d.organizationId||t.isMainTenant!==true)fail('not-found');
     const history=await tx.get(db.collection('leaseOccupancy').where('tenantId','==',d.tenantId));
     const intervals=history.docs.filter(v=>v.data().organizationId===d.organizationId&&v.data().buildingId===d.buildingId).map(v=>({startDate:propertyDate(v.data().start.toMillis(),zone),endDate:propertyDate(v.data().end.toMillis(),zone)}));
     if(t.buildingId===d.buildingId)intervals.push({startDate:propertyDate((t.occupancyStartDate??t.moveInDate).toMillis(),zone),endDate:t.moveOutDate?propertyDate(t.moveOutDate.toMillis(),zone):null});
     if(!intervals.length)fail('not-found');
     if(d.kind==='charge'){
      if(!allows(m,'overridePrices',scope))fail('permission-denied');
      const amountMinor=Number((BigInt(d.unitPriceMinor)*BigInt(d.quantityMilli)+500n)/1000n);if(!Number.isSafeInteger(amountMinor)||amountMinor<=0||amountMinor>1e12)fail('invalid-argument');
      calculation={amountMinor,days:0,lines:[],timeZone:zone,startDate:d.startDate,endDate:d.endDate,chargeType:d.chargeType,unitPriceMinor:d.unitPriceMinor,quantityMilli:d.quantityMilli};
     }else{try{calculation=proratedRent({tenant:t,startDate:d.startDate,endDate:d.endDate,intervals,timeZone:zone});}catch(e){fail('failed-precondition',e.message);}}
     currency=t.currency??'VND';tenantName=t.fullName??'';roomId=t.buildingId===d.buildingId?t.roomId:history.docs.find(v=>v.data().buildingId===d.buildingId)?.data().roomId??'';sourceRevision=revision(tenant);
    }else{
     const c=b.rentalContract;if(!validContract(c))fail('failed-precondition','invoice_contract_required');contractSnapshot=c;currency=b.currency??'VND';direction=c.direction==='rentIn'?'expense':'income';tenantName=c.partyName;
     try{calculation=proratedRent({tenant:{currency,monthlyRentMinor:c.amountMinor},startDate:d.startDate,endDate:d.endDate,intervals:[{startDate:c.startDate,endDate:c.endDate?nextDate(c.endDate):null}],timeZone:zone});}catch(e){fail('failed-precondition',e.message);}
     sourceRevision=revision(building);
    }
    if(!['VND','USD'].includes(currency))fail('failed-precondition');
    const totalMinor=calculation.amountMinor+feeKeys.reduce((n,k)=>n+d.feesMinor[k],0);if(!Number.isSafeInteger(totalMinor)||totalMinor>1e12)fail('invalid-argument');
    const quoteRevision=hash([sourceRevision,revision(building),calculation,d.feesMinor,d.dueDate,direction]);
    if(d.action==='quote')return {record:{...calculation,totalMinor,currency,direction,tenantName,quoteRevision,feesMinor:d.feesMinor,dueDate:d.dueDate}};
    if(d.quoteRevision!==quoteRevision)fail('aborted');
    const existing=await tx.get(db.collection('payments').where('organizationId','==',d.organizationId).where('buildingId','==',d.buildingId));
    if(existing.docs.some(v=>{const x=v.data();return x.status!=='cancelled'&&x.invoiceKind===d.kind&&(d.kind!=='charge'||x.type===d.chargeType)&&(x.tenantId??null)===d.tenantId&&x.billingStartLocalDate<d.endDate&&x.billingEndLocalDate>d.startDate;}))fail('already-exists','invoice_period_exists');
    // Serialize invoice creation against concurrent overlapping periods and property deletion.
    const scale=currency==='USD'?100:1,invoiceId='invoice_'+key;ref=db.doc(`payments/${invoiceId}`);
    const due=propertyDayStart(d.dueDate,zone);if(due===null)fail('invalid-argument');
    patch={organizationId:d.organizationId,buildingId:d.buildingId,roomId,tenantId:d.tenantId,tenantName,invoiceVersion:2,invoiceKind:d.kind,type:d.kind==='tenantRent'?'rent':d.kind==='charge'?d.chargeType:'buildingRent',direction,currency,amount:calculation.amountMinor/scale,amountMinor:calculation.amountMinor,totalMinor,paidAmount:0,status:'pending',feesMinor:d.feesMinor,...Object.fromEntries(feeKeys.map(k=>[k,d.feesMinor[k]/scale])),billingStartLocalDate:d.startDate,billingEndLocalDate:d.endDate,dueLocalDate:d.dueDate,dueDate:Timestamp.fromMillis(due),timeZone:zone,calculation,contractSnapshot,description:d.reason.trim(),createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid};result={invoiceId};
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
    const scale=old.currency==='USD'?100:1,paidMinor=Math.round(old.paidAmount*scale);
    if(d.action==='void'){if(paidMinor!==0)fail('failed-precondition','invoice_refund_first');patch={status:'cancelled'};}
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
