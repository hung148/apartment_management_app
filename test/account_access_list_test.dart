import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/account_access_list.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;
import 'access_editor_test.dart' show choose;

void main() {
  testWidgets(
    'loading and empty review stay usable; stale organizations cannot repopulate accounts',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final store = TeamPreviewStore();
      final service = TeamService(
        transport: (name, data) async {
          if (data['view'] == 'myAccess') {
            return {'record': TeamPreviewStore.grant('owner')};
          }
          if (data['organizationId'] == 'old') return pending.future;
          return {'records': <Map<String, dynamic>>[]};
        },
      );
      await mountReview(
        tester,
        AccountAccessList(
          organizationId: 'old',
          service: service,
          onBack: () {},
        ),
        settle: false,
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await mountReview(
        tester,
        AccountAccessList(
          organizationId: 'new',
          service: service,
          onBack: () {},
        ),
      );
      expect(find.text('No accounts to review.'), findsOneWidget);
      pending.complete({'records': store.accounts});
      await tester.pumpAndSettle();
      expect(find.text('an@example.com'), findsNothing);
      expect(find.text('No accounts to review.'), findsOneWidget);
    },
  );
  testWidgets(
    'unlinked account requires explicit assignment and never creates staff',
    (tester) async {
      final store = TeamPreviewStore();
      await mountReview(
        tester,
        AccountAccessList(
          organizationId: 'preview',
          service: store.service,
          onBack: () {},
        ),
      );
      await press(tester, 'Manage account access');
      await reveal(tester, find.byKey(const ValueKey('access-reason')));
      await tester.enterText(
        find.byKey(const ValueKey('access-reason')),
        'Reviewed account',
      );
      await press(tester, 'Save access');
      expect(store.completed, isEmpty);
      await choose(tester, 'access-role', 'Receptionist');
      await choose(tester, 'access-status', 'Active');
      await press(tester, 'Save access');
      expect(store.accounts.single['role'], 'receptionist');
      expect(store.accounts.single['buildingIds'], isEmpty);
      expect(store.staff.length, 2);
      expect(store.completed.length, 1);
      expect(find.text('Account access review'), findsOneWidget);
    },
  );

  testWidgets(
    'pagination failure clears accounts and protected accounts have no editor',
    (tester) async {
      final store = TeamPreviewStore();
      final service = TeamService(
        transport: (name, data) async {
          if (data['view'] != 'access') return store.call(name, data);
          if (data['cursor'] != null) throw StateError('revoked');
          return {
            'records': [
              {...store.accounts.single, 'canManageAccess': false},
            ],
            'nextCursor': 'next',
          };
        },
      );
      await mountReview(
        tester,
        AccountAccessList(
          organizationId: 'preview',
          service: service,
          onBack: () {},
        ),
      );
      expect(find.text('Manage account access'), findsNothing);
      await press(tester, AppTranslations(const Locale('en'))['team_more']);
      expect(find.text('an@example.com'), findsNothing);
      expect(find.text('No linked staff profile recorded'), findsNothing);
    },
  );

  testWidgets('account review fits populated en vi screens scales and themes', (
    tester,
  ) async {
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
            final store = TeamPreviewStore();
            await mountReview(
              tester,
              AccountAccessList(
                key: UniqueKey(),
                organizationId: 'preview',
                service: store.service,
                onBack: () {},
              ),
              language: language,
              size: size,
              scale: scale,
              brightness: brightness,
            );
            await reveal(tester, find.text(t['team_manage_access']));
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('ACCOUNT_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  '../.dart_tool/accounts-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                ),
              );
            }
            await press(tester, t['team_manage_access']);
            await reveal(tester, find.text(t['team_cancel']));
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });
}
