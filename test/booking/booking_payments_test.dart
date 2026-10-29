// Short-stay payment list (2026-10-24, Tom): the Thanh toán section shows the
// payments made so far and "Thêm lần thanh toán". A new booking keeps them in
// the form and saves them with the booking; a saved booking records each one
// at once. More than is owed shows the change. Refunds are a type. Changing a
// recorded payment needs "Sửa lần thanh toán" (owner/administrator here).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/booking_workspace_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import '../lease/tenant_lease_test.dart' show store;
import '../team/team_review_test.dart' show mountReview;
import '../property/room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;

Widget booking(TeamService service, {String? recordId}) =>
    BookingWorkspaceScreen(
      organizationId: 'preview',
      buildingId: 'riverside',
      accountId: 'owner',
      service: service,
      initialRoomId: recordId == null ? 'room-102' : null,
      initialRecordId: recordId,
      startNew: recordId == null,
      initialStart: recordId == null ? '2026-10-10 14:00' : null,
      initialEnd: recordId == null ? '2026-10-12 12:00' : null,
      onClose: () {},
    );

Finder key(String k) => find.byKey(ValueKey(k));
Future<void> calculate(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

/// Opens "Thêm lần thanh toán" (or a row's "Sửa").
Future<void> openDialog(WidgetTester tester, String button) async {
  await reveal(tester, key(button));
  await tester.tap(key(button));
  await tester.pumpAndSettle();
  expect(key('booking-payment-dialog'), findsOneWidget);
}

Future<void> choose(WidgetTester tester, String dropdown, String item) async {
  await tester.ensureVisible(key(dropdown));
  await tester.tap(key(dropdown));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

Future<void> fillDialog(
  WidgetTester tester, {
  String? kind,
  required String amount,
  String? method,
  String? note,
  String? date,
}) async {
  if (date != null) await tester.enterText(key('payment-date'), date);
  if (kind != null) await choose(tester, 'payment-kind', kind);
  await tester.enterText(key('payment-amount'), amount);
  await tester.pumpAndSettle();
  if (method != null) await choose(tester, 'payment-method', method);
  if (note != null) await tester.enterText(key('payment-note'), note);
  await tester.pumpAndSettle();
}

Future<void> saveDialog(WidgetTester tester) async {
  await tester.ensureVisible(key('payment-save'));
  await tester.tap(key('payment-save'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the old deposit, payment and agreed-total fields are gone', (
    tester,
  ) async {
    final s = store();
    s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
    await mountReview(tester, booking(s.service));
    await calculate(tester);
    for (final k in [
      'ops-depositAmount',
      'ops-depositDate',
      'ops-depositNote',
      'booking-deposit-paid',
      'ops-payAmount',
      'ops-payDate',
      'ops-payNote',
      'ops-agreedPrice',
    ]) {
      expect(key(k), findsNothing, reason: k);
    }
    expect(key('booking-add-payment'), findsOneWidget);
    expect(find.text('No payments yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a new booking keeps payments in the form, shows change and saves them with it',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(tester, booking(s.service));
      await calculate(tester);
      await enter(tester, 'ops-guest', 'Nguyễn Minh Anh');
      await calculate(tester);
      // Total 1,000,000. Deposit 300,000 in cash.
      await openDialog(tester, 'booking-add-payment');
      expect(find.text('Payment 1'), findsOneWidget);
      await fillDialog(
        tester,
        kind: 'Deposit',
        amount: '300000',
        note: 'Cọc qua Zalo',
      );
      await saveDialog(tester);
      expect(key('booking-payment-row-0'), findsOneWidget);
      expect(s.operationalBookings, isEmpty, reason: 'not saved yet');
      // The guest hands over 1,000,000 for the 700,000 still owed.
      await openDialog(tester, 'booking-add-payment');
      expect(find.text('Payment 2'), findsOneWidget);
      await fillDialog(tester, amount: '1000000', method: 'Bank transfer');
      // Worked out while typing: nothing left, 300,000 back.
      expect(
        tester.widget<Text>(key('payment-left')).data,
        'Still owed: 0 VND · Change: 300,000 VND',
      );
      // Transfer shows the receiving account, not the person.
      expect(key('payment-account'), findsOneWidget);
      expect(key('payment-received-by'), findsNothing);
      await saveDialog(tester);
      expect(find.textContaining('Change: 300,000 VND'), findsOneWidget);
      // "Còn lại" under each payment.
      expect(
        tester.widget<Text>(find.descendant(of: key('booking-payment-left-0'), matching: find.byType(Text))).data,
        'Still owed: 700,000 VND',
      );
      expect(
        tester.widget<Text>(find.descendant(of: key('booking-payment-left-1'), matching: find.byType(Text))).data,
        'Still owed: 0 VND',
      );
      await calculate(tester);
      // The totals card lists each payment.
      for (final line in ['1 · Deposit', '2 · Room charge']) {
        expect(
          find.descendant(of: key('booking-quote'), matching: find.text(line)),
          findsOneWidget,
          reason: line,
        );
      }
      expect(
        find.descendant(
          of: key('booking-quote-remaining'),
          matching: find.text('0 VND'),
        ),
        findsOneWidget,
      );
      await press(tester, 'Confirm and save');
      final saved = s.operationalBookings.single;
      expect(saved['paidAmount'], 1000000);
      final receipts = (saved['previewReceipts'] as List).cast<Map>();
      expect(receipts.map((r) => [r['kind'], r['amountMinor'], r['changeMinor']]), [
        ['deposit', 300000, 0],
        ['room', 700000, 300000],
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a draft payment can be edited or removed before saving', (
    tester,
  ) async {
    final s = store();
    s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
    await mountReview(tester, booking(s.service));
    await calculate(tester);
    await enter(tester, 'ops-guest', 'Guest');
    await openDialog(tester, 'booking-add-payment');
    await fillDialog(tester, amount: '200000');
    await saveDialog(tester);
    await openDialog(tester, 'booking-payment-edit-0');
    expect(find.text('Edit payment 1'), findsOneWidget);
    await tester.enterText(key('payment-amount'), '250000');
    await saveDialog(tester);
    expect(find.textContaining('250,000 VND'), findsWidgets);
    await reveal(tester, key('booking-payment-remove-0'));
    await tester.tap(key('booking-payment-remove-0'));
    await tester.pumpAndSettle();
    expect(key('booking-payment-row-0'), findsNothing);
    await calculate(tester);
    await press(tester, 'Confirm and save');
    expect(s.operationalBookings.single['paidAmount'], 0);
  });

  testWidgets('a date after today and an empty amount are refused in the dialog', (
    tester,
  ) async {
    final s = store();
    s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
    await mountReview(tester, booking(s.service));
    await calculate(tester);
    await openDialog(tester, 'booking-add-payment');
    await tester.enterText(key('payment-date'), '2999-01-01');
    await saveDialog(tester);
    expect(find.text('Choose a day up to today.'), findsOneWidget);
    expect(find.text('Enter an amount.'), findsOneWidget);
    expect(key('booking-payment-dialog'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(key('booking-payment-row-0'), findsNothing);
  });

  testWidgets(
    'Thanh toán bằng is typed or picked; a new name asks whether to keep it',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(tester, booking(s.service));
      await calculate(tester);
      // A new name, kept for everyone.
      await openDialog(tester, 'booking-add-payment');
      await tester.enterText(key('payment-amount'), '100000');
      await tester.enterText(key('payment-method'), 'Momo');
      await tester.pumpAndSettle();
      // Not cash: the receiving account is asked instead of the person.
      expect(key('payment-account'), findsOneWidget);
      await saveDialog(tester);
      expect(key('payment-method-ask'), findsOneWidget);
      await tester.tap(key('payment-method-keep'));
      await tester.pumpAndSettle();
      expect(s.previewPaymentMethods.single['label'], 'Momo');
      expect(key('booking-payment-row-0'), findsOneWidget);
      expect(find.textContaining('Momo'), findsWidgets);
      // A name typed once is not kept in the list.
      await openDialog(tester, 'booking-add-payment');
      await tester.enterText(key('payment-amount'), '50000');
      await tester.enterText(key('payment-method'), 'Thẻ quà tặng');
      await saveDialog(tester);
      await tester.tap(key('payment-method-once'));
      await tester.pumpAndSettle();
      expect(s.previewPaymentMethods, hasLength(1));
      expect(find.textContaining('Thẻ quà tặng'), findsWidgets);
      // Next time the kept name is offered while typing.
      await openDialog(tester, 'booking-add-payment');
      await tester.enterText(key('payment-method'), 'mo');
      await tester.pumpAndSettle();
      expect(key('payment-method-option-Momo'), findsOneWidget);
      await tester.tap(key('payment-method-option-Momo'));
      await tester.pumpAndSettle();
      await tester.enterText(key('payment-amount'), '10000');
      await saveDialog(tester);
      expect(key('payment-method-ask'), findsNothing);
      expect(key('booking-payment-row-2'), findsOneWidget);
    },
  );

  testWidgets('a recorded payment can be deleted after asking', (tester) async {
    final s = store();
    s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
    await mountReview(tester, booking(s.service));
    await calculate(tester);
    await enter(tester, 'ops-guest', 'Guest');
    await openDialog(tester, 'booking-add-payment');
    await fillDialog(tester, amount: '400000');
    await saveDialog(tester);
    await calculate(tester);
    await press(tester, 'Confirm and save');
    await calculate(tester);
    expect(s.operationalBookings.single['paidAmount'], 400000);
    await openDialog(tester, 'booking-payment-edit-0');
    await tester.tap(key('payment-delete'));
    await tester.pumpAndSettle();
    expect(key('payment-delete-ask'), findsOneWidget);
    // Closing the question keeps the payment.
    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    expect(s.operationalBookings.single['paidAmount'], 400000);
    await tester.tap(key('payment-delete'));
    await tester.pumpAndSettle();
    await tester.tap(key('payment-delete-confirm'));
    await tester.pumpAndSettle();
    expect(s.operationalBookings.single['paidAmount'], 0);
    expect(key('booking-payment-row-0'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the still-owed sum follows the amount while typing', (
    tester,
  ) async {
    final s = store();
    s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
    await mountReview(tester, booking(s.service));
    await calculate(tester);
    await openDialog(tester, 'booking-add-payment');
    String left() => tester.widget<Text>(key('payment-left')).data!;
    expect(left(), 'Still owed: 1,000,000 VND');
    await tester.enterText(key('payment-amount'), '250000');
    await tester.pump();
    expect(left(), 'Still owed: 750,000 VND');
    await tester.enterText(key('payment-amount'), '2500000');
    await tester.pump();
    expect(left(), 'Still owed: 0 VND · Change: 1,500,000 VND');
  });

  testWidgets(
    'a saved booking records each payment at once; a refund is a type',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(tester, booking(s.service));
      await calculate(tester);
      await enter(tester, 'ops-guest', 'Guest');
      await calculate(tester);
      await press(tester, 'Confirm and save');
      await calculate(tester);
      await openDialog(tester, 'booking-add-payment');
      await fillDialog(tester, amount: '400000');
      await saveDialog(tester);
      expect(s.operationalBookings.single['paidAmount'], 400000);
      expect(key('booking-payment-row-0'), findsOneWidget);
      await openDialog(tester, 'booking-add-payment');
      await choose(tester, 'payment-kind', 'Room refund');
      await tester.enterText(key('payment-amount'), '500000');
      await saveDialog(tester);
      expect(find.textContaining('More than was received'), findsOneWidget);
      await tester.enterText(key('payment-amount'), '100000');
      await saveDialog(tester);
      expect(s.operationalBookings.single['paidAmount'], 300000);
      expect(key('booking-payment-row-1'), findsOneWidget);
      // The old refund section is gone.
      expect(key('booking-refund-rent-section'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the deposit is given back only on a cancelled booking; the sum is spelled out',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(tester, booking(s.service));
      await calculate(tester);
      await enter(tester, 'ops-guest', 'Guest');
      await calculate(tester);
      await openDialog(tester, 'booking-add-payment');
      await fillDialog(tester, kind: 'Deposit', amount: '200000');
      await saveDialog(tester);
      await calculate(tester);
      await press(tester, 'Confirm and save');
      await calculate(tester);
      // Active booking: no refund of the deposit is offered.
      await openDialog(tester, 'booking-add-payment');
      await tester.enterText(key('payment-amount'), '100000');
      await tester.pumpAndSettle();
      // Paid 200,000 so far; 100,000 now leaves 700,000.
      expect(
        tester.widget<Text>(key('payment-left')).data,
        'Still owed: 700,000 VND',
      );
      await tester.tap(key('payment-kind'));
      await tester.pumpAndSettle();
      expect(find.text('Deposit refund'), findsNothing);
      await tester.tap(find.text('Room charge').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      // Cancelled: the deposit can be given back.
      final row = s.operationalBookings.single;
      row['status'] = 'cancelled';
      await tester.pumpWidget(const SizedBox.shrink());
      await mountReview(tester, booking(s.service, recordId: row['id'] as String));
      await calculate(tester);
      await openDialog(tester, 'booking-add-payment');
      expect(find.text('Deposit refund'), findsWidgets);
      await tester.enterText(key('payment-amount'), '200000');
      await saveDialog(tester);
      expect(s.operationalBookings.single['paidAmount'], 0);
    },
  );

  testWidgets('editing a recorded payment needs "Sửa lần thanh toán"', (
    tester,
  ) async {
    final s = store();
    s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
    await mountReview(tester, booking(s.service));
    await calculate(tester);
    await enter(tester, 'ops-guest', 'Guest');
    await openDialog(tester, 'booking-add-payment');
    await fillDialog(tester, amount: '400000');
    await saveDialog(tester);
    await calculate(tester);
    await press(tester, 'Confirm and save');
    await calculate(tester);
    await openDialog(tester, 'booking-payment-edit-0');
    await tester.enterText(key('payment-amount'), '350000');
    await saveDialog(tester);
    expect(s.operationalBookings.single['paidAmount'], 350000);
    // A receptionist sees the list but no "Sửa".
    s.workspaceRole = 'receptionist';
    final id = s.operationalBookings.single['id'] as String;
    // A fresh page, not the owner's form updated in place.
    await tester.pumpWidget(const SizedBox.shrink());
    await mountReview(tester, booking(s.service, recordId: id));
    await calculate(tester);
    expect(key('booking-payment-row-0'), findsOneWidget);
    expect(key('booking-payment-edit-0'), findsNothing);
    expect(key('booking-add-payment'), findsOneWidget);
  });

  for (final (language, size, scale) in [
    ('en', const Size(1440, 900), 1.0),
    ('vi', const Size(320, 740), 2.0),
    ('vi', const Size(812, 375), 1.3),
  ]) {
    testWidgets('payment dialog fits: $language $size ×$scale', (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(
        tester,
        booking(s.service),
        language: language,
        size: size,
        scale: scale,
      );
      await calculate(tester);
      await openDialog(tester, 'booking-add-payment');
      await tester.enterText(key('payment-amount'), '1500000');
      await tester.enterText(
        key('payment-note'),
        'Khách chuyển khoản trước một phần, phần còn lại trả tiền mặt khi nhận phòng',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(key('payment-save'));
      expect(key('payment-save').hitTestable(), findsOneWidget);
      await saveDialog(tester);
      expect(tester.takeException(), isNull);
      await reveal(tester, key('booking-payment-row-0'));
      expect(tester.takeException(), isNull);
    });
  }
}
