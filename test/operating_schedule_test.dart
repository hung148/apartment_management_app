import 'package:flutter/material.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/operating_schedule_editor.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'room_booking_settings_test.dart' show page, enter, toggle;
import 'room_rates_test.dart' show press, reveal;
import 'team_review_test.dart' show mountReview;
import 'access_editor_test.dart' show choose;

ScheduleDraft populated() => ScheduleDraft(
  List.generate(
    7,
    (_) => [ScheduleWindow('08:00', '12:00'), ScheduleWindow('14:00', '22:00')],
  ),
  [
    ScheduleException('2030-01-08', [ScheduleWindow('10:00', '17:00')]),
    ScheduleException('2030-01-09', []),
  ],
);
void main() {
  test(
    'draft checks every weekday and exception, including overnight overlap and date normalization',
    () {
      final d = populated();
      expect(ScheduleDraft.fromMap(d.toMap()!).toMap(), d.toMap());
      d.week[6] = [ScheduleWindow('22:00', '09:00')];
      expect(d.toMap(), isNull);
      d.week[0] = [ScheduleWindow('09:00', '12:00')];
      expect(d.toMap(), isNotNull);
      d.exceptions.add(ScheduleException('2030-02-30', []));
      expect(d.toMap(), isNull);
      d.exceptions.last.date = '2030-01-09';
      expect(d.toMap(), isNull);
      d.exceptions.last.date = '2030-01-10';
      d.exceptions.last.windows.add(ScheduleWindow('22:00', '10:00'));
      expect(d.toMap(), isNull);
      d.exceptions.last.windows.clear();
      expect(d.toMap(), isNotNull);
      d.week[3].add(ScheduleWindow('bad', '17:00'));
      expect(d.toMap(), isNull);
    },
  );
  test(
    'draft enforces six windows and sixty exceptions, preserving independent daily copies',
    () {
      final d = ScheduleDraft.daily(480, 720);
      d.week[0].first.start = '10:00';
      expect(d.week[1].first.start, '08:00');
      d.week[0] = List.generate(
        7,
        (i) => ScheduleWindow(
          '${i.toString().padLeft(2, '0')}:00',
          '${i.toString().padLeft(2, '0')}:30',
        ),
      );
      expect(d.toMap(), isNull);
      d.week[0].removeLast();
      expect(d.toMap(), isNotNull);
      for (var i = 0; i < 61; i++) {
        d.exceptions.add(
          ScheduleException(
            DateTime.utc(
              2030,
              1,
              1,
            ).add(Duration(days: i)).toIso8601String().substring(0, 10),
            [],
          ),
        );
      }
      expect(d.toMap(), isNull);
      d.exceptions.removeLast();
      expect(d.toMap(), isNotNull);
    },
  );
  testWidgets(
    'split weekdays and late-opening date save, reload, close and restore without altering other days',
    (tester) async {
      final store = TeamPreviewStore();
      store.buildings.first['timeZone'] = 'Asia/Ho_Chi_Minh';
      await mountReview(tester, page(store.service));
      await toggle(tester);
      await enter(tester, 'settings_open', '08:00');
      await enter(tester, 'settings_close', '12:00');
      await press(tester, 'Weekly schedule and date exceptions');
      await press(tester, 'Add window');
      await enter(tester, 'schedule-open-1', '14:00');
      await enter(tester, 'schedule-close-1', '22:00');
      await choose(tester, 'schedule-weekday-0', 'Tuesday');
      await enter(tester, 'schedule-open-0', '10:00');
      await enter(tester, 'schedule-close-0', '17:00');
      await press(tester, 'Add date exception');
      final date = find.byWidgetPredicate(
        (w) =>
            w is TextFormField && w.key.toString().contains('schedule-date-'),
      );
      await reveal(tester, date);
      await tester.enterText(date, '2030-01-08');
      await press(tester, 'Add window');
      await enter(tester, 'schedule-open-0', '11:00');
      await enter(tester, 'schedule-close-0', '15:00');
      await press(tester, 'Save booking settings');
      final stored = store.rooms.first['operatingSchedule'] as Map;
      expect(stored['week']['0'], [
        {'start': 480, 'end': 720},
        {'start': 840, 'end': 1320},
      ]);
      expect(stored['week']['1'], [
        {'start': 600, 'end': 1020},
      ]);
      expect(stored['week']['2'], [
        {'start': 480, 'end': 720},
      ]);
      expect(stored['exceptions']['2030-01-08'], [
        {'start': 660, 'end': 900},
      ]);
      expect(store.rooms.first['operatingHoursStartMin'], isNull);
      await press(tester, 'Reload booking settings');
      await press(tester, 'Edit this date');
      expect(find.text('11:00'), findsOneWidget);
      await press(tester, 'Close this day');
      await press(tester, 'Save booking settings');
      expect(
        store.rooms.first['operatingSchedule']['exceptions']['2030-01-08'],
        isEmpty,
      );
      await press(tester, 'Restore weekly hours');
      await press(tester, 'Save booking settings');
      expect(store.rooms.first['operatingSchedule']['exceptions'], isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'invalid hidden dates send nothing and lost replies freeze the entire schedule for exact retry',
    (tester) async {
      final store = TeamPreviewStore();
      store.buildings.first['timeZone'] = 'UTC';
      final draft = populated();
      store.rooms.first['operatingSchedule'] = draft.toMap();
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (name, data) async {
          if (data['action'] == 'update') {
            calls.add(data);
            final result = await store.call(name, data);
            if (calls.length == 1) throw StateError('reply lost');
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await press(tester, 'Add date exception');
      final date = find.byWidgetPredicate(
        (w) =>
            w is TextFormField && w.key.toString().contains('schedule-date-'),
      );
      await reveal(tester, date);
      await tester.enterText(date, '2030-02-30');
      await press(tester, 'Edit weekly hours');
      await press(tester, 'Save booking settings');
      expect(calls, isEmpty);
      await reveal(tester, find.textContaining('Review all days and dates'));
      expect(
        find.textContaining('Review all days and dates').hitTestable(),
        findsOneWidget,
      );
      final edit = find.widgetWithText(TextButton, 'Edit this date').last;
      await reveal(tester, edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await reveal(tester, date);
      await tester.enterText(date, '2030-02-28');
      await press(tester, 'Save booking settings');
      expect(calls, hasLength(1));
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('schedule-add-window')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('schedule-add-exception')),
            )
            .onPressed,
        isNull,
      );
      await press(tester, 'Retry the same settings change');
      expect(calls, hasLength(2));
      expect(calls[0], calls[1]);
      expect(
        store.rooms.first['operatingSchedule']['exceptions']['2030-02-28'],
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'populated schedules and date editor remain usable across languages, sizes, text scales and themes',
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
                'operatingSchedule': populated().toMap(),
                'operatingHoursStartMin': null,
                'operatingHoursEndMin': null,
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
              await enter(tester, 'schedule-open-1', '15:00');
              await reveal(
                tester,
                find.byKey(const ValueKey('schedule-close-1')),
              );
              expect(
                find.byKey(const ValueKey('schedule-close-1')).hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('SCHEDULE_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/schedule-week-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              final edit = find
                  .widgetWithText(TextButton, t['schedule_edit_exception'])
                  .first;
              await reveal(tester, edit);
              await tester.tap(edit);
              await tester.pumpAndSettle();
              await enter(tester, 'schedule-close-0', '16:00');
              await tester.pump();
              expect(find.text('10:00–16:00'), findsOneWidget);
              await reveal(
                tester,
                find.byKey(const ValueKey('schedule-close-0')),
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('SCHEDULE_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/schedule-date-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await press(tester, t['settings_save']);
              expect(
                store
                    .rooms
                    .first['operatingSchedule']['exceptions']['2030-01-08'],
                [
                  {'start': 600, 'end': 960},
                ],
              );
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );
}
