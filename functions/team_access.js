'use strict';

// Keep this policy aligned with lib/models/team_access.dart; parity is tested.
const permissions = Object.freeze([
  'manageOrganization', 'manageTeam', 'manageProperty', 'manageLease',
  'readBookings', 'manageBookings', 'collectPayments', 'overridePrices',
  'refundPayments', 'readFinancialReports', 'readOwnActivity', 'readAllActivity',
  'exportData', 'importData', 'connectDrive', 'readAssignedTasks', 'updateAssignedTasks',
]);
const roles = Object.freeze({
  owner: permissions,
  administrator: permissions,
  manager: ['manageProperty', 'manageLease', 'readBookings', 'manageBookings',
    'collectPayments', 'overridePrices', 'readFinancialReports', 'readOwnActivity'],
  receptionist: ['readBookings', 'manageBookings', 'collectPayments', 'readOwnActivity'],
  housekeeper: ['readAssignedTasks', 'updateAssignedTasks', 'readOwnActivity'],
  accountant: ['readBookings', 'collectPayments', 'refundPayments', 'readFinancialReports', 'readOwnActivity'],
  viewer: ['readFinancialReports'],
});
const overrides = Object.freeze(['overridePrices', 'refundPayments', 'exportData', 'importData']);
const knownRole = role => Object.hasOwn(roles, role);

function allows(membership, permission, {organizationId, userId, buildingId} = {}) {
  if (!membership || membership.accessVersion !== 2 || membership.status !== 'active' ||
      !['all', 'selected'].includes(membership.buildingScope) ||
      !knownRole(membership.role) || !permissions.includes(permission)) return false;
  if (organizationId !== undefined && membership.organizationId !== organizationId) return false;
  if (userId !== undefined && membership.ownerId !== userId) return false;
  if (buildingId !== undefined && (typeof buildingId !== 'string' || !buildingId ||
      (membership.buildingScope !== 'all' &&
        !(membership.buildingScope === 'selected' && Array.isArray(membership.buildingIds) && membership.buildingIds.includes(buildingId))))) return false;
  const override = membership.permissionOverrides?.[permission];
  return overrides.includes(permission) && typeof override === 'boolean'
    ? override : roles[membership.role].includes(permission);
}

function canManageAccessOf(actor, targetRole, context) {
  return allows(actor, 'manageTeam', context) && targetRole !== 'owner' &&
    (actor.role === 'owner' || targetRole !== 'administrator');
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

module.exports = {permissions, roles, overrides, allows, canManageAccessOf, migrationProposal};
