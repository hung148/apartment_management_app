import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/team_access.dart';

void main() {
  test(
    'booking deletion and restoration permission does not grant room deletion',
    () {
      final access = TeamAccess.fromMap({
        'ownerId': 'worker',
        'organizationId': 'org',
        'role': 'custom',
        'status': 'active',
        'accessVersion': 2,
        'buildingScope': 'selected',
        'buildingIds': ['a'],
        'roleGrants': {'deleteBookings': 'managed'},
      });
      expect(
        access.allows(TeamPermission.deleteBookings, buildingId: 'a'),
        true,
      );
      expect(access.allows(TeamPermission.deleteRooms, buildingId: 'a'), false);
      expect(
        access.allows(TeamPermission.deleteBookings, buildingId: 'b'),
        false,
      );
    },
  );
}
