import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/activity_history.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;

void main() {
  test(
    'preview activity pages match newest-first ordering and actor filtering',
    () async {
      final store = TeamPreviewStore();
      store.activity.clear();
      for (final row in [
        {
          'id': 'z-old',
          'actorId': 'worker',
          'createdAt': '2026-09-25T10:00:00Z',
        },
        {
          'id': 'a-new',
          'actorId': 'worker',
          'createdAt': '2026-09-25T12:00:00Z',
        },
        {
          'id': 'c-tie',
          'actorId': 'worker',
          'createdAt': '2026-09-25T11:00:00Z',
        },
        {
          'id': 'b-tie',
          'actorId': 'worker',
          'createdAt': '2026-09-25T11:00:00Z',
        },
        {
          'id': 'other',
          'actorId': 'other',
          'createdAt': '2026-09-25T13:00:00Z',
        },
      ]) {
        store.activity.add(row);
      }
      final first = await store.service.page(
        'preview',
        TeamView.activity,
        actorId: 'worker',
        limit: 2,
      );
      expect(first.records.map((r) => r['id']), ['a-new', 'c-tie']);
      final second = await store.service.page(
        'preview',
        TeamView.activity,
        actorId: 'worker',
        limit: 2,
        cursor: first.nextCursor,
      );
      expect(second.records.map((r) => r['id']), ['b-tie', 'z-old']);
      expect(second.nextCursor, isNull);
      await expectLater(
        store.service.page(
          'preview',
          TeamView.activity,
          actorId: 'other',
          cursor: first.nextCursor,
        ),
        throwsA(isA<Exception>()),
      );
    },
  );
  testWidgets(
    'operational event details show amounts and room moves without identity fields',
    (tester) async {
      final store = TeamPreviewStore()..addOperationalSamples();
      store.activity.removeAt(0);
      await mountReview(
        tester,
        ActivityHistory(
          organizationId: 'preview',
          service: store.service,
          onBack: () {},
        ),
        size: const Size(1440, 1000),
      );
      expect(find.text('Booking payment collected'), findsOneWidget);
      expect(find.text('Tenant moved rooms'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Tenant moved rooms')).dy,
        lessThan(tester.getTopLeft(find.text('Booking payment collected')).dy),
      );
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('activity-sample-payment')),
          matching: find.text('Change details'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Paid amount: 500000'), findsOneWidget);
      expect(find.textContaining('Guest'), findsNothing);
    },
  );
  testWidgets(
    'pagination filter and denied refresh never retain stale events',
    (tester) async {
      final store = TeamPreviewStore();
      final calls = <Map<String, dynamic>>[];
      var denied = false;
      final service = TeamService(
        transport: (name, data) async {
          calls.add(data);
          if (denied) throw StateError('denied');
          return {
            'records': [
              if (data['actorId'] == null)
                {
                  ...store.activity.first,
                  'id': data['cursor'] == null ? 'first-event' : 'older-event',
                },
            ],
            'nextCursor': data['cursor'] == null && data['actorId'] == null
                ? 'next'
                : null,
          };
        },
      );
      await mountReview(
        tester,
        ActivityHistory(
          organizationId: 'preview',
          service: service,
          onBack: () {},
        ),
      );
      await press(tester, 'Load more');
      expect(calls.last['cursor'], 'next');
      await reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'other-account');
      await press(tester, 'Refresh');
      expect(calls.last['actorId'], 'other-account');
      expect(find.text('No activity found.'), findsOneWidget);
      denied = true;
      await press(tester, 'Refresh');
      expect(find.text('Account access changed'), findsNothing);
      expect(find.textContaining('Activity unavailable'), findsOneWidget);
    },
  );
  testWidgets(
    'populated expanded audit details fit languages sizes scales and themes',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final language in ['en', 'vi']) {
        final t = AppTranslations(Locale(language));
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 1000),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final brightness in Brightness.values) {
              final fixture = TeamPreviewStore()..addOperationalSamples();
              if (const bool.fromEnvironment('OPERATIONAL_GOLDENS')) {
                fixture.activity.removeAt(0);
                fixture.activity.removeLast();
              } else {
                fixture.activity.removeRange(1, fixture.activity.length);
              }
              await mountReview(
                tester,
                ActivityHistory(
                  key: UniqueKey(),
                  organizationId: 'preview',
                  service: fixture.service,
                  onBack: () {},
                ),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await reveal(tester, find.text(t['activity_changes']));
              await tester.tap(find.text(t['activity_changes']));
              await tester.pumpAndSettle();
              await reveal(
                tester,
                find.textContaining('${t['activity_before']}\n'),
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('ACTIVITY_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/activity-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
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
