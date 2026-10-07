// 2026-10-04 (Tom): water per person per month on a long-stay lease, and the
// meter reading (with a photo) typed when the lease is made.
import 'dart:typed_data';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/problem_photos.dart'
    show PickedPhoto;
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_lease_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'tenant_lease_test.dart' as lease show store, room, fill;
import 'tenant_contacts_test.dart' as contacts show page, open;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;

Future<void> tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

final _jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0]);

/// The preview store for leases; meters answered here ([meter] may throw).
(TeamService, List<Map<String, dynamic>>, List<Map<String, dynamic>>) _service(
  dynamic s, {
  Object? recordError,
}) {
  final leases = <Map<String, dynamic>>[], meters = <Map<String, dynamic>>[];
  final service = TeamService(
    transport: (name, d) async {
      if (name == 'utilityReadings') {
        meters.add(Map<String, dynamic>.from(d));
        if (d['action'] == 'read') {
          return {
            'record': {'revision': 2},
            'records': [],
          };
        }
        if (d['action'] == 'record') {
          if (recordError != null) throw recordError;
          return {'revision': 3, 'readingId': 'r1'};
        }
        return {
          'readingId': 'r1',
          'photo': {'id': 'p1'},
        };
      }
      if (name == 'tenantLeases') leases.add(Map<String, dynamic>.from(d));
      return s.call(name, d);
    },
  );
  return (service, leases, meters);
}

Widget _page(TeamService service) => TenantLeaseScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  service: service,
  onBack: () {},
  pick: (max) async => [PickedPhoto(_jpeg, 'meter.jpg')],
);

