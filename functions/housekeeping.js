'use strict';
const {createHash}=require('node:crypto');
const {allows}=require('./team_access');
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
function createHousekeepingHandler({db,Timestamp,HttpsError}){
  const fail=(code,message)=>{throw new HttpsError(code,message);};
  return async request=>{
    const uid=request.auth?.uid,d=request.data;
    if(!uid)fail('unauthenticated','team_sign_in_required');
    if(!d||!id(d.organizationId)||!id(d.operationId)||!id(d.taskId)||!['assign','status'].includes(d.action))fail('invalid-argument','task_invalid_input');
    const keys=['organizationId','operationId','taskId','action',...(d.action==='assign'?['buildingId','roomId','assigneeId','title']:['status'])];
    if(Object.keys(d).some(k=>!keys.includes(k)))fail('invalid-argument','task_invalid_input');
    if(d.action==='assign'&&(!id(d.buildingId)||!id(d.roomId)||!id(d.assigneeId)||typeof d.title!=='string'||!d.title.trim()||d.title.length>200))fail('invalid-argument','task_invalid_input');
    if(d.action==='status'&&!['inProgress','completed'].includes(d.status))fail('invalid-argument','task_invalid_status');
    const digest=x=>createHash('sha256').update(JSON.stringify(x)).digest('hex');
    const key=digest(['housekeeping',d.organizationId,uid,d.operationId]);
    const fingerprint=digest(keys.map(k=>d[k]));
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.doc(`organizations/${d.organizationId}`));
      const member=await tx.get(db.doc(`memberships/${uid}_${d.organizationId}`));
      const ref=db.doc(`housekeepingTasks/${d.taskId}`),oldDoc=await tx.get(ref),old=oldDoc.data();
      if(!org.exists||org.data().accessVersion!==2)fail('failed-precondition','team_migration_required');
      if(old&&old.organizationId!==d.organizationId)fail('not-found','task_not_found');
      const buildingId=old?.buildingId??d.buildingId;
      const context={organizationId:d.organizationId,userId:uid,buildingId};
      const manager=allows(member.data(),'manageProperty',context);
      if(d.action==='assign'?!manager:!manager&&!(old?.assigneeId===uid&&allows(member.data(),'updateAssignedTasks',context)))fail('permission-denied','task_access_denied');
      const operationRef=db.doc(`taskOperations/${key}`),prior=await tx.get(operationRef);
      if(prior.exists){if(prior.data().fingerprint!==fingerprint)fail('already-exists','task_operation_reused');return prior.data().result;}
      const building=await tx.get(db.doc(`buildings/${buildingId}`));
      if(!building.exists||building.data().organizationId!==d.organizationId)fail('failed-precondition','task_invalid_property');
      const now=Timestamp.now();let patch;
      if(d.action==='assign'){
        if(old)fail('already-exists','task_exists');
        const room=await tx.get(db.doc(`rooms/${d.roomId}`));
        const assignee=await tx.get(db.doc(`memberships/${d.assigneeId}_${d.organizationId}`));
        if(!room.exists||room.data().organizationId!==d.organizationId||room.data().buildingId!==d.buildingId||
          !allows(assignee.data(),'updateAssignedTasks',{organizationId:d.organizationId,userId:d.assigneeId,buildingId}))fail('failed-precondition','task_invalid_assignment');
        patch={organizationId:d.organizationId,buildingId,roomId:d.roomId,assigneeId:d.assigneeId,title:d.title.trim(),status:'assigned',createdAt:now,createdBy:uid,updatedAt:now,updatedBy:uid};
      }else{
        if(!old)fail('not-found','task_not_found');
        if(old.status==='completed'||!['assigned','inProgress'].includes(old.status)||old.status===d.status)fail('failed-precondition','task_invalid_transition');
        patch={status:d.status,updatedAt:now,updatedBy:uid,...(d.status==='completed'?{completedAt:now,completedBy:uid}:{})};
      }
      const result={taskId:d.taskId,status:patch.status};
      if(old)tx.update(ref,patch);else tx.create(ref,patch);
      tx.create(operationRef,{organizationId:d.organizationId,actorId:uid,fingerprint,result,createdAt:now});
      tx.create(db.doc(`teamActivity/${key}`),{organizationId:d.organizationId,actorId:uid,action:'housekeeping_'+d.action,targetId:d.taskId,createdAt:now,
        before:old?{status:old.status,roomId:old.roomId,buildingId}:null,
        after:{status:patch.status,roomId:old?.roomId??d.roomId,buildingId}});
      return result;
    });
  };
}
module.exports={createHousekeepingHandler};
