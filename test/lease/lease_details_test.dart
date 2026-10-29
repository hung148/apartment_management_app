// B3 (2026-10-01): the long-stay form takes co-tenants, papers, payment
// period and deposit in one go.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'tenant_lease_test.dart' show store, page, room, fill;
import '../team/team_review_test.dart' show mountReview;
import '../property/room_rates_test.dart' show press, reveal;
import '../booking/room_booking_settings_test.dart' show enter;

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// "Thu tiền mỗi" is a dropdown (2026-10-26, was chips).
Future<void> pickPeriod(WidgetTester tester, int months) async {
  await tapKey(tester, 'lease-period');
  await tester.tap(find.text(months == 1 ? '1 month' : '$months months').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a lease with a co-tenant, tạm trú, 3-month period and deposit', (
    tester,
  ) async {
    final s = store();
    await mountReview(tester, page(s.service));
    await room(tester, 'room-102');
    await fill(tester);
    await enter(tester, 'lease-idNumber', '079200001111');
    await tapKey(tester, 'lease-residence');
    await tapKey(tester, 'lease-add-co');
    await enter(tester, 'lease-co-0-name', 'Pham Thi Dung');
    await enter(tester, 'lease-co-0-id', '079200002222');
    await pickPeriod(tester, 3);
    await enter(tester, 'lease-deposit', '1500000');
    await press(tester, 'Create tenant and lease');
    final main = s.tenants.firstWhere(
      (t) =>
          t['fullName'] == 'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông',
    );
    expect(main['nationalId'], '079200001111');
    expect(main['residenceRegistered'], true);
    expect(main['paymentPeriodMonths'], 3);
    // No own due day any more: due on the move-in day.
    expect(main['paymentDueDay'], isNull);
    expect(main['deposit'], 1500000);
    expect(main['depositMethod'], 'cash');
    final co = s.tenants.firstWhere((t) => t['fullName'] == 'Pham Thi Dung');
    expect(co['mainTenantId'], main['id']);
    expect(co['nationalId'], '079200002222');
  });

  // 2026-10-26 (Tom): the "different due day" switch is gone; the period is
  // a dropdown next to the rent.
  testWidgets('no due-day switch; the period is a dropdown', (
    tester,
  ) async {
    final s = store();
    await mountReview(tester, page(s.service));
    await room(tester, 'room-102');
    await fill(tester);
    expect(find.byKey(const ValueKey('lease-own-due-day')), findsNothing);
    expect(find.byKey(const ValueKey('lease-dueDay')), findsNothing);
    expect(find.byKey(const ValueKey('lease-due-same')), findsNothing);
    await pickPeriod(tester, 6);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byKey(const ValueKey('lease-period')),
          )
          .initialValue,
      6,
    );
  });

  // 2026-10-04 (Tom): end date required. 2026-10-26 (Tom): no "Thanh toán"
  // section any more: every kỳ is rent × months (+ phụ thu), changed later in
  // the lease page's payment table.
  testWidgets('end date is required; the form has no payment section', (
    tester,
  ) async {
    final s = store();
    await mountReview(tester, page(s.service));
    await room(tester, 'room-102');
    await fill(tester);
    await enter(tester, 'lease-end', '');
    final before = s.tenants.length;
    await press(tester, 'Create tenant and lease');
    expect(s.tenants.length, before, reason: 'no end date, no lease');
    // An end date on or before move-in is refused too.
    await enter(tester, 'lease-end', '2026-09-27');
    await press(tester, 'Create tenant and lease');
    expect(s.tenants.length, before);
    await enter(tester, 'lease-end', '2027-09-27');
    expect(find.byKey(const ValueKey('lease-dueDay')), findsNothing);
    expect(find.byKey(const ValueKey('lease-payment')), findsNothing);
    expect(find.byKey(const ValueKey('lease-periodAmount')), findsNothing);
    expect(find.byKey(const ValueKey('lease-periodReason')), findsNothing);
    expect(find.textContaining('Calculated:'), findsNothing);
    await pickPeriod(tester, 3);
    await press(tester, 'Create tenant and lease');
    final main = s.tenants.firstWhere(
      (t) =>
          t['fullName'] == 'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông',
    );
    expect(main['contractEndLocalDate'], '2027-09-27');
    expect(main['paymentDueDay'], isNull);
    expect(main['periodRentMinor'], 4500000);
    expect(main['periodRentOverride'], isNull);
  });
}
