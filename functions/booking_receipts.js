'use strict';
// Short-stay payment list (2026-10-24, Tom). Every "lần thanh toán" is one payments document with a bookingId:
// a day, a type (tiền cọc / tiền phòng / phụ thu / khác / hoàn tiền), the amount, how it was paid (a method from the
// organization's list), and who received it: the staff member for cash, the receiving account otherwise.
// When the customer hands over more than is still owed, only what is owed is recorded and the change (tiền thối) is kept
// on the payment. Older bookings keep their payments; they show and edit the same way (their effect is inferred).
// Adding needs "Thu tiền", a refund needs "Hoàn tiền", changing a recorded one needs "Sửa lần thanh toán"; the server
// checks all of them again. Every add and edit goes to activity history with what it was before and after.
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {localTime}=require('./booking_quote');
const {readReferenceRates,convertMinor}=require('./reference_rates');

const KINDS=['deposit','room','surcharge','other','refund'];
const BUILTIN_METHODS=['cash','bankTransfer'];
const MAX_METHODS=30;
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const plain=v=>!!v&&typeof v==='object'&&!Array.isArray(v);
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const scaleOf=currency=>currency==='USD'?100:1;
const minor=(value,scale)=>Math.round((Number(value)||0)*scale);
const localDay=(instant,zone)=>{const p=Object.fromEntries(new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(instant)).map(x=>[x.type,x.value]));return `${p.year}-${p.month}-${p.day}`;};
const RECEIPT_KEYS=['kind','refundFrom','paidOn','amountMinor','methodId','methodLabel','accountId','receivedById','note','inputCurrency','inputAmountMinor','ratesId'];

/** Checks the shape of one payment typed in the dialog. Throws the reason key. */
function checkShape(x){
 const bad=()=>{throw Object.assign(new Error('booking_invalid_request'),{code:'invalid-argument'});};
 if(!plain(x)||Object.keys(x).some(k=>!RECEIPT_KEYS.includes(k)))bad();
 if(!KINDS.includes(x.kind))bad();
 if(x.kind==='refund'?!['deposit','room'].includes(x.refundFrom):x.refundFrom!==undefined)bad();
 if(typeof x.paidOn!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(x.paidOn))bad();
 if(!Number.isSafeInteger(x.amountMinor)||x.amountMinor<=0||x.amountMinor>1e12)bad();
 if(!id(x.methodId))bad();
 // A way of paying typed once and not kept in the list (2026-10-24, Tom): methodId "other" with its name.
 if(x.methodId==='other'?typeof x.methodLabel!=='string'||!x.methodLabel.trim()||x.methodLabel.trim().length>40:x.methodLabel!==undefined)bad();
 if(x.accountId!==undefined&&!id(x.accountId))bad();
 if(x.receivedById!==undefined&&!id(x.receivedById))bad();
 if(x.methodId==='cash'?x.accountId!==undefined:x.receivedById!==undefined)bad();
 if(x.note!==undefined&&(typeof x.note!=='string'||x.note.length>500))bad();
 if(x.inputCurrency!==undefined&&(!['VND','USD'].includes(x.inputCurrency)||!Number.isSafeInteger(x.inputAmountMinor)||x.inputAmountMinor<=0||x.inputAmountMinor>1e12))bad();
 if(x.inputCurrency===undefined&&(x.inputAmountMinor!==undefined||x.ratesId!==undefined))bad();
 return x;
}

/** The organization's own payment methods (besides cash and bank transfer). */
async function readMethods(tx,db,organizationId){
 const doc=await tx.get(db.doc(`orgPaymentMethods/${organizationId}`));
 const list=doc.exists&&doc.data().organizationId===organizationId&&Array.isArray(doc.data().methods)?doc.data().methods:[];
 return list.filter(m=>plain(m)&&id(m.id)&&typeof m.label==='string').map(m=>({id:m.id,label:m.label}));
}

/** The type of a payment. Older payments have no receiptKind: it is worked out from how they were written. */
function kindOf(p){
 if(KINDS.includes(p.receiptKind))return p.receiptKind;
 if(p.status==='refunded')return 'refund';
 if(p.bookingDeposit||p.type==='deposit')return 'deposit';
 return 'room';
}
/** What a payment did to the booking, in minor units: paid (counts toward the total), deposit (the part of paid that
 *  is deposit), held / heldRefunded (deposits taken with the old "Thu cọc" button, kept apart from the total). */
