/// Versioned access policy. Legacy roles deliberately grant no v2 access.
///
/// R1 (2026-09-30): roles are data. Each organization can edit the starter
/// templates below and create its own roles; each permission has a scope
/// (all properties / the member's properties / only their own records).
/// The server is the authority: `myAccess` returns the member's effective
/// grants, and every callable re-checks. This file mirrors
/// functions/team_access.js; permissions, scopes and templates are
/// parity-tested against functions/role_templates.json.
// 'viewer' was removed (2026-09-29); a stored 'viewer' parses as no role (waiting).
library;

enum TeamPermission { manageOrganization, manageTeam, manageRoles, assignAdditionalWorkplace, manageProperty, manageLease, readBookings, createBookings, manageBookings, collectPayments, overridePrices, refundPayments, readFinancialReports, readOwnActivity, readAllActivity, exportData, importData, connectDrive, backdateRecords, readAssignedTasks, updateAssignedTasks, readGuestIds }

/// How far a permission reaches.
/// all: every property in the organization. managed: the member's own
/// property list. own: inside their properties, only records they created
/// or are in charge of.
enum GrantScope { own, managed, all }

typedef Grants = Map<TeamPermission, GrantScope>;

class TeamPolicy {
  static const templateIds = ['owner', 'administrator', 'manager', 'receptionist', 'housekeeper', 'accountant', 'staff', 'investor'];

  static const _org = [GrantScope.all];
  static const _property = [GrantScope.all, GrantScope.managed];
  static const _record = [GrantScope.all, GrantScope.managed, GrantScope.own];

  /// Scopes each permission may use (first = widest).
  static const Map<TeamPermission, List<GrantScope>> scopes = {
    TeamPermission.manageOrganization: _org,
    TeamPermission.manageTeam: _org,
    TeamPermission.manageRoles: _org,
    TeamPermission.assignAdditionalWorkplace: _org,
    TeamPermission.manageProperty: _property,
    TeamPermission.manageLease: _property,
    TeamPermission.readBookings: _record,
    TeamPermission.createBookings: _property,
    TeamPermission.manageBookings: _record,
    TeamPermission.collectPayments: _property,
    TeamPermission.overridePrices: _property,
    TeamPermission.refundPayments: _property,
    TeamPermission.readFinancialReports: _property,
    TeamPermission.readOwnActivity: _org,
    TeamPermission.readAllActivity: _org,
    TeamPermission.exportData: _org,
    TeamPermission.importData: _org,
    TeamPermission.connectDrive: _org,
    TeamPermission.backdateRecords: _org,
    TeamPermission.readAssignedTasks: _property,
    TeamPermission.updateAssignedTasks: _property,
    TeamPermission.readGuestIds: _property,
  };

  /// Permission groups for the roles grid, in display order.
  static const groups = <String, List<TeamPermission>>{
    'bookings': [TeamPermission.readBookings, TeamPermission.createBookings, TeamPermission.manageBookings, TeamPermission.readGuestIds],
    'money': [TeamPermission.collectPayments, TeamPermission.overridePrices, TeamPermission.refundPayments, TeamPermission.readFinancialReports],
    'property': [TeamPermission.manageProperty, TeamPermission.manageLease, TeamPermission.backdateRecords],
    'housekeeping': [TeamPermission.readAssignedTasks, TeamPermission.updateAssignedTasks],
    'team': [TeamPermission.manageTeam, TeamPermission.manageRoles, TeamPermission.readAllActivity, TeamPermission.readOwnActivity],
    'organization': [TeamPermission.manageOrganization, TeamPermission.exportData, TeamPermission.importData, TeamPermission.connectDrive],
  };

  static const overridable = {
    TeamPermission.overridePrices, TeamPermission.refundPayments,
    TeamPermission.exportData, TeamPermission.importData,
  };

