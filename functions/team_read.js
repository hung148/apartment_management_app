'use strict';
const {allows, canManageAccessOf, roles} = require('./team_access');

const FIELDS = Object.freeze({
  buildings: ['organizationId','name'],
  staff: ['organizationId','code','displayName','employmentStatus','accountId','email','phone','color','createdAt','updatedAt'],
  access: ['organizationId','ownerId','staffId','accessVersion','role','status','buildingScope','buildingIds','permissionOverrides','displayName','email','joinedAt','updatedAt'],
  invitations: ['organizationId','staffId','email','access','status','invitedBy','createdAt','expiresAt','acceptedBy','acceptedAt','updatedAt'],
  requests: ['organizationId','userId','email','displayName','status','createdAt','reviewedBy','reviewedAt'],
  activity: ['organizationId','actorId','action','targetId','before','after','reason','createdAt'],
});
const COLLECTIONS = Object.freeze({buildings:'buildings',staff:'staffProfiles',access:'memberships',invitations:'teamInvitations',requests:'teamRequests',activity:'teamActivity'});
const id = v => typeof v === 'string' && /^[A-Za-z0-9_-]{1,256}$/.test(v);
// Deliberate serialization contract: timestamps are UTC ISO strings, not SDK objects.
function serialize(value) {
  if (value?.toDate) return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(serialize);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([k,v])=>[k,serialize(v)]));
  return value;
}
function project(kind, doc) {
  const data=doc.data();
  return {id:doc.id,...Object.fromEntries(FIELDS[kind].filter(k=>data[k]!==undefined).map(k=>[k,serialize(data[k])]))};
}
function createTeamReadHandler({db,HttpsError}) {
  const fail=(code,message)=>{throw new HttpsError(code,message);};
  return async request=>{
    const uid=request.auth?.uid;
    if(!uid)fail('unauthenticated','team_sign_in_required');
    const input=request.data || {};
    if(!id(input.organizationId) || !['myAccess','myRequests',...Object.keys(COLLECTIONS)].includes(input.view))fail('invalid-argument','team_invalid_input');
    const limit=input.limit ?? 25;
    if(!Number.isInteger(limit)||limit<1||limit>100||(input.cursor!==undefined&&!id(input.cursor)))fail('invalid-argument','team_invalid_page');
    if(input.actorId!==undefined && (!id(input.actorId)||input.view!=='activity'))fail('invalid-argument','team_invalid_filter');
    return db.runTransaction(async tx=>{
      const org=await tx.get(db.collection('organizations').doc(input.organizationId));
      if(!org.exists||org.data().accessVersion!==2)fail('failed-precondition','team_migration_required');
      const mine=await tx.get(db.collection('memberships').doc(`${uid}_${input.organizationId}`));
      const member=mine.exists?mine.data():null;
      const context={organizationId:input.organizationId,userId:uid};
      const validIdentity=member?.organizationId===input.organizationId&&member?.ownerId===uid;
      if(input.view==='myAccess'){
        // A revoked user needs their own state to render an access-revoked screen.
        return {record:validIdentity?project('access',mine):null};
      }
      const admin=allows(member,'manageTeam',context)&&member.buildingScope==='all';
      let kind=input.view, query;
      if(input.view==='myRequests'){
        kind='requests';query=db.collection(COLLECTIONS.requests).where('organizationId','==',input.organizationId).where('userId','==',uid);
      }else{
        if(!admin && input.view!=='activity' && input.view!=='staff')fail('permission-denied','team_access_denied');
        query=db.collection(COLLECTIONS[kind]).where('organizationId','==',input.organizationId);
        if(!admin){
          if(input.view==='activity'){
            if(!allows(member,'readOwnActivity',context)|| (input.actorId!==undefined&&input.actorId!==uid))fail('permission-denied','team_access_denied');
            query=query.where('actorId','==',uid);
          }else{
            if(!validIdentity||member.accessVersion!==2||member.status!=='active'||!allows(member,'readOwnActivity',context))fail('permission-denied','team_access_denied');
            query=query.where('accountId','==',uid);
          }
        }else if(kind==='activity'&&input.actorId)query=query.where('actorId','==',input.actorId);
      }
      if(kind==='activity'){
        // Preserve full Firestore timestamp precision and a deterministic tie
        // breaker. Resolve the ID cursor only within this authorized query.
        query=query.orderBy('createdAt','desc').orderBy('__name__','desc');
        if(input.cursor){
          const cursorDoc=await tx.get(db.collection(COLLECTIONS.activity).doc(input.cursor));
          const cursorData=cursorDoc.exists?cursorDoc.data():null;
          const actorFilter=admin?input.actorId:uid;
          if(!cursorData || cursorData.organizationId!==input.organizationId ||
              (actorFilter!==undefined && cursorData.actorId!==actorFilter) ||
              typeof cursorData.createdAt?.toMillis!=='function')fail('invalid-argument','team_invalid_page');
          query=query.startAfter(cursorDoc);
        }
      }else{
        query=query.orderBy('__name__');
        if(input.cursor)query=query.startAfter(input.cursor);
      }
      const snapshot=await tx.get(query.limit(limit+1));
      const docs=snapshot.docs.slice(0,limit);
      const records=await Promise.all(docs.map(async d=>{
        const record=project(kind,d);
        if(kind==='invitations')record.canRevoke=admin && record.status==='pending' && canManageAccessOf(member,record.access?.role,context);
        if(kind==='requests')record.canReview=admin && record.status==='pending';
        if(kind==='access')record.canManageAccess=admin && record.ownerId!==uid &&
          record.organizationId===input.organizationId && d.id===`${record.ownerId}_${input.organizationId}` &&
          canManageAccessOf(member,record.role,context);
        if(kind==='staff'){
          // UI hint only; saveStaff rechecks the same protection in its transaction.
          record.canEditProfile=admin;
          record.canManageAccess=false;
          if(admin && d.data().accountId){
            const linked=await tx.get(db.collection('memberships').doc(`${d.data().accountId}_${input.organizationId}`));
            if(linked.exists){
              record.canEditProfile=canManageAccessOf(member,linked.data().role,context);
              if(linked.data().organizationId===input.organizationId && linked.data().ownerId===d.data().accountId){
                record.accountAccess=project('access',linked);
                record.canManageAccess=record.canEditProfile && d.data().accountId!==uid;
              }
            }
          }
        }
        return record;
      }));
      return {records,nextCursor:snapshot.docs.length>limit?docs.at(-1).id:null};
    });
  };
}
// A recipient can inspect only the exact invitation addressed to their verified
// email. Organization membership is not required and no directory data is read.
function createInvitationLookupHandler({db,HttpsError}) {
  const fail=(code,message)=>{throw new HttpsError(code,message);};
  return async request=>{
    if(!request.auth?.uid)fail('unauthenticated','team_sign_in_required');
    if(request.auth.token?.email_verified!==true || typeof request.auth.token.email!=='string')fail('permission-denied','team_verified_email_required');
    const invitationId=request.data?.invitationId;
    if(!id(invitationId))fail('invalid-argument','team_invalid_id');
    return db.runTransaction(async tx=>{
      const doc=await tx.get(db.collection('teamInvitations').doc(invitationId));
      if(!doc.exists || doc.data().email!==request.auth.token.email.trim().toLowerCase())fail('not-found','team_invitation_unavailable');
      const invitation=doc.data();
      const org=await tx.get(db.collection('organizations').doc(invitation.organizationId));
      if(!org.exists || org.data().accessVersion!==2)fail('failed-precondition','team_migration_required');
      if(org.data().closedAt)fail('failed-precondition','org_closed');
      const mine=await tx.get(db.collection('memberships').doc(`${request.auth.uid}_${invitation.organizationId}`));
      const expired=!invitation.expiresAt?.toMillis || invitation.expiresAt.toMillis()<=Date.now();
      const grant=invitation.access ?? {};
      const properties=[];
      for(const key of (Array.isArray(grant.buildingIds)?grant.buildingIds:[]).slice(0,100)){
        if(!id(key))continue;
        const property=await tx.get(db.collection('buildings').doc(key));
        if(property.exists&&property.data().organizationId===org.id)properties.push({id:key,name:property.data().name??key});
      }
      // Return only the grant the recipient is about to accept, never other users.
      return {invitationId,organizationId:org.id,organizationName:org.data().name ?? '',
        access:serialize(Object.fromEntries(['accessVersion','role','buildingScope','buildingIds','permissionOverrides'].filter(k=>grant[k]!==undefined).map(k=>[k,grant[k]]))),
        properties,expiresAt:serialize(invitation.expiresAt)??null,
        status:invitation.status==='pending'&&expired?'expired':invitation.status,
        roleRemoved:!Object.hasOwn(roles,grant.role),
        canAccept:invitation.status==='pending'&&!expired&&!mine.exists&&Object.hasOwn(roles,grant.role)};
    });
  };
}
module.exports={createTeamReadHandler,createInvitationLookupHandler,serialize};