function effectOf(p,scale){
 if(plain(p.receiptEffect))return {paid:p.receiptEffect.paid??0,deposit:p.receiptEffect.deposit??0,held:p.receiptEffect.held??0,heldRefunded:p.receiptEffect.heldRefunded??0};
 const zero={paid:0,deposit:0,held:0,heldRefunded:0};
 if(p.status==='refunded'){const a=minor(p.amount,scale);return p.type==='deposit'?{...zero,heldRefunded:a}:{...zero,paid:-a};}
 const a=minor(p.paidAmount,scale);
 if(p.bookingDeposit)return {...zero,paid:a,deposit:a};
 if(p.type==='deposit')return {...zero,held:a};
 return {...zero,paid:a};
}
/** The booking's money now, in minor units. */
function balancesOf(b,scale){
 return {total:minor(b.totalPrice,scale),paid:minor(b.paidAmount,scale),
  deposit:b.depositReceivedAmount!=null?minor(b.depositReceivedAmount,scale):(plain(b.depositPayment)?minor(b.depositPayment.amount,scale):0),
  held:minor(b.depositPaidAmount,scale),heldRefunded:minor(b.depositRefundedAmount,scale)};
}
const add=(bal,e,sign=1)=>({...bal,paid:bal.paid+sign*e.paid,deposit:bal.deposit+sign*e.deposit,held:bal.held+sign*e.held,heldRefunded:bal.heldRefunded+sign*e.heldRefunded});

/** What a new (or changed) payment records: the amount, the change given back and its effect. Throws a reason key. */
function plan(bal,x){
 const fail=(code,key)=>{throw Object.assign(new Error(key),{code});};
 const zero={paid:0,deposit:0,held:0,heldRefunded:0};
 if(x.kind!=='refund'){
  const owed=bal.total-bal.paid;
  if(owed<=0)fail('failed-precondition','booking_nothing_owed');
  const recorded=Math.min(x.amountMinor,owed);
  return {recorded,change:x.amountMinor-recorded,effect:{...zero,paid:recorded,deposit:x.kind==='deposit'?recorded:0}};
 }
 const a=x.amountMinor;
 if(x.refundFrom==='deposit'){
  const heldLeft=bal.held-bal.heldRefunded;
  if(heldLeft>0){if(a>heldLeft)fail('invalid-argument','booking_refund_exceeds_deposit');return {recorded:a,change:0,effect:{...zero,heldRefunded:a}};}
  if(a>bal.deposit)fail('invalid-argument','booking_refund_exceeds_deposit');
  return {recorded:a,change:0,effect:{...zero,paid:-a,deposit:-a}};
 }
 if(a>bal.paid-bal.deposit)fail('invalid-argument','booking_refund_exceeds_payment');
 return {recorded:a,change:0,effect:{...zero,paid:-a}};
}
const sane=b=>b.paid>=0&&b.deposit>=0&&b.deposit<=b.paid&&b.paid<=b.total&&b.heldRefunded>=0&&b.heldRefunded<=b.held;

/** The method, the person or account that received the money, checked against the organization. Keeps names of an
 *  unchanged method, person or account even if it was renamed or removed since. */
async function parties(tx,db,{organizationId,org,x,old,methods}){
 const fail=(code,key)=>{throw Object.assign(new Error(key),{code});};
 let methodLabel=null;
 if(x.methodId==='other')methodLabel=x.methodLabel.trim().replace(/\s+/g,' ');
 else if(!BUILTIN_METHODS.includes(x.methodId)){
  const found=methods.find(m=>m.id===x.methodId);
  if(found)methodLabel=found.label;
  else if(old?.methodId===x.methodId)methodLabel=old.methodLabel??null;
  else fail('invalid-argument','booking_method_invalid');
 }
 const out={methodId:x.methodId,methodLabel,paymentMethod:BUILTIN_METHODS.includes(x.methodId)?x.methodId:'other'};
 if(x.receivedById!==undefined){
  if(old?.receivedById===x.receivedById)out.receivedBy={id:x.receivedById,name:old.receivedByName??''};
  else{
   const s=await tx.get(db.doc(`staffProfiles/${x.receivedById}`));
   if(!s.exists||s.data().organizationId!==organizationId||s.data().employmentStatus==='inactive')fail('invalid-argument','booking_staff_invalid');
   out.receivedBy={id:x.receivedById,name:String(s.data().displayName??'')};
  }
 }
 if(x.accountId!==undefined){
  if(old?.receivedAccountId===x.accountId)out.account={id:x.accountId,label:old.receivedAccountLabel??''};
  else{
   const found=(Array.isArray(org.paymentAccounts)?org.paymentAccounts:[]).find(a=>plain(a)&&a.id===x.accountId);
   if(!found)fail('invalid-argument','booking_account_invalid');
   out.account={id:found.id,label:String(found.label??'')};
  }
 }
 return out;
}

