// B3 (2026-10-01): the long-stay form takes co-tenants, papers, payment
// period and deposit in one go.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'tenant_lease_test.dart' show store, page, room, fill;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await reveal(tester, finder);
  await tester.tap(finder);
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
    await tapKey(tester, 'lease-period-3');
    await tapKey(tester, 'lease-own-due-day');
    await enter(tester, 'lease-dueDay', '5');
    await enter(tester, 'lease-deposit', '1500000');
    await press(tester, 'Create tenant and lease');
    final main = s.tenants.firstWhere(
      (t) =>
          t['fullName'] == 'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông',
    );
    expect(main['nationalId'], '079200001111');
    expect(main['residenceRegistered'], true);
    expect(main['paymentPeriodMonths'], 3);
    expect(main['paymentDueDay'], 5);
    expect(main['deposit'], 1500000);
    expect(main['depositMethod'], 'cash');
    final co = s.tenants.firstWhere((t) => t['fullName'] == 'Pham Thi Dung');
    expect(co['mainTenantId'], main['id']);
    expect(co['nationalId'], '079200002222');
  });

  testWidgets('a wrong due day is caught in the form', (tester) async {
    final s = store();
    await mountReview(tester, page(s.service));
    await room(tester, 'room-102');
    await fill(tester);
    final before = s.tenants.length;
    await tapKey(tester, 'lease-own-due-day');
    await enter(tester, 'lease-dueDay', '40');
    await press(tester, 'Create tenant and lease');
    expect(s.tenants.length, before);
    expect(find.text('Enter a day from 1 to 31.'), findsOneWidget);
  });

  // 2026-10-04 (Tom): end date required; due day and amount per period behind
  // switches (off = move-in day, rent × months).
  testWidgets('end date is required; due day and amount are switches', (
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
    // Off: the usual day and amount are explained, no fields.
    expect(find.byKey(const ValueKey('lease-dueDay')), findsNothing);
    expect(find.byKey(const ValueKey('lease-periodAmount')), findsNothing);
    expect(
      find.text('Due on day 27 of each month (the move-in day).'),
      findsOneWidget,
    );
    await tapKey(tester, 'lease-period-3');
    expect(find.textContaining('Each period: 4,500,000 VND'), findsOneWidget);
    // On: the amount starts from rent × months and can be changed.
    await tapKey(tester, 'lease-own-amount');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('lease-periodAmount')),
          )
          .controller!
          .text,
      '4,500,000',
    );
    await enter(tester, 'lease-periodAmount', '4000000');
    await press(tester, 'Create tenant and lease');
    final main = s.tenants.firstWhere(
      (t) =>
          t['fullName'] == 'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông',
    );
    expect(main['contractEndLocalDate'], '2027-09-27');
    expect(main['paymentDueDay'], isNull);
    expect(main['periodRentMinor'], 4000000);
  });
}
