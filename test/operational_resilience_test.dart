import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/lease_lifecycle_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/invoice_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_layout_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/booking_workspace_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/operational_widgets.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'tenant_lease_test.dart' show store;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press;
import 'room_booking_settings_test.dart' show enter;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'invoice lost reply survives remount and retries the identical operation',
    (tester) async {
      final s = store();
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (name, d) async {
          final result = await s.call(name, d);
          if (name == 'invoices' && d['action'] == 'create') {
            calls.add(Map.of(d));
            if (calls.length == 1) throw StateError('Lost response');
          }
          return result;
        },
      );
      Widget page() => InvoiceScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        accountId: 'owner',
        service: service,
        onBack: () {},
      );
      await mountReview(tester, page());
      await press(tester, 'Create new');
      await enter(tester, 'ops-start', '2026-10-01');
      await enter(tester, 'ops-end', '2026-11-01');
      await enter(tester, 'ops-due', '2026-10-05');
      await enter(tester, 'ops-reason', 'Private invoice reason');
      await press(tester, 'Review calculation');
      await press(tester, 'Confirm and save');
      expect(s.operationalInvoices.length, 1);
      expect(find.textContaining('No confirmed reply'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await mountReview(tester, page());
      await press(tester, 'Retry identical request');
      expect(calls.length, 2);
      expect(calls[0], calls[1]);
      expect(s.operationalInvoices.length, 1);
    },
  );
  testWidgets(
    'booking denial clears private details and late context responses are ignored',
    (tester) async {
      final pending = Completer<Map<String, dynamic>>();
      final service = TeamService(
        transport: (_, d) async {
          if (d['buildingId'] == 'old') return pending.future;
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Denied',
          );
        },
      );
      Widget page(String building) => BookingWorkspaceScreen(
        organizationId: 'preview',
        buildingId: building,
        accountId: 'owner',
        service: service,
        onBack: () {},
      );
      await mountReview(tester, page('old'), settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await mountReview(tester, page('new'));
      pending.complete({
        'records': [
          {'id': 'private', 'guestName': 'Private previous guest'},
        ],
        'canManage': true,
        'timeZone': 'UTC',
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Private previous guest'), findsNothing);
      expect(find.textContaining('access denied'), findsOneWidget);
    },
  );
  testWidgets(
    'populated operational forms remain reachable across locales sizes scales themes',
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
              final s = store();
              s.buildings.first.addAll({
                'floors': 2,
                'roomPrefix': 'Riverside',
                'roomType':
                    'Family studio / Phòng gia đình hướng sông rất rộng',
                'roomArea': 123.45,
                'floorRoomCounts': [20, 30],
              });
              s.rooms.last.addAll({
                'rentalMode': 'hourly',
                'hourlyPrice': 123456,
                'currency': 'VND',
              });
              final pages = <String, Widget>{
                'layout': PropertyLayoutScreen(
                  organizationId: 'preview',
                  buildingId: 'riverside',
                  service: s.service,
                  onBack: () {},
                ),
                'lease': LeaseLifecycleScreen(
                  organizationId: 'preview',
                  buildingId: 'riverside',
                  tenantId: 'tenant-anh',
                  service: s.service,
                  onBack: () {},
                ),
                'invoice': InvoiceScreen(
                  organizationId: 'preview',
                  buildingId: 'riverside',
                  accountId: 'owner',
                  service: s.service,
                  onBack: () {},
                ),
                'booking': BookingWorkspaceScreen(
                  organizationId: 'preview',
                  buildingId: 'riverside',
                  accountId: 'owner',
                  service: s.service,
                  onBack: () {},
                ),
              };
              for (final entry in pages.entries) {
                await tester.pumpWidget(const SizedBox.shrink());
                await mountReview(
                  tester,
                  entry.value,
                  language: language,
                  size: size,
                  scale: scale,
                  brightness: brightness,
                );
                String text(String key) =>
                    opsText(tester.element(find.byType(Form).first), key);
                if (entry.key == 'invoice') {
                  await press(tester, text('create'));
                }
                if (entry.key == 'booking') {
                  await press(
                    tester,
                    bookingText(tester.element(find.byType(Form).first), 'newBooking'),
                  );
                }
                if (entry.key == 'invoice') {
                  await enter(tester, 'ops-end', '2026-11-01');
                  await enter(
                    tester,
                    'ops-reason',
                    'Long invoice reason / Lý do thu tiền theo hợp đồng đã thỏa thuận',
                  );
                }
                if (entry.key == 'booking') {
                  await enter(
                    tester,
                    'ops-guest',
                    'Nguyễn Văn Khách — gia đình với tên rất dài Riverside',
                  );
                  await enter(tester, 'ops-startLocal', '2026-10-01 09:00');
                  await enter(tester, 'ops-endLocal', '2026-10-01 11:00');
                }
                FocusManager.instance.primaryFocus?.unfocus();
                await tester.pumpAndSettle();
                final target = find.byType(OutlinedButton).last;
                await tester.ensureVisible(target);
                await tester.pumpAndSettle();
                expect(
                  target.hitTestable(),
                  findsOneWidget,
                  reason: '${entry.key} $language $size $scale $brightness',
                );
                expect(tester.takeException(), isNull);
                if (const bool.fromEnvironment('OPS_GOLDENS')) {
                  await expectLater(
                    find.byKey(const ValueKey('capture')),
                    matchesGoldenFile(
                      '../.dart_tool/ops-${entry.key}-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                    ),
                  );
                }
              }
            }
          }
        }
      }
    },
  );
}
