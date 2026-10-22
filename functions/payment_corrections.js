'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const {propertyDate,propertyDayStart}=require('./lease_dates');
const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
function createReceiptHandler({db,Timestamp,HttpsError}) {
 const fail=(code,message='payment_correction_'+code)=>{throw new HttpsError(code,message);};
 return async request=>{
  const uid=request.auth?.uid,d=request.data??{},write=d.action==='correctReceipt';
  if(!uid)fail('unauthenticated');
  const keys=['action','organizationId','buildingId','bookingId','tenantId',...(write?['paymentId','receiptId','revision','operationId','amountMinor','paidOn','note']:[])];
  if(Object.keys(d).some(k=>!keys.includes(k))||!id(d.organizationId)||!id(d.buildingId)||Boolean(d.bookingId)===Boolean(d.tenantId)||!id(d.bookingId??d.tenantId))fail('invalid-argument');
  if(write&&(!id(d.paymentId)||!id(d.receiptId)||!id(d.operationId)||typeof d.revision!=='string'||!Number.isSafeInteger(d.amountMinor)||d.amountMinor<=0||d.amountMinor>1e12||typeof d.paidOn!=='string'||typeof d.note!=='string'||d.note.length>500))fail('invalid-argument');
  return db.runTransaction(async tx=>{
   const org=await tx.get(db.doc(`organizations/${d.organizationId}`));
   const member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
   const scope={organizationId:d.organizationId,buildingId:d.buildingId,userId:uid};
   if(!org.exists||org.data().accessVersion!==2||org.data().closedAt||!allows(member.data(),'collectPayments',scope))fail('permission-denied');
   const building=await tx.get(db.doc(`buildings/${d.buildingId}`));
   const targetRef=db.doc(`${d.bookingId?'bookings':'tenants'}/${d.bookingId??d.tenantId}`),target=await tx.get(targetRef),t=target.data();
   if(!building.exists||building.data().organizationId!==d.organizationId||!t||t.organizationId!==d.organizationId)fail('not-found');
   if(d.bookingId){const room=await tx.get(db.doc(`rooms/${t.roomId}`));if(!room.exists||room.data().buildingId!==d.buildingId)fail('not-found');}
   else if(t.buildingId!==d.buildingId)fail('not-found');
   const zone=building.data().timeZone,now=Timestamp.now();
   const opKey=write?hash(['receiptCorrection',d.organizationId,uid,d.operationId]):null;
   const opRef=write?db.doc(`paymentOperations/${opKey}`):null;
   const previous=write?await tx.get(opRef):null,fingerprint=write?hash(d):null;
   if(previous?.exists){if(previous.data().before.amountMinor>previous.data().after.amountMinor&&!allows(member.data(),'refundPayments',scope))fail('permission-denied');if(previous.data().fingerprint!==fingerprint)fail('already-exists');return previous.data().result;}
   async function receipts(doc){
    const p=doc.data(),scale=p.currency==='USD'?100:1;
    if(p.organizationId!==d.organizationId||p.buildingId!==d.buildingId||p.direction==='expense'||!['pending','partial','overdue','paid'].includes(p.status)||!['VND','USD'].includes(p.currency))return [];
    const rows=[];
    if(d.bookingId){
     if(p.bookingId!==d.bookingId||p.paidAmount<=0)return [];
     rows.push({receiptId:'booking',amountMinor:Math.round(p.paidAmount*scale),paidOn:propertyDate(p.paidAt?.toMillis?.(),zone)??'',note:t.depositPayment?.paymentId===doc.id?t.depositNote??'':p.notes??'',paymentMethod:p.paymentMethod??'cash'});
    }else{
     if(p.tenantId!==d.tenantId)return [];
     const ops=await tx.get(db.collection('paymentOperations').where('paymentId','==',doc.id));
     for(const r of ops.docs){const v=r.data();if(v.organizationId===d.organizationId&&v.action==='collect')rows.push({receiptId:r.id,amountMinor:v.amountMinor,paidOn:propertyDate(v.createdAt?.toMillis?.(),zone)??'',note:v.note??'',paymentMethod:v.paymentMethod??'cash'});}
     // Preserve an older direct receipt even when later collections were appended.
     let collected=0;
     for(const r of rows){const c=await tx.get(doc.ref.collection('receiptCorrections').doc(r.receiptId));collected+=c.data()?.current?.amountMinor??r.amountMinor;}
     const refunded=ops.docs.reduce((n,r)=>n+(r.data().organizationId===d.organizationId&&r.data().action==='refund'?r.data().amountMinor:0),0);
     const legacy=Math.round(p.paidAmount*scale)-collected+refunded;
     if(legacy>0)rows.push({receiptId:'legacy',amountMinor:legacy,paidOn:propertyDate(p.paidAt?.toMillis?.(),zone)??'',note:p.notes??'',paymentMethod:p.paymentMethod??'cash'});
    }
    for(const r of rows){
     const correction=await tx.get(doc.ref.collection('receiptCorrections').doc(r.receiptId));
     if(correction.exists)Object.assign(r,correction.data().current);
     r.paymentId=doc.id;r.currency=p.currency;
     r.revision=hash([r,p.paidAmount,p.status,correction.data()?.version??0]);
    }
    return rows;
   }
   if(!write){
    const query=await tx.get(db.collection('payments').where(d.bookingId?'bookingId':'tenantId','==',d.bookingId??d.tenantId));
    const records=[];for(const doc of query.docs)records.push(...await receipts(doc));
    return {records};
   }
   const ref=db.doc(`payments/${d.paymentId}`),doc=await tx.get(ref);
   if(!doc.exists)fail('not-found');
   const receipt=(await receipts(doc)).find(r=>r.receiptId===d.receiptId);
   if(!receipt)fail('not-found');
   if(receipt.revision!==d.revision)fail('aborted');
   const day=propertyDayStart(d.paidOn,zone),today=propertyDate(now.toMillis(),zone);
   if(day===null||!today||d.paidOn>today)fail('invalid-argument','payment_correction_date');
   const p=doc.data(),scale=p.currency==='USD'?100:1,delta=d.amountMinor-receipt.amountMinor;
   // Decreasing recorded cash requires the same authority as a refund.
   if(delta<0&&!allows(member.data(),'refundPayments',scope))fail('permission-denied');
   const paid=Math.round(p.paidAmount*scale)+delta;
   const total=d.bookingId?d.amountMinor:(p.totalMinor??Math.round(['amount','internetFee','cableTVFee','hotWaterFee','lateFee','taxAmount'].reduce((s,k)=>s+(p[k]??0),0)*scale));
   if(!Number.isSafeInteger(paid)||paid<0||paid>total)fail('failed-precondition','payment_correction_balance');
   const current={amountMinor:d.amountMinor,paidOn:d.paidOn,note:d.note.trim(),paymentMethod:receipt.paymentMethod};
   let bookingPatch;
   if(d.bookingId){
    const separate=p.type==='deposit'&&!p.bookingDeposit;
    const field=separate?'depositPaidAmount':'paidAmount';
    const balance=Math.round((t[field]??0)*scale)+delta;
    const max=Math.round((separate?t.depositAmount:t.totalPrice)*scale);
    if(balance<0||balance>max||(separate&&balance<Math.round((t.depositRefundedAmount??0)*scale)))fail('failed-precondition','payment_correction_balance');
    bookingPatch={[field]:balance/scale,updatedAt:now};
    if(t.depositPayment?.paymentId===doc.id){bookingPatch.depositPayment={...t.depositPayment,amount:d.amountMinor/scale,paidOn:d.paidOn,paidAt:Timestamp.fromMillis(day)};bookingPatch.depositNote=current.note;}
    if(Array.isArray(t.rentPayments))bookingPatch.rentPayments=t.rentPayments.map(r=>r.paymentId===doc.id?{...r,amount:d.amountMinor/scale,paidOn:d.paidOn,note:current.note}:r);
   }
   const correctionRef=ref.collection('receiptCorrections').doc(d.receiptId),oldCorrection=await tx.get(correctionRef);
   const patch={paidAmount:paid/scale,status:paid===total?'paid':paid===0?'pending':'partial',updatedAt:now,updatedBy:uid};
   if(d.bookingId)Object.assign(patch,{amount:d.amountMinor/scale,paidAt:Timestamp.fromMillis(day),notes:current.note});
   // Invoice paidAt is the latest corrected receipt date, not an arbitrary edit time.
   if(!d.bookingId){const all=await receipts(doc);const dates=all.map(r=>r.receiptId===d.receiptId?d.paidOn:r.paidOn).filter(Boolean).sort();if(dates.length)patch.paidAt=Timestamp.fromMillis(propertyDayStart(dates.at(-1),zone));}
   const result={paymentId:doc.id};
   tx.update(ref,patch);
   if(bookingPatch)tx.update(targetRef,bookingPatch);
   tx.set(correctionRef,{current,version:(oldCorrection.data()?.version??0)+1});
   const history={organizationId:d.organizationId,actorId:uid,action:'correctReceipt',createdAt:now,receiptId:d.receiptId,before:receipt,after:current};
   tx.create(ref.collection('invoiceHistory').doc(opKey),{...history,reason:current.note,
    before:{totalMinor:p.totalMinor??Math.round(p.amount*scale),paidAmount:p.paidAmount,status:p.status,receipt},
    after:{totalMinor:d.bookingId?d.amountMinor:total,paidAmount:paid/scale,status:patch.status,receipt:current}});
   tx.create(opRef,{...history,fingerprint,result});
   tx.create(db.doc(`teamActivity/${opKey}`),{...history,targetId:doc.id});
   return result;
  });
 };
}
module.exports={createReceiptHandler};
