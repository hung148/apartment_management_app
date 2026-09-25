/// Versioned access policy. Legacy roles deliberately grant no v2 access.
enum TeamRole { owner, administrator, manager, receptionist, housekeeper, accountant, viewer }

enum TeamPermission {
  manageOrganization, manageTeam, manageProperty, manageLease,
  readBookings, manageBookings, collectPayments, overridePrices, refundPayments,
  readFinancialReports, readOwnActivity, readAllActivity, exportData, importData,
  connectDrive, readAssignedTasks, updateAssignedTasks,
}

class TeamAccess {
  static const version = 2;
  static const overridable = {
    TeamPermission.overridePrices, TeamPermission.refundPayments,
    TeamPermission.exportData, TeamPermission.importData,
  };
  final TeamRole? role;
  final String status;
  final bool allBuildings;
  final Set<String> buildingIds;
  final Map<TeamPermission, bool> overrides;

  TeamAccess({required this.role, required this.status,
    this.allBuildings = false, Set<String> buildingIds = const {},
    Map<TeamPermission, bool> overrides = const {}})
      : buildingIds = Set.unmodifiable(buildingIds),
        overrides = Map.unmodifiable(overrides);

  static Set<TeamPermission> defaults(TeamRole? role) {
    switch (role) {
      case TeamRole.owner:
      case TeamRole.administrator:
        return TeamPermission.values.toSet();
      case TeamRole.manager:
        return {TeamPermission.manageProperty, TeamPermission.manageLease,
          TeamPermission.readBookings, TeamPermission.manageBookings,
          TeamPermission.collectPayments, TeamPermission.overridePrices,
          TeamPermission.readFinancialReports, TeamPermission.readOwnActivity};
      case TeamRole.receptionist:
        return {TeamPermission.readBookings, TeamPermission.manageBookings,
          TeamPermission.collectPayments, TeamPermission.readOwnActivity};
      case TeamRole.housekeeper:
        return {TeamPermission.readAssignedTasks, TeamPermission.updateAssignedTasks,
          TeamPermission.readOwnActivity};
      case TeamRole.accountant:
        return {TeamPermission.readBookings, TeamPermission.collectPayments,
          TeamPermission.refundPayments, TeamPermission.readFinancialReports,
          TeamPermission.readOwnActivity};
      case TeamRole.viewer:
        return {TeamPermission.readFinancialReports};
      case null:
        return {};
    }
  }

  bool allows(TeamPermission permission, {String? buildingId}) {
    if (status != 'active' || role == null) return false;
    if (buildingId != null &&
        (buildingId.isEmpty || (!allBuildings && !buildingIds.contains(buildingId)))) {
      return false;
    }
    return overridable.contains(permission) && overrides.containsKey(permission)
        ? overrides[permission]!
        : defaults(role).contains(permission);
  }

  /// Call separately from manageTeam: administrators cannot alter peers/owners.
  bool canManageAccessOf(TeamRole? target) =>
      allows(TeamPermission.manageTeam) && target != TeamRole.owner &&
      (role == TeamRole.owner || target != TeamRole.administrator);

  factory TeamAccess.fromMap(Map<String, dynamic> map) {
    final validVersion = map['accessVersion'] == version &&
        (map['buildingScope'] == 'all' || map['buildingScope'] == 'selected');
    final role = TeamRole.values.where((r) => r.name == map['role']).firstOrNull;
    final rawOverrides = map['permissionOverrides'];
    return TeamAccess(
      role: validVersion ? role : null,
      status: map['status'] is String ? map['status'] as String : 'assignmentRequired',
      allBuildings: validVersion && map['buildingScope'] == 'all',
      buildingIds: map['buildingIds'] is List
          ? (map['buildingIds'] as List).whereType<String>().where((s) => s.isNotEmpty).toSet() : {},
      overrides: rawOverrides is Map ? {
        for (final p in overridable)
          if (rawOverrides[p.name] is bool) p: rawOverrides[p.name] as bool,
      } : {},
    );
  }

  Map<String, dynamic> toMap() => {
    'accessVersion': version, 'role': role?.name,
    'status': status, 'buildingScope': allBuildings ? 'all' : 'selected',
    'buildingIds': buildingIds.toList()..sort(),
    'permissionOverrides': {for (final e in overrides.entries)
      if (overridable.contains(e.key)) e.key.name: e.value},
  };
}
