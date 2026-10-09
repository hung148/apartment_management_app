import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/period_invoice_form.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_money.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'account_entry_test.dart' as fixtures;

Map<String, dynamic> _preview({
  bool canPrice = true,
  bool finished = false,
  String name = 'Le Van Chinh',
  String feeName = 'Rubbish',
  bool canBackdate = true,
}) => {
  'tenantName': name,
  'currency': 'VND',
  'roomId': 'r1',
  'today': '2026-10-02',
  'periodMonths': 3,
  'dueDay': 5,
  'periodRentMinor': 15000000,
  'monthlyRentMinor': 5000000,
  'finished': finished,
  'suggestion': finished
      ? null
      : {'startDate': '2026-10-01', 'endDate': '2027-01-01', 'dueDate': '2026-10-05'},
  'fees': finished
      ? []
      : [
          {'id': 'f1', 'name': feeName, 'basis': 'person'},
        ],
  'readings': finished
      ? []
      : [
          {
            'roomId': 'r1',
            'kind': 'electricity',
            'readingId': 'e9',
            'startDate': '2026-09-01',
            'date': '2026-10-01',
            'usageMilli': 120000,
            'amountMinor': 420000,
          },
        ],
  'canPrice': canPrice,
  'canBackdate': canBackdate,
};

