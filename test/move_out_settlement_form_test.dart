import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/move_out_settlement_form.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'account_entry_test.dart' as fixtures;

Map<String, dynamic> _preview({String? problem, bool open = true, String name = 'Le Van Chinh', String feeName = 'Rác', bool feeCredit = true}) => {
  'tenantName': name,
  'currency': 'VND',
  'today': '2026-11-20',
  'startDate': '2026-10-02',
  'open': open,
  'moveOutDate': open ? '2026-11-20' : '2026-11-15',
  'dateFixed': !open,
  'dateProblem': problem,
  'roommates': problem == null ? [] : [{'id': 'm', 'fullName': 'Pham Thi Dung'}],
  'canBackdate': true,
  'canPrice': true,
  'canRefund': true,
  'depositMinor': 5000000,
  'depositMethod': 'bankTransfer',
  'depositAccountLabel': '',
  'rent': null,
  'credits': [
    {'invoiceId': 'p1', 'startDate': '2026-11-20', 'endDate': '2027-01-02', 'creditMinor': 6994624},
  ],
  'feeCredits': [
    if (feeCredit) {'invoiceId': 'p1', 'feeId': 'f1', 'feeName': feeName, 'startDate': '2026-11-20', 'endDate': '2027-01-02', 'creditMinor': 140217},
  ],
  'fees': [
    {'id': 'f1', 'name': feeName, 'basis': 'person', 'startDate': '2026-10-02'},
  ],
  'readings': [
    {'roomId': 'r', 'kind': 'electricity', 'readingId': 'x', 'startDate': '2026-10-02', 'date': '2026-10-31', 'usageMilli': 25000, 'amountMinor': 87500},
  ],
  'lastReading': {'electricity': '2026-10-31'},
  'openInvoices': [
    {'id': 'p1', 'kind': 'period', 'startDate': '2026-10-02', 'endDate': '2027-01-02', 'dueDate': '2026-10-05', 'totalMinor': 15000000, 'paidMinor': 10000000, 'balanceMinor': 5000000},
  ],
  'accounts': [{'id': 'vcb', 'label': 'Vietcombank 0123'}],
  'revision': '0:0',
  'timeZone': 'Asia/Ho_Chi_Minh',
};

Map<String, dynamic> _quote({int refund = 1000000, int owed = 0}) => {
  'moveOutDate': '2026-11-20',
  'currency': 'VND',
  'lines': [
    {'type': 'utility', 'kind': 'electricity', 'roomId': 'r', 'readingId': 'x', 'startDate': '2026-10-02', 'endDate': '2026-10-31', 'usageMilli': 25000, 'amountMinor': 87500},
    {'type': 'manual', 'kind': 'damage', 'label': 'Vỡ kính', 'amountMinor': 300000},
    {'type': 'manual', 'kind': 'keepDeposit', 'label': 'Phá hợp đồng', 'amountMinor': 1000000},
  ],
  'finalMinor': 1387500,
  'depositMinor': 5000000,
  'keptMinor': 1000000,
  'credits': [
    {'kind': 'rent', 'invoiceId': 'p1', 'startDate': '2026-11-20', 'endDate': '2027-01-02', 'creditMinor': 6994624, 'returnedMinor': 1994624},
    {'kind': 'fee', 'invoiceId': 'p1', 'feeId': 'f1', 'feeName': 'Rác', 'startDate': '2026-11-20', 'endDate': '2027-01-02', 'creditMinor': 140217, 'returnedMinor': 140217},
  ],
  'returnedMinor': 1994624,
  'applications': [
    {'invoiceId': 'final', 'amountMinor': 1387500},
  ],
  'refundMinor': refund,
  'owedMinor': owed,
  'tenantName': 'Le Van Chinh',
  'quoteRevision': 'q1',
};

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> _enter(WidgetTester t, Finder f, String text) async {
  await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pump();
}

Widget _form(TeamService s, {VoidCallback? onDone}) => Scaffold(
  body: MoveOutSettlementForm(
    service: s,
    organizationId: 'o',
    buildingId: 'b',
    tenantId: 't',
    backLabel: 'Back',
    onDone: onDone ?? () {},
    onCancel: () {},
  ),
);

