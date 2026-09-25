'use strict';

const {createHash, randomUUID} = require('node:crypto');
const {permissions, roles, overrides, allows, canManageAccessOf} = require('./team_access');

/** All team writes and their audit events commit atomically. Not a migration API. */
function createTeamHandler({db, Timestamp, HttpsError}) {
  const fail = (code, message) => { throw new HttpsError(code, message); };
  const id = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
  const text = (value, max, required = false) => {
    if (typeof value !== 'string' || value.length > max || (required && !value.trim())) fail('invalid-argument', 'team_invalid_input');
    return value.trim();
  };
  const canonical = value => {
    if (Array.isArray(value)) return value.map(canonical);
    if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])]));
    return value;
  };
  const digest = value => createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');
  const access = input => {
    if (!input || !Object.hasOwn(roles, input.role) || input.role === 'owner' ||
        !['all', 'selected'].includes(input.buildingScope) || !Array.isArray(input.buildingIds) ||
        input.buildingIds.length > 100 || !input.buildingIds.every(id) ||
        new Set(input.buildingIds).size !== input.buildingIds.length ||
        (input.buildingScope === 'all' && input.buildingIds.length)) fail('invalid-argument', 'team_invalid_access');
    const custom = input.permissionOverrides ?? {};
    if (!custom || typeof custom !== 'object' || Array.isArray(custom) ||
        Object.entries(custom).some(([key, value]) => !overrides.includes(key) || typeof value !== 'boolean')) fail('invalid-argument', 'team_invalid_override');
    return {accessVersion: 2, role: input.role, buildingScope: input.buildingScope,
      buildingIds: [...input.buildingIds].sort(), permissionOverrides: {...custom}};
  };

  return async request => {
    const uid = request.auth?.uid;
    if (!uid) fail('unauthenticated', 'team_sign_in_required');
    const input = request.data;
    if (!input || !id(input.organizationId) || !id(input.operationId)) fail('invalid-argument', 'team_invalid_input');
    const orgId = input.organizationId;
    const action = input.action;
    const publicActions = ['acceptInvitation', 'requestAccess'];
    if (![...publicActions, 'saveStaff', 'invite', 'revokeInvitation', 'reviewRequest', 'setAccess'].includes(action)) fail('invalid-argument', 'team_invalid_action');
    const operationKey = digest([orgId, uid, input.operationId]);
    const fingerprint = digest(input);
    const operationRef = db.collection('teamOperations').doc(operationKey);
    const eventRef = db.collection('teamActivity').doc(operationKey);
    const generatedId = randomUUID();
    return db.runTransaction(async tx => {
      const org = await tx.get(db.collection('organizations').doc(orgId));
      // A coordinated migration must explicitly enable v2. Never bootstrap from createdBy.
      if (!org.exists || org.data().accessVersion !== 2) fail('failed-precondition', 'team_migration_required');
      const actorRef = db.collection('memberships').doc(`${uid}_${orgId}`);
      const actorDoc = await tx.get(actorRef);
      const actor = actorDoc.exists ? actorDoc.data() : null;
      const context = {organizationId: orgId, userId: uid};
      if (!publicActions.includes(action) && !allows(actor, 'manageTeam', context)) fail('permission-denied', 'team_access_denied');
      if (!publicActions.includes(action) && actor.buildingScope !== 'all') fail('permission-denied', 'team_all_buildings_required');
      const prior = await tx.get(operationRef);
      if (prior.exists) {
        if (prior.data().fingerprint !== fingerprint) fail('already-exists', 'team_operation_reused');
        return prior.data().result;
      }
      const now = Timestamp.now();
      const writes = [];
      let result, targetId, before = null, after = null;
      const read = async (collection, key) => {
        if (!id(key)) fail('invalid-argument', 'team_invalid_id');
        const ref = db.collection(collection).doc(key);
        const doc = await tx.get(ref);
        if (!doc.exists || doc.data().organizationId !== orgId) fail('not-found', 'team_record_not_found');
        return {ref, data: doc.data()};
      };
      const validateGrant = async grant => {
        if (!canManageAccessOf(actor, grant.role, context)) fail('permission-denied', 'team_role_protected');
        for (const p of permissions) if (allows({...grant,status:'active'},p) && !allows(actor,p,context)) fail('permission-denied', 'team_grant_exceeds_access');
        for (const buildingId of grant.buildingIds) await read('buildings', buildingId);
      };
      const managedStaff = async staffId => {
        const staff = await read('staffProfiles', staffId);
        if (staff.data.accountId) {
          const linked = await tx.get(db.collection('memberships').doc(`${staff.data.accountId}_${orgId}`));
          if (linked.exists && !canManageAccessOf(actor, linked.data().role, context)) fail('permission-denied', 'team_role_protected');
        }
        return staff;
      };
      const verifiedEmail = () => {
        if (request.auth.token?.email_verified !== true || typeof request.auth.token.email !== 'string') fail('permission-denied', 'team_verified_email_required');
        return request.auth.token.email.trim().toLowerCase();
      };
      const activate = (userId, email, staff, grant) => {
        const membershipRef = db.collection('memberships').doc(`${userId}_${orgId}`);
        writes.push(['set', membershipRef, {...grant, organizationId: orgId, ownerId: userId,
          staffId: staff.ref.id, status: 'active', displayName: staff.data.displayName,
          email, joinedAt: now, updatedAt: now, updatedBy: uid}]);
        writes.push(['update', staff.ref, {accountId: userId, updatedAt: now}]);
      };

      if (action === 'saveStaff') {
        const fields = input.profile;
        if (!fields || Object.keys(fields).some(k => !['displayName','code','email','phone','color','employmentStatus'].includes(k))) fail('invalid-argument', 'team_invalid_profile');
        const profile = {displayName: text(fields.displayName, 120, true), code: text(fields.code, 40, true),
          email: text(fields.email ?? '', 254), phone: text(fields.phone ?? '', 40),
          color: text(fields.color ?? '', 7), employmentStatus: fields.employmentStatus ?? 'active'};
        if (!['active','inactive'].includes(profile.employmentStatus) ||
            (profile.color && !/^#[0-9a-fA-F]{6}$/.test(profile.color))) fail('invalid-argument', 'team_invalid_profile');
        targetId = input.staffId ?? generatedId;
        if (!id(targetId)) fail('invalid-argument', 'team_invalid_id');
        const existing = input.staffId ? await managedStaff(input.staffId) : null;
        const duplicates = await tx.get(db.collection('staffProfiles').where('organizationId','==',orgId).where('code','==',profile.code));
        if (duplicates.docs.some(d => d.id !== targetId)) fail('already-exists', 'team_staff_code_exists');
        before = existing ? {displayName: existing.data.displayName, employmentStatus: existing.data.employmentStatus} : null;
        after = {displayName: profile.displayName, employmentStatus: profile.employmentStatus};
        const ref = existing?.ref ?? db.collection('staffProfiles').doc(targetId);
        writes.push([existing ? 'update' : 'create', ref, {...profile, updatedAt: now,
          ...(existing ? {} : {organizationId: orgId, accountId: null, createdAt: now, createdBy: uid})}]);
        result = {staffId: targetId};
      } else if (action === 'invite') {
        const grant = access(input.access);
        await validateGrant(grant);
        const staff = await managedStaff(input.staffId);
        if (staff.data.accountId || staff.data.employmentStatus !== 'active') fail('failed-precondition', 'team_staff_unavailable');
        const email = text(input.email, 254, true).toLowerCase();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) fail('invalid-argument', 'team_invalid_email');
        targetId = generatedId;
        writes.push(['create', db.collection('teamInvitations').doc(targetId), {
          organizationId: orgId, staffId: staff.ref.id, email, access: grant,
          status: 'pending', invitedBy: uid, createdAt: now,
          expiresAt: Timestamp.fromMillis(now.toMillis() + 7 * 86400000)}]);
        result = {invitationId: targetId}; after = {staffId: staff.ref.id, ...grant};
      } else if (action === 'revokeInvitation') {
        const invitation = await read('teamInvitations', input.invitationId);
        if (!canManageAccessOf(actor, invitation.data.access.role, context)) fail('permission-denied', 'team_role_protected');
        if (invitation.data.status !== 'pending') fail('failed-precondition', 'team_invitation_closed');
        writes.push(['update', invitation.ref, {status:'revoked', updatedAt:now}]);
        targetId = invitation.ref.id; result = {status:'revoked'};
      } else if (action === 'acceptInvitation') {
        const email = verifiedEmail();
        const invitation = await read('teamInvitations', input.invitationId);
        if (invitation.data.email !== email) fail('permission-denied', 'team_invitation_recipient');
        if (invitation.data.status !== 'pending' || invitation.data.expiresAt.toMillis() <= now.toMillis()) fail('failed-precondition', 'team_invitation_closed');
        // Any existing membership requires explicit access review, never invite escalation.
        if (actorDoc.exists) fail('already-exists', 'team_existing_access');
        const inviterDoc = await tx.get(db.collection('memberships').doc(`${invitation.data.invitedBy}_${orgId}`));
        const inviter = inviterDoc.exists ? inviterDoc.data() : null;
        const grant = access(invitation.data.access);
        if (!canManageAccessOf(inviter, grant.role, {organizationId:orgId,userId:invitation.data.invitedBy}) || inviter.buildingScope !== 'all' ||
            permissions.some(p=>allows({...grant,status:'active'},p) && !allows(inviter,p))) fail('permission-denied', 'team_inviter_access_changed');
        for (const b of grant.buildingIds) await read('buildings', b);
        const staff = await read('staffProfiles', invitation.data.staffId);
        if (staff.data.accountId || staff.data.employmentStatus !== 'active') fail('failed-precondition', 'team_staff_unavailable');
        const linked = await tx.get(db.collection('staffProfiles').where('organizationId','==',orgId).where('accountId','==',uid));
        if (linked.docs.length) fail('already-exists', 'team_account_already_linked');
        activate(uid, email, staff, grant);
        writes.push(['update', invitation.ref, {status:'accepted', acceptedBy:uid, acceptedAt:now}]);
        targetId = invitation.ref.id; result = {status:'active', staffId:staff.ref.id}; after = grant;
      } else if (action === 'requestAccess') {
        const email = verifiedEmail();
        if (actorDoc.exists) fail('already-exists', 'team_existing_access');
        if (!id(input.inviteCode)) fail('invalid-argument','team_invalid_code');
        const code = await tx.get(db.collection('invite_codes').doc(input.inviteCode));
        if (!code.exists || code.data().orgId !== orgId) fail('permission-denied','team_invalid_code');
        targetId = `${uid}_${orgId}`;
        const ref = db.collection('teamRequests').doc(targetId);
        const old = await tx.get(ref);
        if (old.exists) fail('already-exists','team_request_exists');
        writes.push(['create',ref,{organizationId:orgId, userId:uid, email,
          displayName:text(input.displayName,120,true),status:'pending',createdAt:now}]);
        result = {requestId:targetId,status:'pending'};
      } else if (action === 'reviewRequest') {
        const pending = await read('teamRequests', input.requestId);
        if (pending.data.status !== 'pending') fail('failed-precondition','team_request_closed');
        if (!['approve','reject'].includes(input.decision)) fail('invalid-argument','team_invalid_decision');
        if (input.decision === 'approve') {
          const grant = access(input.access); await validateGrant(grant);
          const staff = await managedStaff(input.staffId);
          const existing = await tx.get(db.collection('memberships').doc(`${pending.data.userId}_${orgId}`));
          const linked = await tx.get(db.collection('staffProfiles').where('organizationId','==',orgId).where('accountId','==',pending.data.userId));
          if (existing.exists || linked.docs.length || staff.data.accountId || staff.data.employmentStatus !== 'active') fail('failed-precondition','team_staff_unavailable');
          activate(pending.data.userId, pending.data.email, staff, grant); after = grant;
        }
        const status = input.decision === 'approve' ? 'approved' : 'rejected';
        writes.push(['update',pending.ref,{status,reviewedBy:uid,reviewedAt:now}]);
        targetId = pending.ref.id; result = {status};
      } else if (action === 'setAccess') {
        if (!id(input.userId) || input.userId === uid) fail('permission-denied','team_self_access_change');
        const target = await read('memberships', `${input.userId}_${orgId}`);
        if (target.data.ownerId !== input.userId || !canManageAccessOf(actor,target.data.role,context)) fail('permission-denied','team_role_protected');
        const grant = access(input.access); await validateGrant(grant);
        if (!['active','suspended','revoked'].includes(input.status)) fail('invalid-argument','team_invalid_status');
        const reason = text(input.reason,500,true);
        before = {role:target.data.role,status:target.data.status,buildingScope:target.data.buildingScope ?? null,buildingIds:target.data.buildingIds ?? [],permissionOverrides:target.data.permissionOverrides ?? {}};
        after = {...grant,status:input.status};
        writes.push(['update',target.ref,{...after,updatedAt:now,updatedBy:uid}]);
        targetId = target.ref.id; result = {status:input.status};
        writes.push(['create',eventRef,{organizationId:orgId,actorId:uid,action,targetId,before,after,reason,createdAt:now}]);
      }
      if (action !== 'setAccess') writes.push(['create',eventRef,{organizationId:orgId,actorId:uid,action,targetId,before,after,createdAt:now}]);
      writes.push(['create',operationRef,{organizationId:orgId,actorId:uid,fingerprint,result,createdAt:now}]);
      for (const [method,ref,value] of writes) tx[method](ref,value);
      return result;
    });
  };
}
module.exports = {createTeamHandler};
