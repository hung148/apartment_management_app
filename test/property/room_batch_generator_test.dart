import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import '../support/calendar_nav.dart' show openNewBuilding, closeCalendarDialog;
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
import '../team/team_review_test.dart' show mountReview;
import '../booking/room_booking_settings_test.dart' show enter;
import 'room_rates_test.dart' show press, reveal;

// Room creation: type how many rooms, tap "Create list", fill in each room
// (2026-10-23, Tom). Replaces the prefix / floor / shared-price generator.

/// Types [count] into "Number of rooms" and taps "Create list".
Future<void> makeList(WidgetTester t, int count) async {
  await enter(t, 'rooms-count', '$count');
  final button = find.byKey(const ValueKey('rooms-make-list'));
  await reveal(t, button);
  await t.tap(button);
  await t.pumpAndSettle();
}

Widget bulk(TeamService service) => BulkRoomsScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  service: service,
  onBack: () {},
  onCreated: () {},
);

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
    'new building: count makes blank rows, each filled in, saved together',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, property.create(store.service));
      await property.fill(t);
      await makeList(t, 3);
      for (var i = 0; i < 3; i++) {
        final name = t
            .widget<TextFormField>(find.byKey(ValueKey('initial-room-name-$i')))
            .controller!
            .text;
        expect(name, isEmpty);
      }
      expect(find.byKey(const ValueKey('initial-room-name-3')), findsNothing);
      expect(
        store.rooms.where((r) => r['buildingId'] == 'new-property'),
        isEmpty,
      );
      await enter(t, 'initial-room-name-0', 'A1');
      await enter(t, 'initial-room-name-1', 'A2');
      await enter(t, 'initial-room-name-2', 'A3');
      await enter(t, 'initial-room-roomPrice-1', '6500000');
      await press(t, 'Create property');
      final rooms = store.rooms
          .where((r) => r['buildingId'] == 'new-property')
          .toList();
      expect(rooms.map((r) => r['roomNumber']), ['A1', 'A2', 'A3']);
      expect(rooms.map((r) => r['roomPrice']), [null, 6500000, null]);
    },
  );
  testWidgets('untouched blank rows are not red while typing in another', (
    t,
  ) async {
    final store = TeamPreviewStore();
    await mountReview(t, property.create(store.service));
    await property.fill(t);
    await makeList(t, 3);
    await enter(t, 'initial-room-name-0', 'A1');
    await t.pumpAndSettle();
    final required = AppTranslations(
      const Locale('en'),
    )['property_required'];
    expect(find.text(required), findsNothing);
    // Clearing a name you typed shows the error right away.
    await enter(t, 'initial-room-name-0', '');
    await t.pumpAndSettle();
    expect(find.text(required), findsOneWidget);
  });
  testWidgets('empty names block saving; nothing is created', (t) async {
    final store = TeamPreviewStore();
    await mountReview(t, property.create(store.service));
    await property.fill(t);
    await makeList(t, 2);
    await enter(t, 'initial-room-name-0', 'A1');
    await press(t, 'Create property');
    expect(store.buildings.where((b) => b['id'] == 'new-property'), isEmpty);
    expect(
      find.text(AppTranslations(const Locale('en'))['property_required']),
      findsOneWidget,
    );
  });
  testWidgets(
    'count is checked: 0 and over the limit add nothing; a second list appends',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, property.create(store.service));
      final invalid = AppTranslations(
        const Locale('en'),
      )['rooms_count_invalid'];
      await makeList(t, 0);
      expect(find.text(invalid), findsOneWidget);
      await makeList(t, 201);
      expect(find.text(invalid), findsOneWidget);
      expect(find.byKey(const ValueKey('initial-room-name-0')), findsNothing);
      await makeList(t, 2);
      expect(find.text(invalid), findsNothing);
      expect(find.byKey(const ValueKey('initial-room-name-1')), findsOneWidget);
      // The field empties after use; the list keeps growing.
      expect(
        t
            .widget<TextFormField>(find.byKey(const ValueKey('rooms-count')))
            .controller!
            .text,
        isEmpty,
      );
      await makeList(t, 199);
      expect(find.text(invalid), findsOneWidget);
      await makeList(t, 1);
      expect(find.byKey(const ValueKey('initial-room-name-2')), findsOneWidget);
      // An empty count never blocks saving the building.
      await property.fill(t);
      for (var i = 0; i < 3; i++) {
        await enter(t, 'initial-room-name-$i', 'R$i');
      }
      await press(t, 'Create property');
      expect(
        store.rooms.where((r) => r['buildingId'] == 'new-property').length,
        3,
      );
    },
  );
  testWidgets('a full list of 200 disables count and Add room', (t) async {
    final store = TeamPreviewStore();
    await mountReview(t, property.create(store.service));
    await property.fill(t);
    await makeList(t, 200);
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('rooms-count')))
          .enabled,
      isFalse,
    );
    expect(
      t
          .widget<ButtonStyleButton>(
            find.byKey(const ValueKey('property-add-room')),
          )
          .onPressed,
      isNull,
    );
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'existing building: Generate rooms opens the count; lost reply retries same payload',
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
      expect(find.byKey(const ValueKey('rooms-count')), findsOneWidget);
      expect(find.byTooltip('Close'), findsNothing);
      await makeList(t, 3);
      for (var i = 0; i < 3; i++) {
        await enter(t, 'initial-room-name-$i', 'P00${i + 1}');
      }
      await press(t, 'Create all rooms');
      expect(find.textContaining('Retry'), findsWidgets);
      expect(
        t
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('rooms-make-list')),
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
  testWidgets('Back returns to the single room with its draft intact', (
    t,
  ) async {
    final store = TeamPreviewStore();
    await mountReview(t, room.create(store.service));
    await enter(t, 'room-edit-number', 'Draft 301');
    await press(t, 'Generate rooms');
    expect(find.byKey(const ValueKey('rooms-count')), findsOneWidget);
    await press(t, AppTranslations(const Locale('en'))['back']);
    expect(find.byKey(const ValueKey('rooms-count')), findsNothing);
    expect(
      t
          .widget<TextFormField>(find.byKey(const ValueKey('room-edit-number')))
          .controller!
          .text,
      'Draft 301',
    );
  });
  testWidgets('count waits for authorized preparation and shows after retry', (
    t,
  ) async {
    final store = TeamPreviewStore();
    bool unavailable = true;
    final service = TeamService(
      transport: (name, data) async {
        if (data['action'] == 'prepareBulk' && unavailable) {
          throw StateError('Offline');
        }
        return store.call(name, data);
      },
    );
    await mountReview(t, room.create(service));
    await press(t, 'Generate rooms');
    expect(find.byKey(const ValueKey('rooms-count')), findsNothing);
    unavailable = false;
    await press(t, AppTranslations(const Locale('en'))['room_edit_reload']);
    expect(find.byKey(const ValueKey('rooms-count')), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'bulk duplicate errors keep edits; revoked save clears private drafts',
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
      await mountReview(t, bulk(service));
      await makeList(t, 1);
      await enter(t, 'initial-room-name-0', 'P001');
      error = 'already-exists';
      await press(t, 'Create all rooms');
      expect(find.byKey(const ValueKey('initial-room-name-0')), findsOneWidget);
      expect(
        t
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('rooms-make-list')),
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
  testWidgets('without price rights the rows have no price fields', (t) async {
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
    await mountReview(t, bulk(service));
    await makeList(t, 1);
    expect(
      find.byKey(const ValueKey('initial-room-roomPrice-0')),
      findsNothing,
    );
    await enter(t, 'initial-room-name-0', 'P001');
    await press(t, 'Create all rooms');
    expect(
      store.rooms.where((r) => r['roomNumber'] == 'P001').single['roomPrice'],
      isNull,
    );
  });
  for (final brightness in Brightness.values) {
    testWidgets('building dialog count row VI 320 x2 $brightness', (t) async {
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
      await makeList(t, 2);
      expect(find.byKey(const ValueKey('initial-room-name-1')), findsOneWidget);
      await reveal(t, find.byKey(const ValueKey('rooms-make-list')));
      await t.runAsync(() async {
        final im = await t
            .renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            )
            .toImage();
        final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
        await Directory(
          '.dart_tool/room-count-layout',
        ).create(recursive: true);
        await File(
          '.dart_tool/room-count-layout/dialog-${brightness.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        im.dispose();
      });
      expect(t.takeException(), isNull);
      await closeCalendarDialog(t);
    });
  }
  for (final lang in ['en', 'vi']) {
    for (final size in [
      const Size(320, 740),
      const Size(812, 375),
      const Size(1440, 1000),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('count row fits $lang $size $scale', (t) async {
          final store = TeamPreviewStore();
          await mountReview(
            t,
            property.create(store.service),
            language: lang,
            size: size,
            scale: scale,
          );
          final tr = AppTranslations(Locale(lang));
          final button = find.byKey(const ValueKey('rooms-make-list'));
          await reveal(t, button);
          expect(button.hitTestable(), findsOneWidget);
          // Button labels stay on one line (Tom's rule).
          final label = find.descendant(
            of: button,
            matching: find.text(tr['rooms_make_list']),
          );
          expect(
            (t.renderObject(label) as RenderParagraph).didExceedMaxLines,
            isFalse,
          );
          await makeList(t, 3);
          expect(
            find.byKey(const ValueKey('initial-room-name-2')),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          if ((lang == 'vi' && size.width == 320 && scale == 2) ||
              (lang == 'en' && size.width == 1440 && scale == 1)) {
            await reveal(t, button);
            await t.runAsync(() async {
              final im = await t
                  .renderObject<RenderRepaintBoundary>(
                    find.byKey(const ValueKey('capture')),
                  )
                  .toImage();
              final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
              await Directory(
                '.dart_tool/room-count-layout',
              ).create(recursive: true);
              await File(
                '.dart_tool/room-count-layout/$lang.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              im.dispose();
            });
          }
        });
      }
    }
  }
}
