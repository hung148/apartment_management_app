import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_details_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'property_creation_test.dart' show create, fill;
import '../team/team_review_test.dart' show mountReview;
import '../booking/room_booking_settings_test.dart' show enter;
import 'room_rates_test.dart' show press, reveal;
import 'room_batch_generator_test.dart' show makeList;

Widget edit(TeamService service) => PropertyDetailsScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  service: service,
  onBack: () {},
);
Future<void> tapKey(WidgetTester t, String key) async {
  final f = find.byKey(ValueKey(key));
  await reveal(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  // Building screen rooms: count → list (2026-10-23, Tom). The floor layout
  // editor is no longer shown; a saved layout must survive edits unchanged.
  testWidgets('saved floor layout is kept when the building is edited', (
    t,
  ) async {
    final store = TeamPreviewStore();
    final b = store.buildings.singleWhere((r) => r['id'] == 'riverside');
    b['floors'] = 2;
    b['roomPrefix'] = 'A';
    b['uniformRooms'] = false;
    b['floorRoomCounts'] = [2, 1];
    await mountReview(t, edit(store.service));
    expect(find.byKey(const ValueKey('setup-floors')), findsNothing);
    expect(find.byKey(const ValueKey('rooms-count')), findsOneWidget);
    await enter(t, 'property-name', 'Riverside renamed');
    await press(t, 'Save');
    final saved = store.buildings.singleWhere((r) => r['id'] == 'riverside');
    expect(saved['name'], 'Riverside renamed');
    expect(saved['floors'], 2);
    expect(saved['roomPrefix'], 'A');
    expect(saved['floorRoomCounts'], [2, 1]);
  });
  testWidgets(
    'edit creates rooms once after lost reply without modifying existing rooms',
    (t) async {
      final store = TeamPreviewStore();
      final before = store.rooms.map((r) => Map.of(r)).toList();
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (n, d) async {
          if (n == 'propertyDetails' && d['action'] == 'update') {
            calls.add(d);
            final result = await store.call(n, d);
            if (calls.length == 1) throw StateError('Lost reply');
            return result;
          }
          return store.call(n, d);
        },
      );
      await mountReview(t, edit(service));
      await makeList(t, 2);
      await enter(t, 'initial-room-name-0', 'NEW-1');
      await enter(t, 'initial-room-name-1', 'NEW-2');
      await press(t, 'Save');
      expect(
        t
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('rooms-make-list')),
            )
            .onPressed,
        isNull,
      );
      await press(t, AppTranslations(const Locale('en'))['property_retry']);
      expect(calls[1], calls[0]);
      expect(store.rooms.length, before.length + 2);
      for (final old in before) {
        expect(store.rooms.singleWhere((r) => r['id'] == old['id']), old);
      }
      expect(find.byKey(const ValueKey('initial-room-name-0')), findsNothing);
    },
  );
  testWidgets(
    'duplicate existing name keeps edits for correction and creates nothing',
    (t) async {
      final store = TeamPreviewStore();
      final before = store.rooms.length;
      final old =
          store.rooms.firstWhere(
                (r) => r['buildingId'] == 'riverside',
              )['roomNumber']
              as String;
      await mountReview(t, edit(store.service));
      await makeList(t, 1);
      await enter(t, 'initial-room-name-0', old);
      await enter(t, 'property-name', 'Keep draft');
      await press(t, 'Save');
      expect(store.rooms.length, before);
      expect(find.text('Use a different room name.'), findsOneWidget);
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('property-name')))
            .controller!
            .text,
        'Keep draft',
      );
      await enter(t, 'initial-room-name-0', 'New unique');
      await press(t, 'Save');
      expect(store.rooms.length, before + 1);
    },
  );
  testWidgets('no count and no rows: building saves without rooms', (t) async {
    final store = TeamPreviewStore();
    final count = store.rooms.length;
    await mountReview(t, create(store.service));
    await fill(t);
    await press(t, 'Create property');
    expect(store.rooms.length, count);
    expect(store.buildings.any((r) => r['id'] == 'new-property'), true);
  });
  for (final lang in ['en', 'vi']) {
    for (final size in [const Size(320, 740), const Size(1440, 1000)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('edit with new rooms $lang $size $scale', (t) async {
          final store = TeamPreviewStore();
          await mountReview(
            t,
            edit(store.service),
            language: lang,
            size: size,
            scale: scale,
          );
          await makeList(t, 2);
          await enter(t, 'initial-room-name-0', 'NEW-1');
          await enter(
            t,
            'initial-room-name-1',
            'Phòng gia đình hướng sông — Riverside',
          );
          await enter(t, 'initial-room-type-1', 'Family apartment with balcony');
          final save = find.widgetWithText(
            FilledButton,
            AppTranslations(Locale(lang))['property_save'],
          );
          await reveal(t, save);
          expect(save.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
          if ((lang == 'vi' && size.width == 320 && scale == 2) ||
              (lang == 'en' && size.width == 1440 && scale == 1)) {
            await reveal(t, find.byKey(const ValueKey('rooms-count')));
            await t.runAsync(() async {
              final im = await t
                  .renderObject<RenderRepaintBoundary>(
                    find.byKey(const ValueKey('capture')),
                  )
                  .toImage();
              final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
              await Directory(
                '.dart_tool/building-combined',
              ).create(recursive: true);
              await File(
                '.dart_tool/building-combined/$lang.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              im.dispose();
            });
          }
          await press(t, AppTranslations(Locale(lang))['property_save']);
          expect(
            store.rooms.where((r) => r['roomNumber'] == 'NEW-1').length,
            1,
          );
          expect(
            store.rooms
                .where(
                  (r) =>
                      r['roomNumber'] ==
                      'Phòng gia đình hướng sông — Riverside',
                )
                .single['roomType'],
            'Family apartment with balcony',
          );
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
