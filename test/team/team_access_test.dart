import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/team_access.dart';
import 'package:phan_mem_quan_ly_can_ho/models/staff_profile.dart';

void main() {
  TeamAccess access(String role, {String status = 'active'}) =>
    TeamAccess(role: role, status: status, buildingIds: {'a'});
  const oldRoles = ['owner', 'administrator', 'manager', 'receptionist', 'housekeeper', 'accountant'];

  test('Every role is restricted to selected buildings', () {
    for (final role in TeamPolicy.templateIds) {
      final a = access(role);
      for (final p in TeamAccess.defaults(role)) {
        expect(a.allows(p, buildingId: 'a'), isTrue);
        expect(a.allows(p, buildingId: 'b'), isFalse);
        expect(a.allows(p, buildingId: ''), isFalse);
      }
    }
  });
  test('Suspended, revoked, invited and unassigned users have no permissions', () {
    for (final role in TeamPolicy.templateIds) {
      for (final status in ['suspended', 'revoked', 'invited', 'assignmentRequired']) {
        for (final p in TeamPermission.values) {
          expect(access(role, status: status).allows(p), isFalse);
        }
      }
    }
  });
  test('Receptionist collects but cannot refund, export or override prices', () {
    final a = access('receptionist');
    expect(a.allows(TeamPermission.collectPayments, buildingId: 'a'), isTrue);
    for (final p in [TeamPermission.refundPayments, TeamPermission.overridePrices,
      TeamPermission.exportData, TeamPermission.manageTeam]) {
      expect(a.allows(p), isFalse);
    }
  });
  test('Housekeeper cannot access guests or finances', () {
    final a = access('housekeeper');
    expect(a.allows(TeamPermission.readAssignedTasks, buildingId: 'a'), isTrue);
    expect(a.allows(TeamPermission.readBookings), isFalse);
    expect(a.allows(TeamPermission.readFinancialReports), isFalse);
  });
  test('Override cannot grant team administration or bypass building scope', () {
    final a = TeamAccess(role: 'receptionist', status: 'active',
      buildingIds: {'a'}, overrides: {TeamPermission.manageTeam: true,
        TeamPermission.refundPayments: true});
    expect(a.allows(TeamPermission.manageTeam), isFalse);
    expect(a.allows(TeamPermission.refundPayments, buildingId: 'a'), isTrue);
    expect(a.allows(TeamPermission.refundPayments, buildingId: 'b'), isFalse);
  });
  test('Owner and administrator access-management boundaries', () {
    expect(access('administrator').canManageAccessOf('owner'), isFalse);
    expect(access('administrator').canManageAccessOf('administrator'), isFalse);
    expect(access('owner').canManageAccessOf('administrator'), isTrue);
    expect(access('manager').canManageAccessOf('receptionist'), isFalse);
    expect(access('administrator').canManageAccessOf('staff'), isTrue);
  });
  test('Legacy, unknown and unversioned roles fail closed', () {
    for (final map in <Map<String, dynamic>>[
      {'role':'member','status':'active'}, {'role':'admin','status':'active'},
      {'role':'owner','status':'active'},
      {'accessVersion':2,'role':'unknown','status':'active','buildingScope':'all'},
      {'accessVersion':2,'role':'viewer','status':'active','buildingScope':'all'},
    ]) {
      for (final p in TeamPermission.values) {
        expect(TeamAccess.fromMap(map).allows(p), isFalse);
      }
    }
  });
  test('Empty selected scope is not all buildings; all scope includes future buildings', () {
    final selected = TeamAccess(role: 'manager', status: 'active');
    expect(selected.allows(TeamPermission.manageProperty, buildingId: 'future'), isFalse);
    final all = TeamAccess(role: 'manager', status: 'active', allBuildings: true);
    final restored = TeamAccess.fromMap(all.toMap());
    expect(restored.allows(TeamPermission.manageProperty, buildingId: 'future'), isTrue);
  });
  test('Malformed building scope fails closed even with listed buildings', () {
    final a = TeamAccess.fromMap({'accessVersion': 2, 'role': 'manager',
      'status': 'active', 'buildingScope': 'invalid', 'buildingIds': ['a']});
    expect(a.allows(TeamPermission.manageProperty, buildingId: 'a'), isFalse);
  });

  // ---- R1: roles as data ----
  test('Permissions, scopes and templates match functions/role_templates.json', () {
    final json = jsonDecode(File('functions/role_templates.json').readAsStringSync()) as Map;
    final permissions = json['permissions'] as Map;
    expect(TeamPermission.values.map((p) => p.name).toList(), permissions.keys.toList());
    for (final p in TeamPermission.values) {
      expect(TeamPolicy.scopes[p]!.map((s) => s.name).toList(), permissions[p.name], reason: p.name);
    }
    expect(TeamPolicy.overridable.map((p) => p.name).toSet(), (json['overridable'] as List).toSet());
    final templates = json['templates'] as Map;
    expect(TeamPolicy.templateIds, templates.keys.toList());
    for (final id in TeamPolicy.templateIds) {
      expect(TeamPolicy.encode(TeamPolicy.templates[id]!), Map<String, String>.from(templates[id]['grants'] as Map), reason: id);
      final hex = templates[id]['color'] as String;
      expect(TeamPolicy.templateColors[id], 0xFF000000 | int.parse(hex.substring(1), radix: 16), reason: id);
    }
    // The retired wire key remains parseable; usable permissions appear once.
    expect(TeamPolicy.groups.values.expand((g) => g).toList()..sort((a, b) => a.index - b.index), TeamPermission.values.where((p)=>p!=TeamPermission.assignAdditionalWorkplace).toList());
    expect(access('owner').allows(TeamPermission.assignAdditionalWorkplace),isFalse);
  });
  test('Existing roles keep their old permissions (plus add bookings and backdating)', () {
    for (final role in oldRoles) {
      final g = TeamPolicy.templates[role]!;
      expect(g.containsKey(TeamPermission.createBookings), g.containsKey(TeamPermission.manageBookings));
      expect(g.containsKey(TeamPermission.backdateRecords), ['owner', 'administrator'].contains(role));
      expect(g.containsKey(TeamPermission.manageRoles), role == 'owner');
      expect(g.values.every((s) => s != GrantScope.own), isTrue);
    }
  });
  test('Server grants are used as given, including own records and all properties', () {
    final a = TeamAccess.fromMap({'accessVersion': 2, 'role': 'r_abc', 'roleName': ' Nhân viên ',
      'status': 'active', 'buildingScope': 'selected', 'buildingIds': ['a'],
      'grants': {'readBookings': 'all', 'manageBookings': 'own', 'createBookings': 'managed', 'bogus': 'all'}});
    expect(a.role, 'r_abc');
    expect(a.roleName, 'Nhân viên');
    expect(a.allows(TeamPermission.readBookings, buildingId: 'b'), isTrue);
    expect(a.allows(TeamPermission.createBookings, buildingId: 'b'), isFalse);
    expect(a.allows(TeamPermission.manageBookings, buildingId: 'a'), isTrue); // hint; server checks the record
    expect(a.scopeOf(TeamPermission.manageBookings), GrantScope.own);
    expect(a.reachesAllProperties, isTrue);
    expect(a.level, 0);
  });
  test('A grants copy on the membership replaces the template, with overrides on top', () {
    final a = TeamAccess.fromMap({'accessVersion': 2, 'role': 'receptionist', 'status': 'active',
      'buildingScope': 'all', 'roleGrants': {'readBookings': 'managed'},
      'permissionOverrides': {'refundPayments': true}});
    expect(a.allows(TeamPermission.collectPayments), isFalse);
    expect(a.allows(TeamPermission.refundPayments), isTrue);
    final custom = TeamAccess.fromMap({'accessVersion': 2, 'role': 'r_x', 'status': 'active',
      'buildingScope': 'all', 'roleGrants': {'manageRoles': 'all', 'manageTeam': 'all'}});
    expect(custom.level, 2);
    expect(TeamAccess.fromMap({'accessVersion': 2, 'role': 'r_x', 'status': 'active', 'buildingScope': 'all'}).role, isNull);
  });
  test('Organization-wide permissions keep the property list when a building is named', () {
    final a = TeamAccess(role: 'r_x', status: 'active', buildingIds: {'a'},
      grants: {TeamPermission.exportData: GrantScope.all});
    expect(a.allows(TeamPermission.exportData), isTrue);
    expect(a.allows(TeamPermission.exportData, buildingId: 'b'), isFalse);
  });
  test('Staff round trip preserves historical identity without a login', () {
    final s = StaffProfile(id: 'staff1', organizationId: 'org', code: 'S001',
      displayName: 'Historical staff', employmentStatus: 'inactive', createdAt: DateTime(2026));
    final restored = StaffProfile.fromMap(s.id, s.toMap());
    expect(restored.id, s.id);
    expect(restored.accountId, isNull);
    expect(restored.employmentStatus, 'inactive');
    expect(restored.displayName, s.displayName);
  });
}
