'use strict';

// Roles are data (R1, 2026-09-30). Starter templates and the permission list
// live in role_templates.json, shared with lib/models/team_access.dart; parity
// is tested. A membership carries a copy of its role's grants (roleGrants) so
// every check stays synchronous; editing a role updates those copies in the
// same transaction. A membership without a copy uses its template.
const policy = require('./role_templates.json');

const permissions = Object.freeze(Object.keys(policy.permissions));
const permissionScopes = Object.freeze(Object.fromEntries(
  Object.entries(policy.permissions).map(([p, s]) => [p, Object.freeze([...s])])));
const overrides = Object.freeze([...policy.overridable]);
const templates = Object.freeze(Object.fromEntries(Object.entries(policy.templates).map(([id, t]) =>
  [id, Object.freeze({color: t.color, grants: Object.freeze({...t.grants})})])));
// Template id -> permission names (kept for callers and tests that list a role).
const roles = Object.freeze(Object.fromEntries(Object.entries(templates).map(([id, t]) =>
  [id, Object.freeze(Object.keys(t.grants))])));
const scopeRank = Object.freeze({own: 1, managed: 2, all: 3});
const knownRole = role => typeof role === 'string' && Object.hasOwn(templates, role);

/** Keeps only known permissions with a scope that permission supports. */
function cleanGrants(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const out = {};
  for (const [p, s] of Object.entries(value)) {
    if (p!=='assignAdditionalWorkplace' && Object.hasOwn(permissionScopes, p) && permissionScopes[p].includes(s)) out[p] = s;
  }
  return out;
}

/** The role's grants for a membership, or null when it has no usable role (waiting). */
function roleGrants(m) {
  if (!m || typeof m !== 'object') return null;
  if(m.role==='coOwner')return null;
  if (m.role === 'owner') return {...templates.owner.grants};
  if (typeof m.role !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(m.role)) return null;
  if (m.roleGrants && typeof m.roleGrants === 'object') return cleanGrants(m.roleGrants);
  return knownRole(m.role) ? {...templates[m.role].grants} : null;
}
const hasRole = m => roleGrants(m) !== null;

/** Role grants plus the member's own on/off overrides. */
function effectiveGrants(m) {
  const base = roleGrants(m);
  if (!base) return null;
  const custom = m.permissionOverrides;
  if (custom && typeof custom === 'object') {
    for (const p of overrides) {
      if (custom[p] === false) delete base[p];
      else if (custom[p] === true && !base[p]) base[p] = 'managed';
    }
  }
  return base;
}

const ownsRecord = (m, record) => !!record && typeof record === 'object' &&
  ((typeof m.ownerId === 'string' && record.createdBy === m.ownerId) ||
   (typeof m.staffId === 'string' && m.staffId !== '' && record.staffInChargeId === m.staffId));

/**
 * context.buildingId: the property the action touches.
 * context.record: the booking/lease being read or changed (checked for "own").
 * context.anyRecord: true when the caller only needs "some" access (showing a
 * list it will filter per record, or creating a record that will be theirs).
 * Without record or anyRecord, an "own" grant is denied (fail closed).
 */
function allows(membership, permission, {organizationId, userId, buildingId, record, anyRecord} = {}) {
  if (!membership || membership.accessVersion !== 2 || membership.status !== 'active' ||
      !['all', 'selected'].includes(membership.buildingScope) ||
      (!permissions.includes(permission)||permission==='assignAdditionalWorkplace')) return false;
  if (organizationId !== undefined && membership.organizationId !== organizationId) return false;
  if (userId !== undefined && membership.ownerId !== userId) return false;
  const grants = effectiveGrants(membership);
  const scope = grants?.[permission];
  if (!scope) return false;
  if (buildingId !== undefined) {
    if (typeof buildingId !== 'string' || !buildingId) return false;
    // "All properties" only widens permissions where it was a choice; on/off
    // (organization-wide) permissions keep the member's property list.
    const widened = scope === 'all' && permissionScopes[permission].length > 1;
    if (!widened && membership.buildingScope !== 'all' &&
        !(Array.isArray(membership.buildingIds) && membership.buildingIds.includes(buildingId))) return false;
  }
  if (scope === 'own') return record ? ownsRecord(membership, record) : anyRecord === true;
  return true;
}

/** True when some grant reaches properties outside the member's list. */
const reachesAllProperties = m => m?.buildingScope === 'all' ||
  Object.entries(effectiveGrants(m) ?? {}).some(([p, s]) => s === 'all' && permissionScopes[p].length > 1);

