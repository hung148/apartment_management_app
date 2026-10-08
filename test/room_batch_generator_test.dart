import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'support/calendar_nav.dart' show openNewBuilding, closeCalendarDialog;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/bulk_rooms_screen.dart';
import 'property_creation_test.dart' as property;
import 'room_creation_test.dart' as room;
import 'team_review_test.dart' show mountReview;
import 'room_booking_settings_test.dart' show enter;
import 'room_rates_test.dart' show press, reveal;

Future<void> generate(
  WidgetTester t, {
  String language = 'en',
  String prefix = 'P',
  String start = '001',
  String count = '3',
  String price = '5000000',
}) async {
  final tr = AppTranslations(Locale(language));
  final button = find.byKey(const ValueKey('rooms-generate'));
  await reveal(t, button);
  await t.tap(button);
  await t.pumpAndSettle();
  expect(find.byTooltip(tr['close']), findsOneWidget);
  await enter(t, 'rooms_prefix', prefix);
  await enter(t, 'rooms_start', start);
  await enter(t, 'rooms_count', count);
  if (price.isNotEmpty) await enter(t, 'batch-roomPrice', price);
  await press(t, tr['rooms_add_list']);
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
    'building generator preserves zeros, shares price, allows edits and saves together',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, property.create(store.service));
      await property.fill(t);
      await generate(t);
      expect(
        store.rooms.where((r) => r['buildingId'] == 'new-property'),
        isEmpty,
      );
      await enter(t, 'initial-room-name-1', 'Custom');
      await enter(t, 'initial-room-roomPrice-1', '6500000');
      await press(t, 'Create property');
      final rooms = store.rooms
          .where((r) => r['buildingId'] == 'new-property')
          .toList();
      expect(rooms.map((r) => r['roomNumber']), ['P001', 'Custom', 'P003']);
      expect(rooms.map((r) => r['roomPrice']), [5000000, 6500000, 5000000]);
    },
  );
  testWidgets(
    'existing room create switches to batch; lost reply retries identical payload',
    (t) async {
      final store = TeamPreviewStore();
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (name, d) async {
          final result = await store.call(name, d);
          if (d['action'] == 'createBulk') {
            calls.add(d);
            if (calls.length == 1) throw StateError('lost');
          }
          return result;
        },
      );
      await mountReview(t, room.create(service));
      await press(t, 'Generate rooms');
      expect(find.byKey(const ValueKey('rooms_prefix')), findsOneWidget);
      expect(find.byKey(const ValueKey('rooms-generate')), findsNothing);
      await enter(t, 'rooms_prefix', 'P');
      await enter(t, 'rooms_start', '001');
      await enter(t, 'rooms_count', '3');
      await enter(t, 'batch-roomPrice', '5000000');
      await press(t, 'Add to room list');
      await press(t, 'Create all rooms');
      expect(find.textContaining('Retry'), findsWidgets);
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('rooms-generate')),
            )
            .onPressed,
        isNull,
      );
      await press(t, AppTranslations(const Locale('en'))['room_edit_retry']);
      expect(calls.length, 2);
      expect(calls[1], calls[0]);
      expect(
        store.rooms
            .where((r) => (r['roomNumber'] as String).startsWith('P00'))
            .length,
        3,
      );
    },
  );
  testWidgets(
    'cancel direct generator returns to single room with draft intact',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, room.create(store.service));
      await enter(t, 'room-edit-number', 'Draft 301');
      await press(t, 'Generate rooms');
      expect(find.byKey(const ValueKey('rooms_prefix')), findsOneWidget);
      await t.tap(find.byTooltip(AppTranslations(const Locale('en'))['close']));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('rooms_prefix')), findsNothing);
      expect(
        t
            .widget<TextFormField>(
              find.byKey(const ValueKey('room-edit-number')),
            )
            .controller!
            .text,
        'Draft 301',
      );
      await press(t, 'Generate rooms');
      expect(find.byKey(const ValueKey('rooms_prefix')), findsOneWidget);
    },
  );
  testWidgets('direct generator waits for authorized preparation and opens after retry', (t) async {
    final store = TeamPreviewStore(); bool unavailable = true;
    final service = TeamService(transport: (name, data) async {
      if (data['action'] == 'prepareBulk' && unavailable) throw StateError('Offline');
      return store.call(name, data);
    });
    await mountReview(t, room.create(service));
    await press(t, 'Generate rooms');
    expect(find.byKey(const ValueKey('rooms_prefix')), findsNothing);
    expect(find.byKey(const ValueKey('rooms-generate')), findsNothing);
    unavailable = false;
    await press(t, AppTranslations(const Locale('en'))['room_edit_reload']);
    expect(find.byKey(const ValueKey('rooms_prefix')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'generator rejects over-limit and duplicate batches without changing list',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, property.create(store.service));
      await generate(t, count: '51');
      expect(
        find.text(AppTranslations(const Locale('en'))['rooms_count_invalid']),
        findsOneWidget,
      );
      await enter(t, 'rooms_count', '2');
      await press(t, 'Add to room list');
      await generate(t, count: '2');
      expect(find.text('Use a different room name.'), findsOneWidget);
      await t.tap(find.byTooltip(AppTranslations(const Locale('en'))['close']));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('initial-room-name-2')), findsNothing);
    },
  );
  testWidgets(
    'floor numbering generates 101 and 201 groups in a new building',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, property.create(store.service));
      await property.fill(t);
      final b = find.byKey(const ValueKey('rooms-generate'));
      await reveal(t, b);
      await t.tap(b);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('rooms-by-floor')));
      await t.tap(find.byKey(const ValueKey('rooms-by-floor')));
      await t.pumpAndSettle();
      await enter(t, 'rooms_floors', '2');
      await enter(t, 'rooms_per_floor', '3');
      await enter(t, 'batch-roomPrice', '5000000');
      await press(t, 'Add to room list');
      await press(t, 'Create property');
      final rows = store.rooms
          .where((r) => r['buildingId'] == 'new-property')
          .toList();
      expect(rows.map((r) => r['roomNumber']), [
        '101',
        '102',
        '103',
        '201',
        '202',
        '203',
      ]);
      expect(rows.every((r) => r['roomPrice'] == 5000000), isTrue);
    },
  );
  testWidgets(
    'floor batch respects total limit, ground floor and existing building save',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(
        t,
        BulkRoomsScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          service: store.service,
          onBack: () {},
          onCreated: () {},
        ),
      );
      final b = find.byKey(const ValueKey('rooms-generate'));
      await reveal(t, b);
      await t.tap(b);
      await t.pumpAndSettle();
      await enter(t, 'rooms_prefix', 'G');
      await t.ensureVisible(find.byKey(const ValueKey('rooms-by-floor')));
      await t.tap(find.byKey(const ValueKey('rooms-by-floor')));
      await t.pumpAndSettle();
      await enter(t, 'rooms_first_floor', '0');
      await enter(t, 'rooms_floors', '2');
      await enter(t, 'rooms_per_floor', '26');
      await press(t, 'Add to room list');
      expect(
        find.text(AppTranslations(const Locale('en'))['rooms_count_invalid']),
        findsOneWidget,
      );
      await enter(t, 'rooms_per_floor', '2');
      await press(t, 'Add to room list');
      await press(t, 'Create all rooms');
      expect(
        store.rooms
            .where((r) => (r['roomNumber'] as String).startsWith('G'))
            .map((r) => r['roomNumber']),
        ['G001', 'G002', 'G101', 'G102'],
      );
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets('actual building dialog generator VI200 $brightness', (
      t,
    ) async {
      final store = TeamPreviewStore();
      await mountReview(
        t,
        RoleWorkspace(organizationId: 'preview', service: store.service),
        language: 'vi',
        size: const Size(320, 740),
        scale: 2,
        brightness: brightness,
      );
      await openNewBuilding(t);
      final b = find.byKey(const ValueKey('rooms-generate'));
      await reveal(t, b);
      await t.tap(b);
      await t.pumpAndSettle();
      await enter(t, 'rooms_prefix', 'P');
      await enter(t, 'rooms_count', '2');
      await t.runAsync(() async {
        final im = await t
            .renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            )
            .toImage();
        final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
        await Directory(
          '.dart_tool/room-generator-layout',
        ).create(recursive: true);
        await File(
          '.dart_tool/room-generator-layout/dialog-${brightness.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        im.dispose();
      });
      await press(t, AppTranslations(const Locale('vi'))['rooms_add_list']);
      expect(find.byKey(const ValueKey('initial-room-name-1')), findsOneWidget);
      expect(t.takeException(), isNull);
      await closeCalendarDialog(t);
    });
  }
  testWidgets(
    'bulk duplicate errors retain edits and revoked save clears private drafts',
    (t) async {
      final store = TeamPreviewStore();
      String? error;
      final service = TeamService(
        transport: (n, d) async {
          if (d['action'] == 'createBulk' && error != null) {
            throw FirebaseFunctionsException(code: error, message: 'Test');
          }
          return store.call(n, d);
        },
      );
      await mountReview(
        t,
        BulkRoomsScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          service: service,
          onBack: () {},
          onCreated: () {},
        ),
      );
      await generate(t);
      error = 'already-exists';
      await press(t, 'Create all rooms');
      expect(find.byKey(const ValueKey('initial-room-name-0')), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('rooms-generate')),
            )
            .onPressed,
        isNotNull,
      );
      error = 'permission-denied';
      await press(t, 'Create all rooms');
      expect(find.byKey(const ValueKey('initial-room-name-0')), findsNothing);
      expect(find.text('P001'), findsNothing);
    },
  );
  for (final lang in ['en', 'vi']) {
    for (final size in [
      const Size(320, 740),
      const Size(812, 375),
      const Size(1440, 1000),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('generator populated $lang $size $scale', (t) async {
          final store = TeamPreviewStore();
          await mountReview(
            t,
            property.create(store.service),
            language: lang,
            size: size,
            scale: scale,
          );
          await property.fill(t);
          final b = find.byKey(const ValueKey('rooms-generate'));
          await reveal(t, b);
          await t.tap(b);
          await t.pumpAndSettle();
          await enter(t, 'rooms_prefix', 'Tầng-A-');
          await t.ensureVisible(find.byKey(const ValueKey('rooms-by-floor')));
          await t.tap(find.byKey(const ValueKey('rooms-by-floor')));
          await t.pumpAndSettle();
          await enter(t, 'rooms_floors', '3');
          await enter(t, 'rooms_per_floor', '1');
          await enter(t, 'batch-roomPrice', '12500000');
          final tr = AppTranslations(Locale(lang));
          for (final key in [
            'rooms_first_floor',
            'rooms_shared_prices',
            'rooms_generate_hint',
          ]) {
            expect(
              (t.renderObject(find.text(tr[key])) as RenderParagraph)
                  .didExceedMaxLines,
              isFalse,
            );
          }
          final add = find.widgetWithText(FilledButton, tr['rooms_add_list']);
          await reveal(t, add);
          expect(add.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
          if ((lang == 'vi' && size.width == 320 && scale == 2) ||
              (lang == 'en' && size.width == 1440 && scale == 1)) {
            await t.runAsync(() async {
              final im = await t
                  .renderObject<RenderRepaintBoundary>(
                    find.byKey(const ValueKey('capture')),
                  )
                  .toImage();
              final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
              await Directory(
                '.dart_tool/room-generator-layout',
              ).create(recursive: true);
              await File(
                '.dart_tool/room-generator-layout/$lang.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              im.dispose();
            });
          }
          await t.tap(add);
          await t.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('initial-room-name-2')),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await press(t, tr['property_create']);
          expect(
            store.rooms.where((r) => r['buildingId'] == 'new-property').length,
            3,
          );
        });
      }
    }
  }
  testWidgets(
    'bulk prep without price grants hides shared and per-room prices',
    (t) async {
      final store = TeamPreviewStore();
      final service = TeamService(
        transport: (n, d) async {
          final r = await store.call(n, d);
          if (d['action'] == 'prepareBulk') {
            (r['record'] as Map)['canSetRoomPrices'] = false;
          }
          return r;
        },
      );
      await mountReview(
        t,
        BulkRoomsScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          service: service,
          onBack: () {},
          onCreated: () {},
        ),
      );
      await generate(t, price: '');
      expect(
        find.byKey(const ValueKey('initial-room-roomPrice-0')),
        findsNothing,
      );
      await press(t, 'Create all rooms');
      expect(
        store.rooms.where((r) => r['roomNumber'] == 'P001').single['roomPrice'],
        isNull,
      );
    },
  );
}
