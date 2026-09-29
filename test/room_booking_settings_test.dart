import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_booking_settings_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_details_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show reveal, press;
import 'room_directory_test.dart' show directory;

Widget page(TeamService service, {String room = 'room-101'}) =>
    RoomBookingSettingsScreen(
      organizationId: 'preview',
      buildingId: 'riverside',
      roomId: room,
      service: service,
      onBack: () {},
    );
Future<void> enter(WidgetTester tester, String key, String value) async {
  final finder = find.byKey(ValueKey(key));
  await reveal(tester, finder);
  await tester.enterText(finder, value);
}

Future<void> toggle(WidgetTester tester) async {
  final finder = find.byType(CheckboxListTile);
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('24-hour parsing accepts boundaries and rejects malformed values', () {
    expect(bookingMinute('09:05'), 545);
    expect(bookingMinute('24:00', closing: true), 1440);
    for (final value in ['24:00', '09:60', '9:00', '-1:00', '10:xx']) {
      expect(bookingMinute(value), isNull);
    }
    expect(bookingMinute('24:01', closing: true), isNull);
  });
  testWidgets(
    'overnight settings save and reopen with next-day guidance',
    (tester) async {
      final store = TeamPreviewStore();
      store.buildings.first['timeZone'] = 'Asia/Ho_Chi_Minh';
      await mountReview(tester, page(store.service));
      await toggle(tester);
      await enter(tester, 'settings_open', '22:00');
      await enter(tester, 'settings_close', '06:00');
      await press(tester, 'Save booking settings');
      expect(store.rooms.first['operatingHoursStartMin'], 1320);
      expect(store.rooms.first['operatingHoursEndMin'], 360);
      await press(tester, 'Reload booking settings');
      expect(find.text('22:00'), findsOneWidget);
      expect(find.text('06:00'), findsOneWidget);
      expect(find.textContaining('on the next day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'property timezone enables operating hours; manager saves settings from directory and can reopen',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'manager';
      await mountReview(tester, page(store.service));
      expect(
        tester
            .widget<CheckboxListTile>(find.byType(CheckboxListTile))
            .onChanged,
        isNull,
      );
      await mountReview(
        tester,
        PropertyDetailsScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          service: store.service,
          onBack: () {},
        ),
      );
      await enter(tester, 'property-timezone', 'Asia/Ho_Chi_Minh');
      await press(tester, 'Save property details');
      expect(store.buildings.first['timeZone'], 'Asia/Ho_Chi_Minh');
      await mountReview(tester, directory(store.service));
      final button = find.byKey(const ValueKey('settings-room-room-101'));
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await enter(tester, 'settings_minimum', '2');
      await enter(tester, 'settings_buffer', '30');
      await toggle(tester);
      await enter(tester, 'settings_open', '09:05');
      await enter(tester, 'settings_close', '17:30');
      await press(tester, 'Save booking settings');
      expect(store.rooms.first['minBookingHours'], 2);
      expect(store.rooms.first['operatingHoursStartMin'], 545);
      expect(store.rooms.first['operatingHoursEndMin'], 1050);
      expect(find.text('09:05'), findsOneWidget);
      await reveal(tester, find.text('Booking settings saved.'));
      expect(find.text('Booking settings saved.'), findsOneWidget);
      await press(tester, 'Manage rooms');
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('17:30'), findsOneWidget);
    },
  );
  testWidgets(
    'invalid durations and hours send nothing; lost reply retries exactly; conflict and denial clear authority',
    (tester) async {
      final store = TeamPreviewStore();
      store.buildings.first['timeZone'] = 'Asia/Ho_Chi_Minh';
      final calls = <Map<String, dynamic>>[];
      String? error, message;
      final service = TeamService(
        transport: (name, data) async {
          if (error != null) {
            throw FirebaseFunctionsException(
              code: error,
              message: message ?? 'test',
            );
          }
          if (data['action'] == 'update') {
            calls.add(Map.of(data));
            final result = await store.call(name, data);
            if (calls.length == 1) throw StateError('lost');
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await enter(tester, 'settings_minimum', '169');
      await press(tester, 'Save booking settings');
      expect(calls, isEmpty);
      await enter(tester, 'settings_minimum', '1');
      await toggle(tester);
      await enter(tester, 'settings_open', '17:00');
      await enter(tester, 'settings_close', '17:00');
      await press(tester, 'Save booking settings');
      expect(calls, isEmpty);
      await enter(tester, 'settings_open', '09:00');
      await enter(tester, 'settings_close', '17:00');
      await press(tester, 'Save booking settings');
      await press(tester, 'Retry the same settings change');
      expect(calls[0], calls[1]);
      error = 'failed-precondition';
      message = 'settings_existing_conflict';
      await press(tester, 'Save booking settings');
      await reveal(tester, find.textContaining('These settings conflict'));
      expect(
        find.text(
          'These settings conflict with active bookings. Review their times and gaps before saving.',
        ),
        findsOneWidget,
      );
      error = 'aborted';
      await press(tester, 'Save booking settings');
      expect(find.text('Save booking settings'), findsNothing);
      await reveal(tester, find.textContaining('Copy any edits'));
      expect(find.textContaining('Copy any edits'), findsOneWidget);
      error = null;
      await press(tester, 'Reload booking settings');
      error = 'permission-denied';
      await press(tester, 'Save booking settings');
      expect(find.byKey(const ValueKey('settings_minimum')), findsNothing);
    },
  );
  testWidgets(
    'switching rooms during save ignores late result and read failures recover',
    (tester) async {
      final store = TeamPreviewStore(),
          pending = Completer<Map<String, dynamic>>();
      bool denied = false;
      final service = TeamService(
        transport: (name, data) async {
          if (denied) throw StateError('denied');
          return data['action'] == 'update'
              ? pending.future
              : store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await reveal(tester, find.text('Save booking settings'));
      await tester.tap(find.text('Save booking settings'));
      await tester.pump();
      await mountReview(tester, page(service, room: 'room-102'));
      pending.complete({});
      await tester.pumpAndSettle();
      expect(find.text('102'), findsOneWidget);
      expect(find.text('Booking settings saved.'), findsNothing);
      denied = true;
      await press(tester, 'Reload booking settings');
      expect(find.text('102'), findsNothing);
      denied = false;
      await press(tester, 'Reload booking settings');
      expect(find.text('102'), findsOneWidget);
    },
  );
  testWidgets(
    'populated settings and timezone form fit languages orientations scales and themes',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final language in ['en', 'vi']) {
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 1000),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final brightness in Brightness.values) {
              final store = TeamPreviewStore();
              store.buildings.first['timeZone'] =
                  'America/Argentina/Buenos_Aires';
              store.rooms.first.addAll({
                'roomNumber':
                    'Phòng gia đình Riverside — tầng mười hai hướng sông Hàn',
                'minBookingHours': 2,
                'cleaningBufferMinutes': 30,
                'operatingHoursStartMin': 1320,
                'operatingHoursEndMin': 360,
              });
              final t = AppTranslations(Locale(language));
              await mountReview(
                tester,
                page(store.service),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await reveal(tester, find.text(t['settings_hours_hint']));
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('SETTINGS_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/settings-info-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await enter(tester, 'settings_close', '22:00');
              await press(tester, t['settings_save']);
              await reveal(tester, find.text(t['settings_time_invalid']));
              expect(
                find.text(t['settings_time_invalid']).hitTestable(),
                findsOneWidget,
              );
              await enter(tester, 'settings_close', '06:00');
              await reveal(tester, find.text(t['settings_save']));
              expect(
                find.text(t['settings_save']).hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('SETTINGS_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/settings-form-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await mountReview(
                tester,
                PropertyDetailsScreen(
                  organizationId: 'preview',
                  buildingId: 'riverside',
                  service: store.service,
                  onBack: () {},
                ),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await reveal(tester, find.text(t['property_save']));
              expect(
                find.text(t['property_save']).hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('SETTINGS_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/timezone-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
            }
          }
        }
      }
    },
  );
}
