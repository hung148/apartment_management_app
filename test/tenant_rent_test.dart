import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_contacts_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_rent_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'tenant_lease_test.dart' show store;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;

Widget page(TeamService s) => TenantRentScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  tenantId: 'tenant-anh',
  service: s,
  onBack: () {},
);
void main() {
  testWidgets(
    'missing timezone and revoked price access show no editor; late reads cannot replace another tenant',
    (tester) async {
      final s = store()
        ..priceOverride = false
        ..workspaceRole = 'manager';
      await mountReview(
        tester,
        TenantContactsScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          service: s.service,
          onBack: () {},
        ),
      );
      expect(find.text('Rent schedule'), findsNothing);
      await mountReview(tester, page(s.service));
      expect(find.byKey(const ValueKey('rent-plan-date')), findsNothing);
      final pending = Completer<Map<String, dynamic>>();
      final service = TeamService(
        transport: (_, d) async {
          if (d['tenantId'] == 'tenant-anh') return pending.future;
          throw FirebaseFunctionsException(code: 'not-found', message: 'Gone');
        },
      );
      await mountReview(tester, page(service), settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await mountReview(
        tester,
        TenantRentScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          tenantId: 'different',
          service: service,
          onBack: () {},
        ),
      );
      pending.complete({
        'record': {'fullName': 'Stale private name'},
      });
      await tester.pumpAndSettle();
      expect(find.text('Stale private name'), findsNothing);
      expect(find.byKey(const ValueKey('rent-plan-date')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      s.workspaceRole = 'owner';
      s.buildings.first.remove('timeZone');
      await mountReview(tester, page(s.service));
      expect(find.byKey(const ValueKey('rent-plan-date')), findsNothing);
    },
  );
  testWidgets(
    'directory schedules replaces and cancels future rent without changing original rent',
    (tester) async {
      final s = store();
      await mountReview(
        tester,
        TenantContactsScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          service: s.service,
          onBack: () {},
        ),
      );
      await press(tester, 'Rent schedule');
      await enter(tester, 'rent-plan-date', '2026-09-27');
      await enter(tester, 'rent-plan-amount', '2000000');
      await enter(tester, 'rent-plan-reason', 'Renewal');
      await press(tester, 'Save future rent');
      expect(s.tenants.first['rentSchedule'], isNull);
      await enter(tester, 'rent-plan-date', '2026-10-01');
      await press(tester, 'Save future rent');
      expect(
        (s.tenants.first['rentSchedule'] as List).single['amountMinor'],
        2000000,
      );
      expect(s.tenants.first['monthlyRentMinor'], 1500000);
      await enter(tester, 'rent-plan-date', '2026-10-01');
      await enter(tester, 'rent-plan-amount', '2100000');
      await enter(tester, 'rent-plan-reason', 'Correct planned amount');
      await press(tester, 'Save future rent');
      expect((s.tenants.first['rentSchedule'] as List).length, 1);
      await press(tester, 'Select this change to cancel');
      await enter(tester, 'rent-plan-reason', 'Agreement withdrawn');
      await press(tester, 'Confirm cancellation');
      expect(s.tenants.first['rentSchedule'], isEmpty);
      final records = s.rentHistory['tenant-anh']!;
      expect(records.length, 3);
      expect(records.first['after'], isNull);
      expect((records.first['before'] as Map)['amountMinor'], 2100000);
      expect((records[1]['before'] as Map)['amountMinor'], 2000000);
      expect((records[1]['after'] as Map)['amountMinor'], 2100000);
      expect(records.last['before'], isNull);
    },
  );
  testWidgets(
    'uncertain rent save freezes identical retry; stale and denied saves require reload',
    (tester) async {
      final s = store();
      final calls = <Map<String, dynamic>>[];
      String? error;
      final service = TeamService(
        transport: (name, d) async {
          if (d['action'] != 'read') {
            calls.add(Map.of(d));
            if (error != null) {
              throw FirebaseFunctionsException(code: error, message: 'test');
            }
            final result = await s.call(name, d);
            if (calls.length == 1) throw StateError('lost');
            return result;
          }
          return s.call(name, d);
        },
      );
      await mountReview(tester, page(service));
      await enter(tester, 'rent-plan-date', '2026-10-01');
      await enter(tester, 'rent-plan-amount', '2000000');
      await enter(tester, 'rent-plan-reason', 'Reason');
      await press(tester, 'Save future rent');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('rent-plan-date')))
            .enabled,
        false,
      );
      await press(tester, 'Retry the same rent change');
      expect(calls[0], calls[1]);
      expect(s.rentHistory['tenant-anh']!.length, 1);
      error = 'aborted';
      await enter(tester, 'rent-plan-date', '2026-11-01');
      await enter(tester, 'rent-plan-amount', '2200000');
      await enter(tester, 'rent-plan-reason', 'Reason');
      await press(tester, 'Save future rent');
      expect(find.byKey(const ValueKey('rent-plan-date')), findsNothing);
      await press(tester, 'Reload rent schedule');
      error = 'permission-denied';
      await enter(tester, 'rent-plan-date', '2026-11-01');
      await enter(tester, 'rent-plan-amount', '2200000');
      await enter(tester, 'rent-plan-reason', 'Reason');
      await press(tester, 'Save future rent');
      expect(find.text(s.tenants.first['fullName'] as String), findsNothing);
    },
  );
  testWidgets(
    'populated schedules and errors fit locales sizes text scales and themes',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final lang in ['en', 'vi']) {
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 1000),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final brightness in Brightness.values) {
              final s = store();
              s.tenants.first['fullName'] =
                  'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông, căn hộ hướng sông';
              s.tenants.first['rentSchedule'] = [
                {'effectiveDate': '2026-10-01', 'amountMinor': 1900000},
                {'effectiveDate': '2027-01-01', 'amountMinor': 2000000},
              ];
              final t = AppTranslations(Locale(lang));
              await mountReview(
                tester,
                page(s.service),
                language: lang,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await enter(tester, 'rent-plan-date', '2027-02-01');
              await enter(tester, 'rent-plan-amount', '2200000');
              await press(tester, t['rent_plan_save']);
              await reveal(tester, find.text(t['rent_plan_reason_required']));
              expect(
                find.text(t['rent_plan_reason_required']).hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('RENT_PLAN_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/rent-plan-$lang-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await enter(
                tester,
                'rent-plan-reason',
                'Điều chỉnh theo thỏa thuận gia hạn',
              );
              await press(tester, t['rent_plan_save']);
              expect((s.tenants.first['rentSchedule'] as List).length, 3);
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );
}