/** The amount typed in another currency than the booking's must convert to exactly the amount sent. */
async function originalInput(tx,db,{x,org,currency}){
 const fail=(code,key)=>{throw Object.assign(new Error(key),{code});};
 if(x.inputCurrency===undefined)return null;
 if(x.inputCurrency!==(org.displayCurrency??currency))fail('failed-precondition','booking_currency_changed');
 let amount=x.inputAmountMinor;
 if(x.inputCurrency!==currency){
  try{amount=convertMinor(amount,x.inputCurrency,currency,await readReferenceRates(tx,db,x.ratesId));}catch(e){fail('failed-precondition',e.message);}
 }
 if(amount!==x.amountMinor)fail('invalid-argument','booking_invalid_conversion');
 return {currency:x.inputCurrency,amountMinor:x.inputAmountMinor,...(x.ratesId?{exchangeRateSnapshotId:x.ratesId}:{})};
}

/** A payment day: up to today in the property's time, at most 400 days back. Today's payment is timed now. */
function paidAtFor(paidOn,zone,nowMs,fail){
 const today=localDay(nowMs,zone),noon=localTime(`${paidOn} 12:00`,zone);
 if(noon===null||paidOn>today||nowMs-noon>400*86400000)fail('invalid-argument','booking_payment_date');
 return paidOn===today?nowMs:noon;
}

/** The payments document for one lần thanh toán. */
function receiptDoc({booking,bookingId,x,who,recorded,change,effect,paidAt,scale,input,uid,now,Timestamp,old}){
 const refund=x.kind==='refund',heldRefund=refund&&effect.heldRefunded>0;
 const note=typeof x.note==='string'?x.note.trim():'';
 const doc={
  ...(old??{}),
  organizationId:booking.organizationId,buildingId:booking.buildingId,roomId:booking.roomId,tenantId:null,tenantName:booking.guestName??'',bookingId,
  type:heldRefund?'deposit':'hourlyRent',bookingDeposit:x.kind==='deposit',status:refund?'refunded':'paid',
  amount:recorded/scale,paidAmount:refund?0:recorded/scale,currency:booking.currency||'VND',
  paymentMethod:who.paymentMethod,methodId:who.methodId,methodLabel:who.methodLabel,
  receivedAccountId:who.account?.id??null,receivedAccountLabel:who.account?.label??null,
  receivedById:who.receivedBy?.id??null,receivedByName:who.receivedBy?.name??null,
  tenderedAmount:refund?null:(recorded+change)/scale,changeAmount:refund?null:change/scale,
  receiptKind:x.kind,refundFrom:refund?x.refundFrom:null,receiptEffect:effect,paidOn:x.paidOn,paidAt:Timestamp.fromMillis(paidAt),
  notes:note,dueDate:booking.endTime??null,billingStartDate:booking.startTime??null,billingEndDate:booking.endTime??null,
  descriptionKey:x.kind==='deposit'?'booking_deposit_payment':refund&&x.refundFrom==='deposit'?'booking_deposit_refund':'booking_payment',
  ...(old?{updatedAt:now,updatedBy:uid}:{createdAt:now,createdBy:uid}),
 };
 if(input)doc.originalInput=input;else if(old&&(minor(old.amount,scale)!==recorded))delete doc.originalInput;
 return doc;
}
/** The booking fields after the payments changed. */
function bookingPatch(bal,scale){
 return {paidAmount:bal.paid/scale,depositReceivedAmount:bal.deposit/scale,depositPaidAmount:bal.held/scale,depositRefundedAmount:bal.heldRefunded/scale,depositRefunded:bal.held>0&&bal.heldRefunded===bal.held};
}
/** One row of the payment list. */
function project(doc,scale,zone){
 const p=doc.data(),kind=kindOf(p);
 const day=typeof p.paidOn==='string'&&p.paidOn?p.paidOn:(p.paidAt?.toMillis?localDay(p.paidAt.toMillis(),zone):'');
 const row={paymentId:doc.id,kind,refundFrom:kind==='refund'?(p.refundFrom??(p.type==='deposit'?'deposit':'room')):null,paidOn:day,
  amountMinor:minor(kind==='refund'?p.amount:p.paidAmount,scale),
  tenderedMinor:p.tenderedAmount!=null?minor(p.tenderedAmount,scale):null,changeMinor:p.changeAmount!=null?minor(p.changeAmount,scale):null,
  methodId:p.methodId??(['cash','bankTransfer'].includes(p.paymentMethod)?p.paymentMethod:null),paymentMethod:p.paymentMethod??'cash',methodLabel:p.methodLabel??null,
  accountId:p.receivedAccountId&&p.receivedAccountId!=='cash'?p.receivedAccountId:null,accountLabel:p.receivedAccountId&&p.receivedAccountId!=='cash'?p.receivedAccountLabel??'':null,
  receivedById:p.receivedById??null,receivedByName:p.receivedByName??null,note:String(p.notes??''),
  // What it did to the amount paid (+ payment, − refund; 0 for a deposit kept apart), for "Còn lại" on each row.
  paidEffectMinor:effectOf(p,scale).paid,
  createdAt:p.createdAt?.toMillis?.()??null};
 row.revision=hash([row,p.updatedAt?.toMillis?.()??null]);
 return row;
}
/** What history keeps of a payment (no guest details). */
const snapshot=r=>r&&{kind:r.kind,refundFrom:r.refundFrom,paidOn:r.paidOn,amountMinor:r.amountMinor,tenderedMinor:r.tenderedMinor,changeMinor:r.changeMinor,method:r.methodLabel??r.methodId,receivedBy:r.receivedByName,account:r.accountLabel,note:r.note};

