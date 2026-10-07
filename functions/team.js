'use strict';

const {createHash, randomUUID} = require('node:crypto');
const {overrides, allows, canManageAccessOf, canAssignGrants, effectiveGrants, grantsLevel, memberLevel} = require('./team_access');
const {resolveRole, roleFields} = require('./roles');
const {accountPolicy,policyLocks,emailOwnsOrganizations,checkEmployer,prepareBinding}=require('./account_policy');

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
    // The role itself (template or organization role) is resolved inside the transaction.
    if (!input || typeof input.role !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(input.role) || input.role === 'owner' ||
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
    if (![...publicActions, 'saveStaff', 'invite', 'addStaff', 'changeInvitationEmail', 'revokeInvitation', 'reviewRequest', 'setAccess'].includes(action)) fail('invalid-argument', 'team_invalid_action');
    const operationKey = digest([orgId, uid, input.operationId]);
    const fingerprint = digest(input);
    const operationRef = db.collection('teamOperations').doc(operationKey);
    const eventRef = db.collection('teamActivity').doc(operationKey);
    const generatedId = randomUUID(), secondId = randomUUID();
    // Gmail pre-approvals (R2) have no expiry (expiresAt null); link invitations keep theirs.
    const open = inv => inv.status === 'pending' && (inv.expiresAt == null || inv.expiresAt.toMillis() > Timestamp.now().toMillis());
    const emailOk = value => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
    return db.runTransaction(async tx => {
      const org = await tx.get(db.collection('organizations').doc(orgId));
      // A coordinated migration must explicitly enable v2. Never bootstrap from createdBy.
      if (!org.exists || org.data().accessVersion !== 2) fail('failed-precondition', 'team_migration_required');
      if (org.data().closedAt) fail('failed-precondition', 'org_closed');
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
      const policyCommits = [];
      let employerShareId = null;
      const checkStaffAccount = async (userId, email, approvedBy = uid, primary = false) => {
        policyCommits.push(await policyLocks(db,tx,userId,email));
        if ((await accountPolicy(db,tx,userId)).hasOwned) fail('failed-precondition','team_owner_account');
        const primaryWorkplace=await checkEmployer(db,tx,{uid:userId,email,orgId},fail);
        if(action!=='requestAccess')policyCommits.push(await prepareBinding(db,tx,userId,orgId,{email,source:action},fail));
        return primaryWorkplace;
      };
      const checkStaffEmail = async email => {
        policyCommits.push(await policyLocks(db,tx,null,email));
        if (await emailOwnsOrganizations(db,tx,email)) fail('failed-precondition','team_owner_account');
        return checkEmployer(db,tx,{email,orgId,approvedBy:uid,onShare:key=>{employerShareId=key;}},fail);
      };
      let result, targetId, before = null, after = null;
      const read = async (collection, key) => {
        if (!id(key)) fail('invalid-argument', 'team_invalid_id');
        const ref = db.collection(collection).doc(key);
        const doc = await tx.get(ref);
        if (!doc.exists || doc.data().organizationId !== orgId) fail('not-found', 'team_record_not_found');
        return {ref, data: doc.data()};
      };
      // Resolves the role, checks the actor may give it, and returns the membership
      // fields to store (grant + grants copy for organization roles).
      const roleCache = new Map();
      const role = async roleId => {
        if (!roleCache.has(roleId)) roleCache.set(roleId, await resolveRole(db, tx, orgId, roleId));
        return roleCache.get(roleId);
      };
      const grantedBy = (who, grant, resolved) => effectiveGrants({...grant, ...roleFields(resolved), ownerId: who?.ownerId, accessVersion: 2, status: 'active'});
      const validateGrant = async grant => {
        const resolved = await role(grant.role);
        if (!resolved) fail('failed-precondition', 'team_role_not_found');
        const effective = grantedBy(actor, grant, resolved);
        if (grantsLevel(effective) >= memberLevel(actor)) fail('permission-denied', 'team_role_protected');
        if (!canAssignGrants(actor, effective, context)) fail('permission-denied', 'team_grant_exceeds_access');
        for (const buildingId of grant.buildingIds) await read('buildings', buildingId);
        return {...grant, ...roleFields(resolved)};
      };
      // Level of an invitation's role for revoke/protection checks (deleted role = 0).
      const invitationTarget = async access => {
        const resolved = await role(access?.role);
        return resolved ? {role: access.role, ...roleFields(resolved), permissionOverrides: access.permissionOverrides ?? {}} : {role: null};
      };
      const managedStaff = async staffId => {
        const staff = await read('staffProfiles', staffId);
        if (staff.data.accountId) {
          const linked = await tx.get(db.collection('memberships').doc(`${staff.data.accountId}_${orgId}`));
          if (linked.exists && !canManageAccessOf(actor, linked.data(), context)) fail('permission-denied', 'team_role_protected');
        }
        return staff;
      };
      const verifiedEmail = () => {
        if (request.auth.token?.email_verified !== true || typeof request.auth.token.email !== 'string') fail('permission-denied', 'team_verified_email_required');
        return request.auth.token.email.trim().toLowerCase();
      };
      const activate = (userId, email, staff, grant, approvedBy = uid, employerPrimary = false) => {
        const membershipRef = db.collection('memberships').doc(`${userId}_${orgId}`);
        writes.push(['set', membershipRef, {...grant, organizationId: orgId, ownerId: userId,
          staffId: staff.ref.id, employerShareId, employerApprovedBy: approvedBy, employerPrimary, status: 'active', displayName: staff.data.displayName,
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
        const employerPrimary = await checkStaffEmail(email);
        targetId = generatedId;
        writes.push(['create', db.collection('teamInvitations').doc(targetId), {
          organizationId: orgId, staffId: staff.ref.id, email, access: grant,
          status: 'pending', employerPrimary, employerApprovedBy: uid, invitedBy: uid, createdAt: now,
          expiresAt: Timestamp.fromMillis(now.toMillis() + 7 * 86400000)}]);
        result = {invitationId: targetId}; after = {staffId: staff.ref.id, ...grant};
      } else if (action === 'revokeInvitation') {
        const invitation = await read('teamInvitations', input.invitationId);
        if (!canManageAccessOf(actor, await invitationTarget(invitation.data.access), context)) fail('permission-denied', 'team_role_protected');
        if (invitation.data.status !== 'pending') fail('failed-precondition', 'team_invitation_closed');
        writes.push(['update', invitation.ref, {status:'revoked', updatedAt:now}]);
        targetId = invitation.ref.id; result = {status:'revoked'};
        before = {status:'pending'}; after = {status:'revoked'};
      } else if (action === 'acceptInvitation') {
        const email = verifiedEmail();
        const invitation = await read('teamInvitations', input.invitationId);
        if (invitation.data.email !== email) fail('permission-denied', 'team_invitation_recipient');
        if (!open(invitation.data)) fail('failed-precondition', 'team_invitation_closed');
        // Any existing membership requires explicit access review, never invite escalation.
        // Any existing membership requires explicit access review, except one that was
        // revoked: a removed person who is added again may join again (R2).
        await checkStaffAccount(uid,email,invitation.data.employerApprovedBy??invitation.data.invitedBy,invitation.data.employerPrimary===true);
        const rejoining = actorDoc.exists && actorDoc.data().status === 'revoked';
        if (actorDoc.exists && !rejoining) fail('already-exists', 'team_existing_access');
        const inviterDoc = await tx.get(db.collection('memberships').doc(`${invitation.data.invitedBy}_${orgId}`));
        const inviter = inviterDoc.exists ? inviterDoc.data() : null;
        // A role removed after the invitation was sent (e.g. viewer, or a deleted
        // organization role) cannot be accepted. An edited role gives its current grants.
        const resolved = await role(invitation.data.access?.role);
        if (!resolved) fail('failed-precondition', 'team_invitation_role_removed');
        const grant = {...access(invitation.data.access), ...roleFields(resolved)};
        if (!inviter || !canAssignGrants(inviter, grantedBy(inviter, grant, resolved), {organizationId:orgId,userId:invitation.data.invitedBy})) fail('permission-denied', 'team_inviter_access_changed');
        for (const b of grant.buildingIds) await read('buildings', b);
        const staff = await read('staffProfiles', invitation.data.staffId);
        // A re-joining person may get back the profile that is still linked to them.
        if ((staff.data.accountId && !(rejoining && staff.data.accountId === uid)) || staff.data.employmentStatus !== 'active') fail('failed-precondition', 'team_staff_unavailable');
        const linked = await tx.get(db.collection('staffProfiles').where('organizationId','==',orgId).where('accountId','==',uid));
        if (linked.docs.length && !rejoining) fail('already-exists', 'team_account_already_linked');
        // Re-joining: the old staff profile keeps its history but is no longer linked.
        for (const old of linked.docs) if (old.id !== staff.ref.id) writes.push(['update', old.ref, {accountId: null, updatedAt: now}]);
        activate(uid, email, staff, grant, invitation.data.employerApprovedBy??invitation.data.invitedBy,invitation.data.employerPrimary===true);
        writes.push(['update', invitation.ref, {status:'accepted', acceptedBy:uid, acceptedAt:now}]);
        targetId = invitation.ref.id; result = {status:'active', staffId:staff.ref.id}; after = grant;
      } else if (action === 'addStaff') {
        // R2: staff profile + Gmail pre-approval in one step. The person joins by
        // signing in with that Gmail (claimMyInvitations); no link to send.
        const fields = input.profile;
        if (!fields || typeof fields !== 'object' || Object.keys(fields).some(k => !['displayName','email','phone'].includes(k))) fail('invalid-argument', 'team_invalid_profile');
        const displayName = text(fields.displayName, 120, true);
        const phone = text(fields.phone ?? '', 40);
        const email = text(fields.email, 254, true).toLowerCase();
        if (!emailOk(email)) fail('invalid-argument', 'team_invalid_email');
        const grant = access(input.access);
        await validateGrant(grant);
        const employerPrimary = await checkStaffEmail(email);
        const members = await tx.get(db.collection('memberships').where('organizationId','==',orgId).where('email','==',email));
        if (members.docs.some(m => m.data().status !== 'revoked')) fail('already-exists', 'team_email_already_member');
        const pending = await tx.get(db.collection('teamInvitations').where('organizationId','==',orgId).where('email','==',email));
        if (pending.docs.some(i => open(i.data()))) fail('already-exists', 'team_email_already_invited');
        const all = await tx.get(db.collection('staffProfiles').where('organizationId','==',orgId));
        // Reuse a profile with this email that nobody uses now (an earlier pre-approval
        // that was removed, or a person who left), so one person keeps one profile.
        let reuse = null;
        for (const p of all.docs.filter(d => (d.data().email ?? '').toLowerCase() === email)) {
          if (!p.data().accountId) { reuse = p; break; }
          const m = await tx.get(db.collection('memberships').doc(`${p.data().accountId}_${orgId}`));
          if (!m.exists || m.data().status === 'revoked') { reuse = p; break; }
        }
        const codes = new Set(all.docs.map(d => d.data().code));
        let n = all.docs.length + 1;
        for (let i = 1; i <= all.docs.length + 1; i++) if (!codes.has(`S${String(i).padStart(2, '0')}`)) { n = i; break; }
        const code = reuse ? reuse.data().code : `S${String(n).padStart(2, '0')}`;
        const staffRef = reuse ? reuse.ref : db.collection('staffProfiles').doc(generatedId);
        if (reuse) writes.push(['update', staffRef, {displayName, email, phone, employmentStatus: 'active', updatedAt: now}]);
        else writes.push(['create', staffRef, {organizationId: orgId, code, displayName, email, phone, color: '',
          employmentStatus: 'active', accountId: null, createdAt: now, createdBy: uid, updatedAt: now}]);
        targetId = secondId;
        writes.push(['create', db.collection('teamInvitations').doc(targetId), {organizationId: orgId, staffId: staffRef.id,
          email, access: grant, employerPrimary, employerApprovedBy: uid, status: 'pending', kind: 'gmail', invitedBy: uid, createdAt: now, expiresAt: null}]);
        result = {staffId: staffRef.id, invitationId: targetId, code};
        after = {staffId: staffRef.id, code, ...grant};
      } else if (action === 'changeInvitationEmail') {
        // Fix a typo in a Gmail before the person's first sign-in.
        const invitation = await read('teamInvitations', input.invitationId);
        if (!canManageAccessOf(actor, await invitationTarget(invitation.data.access), context)) fail('permission-denied', 'team_role_protected');
        if (!open(invitation.data)) fail('failed-precondition', 'team_invitation_closed');
        const email = text(input.email, 254, true).toLowerCase();
        if (!emailOk(email)) fail('invalid-argument', 'team_invalid_email');
        const employerPrimary = await checkStaffEmail(email);
        const members = await tx.get(db.collection('memberships').where('organizationId','==',orgId).where('email','==',email));
        if (members.docs.some(m => m.data().status !== 'revoked')) fail('already-exists', 'team_email_already_member');
        const pending = await tx.get(db.collection('teamInvitations').where('organizationId','==',orgId).where('email','==',email));
        if (pending.docs.some(i => i.id !== invitation.ref.id && open(i.data()))) fail('already-exists', 'team_email_already_invited');
        const staffDoc = await tx.get(db.collection('staffProfiles').doc(invitation.data.staffId));
        writes.push(['update', invitation.ref, {email, employerPrimary, employerApprovedBy: uid, updatedAt: now}]);
        if (staffDoc.exists && staffDoc.data().organizationId === orgId && !staffDoc.data().accountId) writes.push(['update', staffDoc.ref, {email, updatedAt: now}]);
        targetId = invitation.ref.id; result = {status: 'pending'};
        // No addresses in the activity log.
        before = {emailChanged: false}; after = {emailChanged: true};
      } else if (action === 'requestAccess') {
        const email = verifiedEmail();
        if (actorDoc.exists) fail('already-exists', 'team_existing_access');
        await checkStaffAccount(uid,email);
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
          const employerPrimary = await checkStaffAccount(pending.data.userId,pending.data.email);
          const grant = await validateGrant(access(input.access));
          const staff = await managedStaff(input.staffId);
          const existing = await tx.get(db.collection('memberships').doc(`${pending.data.userId}_${orgId}`));
          const linked = await tx.get(db.collection('staffProfiles').where('organizationId','==',orgId).where('accountId','==',pending.data.userId));
          if (existing.exists || linked.docs.length || staff.data.accountId || staff.data.employmentStatus !== 'active') fail('failed-precondition','team_staff_unavailable');
          activate(pending.data.userId, pending.data.email, staff, grant,uid,employerPrimary); after = grant;
        }
        const status = input.decision === 'approve' ? 'approved' : 'rejected';
        writes.push(['update',pending.ref,{status,reviewedBy:uid,reviewedAt:now}]);
        targetId = pending.ref.id; result = {status};
        before = {status:'pending'}; after = {...(after || {}),requestStatus:status};
      } else if (action === 'setAccess') {
        if (!id(input.userId) || input.userId === uid) fail('permission-denied','team_self_access_change');
        const target = await read('memberships', `${input.userId}_${orgId}`);
        if (target.data.ownerId !== input.userId || !canManageAccessOf(actor,target.data,context)) fail('permission-denied','team_role_protected');
        const grant = await validateGrant(access(input.access));
        if (!['active','suspended','revoked'].includes(input.status)) fail('invalid-argument','team_invalid_status');
        if(input.status==='revoked'){policyCommits.push(await policyLocks(db,tx,input.userId,target.data.email));policyCommits.push(await prepareBinding(db,tx,input.userId,orgId,{release:true,source:'revoke'},fail));}
        if (input.status !== 'revoked') await checkStaffAccount(input.userId,target.data.email, (((org.data().ownerTransferredTo ?? org.data().createdBy) === uid || allows(actor, 'assignAdditionalWorkplace', context)) ? uid : target.data.employerApprovedBy ?? uid),target.data.employerPrimary===true && target.data.status!=='revoked');
        const reason = text(input.reason,500,true);
        before = {role:target.data.role,roleRevision:target.data.roleRevision ?? null,status:target.data.status,buildingScope:target.data.buildingScope ?? null,buildingIds:target.data.buildingIds ?? [],permissionOverrides:target.data.permissionOverrides ?? {}};
        after = {...grant,status:input.status,...(input.status!=='revoked'?{employerShareId}:{}),employerApprovedBy:(((org.data().ownerTransferredTo ?? org.data().createdBy) === uid || allows(actor, 'assignAdditionalWorkplace', context)) ? uid : target.data.employerApprovedBy ?? uid)};
        // Members who joined before v2 (or any account without a staff record)
        // get a linked staff profile, so they appear in the staff list like
        // invited staff. Reuses a profile already linked to the account.
        let staffLink = {};
        if (input.status !== 'revoked') {
          const current = target.data.staffId && id(target.data.staffId)
            ? await tx.get(db.collection('staffProfiles').doc(target.data.staffId)) : null;
          const valid = current?.exists && current.data().organizationId === orgId && current.data().accountId === input.userId;
          if (!valid) {
            const linked = await tx.get(db.collection('staffProfiles').where('organizationId','==',orgId).where('accountId','==',input.userId));
            if (linked.docs.length) {
              staffLink = {staffId: linked.docs[0].id};
            } else {
              const staffId = digest(['staffFor', orgId, input.userId]).slice(0, 28);
              const base = 'ACC-' + staffId.slice(0, 6).toUpperCase();
              const taken = await tx.get(db.collection('staffProfiles').where('organizationId','==',orgId).where('code','==',base));
              const code = taken.docs.some(d => d.id !== staffId) ? 'ACC-' + staffId.slice(0, 12).toUpperCase() : base;
              const name = typeof target.data.displayName === 'string' && target.data.displayName.trim()
                ? target.data.displayName.trim().slice(0, 120)
                : (typeof target.data.email === 'string' && target.data.email) || 'Staff';
              writes.push(['set', db.collection('staffProfiles').doc(staffId), {organizationId: orgId, code, displayName: name,
                email: typeof target.data.email === 'string' ? target.data.email.slice(0, 254) : '', phone: '', color: '',
                employmentStatus: 'active', accountId: input.userId, createdAt: now, createdBy: uid, updatedAt: now}]);
              staffLink = {staffId};
            }
            after = {...after, ...staffLink};
          }
        }
        writes.push(['update',target.ref,{...after,updatedAt:now,updatedBy:uid}]);
        targetId = target.ref.id; result = {status:input.status};
        writes.push(['create',eventRef,{organizationId:orgId,actorId:uid,action,targetId,before,after,reason,createdAt:now}]);
      }
      if (action !== 'setAccess') writes.push(['create',eventRef,{organizationId:orgId,actorId:uid,action,targetId,before,after,createdAt:now}]);
      writes.push(['create',operationRef,{organizationId:orgId,actorId:uid,fingerprint,result,createdAt:now}]);
      for (const commit of policyCommits) commit();
      if(writes.some(([,ref])=>ref.path.startsWith('staffProfiles/')))tx.update(org.ref,{staffInventoryUpdatedAt:now});
      for (const [method,ref,value] of writes) tx[method](ref,value);
      return result;
    });
  };
}
module.exports = {createTeamHandler};
