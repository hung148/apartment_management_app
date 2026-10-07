'use strict';

const {createHash} = require('node:crypto');
const {templates, knownRole, cleanGrants, parseGrants, allows, canEditRole, canAssignGrants,
  memberLevel, grantsLevel} = require('./team_access');

const MAX_CUSTOM_ROLES = 30;
const MAX_MEMBERS_PER_ROLE = 400;
// Statuses that still hold a role. A revoked membership keeps its old role only as history.
const HOLDING = ['active', 'suspended', 'assignmentRequired', 'invited'];

/**
 * Organization roles (R1). One document per role in `orgRoles/{orgId}_{roleId}`.
 * Template roles (administrator, manager, ...) exist without a document until
 * someone edits or deletes them. Owner is fixed and never stored.
 * Saving a role rewrites the grants copy on every membership that has it, in
 * the same transaction, so everyone's access changes at the same moment.
 */
function createRolesHandler({db, Timestamp, HttpsError}) {
  const fail = (code, message) => { throw new HttpsError(code, message); };
  const id = v => typeof v === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(v);
  const roleIdOk = v => typeof v === 'string' && v !== 'owner' && (knownRole(v) || /^r_[A-Za-z0-9]{8,32}$/.test(v));
  const hash = v => createHash('sha256').update(JSON.stringify(v)).digest('hex');
  const roleRef = (orgId, roleId) => db.collection('orgRoles').doc(`${orgId}_${roleId}`);

  /** Current definition: {grants, revision, name, color, template, stored} or null (missing/deleted). */
  function current(roleId, doc) {
    if (doc?.exists) {
      const x = doc.data();
      if (x.deletedAt) return null;
      return {grants: cleanGrants(x.grants) ?? {}, revision: Number.isInteger(x.revision) ? x.revision : 0,
        name: typeof x.name === 'string' ? x.name : '', color: typeof x.color === 'string' ? x.color : '',
        template: typeof x.template === 'string' ? x.template : null, stored: true, createdAt: x.createdAt ?? null,
        createdBy: x.createdBy ?? null};
    }
    if (knownRole(roleId) && roleId !== 'owner') {
      return {grants: {...templates[roleId].grants}, revision: 0, name: '', color: templates[roleId].color,
        template: roleId, stored: false, createdAt: null, createdBy: null};
    }
    return null;
  }

  return async request => {
    const uid = request.auth?.uid;
    if (!uid) fail('unauthenticated', 'team_sign_in_required');
    const d = request.data || {};
    if (!id(d.organizationId) || !['list', 'save', 'delete'].includes(d.action)) fail('invalid-argument', 'role_invalid_input');
    const orgId = d.organizationId;
    const write = d.action !== 'list';
    let name, color, grants;
    if (write) {
      if (!id(d.operationId)) fail('invalid-argument', 'role_invalid_input');
      if (d.roleId !== undefined && !roleIdOk(d.roleId)) fail('invalid-argument', 'role_invalid_input');
      if (d.action === 'delete' && d.roleId === undefined) fail('invalid-argument', 'role_invalid_input');
      if (d.roleId !== undefined && (!Number.isInteger(d.expectedRevision) || d.expectedRevision < 0)) fail('invalid-argument', 'role_invalid_input');
      if (d.roleId === undefined && d.expectedRevision !== undefined) fail('invalid-argument', 'role_invalid_input');
    }
    if (d.action === 'save') {
      // A starter role may keep an empty name: the app then shows its translated name.
      const template = d.roleId !== undefined && knownRole(d.roleId);
      if (typeof d.name !== 'string' || (!d.name.trim() && !template) || d.name.trim().length > 40) fail('invalid-argument', 'role_invalid_name');
      name = d.name.trim().replace(/\s+/g, ' ');
      if (typeof d.color !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(d.color)) fail('invalid-argument', 'role_invalid_input');
      color = d.color.toUpperCase();
      grants = parseGrants(d.grants);
      if (!grants) fail('invalid-argument', 'role_invalid_grants');
    }
    const operationKey = hash(['roles', orgId, uid, d.operationId ?? '']);
    const fingerprint = hash(d);

    return db.runTransaction(async tx => {
      const org = await tx.get(db.collection('organizations').doc(orgId));
      if (!org.exists || org.data().accessVersion !== 2) fail('failed-precondition', 'team_migration_required');
      if (org.data().closedAt) fail('failed-precondition', 'org_closed');
      const actorDoc = await tx.get(db.collection('memberships').doc(`${uid}_${orgId}`));
      const actor = actorDoc.exists ? actorDoc.data() : null;
      const context = {organizationId: orgId, userId: uid};
      if (!allows(actor, 'manageTeam', context) && !allows(actor, 'manageRoles', context)) fail('permission-denied', 'team_access_denied');

      if (d.action === 'list') {
        const [stored, members, invitations] = await Promise.all([
          tx.get(db.collection('orgRoles').where('organizationId', '==', orgId)),
          tx.get(db.collection('memberships').where('organizationId', '==', orgId)),
          tx.get(db.collection('teamInvitations').where('organizationId', '==', orgId).where('status', '==', 'pending')),
        ]);
        const byId = new Map(stored.docs.filter(doc => doc.id === `${orgId}_${doc.data().roleId}`).map(doc => [doc.data().roleId, doc]));
        const count = new Map(), pending = new Map();
        for (const m of members.docs) {
          const x = m.data();
          if (m.id === `${x.ownerId}_${orgId}` && HOLDING.includes(x.status)) count.set(x.role, (count.get(x.role) ?? 0) + 1);
        }
        const now = Date.now();
        for (const inv of invitations.docs) {
          const x = inv.data();
          if (x.expiresAt == null || x.expiresAt.toMillis?.() > now) pending.set(x.access?.role, (pending.get(x.access?.role) ?? 0) + 1);
        }
        const ids = [...Object.keys(templates).filter(r => r !== 'owner'),
          ...[...byId.keys()].filter(r => !knownRole(r)).sort()];
        const roles = [{id: 'owner', template: 'owner', name: '', color: templates.owner.color,
          grants: {...templates.owner.grants}, revision: 0, fixed: true, members: count.get('owner') ?? 0,
          pendingInvitations: 0, canEdit: false, canDelete: false, canAssign: false}];
        for (const roleId of ids) {
          const role = current(roleId, byId.get(roleId));
          if (!role) continue;
          const members = count.get(roleId) ?? 0, invites = pending.get(roleId) ?? 0;
          const canEdit = canEditRole(actor, role.grants, role.grants, context);
          roles.push({id: roleId, template: role.template, name: role.name, color: role.color,
            grants: role.grants, revision: role.revision, fixed: false, members, pendingInvitations: invites,
            canEdit, canDelete: canEdit && members === 0 && invites === 0,
            canAssign: canAssignGrants(actor, role.grants, context)});
        }
        const custom = ids.filter(r => !knownRole(r)).length;
        return {roles, canCreate: allows(actor, 'manageRoles', context) && actor.buildingScope === 'all' && custom < MAX_CUSTOM_ROLES,
          myRole: actor.role, myLevel: memberLevel(actor)};
      }

      const operationRef = db.collection('teamOperations').doc(operationKey);
      const prior = await tx.get(operationRef);
      if (prior.exists) {
        if (prior.data().fingerprint !== fingerprint) fail('already-exists', 'team_operation_reused');
        return prior.data().result;
      }
      const creating = d.roleId === undefined;
      const roleId = creating ? `r_${operationKey.slice(0, 16)}` : d.roleId;
      const ref = roleRef(orgId, roleId);
      const doc = await tx.get(ref);
      const before = creating ? null : current(roleId, doc);
      if (creating && doc.exists) fail('already-exists', 'team_operation_reused');
      if (!creating && !before) fail('not-found', 'role_not_found');
      if (!creating && before.revision !== d.expectedRevision) fail('aborted', 'role_changed');
      const after = d.action === 'save' ? grants : null;
      if (!canEditRole(actor, before?.grants ?? null, after, context)) fail('permission-denied', 'role_edit_denied');

      const holders = await tx.get(db.collection('memberships').where('organizationId', '==', orgId).where('role', '==', roleId));
      const holding = holders.docs.filter(m => m.id === `${m.data().ownerId}_${orgId}`);
      const now = Timestamp.now();
      const revision = (before?.revision ?? 0) + 1;
      const writes = [];
      let result;

      if (d.action === 'save') {
        const stored = await tx.get(db.collection('orgRoles').where('organizationId', '==', orgId));
        const others = stored.docs.filter(r => r.data().roleId !== roleId && !r.data().deletedAt);
        if (name && others.some(r => typeof r.data().name === 'string' && r.data().name.toLowerCase() === name.toLowerCase())) fail('already-exists', 'role_name_exists');
        if (creating && others.filter(r => !knownRole(r.data().roleId)).length >= MAX_CUSTOM_ROLES) fail('resource-exhausted', 'role_limit_reached');
        if (holding.length > MAX_MEMBERS_PER_ROLE) fail('failed-precondition', 'role_too_many_members');
        writes.push(['set', ref, {organizationId: orgId, roleId, template: before?.template ?? null, name, color, grants,
          revision, createdAt: before?.createdAt ?? now, createdBy: before?.createdBy ?? uid,
          updatedAt: now, updatedBy: uid, deletedAt: null}]);
        // Everyone holding the role gets the new grants now (revoked ones too, harmlessly).
        for (const m of holding) writes.push(['update', m.ref, {roleGrants: grants, roleRevision: revision, roleName: name, updatedAt: now}]);
        result = {roleId, revision};
      } else {
        const invitations = await tx.get(db.collection('teamInvitations').where('organizationId', '==', orgId).where('status', '==', 'pending'));
        const inUse = holding.filter(m => HOLDING.includes(m.data().status)).length +
          invitations.docs.filter(i => i.data().access?.role === roleId && (i.data().expiresAt == null || i.data().expiresAt.toMillis?.() > now.toMillis())).length;
        if (inUse) fail('failed-precondition', 'role_in_use');
        writes.push(['set', ref, {organizationId: orgId, roleId, template: before.template, name: before.name,
          color: before.color, grants: before.grants, revision, createdAt: before.createdAt ?? now,
          createdBy: before.createdBy ?? uid, updatedAt: now, updatedBy: uid, deletedAt: now, deletedBy: uid}]);
        result = {roleId, deleted: true};
      }
      writes.push(['create', db.collection('teamActivity').doc(operationKey), {organizationId: orgId, actorId: uid,
        action: d.action === 'save' ? (creating ? 'createRole' : 'updateRole') : 'deleteRole', targetId: roleId,
        before: before ? {name: before.name || null, template: before.template, grants: before.grants} : null,
        after: after ? {name, template: before?.template ?? null, grants: after, members: holding.length} : null,
        createdAt: now}]);
      writes.push(['create', operationRef, {organizationId: orgId, actorId: uid, fingerprint, result, createdAt: now}]);
      for (const [method, r, value] of writes) tx[method](r, value);
      return result;
    });
  };
}

/** Inside a transaction: the role to assign, or null when missing/deleted/owner. */
async function resolveRole(db, tx, orgId, roleId) {
  if (typeof roleId !== 'string' || roleId === 'owner' || !/^[A-Za-z0-9_-]{1,64}$/.test(roleId)) return null;
  const doc = await tx.get(db.collection('orgRoles').doc(`${orgId}_${roleId}`));
  if (doc.exists) {
    const x = doc.data();
    if (x.deletedAt || x.organizationId !== orgId) return null;
    return {grants: cleanGrants(x.grants) ?? {}, revision: Number.isInteger(x.revision) ? x.revision : 0, stored: true,
      name: typeof x.name === 'string' ? x.name : ''};
  }
  if (!knownRole(roleId)) return null;
  return {grants: {...templates[roleId].grants}, revision: 0, stored: false, name: ''};
}

/**
 * Membership fields for a role: a stored role gets a grants copy (and its name, for
 * lists and the dashboard); a template not yet edited follows the code.
 */
const roleFields = role => role.stored
  ? {roleGrants: role.grants, roleRevision: role.revision, roleName: role.name || null}
  : {roleGrants: null, roleRevision: null, roleName: null};

module.exports = {createRolesHandler, resolveRole, roleFields, grantsLevel};
