import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/building_existing_rooms.dart';
import 'building_room_setup_test.dart' show edit;
import '../team/team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show reveal;

void main() {
  testWidgets(
    'edit lists existing rooms without putting them in creation drafts',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, edit(store.service));
      final heading = find.byKey(const ValueKey('building-existing-rooms'));
      expect(heading, findsOneWidget);
      await reveal(t, heading);
      for (final room in store.rooms.where(
        (r) => r['buildingId'] == 'riverside',
      )) {
        expect(
          find.byKey(ValueKey('existing-room-${room['id']}')),
          findsOneWidget,
        );
      }
      expect(find.byKey(const ValueKey('initial-room-name-0')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('pagination failure clears stale rooms and retry recovers', (t) async {
    var fail = true;
    final service = TeamService(transport: (name, data) async {
      if (data['cursor'] != null && fail) throw StateError('Denied');
      return {'records': [{'id': data['cursor'] == null ? 'one' : 'two', 'roomNumber': data['cursor'] == null ? '101' : '201', 'roomType': 'Family suite', 'area': 45}], 'nextCursor': data['cursor'] == null ? 'next' : null};
    });
    await mountReview(t, SingleChildScrollView(child: BuildingExistingRooms(organizationId:'preview', buildingId:'riverside', service:service)));
    await t.tap(find.byKey(const ValueKey('existing-rooms-more'))); await t.pumpAndSettle();
    expect(find.text('101'),findsNothing);
    fail=false;
    await t.tap(find.byType(OutlinedButton)); await t.pumpAndSettle();
    expect(find.text('101'),findsOneWidget);
    await t.tap(find.byKey(const ValueKey('existing-rooms-more'))); await t.pumpAndSettle();
    expect(find.text('201'),findsOneWidget);
    expect(find.byKey(const ValueKey('existing-rooms-more')),findsNothing);
  });
}
