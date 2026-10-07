// 2026-10-04: electricity on a long-stay lease — price per kWh, the last
// reading, and "Record reading" with the meter number, day and a photo.
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/lease_electricity.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/problem_photos.dart'
    show PickedPhoto;
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'account_entry_test.dart' as fixtures;

Map<String, dynamic> _meter() => {
  'record': {
    'roomNumber': '101',
    'currency': 'VND',
    'revision': 3,
    'propertyRevision': 0,
    'roomTariffs': [
      {
        'effectiveDate': '2026-10-01',
        'tariff': {
          'currency': 'VND',
          'bands': [
            {'throughMilli': null, 'priceMinor': 3500},
          ],
        },
      },
    ],
    'propertyTariffs': [],
    'lastReadingId': 'r1',
    'lastDate': '2026-10-01',
    'lastReadingMilli': 1200000,
    'canBill': true,
    'canPrice': true,
    'today': '2026-10-04',
  },
  'records': [
    {
      'id': 'r1',
      'date': '2026-10-01',
      'readingMilli': 1200000,
      'calculation': null,
      'photos': [
        {'id': 'p1', 'mimeType': 'image/jpeg'},
      ],
    },
  ],
  'nextCursor': null,
};

void main() {
  test('usage is priced like the server: one rounding on the total', () {
    final tariff = {
      'bands': [
        {'throughMilli': 50000, 'priceMinor': 1893},
        {'throughMilli': null, 'priceMinor': 1956},
      ],
    };
    expect(electricityCharge(120000, tariff), 50 * 1893 + 70 * 1956);
    expect(
      electricityCharge(500, {
        'bands': [
          {'throughMilli': null, 'priceMinor': 3},
        ],
      }),
      2,
    );
  });

  testWidgets(
    'record a reading with its photo; the kWh are priced before saving',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (name, d) async {
          expect(name, 'utilityReadings');
          calls.add(Map<String, dynamic>.from(d));
          if (d['action'] == 'read') return _meter();
          if (d['action'] == 'record')
            return {'revision': 4, 'readingId': 'r2'};
          return {
            'readingId': 'r2',
            'photo': {'id': 'p2'},
          };
        },
      );
      final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]);
      await fixtures.mount(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: LeaseElectricitySection(
              organizationId: 'o',
              buildingId: 'b',
              roomId: 'room1',
              roomLabel: 'Room 101',
              service: service,
              pick: (max) async => [PickedPhoto(jpeg, 'meter.jpg')],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('3,500 VND / kWh'), findsOneWidget);
      expect(find.textContaining('1200 kWh · 2026-10-01'), findsWidgets);
      await t.tap(find.byKey(const ValueKey('lease-electricity-record')));
      await t.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, '2026-10-04'), findsOneWidget);
      // Lower than the last reading is caught.
      await t.enterText(
        find.byKey(const ValueKey('lease-electricity-reading')),
        '1100',
      );
      await t.tap(find.byKey(const ValueKey('lease-electricity-save')));
      await t.pumpAndSettle();
      expect(find.text('Lower than the last reading.'), findsOneWidget);
      await t.enterText(
        find.byKey(const ValueKey('lease-electricity-reading')),
        '1300',
      );
      await t.pump();
      expect(
        find.text('100 kWh × 3,500 VND/kWh = 350,000 VND'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('lease-electricity-photo')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('lease-electricity-save')));
      await t.pumpAndSettle();
      final record = calls.firstWhere((c) => c['action'] == 'record');
      expect(record['readingMilli'], 1300000);
      expect(record['date'], '2026-10-04');
      expect(record['revision'], 3);
      expect((record['reason'] as String).isNotEmpty, true);
      final photo = calls.firstWhere((c) => c['action'] == 'addPhoto');
      expect(photo['readingId'], 'r2');
      expect(photo['mimeType'], 'image/jpeg');
      expect(
        calls.where((c) => c['action'] == 'read'),
        hasLength(2),
        reason: 'reloads after saving',
      );
    },
  );

  // 2026-10-04 (Tom): each reading says whether it is on an invoice yet.
  testWidgets('readings say whether they are on an invoice', (t) async {
    final m = _meter();
    m['records'] = [
      {
        'id': 'r0',
        'date': '2026-08-01',
        'readingMilli': 1000000,
        'calculation': null,
      },
      {
        'id': 'r1',
        'date': '2026-09-01',
        'readingMilli': 1100000,
        'invoiceId': 'inv1',
        'calculation': {
          'usageMilli': 100000,
          'amountMinor': 350000,
          'currency': 'VND',
        },
      },
      {
        'id': 'r2',
        'date': '2026-10-01',
        'readingMilli': 1200000,
        'calculation': {
          'usageMilli': 100000,
          'amountMinor': 350000,
          'currency': 'VND',
        },
      },
    ];
    final service = TeamService(transport: (name, d) async => m);
    await fixtures.mount(
      t,
      Scaffold(
        body: SingleChildScrollView(
          child: LeaseElectricitySection(
            organizationId: 'o',
            buildingId: 'b',
            roomId: 'room1',
            roomLabel: 'Room 101',
            service: service,
            pick: (max) async => [],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.textContaining('2026-10-01 · 1200 kWh · +100 kWh'),
      findsOneWidget,
    );
    expect(find.textContaining('Not on an invoice yet'), findsOneWidget);
    expect(
      find.textContaining('2026-09-01 · 1100 kWh · +100 kWh'),
      findsOneWidget,
    );
    expect(find.textContaining('On an invoice'), findsOneWidget);
    expect(find.textContaining('Starting point, no charge.'), findsOneWidget);
  });

  testWidgets('change the price per kWh from a day on', (t) async {
    final calls = <Map<String, dynamic>>[];
    final service = TeamService(
      transport: (name, d) async {
        calls.add(Map<String, dynamic>.from(d));
        if (d['action'] == 'read') return _meter();
        return {'revision': 4};
      },
    );
    await fixtures.mount(
      t,
      Scaffold(
        body: SingleChildScrollView(
          child: LeaseElectricitySection(
            organizationId: 'o',
            buildingId: 'b',
            roomId: 'room1',
            roomLabel: 'Room 101',
            service: service,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('lease-electricity-price')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('lease-electricity-price-input')),
      '3800',
    );
    await t.tap(find.byKey(const ValueKey('lease-electricity-price-save')));
    await t.pumpAndSettle();
    final tariff = calls.firstWhere((c) => c['action'] == 'tariff');
    expect(tariff['effectiveDate'], '2026-10-04');
    expect(tariff['tariffScope'], 'room');
    expect(tariff['tariff'], {
      'currency': 'VND',
      'bands': [
        {'throughMilli': null, 'priceMinor': 3800},
      ],
    });
  });

  testWidgets('a failed load says so', (t) async {
    final service = TeamService(
      transport: (name, d) async => throw Exception('x'),
    );
    await fixtures.mount(
      t,
      Scaffold(
        body: LeaseElectricitySection(
          organizationId: 'o',
          buildingId: 'b',
          roomId: 'room1',
          roomLabel: 'Room 101',
          service: service,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Could not load electricity.'), findsOneWidget);
  });
}
