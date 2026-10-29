// Building prices (PRICE_DEFAULTS.md, Tom 2026-10-26): set when creating a
// building, room rows start with them; editing them changes the rooms that
// follow and asks which rooms with their own price should take them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_details_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_rates_screen.dart';
import '../team/team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show reveal;
import '../booking/room_booking_settings_test.dart' show enter;

const desktop = Size(1280, 900);

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String text(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(ValueKey(key))).controller!.text;

/// riverside: monthly 5,000,000; room-101 follows it, room-102 has its own
/// 4,000,000.
TeamPreviewStore _store() {
  final s = TeamPreviewStore();
  // Hourly templates (bookingWorkspace) need the building's time zone.
  s.buildings.first['timeZone'] = 'Asia/Ho_Chi_Minh';
  s.buildings.first['defaultPrices'] = {
    'roomPriceMinor': 5000000,
    'nightlyPriceMinor': null,
    'waterMonthMinor': 100000,
    'waterBasis': 'person',
  };
  s.rooms[0]
    ..['roomPrice'] = 5000000
    ..['priceFollows'] = {'roomPrice': true, 'nightlyPrice': false};
  s.rooms[1]
    ..['roomPrice'] = 4000000
    ..['priceFollows'] = {'roomPrice': false, 'nightlyPrice': false};
  return s;
}

Widget _edit(TeamPreviewStore s) => PropertyDetailsScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  service: s.service,
  onBack: () {},
);

