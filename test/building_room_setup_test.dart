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
import 'team_review_test.dart' show mountReview;
import 'room_booking_settings_test.dart' show enter;
import 'room_rates_test.dart' show press, reveal;

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
  testWidgets(
    'custom floor defaults generate editable rooms and persist with one save',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, create(store.service));
      await fill(t);
      await enter(t, 'setup-floors', '2');
      await enter(t, 'setup-prefix', 'A');
      await enter(t, 'setup-type', 'Studio');
      await enter(t, 'setup-area', '25.5');
      await enter(t, 'setup-count', '2');
      await tapKey(t, 'setup-uniform-false');
      await enter(t, 'setup-count-0', '2');
      await enter(t, 'setup-count-1', '1');
      await enter(t, 'setup-type-1', 'Family');
      await enter(t, 'setup-area-1', '48');
      await enter(t, 'setup-nightlyPrice', '350000');
      await tapKey(t, 'setup-generate');
      await enter(t, 'initial-room-name-2', 'Family suite');
      await press(t, 'Create property');
      final rooms = store.rooms
          .where((r) => r['buildingId'] == 'new-property')
          .toList();
      expect(rooms.map((r) => r['roomNumber']), [
        'A101',
        'A102',
        'Family suite',
      ]);
      expect(rooms.map((r) => r['roomType']), ['Studio', 'Studio', 'Family']);
      expect(rooms.map((r) => r['area']), [25.5, 25.5, 48]);
      expect(rooms.every((r) => r['nightlyPrice'] == 350000), true);
      final building = store.buildings.singleWhere(
        (r) => r['id'] == 'new-property',
      );
      expect(building['floorRoomCounts'], [2, 1]);
      expect((building['floorDefaults'] as List)[1]['roomType'], 'Family');
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('setup-type-1')))
            .controller!
            .text,
        'Family',
      );
    },
  );
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
      await enter(t, 'setup-prefix', 'NEW-');
      await enter(t, 'setup-count', '2');
      await tapKey(t, 'setup-generate');
      await press(t, 'Save');
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('setup-generate')),
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
      await tapKey(t, 'property-add-room');
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
  testWidgets(
    'blank defaults remain optional and no rooms are implicitly created',
    (t) async {
      final store = TeamPreviewStore();
      final count = store.rooms.length;
      await mountReview(t, create(store.service));
      await fill(t);
      await press(t, 'Create property');
      expect(store.rooms.length, count);
      expect(store.buildings.any((r) => r['id'] == 'new-property'), true);
    },
  );
  testWidgets(
    'invalid floor count in custom mode shows validation without throwing',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, create(store.service));
      await tapKey(t, 'setup-uniform-false');
      await enter(t, 'setup-floors', '201');
      expect(t.takeException(), isNull);
      await tapKey(t, 'setup-generate');
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('initial-room-name-0')), findsNothing);
    },
  );
  testWidgets('200 generated rooms save in one request with responsive review', (t) async {
    final store=TeamPreviewStore(); var writes=0;
    final service=TeamService(transport:(n,d) async { if(n=='propertyDetails' && d['action']=='create') writes++; return store.call(n,d); });
    await mountReview(t,create(service)); await fill(t);
    await enter(t,'setup-floors','10'); await enter(t,'setup-count','20');
    await tapKey(t,'setup-generate');
    expect(find.byKey(const ValueKey('initial-room-name-199')),findsOneWidget);
    await press(t,'Create property');
    expect(writes,1);
    expect(store.rooms.where((r)=>r['buildingId']=='new-property').length,200);
    expect(t.takeException(),isNull);
  });
  for (final lang in ['en', 'vi']) {
    for (final size in [
      const Size(320, 740),
      const Size(812, 375),
      const Size(1440, 1000),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('combined edit populated $lang $size $scale', (t) async {
          final store = TeamPreviewStore();
          await mountReview(
            t,
            edit(store.service),
            language: lang,
            size: size,
            scale: scale,
          );
          await enter(t, 'setup-prefix', 'NEW-');
          await enter(t, 'setup-floors', '2');
          await enter(t, 'setup-count', '1');
          await enter(t, 'setup-type', 'Family apartment with balcony');
          await enter(t, 'setup-area', '48.5');
          await tapKey(t, 'setup-uniform-false');
          await enter(t, 'setup-count-0', '1');
          await enter(t, 'setup-count-1', '1');
          await enter(t, 'setup-type-1', 'Studio overlooking the river');
          await tapKey(t, 'setup-generate');
          await enter(
            t,
            'initial-room-name-1',
            'Phòng gia đình hướng sông — Riverside',
          );
          final save = find.widgetWithText(
            FilledButton,
            AppTranslations(Locale(lang))['property_save'],
          );
          await reveal(t, save);
          expect(save.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
          if ((lang == 'vi' && size.width == 320 && scale == 2) ||
              (lang == 'en' && size.width == 1440 && scale == 1)) {
            await reveal(t, find.byKey(const ValueKey('setup-count-0')));
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
            store.rooms
                .where((r) => (r['roomNumber'] as String).startsWith('NEW-'))
                .length,
            1,
          );
          expect(
            store.rooms
                .where(
                  (r) =>
                      r['roomNumber'] ==
                      'Phòng gia đình hướng sông — Riverside',
                )
                .length,
            1,
          );
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