final _quote = {
  'totalMinor': 15420000 + 300000 - 1500000,
  'currency': 'VND',
  'quoteRevision': 'q1',
  'lines': [
    {'type': 'rent', 'amountMinor': 15000000, 'startDate': '2026-10-01', 'endDate': '2027-01-01', 'basis': 'period', 'months': 3},
    {'type': 'service', 'feeId': 'f1', 'feeName': 'Rubbish', 'amountMinor': 300000, 'people': [{}, {}]},
    {'type': 'utility', 'kind': 'electricity', 'roomId': 'r1', 'readingId': 'e9', 'startDate': '2026-09-01', 'endDate': '2026-10-01', 'usageMilli': 120000, 'amountMinor': 420000},
    {'type': 'manual', 'kind': 'discount', 'label': 'Loyal tenant', 'amountMinor': -1500000, 'percent': 10},
  ],
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

Widget _form(TeamService s, {String? tenantId = 't', VoidCallback? onDone}) => Scaffold(
  body: PeriodInvoiceForm(
    service: s,
    organizationId: 'o',
    buildingId: 'b',
    tenantId: tenantId,
    backLabel: 'Back',
    onDone: onDone ?? () {},
    onCancel: () {},
  ),
);

void main() {
  testWidgets('new period invoice pins selected currency and server rate through review and save', (t) async {
    final money = OrganizationMoney.shared;
    money.clear();
    addTearDown(money.clear);
    final rateId = List.filled(64, 'a').join();
    money.configure('o', 'USD', ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 25000}, dates: {'VND': '2026-10-08'}, snapshotId: rateId));
    final requests = <Map<String, dynamic>>[];
    final service = TeamService(transport: (_, data) async {
      requests.add(Map.of(data));
      if (data['action'] == 'periodPreview') {
        return {'record': {..._preview(), 'currency': 'USD', 'monthlyRentMinor': 20000,
          'periodRentMinor': 60000, 'fees': <Map>[], 'readings': <Map>[]}};
      }
      if (data['action'] == 'quote') {
        return {'record': {'currency': 'USD', 'totalMinor': 60000, 'quoteRevision': 'usd-q',
          'lines': [{'type': 'rent', 'amountMinor': 60000, 'startDate': '2026-10-01', 'endDate': '2027-01-01', 'basis': 'period', 'months': 3}]}};
      }
      return {'invoiceId': 'new-usd'};
    });
    await fixtures.mount(t, _form(service));
    await t.pumpAndSettle();
    expect(requests.first['ratesId'], rateId);
    money.configure('o', 'VND', ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 27000}, dates: {}, snapshotId: List.filled(64, 'b').join()));
    await _enter(t, find.byKey(const ValueKey('period-reason')), 'Period');
    await _tap(t, find.byKey(const ValueKey('period-review')));
    final quote = requests.last;
    expect(quote['inputCurrency'], 'USD');
    expect(quote['ratesId'], rateId);
    await _tap(t, find.byKey(const ValueKey('period-create')));
    expect(requests.last['action'], 'create');
    expect(requests.last['ratesId'], rateId);
    expect(requests.last['inputCurrency'], 'USD');
  });
  testWidgets('suggested period, everything ticked, discount by percent, exact retry', (t) async {
    final creates = <Map<String, dynamic>>[];
    Map<String, dynamic>? quoted, previewed;
    var fail = true, done = 0;
    final service = TeamService(
      transport: (name, d) async {
        expect(name, 'invoices');
        if (d['action'] == 'periodPreview') {
          previewed = Map<String, dynamic>.from(d);
          return {'record': _preview()};
        }
        if (d['action'] == 'quote') {
          quoted = Map<String, dynamic>.from(d);
          return {'record': _quote};
        }
        creates.add(Map<String, dynamic>.from(d));
        if (fail) {
          fail = false;
          throw FirebaseFunctionsException(code: 'unavailable', message: 'offline');
        }
        return {'invoiceId': 'i1'};
      },
    );
    await fixtures.mount(t, _form(service, onDone: () => done++));
    await t.pumpAndSettle();
    expect(previewed?['tenantId'], 't');
    // The end date is shown inclusive: the period [10-01, 01-01) ends 12-31.
    expect(find.widgetWithText(TextFormField, '2026-10-01'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '2026-12-31'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '2026-10-05'), findsOneWidget);
    expect(find.textContaining('15,000,000 VND'), findsOneWidget);

    await _tap(t, find.byKey(const ValueKey('period-add-line')));
    await _tap(t, find.byKey(const ValueKey('period-line-0-discount')));
    await _tap(t, find.byKey(const ValueKey('period-line-0-percent')));
    await _enter(t, find.byKey(const ValueKey('period-line-0-label')), 'Loyal tenant');
    await _enter(t, find.byKey(const ValueKey('period-line-0-amount')), '10');
    await _enter(t, find.byKey(const ValueKey('period-reason')), 'Period 2');
    await _tap(t, find.byKey(const ValueKey('period-review')));

    expect(quoted?['kind'], 'period');
    expect(quoted?['startDate'], '2026-10-01');
    expect(quoted?['endDate'], '2027-01-01');
    expect(quoted?['dueDate'], '2026-10-05');
    expect(quoted?['includeRent'], true);
    expect(quoted?['serviceFeeIds'], ['f1']);
    expect(quoted?['readings'], [
      {'roomId': 'r1', 'kind': 'electricity', 'readingId': 'e9'},
    ]);
    expect(quoted?['lines'], [
      {'kind': 'discount', 'label': 'Loyal tenant', 'percent': 10},
    ]);
    expect(find.textContaining('(3 months)'), findsOneWidget);
    expect(find.text('Rubbish · 2 people'), findsOneWidget);
    expect(find.textContaining('120 kWh'), findsWidgets);
    expect(find.text('Loyal tenant (10%)'), findsOneWidget);
    expect(find.text('−1,500,000 VND'), findsOneWidget);
    expect(find.byKey(const ValueKey('period-total')), findsOneWidget);

    await _tap(t, find.byKey(const ValueKey('period-create')));
    expect(find.textContaining('Save was not confirmed'), findsOneWidget);
    expect(find.text('Edit'), findsNothing, reason: 'an unconfirmed save can only be retried');
    await _tap(t, find.byKey(const ValueKey('period-create')));
    expect(creates, hasLength(2));
    expect(creates[1], creates[0]);
    expect(creates[0]['quoteRevision'], 'q1');
    expect(done, 1);
  });

  testWidgets('unticked items stay off the request; other lines may subtract', (t) async {
    Map<String, dynamic>? quoted;
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'periodPreview') return {'record': _preview()};
        quoted = Map<String, dynamic>.from(d);
        return {'record': _quote};
      },
    );
    await fixtures.mount(t, _form(service));
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('period-rent')));
    await _tap(t, find.byKey(const ValueKey('period-fee-f1')));
    await _tap(t, find.byKey(const ValueKey('period-add-line')));
    await _tap(t, find.byKey(const ValueKey('period-line-0-other')));
    await _enter(t, find.byKey(const ValueKey('period-line-0-label')), 'Refund for broken fan');
    await _enter(t, find.byKey(const ValueKey('period-line-0-amount')), '-50.000');
    await _enter(t, find.byKey(const ValueKey('period-reason')), 'Electricity only');
    await _tap(t, find.byKey(const ValueKey('period-review')));
    expect(quoted?['includeRent'], false);
    expect(quoted?['serviceFeeIds'], isEmpty);
    expect(quoted?['readings'], hasLength(1));
    expect(quoted?['lines'], [
      {'kind': 'other', 'label': 'Refund for broken fan', 'amountMinor': -50000},
    ]);
  });

  testWidgets('line mistakes are caught before sending', (t) async {
    var quotes = 0;
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'periodPreview') return {'record': _preview()};
        quotes++;
        return {'record': _quote};
      },
    );
    await fixtures.mount(t, _form(service));
    await t.pumpAndSettle();
    await _enter(t, find.byKey(const ValueKey('period-reason')), 'Period 2');
    await _tap(t, find.byKey(const ValueKey('period-add-line')));
    await _tap(t, find.byKey(const ValueKey('period-review')));
    expect(find.text('Each line needs a description.'), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('period-line-0-label')), 'Late');
    await _enter(t, find.byKey(const ValueKey('period-line-0-amount')), '-5');
    await _tap(t, find.byKey(const ValueKey('period-review')));
    expect(find.text('Enter an amount above 0 for each line.'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('period-line-0-discount')));
    await _tap(t, find.byKey(const ValueKey('period-line-0-percent')));
    await _enter(t, find.byKey(const ValueKey('period-line-0-amount')), '150');
    await _tap(t, find.byKey(const ValueKey('period-review')));
    expect(find.text('Enter a percent from 1 to 100.'), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('period-line-0-amount')), '10');
    await _tap(t, find.byKey(const ValueKey('period-rent')));
    await _tap(t, find.byKey(const ValueKey('period-review')));
    expect(find.text('A percent discount needs the rent on this invoice.'), findsOneWidget);
    // End before start.
    await _tap(t, find.byKey(const ValueKey('period-rent')));
    await _enter(t, find.byKey(const ValueKey('period-end')), '2026-09-30');
    await _tap(t, find.byKey(const ValueKey('period-review')));
    expect(find.text('Must be on or after the start.'), findsOneWidget);
    expect(quotes, 0);
  });

  testWidgets('server refusals are explained in Vietnamese and the form stays', (t) async {
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'periodPreview') return {'record': _preview()};
        throw FirebaseFunctionsException(
          code: 'already-exists',
          message: '[firebase_functions/already-exists] invoice_period_exists',
        );
      },
    );
    await fixtures.mount(t, _form(service), locale: 'vi');
    await t.pumpAndSettle();
    await _enter(t, find.byKey(const ValueKey('period-reason')), 'Kỳ 2');
    await _tap(t, find.byKey(const ValueKey('period-review')));
    expect(find.textContaining('Tiền thuê hoặc một khoản phí đã có hóa đơn'), findsOneWidget);
    expect(find.text('Kỳ 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('period-create')), findsNothing);
  });

  testWidgets('a finished lease says so and offers nothing to send', (t) async {
    final service = TeamService(
      transport: (name, d) async => {'record': _preview(finished: true)},
    );
    await fixtures.mount(t, _form(service, tenantId: 'u'));
    await t.pumpAndSettle();
    expect(find.text('This lease has no period left to bill.'), findsOneWidget);
    expect(find.byKey(const ValueKey('period-review')), findsNothing);
  });

  testWidgets('choosing a lease; no price permission means no extra lines', (t) async {
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'tenants') {
          return {
            'records': [
              {'id': 't', 'fullName': 'Le Van Chinh'},
              {'id': 'u', 'fullName': 'Tran Thi Mai'},
            ],
          };
        }
        return {'record': _preview(canPrice: false)};
      },
    );
    await fixtures.mount(t, _form(service, tenantId: null));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('period-tenant-u')), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('period-tenant-t')));
    expect(find.byKey(const ValueKey('period-tenant-u')), findsNothing);
    expect(find.byKey(const ValueKey('period-add-line')), findsNothing);
    expect(find.text('Adding lines needs permission to change prices.'), findsOneWidget);
  });

  testWidgets('a period that already started warns staff without "Enter past dates"', (t) async {
    final service = TeamService(
      transport: (name, d) async => {'record': _preview(canBackdate: false)},
    );
    await fixtures.mount(t, _form(service));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('period-backdate-notice')), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('period-start')), '2026-10-02');
    await _enter(t, find.byKey(const ValueKey('period-due')), '2026-10-05');
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('period-backdate-notice')), findsNothing);
  });

  testWidgets('a fee already billed past the start stays off and says how far', (t) async {
    Map<String, dynamic>? quoted;
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'periodPreview') {
          final p = _preview();
          p['fees'] = [
            {'id': 'f1', 'name': 'Rubbish', 'basis': 'person', 'billedUntil': '2026-11-01'},
          ];
          return {'record': p};
        }
        quoted = Map<String, dynamic>.from(d);
        return {'record': _quote};
      },
    );
    await fixtures.mount(t, _form(service));
    await t.pumpAndSettle();
    expect(find.text('Per person · billed through 2026-10-31'), findsOneWidget);
    final box = t.widget<CheckboxListTile>(find.byKey(const ValueKey('period-fee-f1')));
    expect(box.value, false);
    expect(box.onChanged, isNull);
    await _enter(t, find.byKey(const ValueKey('period-reason')), 'Period 2');
    await _tap(t, find.byKey(const ValueKey('period-review')));
    expect(quoted?['serviceFeeIds'], isEmpty);
    // Starting after the billed days makes it available again.
    await _tap(t, find.text('Edit'));
    await _enter(t, find.byKey(const ValueKey('period-start')), '2026-11-01');
    await t.pumpAndSettle();
    expect(t.widget<CheckboxListTile>(find.byKey(const ValueKey('period-fee-f1'))).onChanged, isNotNull);
  });

  // 2026-10-04 (Tom): with no electricity reading to bill, the form says why.
  testWidgets('no electricity line: the form says why', (t) async {
    Future<String?> note(Map<String, dynamic>? last, {bool reading = false}) async {
      final service = TeamService(
        transport: (name, d) async {
          final p = _preview();
          if (!reading) p['readings'] = <Map<String, dynamic>>[];
          p['lastElectricity'] = last;
          return {'record': p};
        },
      );
      // A fresh form each time: the same form on the same spot keeps its
      // first preview.
      await t.pumpWidget(const SizedBox());
      await fixtures.mount(t, _form(service));
      await t.pumpAndSettle();
      final f = find.byKey(const ValueKey('period-no-electricity'));
      return f.evaluate().isEmpty ? null : t.widget<Text>(f).data;
    }

    expect(
      await note({'date': '2026-10-01', 'status': 'invoiced'}),
      contains('already on an invoice'),
    );
    expect(await note({'date': '2026-10-01', 'status': 'noCharge'}), contains('starting point'));
    expect(await note(null), contains('no meter reading yet'));
    // A reading to bill is listed instead; no note.
    expect(await note({'date': '2026-10-01', 'status': 'unbilled'}, reading: true), isNull);
  });

  testWidgets('a failed load offers Retry', (t) async {
    var calls = 0;
    final service = TeamService(
      transport: (name, d) async {
        calls++;
        if (calls == 1) throw FirebaseFunctionsException(code: 'unavailable', message: 'offline');
        return {'record': _preview()};
      },
    );
    await fixtures.mount(t, _form(service));
    await t.pumpAndSettle();
    await _tap(t, find.text('Retry'));
    expect(find.byKey(const ValueKey('period-review')), findsOneWidget);
  });

  for (final locale in ['en', 'vi']) {
    for (final size in [const Size(360, 800), const Size(800, 360), const Size(1440, 900)]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('period invoice layouts $locale ${size.width} $scale', (t) async {
          final service = TeamService(
            transport: (name, d) async {
              if (d['action'] == 'periodPreview') {
                return {
                  'record': _preview(
                    name: 'Nguyễn Văn An — Khách thuê căn hộ gia đình hướng biển',
                    feeName: 'Phí vệ sinh khu vực chung và thu gom rác hằng ngày',
                  ),
                };
              }
              return {'record': _quote};
            },
          );
          await fixtures.mount(t, _form(service), locale: locale, size: size, scale: scale);
          await t.pumpAndSettle();
          await _tap(t, find.byKey(const ValueKey('period-add-line')));
          await _tap(t, find.byKey(const ValueKey('period-line-0-discount')));
          await _enter(t, find.byKey(const ValueKey('period-line-0-label')), 'Giảm giá khách thuê lâu năm');
          await _enter(t, find.byKey(const ValueKey('period-line-0-amount')), '100000');
          await _enter(t, find.byKey(const ValueKey('period-reason')), 'Kỳ 2');
          await _tap(t, find.byKey(const ValueKey('period-review')));
          final create = find.byKey(const ValueKey('period-create'));
          await t.ensureVisible(create);
          await t.pumpAndSettle();
          expect(create.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