  static const _m = GrantScope.managed, _a = GrantScope.all, _o = GrantScope.own;
  static const Map<String, Grants> templates = {
    'owner': {
      TeamPermission.manageOrganization: _a, TeamPermission.manageTeam: _a, TeamPermission.manageRoles: _a,
      TeamPermission.manageProperty: _m, TeamPermission.manageLease: _m, TeamPermission.readBookings: _m,
      TeamPermission.createBookings: _m, TeamPermission.manageBookings: _m, TeamPermission.collectPayments: _m,
      TeamPermission.overridePrices: _m, TeamPermission.refundPayments: _m, TeamPermission.readFinancialReports: _m,
      TeamPermission.readOwnActivity: _a, TeamPermission.readAllActivity: _a, TeamPermission.exportData: _a,
      TeamPermission.importData: _a, TeamPermission.connectDrive: _a, TeamPermission.backdateRecords: _a,
      TeamPermission.readAssignedTasks: _m, TeamPermission.updateAssignedTasks: _m,
      TeamPermission.readGuestIds: _m,
    },
    'administrator': {
      TeamPermission.manageOrganization: _a, TeamPermission.manageTeam: _a,
      TeamPermission.manageProperty: _m, TeamPermission.manageLease: _m, TeamPermission.readBookings: _m,
      TeamPermission.createBookings: _m, TeamPermission.manageBookings: _m, TeamPermission.collectPayments: _m,
      TeamPermission.overridePrices: _m, TeamPermission.refundPayments: _m, TeamPermission.readFinancialReports: _m,
      TeamPermission.readOwnActivity: _a, TeamPermission.readAllActivity: _a, TeamPermission.exportData: _a,
      TeamPermission.importData: _a, TeamPermission.connectDrive: _a, TeamPermission.backdateRecords: _a,
      TeamPermission.readAssignedTasks: _m, TeamPermission.updateAssignedTasks: _m,
      TeamPermission.readGuestIds: _m,
    },
    'manager': {
      TeamPermission.manageProperty: _m, TeamPermission.manageLease: _m, TeamPermission.readBookings: _m,
      TeamPermission.createBookings: _m, TeamPermission.manageBookings: _m, TeamPermission.collectPayments: _m,
      TeamPermission.overridePrices: _m, TeamPermission.readFinancialReports: _m, TeamPermission.readOwnActivity: _a,
    },
    'receptionist': {
      TeamPermission.readBookings: _m, TeamPermission.createBookings: _m, TeamPermission.manageBookings: _m,
      TeamPermission.collectPayments: _m, TeamPermission.readOwnActivity: _a,
    },
    'housekeeper': {
      TeamPermission.readAssignedTasks: _m, TeamPermission.updateAssignedTasks: _m, TeamPermission.readOwnActivity: _a,
    },
    'accountant': {
      TeamPermission.readBookings: _m, TeamPermission.collectPayments: _m, TeamPermission.refundPayments: _m,
      TeamPermission.readFinancialReports: _m, TeamPermission.readOwnActivity: _a,
    },
    'staff': {
      TeamPermission.readBookings: _m, TeamPermission.createBookings: _m, TeamPermission.manageBookings: _o,
      TeamPermission.collectPayments: _m, TeamPermission.readOwnActivity: _a,
    },
    'investor': {
      TeamPermission.readBookings: _m, TeamPermission.readFinancialReports: _m, TeamPermission.readOwnActivity: _a,
    },
  };

  static const templateColors = {
    'owner': 0xFF6D4C41, 'administrator': 0xFF3949AB, 'manager': 0xFF00897B,
    'receptionist': 0xFF1E88E5, 'housekeeper': 0xFF8E24AA, 'accountant': 0xFFF4511E,
    'staff': 0xFF43A047, 'investor': 0xFFFDD835,
  };

  static bool isTemplate(Object? id) => id is String && templates.containsKey(id);

  /// Parses a {permission: scope} map; unknown permissions and unsupported scopes are dropped.
  static Grants parse(Object? raw) {
    if (raw is! Map) return {};
    final out = <TeamPermission, GrantScope>{};
    for (final p in TeamPermission.values) {
      final s = GrantScope.values.where((v) => v.name == raw[p.name]).firstOrNull;
      if (s != null && scopes[p]!.contains(s)) out[p] = s;
    }
    return out;
  }

  static Map<String, String> encode(Grants grants) => {
    for (final e in grants.entries)
      if (scopes[e.key]!.contains(e.value)) e.key.name: e.value.name,
  };

  /// 3 owner, 2 can manage roles, 1 can manage the team, 0 others.
  static int level(Grants grants) => grants.containsKey(TeamPermission.manageRoles)
      ? 2
      : grants.containsKey(TeamPermission.manageTeam) ? 1 : 0;
}

class TeamAccess {
  static const version = 2;
  static const overridable = TeamPolicy.overridable;

  /// Template id or organization role id; null = waiting for a role.
  final String? role;
  final String? roleName;
  final String status;
  final bool allBuildings;
  final Set<String> buildingIds;
  final Map<TeamPermission, bool> overrides;
  /// Effective grants (role + overrides).
  final Grants grants;