void main() {
  testWidgets('water and the move-in meter reading with its photo', (
    tester,
  ) async {
    final s = lease.store();
    final (service, leases, meters) = _service(s);
    await mountReview(tester, _page(service));
    await lease.room(tester, 'room-102');
    await lease.fill(tester);
    await enter(tester, 'lease-water', '100000');
    // A photo without the reading it shows is caught.
    await tapKey(tester, 'lease-power-photo');
    expect(
      find.byKey(const ValueKey('lease-power-photo-preview')),
      findsOneWidget,
    );
    await press(tester, 'Create tenant and lease');
    expect(leases.where((d) => d['action'] == 'create'), isEmpty);
    expect(find.text('Enter a number (kWh).'), findsOneWidget);
    await enter(tester, 'lease-powerStart', '1200');
    await press(tester, 'Create tenant and lease');
    final create = leases.singleWhere((d) => d['action'] == 'create');
    expect(create['surcharges'], [
      {
        'label': 'Water',
        'amountMinor': 100000,
        'basis': 'person',
        'frequency': 'month',
        'kind': 'water',
      },
    ]);
    expect(meters.map((d) => d['action']), ['read', 'record', 'addPhoto']);
    expect(meters[1]['date'], '2026-09-27');
    expect(meters[1]['readingMilli'], 1200000);
    expect(meters[1]['revision'], 2);
    expect(meters[2]['readingId'], 'r1');
    expect(meters[2]['mimeType'], 'image/jpeg');
    expect(find.byKey(const ValueKey('lease-reading-warning')), findsNothing);
    expect(find.byKey(const ValueKey('lease-done')), findsOneWidget);
  });

  testWidgets('a reading that fails says so; the lease is still saved', (
    tester,
  ) async {
    final s = lease.store();
    final (service, leases, _) = _service(
      s,
      recordError: FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'utility_tariff_required',
      ),
    );
    await mountReview(tester, _page(service));
    await lease.room(tester, 'room-102');
    await lease.fill(tester);
    await enter(tester, 'lease-powerStart', '1200');
    await press(tester, 'Create tenant and lease');
    expect(leases.where((d) => d['action'] == 'create'), hasLength(1));
    expect(
      find.textContaining('the room has no electricity price yet'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('lease-done')), findsOneWidget);
  });

  testWidgets('moving in later: no reading box, a note instead', (
    tester,
  ) async {
    final s = lease.store();
    final (service, _, _) = _service(s);
    await mountReview(tester, _page(service));
    await lease.room(tester, 'room-102');
    await lease.fill(tester, date: '2026-10-05');
    expect(find.byKey(const ValueKey('lease-powerStart')), findsNothing);
    expect(
      find.text(
        'Moving in later: on that day, open this lease on the calendar › Electricity › Record reading.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the tenant page shows water on its own and edits it', (
    tester,
  ) async {
    final s = lease.store();
    s.tenants.first['surcharges'] = [
      {
        'id': 'park',
        'label': 'Gửi xe',
        'amountMinor': 100000,
        'basis': 'room',
        'frequency': 'period',
      },
      {
        'id': 'w',
        'label': 'Water',
        'amountMinor': 100000,
        'basis': 'person',
        'frequency': 'month',
        'kind': 'water',
      },
    ];
    await mountReview(tester, contacts.page(s.service));
    await contacts.open(tester, 'tenant-anh');
    expect(find.text('100,000 VND per person per month'), findsOneWidget);
    // Not repeated among the surcharges.
    expect(find.textContaining('Water ·'), findsNothing);
    expect(
      find.text('Gửi xe · 100,000 VND · Per room · Every period'),
      findsOneWidget,
    );
    await tapKey(tester, 'lease-water-edit');
    await enter(tester, 'lease-water-amount', '120000');
    await tapKey(tester, 'lease-water-save');
    final rows = (s.tenants.first['surcharges'] as List).cast<Map>();
    expect(rows.map((r) => [r['id'], r['amountMinor'], r['kind']]), [
      ['park', 100000, null],
      ['w', 120000, 'water'],
    ]);
    expect(find.text('120,000 VND per person per month'), findsOneWidget);
    // Editing the surcharges keeps the water line.
    await tapKey(tester, 'lease-surcharges-edit');
    await enter(tester, 'lease-surcharge-0-amount', '130000');
    await tapKey(tester, 'lease-surcharges-save');
    final after = (s.tenants.first['surcharges'] as List).cast<Map>();
    expect(after.map((r) => [r['id'], r['amountMinor']]), [
      ['park', 130000],
      ['w', 120000],
    ]);
    // Empty stops the water charge.
    await tapKey(tester, 'lease-water-edit');
    await enter(tester, 'lease-water-amount', '');
    await tapKey(tester, 'lease-water-save');
    expect(
      (s.tenants.first['surcharges'] as List).map((r) => (r as Map)['id']),
      ['park'],
    );
    expect(find.text('No water charge.'), findsOneWidget);
  });

  // 2026-10-04 (Tom): water for the whole room instead of per person.
  testWidgets('water can be one price for the whole room', (tester) async {
    final s = lease.store();
    final (service, leases, _) = _service(s);
    await mountReview(tester, _page(service));
    await lease.room(tester, 'room-102');
    await lease.fill(tester);
    await enter(tester, 'lease-water', '150000');
    await tapKey(tester, 'lease-water-room');
    expect(
      find.text('Optional. Each period: price × months, whoever lives there.'),
      findsOneWidget,
    );
    await press(tester, 'Create tenant and lease');
    final create = leases.singleWhere((d) => d['action'] == 'create');
    expect((create['surcharges'] as List).single, {
      'label': 'Water',
      'amountMinor': 150000,
      'basis': 'room',
      'frequency': 'month',
      'kind': 'water',
    });
  });

  testWidgets('the tenant page switches water to the whole room', (
    tester,
  ) async {
    final s = lease.store();
    s.tenants.first['surcharges'] = [
      {
        'id': 'w',
        'label': 'Water',
        'amountMinor': 100000,
        'basis': 'person',
        'frequency': 'month',
        'kind': 'water',
      },
    ];
    await mountReview(tester, contacts.page(s.service));
    await contacts.open(tester, 'tenant-anh');
    await tapKey(tester, 'lease-water-edit');
    // The page stays where it was scrolled after saving (2026-10-04, Tom).
    double scrolled() => tester
        .state<ScrollableState>(
          find
              .ancestor(
                of: find.byKey(const ValueKey('lease-water')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position
        .pixels;
    final before = scrolled();
    expect(before, greaterThan(0));
    // Plain taps: the shared helpers scroll the page to the top first.
    await tester.tap(find.byKey(const ValueKey('lease-water-room')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('lease-water-amount')),
      '200000',
    );
    await tester.tap(find.byKey(const ValueKey('lease-water-save')));
    await tester.pumpAndSettle();
    final row = (s.tenants.first['surcharges'] as List).single as Map;
    expect(
      [row['id'], row['basis'], row['amountMinor']],
      ['w', 'room', 200000],
    );
    expect(
      find.text('200,000 VND per month for the whole room'),
      findsOneWidget,
    );
    expect(scrolled(), before);
  });
}
