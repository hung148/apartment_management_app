// Bảng thanh toán theo kỳ (PAYMENT_SCHEDULE.md, Tom 2026-10-26): the lease
// page's payment table — table on wide screens, cards on phones, tap a cell
// to change it, split / join, locked kỳ, the invoice links.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/app_functions.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/lease_schedule_section.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_contacts_screen.dart';
import '../team/team_review_test.dart' show mountReview;
import '../property/room_rates_test.dart' show reveal;
import '../booking/room_booking_settings_test.dart' show enter;

const desktop = Size(1280, 900), phone = Size(375, 812);

TeamPreviewStore _store() {
  final s = TeamPreviewStore()
    ..buildings.first['timeZone'] = 'Asia/Ho_Chi_Minh';
  s.tenants.first
    ..['moveInLocalDate'] = '2026-09-01'
    // The day the tenant leaves: six whole months.
    ..['contractEndLocalDate'] = '2027-03-01'
    ..['monthlyRentMinor'] = 5000000
    ..['paymentPeriodMonths'] = 1
    ..['surcharges'] = [
      {
        'id': 's1',
        'label': 'Rác',
        'amountMinor': 100000,
        'basis': 'room',
        'frequency': 'period',
      },
    ]
    ..['canBill'] = true;
  return s;
}

class _Opened {
  String? invoice;
  List<String>? period;
}

Widget _section(TeamPreviewStore s, _Opened opened) => SingleChildScrollView(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: LeaseScheduleSection(
      service: s.service,
      organizationId: 'preview',
      buildingId: 'riverside',
      tenantId: 'tenant-anh',
      onOpenInvoice: (id) => opened.invoice = id,
      onNewInvoice: (a, b, c) => opened.period = [a, b, c],
    ),
  ),
);

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Can this cell be tapped? (The tap target carries the cell's key.)
bool _tappable(WidgetTester tester, String key) =>
    tester.widget(find.byKey(ValueKey(key))) is InkWell;

int _rows(WidgetTester tester) => find
    .byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('schedule-row-'),
    )
    .evaluate()
    .length;

