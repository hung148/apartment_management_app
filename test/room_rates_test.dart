import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_rates_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' as staff;
import 'room_directory_test.dart' show directory;

Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  tester
      .state<ScrollableState>(staff.mainScrollable())
      .position
      .jumpTo(0);
  await tester.pumpAndSettle();
  await staff.reveal(tester, finder);
}

Future<void> press(WidgetTester tester, String label) async {
  final finder = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
  );
  await reveal(tester, finder);
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Widget page(TeamService service, {String room = 'room-101'}) => RoomRatesScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  roomId: room,
  service: service,
  onBack: () {},
);
Future<void> enterRate(WidgetTester tester, String field, String value) async {
  final finder = find.byKey(ValueKey('rates-$field'));
  await reveal(tester, finder);
  await tester.enterText(finder, value);
}

void main() {
  testWidgets(
    'missing room prices use pricing guidance, preserving exchange-rate guidance',
    (tester) async {
      for (final language in ['en', 'vi']) {
        final store = TeamPreviewStore();
        final t = AppTranslations(Locale(language));
        await mountReview(tester, page(store.service), language: language);
        // 2026-10-04: every price is optional; empty prices save.
        await press(tester, t['rates_save']);
        expect(find.text(t['rates_saved']), findsOneWidget);
        expect(
          t['rates_required'],
          language == 'en'
              ? 'Refresh exchange rates to calculate complete totals. Original transactions remain visible.'
              : 'Cần cập nhật tỷ giá để tính tổng đầy đủ. Các giao dịch gốc vẫn hiển thị.',
        );
      }
    },
  );
  testWidgets('no rental mode: every room takes short stays and leases', (tester) async {
    final store = TeamPreviewStore();
    store.rooms.first['rentalMode'] = 'monthly';
    await mountReview(tester, page(store.service), language: 'vi', size: const Size(320, 740), scale: 2);
    expect(find.byKey(const ValueKey('rates-selected-mode')), findsNothing);
    expect(find.text('Hình thức cho thuê'), findsNothing);
    await press(tester, 'Lưu giá và hình thức cho thuê');
    expect(store.rooms.first['rentalMode'], 'both');
    expect(tester.takeException(), isNull);
  });
  test(
    'exact dong and cents parsing reads grouping, rejects fractions and oversized amounts',
    () {
      expect(parseRoomRate('0.29', 'USD'), 29);
      expect(parseRoomRate('50000', 'VND'), 50000);
      // Comma between thousands, dot before cents (2026-10-05, Tom).
      expect(parseRoomRate('5,000,000', 'VND'), 5000000);
      expect(parseRoomRate('1,000', 'USD'), 100000);
      for (final text in [
        '-1',
        '0',
        '1.234',
        '12,50',
        'NaN',
        '1e3',
        '100000000000000',
      ]) {
        expect(parseRoomRate(text, 'USD'), isNull);
      }
      expect(parseRoomRate('1.5', 'VND'), isNull);
    },
  );
  testWidgets(
    'directory opens rates, mode requires prices, saves exact cents and hides rates without authority',
    (tester) async {
      final store = TeamPreviewStore();
      store.rooms.first['currency'] = 'USD';
      await mountReview(tester, directory(store.service));
      final button = find.byKey(const ValueKey('rates-room-room-101'));
      await reveal(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await press(tester, 'Save pricing and mode');
      expect(store.rooms.first['roomPrice'], isNull);
      await enterRate(tester, 'roomPrice', '600');
      await enterRate(tester, 'hourlyPrice', '0.29');
      await enterRate(tester, 'nightlyPrice', '20');
      await press(tester, 'Save pricing and mode');
      expect(store.rooms.first['hourlyPrice'], 0.29);
      expect(store.rooms.first['nightlyPrice'], 20);
      expect(store.rooms.first['dailyPrice'], isNull);
      expect(store.rooms.first['rentalMode'], 'both');
      expect(find.text('Pricing and rental mode saved.'), findsOneWidget);
      await press(tester, 'Manage rooms');
      store.priceOverride = false;
      await press(tester, 'Refresh');
      expect(find.byKey(const ValueKey('rates-room-room-101')), findsNothing);
    },
  );
  testWidgets(
    'uncertain price updates retry identically, conflicts require reload, occupied mode shows reason and denial clears',
    (tester) async {
      final store = TeamPreviewStore();
      store.rooms.first['roomPrice'] = 1500000;
      final sent = <Map<String, dynamic>>[];
      String? error, message;
      final service = TeamService(
        transport: (name, data) async {
          if (error != null) {
            throw FirebaseFunctionsException(
              code: error,
              message: message ?? 'test',
            );
          }
          if (data['action'] == 'update') {
            sent.add(Map.of(data));
            final result = await store.call(name, data);
            if (sent.length == 1) throw StateError('lost');
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await press(tester, 'Save pricing and mode');
      await press(tester, 'Retry the same pricing change');
      expect(sent[0], sent[1]);
      error = 'failed-precondition';
      message = 'room_rates_active_bookings';
      await press(tester, 'Save pricing and mode');
      expect(find.textContaining('Finish or cancel'), findsOneWidget);
      error = 'aborted';
      await press(tester, 'Save pricing and mode');
      expect(find.text('Save pricing and mode'), findsNothing);
      expect(find.textContaining('Copy any edits'), findsOneWidget);
      error = null;
      await press(tester, 'Reload pricing');
      error = 'permission-denied';
      await press(tester, 'Save pricing and mode');
      expect(find.byKey(const ValueKey('rates-roomPrice')), findsNothing);
    },
  );
  testWidgets(
    'switching room during save ignores late completion and failed reads recover',
    (tester) async {
      final store = TeamPreviewStore();
      store.rooms.first['roomPrice'] = 1000000;
      final pending = Completer<Map<String, dynamic>>();
      bool denied = false;
      final service = TeamService(
        transport: (name, data) async {
          if (denied) throw StateError('offline');
          return data['action'] == 'update'
              ? pending.future
              : store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await reveal(tester, find.text('Save pricing and mode'));
      await tester.tap(find.text('Save pricing and mode'));
      await tester.pump();
      await mountReview(tester, page(service, room: 'room-102'));
      pending.complete({});
      await tester.pumpAndSettle();
      expect(find.text('102'), findsOneWidget);
      expect(find.text('Pricing and rental mode saved.'), findsNothing);
      denied = true;
      await press(tester, 'Reload pricing');
      expect(find.text('102'), findsNothing);
      denied = false;
      await press(tester, 'Reload pricing');
      expect(find.text('102'), findsOneWidget);
    },
  );
  testWidgets('populated rates fit languages sizes scales and themes', (
    tester,
  ) async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final language in ['en', 'vi']) {
      for (final size in [
        const Size(320, 740),
        const Size(812, 375),
        const Size(1440, 1000),
      ]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          for (final brightness in Brightness.values) {
            final store = TeamPreviewStore();
            store.rooms.first.addAll({
              'roomNumber':
                  'Phòng gia đình Riverside — tầng mười hai hướng sông Hàn',
              'currency': 'USD',
              'rentalMode': 'both',
              'roomPrice': 1200.50,
              'hourlyPrice': 12.50,
              'nightlyPrice': 100,
            });
            final t = AppTranslations(Locale(language));
            await mountReview(
              tester,
              page(store.service),
              language: language,
              size: size,
              scale: scale,
              brightness: brightness,
            );
            await reveal(tester, find.text(t['rates_info']));
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('RATES_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  '../.dart_tool/rates-top-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                ),
              );
            }
            // The box refuses letters and extra dots while typing, so the
            // error is shown for a price of 0 (2026-10-05).
            await enterRate(tester, 'roomPrice', '0');
            await press(tester, t['rates_save']);
            await reveal(tester, find.text(t['rates_invalid']));
            expect(find.text(t['rates_invalid']).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('RATES_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile('../.dart_tool/rates-required-$language-${size.width.toInt()}-$scale-${brightness.name}.png'),
              );
            }
            await enterRate(tester, 'roomPrice', '1200.50');
            await enterRate(tester, 'hourlyPrice', '0');
            await press(tester, t['rates_save']);
            await reveal(tester, find.text(t['rates_invalid']));
            expect(find.text(t['rates_invalid']).hitTestable(), findsOneWidget);
            await enterRate(tester, 'hourlyPrice', '12.50');
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await reveal(tester, find.text(t['rates_save']));
            expect(find.text(t['rates_save']).hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('RATES_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  '../.dart_tool/rates-form-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                ),
              );
            }
          }
        }
      }
    }
  });

  // 2026-10-04: monthly, per night and per hour only.
  testWidgets('an older day price shows as the night price; prices may be empty', (tester) async {
    final store = TeamPreviewStore();
    store.rooms.first.addAll({
      'rentalMode': 'hourly',
      'currency': 'VND',
      'dailyPrice': 450000,
      'dailyPriceThresholdHours': 8,
      'hourlyPrice': null,
    });
    await mountReview(tester, page(store.service));
    for (final gone in ['rates-dailyPrice', 'rates-overnightPrice', 'rates-threshold']) {
      expect(find.byKey(ValueKey(gone)), findsNothing, reason: gone);
    }
    expect(find.text('Price per night'), findsOneWidget);
    expect(find.text('Price per hour'), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('rates-nightlyPrice')));
    expect(
      tester.widget<TextFormField>(find.byKey(const ValueKey('rates-nightlyPrice'))).controller!.text,
      '450,000',
    );
    await enterRate(tester, 'nightlyPrice', '');
    await enterRate(tester, 'hourlyPrice', '120000');
    await press(tester, 'Save pricing and mode');
    expect(store.rooms.first['hourlyPrice'], 120000);
    expect(store.rooms.first['nightlyPrice'], isNull);
    // The old day price and its threshold are cleared.
    expect(store.rooms.first['dailyPrice'], isNull);
    expect(store.rooms.first['dailyPriceThresholdHours'], isNull);
    expect(find.text('Pricing and rental mode saved.'), findsOneWidget);
  });
}
