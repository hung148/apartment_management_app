import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
// B1/B2 (2026-10-01): the sectioned short-stay booking form.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_money.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/booking_workspace_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'tenant_lease_test.dart' show store;
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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'a nightly booking with a co-guest and a surcharge is quoted and saved',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({
        'rentalMode': 'both',
        'hourlyPrice': 100000,
        'dailyPrice': 500000,
        'currency': 'VND',
      });
      await mountReview(
        tester,
        BookingWorkspaceScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          accountId: 'owner',
          service: s.service,
          onBack: () {},
        ),
      );
      await press(tester, 'New booking');
      await enter(tester, 'ops-guest', 'Anh');
      await enter(tester, 'ops-startLocal', '2026-10-10 14:00');
      await enter(tester, 'ops-endLocal', '2026-10-12 12:00');
      await tester.pumpAndSettle();
      expect(find.text('2 nights'), findsOneWidget);
      await tapKey(tester, 'booking-pricing-nightly');
      await tapKey(tester, 'booking-add-guest');
      await enter(tester, 'ops-coGuest-0', 'Binh');
      await enter(tester, 'ops-coGuestId-0', '079200005678');
      await tapKey(tester, 'booking-add-surcharge');
      await enter(tester, 'ops-surcharge-0', 'Extra bed');
      await enter(tester, 'ops-surchargeAmount-0', '150000');
      await press(tester, 'Review calculation');
      expect(find.text('1,150,000 VND'), findsOneWidget);
      await press(tester, 'Confirm and save');
      final b = s.operationalBookings.single;
      expect(b['totalPrice'], 1150000);
      expect(b['pricingType'], 'nightly');
      expect((b['guests'] as List).single['name'], 'Binh');
      expect(b['numberOfGuests'], 2);
      expect((b['surcharges'] as List).single['label'], 'Extra bed');
      // The detail view shows the stay in anh Hưng's words.
      expect(find.text('Anh'), findsWidgets);
      expect(find.textContaining('Extra bed'), findsOneWidget);
    },
  );

  testWidgets('an incomplete surcharge line is caught before the price check', (
    tester,
  ) async {
    final s = store();
    s.rooms.last.addAll({
      'rentalMode': 'hourly',
      'hourlyPrice': 100000,
      'currency': 'VND',
    });
    await mountReview(
      tester,
      BookingWorkspaceScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        accountId: 'owner',
        service: s.service,
        onBack: () {},
      ),
    );
    await press(tester, 'New booking');
    await enter(tester, 'ops-guest', 'Anh');
    await enter(tester, 'ops-startLocal', '2026-10-10 09:00');
    await enter(tester, 'ops-endLocal', '2026-10-10 11:00');
    await tapKey(tester, 'booking-add-surcharge');
    await enter(tester, 'ops-surchargeAmount-0', '50000');
    await press(tester, 'Review calculation');
    expect(find.byKey(const ValueKey('booking-form-message')), findsOneWidget);
    expect(s.operationalBookings, isEmpty);
  });

  // 2026-10-03: only per night and per hour; a nights box moves the check-out;
  // a price per hour; the price box is the room's price for people without "Đổi giá".
  Future<TeamPreviewStore> openNew(
    WidgetTester tester, {
    String role = 'owner',
    int nightlyPrice = 500000,
    List<int>? saved,
  }) async {
    final s = store()
      ..workspaceRole = role
      ..previewToday = '2026-10-04';
    s.rooms.last.addAll({
      'rentalMode': 'both',
      'hourlyPrice': 100000,
      'dailyPrice': nightlyPrice,
      'currency': 'VND',
    });
    if (saved != null) {
      s.buildingPriceLists['riverside'] = List.of(saved);
    }
    await mountReview(
      tester,
      BookingWorkspaceScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        accountId: 'owner',
        service: s.service,
        onBack: () {},
      ),
    );
    await press(tester, 'New booking');
    await enter(tester, 'ops-guest', 'Anh');
    await enter(tester, 'ops-startLocal', '2026-10-10 14:00');
    await enter(tester, 'ops-endLocal', '2026-10-12 12:00');
    await tester.pumpAndSettle();
    return s;
  }

  String text(WidgetTester tester, String key) =>
      tester.widget<TextFormField>(find.byKey(ValueKey(key))).controller!.text;

  testWidgets(
    'new converted custom nights use selected currency and preserve source room price',
    (tester) async {
      OrganizationMoney.shared.configure(
        'preview',
        'USD',
        ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 25000}, dates: {}),
      );
      addTearDown(OrganizationMoney.shared.clear);
      final s = await openNew(tester, nightlyPrice: 500001);
      await tapKey(tester, 'booking-custom-nights');
      await enter(tester, 'ops-nightsField', '3');
      await press(tester, 'Review calculation');
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings.single['totalPrice'], 60);
      expect(s.operationalBookings.single['currency'], 'USD');
      expect(s.rooms.last['dailyPrice'], 500001);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'per night: the nights box and the check-out follow each other; price × nights',
    (tester) async {
      final s = await openNew(tester);
      expect(
        find.byKey(const ValueKey('booking-pricing-overnight')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('booking-pricing-daily')), findsNothing);
      expect(text(tester, 'ops-nightsField'), '2');
      expect(text(tester, 'ops-unitPrice'), '500,000');
      await enter(tester, 'ops-nightsField', '3');
      await tester.pumpAndSettle();
      expect(text(tester, 'ops-endLocal'), '2026-10-13 12:00');
      expect(
        find.textContaining('3 nights × 500,000 VND = 1,500,000 VND'),
        findsOneWidget,
      );
      await enter(tester, 'ops-endLocal', '2026-10-11 11:00');
      await tester.pumpAndSettle();
      expect(text(tester, 'ops-nightsField'), '1');
      await enter(tester, 'ops-unitPrice', '450000');
      await enter(tester, 'ops-nightsField', '2');
      await tester.pumpAndSettle();
      expect(text(tester, 'ops-endLocal'), '2026-10-12 11:00');
      await press(tester, 'Review calculation');
      expect(find.text('900,000 VND'), findsWidgets);
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings.single['totalPrice'], 900000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('per hour: hours × the price per hour, saved with the booking', (
    tester,
  ) async {
    final s = await openNew(tester);
    await tapKey(tester, 'booking-pricing-hourly');
    await enter(tester, 'ops-endLocal', '2026-10-10 16:30');
    await tester.pumpAndSettle();
    expect(text(tester, 'ops-unitPrice'), '100,000');
    expect(
      find.textContaining('2.5 hours × 100,000 VND = 250,000 VND'),
      findsOneWidget,
    );
    await enter(tester, 'ops-unitPrice', '80000');
    await tester.pumpAndSettle();
    expect(find.textContaining('= 200,000 VND'), findsOneWidget);
    await press(tester, 'Review calculation');
    await press(tester, 'Confirm and save');
    final b = s.operationalBookings.single;
    expect(
      [b['totalPrice'], b['pricingType'], b['hourlyPrice']],
      [200000, 'hourly', 80000],
    );
  });

  testWidgets(
    'without "Đổi giá" the price box shows the room price and cannot be changed',
    (tester) async {
      await openNew(tester, role: 'receptionist');
      final box = tester.widget<TextFormField>(
        find.byKey(const ValueKey('ops-unitPrice')),
      );
      expect(box.enabled, isFalse);
      expect(text(tester, 'ops-unitPrice'), '500,000');
      expect(
        find.text('Room price. Changing it needs "Change prices".'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('booking-custom-nights')), findsNothing);
    },
  );

  // Speed (2026-10-09): the form opens at once with the options shown last
  // time; the server's answer replaces them; a refusal still closes it.
  testWidgets('the booking form opens at once the second time', (tester) async {
    final s = store()..previewToday = '2026-10-04';
    s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
    Completer<void>? hold;
    Object? refuse;
    final service = TeamService(
      transport: (name, data) async {
        if (name == 'bookingWorkspace' && data['action'] == 'rooms') {
          if (hold != null) await hold!.future;
          if (refuse != null) throw refuse!;
        }
        return s.call(name, data);
      },
    );
    await mountReview(
      tester,
      BookingWorkspaceScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        accountId: 'owner',
        service: service,
        onBack: () {},
      ),
    );
    await press(tester, 'New booking');
    expect(find.byKey(const ValueKey('ops-guest')), findsOneWidget);
    await press(tester, 'Cancel');
    // The server is slow now: the form is there before its answer.
    hold = Completer<void>();
    await press(tester, 'New booking');
    expect(find.byKey(const ValueKey('ops-guest')), findsOneWidget);
    expect(text(tester, 'ops-unitPrice'), '500,000');
    hold?.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ops-guest')), findsOneWidget);
    await press(tester, 'Cancel');
    // Access removed meanwhile: the fresh answer closes the form.
    hold = null;
    refuse = FirebaseFunctionsException(
      code: 'permission-denied',
      message: 'booking_permission-denied',
    );
    await press(tester, 'New booking');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ops-guest')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Speed (2026-10-09): a stay opened from the calendar shows what the
  // calendar knows at once, then the booking itself.
  testWidgets(
    'a booking from the calendar shows its guest and dates while it loads',
    (tester) async {
      final hold = Completer<void>();
      final s = store();
      final service = TeamService(
        transport: (name, data) async {
          await hold.future;
          return s.call(name, data);
        },
      );
      await mountReview(
        tester,
        BookingWorkspaceScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          accountId: 'owner',
          service: service,
          initialRecordId: 'missing',
          onClose: () {},
          preview: const ['Anh', '10/10 14:00 – 12/10 12:00', 'Upcoming'],
        ),
        // Still loading: the progress bar never settles.
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      final preview = find.byKey(const ValueKey('booking-preview'));
      expect(preview, findsOneWidget);
      expect(
        find.descendant(
          of: preview,
          matching: find.text('10/10 14:00 – 12/10 12:00'),
        ),
        findsOneWidget,
      );
      hold.complete();
      await tester.pumpAndSettle();
      expect(preview, findsNothing, reason: 'gone once the server answered');
      expect(tester.takeException(), isNull);
    },
  );

  // 2026-10-09 (Tom): saved nightly prices, one list per building, as chips.
  testWidgets(
    'saved prices: saved, tapped, removed; the room price is always a chip',
    (tester) async {
      final s = await openNew(tester);
      final save = find.byKey(const ValueKey('booking-save-price'));
      // The room's own price is a chip (no ×) and is already in the box.
      final own = find.byKey(const ValueKey('booking-saved-price-500000'));
      expect(tester.widget<InputChip>(own).onDeleted, isNull);
      expect(tester.widget<ActionChip>(save).onPressed, isNull);
      await enter(tester, 'ops-unitPrice', '650000');
      await tester.pumpAndSettle();
      await tapKey(tester, 'booking-save-price');
      expect(s.buildingPriceLists['riverside'], [650000]);
      final chip = find.byKey(const ValueKey('booking-saved-price-650000'));
      expect(chip, findsOneWidget);
      expect(tester.widget<ActionChip>(save).onPressed, isNull);
      // Another price typed, then the saved one tapped.
      await enter(tester, 'ops-unitPrice', '480000');
      await tester.pumpAndSettle();
      await tapKey(tester, 'booking-saved-price-650000');
      expect(text(tester, 'ops-unitPrice'), '650,000');
      expect(tester.widget<InputChip>(chip).selected, isTrue);
      await press(tester, 'Review calculation');
      expect(find.text('1,300,000 VND'), findsWidgets);
      await press(tester, 'Edit');
      // Removed with its ×.
      await reveal(tester, chip);
      await tester.tap(
        find.descendant(
          of: chip,
          matching: find.byTooltip('Remove this price'),
        ),
      );
      await tester.pumpAndSettle();
      expect(s.buildingPriceLists['riverside'], isEmpty);
      expect(chip, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  // Tom (2026-10-09): a saved price is still there for the next booking and
  // for every room of the building.
  testWidgets('saved prices stay for the next booking and every room', (
    tester,
  ) async {
    final s = await openNew(tester);
    await enter(tester, 'ops-unitPrice', '650000');
    await tester.pumpAndSettle();
    await tapKey(tester, 'booking-save-price');
    await press(tester, 'Cancel');
    await press(tester, 'New booking');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('booking-saved-price-650000')),
      findsOneWidget,
    );
    // The other room of the building (no price of its own) shows it too.
    await tapKey(tester, 'booking-room-room-101');
    expect(
      find.byKey(const ValueKey('booking-saved-price-650000')),
      findsOneWidget,
    );
    expect(s.buildingPriceLists.keys, ['riverside']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saved prices: a building starts with its defaults; removed ones stay removed',
    (tester) async {
      final s = store()..defaultNightPrices = [300000, 400000];
      final rooms = await s.call('bookingWorkspace', {
        'action': 'rooms',
        'organizationId': 'preview',
        'buildingId': 'riverside',
      });
      for (final r in rooms['records'] as List) {
        expect((r as Map)['savedNightPricesMinor'], [300000, 400000]);
      }
      await s.call('bookingWorkspace', {
        'action': 'prices',
        'organizationId': 'preview',
        'buildingId': 'riverside',
        'priceMinor': 300000,
        'remove': true,
      });
      expect(s.nightPricesOf('riverside'), [400000]);
    },
  );

  testWidgets(
    'different price each night: a chip fills every night, the ▾ one night, new ones are saved',
    (tester) async {
      final s = await openNew(tester, saved: [450000, 650000]);
      await enter(tester, 'ops-endLocal', '2026-10-13 12:00');
      await tester.pumpAndSettle();
      await tapKey(tester, 'booking-custom-nights');
      // Every night at once.
      await tapKey(tester, 'booking-all-nights-price-450000');
      for (var i = 0; i < 3; i++) {
        expect(text(tester, 'ops-night-$i'), '450,000');
      }
      // One night from its ▾.
      await tapKey(tester, 'booking-night-menu-1');
      await tester.tap(
        find.byKey(const ValueKey('booking-night-1-price-650000')),
      );
      await tester.pumpAndSettle();
      expect(text(tester, 'ops-night-1'), '650,000');
      // A typed price is saved from its ▾ …
      await enter(tester, 'ops-night-2', '520000');
      await tester.pumpAndSettle();
      await tapKey(tester, 'booking-night-menu-2');
      await tester.tap(find.byKey(const ValueKey('booking-night-2-save')));
      await tester.pumpAndSettle();
      expect(s.buildingPriceLists['riverside'], [450000, 520000, 650000]);
      // … or all new nights at once.
      await enter(tester, 'ops-night-0', '530000');
      await enter(tester, 'ops-night-2', '540000');
      await tester.pumpAndSettle();
      await tapKey(tester, 'booking-save-night-prices');
      expect(s.buildingPriceLists['riverside'], [
        450000,
        520000,
        530000,
        540000,
        650000,
      ]);
      await press(tester, 'Review calculation');
      await press(tester, 'Confirm and save');
      expect(
        s.operationalBookings.single['totalPrice'],
        530000 + 650000 + 540000,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saved prices: without "Đổi giá" prices are picked, not typed; nothing is saved',
    (tester) async {
      final s = await openNew(tester, role: 'receptionist', saved: [450000]);
      expect(find.byKey(const ValueKey('booking-save-price')), findsNothing);
      final chip = find.byKey(const ValueKey('booking-saved-price-450000'));
      expect(tester.widget<InputChip>(chip).onDeleted, isNull);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('ops-unitPrice')))
            .enabled,
        isFalse,
      );
      await tapKey(tester, 'booking-saved-price-450000');
      expect(text(tester, 'ops-unitPrice'), '450,000');
      // Each night too, from the list only.
      await tapKey(tester, 'booking-custom-nights');
      await tapKey(tester, 'booking-night-menu-1');
      await tester.tap(
        find.byKey(const ValueKey('booking-night-1-price-500000')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('booking-night-1-save')), findsNothing);
      await press(tester, 'Review calculation');
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings.single['totalPrice'], 450000 + 500000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('saved prices: a full list says so and keeps the form', (
    tester,
  ) async {
    final s = await openNew(
      tester,
      saved: [for (var i = 1; i <= 12; i++) i * 100000],
    );
    await enter(tester, 'ops-unitPrice', '950000');
    await tester.pumpAndSettle();
    await tapKey(tester, 'booking-save-price');
    expect(
      find.text('This building already has 12 saved prices. Remove one first.'),
      findsOneWidget,
    );
    expect(s.buildingPriceLists['riverside'], hasLength(12));
    expect(text(tester, 'ops-unitPrice'), '950,000');
  });

  // Fix 5 (2026-10-09, Tom): an agreed room price with "Đổi giá" and a reason;
  // the booking keeps the calculated price and who changed it.
  testWidgets(
    'agreed price: needs a reason; saved with the calculated price; kept by an edit without "Đổi giá"',
    (tester) async {
      final s = await openNew(tester);
      expect(find.byKey(const ValueKey('ops-agreedPrice')), findsNothing);
      await tapKey(tester, 'booking-agreed');
      // Starts from the calculated room price: 2 nights × 500,000.
      expect(text(tester, 'ops-agreedPrice'), '1,000,000');
      expect(
        find.text('Calculated: 1,000,000 VND. Surcharges are added on top.'),
        findsOneWidget,
      );
      await enter(tester, 'ops-agreedPrice', '900000');
      await press(tester, 'Review calculation');
      // No reason: not checked, nothing saved.
      expect(find.byKey(const ValueKey('booking-quote')), findsNothing);
      expect(find.text('Enter a valid value.'), findsWidgets);
      await enter(tester, 'ops-agreedReason', 'Regular guest');
      await press(tester, 'Review calculation');
      final quote = find.byKey(const ValueKey('booking-quote'));
      expect(
        find.descendant(of: quote, matching: find.text('Agreed room price')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: quote, matching: find.text('1,000,000 VND')),
        findsOneWidget,
        reason: 'the calculated price',
      );
      expect(
        find.descendant(of: quote, matching: find.text('Regular guest')),
        findsOneWidget,
      );
      await press(tester, 'Confirm and save');
      var b = s.operationalBookings.single;
      expect(b['totalPrice'], 900000);
      expect(
        [
          (b['priceOverride'] as Map)['total'],
          (b['priceOverride'] as Map)['calculatedTotal'],
          (b['priceOverride'] as Map)['reason'],
        ],
        [900000, 1000000, 'Regular guest'],
      );
      // The details say who changed it and why.
      expect(find.text('Changed by'), findsOneWidget);
      expect(find.text('Preview owner'), findsOneWidget);
      // A receptionist edits the booking: the agreed price stays as it is.
      s.workspaceRole = 'receptionist';
      await press(tester, 'Edit');
      expect(find.byKey(const ValueKey('booking-agreed')), findsNothing);
      expect(find.byKey(const ValueKey('booking-agreed-kept')), findsOneWidget);
      await enter(tester, 'ops-guest', 'Anh Tuan');
      await press(tester, 'Review calculation');
      await press(tester, 'Confirm and save');
      b = s.operationalBookings.single;
      expect(b['guestName'], 'Anh Tuan');
      expect(b['totalPrice'], 900000);
      expect((b['priceOverride'] as Map)['byName'], 'Preview owner');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('agreed price: switched off goes back to the calculated price', (
    tester,
  ) async {
    final s = await openNew(tester);
    await tapKey(tester, 'booking-agreed');
    await enter(tester, 'ops-agreedPrice', '800000');
    await enter(tester, 'ops-agreedReason', 'Long stay');
    await press(tester, 'Review calculation');
    await press(tester, 'Confirm and save');
    expect(s.operationalBookings.single['totalPrice'], 800000);
    await press(tester, 'Edit');
    final agreed = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('booking-agreed')),
    );
    expect(agreed.value, isTrue);
    expect(text(tester, 'ops-agreedPrice'), '800,000');
    expect(text(tester, 'ops-agreedReason'), 'Long stay');
    await tapKey(tester, 'booking-agreed');
    await press(tester, 'Review calculation');
    await press(tester, 'Confirm and save');
    final b = s.operationalBookings.single;
    expect(b['totalPrice'], 1000000);
    expect(b['priceOverride'], isNull);
    expect(find.text('Changed by'), findsNothing);
  });

  testWidgets('agreed price: not offered without "Đổi giá"', (tester) async {
    await openNew(tester, role: 'receptionist');
    expect(find.byKey(const ValueKey('booking-agreed')), findsNothing);
    expect(find.byKey(const ValueKey('ops-agreedPrice')), findsNothing);
  });

  // 2026-10-04: no custom total; the deposit says how and when it was paid and
  // is taken off the total.
  testWidgets(
    'no custom total; a deposit by transfer on a day is taken off the total and saved as a payment',
    (tester) async {
      final s = await openNew(tester);
      for (final gone in [
        'ops-overridePrice',
        'ops-overrideReason',
        'ops-depositNote',
      ]) {
        expect(find.byKey(ValueKey(gone)), findsNothing, reason: gone);
      }
      // How and when show up once there is an amount.
      expect(find.byKey(const ValueKey('booking-deposit-cash')), findsNothing);
      await enter(tester, 'ops-depositAmount', '300000');
      await tester.pumpAndSettle();
      expect(text(tester, 'ops-depositDate'), '2026-10-04');
      await tapKey(tester, 'booking-deposit-bankTransfer');
      expect(find.text('Transfer date (YYYY-MM-DD)'), findsOneWidget);
      // Not a day in the future.
      await enter(tester, 'ops-depositDate', '2026-10-05');
      await press(tester, 'Review calculation');
      await reveal(tester, find.byKey(const ValueKey('ops-depositDate')));
      expect(
        find.text('Enter a day up to today (YYYY-MM-DD).'),
        findsOneWidget,
      );
      await enter(tester, 'ops-depositDate', '2026-10-03');
      await press(tester, 'Review calculation');
      // 2 nights × 500,000 = 1,000,000; minus the 300,000 deposit = 700,000.
      await reveal(
        tester,
        find.byKey(const ValueKey('booking-quote-remaining')),
      );
      expect(find.text('− 300,000 VND'), findsOneWidget);
      expect(find.text('700,000 VND'), findsOneWidget);
      await press(tester, 'Confirm and save');
      final b = s.operationalBookings.single;
      expect([b['totalPrice'], b['paidAmount']], [1000000, 300000]);
      expect(b['depositPayment'], {
        'amount': 300000,
        'paymentMethod': 'bankTransfer',
        'paidOn': '2026-10-03',
      });
      expect(
        find.text('300,000 VND · Bank transfer · 2026-10-03'),
        findsOneWidget,
      );
      expect(find.text('700,000 VND'), findsOneWidget);
      // Editing shows the deposit but does not take another one.
      final edit = find.byIcon(Icons.edit_outlined);
      await reveal(tester, edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await reveal(
        tester,
        find.byKey(const ValueKey('booking-deposit-recorded')),
      );
      expect(
        find.text('Deposit received: 300,000 VND · Bank transfer · 2026-10-03'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('ops-depositAmount')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a deposit larger than the total is caught at the price check', (
    tester,
  ) async {
    final s = await openNew(tester);
    await enter(tester, 'ops-depositAmount', '1000001');
    await press(tester, 'Review calculation');
    expect(find.text('The deposit is more than the total.'), findsOneWidget);
    expect(find.byKey(const ValueKey('booking-quote')), findsNothing);
    expect(s.operationalBookings, isEmpty);
    // All of it up front is fine; cash is the default.
    await enter(tester, 'ops-depositAmount', '1000000');
    await press(tester, 'Review calculation');
    await press(tester, 'Confirm and save');
    expect(
      s.operationalBookings.single['depositPayment']['paymentMethod'],
      'cash',
    );
    expect(s.operationalBookings.single['paidAmount'], 1000000);
  });

  testWidgets(
    'Vietnamese: hours read "3 giờ", the deposit reads "Tiền cọc" with Tiền mặt / Chuyển khoản / Thẻ',
    (tester) async {
      final s = store()..previewToday = '2026-10-04';
      s.rooms.last.addAll({
        'rentalMode': 'both',
        'hourlyPrice': 100000,
        'dailyPrice': 500000,
        'currency': 'VND',
      });
      await mountReview(
        tester,
        BookingWorkspaceScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          accountId: 'owner',
          service: s.service,
          onBack: () {},
        ),
        language: 'vi',
      );
      await press(tester, 'Đặt phòng mới');
      await enter(tester, 'ops-startLocal', '2026-10-10 14:00');
      await enter(tester, 'ops-endLocal', '2026-10-10 17:00');
      await tapKey(tester, 'booking-pricing-hourly');
      expect(
        find.textContaining('3 giờ × 100,000 VND = 300,000 VND'),
        findsOneWidget,
      );
      expect(find.textContaining('số giờ'), findsNothing);
      await enter(tester, 'ops-depositAmount', '100000');
      await tester.pumpAndSettle();
      for (final label in ['Tiền mặt', 'Chuyển khoản', 'Thẻ']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Ngày trả cọc (YYYY-MM-DD)'), findsOneWidget);
      await tapKey(tester, 'booking-deposit-bankTransfer');
      expect(find.text('Ngày chuyển khoản (YYYY-MM-DD)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // 2026-10-04: a surcharge is per room (once) or per person (× guests, once).
  testWidgets(
    'a per-person surcharge is its price × the guests; a per-room one is once',
    (tester) async {
      final s = await openNew(tester);
      await enter(tester, 'ops-guestCount', '3');
      await tapKey(tester, 'booking-add-surcharge');
      await enter(tester, 'ops-surcharge-0', 'Extra bed');
      await enter(tester, 'ops-surchargeAmount-0', '100000');
      await tapKey(tester, 'booking-add-surcharge');
      await enter(tester, 'ops-surcharge-1', 'Breakfast');
      await enter(tester, 'ops-surchargeAmount-1', '50000');
      await tapKey(tester, 'booking-surcharge-1-person');
      await reveal(
        tester,
        find.byKey(const ValueKey('booking-surcharge-1-total')),
      );
      expect(find.text('50,000 VND × 3 guests = 150,000 VND'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('booking-surcharge-0-total')),
        findsNothing,
      );
      await press(tester, 'Review calculation');
      // 2 nights × 500,000 + 100,000 + 150,000.
      await reveal(tester, find.byKey(const ValueKey('booking-quote')));
      expect(find.text('1,250,000 VND'), findsOneWidget);
      await press(tester, 'Confirm and save');
      final b = s.operationalBookings.single;
      expect(b['totalPrice'], 1250000);
      expect((b['surcharges'] as List)[1], {
        'label': 'Breakfast',
        'amount': 150000,
        'basis': 'person',
        'unitAmount': 50000,
        'count': 3,
      });
      expect(find.text('50,000 VND × 3 guests = 150,000 VND'), findsOneWidget);
      // Editing keeps the line per person, at the price for one guest.
      final edit = find.byIcon(Icons.edit_outlined);
      await reveal(tester, edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(text(tester, 'ops-surchargeAmount-1'), '50,000');
      final chip = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('booking-surcharge-1-person')),
      );
      expect(chip.selected, isTrue);
    },
  );

  testWidgets(
    'a booking shows its room\'s open technical problems and opens them for that room only',
    (tester) async {
      final s = store()..previewToday = '2026-10-04';
      s.rooms.last.addAll({
        'rentalMode': 'both',
        'hourlyPrice': 100000,
        'dailyPrice': 500000,
        'currency': 'VND',
      });
      final roomId = s.rooms.last['id'] as String;
      Map<String, dynamic> problem(
        String id,
        String room,
        String number,
        String title, {
        bool blocks = false,
      }) => {
        'id': id,
        'roomId': room,
        'roomNumber': number,
        'title': title,
        'description': '',
        'status': 'open',
        'blocksRoom': blocks,
        'reportedByName': 'Lan',
        'reportedLocalDate': '2026-10-03',
        'photos': const [],
      };
      final service = TeamService(
        transport: (name, data) async {
          if (name == 'technicalProblems') {
            return {
              'records': [
                problem('p1', roomId, '102', 'Leaking tap', blocks: true),
                problem('p2', 'elsewhere', '9', 'Other room broken'),
              ],
              'rooms': [
                {'id': roomId, 'roomNumber': '102', 'blocked': true},
                {'id': 'elsewhere', 'roomNumber': '9', 'blocked': false},
              ],
              'accounts': const [],
              'currency': 'VND',
              'today': '2026-10-04',
              'canReport': true,
              'canManage': true,
              'canExpense': false,
              'uid': 'u',
              'drive': {'state': 'none'},
            };
          }
          return s.call(name, data);
        },
      );
      await mountReview(
        tester,
        BookingWorkspaceScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          accountId: 'owner',
          service: service,
          onBack: () {},
        ),
        size: const Size(1440, 1000),
      );
      await press(tester, 'New booking');
      await enter(tester, 'ops-guest', 'Anh');
      await enter(tester, 'ops-startLocal', '2026-10-10 14:00');
      await enter(tester, 'ops-endLocal', '2026-10-12 12:00');
      await press(tester, 'Review calculation');
      await press(tester, 'Confirm and save');
      final section = find.byKey(const ValueKey('room-problems'));
      await reveal(tester, section);
      expect(
        find.descendant(of: section, matching: find.text('Leaking tap')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: section,
          matching: find.text('Room not rented until fixed'),
        ),
        findsOneWidget,
      );
      expect(find.text('Other room broken'), findsNothing);
      await tapKey(tester, 'room-problems-open');
      final dialog = find.byType(Dialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('102 · Leaking tap')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.textContaining('Other room'),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  // 2026-10-04 (Tom): no row of buttons at the end of a booking. "Edit" is on
  // the booking card, "Collect" in the money section, confirming in "…", and
  // only the usual next step (check in / check out) stays at the end.
  testWidgets(
    'a booking keeps one button at the end; the rest sit in their sections',
    (tester) async {
      final s = store();
      // Hourly, like the collect test, so the booking has an amount to collect.
      s.rooms.last.addAll({
        'rentalMode': 'hourly',
        'hourlyPrice': 100000,
        'currency': 'VND',
      });
      await mountReview(
        tester,
        BookingWorkspaceScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          accountId: 'owner',
          service: s.service,
          onBack: () {},
        ),
        size: const Size(1440, 1000),
      );
      await press(tester, 'New booking');
      await enter(tester, 'ops-guest', 'Guest family');
      await enter(tester, 'ops-startLocal', '2026-10-01 09:00');
      await enter(tester, 'ops-endLocal', '2026-10-01 11:00');
      await press(tester, 'Review calculation');
      await press(tester, 'Confirm and save');
      for (final gone in ['Collect booking payment', 'Confirm booking']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      expect(find.byKey(const ValueKey('booking-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('booking-collect')), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Check in'), findsOneWidget);
      // Confirming is in the "…" menu.
      await tapKey(tester, 'booking-more');
      expect(find.text('Confirm booking'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      // "Edit" on the card opens the form.
      await tapKey(tester, 'booking-edit');
      expect(find.byKey(const ValueKey('ops-guest')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // 2026-10-05 (Tom): an overnight stay starts per night, a same-day stay per
  // hour, until staff pick one themselves.
  testWidgets('a new booking picks per night or per hour from its dates', (
    tester,
  ) async {
    final s = store();
    s.rooms.last.addAll({
      'rentalMode': 'both',
      'hourlyPrice': 100000,
      'dailyPrice': 500000,
      'currency': 'VND',
    });
    await mountReview(
      tester,
      BookingWorkspaceScreen(
        organizationId: 'preview',
        buildingId: 'riverside',
        accountId: 'owner',
        service: s.service,
        onBack: () {},
      ),
    );
    bool picked(String type) => tester
        .widget<ChoiceChip>(find.byKey(ValueKey('booking-pricing-$type')))
        .selected;
    await press(tester, 'New booking');
    await enter(tester, 'ops-startLocal', '2026-10-10 14:00');
    await enter(tester, 'ops-endLocal', '2026-10-11 12:00');
    await tester.pumpAndSettle();
    expect(picked('nightly'), isTrue);
    await enter(tester, 'ops-endLocal', '2026-10-10 17:00');
    await tester.pumpAndSettle();
    expect(picked('hourly'), isTrue);
    // Picked by hand: the dates no longer change it.
    await tapKey(tester, 'booking-pricing-nightly');
    await enter(tester, 'ops-endLocal', '2026-10-10 18:00');
    await tester.pumpAndSettle();
    expect(picked('nightly'), isTrue);
  });
}
