import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'property_creation_test.dart' show create, fill;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show reveal, press;
import 'room_booking_settings_test.dart' show enter;
import 'access_editor_test.dart' show choose;
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'support/calendar_nav.dart' show openNewBuilding, closeCalendarDialog;

Future<void> add(WidgetTester t, String name, int index) async {
  final button = find.byKey(const ValueKey('property-add-room'));
  await reveal(t, button);
  await t.tap(button);
  await t.pumpAndSettle();
  await enter(t, 'initial-room-name-$index', name);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 740), const Size(812, 375)]) {
      testWidgets('calendar dialog populated rooms and cost $brightness $size', (
        t,
      ) async {
        final store = TeamPreviewStore();
        await mountReview(
          t,
          RoleWorkspace(organizationId: 'preview', service: store.service),
          language: 'vi',
          size: size,
          scale: 2,
          brightness: brightness,
        );
        await openNewBuilding(t);
        await fill(t);
        await enter(t, 'property-exploitation-cost', '25000000');
        await add(t, 'P101 — Phòng gia đình hướng biển', 0);
        await enter(t, 'initial-room-nightlyPrice-0', '750000');
        await add(t, 'P102', 1);
        final save = find.widgetWithText(
          FilledButton,
          AppTranslations(const Locale('vi'))['property_create'],
        );
        await reveal(t, save);
        expect(save.hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await reveal(
          t,
          find.byKey(const ValueKey('property-exploitation-cost')),
        );
        final hint = find.text(
          AppTranslations(const Locale('vi'))['property_cost_hint'],
        );
        expect(hint, findsOneWidget);
        expect(
          (t.renderObject(hint) as RenderParagraph).didExceedMaxLines,
          isFalse,
          reason: 'Full cost explanation must remain visible',
        );
        await t.runAsync(() async {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          final im = await boundary.toImage();
          final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
          await Directory(
            '.dart_tool/property-bulk-layout',
          ).create(recursive: true);
          await File(
            '.dart_tool/property-bulk-layout/cost-${brightness.name}-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          im.dispose();
        });
        await closeCalendarDialog(t);
        expect(t.takeException(), isNull);
      });
    }
  }
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
    'two rooms and building amount survive lost reply without duplicates',
    (t) async {
      final store = TeamPreviewStore();
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (name, d) async {
          if (d['action'] == 'create') {
            calls.add(d);
            final result = await store.call(name, d);
            if (calls.length == 1) throw StateError('lost');
            return result;
          }
          return store.call(name, d);
        },
      );
      await mountReview(t, create(service));
      await fill(t);
      await choose(t, 'property-currency-VND', 'USD');
      await enter(t, 'property-exploitation-cost', '1234.56');
      await add(t, 'P101', 0);
      await enter(t, 'initial-room-roomPrice-0', '1250.99');
      await add(t, 'P102', 1);
      await enter(t, 'initial-room-nightlyPrice-1', '35.50');
      await press(t, 'Create property');
      expect(calls.single['exploitationCostMinor'], 123456);
      expect((calls.single['rooms'] as List).length, 2);
      expect(
        t
            .widget<TextFormField>(
              find.byKey(const ValueKey('initial-room-name-0')),
            )
            .enabled,
        false,
      );
      await press(t, AppTranslations(const Locale('en'))['property_retry']);
      expect(calls[1], calls[0]);
      final rooms = store.rooms
          .where((r) => r['buildingId'] == 'new-property')
          .toList();
      expect(rooms.length, 2);
      expect(rooms[0]['roomPrice'], 1250.99);
      expect(rooms[1]['nightlyPrice'], 35.50);
    },
  );
  testWidgets(
    'duplicate names block save; removing a row keeps the other values',
    (t) async {
      final store = TeamPreviewStore();
      await mountReview(t, create(store.service));
      await fill(t);
      await add(t, 'P101', 0);
      await add(t, ' p101 ', 1);
      await press(t, 'Create property');
      expect(store.buildings.where((b) => b['id'] == 'new-property'), isEmpty);
      final remove = find.byKey(const ValueKey('initial-room-remove-0'));
      await reveal(t, remove);
      await t.tap(remove);
      await t.pumpAndSettle();
      await enter(t, 'initial-room-name-0', 'P102');
      await press(t, 'Create property');
      expect(
        store.rooms
            .where((r) => r['buildingId'] == 'new-property')
            .single['roomNumber'],
        'P102',
      );
    },
  );
  testWidgets(
    'without price permission room names stay editable and prices are absent',
    (t) async {
      final store = TeamPreviewStore();
      final service = TeamService(
        transport: (name, d) async {
          final result = await store.call(name, d);
          if (d['action'] == 'prepareCreate') {
            (result['record'] as Map)['canSetRoomPrices'] = false;
          }
          return result;
        },
      );
      await mountReview(t, create(service));
      await fill(t);
      await add(t, '101', 0);
      expect(
        find.byKey(const ValueKey('initial-room-roomPrice-0')),
        findsNothing,
      );
      await press(t, 'Create property');
      expect(
        store.rooms
            .where((r) => r['buildingId'] == 'new-property')
            .single['roomPrice'],
        null,
      );
    },
  );
  for (final language in ['en', 'vi']) {
    for (final size in [
      const Size(320, 740),
      const Size(812, 375),
      const Size(1440, 1000),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('populated bulk rooms $language $size $scale', (t) async {
          final store = TeamPreviewStore();
          await mountReview(
            t,
            create(store.service),
            language: language,
            size: size,
            scale: scale,
          );
          await fill(t);
          await enter(t, 'property-exploitation-cost', '25000000');
          await add(t, 'P101 — Phòng studio hướng biển tầng mười hai', 0);
          await enter(t, 'initial-room-roomPrice-0', '12500000');
          await enter(t, 'initial-room-nightlyPrice-0', '750000');
          await add(t, 'P102 — Căn hộ gia đình phía Đông', 1);
          await enter(t, 'initial-room-hourlyPrice-1', '150000');
          final tr = AppTranslations(Locale(language));
          for (final key in [
            'property_room_type',
            'property_room_area_optional',
          ]) {
            for (final element in find.text(tr[key]).evaluate()) {
              expect(
                (element.renderObject! as RenderParagraph).didExceedMaxLines,
                isFalse,
                reason: 'Full room labels must remain visible',
              );
            }
          }
          final save = find.widgetWithText(FilledButton, tr['property_create']);
          await reveal(t, save);
          expect(save.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
          final remove = find.byKey(const ValueKey('initial-room-remove-1'));
          await reveal(t, remove);
          expect(remove.hitTestable(), findsOneWidget);
          if ((language == 'vi' && size.width == 320 && scale == 2) ||
              (language == 'en' && size.width == 1440 && scale == 1)) {
            await reveal(t, find.byKey(const ValueKey('initial-room-name-1')));
            await t.runAsync(() async {
              final boundary = t.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('capture')),
              );
              final im = await boundary.toImage();
              final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
              await Directory(
                '.dart_tool/property-bulk-layout',
              ).create(recursive: true);
              await File(
                '.dart_tool/property-bulk-layout/rooms-$language.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              im.dispose();
            });
          }
          await reveal(t, save);
          await t.tap(save);
          await t.pumpAndSettle();
          expect(
            store.rooms.where((r) => r['buildingId'] == 'new-property').length,
            2,
          );
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