/** Payments of a booking that belong on its list (expenses and other organizations' records left out). */
async function listDocs(tx,db,booking,bookingId){
 const q=await tx.get(db.collection('payments').where('bookingId','==',bookingId));
 return q.docs.filter(d=>{const p=d.data();return p.organizationId===booking.organizationId&&p.direction!=='expense'&&['paid','refunded','partial'].includes(p.status)&&(p.status==='refunded'?minor(p.amount,100)>0:minor(p.paidAmount,100)>0);})
  .sort((a,b)=>(a.data().paidAt?.toMillis?.()??0)-(b.data().paidAt?.toMillis?.()??0)||(a.data().createdAt?.toMillis?.()??0)-(b.data().createdAt?.toMillis?.()??0)||a.id.localeCompare(b.id));
}

function createReceiptsHandler({db,Timestamp,HttpsError,FieldValue}){
 const fail=(code,key='booking_'+code)=>{throw new HttpsError(code,key);};
 const rethrow=e=>{if(e instanceof HttpsError||!e?.code)throw e;fail(e.code,e.message);};
 return async request=>{
  const d=request.data||{},uid=request.auth?.uid;if(!uid)fail('unauthenticated');
  const keys={receipts:['bookingId'],receipt:['bookingId','paymentId','receiptRevision','operationId',...RECEIPT_KEYS],removeReceipt:['bookingId','paymentId','receiptRevision','operationId'],paymentMethod:['operationId','label']}[d.action];
  if(!keys||Object.keys(d).some(k=>!['action','organizationId','buildingId',...keys].includes(k))||!id(d.organizationId)||!id(d.buildingId))fail('invalid-argument');
  if(d.action!=='paymentMethod'&&!id(d.bookingId))fail('invalid-argument');
  if(d.action!=='receipts'&&!id(d.operationId))fail('invalid-argument');
  if(d.action==='removeReceipt'&&(!id(d.paymentId)||typeof d.receiptRevision!=='string'))fail('invalid-argument');
  if(d.action==='receipt'){try{checkShape(Object.fromEntries(RECEIPT_KEYS.filter(k=>d[k]!==undefined).map(k=>[k,d[k]])));}catch(e){rethrow(e);}if(d.paymentId!==undefined&&(!id(d.paymentId)||typeof d.receiptRevision!=='string'))fail('invalid-argument');if(d.paymentId===undefined&&d.receiptRevision!==undefined)fail('invalid-argument');}
  if(d.action==='paymentMethod'&&(typeof d.label!=='string'||!d.label.trim()||d.label.trim().length>40))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const [org,member,building]=await Promise.all([tx.get(db.doc(`organizations/${d.organizationId}`)),tx.get(db.doc(`memberships/${uid}_${d.organizationId}`)),tx.get(db.doc(`buildings/${d.buildingId}`))]);
   const m=member.data(),scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||!building.exists||building.data().organizationId!==d.organizationId)fail('permission-denied');
   const zone=building.data().timeZone,now=Timestamp.now();
   // A new way of paying (Thanh toán bằng → Thêm cách mới): kept for the whole organization. Same name = the same one.
   if(d.action==='paymentMethod'){
    if(!allows(m,'collectPayments',scope))fail('permission-denied');
    const ref=db.doc(`orgPaymentMethods/${d.organizationId}`),list=await readMethods(tx,db,d.organizationId);
    const label=d.label.trim().replace(/\s+/g,' '),key=label.toLocaleLowerCase('vi');
    const builtinNames={cash:['tiền mặt','cash'],bankTransfer:['chuyển khoản','bank transfer','transfer']};
    const builtin=Object.entries(builtinNames).find(([,names])=>names.includes(key));
    if(builtin)return {methodId:builtin[0],methods:list};
    const same=list.find(x=>x.label.toLocaleLowerCase('vi')===key);
    if(same)return {methodId:same.id,methods:list};
    if(list.length>=MAX_METHODS)fail('failed-precondition','booking_methods_full');
    const methodId='m_'+hash([d.organizationId,key]).slice(0,16),next=[...list,{id:methodId,label}];
    tx.set(ref,{organizationId:d.organizationId,methods:next,updatedAt:now,updatedBy:uid});
    return {methodId,methods:next};
   }
   // Payments need "Thu tiền" (adding) or "Sửa lần thanh toán" (changing) before anything about the booking is read.
   if((d.action==='receipt'||d.action==='removeReceipt')&&!allows(m,d.paymentId!==undefined?'editBookingPayments':'collectPayments',scope))fail('permission-denied');
   const bookingRef=db.doc(`bookings/${d.bookingId}`),bookingDoc=await tx.get(bookingRef),booking=bookingDoc.data();
   if(!booking||booking.organizationId!==d.organizationId||booking.buildingId!==d.buildingId||!allows(m,'readBookings',{...scope,record:booking}))fail('not-found');
   const scale=scaleOf(booking.currency||'VND');
   if(d.action==='receipts'){
    const docs=await listDocs(tx,db,booking,d.bookingId),bal=balancesOf(booking,scale);
    return {records:docs.map(x=>project(x,scale,zone)),currency:booking.currency||'VND',totalMinor:bal.total,paidMinor:bal.paid,remainingMinor:Math.max(0,bal.total-bal.paid),
     heldDepositMinor:bal.held-bal.heldRefunded,depositMinor:bal.deposit,
     canCollect:allows(m,'collectPayments',scope),canRefund:allows(m,'refundPayments',scope),canEdit:allows(m,'editBookingPayments',scope)};
   }
   // removeReceipt: a payment recorded by mistake (2026-10-24, Tom). The payment is kept as cancelled (no money),
   // the booking's totals go back, and history keeps what it was. Needs "Sửa lần thanh toán" (and "Hoàn tiền" for a refund).
   if(d.action==='removeReceipt'){
    const opRef=db.doc(`bookingOperations/${hash(['removeReceipt',d.organizationId,uid,d.operationId])}`),fingerprint=hash(d);
    const prior=await tx.get(opRef);
    if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition','booking_operation_reused');return prior.data().result;}
    const ref=db.doc(`payments/${d.paymentId}`),s=await tx.get(ref),old=s.data();
    if(!old||old.bookingId!==d.bookingId||old.organizationId!==d.organizationId||!['paid','refunded','partial'].includes(old.status))fail('not-found');
    const row=project(s,scale,zone);
    if(row.revision!==d.receiptRevision)fail('aborted','booking_changed');
    if(row.kind==='refund'&&!allows(m,'refundPayments',scope))fail('permission-denied');
    const after=add(balancesOf(booking,scale),effectOf(old,scale),-1);
    if(!sane(after))fail('failed-precondition','booking_payment_balance');
    const zero={paid:0,deposit:0,held:0,heldRefunded:0};
    tx.set(ref,{...old,status:'cancelled',paidAmount:0,receiptEffect:zero,removedAt:now,removedBy:uid,updatedAt:now,updatedBy:uid});
    const patch={...bookingPatch(after,scale),updatedAt:now};
    if(plain(booking.depositPayment)&&booking.depositPayment.paymentId===d.paymentId)patch.depositPayment=null;
    if(Array.isArray(booking.rentPayments)&&booking.rentPayments.some(r=>r?.paymentId===d.paymentId))patch.rentPayments=booking.rentPayments.filter(r=>r?.paymentId!==d.paymentId);
    tx.update(bookingRef,patch);
    if(FieldValue)tx.update(db.doc(`rooms/${booking.roomId}`),{bookingRevision:FieldValue.increment(1)});
    const result={paymentId:d.paymentId,removed:true};
    tx.create(db.doc(`teamActivity/${opRef.id}`),{organizationId:d.organizationId,actorId:uid,action:'booking_receipt_delete',targetId:d.bookingId,paymentId:d.paymentId,createdAt:now,before:snapshot(row),after:null});
    tx.create(opRef,{organizationId:d.organizationId,actorId:uid,createdAt:now,fingerprint,result});
    return result;
   }
   // receipt: add one, or change one already recorded.
   const opRef=db.doc(`bookingOperations/${hash(['receipt',d.organizationId,uid,d.operationId])}`),fingerprint=hash(d);
   const prior=await tx.get(opRef);
   const x=Object.fromEntries(RECEIPT_KEYS.filter(k=>d[k]!==undefined).map(k=>[k,d[k]]));
   const editing=d.paymentId!==undefined;
   const need=editing?'editBookingPayments':'collectPayments';
   if(!allows(m,need,scope)||(x.kind==='refund'&&!allows(m,'refundPayments',scope)))fail('permission-denied');
   if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition','booking_operation_reused');return prior.data().result;}
   let oldRef=null,oldDoc=null,oldRow=null;
   if(editing){
    oldRef=db.doc(`payments/${d.paymentId}`);const s=await tx.get(oldRef);oldDoc=s.data();
    if(!oldDoc||oldDoc.bookingId!==d.bookingId||oldDoc.organizationId!==d.organizationId)fail('not-found');
    oldRow=project(s,scale,zone);
    if(oldRow.revision!==d.receiptRevision)fail('aborted','booking_changed');
    if(oldRef&&(kindOf(oldDoc)==='refund')!==(x.kind==='refund'))fail('invalid-argument','booking_invalid_request');
    if(kindOf(oldDoc)==='refund'&&!allows(m,'refundPayments',scope))fail('permission-denied');
   }else if(x.kind!=='refund'&&['cancelled','noShow'].includes(booking.status))fail('failed-precondition','booking_invalid_transition');
   // The deposit is part of the payment (2026-10-24, Tom): it is given back only when the booking is cancelled.
   if(!editing&&x.kind==='refund'&&x.refundFrom==='deposit'&&!['cancelled','noShow'].includes(booking.status))fail('failed-precondition','booking_deposit_refund_cancelled_only');
   let bal=balancesOf(booking,scale);
   if(editing)bal=add(bal,effectOf(oldDoc,scale),-1);
   let planned,who,input,paidAt;
   try{
    planned=plan(bal,x);
    who=await parties(tx,db,{organizationId:d.organizationId,org:org.data(),x,old:oldDoc,methods:await readMethods(tx,db,d.organizationId)});
    input=await originalInput(tx,db,{x,org:org.data(),currency:booking.currency||'VND'});
    paidAt=paidAtFor(x.paidOn,zone,now.toMillis(),(c,k)=>{throw Object.assign(new Error(k),{code:c});});
    // An edit that keeps the day keeps the time, so the payment stays in its place in the list.
    if(editing&&oldDoc.paidOn===x.paidOn&&typeof oldDoc.paidAt?.toMillis==='function')paidAt=oldDoc.paidAt.toMillis();
   }catch(e){rethrow(e);}
   const after=add(bal,planned.effect);
   if(!sane(after))fail('failed-precondition','booking_payment_balance');
   const ref=editing?oldRef:db.doc(`payments/booking_${d.bookingId}_${d.operationId}_receipt`);
   const doc=receiptDoc({booking,bookingId:d.bookingId,x,who,recorded:planned.recorded,change:planned.change,effect:planned.effect,paidAt,scale,input,uid,now,Timestamp,old:oldDoc});
   const patch={...bookingPatch(after,scale),updatedAt:now};
   // Older bookings keep a copy of the deposit and payments taken with the booking: keep them in step.
   if(editing&&plain(booking.depositPayment)&&booking.depositPayment.paymentId===d.paymentId){
    patch.depositPayment=x.kind==='deposit'?{...booking.depositPayment,amount:planned.recorded/scale,paymentMethod:who.paymentMethod,paidOn:x.paidOn,paidAt:doc.paidAt}:null;
    patch.depositNote=x.kind==='deposit'?doc.notes:(booking.depositNote??'');
   }
   if(editing&&Array.isArray(booking.rentPayments)&&booking.rentPayments.some(r=>r?.paymentId===d.paymentId))
    patch.rentPayments=booking.rentPayments.filter(r=>r?.paymentId!==d.paymentId||x.kind!=='deposit'&&x.kind!=='refund').map(r=>r?.paymentId===d.paymentId?{...r,amount:planned.recorded/scale,paymentMethod:who.paymentMethod,paidOn:x.paidOn,note:doc.notes}:r);
   if(editing)tx.set(ref,doc);else tx.create(ref,doc);
   tx.update(bookingRef,patch);
   if(FieldValue)tx.update(db.doc(`rooms/${booking.roomId}`),{bookingRevision:FieldValue.increment(1)});
   const row=project({id:ref.id,data:()=>doc},scale,zone);
   const result={paymentId:ref.id,recordedMinor:planned.recorded,changeMinor:planned.change};
   tx.create(db.doc(`teamActivity/${opRef.id}`),{organizationId:d.organizationId,actorId:uid,action:editing?'booking_receipt_edit':'booking_receipt_add',targetId:d.bookingId,paymentId:ref.id,createdAt:now,before:snapshot(oldRow),after:snapshot(row)});
   tx.create(opRef,{organizationId:d.organizationId,actorId:uid,createdAt:now,fingerprint,result});
   return result;
  });
 };
}