void main() {
  testWidgets('new building: rows start with the building price and follow it '
      'until changed; prices and templates are saved', (tester) async {
    final s = TeamPreviewStore();
    await mountReview(
      tester,
      PropertyDetailsScreen(
        organizationId: 'preview',
        buildingId: 'new-b',
        service: s.service,
        create: true,
        onBack: () {},
      ),
      size: desktop,
    );
    await enter(tester, 'property-name', 'Tòa mới');
    await enter(tester, 'building-roomPrice', '3000000');
    await enter(tester, 'rooms-count', '2');
    await tapKey(tester, 'rooms-make-list');
    expect(text(tester, 'initial-room-roomPrice-0'), '3,000,000');
    expect(text(tester, 'initial-room-roomPrice-1'), '3,000,000');
    expect(find.byKey(const ValueKey('initial-room-hourlyPrice-0')), findsNothing);

    await enter(tester, 'initial-room-roomPrice-1', '4000000');
    await enter(tester, 'building-roomPrice', '3600000');
    await tester.pump();
    expect(text(tester, 'initial-room-roomPrice-0'), '3,600,000');
    expect(text(tester, 'initial-room-roomPrice-1'), '4,000,000');

    await enter(tester, 'building-electricity', '3500');
    await enter(tester, 'building-water', '120000');
    await tapKey(tester, 'building-water-room');
    await tapKey(tester, 'hour-template-add');
    await enter(tester, 'hour-template-name', 'Giờ thường');
    await enter(tester, 'hour-template-hour-0', '100000');
    await tapKey(tester, 'hour-template-more');
    await enter(tester, 'hour-template-hour-1', '80000');
    await tapKey(tester, 'hour-template-save');
    expect(find.text('Giờ thường'), findsOneWidget);

    await enter(tester, 'initial-room-name-0', 'A1');
    await enter(tester, 'initial-room-name-1', 'A2');
    await tapKey(tester, 'property-save');

    final b = s.buildings.firstWhere((b) => b['id'] == 'new-b');
    expect(b['defaultPrices'], {
      'roomPriceMinor': 3600000,
      'nightlyPriceMinor': null,
      'waterMonthMinor': 120000,
      'waterBasis': 'room',
    });
    expect(b['electricityPriceMinor'], 3500);
    final made = s.rooms.where((r) => r['buildingId'] == 'new-b').toList();
    expect(made.map((r) => r['roomPrice']), [3600000, 4000000]);
    expect(made[0]['priceFollows'], {'roomPrice': true, 'nightlyPrice': false});
    expect(made[1]['priceFollows'], {'roomPrice': false, 'nightlyPrice': false});
    final templates = s.buildingHourTemplates['new-b']!;
    expect(templates.single['name'], 'Giờ thường');
    expect(templates.single['hourPricesMinor'], [100000, 80000]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edit: following rooms change; ticked own-price rooms take it '
      'and follow from then on', (tester) async {
    final s = _store();
    await mountReview(tester, _edit(s), size: desktop);
    expect(text(tester, 'building-roomPrice'), '5,000,000');
    expect(find.text('1 of 2 rooms follow the monthly rent.'), findsOneWidget);
    await enter(tester, 'building-roomPrice', '5500000');
    await tapKey(tester, 'building-prices-save');
    expect(find.byKey(const ValueKey('price-checklist')), findsOneWidget);
    expect(find.byKey(const ValueKey('price-checklist-room-102')), findsOneWidget);
    expect(find.byKey(const ValueKey('price-checklist-room-101')), findsNothing);
    await tapKey(tester, 'price-checklist-room-102');
    await tapKey(tester, 'price-checklist-apply');
    expect(s.rooms[0]['roomPrice'], 5500000);
    expect(s.rooms[1]['roomPrice'], 5500000);
    expect(s.rooms[1]['priceFollows']['roomPrice'], true);
    expect(find.text('Saved. 2 room(s) updated.'), findsOneWidget);
    expect(find.text('2 of 2 rooms follow the monthly rent.'), findsOneWidget);
  });

  testWidgets('edit: an unticked room keeps its own price; Cancel saves nothing', (
    tester,
  ) async {
    final s = _store();
    await mountReview(tester, _edit(s), size: desktop);
    await enter(tester, 'building-roomPrice', '6000000');
    await tapKey(tester, 'building-prices-save');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(s.rooms[0]['roomPrice'], 5000000, reason: 'cancelled');
    await tapKey(tester, 'building-prices-save');
    expect(find.text('None of them'), findsOneWidget);
    await tapKey(tester, 'price-checklist-apply');
    expect(s.rooms[0]['roomPrice'], 6000000);
    expect(s.rooms[1]['roomPrice'], 4000000);
    expect(s.rooms[1]['priceFollows']['roomPrice'], false);
  });

  testWidgets('edit: "All rooms" ticks every own-price room', (tester) async {
    final s = _store();
    s.rooms[0]['priceFollows'] = {'roomPrice': false, 'nightlyPrice': false};
    await mountReview(tester, _edit(s), size: desktop);
    await enter(tester, 'building-roomPrice', '5200000');
    await tapKey(tester, 'building-prices-save');
    await tapKey(tester, 'price-checklist-all');
    expect(find.text('Apply to 2'), findsOneWidget);
    await tapKey(tester, 'price-checklist-apply');
    expect(s.rooms.map((r) => r['roomPrice']), [5200000, 5200000]);
  });

  testWidgets('edit: new electricity price from a date; rooms with their own '
      'electricity price are asked too', (tester) async {
    final s = _store();
    s.rooms[1]['ownElectricityMinor'] = 4000;
    await mountReview(tester, _edit(s), size: desktop);
    await enter(tester, 'building-electricity', '3800');
    await enter(tester, 'building-electricity-from', '2026-13-01');
    await tapKey(tester, 'building-prices-save');
    expect(find.text('Use the form YYYY-MM-DD.'), findsOneWidget);
    await enter(tester, 'building-electricity-from', '2026-11-01');
    await tapKey(tester, 'building-prices-save');
    expect(find.text('4,000 VND/kWh'), findsOneWidget);
    await tapKey(tester, 'price-checklist-room-102');
    await tapKey(tester, 'price-checklist-apply');
    expect(s.buildings.first['electricityPriceMinor'], 3800);
    expect(s.buildings.first['electricityFrom'], '2026-11-01');
    expect(s.rooms[1]['ownElectricityMinor'], isNull);
  });

  testWidgets('edit: hourly templates can be added and deleted', (tester) async {
    final s = _store();
    await mountReview(tester, _edit(s), size: desktop);
    expect(find.byKey(const ValueKey('hour-templates-empty')), findsOneWidget);
    await tapKey(tester, 'hour-template-add');
    await enter(tester, 'hour-template-name', 'Cuối tuần');
    await enter(tester, 'hour-template-hour-0', '150000');
    await tapKey(tester, 'hour-template-save');
    final list = s.buildingHourTemplates['riverside']!;
    expect(list.single['hourPricesMinor'], [150000]);
    expect(find.text('Cuối tuần'), findsOneWidget);
    await tapKey(tester, 'hour-template-remove-${list.single['id']}');
    await tapKey(tester, 'hour-template-remove-confirm');
    expect(s.buildingHourTemplates['riverside'], isEmpty);
  });

  testWidgets('without "Đổi giá" the prices are shown but locked', (tester) async {
    final s = _store()
      ..workspaceRole = 'manager'
      ..priceOverride = false;
    await mountReview(tester, _edit(s), size: desktop);
    final f = tester.widget<TextFormField>(
      find.byKey(const ValueKey('building-roomPrice')),
    );
    expect(f.enabled, isFalse);
    expect(find.byKey(const ValueKey('building-prices-save')), findsNothing);
  });

  testWidgets('room page: "use the building price" shows it locked; turning '
      'it off gives the room its own price', (tester) async {
    final s = _store();
    await mountReview(
      tester,
      RoomRatesScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        roomId: 'room-101',
        service: s.service,
        onBack: () {},
      ),
      size: desktop,
    );
    expect(find.byKey(const ValueKey('rates-hourlyPrice')), findsNothing);
    expect(find.byKey(const ValueKey('rates-roomPrice-building')), findsOneWidget);
    expect(find.text('5,000,000 VND'), findsOneWidget);
    expect(find.byKey(const ValueKey('rates-roomPrice')), findsNothing);
    await tapKey(tester, 'rates-follow-roomPrice');
    await enter(tester, 'rates-roomPrice', '4500000');
    await tester.tap(find.text('Save pricing and mode'));
    await tester.pumpAndSettle();
    expect(s.rooms[0]['roomPrice'], 4500000);
    expect(s.rooms[0]['priceFollows']['roomPrice'], false);
    await tapKey(tester, 'rates-follow-roomPrice');
    await tester.tap(find.text('Save pricing and mode'));
    await tester.pumpAndSettle();
    expect(s.rooms[0]['roomPrice'], 5000000);
    expect(s.rooms[0]['priceFollows']['roomPrice'], true);
  });

  // Tom 2026-10-28: no checklist for rooms without a price; they just take it.
  testWidgets('edit: a room with no price takes the building price unasked', (
    tester,
  ) async {
    final s = _store();
    s.rooms[1]
      ..['roomPrice'] = null
      ..['priceFollows'] = {'roomPrice': false, 'nightlyPrice': false};
    await mountReview(tester, _edit(s), size: desktop);
    await enter(tester, 'building-roomPrice', '5300000');
    await tapKey(tester, 'building-prices-save');
    expect(find.byKey(const ValueKey('price-checklist')), findsNothing);
    expect(s.rooms[0]['roomPrice'], 5300000);
    expect(s.rooms[1]['roomPrice'], 5300000);
    expect(s.rooms[1]['priceFollows']['roomPrice'], true);
    expect(find.text('Saved. 2 room(s) updated.'), findsOneWidget);
  });

  testWidgets('phones, large text, Vietnamese: nothing cut off', (tester) async {
    for (final language in ['en', 'vi']) {
      for (final (size, scale) in [
        (const Size(375, 812), 1.0),
        (const Size(375, 812), 2.0),
      ]) {
        await mountReview(
          tester,
          _edit(_store()),
          size: size,
          scale: scale,
          language: language,
        );
        expect(tester.takeException(), isNull, reason: '$language $scale');
      }
    }
  });
}