void main() {
  testWidgets('wide screens: one table row per kỳ, rent + phụ thu, nothing paid', (
    tester,
  ) async {
    await mountReview(tester, _section(_store(), _Opened()), size: desktop);
    expect(find.byKey(const ValueKey('schedule-table')), findsOneWidget);
    expect(_rows(tester), 6);
    expect(find.text('Period 1'), findsOneWidget);
    expect(find.text('01/09 – 30/09'), findsOneWidget);
    expect(find.text('01/02 – 28/02'), findsOneWidget);
    expect(find.text('01/09/2026'), findsOneWidget, reason: 'Hạn thu = first day');
    expect(find.text('5,100,000 VND'), findsNWidgets(12), reason: 'total + left');
    expect(find.text('0 VND'), findsNWidgets(6));
    expect(find.text('6 periods · 0 invoiced'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a shorter kỳ moves the later ones and adds one at the end', (
    tester,
  ) async {
    await mountReview(tester, _section(_store(), _Opened()), size: desktop);
    await tapKey(tester, 'schedule-dates-k20261001');
    await enter(tester, 'schedule-end', '2026-10-25');
    await tapKey(tester, 'schedule-save');
    expect(_rows(tester), 7);
    expect(find.text('01/10 – 25/10'), findsOneWidget);
    expect(find.text('25 days'), findsOneWidget);
    expect(find.text('26/10 – 25/11'), findsOneWidget);
    expect(find.text('26/02 – 28/02'), findsOneWidget);
  });

  testWidgets('another amount needs a reason; the reason shows under it', (
    tester,
  ) async {
    await mountReview(tester, _section(_store(), _Opened()), size: desktop);
    await tapKey(tester, 'schedule-amount-k20260901');
    await enter(tester, 'schedule-amount', '4600000');
    await tapKey(tester, 'schedule-save');
    expect(find.text('Enter why the amount differs.'), findsOneWidget);
    await enter(tester, 'schedule-reason', 'Giảm tháng đầu');
    await tapKey(tester, 'schedule-save');
    expect(find.text('4,600,000 VND'), findsNWidgets(2));
    expect(find.text('Giảm tháng đầu'), findsOneWidget);
  });

  testWidgets('Hạn thu can be moved inside the kỳ; outside is refused', (
    tester,
  ) async {
    await mountReview(tester, _section(_store(), _Opened()), size: desktop);
    await tapKey(tester, 'schedule-due-k20260901');
    await enter(tester, 'schedule-due', '2026-10-05');
    await tapKey(tester, 'schedule-save');
    expect(find.text('The due date must be inside the period.'), findsOneWidget);
    await enter(tester, 'schedule-due', '2026-09-05');
    await tapKey(tester, 'schedule-save');
    expect(find.text('05/09/2026'), findsOneWidget);
  });

  testWidgets('split a kỳ, then join it back after "Are you sure?"', (
    tester,
  ) async {
    await mountReview(tester, _section(_store(), _Opened()), size: desktop);
    await tapKey(tester, 'schedule-menu-k20260901');
    await tester.tap(find.text('Split period'));
    await tester.pumpAndSettle();
    await enter(tester, 'schedule-split-date', '2026-09-16');
    await tapKey(tester, 'schedule-save');
    expect(_rows(tester), 7);
    expect(find.text('01/09 – 15/09'), findsOneWidget);
    expect(find.text('16/09 – 30/09'), findsOneWidget);
    await tapKey(tester, 'schedule-menu-k20260916');
    await tester.tap(find.text('Join into period 1'));
    await tester.pumpAndSettle();
    expect(find.text('Period 2 becomes part of period 1. Are you sure?'), findsOneWidget);
    await tapKey(tester, 'schedule-merge-confirm');
    expect(_rows(tester), 6);
    expect(find.text('01/09 – 30/09'), findsOneWidget);
  });

  testWidgets('an invoiced kỳ is locked; Chi tiết opens its invoice or a new one', (
    tester,
  ) async {
    final s = _store()..scheduleInvoices['k20260901'] = 'inv-1';
    final opened = _Opened();
    await mountReview(tester, _section(s, opened), size: desktop);
    expect(find.byKey(const ValueKey('schedule-locked-k20260901')), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-menu-k20260901')), findsNothing);
    expect(
      _tappable(tester, 'schedule-dates-k20260901'),
      isFalse,
      reason: 'locked: not tappable',
    );
    expect(_tappable(tester, 'schedule-dates-k20261001'), isTrue);
    expect(find.text('6 periods · 1 invoiced'), findsOneWidget);
    await tapKey(tester, 'schedule-details-k20260901');
    expect(opened.invoice, 'inv-1');
    await tapKey(tester, 'schedule-details-k20261001');
    expect(opened.period, ['2026-10-01', '2026-11-01', '2026-10-01']);
  });

  testWidgets('without "Đổi giá" the amount cannot be tapped', (tester) async {
    final s = _store()
      ..workspaceRole = 'manager'
      ..priceOverride = false;
    await mountReview(tester, _section(s, _Opened()), size: desktop);
    expect(_tappable(tester, 'schedule-amount-k20260901'), isFalse);
    expect(
      _tappable(tester, 'schedule-dates-k20260901'),
      isTrue,
      reason: 'dates still editable',
    );
  });

  testWidgets('no contract end date: the table asks for one', (tester) async {
    final s = _store();
    s.tenants.first['contractEndLocalDate'] = null;
    await mountReview(tester, _section(s, _Opened()), size: desktop);
    expect(find.byKey(const ValueKey('schedule-needs-end')), findsOneWidget);
    expect(_rows(tester), 0);
  });

  testWidgets('phones and large text: cards, nothing cut off', (tester) async {
    for (final language in ['en', 'vi']) {
      for (final (size, scale) in [
        (phone, 1.0),
        (phone, 2.0),
        (desktop, 2.0),
      ]) {
        await mountReview(
          tester,
          _section(_store(), _Opened()),
          size: size,
          scale: scale,
          language: language,
        );
        expect(
          find.byKey(const ValueKey('schedule-cards')),
          findsOneWidget,
          reason: '$language $size $scale',
        );
        expect(tester.takeException(), isNull, reason: '$language $size $scale');
      }
    }
    await mountReview(tester, _section(_store(), _Opened()), size: desktop, language: 'vi');
    expect(find.text('Bảng thanh toán theo kỳ'), findsOneWidget);
    expect(find.text('Kỳ thu / Khoảng thuê'), findsOneWidget);
    expect(find.text('Còn phải thu'), findsOneWidget);
    expect(find.text('1 tháng'), findsNWidgets(6));
  });

  testWidgets('the lease page shows the table under the contract', (tester) async {
    final s = _store();
    await mountReview(
      tester,
      TenantContactsScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        service: s.service,
        onBack: () {},
      ),
      size: desktop,
    );
    await tapKey(tester, 'tenant-contact-tenant-anh');
    final table = find.byKey(const ValueKey('lease-schedule'));
    await reveal(tester, table);
    expect(table, findsOneWidget);
    expect(_rows(tester), 6);
  });

  // Found by room_calendar_test: closing a lease dialog reloaded the calendar
  // although only the table was read. A read is not a change; an edit is.
  test('reading the table is not a change; editing it is', () {
    expect(
      ServerWrites.isRead('tenantLeases', {'action': 'schedule', 'op': 'read'}),
      isTrue,
    );
    for (final op in ['edit', 'split', 'merge']) {
      expect(
        ServerWrites.isRead('tenantLeases', {'action': 'schedule', 'op': op}),
        isFalse,
        reason: op,
      );
    }
  });

  // Tom, 2026-10-26: over the calendar the section is only the count and
  // "Xem bảng"; the whole table opens in its own dialog.
  Widget summary(TeamPreviewStore s, _Opened opened) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: LeaseScheduleSection(
        service: s.service,
        organizationId: 'preview',
        buildingId: 'riverside',
        tenantId: 'tenant-anh',
        summary: true,
        onOpenInvoice: (id) => opened.invoice = id,
        onNewInvoice: (a, b, c) => opened.period = [a, b, c],
      ),
    ),
  );

  testWidgets('over the calendar: a button; the table opens in a dialog', (
    tester,
  ) async {
    for (final size in [desktop, phone]) {
      final opened = _Opened();
      await mountReview(tester, summary(_store(), opened), size: size);
      expect(find.text('6 periods · 0 invoiced'), findsOneWidget);
      expect(_rows(tester), 0, reason: 'no rows on the page');
      await tapKey(tester, 'schedule-open');
      expect(find.byKey(const ValueKey('schedule-dialog')), findsOneWidget);
      expect(_rows(tester), 6, reason: '$size');
      expect(tester.takeException(), isNull);
      // Editing inside the dialog works as on the page.
      await tapKey(tester, 'schedule-due-k20260901');
      await enter(tester, 'schedule-due', '2026-09-05');
      await tapKey(tester, 'schedule-save');
      expect(find.text('05/09/2026'), findsOneWidget);
      // Chi tiết closes the dialog, then opens the invoice form.
      await tapKey(tester, 'schedule-details-k20261001');
      expect(find.byKey(const ValueKey('schedule-dialog')), findsNothing);
      expect(opened.period, ['2026-10-01', '2026-11-01', '2026-10-01']);
    }
    // Closing it reloads the count on the page.
    final s = _store()..scheduleInvoices['k20260901'] = 'inv-1';
    await mountReview(tester, summary(s, _Opened()), size: desktop);
    await tapKey(tester, 'schedule-open');
    s.scheduleInvoices['k20261001'] = 'inv-2';
    await tapKey(tester, 'schedule-dialog-close');
    expect(find.text('6 periods · 2 invoiced'), findsOneWidget);
  });

  testWidgets('the lease page shows the summary only when opened over the calendar', (
    tester,
  ) async {
    final s = _store();
    await mountReview(
      tester,
      TenantContactsScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        service: s.service,
        initialRecordId: 'tenant-anh',
        onClose: () {},
      ),
      size: desktop,
    );
    final open = find.byKey(const ValueKey('schedule-open'));
    await reveal(tester, open);
    expect(open, findsOneWidget);
    expect(_rows(tester), 0);
  });

  // Live check 2026-10-26: in an 800 px window the dialog showed cards, not
  // the table. The dialog is wide enough for the table at both sizes.
  testWidgets('the table dialog shows the table on wide windows', (
    tester,
  ) async {
    for (final size in [const Size(800, 815), desktop]) {
      await mountReview(tester, summary(_store(), _Opened()), size: size);
      await tapKey(tester, 'schedule-open');
      final table = find.byKey(const ValueKey('schedule-table'));
      final width = tester.getSize(find.byKey(const ValueKey('schedule-dialog'))).width;
      expect(table, findsOneWidget, reason: '$size: dialog $width px wide');
      await tapKey(tester, 'schedule-dialog-close');
    }
  });
}
