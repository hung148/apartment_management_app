import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/access_request.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;

Future<void> fill(WidgetTester tester) async {
  for (final field in {
    'team_request_org': 'preview',
    'team_request_code': 'demo-code',
    'team_request_name': 'Nguyễn Văn Bảo — Nhân viên lễ tân Riverside',
  }.entries) {
    final finder = find.byKey(ValueKey(field.key));
    await reveal(tester, finder);
    await tester.enterText(finder, field.value);
  }
}

void main() {
  testWidgets(
    'request creates no linked account and reflects explicit owner review',
    (tester) async {
      final store = TeamPreviewStore();
      await mountReview(
        tester,
        AccessRequestScreen(service: store.service, onBack: () {}),
      );
      await fill(tester);
      await press(tester, 'Send request');
      expect(store.staff.every((s) => s['accountId'] == null), true);
      expect(store.requests.last['status'], 'pending');
      await store.service.execute(
        store.service.prepare('preview', TeamAction.reviewRequest, {
          'requestId': 'local-request',
          'decision': 'approve',
          'staffId': 'anh',
          'access': TeamPreviewStore.grant(),
        }),
      );
      await press(tester, 'Check my request status');
      await reveal(tester, find.text('Approved'));
      expect(find.text('Approved'), findsOneWidget);
      await reveal(tester, find.byKey(const ValueKey('team_request_org')));
      await tester.enterText(
        find.byKey(const ValueKey('team_request_org')),
        'other',
      );
      await tester.pump();
      expect(find.text('Approved'), findsNothing);
    },
  );

  testWidgets('uncertain submit locks input and retries the same operation', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    final service = TeamService(
      transport: (name, data) async {
        if (name == 'mutateTeam') {
          calls.add(data);
          if (calls.length == 1) throw Exception('connection lost');
          return {'status': 'pending'};
        }
        return {'records': <Map<String, dynamic>>[], 'nextCursor': null};
      },
    );
    await mountReview(
      tester,
      AccessRequestScreen(service: service, onBack: () {}),
    );
    await fill(tester);
    await press(tester, 'Send request');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('team_request_org')))
          .readOnly,
      true,
    );
    await press(tester, 'Retry same save');
    expect(calls.length, 2);
    expect(calls[0], calls[1]);
    expect(calls[0]['action'], 'requestAccess');
  });

  testWidgets(
    'denied status clears previous records and rejected submit unlocks',
    (tester) async {
      var denied = false;
      final service = TeamService(
        transport: (name, data) async {
          if (denied || name == 'mutateTeam') {
            throw FirebaseFunctionsException(code: 'permission-denied', message: 'Denied');
          }
          return {
            'records': [
              {'displayName': 'Private name', 'status': 'pending'},
            ],
          };
        },
      );
      await mountReview(
        tester,
        AccessRequestScreen(service: service, onBack: () {}),
      );
      await fill(tester);
      await press(tester, 'Check my request status');
      expect(find.text('Private name'), findsOneWidget);
      denied = true;
      await press(tester, 'Check my request status');
      expect(find.text('Private name'), findsNothing);
      await press(tester, 'Send request');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('team_request_org')))
            .readOnly,
        false,
      );
    },
  );

  testWidgets(
    'request form and populated status fit locales sizes scales themes',
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
              await mountReview(
                tester,
                AccessRequestScreen(
                  key: UniqueKey(),
                  service: TeamPreviewStore().service,
                  onBack: () {},
                ),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await fill(tester);
              await press(tester, t['team_request_submit']);
              await reveal(tester, find.text(t['team_status_pending']));
              expect(
                find.text(t['team_status_pending']).hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('REQUEST_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/request-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
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
