'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const validDate=v=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)&&v>='2000-01-01'&&v<='2199-12-31'&&Number.isFinite(Date.parse(v+'T00:00:00Z'))&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v;
const fields=['direction','status','partyName','partyPhone','amountMinor','dueDay','startDate','endDate','notes'];
function validContract(c){
  return c&&typeof c==='object'&&!Array.isArray(c)&&Object.keys(c).length===fields.length&&fields.every(k=>Object.hasOwn(c,k))&&
    ['rentIn','rentOut'].includes(c.direction)&&['active','ended'].includes(c.status)&&typeof c.partyName==='string'&&c.partyName.trim().length>0&&c.partyName.length<=160&&typeof c.partyPhone==='string'&&c.partyPhone.length<=80&&
    Number.isSafeInteger(c.amountMinor)&&c.amountMinor>0&&c.amountMinor<=1e12&&Number.isInteger(c.dueDay)&&c.dueDay>=1&&c.dueDay<=31&&validDate(c.startDate)&&(c.endDate===null||validDate(c.endDate)&&c.endDate>=c.startDate)&&(c.status!=='ended'||c.endDate!==null)&&typeof c.notes==='string'&&c.notes.length<=2000;
}
function createPropertyContractHandler({db,Timestamp,HttpsError}){
  const fail=code=>{throw new HttpsError(code,'contract_'+code);};
  return async request=>{
    const uid=request.auth?.uid,d=request.data||{},write=d.action==='update',history=d.action==='history';
    if(!uid)fail('unauthenticated');
    const keys=['action','organizationId','buildingId',...(history?['cursor']:[]),...(write?['operationId','revision','currency','contract']:[])];
    if(!['read','update','history'].includes(d.action)||!id(d.organizationId)||!id(d.buildingId)||Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument');
    if(history&&d.cursor!=null&&(typeof d.cursor!=='string'||! /^[a-f0-9]{64}$/.test(d.cursor)))fail('invalid-argument');
    if(write&&(!id(d.operationId)||typeof d.revision!=='string'||!/^\d+:\d+$/.test(d.revision)||!['VND','USD'].includes(d.currency)||!validContract(d.contract)))fail('invalid-argument');
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`)),member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      const scope={organizationId:d.organizationId,userId:uid,buildingId:d.buildingId};
      if(!org.exists||org.data().accessVersion!==2||!allows(member.data(),'manageProperty',scope)||!allows(member.data(),'manageLease',scope))fail('permission-denied');
      const ref=db.doc(`buildings/${d.buildingId}`),doc=await tx.get(ref),old=doc.data();
      if(!old||old.organizationId!==d.organizationId)fail('not-found');
      if(history){
        let query=ref.collection('rentalContractHistory').orderBy('createdAt','desc').orderBy('__name__','desc');
        if(d.cursor!=null){
          const cursor=await tx.get(ref.collection('rentalContractHistory').doc(d.cursor));
          if(!cursor.exists||cursor.data().organizationId!==d.organizationId)fail('invalid-argument');
          query=query.startAfter(cursor);
        }
        const page=await tx.get(query.limit(21)),docs=page.docs.slice(0,20);
        const snapshot=v=>v==null?null:Object.fromEntries(fields.map(k=>[k,v[k]??null]));
        return {records:docs.map(row=>{
          const v=row.data();if(v.organizationId!==d.organizationId)fail('failed-precondition');
          return {id:row.id,actorId:v.actorId,currency:v.currency,createdAt:v.createdAt.toDate().toISOString(),before:snapshot(v.before),after:snapshot(v.after)};
        }),nextCursor:page.docs.length>20?docs.at(-1).id:null};
      }
      const revision=`${doc.updateTime.seconds}:${doc.updateTime.nanoseconds}`,currency=old.currency??'VND';
      if(!['VND','USD'].includes(currency))fail('failed-precondition');
      if(!write){
        const legacy={};
        for(const k of ['managementType','renterName','renterPhone','rentAmount','rentDueDay','rentContractStart','rentContractEnd','renterNotes']){
          if(old[k]!=null)legacy[k]=old[k]?.toDate?old[k].toDate().toISOString():old[k];
        }
        return {record:{name:old.name??'',revision,currency,contract:old.rentalContract??null,legacy}};
      }
      const hash=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
      const key=hash(['propertyContract',d.organizationId,uid,d.operationId]),op=ref.collection('rentalContractHistory').doc(key);
      const prior=await tx.get(op),fingerprint=hash([d.revision,d.currency,...fields.map(k=>d.contract[k])]);
      if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('failed-precondition');return prior.data().result;}
      if(revision!==d.revision||currency!==d.currency)fail('aborted');
      const contract={...d.contract,partyName:d.contract.partyName.trim(),partyPhone:d.contract.partyPhone.trim(),notes:d.contract.notes.trim()},now=Timestamp.now(),result={buildingId:d.buildingId};
      tx.update(ref,{rentalContract:contract,updatedAt:now,updatedBy:uid});
      tx.create(op,{organizationId:d.organizationId,actorId:uid,currency,before:old.rentalContract??null,after:contract,fingerprint,result,createdAt:now});
      // Broad activity feeds contain no party contacts or contract notes.
      tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'property_contract_updated',targetId:d.buildingId,createdAt:now,before:old.rentalContract?{buildingId:d.buildingId,direction:old.rentalContract.direction,status:old.rentalContract.status}:null,after:{buildingId:d.buildingId,direction:contract.direction,status:contract.status}});
      return result;
    });
  };
}
module.exports={createPropertyContractHandler,validContract,validDate};