  TeamAccess({required this.role, required this.status,
    this.roleName,
    this.allBuildings = false, Set<String> buildingIds = const {},
    Map<TeamPermission, bool> overrides = const {},
    Grants? grants})
      : buildingIds = Set.unmodifiable(buildingIds),
        overrides = Map.unmodifiable(overrides),
        grants = Map.unmodifiable(grants ?? _withOverrides(TeamPolicy.templates[role] ?? const {}, overrides));

  static Grants _withOverrides(Grants base, Map<TeamPermission, bool> overrides) {
    final out = Map<TeamPermission, GrantScope>.of(base);
    for (final p in TeamPolicy.overridable) {
      if (overrides[p] == false) out.remove(p);
      if (overrides[p] == true && !out.containsKey(p)) out[p] = GrantScope.managed;
    }
    return out;
  }

  /// Permissions of a starter template (kept for templates and older callers).
  static Set<TeamPermission> defaults(String? role) =>
      (TeamPolicy.templates[role] ?? const {}).keys.toSet();

  bool get isOwner => role == 'owner';
  int get level => (isOwner || role == 'coOwner') ? 3 : TeamPolicy.level(grants);

  /// True when some grant reaches properties outside the member's list.
  bool get reachesAllProperties => allBuildings || grants.entries.any((e) =>
      e.value == GrantScope.all && TeamPolicy.scopes[e.key]!.length > 1);

  GrantScope? scopeOf(TeamPermission permission) =>
      status == 'active' && role != null ? grants[permission] : null;

  /// A UI hint only; the server re-checks. "Own records only" counts as allowed
  /// here, and the server returns per-record flags (canManage, ...).
  bool allows(TeamPermission permission, {String? buildingId}) {
    if(permission == TeamPermission.assignAdditionalWorkplace || role == 'coOwner') return false;
    final scope = scopeOf(permission);
    if (scope == null) return false;
    if (buildingId != null) {
      if (buildingId.isEmpty) return false;
      final widened = scope == GrantScope.all && TeamPolicy.scopes[permission]!.length > 1;
      if (!widened && !allBuildings && !buildingIds.contains(buildingId)) return false;
    }
    return true;
  }

  /// For a starter template id: may this member change access of someone with it?
  /// For organization roles use the server's canAssign / canManageAccess flags.
  bool canManageAccessOf(String? target) {
    if (!allows(TeamPermission.manageTeam) || (target == 'owner' || target == 'coOwner')) return false;
    return level > TeamPolicy.level(TeamPolicy.templates[target] ?? const {});
  }

  factory TeamAccess.fromMap(Map<String, dynamic> map) {
    final validVersion = map['accessVersion'] == version &&
        (map['buildingScope'] == 'all' || map['buildingScope'] == 'selected');
    final rawRole = map['role'];
    final rawOverrides = map['permissionOverrides'];
    final overrides = rawOverrides is Map ? {
      for (final p in overridable)
        if (rawOverrides[p.name] is bool) p: rawOverrides[p.name] as bool,
    } : <TeamPermission, bool>{};
    final copied = map['roleGrants'] is Map;
    final served = map['grants'] is Map;
    final known = rawRole is String && RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(rawRole) &&
        rawRole != 'coOwner' && (rawRole == 'owner' || TeamPolicy.isTemplate(rawRole) || copied || served);
    final role = validVersion && known ? rawRole : null;
    Grants? grants;
    if (role != null) {
      if (served) {
        grants = TeamPolicy.parse(map['grants']);
      } else if (role == 'owner') {
        grants = _withOverrides(TeamPolicy.templates['owner']!, overrides);
      } else if (copied) {
        grants = _withOverrides(TeamPolicy.parse(map['roleGrants']), overrides);
      }
    }
    return TeamAccess(
      role: role,
      roleName: map['roleName'] is String && (map['roleName'] as String).trim().isNotEmpty
          ? (map['roleName'] as String).trim() : null,
      status: map['status'] is String ? map['status'] as String : 'assignmentRequired',
      allBuildings: validVersion && map['buildingScope'] == 'all',
      buildingIds: map['buildingIds'] is List
          ? (map['buildingIds'] as List).whereType<String>().where((s) => s.isNotEmpty).toSet() : {},
      overrides: overrides,
      grants: role == null ? const {} : grants,
    );
  }

  Map<String, dynamic> toMap() => {
    'accessVersion': version, 'role': role,
    'status': status, 'buildingScope': allBuildings ? 'all' : 'selected',
    'buildingIds': buildingIds.toList()..sort(),
    'permissionOverrides': {for (final e in overrides.entries)
      if (overridable.contains(e.key)) e.key.name: e.value},
  };
}