/** For a new booking: the payments added in the form before its first save, written with it (calendar.js).
 *  Resolves each one now (inside the workspace transaction); calendar.js applies the amounts to the new booking. */
async function prepareNewReceipts(tx,db,{list,organizationId,org,currency,zone,nowMs,member,scope}){
 const fail=(code,key)=>{throw Object.assign(new Error(key),{code});};
 if(!Array.isArray(list)||list.length>20)fail('invalid-argument','booking_invalid_request');
 if(!list.length)return [];
 if(!allows(member,'collectPayments',scope))fail('permission-denied','booking_permission-denied');
 const methods=await readMethods(tx,db,organizationId),out=[];
 for(const raw of list){
  const x=checkShape(raw);
  if(x.kind==='refund')fail('invalid-argument','booking_invalid_request');
  out.push({x,who:await parties(tx,db,{organizationId,org,x,old:null,methods}),input:await originalInput(tx,db,{x,org,currency}),paidAt:paidAtFor(x.paidOn,zone,nowMs,fail)});
 }
 return out;
}
/** Applied by calendar.js to the new booking (`next`): returns the documents to create; throws when too much is paid. */
function applyNewReceipts({prepared,next,bookingId,operationId,uid,now,Timestamp}){
 const scale=scaleOf(next.currency||'VND');let bal=balancesOf(next,scale);const docs=[];
 prepared.forEach((r,i)=>{
  const planned=plan(bal,r.x);bal=add(bal,planned.effect);
  docs.push({id:`booking_${bookingId}_${operationId}_r${i}`,data:receiptDoc({booking:next,bookingId,x:r.x,who:r.who,recorded:planned.recorded,change:planned.change,effect:planned.effect,paidAt:r.paidAt,scale,input:r.input,uid,now,Timestamp,old:null})});
 });
 if(!sane(bal))throw Object.assign(new Error('booking_payment_balance'),{code:'failed-precondition'});
 Object.assign(next,bookingPatch(bal,scale));
 return docs;
}

module.exports={createReceiptsHandler,prepareNewReceipts,applyNewReceipts,readMethods,kindOf,effectOf,balancesOf,plan,KINDS};
