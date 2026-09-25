import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/team_access.dart';
import 'package:phan_mem_quan_ly_can_ho/models/staff_profile.dart';

void main() {
  TeamAccess access(TeamRole role, {String status = 'active'}) =>
    TeamAccess(role: role, status: status, buildingIds: {'a'});

  test('Every role is restricted to selected buildings', () {
    for (final role in TeamRole.values) {
      final a = access(role);
      for (final p in TeamAccess.defaults(role)) {
        expect(a.allows(p, buildingId: 'a'), isTrue);
        expect(a.allows(p, buildingId: 'b'), isFalse);
        expect(a.allows(p, buildingId: ''), isFalse);
      }
    }
  });
  test('Suspended, revoked, invited and unassigned users have no permissions', () {
    for (final role in TeamRole.values) {
      for (final status in ['suspended', 'revoked', 'invited', 'assignmentRequired']) {
        for (final p in TeamPermission.values) {
          expect(access(role, status: status).allows(p), isFalse);
        }
      }
    }
  });
  test('Receptionist collects but cannot refund, export or override prices', () {
    final a = access(TeamRole.receptionist);
    expect(a.allows(TeamPermission.collectPayments, buildingId: 'a'), isTrue);
    for (final p in [TeamPermission.refundPayments, TeamPermission.overridePrices,
      TeamPermission.exportData, TeamPermission.manageTeam]) {
      expect(a.allows(p), isFalse);
    }
  });
  test('Housekeeper cannot access guests or finances', () {
    final a = access(TeamRole.housekeeper);
    expect(a.allows(TeamPermission.readAssignedTasks, buildingId: 'a'), isTrue);
    expect(a.allows(TeamPermission.readBookings), isFalse);
    expect(a.allows(TeamPermission.readFinancialReports), isFalse);
  });
  test('Override cannot grant team administration or bypass building scope', () {
    final a = TeamAccess(role: TeamRole.receptionist, status: 'active',
      buildingIds: {'a'}, overrides: {TeamPermission.manageTeam: true,
        TeamPermission.refundPayments: true});
    expect(a.allows(TeamPermission.manageTeam), isFalse);
    expect(a.allows(TeamPermission.refundPayments, buildingId: 'a'), isTrue);
    expect(a.allows(TeamPermission.refundPayments, buildingId: 'b'), isFalse);
  });
  test('Owner and administrator access-management boundaries', () {
    expect(access(TeamRole.administrator).canManageAccessOf(TeamRole.owner), isFalse);
    expect(access(TeamRole.administrator).canManageAccessOf(TeamRole.administrator), isFalse);
    expect(access(TeamRole.owner).canManageAccessOf(TeamRole.administrator), isTrue);
    expect(access(TeamRole.manager).canManageAccessOf(TeamRole.receptionist), isFalse);
  });
  test('Legacy, unknown and unversioned roles fail closed', () {
    for (final map in <Map<String, dynamic>>[
      {'role':'member','status':'active'}, {'role':'admin','status':'active'},
      {'role':'owner','status':'active'},
      {'accessVersion':2,'role':'unknown','status':'active'},
    ]) {
      for (final p in TeamPermission.values) {
        expect(TeamAccess.fromMap(map).allows(p), isFalse);
      }
    }
  });
  test('Empty selected scope is not all buildings; all scope includes future buildings', () {
    final selected = TeamAccess(role: TeamRole.manager, status: 'active');
    expect(selected.allows(TeamPermission.manageProperty, buildingId: 'future'), isFalse);
    final all = TeamAccess(role: TeamRole.manager, status: 'active', allBuildings: true);
    final restored = TeamAccess.fromMap(all.toMap());
    expect(restored.allows(TeamPermission.manageProperty, buildingId: 'future'), isTrue);
  });
  test('Malformed building scope fails closed even with listed buildings', () {
    final a = TeamAccess.fromMap({'accessVersion': 2, 'role': 'manager',
      'status': 'active', 'buildingScope': 'invalid', 'buildingIds': ['a']});
    expect(a.allows(TeamPermission.manageProperty, buildingId: 'a'), isFalse);
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
