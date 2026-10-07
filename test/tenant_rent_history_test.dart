import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_rent_history.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_contacts_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'tenant_rent_test.dart' show page;
import 'team_review_test.dart' show mountReview;

import 'room_booking_settings_test.dart' show enter;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> press(WidgetTester tester, String label) async {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Map<String, dynamic> row(int i) => {
  'id': 'version-$i',
  'actorId': 'manager-account-12345678901234567890123456789',
  'currency': 'USD',
  'createdAt': '2026-09-27T12:00:00Z',
  'effectiveDate': '2026-10-01',
  'timeZone': 'Asia/Ho_Chi_Minh',
  'reason': List.filled(
    20,
    'Agreement reviewed / Thỏa thuận điều chỉnh.',
  ).join(' '),
  'before': {'effectiveDate': '2026-10-01', 'amountMinor': 123456789},
  'after': i == 1
      ? null
      : {'effectiveDate': '2026-10-01', 'amountMinor': 987654321},
};
Widget history(TeamService s, {String building = 'riverside'}) =>
    TenantRentHistory(
      organizationId: 'preview',
      buildingId: building,
      tenantId: 'tenant-anh',
      service: s,
      onBack: () {},
    );
void main() {
  // 2026-10-04 (Tom): no separate rent pages behind buttons; the lease
  // section lists the rent changes, and only people who may change prices
  // see them and the "Change" button.
  testWidgets(
    'the tenant page lists rent changes; price-restricted managers see the rent only',
    (tester) async {
      final store = TeamPreviewStore();
      store.buildings.first['timeZone'] = 'Asia/Ho_Chi_Minh';
      store.tenants.first['rentSchedule'] = [
        {'effectiveDate': '2026-09-10', 'amountMinor': 1800000},
        {'effectiveDate': '2026-10-01', 'amountMinor': 2000000},
      ];
      Widget directory() => TenantContactsScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        service: store.service,
        onBack: () {},
      );
      Future<void> open() async {
        final f = find.byKey(const ValueKey('tenant-contact-tenant-anh'));
        await reveal(tester, f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      await mountReview(tester, directory());
      await open();
      expect(find.text('Rent-change history'), findsNothing);
      expect(find.text('Rent schedule'), findsNothing);
      expect(find.text('1,800,000 VND'), findsOneWidget, reason: 'today');
      expect(
        find.text('From 2026-10-01 · 2,000,000 VND · planned'),
        findsOneWidget,
      );
      expect(
        find.text('From 2026-09-10 · 1,800,000 VND · in effect'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lease-rent-cancel-2026-10-01')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lease-rent-cancel-2026-09-10')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      store.workspaceRole = 'manager';
      store.priceOverride = false;
      await mountReview(tester, directory());
      await open();
      expect(find.text('1,500,000 VND'), findsOneWidget);
      expect(find.byKey(const ValueKey('lease-rent-change')), findsNothing);
      expect(find.textContaining('planned'), findsNothing);
    },
  );
  testWidgets(
    'saved history opens from rent schedule and returning preserves unsaved draft',
    (tester) async {
      final store = TeamPreviewStore();
      store.buildings.first['timeZone'] = 'Asia/Ho_Chi_Minh';
      await mountReview(tester, page(store.service));
      await enter(tester, 'rent-plan-date', '2026-10-01');
      await enter(tester, 'rent-plan-amount', '2000000');
      await enter(tester, 'rent-plan-reason', 'Signed amendment');
      await press(tester, 'Save future rent');
      await enter(tester, 'rent-plan-reason', 'Unsaved draft');
      await press(tester, 'Rent-change history');
      expect(find.textContaining('preview-owner'), findsOneWidget);
      expect(find.textContaining('Signed amendment'), findsOneWidget);
      expect(find.textContaining('2,000,000 VND'), findsOneWidget);
      await press(tester, 'Back to rent schedule');
      expect(find.text('Unsaved draft'), findsOneWidget);
    },
  );
  testWidgets(
    'pagination retries preserve rows, revocation clears sensitive history, refresh recovers',
    (tester) async {
      final store = TeamPreviewStore();
      store.rentHistory['tenant-anh'] = List.generate(23, row);
      String? failure;
      final service = TeamService(
        transport: (name, data) async {
          if (failure != null) {
            throw FirebaseFunctionsException(code: failure, message: 'test');
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, history(service));
      expect(
        find.byKey(const ValueKey('rent-history-version-0')),
        findsOneWidget,
      );
      failure = 'unavailable';
      await press(tester, 'Load older versions');
      expect(
        find.byKey(const ValueKey('rent-history-version-0')),
        findsOneWidget,
      );
      failure = null;
      await press(tester, 'Retry older versions');
      expect(
        find.byKey(const ValueKey('rent-history-version-22')),
        findsOneWidget,
      );
      expect(find.text('Load older versions'), findsNothing);
      failure = 'permission-denied';
      await press(tester, 'Refresh history');
      expect(find.byType(Card), findsNothing);
      expect(find.byType(Card), findsNothing);
      failure = null;
      store.rentHistory.clear();
      await press(tester, 'Refresh history');
      expect(
        find.text('No recorded rent changes for this tenant.'),
        findsOneWidget,
      );
    },
  );
  testWidgets('switching properties ignores late history responses', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final service = TeamService(
      transport: (name, data) async => data['buildingId'] == 'riverside'
          ? pending.future
          : {'records': [], 'nextCursor': null},
    );
    await mountReview(tester, history(service), settle: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await mountReview(tester, history(service, building: 'other'));
    pending.complete({
      'records': [row(0)],
      'nextCursor': null,
    });
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNothing);
    expect(
      find.text('No recorded rent changes for this tenant.'),
      findsOneWidget,
    );
  });
  testWidgets(
    'long before and after versions fit languages sizes text scales and themes',
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
              store.rentHistory['tenant-anh'] = [row(0)];
              final t = AppTranslations(Locale(language));
              await mountReview(
                tester,
                history(store.service),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              final previous = find.text(
                '${t['rent_history_before']}: 1,234,567.89 USD',
              );
              await reveal(tester, previous);
              expect(previous.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('RENT_HISTORY_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/rent-history-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
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
