// 2026-10-04 (Tom): the lease page has two buttons at the end (period invoice,
// move out); the short changes open as small dialogs from their sections.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_contacts_screen.dart';
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show reveal;
import 'room_booking_settings_test.dart' show enter;

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

TeamPreviewStore _store() {
  final s = TeamPreviewStore()
    ..buildings.first['timeZone'] = 'Asia/Ho_Chi_Minh';
  s.tenants.first
    ..['contractEndLocalDate'] = '2027-09-01'
    // As the server says for someone who may bill and settle.
    ..['canBill'] = true
    ..['canSettle'] = true;
  s.tenants.add({
    'id': 'tenant-co',
    'buildingId': 'riverside',
    'roomId': 'room-101',
    'fullName': 'Le Van Chinh',
    'phoneNumber': '',
    'status': 'active',
    'isMainTenant': false,
    'mainTenantId': 'tenant-anh',
    'moveInLocalDate': '2026-09-05',
    'revision': '1:0',
  });
  return s;
}

Widget _page(TeamPreviewStore s) => TenantContactsScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  service: s.service,
  onBack: () {},
);

void main() {
  testWidgets('no row of buttons: two steps at the end, changes in sections', (
    tester,
  ) async {
    final s = _store();
    await mountReview(tester, _page(s));
    await tapKey(tester, 'tenant-contact-tenant-anh');
    for (final gone in [
      'Lease and move-out',
      'Rent schedule',
      'Rent-change history',
      'Add roommate',
      'Move out and settle',
    ]) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.text('Period invoice'), findsOneWidget);
    expect(find.text('Move out'), findsOneWidget);
    // The people living with the tenant are listed in the lease.
    expect(
      find.byKey(const ValueKey('lease-roommate-tenant-co')),
      findsOneWidget,
    );
    expect(find.text('Moved in 2026-09-05'), findsOneWidget);

    // End date: "Edit" opens one date and a reason.
    await tapKey(tester, 'lease-end-edit-tenant-anh');
    await enter(tester, 'lease-change-date', '2026-08-01');
    await enter(tester, 'lease-change-reason', 'Extended');
    await tapKey(tester, 'lease-change-save');
    expect(
      find.text('The end date must be after the move-in day.'),
      findsOneWidget,
    );
    await enter(tester, 'lease-change-date', '2028-03-01');
    await tapKey(tester, 'lease-change-save');
    expect(s.tenants.first['contractEndLocalDate'], '2028-03-01');
    expect(find.text('2028-03-01'), findsOneWidget);

    // Moving the lease: in the "…" menu; refused while someone lives with them.
    await tapKey(tester, 'lease-more-tenant-anh');
    await tapKey(tester, 'lease-move-room');
    await tapKey(tester, 'lease-change-room');
    await tester.tap(find.text('Room 102').last);
    await tester.pumpAndSettle();
    await enter(tester, 'lease-change-reason', 'Bigger room');
    await tapKey(tester, 'lease-change-save');
    expect(
      find.text(
        'The people living with this tenant must move out or move first.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(s.tenants.first['roomId'], 'room-101');

    // The roommate's page: move out with a date that already happened.
    await tapKey(tester, 'lease-roommate-tenant-co');
    expect(
      find.text('Lives with Nguyễn Thị Minh Anh — gia đình Riverside'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('roommate-move-tenant-co')),
      findsOneWidget,
    );
    await tapKey(tester, 'roommate-out-tenant-co');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('lease-change-date')),
          )
          .controller!
          .text,
      '2026-09-27',
      reason: 'today by default',
    );
    await enter(tester, 'lease-change-date', '2026-10-05');
    await enter(tester, 'lease-change-reason', 'Left');
    await tapKey(tester, 'lease-change-save');
    expect(
      find.text(
        'Use the day it happened: today or earlier, after the move-in day.',
      ),
      findsOneWidget,
    );
    await enter(tester, 'lease-change-date', '2026-09-27');
    await tapKey(tester, 'lease-change-save');
    final co = s.tenants.firstWhere((t) => t['id'] == 'tenant-co');
    expect(co['status'], 'moveOut');
    expect(find.byKey(const ValueKey('roommate-out-tenant-co')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // 2026-10-04 (Tom): the amount per period follows rent changes.
  testWidgets('the amount per period: special until the first rent change', (
    tester,
  ) async {
    final s = _store();
    s.tenants.first
      ..['paymentPeriodMonths'] = 3
      ..['periodRentMinor'] = 4000000
      ..['rentSchedule'] = [
        {'effectiveDate': '2026-10-01', 'amountMinor': 2000000},
      ];
    await mountReview(tester, _page(s));
    await tapKey(tester, 'tenant-contact-tenant-anh');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lease-per-period')),
        matching: find.text('4,000,000 VND · until 2026-10-01'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'From 2026-10-01 · 2,000,000 VND · 6,000,000 VND per period · planned',
      ),
      findsOneWidget,
    );
    // Once a change is in effect, it is rent × months.
    await tester.pumpWidget(const SizedBox.shrink());
    (s.tenants.first['rentSchedule'] as List).first['effectiveDate'] =
        '2026-09-20';
    await mountReview(tester, _page(s));
    await tapKey(tester, 'tenant-contact-tenant-anh');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('lease-per-period')),
        matching: find.text('6,000,000 VND'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
