'use strict';
const {createHash}=require('node:crypto');
const {accountPolicy,policyLocks}=require('./account_policy');
const {feesId,roomFeesId}=require('./service_fee_invoice');
const {meterId}=require('./utility_invoice');
const {effectiveGrants,permissionScopes}=require('./team_access');
// Atomic merge: no partial data move is visible. Large accounts are refused
// before any write and require a reviewed maintenance migration.
function createOrganizationMergeHandler({db,Timestamp,HttpsError,dryRun=false}){
 const fail=(key)=>{throw new HttpsError('failed-precondition',key);};
 const valid=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
 return async request=>{
  const uid=request.auth?.uid,d=request.data??{};
  if(!valid(uid))throw new HttpsError('unauthenticated','team_sign_in_required');
  const recovery=d.action==='recover';
  if(!['preview','merge','recoveryList','recover'].includes(d.action)||Object.keys(d).some(k=>!['action','name','operationId','organizationIds','mergeIds','confirmDelete','sourceOrganizationId'].includes(k))||
   (recovery&&(!valid(d.operationId)||!valid(d.sourceOrganizationId)))||
   (d.action==='merge'&&(!valid(d.operationId)||typeof d.name!=='string'||!d.name.trim()||d.name.trim().length>120)))
   throw new HttpsError('invalid-argument','org_invalid_input');
  const collections=await db.listCollections();
  return db.runTransaction(async tx=>{
   const op=db.collection('organizationMerges').doc(createHash('sha256').update(uid+':'+(d.operationId??'preview')).digest('hex'));
   const prior=await tx.get(op);
   const fingerprint=recovery?JSON.stringify(['recover',d.sourceOrganizationId]):JSON.stringify([d.name?.trim(),d.organizationIds,d.mergeIds,d.confirmDelete]);
   if((d.action==='merge'||recovery)&&prior.exists){if(prior.data().fingerprint!==fingerprint)fail('org_operation_reused');return prior.data().result;}
   const locks=await policyLocks(db,tx,uid,request.auth.token?.email);
   const policy=await accountPolicy(db,tx,uid);
   if(policy.deleting)fail('account_deletion_in_progress');
   if(policy.hasStaff)fail('org_merge_access_review');
   const currentId=policy.organizationIds.length===1&&policy.hasOwned?policy.organizationIds[0]:null;
   if((recovery||d.action==='recoveryList')&&currentId){
    const members=await tx.get(db.collection('memberships').where('organizationId','==',currentId));
    const owners=members.docs.filter(m=>m.data().status==='active'&&m.data().role==='owner');
    if(owners.length!==1||owners[0].data().ownerId!==uid||members.docs.some(m=>m.data().role==='coOwner'&&m.data().status!=='revoked'))fail('org_merge_owner_only');
   }
   if(d.action==='recoveryList'){
    if(!currentId)fail('org_merge_owner_only');
    const targetOrg=await tx.get(db.doc(`organizations/${currentId}`));
    const member=await tx.get(db.doc(`memberships/${uid}_${currentId}`));
    if(targetOrg.data()?.closedAt||targetOrg.data()?.mergedInto||(targetOrg.data()?.ownerTransferredTo??targetOrg.data()?.createdBy)!==uid||member.data()?.status!=='active'||member.data()?.role!=='owner')fail('org_merge_owner_only');
    const sources=await tx.get(db.collection('organizations').where('closedBy','==',uid));
    return {organizationId:currentId,organizations:sources.docs.filter(o=>{
     const x=o.data();return x.excludedFromMerge&&x.mergedInto===currentId&&x.closedAt&&!x.purgeStartedAt&&x.purgeAfter?.toMillis()>Timestamp.now().toMillis()&&(x.ownerTransferredTo??x.createdBy)===uid;
    }).map(o=>({id:o.id,name:o.data().name??'',deleteAt:o.data().purgeAfter.toDate().toISOString()}))};
   }
   if(recovery&&!currentId)fail('org_merge_owner_only');
   const allIds=recovery?[currentId,d.sourceOrganizationId].sort():policy.organizationIds;
   if(new Set(allIds).size!==allIds.length)fail('org_merge_changed');
   if(allIds.length<2)fail('org_merge_not_needed');
   const orgs=[];
   for(const id of allIds){
    const o=await tx.get(db.collection('organizations').doc(id)),m=await tx.get(db.collection('memberships').doc(`${uid}_${id}`));
    const x=o.data(),member=m.data();
    const source=recovery&&id===d.sourceOrganizationId;
    if(source&&(!x?.excludedFromMerge||x.mergedInto!==currentId||x.closedBy!==uid||x.purgeStartedAt||!x.closedAt||!(x.purgeAfter?.toMillis()>Timestamp.now().toMillis())))fail('org_restore_expired');
    if(!x||(!source&&(x.closedAt||x.mergedInto))||(x.ownerTransferredTo??x.createdBy)!==uid||
      (!source&&((member&&member.status!=='active')||(x.accessVersion===2&&member?.role!=='owner'))))fail('org_merge_owner_only');
    orgs.push(o);
   }
   const allConnections=[];
   for(const org of orgs){const c=await tx.get(db.collection('driveConnections').doc(org.id));if(c.exists)allConnections.push(c);}
   if(d.action==='preview')return {organizations:orgs.map(o=>({id:o.id,name:o.data().name??'',...(allConnections.some(c=>c.id===o.id)?{driveConnection:true}:{})}))};
   if(recovery){
    if(allConnections.some(c=>c.id!==currentId))fail('org_merge_drive_review');
    d.organizationIds=allIds;d.mergeIds=allIds;d.confirmDelete=false;
    d.name=orgs.find(o=>o.id===currentId).data().name;
    if(typeof d.name!=='string'||!d.name.trim())fail('org_merge_changed');
   }
   if(!Array.isArray(d.organizationIds)||JSON.stringify([...d.organizationIds].sort())!==JSON.stringify(allIds)||
    !Array.isArray(d.mergeIds)||!d.mergeIds.length||new Set(d.mergeIds).size!==d.mergeIds.length||d.mergeIds.some(id=>!allIds.includes(id)))fail('org_merge_changed');
   const ids=[...d.mergeIds].sort(),excluded=allIds.filter(id=>!ids.includes(id));
   if(excluded.length&&d.confirmDelete!==true)fail('org_merge_delete_confirmation');
   if(new Set(orgs.filter(o=>ids.includes(o.id)).map(o=>o.data().accessVersion??1)).size!==1)fail('org_merge_version_review');
   const records=new Map(),origins=new Map();
   for(const c of collections){
    if(['organizations','accountOrganizations','organizationMerges','requestLimits','accountPolicyLocks'].includes(c.id))continue;
    for(const id of (recovery?[d.sourceOrganizationId]:allIds))for(const field of ['organizationId','orgId']){
     const rows=await tx.get(db.collection(c.id).where(field,'==',id));
     for(const row of rows.docs){records.set(row.ref.path,row);origins.set(row.ref.path,id);}
    }
   }
   // Legacy children sometimes only refer to a room/tenant, so discover those too.
   for(const [parent,child,field] of [['rooms','tenants','roomId'],['rooms','bookings','roomId'],['rooms','payments','roomId'],['tenants','payments','tenantId']]){
    for(const row of [...records.values()].filter(r=>r.ref.path.startsWith(parent+'/'))){
     const linked=await tx.get(db.collection(child).where(field,'==',row.id));
     for(const r of linked.docs){const origin=origins.get(row.ref.path);if(r.data().organizationId&&r.data().organizationId!==origin)fail('org_merge_cross_link');records.set(r.ref.path,r);origins.set(r.ref.path,origin);}
    }
   }
   // Keep the Drive-connected organization so existing OAuth/folder references work.
   const connections=allConnections.filter(c=>ids.includes(c.id));
   if(connections.length>1)fail('org_merge_drive_review');
   const target=recovery?currentId:connections[0]?.id??ids[0];
   const members=[...records.values()].filter(r=>r.ref.path.startsWith('memberships/'));
   const accounts=new Map(),staffLocks=[];
   for(const row of members){
    const m=row.data();if(m.status==='revoked')continue;
    if(m.role==='coOwner'||m.employerShareId||(m.role==='owner'&&m.ownerId!==uid))fail('org_merge_access_review');
    if(m.ownerId===uid)continue;
    if(ids.includes(m.organizationId)&&orgs.find(o=>o.id===m.organizationId).data().accessVersion!==2)fail('org_merge_access_review');
    if(accounts.has(m.ownerId))fail('org_merge_access_review');
    const other=await accountPolicy(db,tx,m.ownerId);
    if(other.deleting||other.organizationIds.some(id=>!allIds.includes(id)))fail('org_merge_access_review');
    accounts.set(m.ownerId,row);
    staffLocks.push(await policyLocks(db,tx,m.ownerId,m.email));
   }
   // Detailed histories stay under unchanged parent IDs; update scoped fields.
   const children=[];
   async function walk(ref){for(const c of await ref.listCollections()){
    const q=await tx.get(db.collection(ref.path+'/'+c.id));
    for(const r of q.docs){children.push(r);origins.set(r.ref.path,origins.get(ref.path));await walk(r.ref);}
   }}
   for(const row of records.values())await walk(row.ref);
   const writes=new Map();
   const roleIds=new Map();
   for(const row of records.values())if(row.ref.path.startsWith('orgRoles/')&&ids.includes(row.data().organizationId)){
    const x=row.data();roleIds.set(`${x.organizationId}:${x.roleId}`,x.organizationId===target?x.roleId:`r_${createHash('sha256').update(row.ref.path).digest('hex').slice(0,16)}`);
   }
   const paths=new Map(),meterIds=new Map();
   const scopedHash=values=>createHash('sha256').update(JSON.stringify(values)).digest('hex');
   for(const row of records.values()){
    if(!ids.includes(origins.get(row.ref.path)))continue;
    const c=row.ref.path.split('/')[0],x=row.data();let path=row.ref.path;
    if(c==='serviceFees')path=`serviceFees/${feesId(target,x.buildingId)}`;
    if(c==='serviceFeeRooms')path=`serviceFeeRooms/${roomFeesId(target,x.roomId)}`;
    if(c==='orgRoles')path=`orgRoles/${target}_${roleIds.get(`${x.organizationId}:${x.roleId}`)}`;
    if(c==='utilityTariffs')path=`utilityTariffs/${scopedHash([target,x.buildingId,x.kind])}`;
    if(c==='utilityMeters'){const newId=meterId(target,x.roomId,x.kind);path=`utilityMeters/${newId}`;meterIds.set(row.id,newId);}
    paths.set(row.ref.path,path);
   }
   const remap=x=>{
    if(Array.isArray(x))return x.map(remap);
    if(!x||typeof x!=='object'||Object.getPrototypeOf(x)!==Object.prototype)return x;
    return Object.fromEntries(Object.entries(x).map(([k,v])=>[k,['organizationId','orgId'].includes(k)&&ids.includes(v)?target:k==='meterId'&&meterIds.has(v)?meterIds.get(v):remap(v)]));
   };
   const now=Timestamp.now();
   for(const row of [...records.values(),...children]){
    const c=row.ref.path.split('/')[0],old=row.data(),next=remap(old);
    const excludedRecord=excluded.includes(origins.get(row.ref.path));
    if(excludedRecord){
     if(c==='memberships'){
      writes.set(row.ref.path,{...old,status:'revoked',revokedReason:'organizationDeletedAtMerge',updatedAt:now});
      if(old.ownerId!==uid){
       const binding=await tx.get(db.doc(`accountOrganizations/${old.ownerId}`));
       if(binding.data()?.organizationId===old.organizationId)writes.set(binding.ref.path,{organizationId:null,state:'released',source:'mergeDeletion',updatedAtMs:Date.now()});
      }
     }
     if(c==='teamInvitations'&&old.status==='pending')writes.set(row.ref.path,{...old,status:'revoked',revokedReason:'organizationDeletedAtMerge'});
     if(c==='invite_codes')writes.set(row.ref.path,{...old,retiredByMerge:true});
     continue;
    }
    if(c==='memberships'){
     if(old.ownerId===uid){writes.set(row.ref.path,{...old,status:'revoked',revokedReason:'organizationMerged',updatedAt:now});continue;}
     if(old.status==='revoked')continue;
     writes.set(row.ref.path,{...old,status:'revoked',revokedReason:'organizationMerged',updatedAt:now});
     // All-property staff scope becomes only their original properties after merge.
     const propertyIds=[...records.values()].filter(r=>r.ref.path.startsWith('buildings/')&&r.data().organizationId===old.organizationId).map(r=>r.id);
     const scope=old.buildingScope==='all'?{buildingScope:'selected',buildingIds:propertyIds}:{};
     const grants={...effectiveGrants(old)};
     for(const [p,s] of Object.entries(grants)){
      if(['manageOrganization','manageTeam','manageRoles','readAllActivity','exportData','importData','connectDrive'].includes(p))delete grants[p];
      else if(s==='all'&&permissionScopes[p]?.includes('managed'))grants[p]='managed';
     }
     const role=roleIds.get(`${old.organizationId}:${old.role}`)??old.role;
     writes.set(`memberships/${old.ownerId}_${target}`,{...next,...scope,role,roleGrants:grants,permissionOverrides:{},organizationId:target,updatedAt:now});
     writes.set(`accountOrganizations/${old.ownerId}`,{organizationId:target,state:'bound',source:'merge',updatedAtMs:Date.now()});continue;
    }
    if(c==='invite_codes'){writes.set(row.ref.path,{...old,retiredByMerge:true});continue;}
    if(!old.organizationId&&!old.orgId&&row.ref.path.split('/').length===2)next.organizationId=target;
    if(c==='teamInvitations'&&old.status==='pending'){next.status='revoked';next.revokedReason='organizationMerged';}
    const root=row.ref.path.split('/').slice(0,2).join('/');
    const path=(paths.get(root)??root)+row.ref.path.slice(root.length);
    if(c==='orgRoles'&&row.ref.path.split('/').length===2)next.roleId=roleIds.get(`${old.organizationId}:${old.roleId}`);
    if(path!==row.ref.path){
     const existing=await tx.get(db.doc(path));
     if(existing.exists&&existing.ref.path!==row.ref.path)fail('org_merge_cross_link');
     // Preserve original keyed records as archived evidence.
     writes.set(row.ref.path,{...old,mergedInto:target});
    }
    writes.set(path,next);
   }
   const targetOrg=orgs.find(o=>o.id===target).data();
   const ownerSource=recovery?(await tx.get(db.doc(`memberships/${uid}_${target}`))).data():members.find(r=>r.data().ownerId===uid&&r.data().organizationId===target)?.data()??{};
   writes.set(`memberships/${uid}_${target}`,{...ownerSource,ownerId:uid,organizationId:target,status:'active',role:targetOrg.accessVersion===2?'owner':'admin',...(targetOrg.accessVersion===2?{accessVersion:2,buildingScope:'all',buildingIds:[],permissionOverrides:{}}:{}),updatedAt:now});
   for(const org of orgs){
    const sourceData={...org.data()};
    if(recovery&&org.id!==target){delete sourceData.purgeAfter;sourceData.excludedFromMerge=false;sourceData.recoveredAt=now;}
    writes.set(org.ref.path,org.id===target?{...org.data(),name:d.name.trim(),mergedFrom:[...new Set([...(org.data().mergedFrom??[]),...ids.filter(id=>id!==target)])],updatedAt:now}:excluded.includes(org.id)?
    {...org.data(),mergedInto:target,excludedFromMerge:true,closedAt:now,closedBy:uid,purgeAfter:Timestamp.fromMillis(now.toMillis()+30*86400000)}:
    {...sourceData,mergedInto:target,mergedAt:now,closedAt:now,closedBy:uid});
   }
   writes.set(`accountOrganizations/${uid}`,{organizationId:target,state:'bound',source:'merge',updatedAtMs:Date.now()});
   const result={organizationId:target,deletedOrganizationIds:excluded,organizations:orgs.map(o=>({id:o.id,name:o.data().name??''})),records:records.size+children.length};
   if(writes.size+staffLocks.length*2+4>450||Buffer.byteLength(JSON.stringify([...writes]))>7*1024*1024)fail('org_merge_maintenance_required');
   if(dryRun)return {...result,plannedWrites:writes.size,readOnly:true};
   locks();
   for(const commit of staffLocks)commit();
   for(const [path,data] of writes)tx.set(db.doc(path),data);
   tx.set(op,{actorId:uid,name:d.name.trim(),fingerprint,status:'complete',createdAt:now,result,originalOrganizationNames:orgs.map(o=>({id:o.id,name:o.data().name??''})),
    moves:[...records.values(),...children].map(r=>({path:r.ref.path,from:origins.get(r.ref.path),to:excluded.includes(origins.get(r.ref.path))?null:target}))});
   return result;
  });
 };
}
module.exports={createOrganizationMergeHandler};