// Levels: owner 3 > can manage roles 2 > can manage team 1 > others 0.
function grantsLevel(grants) {
  if (!grants) return 0;
  return grants.manageRoles ? 2 : grants.manageTeam ? 1 : 0;
}
function memberLevel(m) {
  if (!m) return 0;
  if (['owner','coOwner'].includes(m.role)) return 3;
  return grantsLevel(effectiveGrants(m));
}
/** Target: a membership, a template id, or 'owner'. */
function targetLevel(target) {
  if (['owner','coOwner'].includes(target) || ['owner','coOwner'].includes(target?.role)) return 3;
  if (typeof target === 'string') return knownRole(target) ? grantsLevel(templates[target].grants) : 0;
  return memberLevel(target);
}

/** Every grant in `grants` is also held by `actor`, at an equal or wider scope. */
function grantsWithin(grants, actor) {
  const mine = effectiveGrants(actor);
  if (!mine) return false;
  const rank = (p, s) => (s === 'managed' && actor.buildingScope === 'all' && permissionScopes[p].includes('all')) ? scopeRank.all : scopeRank[s];
  return Object.entries(grants ?? {}).every(([p, s]) => mine[p] && rank(p, mine[p]) >= scopeRank[s]);
}

/** May the actor change this member's access? Never the owner, never someone at or above the actor. */
function canManageAccessOf(actor, target, context) {
  return allows(actor, 'manageTeam', context) && targetLevel(target) !== 3 &&
    memberLevel(actor) > targetLevel(target);
}

/** May the actor give a role with these (effective) grants to someone? */
function canAssignGrants(actor, grants, context) {
  return !grants?.assignAdditionalWorkplace &&
    allows(actor, 'manageTeam', context) && actor.buildingScope === 'all' &&
    memberLevel(actor) > grantsLevel(grants) && grantsWithin(grants, actor);
}

/** May the actor create/edit/delete a role? before = null when creating. */
function canEditRole(actor, before, after, context) {
  return !before?.assignAdditionalWorkplace && !after?.assignAdditionalWorkplace &&
    allows(actor, 'manageRoles', context) && actor.buildingScope === 'all' &&
    (before === null || memberLevel(actor) > grantsLevel(before)) &&
    (after === null || (memberLevel(actor) > grantsLevel(after) && grantsWithin(after, actor)));
}

/** Validates a grants map sent by a client; returns a clean copy or null. */
function parseGrants(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const entries = Object.entries(value);
  if(entries.some(([p])=>p==='assignAdditionalWorkplace'))return null;
  if (entries.length > permissions.length) return null;
  for (const [p, s] of entries) if (!Object.hasOwn(permissionScopes, p) || !permissionScopes[p].includes(s)) return null;
  return Object.fromEntries(entries.sort(([a], [b]) => a < b ? -1 : a > b ? 1 : 0));
}

/** Can take over as owner (account deletion hand-over): settings + team, all properties. */
function canRunOrganization(m) {
  const g = m?.accessVersion === 2 && m.status === 'active' && m.buildingScope === 'all' && m.role !== 'owner' ? effectiveGrants(m) : null;
  return !!(g?.manageOrganization && g?.manageTeam);
}

// Produces a proposal only. It never writes or silently assigns legacy members.
function migrationProposal(organization, memberships) {
  const issues = [];
  const seen = new Set();
  const proposals = memberships.map(m => {
    if (m.organizationId !== organization.id) {
      issues.push({membershipId: m.id, reason: 'organizationMismatch'});
      return {membershipId: m.id, action: 'review'};
    }
    if (!m.ownerId || seen.has(m.ownerId)) {
      issues.push({membershipId: m.id, reason: 'missingOrDuplicateAccount'});
      return {membershipId: m.id, action: 'review'};
    }
    seen.add(m.ownerId);
    if (m.accessVersion === 2) return {membershipId: m.id, action: 'unchanged'};
    const owner = m.ownerId === organization.createdBy;
    const role = owner ? 'owner' : m.role === 'admin' ? 'administrator' : null;
    const status = m.status === 'active' ? (role ? 'active' : 'assignmentRequired') : 'suspended';
    return {membershipId: m.id, action: 'review', proposed: {
      accessVersion: 2, role, status, buildingScope: role ? 'all' : 'selected',
      buildingIds: [], permissionOverrides: {},
    }};
  });
  const creator = memberships.find(m => m.organizationId === organization.id && m.ownerId === organization.createdBy);
  if (!creator || creator.status !== 'active') issues.push({reason: 'missingActiveOwner'});
  return {organizationId: organization.id, proposals, issues};
}

module.exports = {permissions, permissionScopes, roles, templates, overrides, scopeRank,
  knownRole, cleanGrants, roleGrants, hasRole, effectiveGrants, ownsRecord, allows,
  reachesAllProperties, grantsLevel, memberLevel, grantsWithin, canManageAccessOf,
  canAssignGrants, canEditRole, parseGrants, canRunOrganization, migrationProposal};
