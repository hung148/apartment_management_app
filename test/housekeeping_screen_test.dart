import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/housekeeping_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;
import 'access_editor_test.dart' show choose;

void main() {
  testWidgets('switching context during a save unlocks the new context', (
    tester,
  ) async {
    final store = TeamPreviewStore()..workspaceRole = 'housekeeper';
    final pending = Completer<Map<String, dynamic>>();
    final service = TeamService(
      transport: (name, data) async {
        if (name == 'mutateHousekeepingTask') return pending.future;
        return store.call(name, data);
      },
    );
    Widget page(String org) => HousekeepingScreen(
      organizationId: org,
      buildingId: 'riverside',
      service: service,
      onBack: () {},
    );
    await mountReview(tester, page('preview'));
    await reveal(tester, find.text('Done'));
    await tester.tap(find.text('Done'));
    await tester.pump();
    await mountReview(tester, page('other'), settle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final refresh = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Refresh'),
    );
    expect(refresh.onPressed, isNotNull);
    pending.complete({});
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Refresh'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'manager assigns and worker completes without assignment controls',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'manager';
      Widget page() => HousekeepingScreen(
        key: UniqueKey(),
        organizationId: 'preview',
        buildingId: 'riverside',
        service: store.service,
        onBack: () {},
      );
      await mountReview(tester, page());
      await press(tester, 'Assign');
      await press(tester, 'Save assignment');
      expect(store.tasks.length, 1);
      await choose(tester, 'task-room', '101 — Phòng gia đình Riverside');
      await choose(
        tester,
        'task-person',
        'Nguyễn Thị Lan — Nhân viên dọn phòng',
      );
      await reveal(tester, find.byKey(const ValueKey('task-title')));
      await tester.enterText(
        find.byKey(const ValueKey('task-title')),
        'Replace towels',
      );
      await press(tester, 'Save assignment');
      expect(store.tasks.length, 2);
      store.tasks.removeAt(0);
      store.workspaceRole = 'housekeeper';
      await mountReview(tester, page());
      expect(find.text('Assign'), findsNothing);
      await press(tester, 'Start');
      expect(store.tasks.single['status'], 'inProgress');
      await press(tester, 'Done');
      expect(store.tasks.single['status'], 'completed');
      expect(find.text('Done'), findsNothing);
    },
  );
  testWidgets(
    'uncertain task response retains same operation and read failure clears data',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'housekeeper';
      final calls = <Map<String, dynamic>>[];
      var denied = false;
      final service = TeamService(
        transport: (name, data) async {
          if (denied) throw StateError('revoked');
          if (name == 'mutateHousekeepingTask') {
            calls.add(Map.of(data));
            final result = await store.call(name, data);
            if (calls.length == 1) throw StateError('lost reply');
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(
        tester,
        HousekeepingScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          service: service,
          onBack: () {},
        ),
      );
      await press(tester, 'Done');
      await press(tester, 'Retry the same task change');
      expect(calls[0], calls[1]);
      denied = true;
      await press(tester, 'Refresh');
      expect(find.textContaining('thay khăn'), findsNothing);
    },
  );
  testWidgets(
    'populated assignment form fits locales orientations scales and themes',
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
              final store = TeamPreviewStore()..workspaceRole = 'manager';
              final t = AppTranslations(Locale(language));
              await mountReview(
                tester,
                HousekeepingScreen(
                  key: UniqueKey(),
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
              await press(tester, t['tasks_assign']);
              await choose(
                tester,
                'task-room',
                '101 — Phòng gia đình Riverside',
              );
              await choose(
                tester,
                'task-person',
                'Nguyễn Thị Lan — Nhân viên dọn phòng',
              );
              await reveal(tester, find.byKey(const ValueKey('task-title')));
              await tester.enterText(
                find.byKey(const ValueKey('task-title')),
                'Thay khăn và kiểm tra phòng gia đình Riverside',
              );
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              await reveal(tester, find.text(t['tasks_save']));
              expect(find.text(t['tasks_save']).hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('TASK_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/tasks-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
            }
          }
        }
      }
    },
  );
  testWidgets('a task shows its planned and real work time', (tester) async {
    final store = TeamPreviewStore()..workspaceRole = 'manager';
    store.tasks
      ..first['plannedStart'] = '2026-10-06 12:00'
      ..first['plannedEnd'] = '2026-10-06 14:00'
      ..first['startedLocal'] = '2026-10-06 09:45'
      ..add({
        'id': 'clean-102',
        'roomId': 'room-101',
        'assigneeId': 'preview-housekeeper',
        'title': 'Lau kính',
        'status': 'completed',
        'buildingId': 'riverside',
        'startedLocal': '2026-10-06 23:50',
        'completedLocal': '2026-10-07 00:20',
      });
    await mountReview(
      tester,
      HousekeepingScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        service: TeamService(transport: store.call),
        onBack: () {},
      ),
    );
    expect(find.text('Planned: 2026-10-06 12:00 – 14:00'), findsOneWidget);
    // The list uses the calendar's words for a cleaning's state.
    expect(find.text('Not started'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
    expect(find.text('Actual: 2026-10-06 09:45 – …'), findsOneWidget);
    expect(
      find.text('Actual: 2026-10-06 23:50 – 2026-10-07 00:20'),
      findsOneWidget,
    );
    // Short button labels (1–3 words).
    expect(find.widgetWithText(OutlinedButton, 'Start'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
  });
}
