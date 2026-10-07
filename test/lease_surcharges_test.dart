// 2026-10-04: long-stay surcharges (phụ thu), the electricity price typed with
// the lease, the stay status and the ended-contract reminder.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/period_invoice_form.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'tenant_lease_test.dart' as lease show store, page, room, fill;
import 'tenant_contacts_test.dart' as contacts show page, open;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;
import 'account_entry_test.dart' as fixtures;

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the lease form sends surcharges and the electricity price', (
    tester,
  ) async {
    final s = lease.store();
    Map<String, dynamic>? sent;
    final service = TeamService(
      transport: (name, d) {
        if (name == 'tenantLeases' && d['action'] == 'create')
          sent = Map<String, dynamic>.from(d);
        return s.call(name, d);
      },
    );
    await mountReview(tester, lease.page(service));
    await lease.room(tester, 'room-102');
    await lease.fill(tester);
    expect(find.textContaining('Not part of the total'), findsOneWidget);
    await tapKey(tester, 'lease-add-surcharge');
    await enter(tester, 'lease-surcharge-0-label', 'Vệ sinh');
    await enter(tester, 'lease-surcharge-0-amount', '50000');
    await tapKey(tester, 'lease-surcharge-0-person');
    await tapKey(tester, 'lease-surcharge-0-once');
    await enter(tester, 'lease-electricity', '3500');
    await press(tester, 'Create tenant and lease');
    expect(sent?['electricityPriceMinor'], 3500);
    expect(sent?['surcharges'], [
      {
        'label': 'Vệ sinh',
        'amountMinor': 50000,
        'basis': 'person',
        'frequency': 'once',
      },
    ]);
    final main = s.tenants.firstWhere(
      (t) =>
          t['fullName'] == 'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông',
    );
    expect((main['surcharges'] as List).single['label'], 'Vệ sinh');
  });

  testWidgets('an empty surcharge row is caught in the form', (tester) async {
    final s = lease.store();
    await mountReview(tester, lease.page(s.service));
    await lease.room(tester, 'room-102');
    await lease.fill(tester);
    final before = s.tenants.length;
    await tapKey(tester, 'lease-add-surcharge');
    await press(tester, 'Create tenant and lease');
    expect(s.tenants.length, before);
    expect(find.text('Enter an amount above 0.'), findsOneWidget);
  });

  testWidgets(
    'the tenant page shows the stay status, surcharges and the ended contract',
    (tester) async {
      final s = lease.store();
      s.tenants.first.addAll({
        'contractEnded': true,
        'surcharges': [
          {
            'id': 'park',
            'label': 'Gửi xe',
            'amountMinor': 100000,
            'basis': 'room',
            'frequency': 'period',
          },
        ],
      });
      await mountReview(tester, contacts.page(s.service));
      await contacts.open(tester, 'tenant-anh');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tenant-stay-status')),
          matching: find.text('Staying'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('lease-contract-ended')),
        findsOneWidget,
      );
      expect(
        find.text('Gửi xe · 100,000 VND · Per room · Every period'),
        findsOneWidget,
      );
      await tapKey(tester, 'lease-surcharges-edit');
      await enter(tester, 'lease-surcharge-0-amount', '120000');
      await tapKey(tester, 'lease-surcharges-save');
      final saved = (s.tenants.first['surcharges'] as List).single as Map;
      expect(saved['id'], 'park');
      expect(saved['amountMinor'], 120000);
      expect(
        find.text('Gửi xe · 120,000 VND · Per room · Every period'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'a period invoice ticks open surcharges, keeps billed ones off, and sends the amount',
    (t) async {
      Map<String, dynamic>? quoted;
      final service = TeamService(
        transport: (name, d) async {
          if (d['action'] == 'periodPreview') {
            return {
              'record': {
                'tenantName': 'Le Van Chinh',
                'currency': 'VND',
                'roomId': 'r1',
                'today': '2026-10-02',
                'periodMonths': 1,
                'dueDay': null,
                'periodRentMinor': 5000000,
                'monthlyRentMinor': 5000000,
                'finished': false,
                'suggestion': {
                  'startDate': '2026-10-02',
                  'endDate': '2026-11-02',
                  'dueDate': '2026-10-05',
                },
                'fees': [],
                'readings': [],
                'surcharges': [
                  {
                    'id': 'park',
                    'label': 'Gửi xe',
                    'amountMinor': 100000,
                    'basis': 'room',
                    'frequency': 'period',
                    'count': 1,
                    'billed': false,
                  },
                  {
                    'id': 'clean',
                    'label': 'Vệ sinh',
                    'amountMinor': 50000,
                    'basis': 'person',
                    'frequency': 'once',
                    'count': 2,
                    'billed': true,
                  },
                ],
                'canPrice': true,
                'canBackdate': true,
              },
            };
          }
          quoted = Map<String, dynamic>.from(d);
          return {
            'record': {
              'totalMinor': 5120000,
              'currency': 'VND',
              'quoteRevision': 'q1',
              'lines': [
                {
                  'type': 'rent',
                  'amountMinor': 5000000,
                  'startDate': '2026-10-02',
                  'endDate': '2026-11-02',
                  'basis': 'period',
                  'months': 1,
                },
                {
                  'type': 'surcharge',
                  'surchargeId': 'park',
                  'label': 'Gửi xe',
                  'basis': 'room',
                  'frequency': 'period',
                  'unitMinor': 120000,
                  'count': 1,
                  'amountMinor': 120000,
                },
              ],
            },
          };
        },
      );
      await fixtures.mount(
        t,
        Scaffold(
          body: PeriodInvoiceForm(
            service: service,
            organizationId: 'o',
            buildingId: 'b',
            tenantId: 't',
            backLabel: 'Back',
            onDone: () {},
            onCancel: () {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('already billed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('period-surcharge-clean-amount')),
        findsNothing,
      );
      final amount = find.byKey(const ValueKey('period-surcharge-park-amount'));
      await t.ensureVisible(amount);
      await t.enterText(amount, '120000');
      final reason = find.byKey(const ValueKey('period-reason'));
      await t.ensureVisible(reason);
      await t.enterText(reason, 'Kỳ 1');
      final review = find.byKey(const ValueKey('period-review'));
      await t.ensureVisible(review);
      await t.tap(review);
      await t.pumpAndSettle();
      expect(quoted?['surcharges'], [
        {'id': 'park', 'amountMinor': 120000},
      ]);
      expect(find.text('Surcharge: Gửi xe'), findsWidgets);
      expect(find.text('120,000 VND'), findsOneWidget);
    },
  );
}
