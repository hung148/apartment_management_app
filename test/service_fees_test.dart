import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_service_fees_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/service_fee_text.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/service_fees_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'account_entry_test.dart' as fixtures;

const _version = {
  'effectiveDate': '2026-09-01',
  'active': true,
  'rateMinor': 100000,
  'rule': {'mode': 'days'},
  'includedPeople': 0,
  'roundingMinor': 0,
};
Map<String, dynamic> _fee({
  String basis = 'person',
  String? billedThrough,
  String unit = '',
  String name = 'Rubbish',
}) => {
  'id': 'f1',
  'name': name,
  'basis': basis,
  'unitLabel': unit,
  'versions': [
    basis == 'quantity' ? {..._version, 'rule': null} : _version,
  ],
  'billedThrough': billedThrough,
  'overrides': <Map>[],
  'roomBilledThrough': null,
  'current': {
    ...(basis == 'quantity' ? {..._version, 'rule': null} : _version),
    'roomRate': false,
  },
};
Map<String, dynamic> _record(List<Map<String, dynamic>> fees) => {
  'currency': 'VND',
  'today': '2026-10-02',
  'revision': 3,
  'roomRevision': 0,
  'roomNumber': '101',
  'canPrice': true,
  'canBill': true,
  'fees': fees,
  'tenants': [
    {'id': 't', 'fullName': 'Le Van Chinh', 'current': true, 'currency': 'VND'},
  ],
};
final _quote = {
  'amountMinor': 133333,
  'totalMinor': 133333,
  'currency': 'VND',
  'periodDays': 31,
  'startDate': '2026-10-01',
  'endDate': '2026-11-01',
  'terms': {..._version, 'roomRate': false},
  'lines': [
    {'tenantId': 't', 'name': 'Le Van Chinh', 'days': 31, 'periodDays': 31, 'amountMinor': 100000, 'free': false},
    {'tenantId': 'm', 'name': 'Pham Thi Dung', 'days': 10, 'periodDays': 31, 'amountMinor': 33333, 'free': false},
  ],
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

Widget _property(TeamService s) => Scaffold(
  body: ServiceFeesScreen(organizationId: 'o', buildingId: 'b', service: s),
);
Widget _room(TeamService s) => Scaffold(
  body: RoomServiceFeesScreen(
    organizationId: 'o',
    buildingId: 'b',
    roomId: 'r',
    service: s,
    onBack: () {},
  ),
);

void main() {
  test('money parsing accepts thousands separators and rejects decimals for VND', () {
    expect(parseMinor('100000', 'VND'), 100000);
    expect(parseMinor('100.000', 'VND'), 100000);
    expect(parseMinor('100,000', 'VND'), 100000);
    expect(parseMinor('12.5', 'USD'), 1250);
    for (final bad in ['', '-1', '1.5', 'abc', '10000000000000']) {
      expect(parseMinor(bad, 'VND'), isNull, reason: bad);
    }
    expect(addDays('2026-10-31', 1), '2026-11-01');
    expect(periodText('2026-10-01', '2026-11-01'), '2026-10-01 – 2026-10-31');
  });

  testWidgets('the property list shows what applies today; a new fee with a preset sends exact terms', (t) async {
    final requests = <Map<String, dynamic>>[];
    final service = TeamService(
      transport: (_, d) async {
        if (d['action'] == 'read') return {'record': _record([_fee()])};
        requests.add(Map<String, dynamic>.from(d));
        return {'revision': 4, 'feeId': 'f2'};
      },
    );
    await fixtures.mount(t, _property(service));
    await t.pumpAndSettle();
    expect(find.text('Rubbish'), findsOneWidget);
    expect(find.textContaining('100,000 VND / person / period'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('fee-add')));
    await _enter(t, find.byKey(const ValueKey('fee-name')), 'Parking');
    await _enter(t, find.byKey(const ValueKey('fee-rate')), '50.000');
    await _tap(t, find.byKey(const ValueKey('fee-mode-thresholds')));
    await _tap(t, find.widgetWithText(ActionChip, 'Half / full'));
    await _enter(t, find.byKey(const ValueKey('fee-reason')), 'House rules');
    await _tap(t, find.byKey(const ValueKey('fee-save')));
    expect(requests, hasLength(1));
    final r = requests.single;
    expect(r['action'], 'define');
    expect(r['revision'], 3);
    expect(r['feeId'], isNull);
    expect(r['name'], 'Parking');
    expect(r['basis'], 'person');
    expect(r['version'], {
      'effectiveDate': '2026-10-02',
      'active': true,
      'rateMinor': 50000,
      'rule': {
        'mode': 'thresholds',
        'steps': [
          {'minDays': 1, 'percent': 50},
          {'minDays': 15, 'percent': 100},
        ],
      },
      'includedPeople': 0,
      'roundingMinor': 0,
    });
    expect(find.text('Fee added.'), findsOneWidget);
  });

  testWidgets('invalid steps and dates before what was billed are blocked before sending', (t) async {
    var writes = 0;
    final service = TeamService(
      transport: (_, d) async {
        if (d['action'] == 'read') return {'record': _record([_fee(billedThrough: '2026-10-01')])};
        writes++;
        return {'revision': 4};
      },
    );
    await fixtures.mount(t, _property(service));
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('fee-edit-f1')));
    expect(find.textContaining('Choose 2026-10-01 or later'), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('fee-date')), '2026-09-15');
    await _enter(t, find.byKey(const ValueKey('fee-reason')), 'Correction');
    await _tap(t, find.byKey(const ValueKey('fee-save')));
    expect(find.text('Choose 2026-10-01 or later.'), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('fee-date')), '2026-10-05');
    await _tap(t, find.byKey(const ValueKey('fee-mode-thresholds')));
    await _enter(t, find.byKey(const ValueKey('fee-step-days-0')), '20');
    await _tap(t, find.text('Add step'));
    await _enter(t, find.byKey(const ValueKey('fee-step-days-1')), '10');
    await _enter(t, find.byKey(const ValueKey('fee-step-percent-1')), '100');
    await _tap(t, find.byKey(const ValueKey('fee-save')));
    expect(find.text('Each step needs more days and a higher percent than the one before.'), findsOneWidget);
    expect(writes, 0);
  });

  testWidgets('room invoice: per-person lines, inclusive dates and an exact retry after a lost response', (t) async {
    final creates = <Map<String, dynamic>>[];
    Map<String, dynamic>? quoted;
    var fail = true;
    final service = TeamService(
      transport: (name, d) async {
        if (name == 'serviceFees') return {'record': _record([_fee()])};
        if (d['action'] == 'quote') {
          quoted = Map<String, dynamic>.from(d);
          return {'record': _quote};
        }
        creates.add(Map<String, dynamic>.from(d));
        if (fail) {
          fail = false;
          throw FirebaseFunctionsException(code: 'unavailable', message: 'offline');
        }
        return {'invoiceId': 'invoice_1'};
      },
    );
    await fixtures.mount(t, _room(service));
    await t.pumpAndSettle();
    expect(find.text('Property price'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('room-fee-bill-f1')));
    expect(find.byKey(const ValueKey('fee-invoice-start')), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('fee-invoice-reason')), 'Rubbish, October');
    await _tap(t, find.byKey(const ValueKey('fee-invoice-review')));
    expect(quoted?['kind'], 'service');
    expect(quoted?['tenantId'], 't');
    expect(quoted?['startDate'], '2026-10-01');
    expect(quoted?['endDate'], '2026-11-01', reason: 'the last day is inclusive on screen');
    expect(quoted?['quantityMilli'], isNull);
    expect(find.text('Pham Thi Dung: 10/31 days = 33,333 VND'), findsOneWidget);
    expect(find.text('Total: 133,333 VND'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('fee-invoice-create')));
    expect(find.textContaining('Save was not confirmed'), findsOneWidget);
    expect(find.text('Edit'), findsNothing, reason: 'an unconfirmed save can only be retried');
    await _tap(t, find.byKey(const ValueKey('fee-invoice-create')));
    expect(creates, hasLength(2));
    expect(creates[1], creates[0]);
    expect(creates[0]['quoteRevision'], 'q1');
    expect(find.text('Invoice created. It is in Money › Invoices.'), findsOneWidget);
  });

  testWidgets('server refusals explain what to do; the form stays as typed', (t) async {
    var creates = 0;
    final service = TeamService(
      transport: (name, d) async {
        if (name == 'serviceFees') return {'record': _record([_fee()])};
        if (d['action'] == 'quote') {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: '[firebase_functions/failed-precondition] service_fee_boundary_required',
          );
        }
        creates++;
        return {};
      },
    );
    await fixtures.mount(t, _room(service), locale: 'vi');
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('room-fee-bill-f1')));
    await _enter(t, find.byKey(const ValueKey('fee-invoice-reason')), 'Phí rác tháng 10');
    await _tap(t, find.byKey(const ValueKey('fee-invoice-review')));
    expect(
      find.text('Giá thay đổi trong kỳ này. Lập hóa đơn đến ngày đổi giá, rồi một hóa đơn từ ngày đó.'),
      findsOneWidget,
    );
    expect(find.text('Phí rác tháng 10'), findsOneWidget);
    expect(creates, 0);
  });

  testWidgets('a room price dialog sends the dated room override', (t) async {
    final writes = <Map<String, dynamic>>[];
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'read') return {'record': _record([_fee()])};
        writes.add(Map<String, dynamic>.from(d));
        return {'revision': 1};
      },
    );
    await fixtures.mount(t, _room(service));
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('room-fee-rate-f1')));
    await _tap(t, find.byKey(const ValueKey('room-rate-mode-off')));
    await t.enterText(find.byKey(const ValueKey('room-rate-reason')), 'Room has its own bins');
    await _tap(t, find.byKey(const ValueKey('room-rate-save')));
    expect(writes.single['action'], 'roomRate');
    expect(writes.single['revision'], 0);
    expect(writes.single['override'], {'effectiveDate': '2026-10-02', 'mode': 'off'});
    expect(find.text('Room price saved.'), findsOneWidget);
  });

  testWidgets('a quantity extra bills one service date and the entered quantity', (t) async {
    Map<String, dynamic>? quoted;
    final service = TeamService(
      transport: (name, d) async {
        if (name == 'serviceFees') {
          return {'record': _record([_fee(basis: 'quantity', unit: 'kg', name: 'Laundry')])};
        }
        quoted = Map<String, dynamic>.from(d);
        return {
          'record': {
            ..._quote,
            'lines': [
              {'tenantId': 't', 'name': 'Le Van Chinh', 'quantityMilli': 2500, 'amountMinor': 37500},
            ],
            'totalMinor': 37500,
          },
        };
      },
    );
    await fixtures.mount(t, _room(service));
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('room-fee-bill-f1')));
    await _enter(t, find.byKey(const ValueKey('fee-invoice-quantity')), '2,5');
    await _enter(t, find.byKey(const ValueKey('fee-invoice-reason')), 'Laundry');
    await _tap(t, find.byKey(const ValueKey('fee-invoice-review')));
    expect(quoted?['quantityMilli'], 2500);
    expect(quoted?['startDate'], '2026-10-02');
    expect(quoted?['endDate'], '2026-10-03');
    expect(find.text('Le Van Chinh: 2.5 kg = 37,500 VND'), findsOneWidget);
  });

  for (final locale in ['en', 'vi']) {
    for (final size in [const Size(360, 800), const Size(800, 360), const Size(1440, 900)]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('service fee layouts $locale ${size.width} $scale', (t) async {
          const longName = 'Phí vệ sinh khu vực chung và thu gom rác hằng ngày';
          final service = TeamService(
            transport: (name, d) async {
              if (name == 'serviceFees') {
                return {
                  'record': {
                    ..._record([_fee(name: longName)]),
                    'roomNumber': 'Riverside — Phòng gia đình hướng biển 1201',
                    'tenants': [
                      {'id': 't', 'fullName': 'Nguyễn Văn An — Khách thuê căn hộ gia đình hướng biển', 'current': true, 'currency': 'VND'},
                    ],
                  },
                };
              }
              return {'record': _quote};
            },
          );
          await fixtures.mount(t, _property(service), locale: locale, size: size, scale: scale);
          await t.pumpAndSettle();
          await _tap(t, find.byKey(const ValueKey('fee-add')));
          await _tap(t, find.byKey(const ValueKey('fee-mode-thresholds')));
          final save = find.byKey(const ValueKey('fee-save'));
          await t.ensureVisible(save);
          await t.pumpAndSettle();
          expect(save.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);

          await fixtures.mount(t, _room(service), locale: locale, size: size, scale: scale);
          await t.pumpAndSettle();
          expect(find.text(longName), findsOneWidget);
          await _tap(t, find.byKey(const ValueKey('room-fee-bill-f1')));
          await _enter(t, find.byKey(const ValueKey('fee-invoice-reason')), 'Phí tháng 10');
          await _tap(t, find.byKey(const ValueKey('fee-invoice-review')));
          final create = find.byKey(const ValueKey('fee-invoice-create'));
          await t.ensureVisible(create);
          await t.pumpAndSettle();
          expect(create.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
