import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'property_creation_test.dart' show create, fill;
import 'property_details_screen_test.dart' show page;
import 'property_initial_rooms_test.dart' show add;
import 'team_review_test.dart' show mountReview;
import 'room_booking_settings_test.dart' show enter;
import 'room_rates_test.dart' show press;

void main() {
  test('building copy and serialization preserve cost and currency', () {
    final building = Building(
      id: 'b',
      organizationId: 'org',
      name: 'Building',
      address: 'Address',
      createdAt: DateTime(2026),
      currency: 'USD',
      exploitationCostMinor: 123456,
    );
    final copy = Building.fromMap(
      'b',
      building.copyWith(name: 'Updated').toMap(),
    );
    expect(copy.name, 'Updated');
    expect(copy.currency, 'USD');
    expect(copy.exploitationCostMinor, 123456);
    final legacy = building.toMap()..remove('exploitationCostMinor');
    expect(Building.fromMap('b', legacy).exploitationCostMinor, isNull);
  });

  testWidgets('existing USD cost reads, edits and clears without rooms input', (
    t,
  ) async {
    final store = TeamPreviewStore();
    store.buildings.first.addAll({
      'currency': 'USD',
      'exploitationCostMinor': 123456,
    });
    await mountReview(t, page(store.service));
    expect(
      t
          .widget<TextFormField>(
            find.byKey(const ValueKey('property-exploitation-cost')),
          )
          .controller!
          .text,
      '1,234.56',
    );
    expect(find.byKey(const ValueKey('property-add-room')), findsNothing);
    await enter(t, 'property-exploitation-cost', '0');
    await press(t, 'Save property details');
    expect(store.buildings.first['exploitationCostMinor'], 0);
    await enter(t, 'property-exploitation-cost', '');
    await press(t, 'Save property details');
    expect(store.buildings.first['exploitationCostMinor'], isNull);
  });

  testWidgets(
    'new building inherits selected app currency and stores exact original cents',
    (t) async {
      final store = TeamPreviewStore()..organizationCurrency = 'USD';
      await mountReview(t, create(store.service));
      await fill(t);
      expect(find.byKey(const ValueKey('property-currency-VND')), findsNothing);
      await enter(t, 'property-exploitation-cost', '123.45');
      await add(t, '101', 0);
      await enter(t, 'initial-room-roomPrice-0', '25.50');
      await press(t, 'Create property');
      final building = store.buildings.singleWhere(
        (b) => b['id'] == 'new-property',
      );
      expect(building['exploitationCostMinor'], 12345);
      expect(building['currency'], 'USD');
      final room = store.rooms.singleWhere(
        (r) => r['buildingId'] == 'new-property',
      );
      expect(room['roomPrice'], 25.5);
      expect(room['currency'], 'USD');
    },
  );
}