void main() {
  testWidgets('credit, lines and kept deposit; the refund way is required and sent; exact retry', (t) async {
    final quotes = <Map<String, dynamic>>[], settles = <Map<String, dynamic>>[];
    var fail = true;
    final service = TeamService(
      transport: (name, d) async {
        expect(name, 'leaseLifecycle');
        if (d['action'] == 'settlementPreview') return {'record': _preview()};
        if (d['action'] == 'settlementQuote') {
          quotes.add(Map<String, dynamic>.from(d));
          return {'record': _quote()};
        }
        settles.add(Map<String, dynamic>.from(d));
        if (fail) {
          fail = false;
          throw FirebaseFunctionsException(code: 'unavailable', message: 'offline');
        }
        return {'settlementId': 's1', 'finalInvoiceId': 'i1', 'refundMinor': 1000000, 'owedMinor': 0, 'currency': 'VND'};
      },
    );
    await fixtures.mount(t, _form(service));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, '2026-11-20'), findsOneWidget);
    expect(find.textContaining('5,000,000 VND'), findsWidgets);
    await _tap(t, find.byKey(const ValueKey('settlement-credit')));
    // Rent and fees paid ahead are two separate choices.
    expect(find.textContaining('Rác 2026-11-20'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('settlement-credit-fees')));
    await _tap(t, find.byKey(const ValueKey('settlement-fee-f1')));
    await _tap(t, find.byKey(const ValueKey('settlement-add-line')));
    await _enter(t, find.byKey(const ValueKey('settlement-line-0-label')), 'Vỡ kính');
    await _enter(t, find.byKey(const ValueKey('settlement-line-0-amount')), '300.000');
    await _tap(t, find.byKey(const ValueKey('settlement-add-line')));
    await _tap(t, find.byKey(const ValueKey('settlement-line-1-keepDeposit')));
    await _enter(t, find.byKey(const ValueKey('settlement-line-1-label')), 'Phá hợp đồng');
    await _enter(t, find.byKey(const ValueKey('settlement-line-1-amount')), '1.000.000');
    await _enter(t, find.byKey(const ValueKey('settlement-reason')), 'Trả phòng');
    await _tap(t, find.byKey(const ValueKey('settlement-review')));
    final q = quotes.single;
    expect(q['effectiveDate'], '2026-11-20');
    expect(q['creditRent'], true);
    expect(q['creditFees'], true);
    expect(q['includeRent'], false);
    expect(q['serviceFeeIds'], isEmpty, reason: 'the fee was unticked');
    expect(q['readings'], [
      {'roomId': 'r', 'kind': 'electricity', 'readingId': 'x'},
    ]);
    expect(q['lines'], [
      {'kind': 'damage', 'label': 'Vỡ kính', 'amountMinor': 300000},
      {'kind': 'keepDeposit', 'label': 'Phá hợp đồng', 'amountMinor': 1000000},
    ]);
    expect(find.text('Keep deposit: Phá hợp đồng'), findsOneWidget);
    expect(find.byKey(const ValueKey('settlement-refund')), findsOneWidget);
    expect(find.textContaining('This cannot be undone'), findsOneWidget);
    // No refund way chosen yet: refused before anything is sent.
    await _tap(t, find.byKey(const ValueKey('settlement-confirm')));
    expect(settles, isEmpty);
    expect(find.text('Choose how the money is returned.'), findsWidgets);
    // Rent paid ahead adds to the tenant's money, so it reads as "+".
    expect(find.textContaining('+6,994,624'), findsOneWidget);
    expect(find.textContaining('Fee credit Rác'), findsOneWidget);
    expect(find.textContaining('+140,217'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('settlement-refund-bank')));
    expect(find.text('Choose how the money is returned.'), findsNothing, reason: 'picking a way clears the warning');
    await _tap(t, find.byKey(const ValueKey('settlement-account-vcb')));
    await _tap(t, find.byKey(const ValueKey('settlement-confirm')));
    expect(quotes.length, 2, reason: 'the chosen refund way is priced again');
    expect(quotes.last['refundMethod'], 'bankTransfer');
    expect(quotes.last['refundAccountId'], 'vcb');
    expect(find.textContaining('Save was not confirmed'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    await _tap(t, find.byKey(const ValueKey('settlement-confirm')));
    expect(settles, hasLength(2));
    expect(settles[1], settles[0]);
    expect(settles[0]['quoteRevision'], 'q1');
    expect(settles[0]['revision'], '0:0');
    expect(settles[0]['refundMethod'], 'bankTransfer');
    expect(find.byKey(const ValueKey('settlement-done')), findsOneWidget);
    expect(find.textContaining('Return 1,000,000 VND'), findsOneWidget);
  });

  testWidgets('a roommate still living there blocks review and says who', (t) async {
    final service = TeamService(transport: (name, d) async => {'record': _preview(problem: 'lease_handle_roommates_first')});
    await fixtures.mount(t, _form(service));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('settlement-roommates')), findsOneWidget);
    expect(find.textContaining('Pham Thi Dung'), findsOneWidget);
    final review = t.widget<FilledButton>(find.byKey(const ValueKey('settlement-review')));
    expect(review.onPressed, isNull);
  });

  testWidgets('a lease that already ended keeps its date; what is owed is explained', (t) async {
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'settlementPreview') return {'record': _preview(open: false, feeCredit: false)};
        return {'record': {..._quote(refund: 0, owed: 3005376), 'credits': [], 'returnedMinor': 0}};
      },
    );
    await fixtures.mount(t, _form(service), locale: 'vi');
    await t.pumpAndSettle();
    expect(find.text('Quyết toán trả phòng'), findsOneWidget);
    final date = t.widget<TextFormField>(find.byKey(const ValueKey('settlement-date')));
    expect(date.enabled, false);
    // A fee whose own rule keeps the full charge offers nothing back: no box.
    expect(find.byKey(const ValueKey('settlement-credit-fees')), findsNothing);
    expect(find.byKey(const ValueKey('settlement-credit')), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('settlement-reason')), 'Quyết toán');
    await _tap(t, find.byKey(const ValueKey('settlement-review')));
    expect(find.byKey(const ValueKey('settlement-owed')), findsOneWidget);
    expect(find.textContaining('vẫn nằm trên các hóa đơn'), findsOneWidget);
    expect(find.byKey(const ValueKey('settlement-refund-cash')), findsNothing);
  });

  testWidgets('a stale meter reading gets a hint; server refusals are explained', (t) async {
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'settlementPreview') return {'record': _preview()};
        throw FirebaseFunctionsException(code: 'failed-precondition', message: 'settlement_keep_exceeds_deposit');
      },
    );
    await fixtures.mount(t, _form(service));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('settlement-meter-electricity')), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('settlement-reason')), 'Trả phòng');
    await _tap(t, find.byKey(const ValueKey('settlement-review')));
    expect(find.text('The deposit kept cannot be more than the deposit.'), findsOneWidget);
    expect(find.text('Trả phòng'), findsOneWidget, reason: 'the form stays as typed');
  });

  for (final locale in ['en', 'vi']) {
    for (final size in [const Size(360, 800), const Size(800, 360), const Size(1440, 900)]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('settlement layouts $locale ${size.width} $scale', (t) async {
          final service = TeamService(
            transport: (name, d) async {
              if (d['action'] == 'settlementPreview') {
                return {
                  'record': _preview(
                    name: 'Nguyễn Văn An — Khách thuê căn hộ gia đình hướng biển',
                    feeName: 'Phí vệ sinh khu vực chung và thu gom rác hằng ngày',
                  ),
                };
              }
              return {'record': _quote()};
            },
          );
          await fixtures.mount(t, _form(service), locale: locale, size: size, scale: scale);
          await t.pumpAndSettle();
          await _tap(t, find.byKey(const ValueKey('settlement-add-line')));
          await _tap(t, find.byKey(const ValueKey('settlement-line-0-keepDeposit')));
          await _enter(t, find.byKey(const ValueKey('settlement-line-0-label')), 'Phá hợp đồng trước thời hạn');
          await _enter(t, find.byKey(const ValueKey('settlement-line-0-amount')), '1000000');
          await _enter(t, find.byKey(const ValueKey('settlement-reason')), 'Trả phòng');
          await _tap(t, find.byKey(const ValueKey('settlement-review')));
          await _tap(t, find.byKey(const ValueKey('settlement-refund-bank')));
          final confirm = find.byKey(const ValueKey('settlement-confirm'));
          await t.ensureVisible(confirm);
          await t.pumpAndSettle();
          expect(confirm.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
