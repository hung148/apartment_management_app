import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/booking_workspace_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'tenant_lease_test.dart' show store, page, room, fill;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;

Widget booking(TeamService service) => BookingWorkspaceScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  accountId: 'owner',
  service: service,
  initialRoomId: 'room-102',
  startNew: true,
  initialStart: '2026-10-10 14:00',
  initialEnd: '2026-10-13 12:00',
  onClose: () {},
);

Finder field(String key) => find.byKey(ValueKey(key));
Future<void> calculate(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'deposit and payment save together and checked-out status can be edited',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(tester, booking(s.service));
      await calculate(tester);
      await enter(tester, 'ops-guest', 'Nguyễn Minh Anh');
      await enter(tester, 'ops-depositAmount', '200000');
      await enter(tester, 'ops-depositNote', 'Deposit note');
      await reveal(tester, field('booking-deposit-paid'));
      await tester.tap(field('booking-deposit-paid'));
      await tester.pumpAndSettle();
      await enter(tester, 'ops-payAmount', '300000');
      await enter(tester, 'ops-payNote', 'Partial payment note');
      await calculate(tester);
      expect(
        find.descendant(
          of: field('booking-quote-remaining'),
          matching: find.text('1,000,000 VND'),
        ),
        findsOneWidget,
      );
      await reveal(tester, field('booking-stay-checkedOut'));
      await tester.tap(field('booking-stay-checkedOut'));
      await calculate(tester);
      await press(tester, 'Confirm and save');
      final saved = s.operationalBookings.single;
      expect(saved['status'], 'checkedOut');
      expect(saved['paidAmount'], 500000);
      expect(saved['depositNote'], 'Deposit note');
      expect(
        (saved['rentPayments'] as List).single['note'],
        'Partial payment note',
      );
      expect(field('ops-guest'), findsOneWidget);
      await calculate(tester);
      expect(
        tester.widget<TextFormField>(field('ops-payAmount')).controller!.text,
        '',
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: field('ops-depositAmount'),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await reveal(tester, field('booking-stay-checkedIn'));
      await tester.tap(field('booking-stay-checkedIn'));
      await calculate(tester);
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings.single['status'], 'checkedIn');
      expect(s.operationalBookings.single['paidAmount'], 500000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unticked deposit is requested only and ticking requires an amount',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(tester, booking(s.service));
      await calculate(tester);
      await enter(tester, 'ops-guest', 'Guest');
      await reveal(tester, field('booking-deposit-paid'));
      await tester.tap(field('booking-deposit-paid'));
      await calculate(tester);
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings, isEmpty);
      await reveal(tester, field('booking-deposit-paid'));
      await tester.tap(field('booking-deposit-paid'));
      await enter(tester, 'ops-depositAmount', '200000');
      await calculate(tester);
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings.single['depositAmount'], 200000);
      expect(s.operationalBookings.single['paidAmount'], 0);
      expect(s.operationalBookings.single['depositPayment'], isNull);
    },
  );

  testWidgets(
    'narrow enlarged payment totals do not wrap one letter per line',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(
        tester,
        booking(s.service),
        language: 'vi',
        size: const Size(320, 740),
        scale: 2,
      );
      await calculate(tester);
      final total = find.descendant(
        of: field('booking-quote'),
        matching: find.text('Tổng cộng'),
      );
      expect(tester.getSize(total).height, lessThan(130));
    },
  );

  testWidgets(
    'editing during a quote ignores old replies and saves the latest price',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      final oldReply = Completer<void>();
      var hold = false, quotes = 0;
      final service = TeamService(
        transport: (name, data) async {
          final answer = await s.call(name, data);
          if (name == 'bookingWorkspace' && data['action'] == 'quote') {
            quotes++;
            if (hold) {
              hold = false;
              await oldReply.future;
            }
          }
          return answer;
        },
      );
      await mountReview(tester, booking(service));
      await calculate(tester);
      await enter(tester, 'ops-guest', 'Main guest');
      final before = quotes;
      hold = true;
      await tester.enterText(field('ops-night-1'), '600000');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(quotes, before + 1);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm and save'),
            )
            .onPressed,
        isNull,
      );
      await tester.enterText(field('ops-night-1'), '650000');
      await tester.pump();
      await calculate(tester);
      expect(
        find.descendant(
          of: field('booking-quote'),
          matching: find.text('1,650,000 VND'),
        ),
        findsWidgets,
      );
      oldReply.complete();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: field('booking-quote'),
          matching: find.text('1,600,000 VND'),
        ),
        findsNothing,
      );
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings.single['nightPrices'], [
        500000,
        650000,
        500000,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed automatic calculation offers retry without losing entered details',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      var fail = true;
      final service = TeamService(
        transport: (name, data) async {
          if (name == 'bookingWorkspace' && data['action'] == 'quote' && fail) {
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'Offline',
            );
          }
          return s.call(name, data);
        },
      );
      await mountReview(tester, booking(service));
      await calculate(tester);
      await enter(tester, 'ops-guest', 'Keep this name');
      expect(field('booking-quote'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm and save'),
            )
            .onPressed,
        isNull,
      );
      fail = false;
      await press(tester, 'Retry calculation');
      await calculate(tester);
      expect(field('booking-quote'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(field('ops-guest')).controller!.text,
        'Keep this name',
      );
      await press(tester, 'Confirm and save');
      expect(s.operationalBookings.single['guestName'], 'Keep this name');
    },
  );

  testWidgets(
    'optional co-guest details save and nightly edits survive adding a night',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(tester, booking(s.service));
      await enter(tester, 'ops-guest', 'Only required name');
      await enter(tester, 'ops-night-1', '600000');
      await enter(tester, 'ops-nightsField', '4');
      await reveal(tester, field('booking-add-guest'));
      await tester.tap(field('booking-add-guest'));
      await tester.pumpAndSettle();
      await enter(tester, 'ops-coGuestId-0', '1234');
      await calculate(tester);
      await press(tester, 'Confirm and save');
      final saved = s.operationalBookings.single;
      expect(saved['nightPrices'], [500000, 600000, 500000, 500000]);
      expect((saved['guests'] as List).single['name'], '');
      expect((saved['guests'] as List).single['idNumber'], '1234');
    },
  );

  testWidgets(
    'long stay payment defaults follow rent until explicitly edited',
    (tester) async {
      final s = store();
      await mountReview(tester, page(s.service));
      await room(tester, 'room-102');
      await fill(tester);
      await tester.pumpAndSettle();
      expect(field('lease-own-amount'), findsNothing);
      expect(field('lease-payment'), findsOneWidget);
      final hint = find.text('Calculated: 1,500,000 VND (rent × 1).');
      final reasonLabel = find.text('Reason for the change');
      expect(
        tester.getRect(reasonLabel).top - tester.getRect(hint).bottom,
        greaterThanOrEqualTo(16),
        reason: 'hint and next label need breathing room',
      );
      await enter(tester, 'lease-rent', '2000000');
      expect(
        tester
            .widget<TextFormField>(field('lease-periodAmount'))
            .controller!
            .text,
        '2,000,000',
      );
      await enter(tester, 'lease-periodAmount', '1800000');
      await enter(tester, 'lease-periodReason', 'Agreed discount');
      await enter(tester, 'lease-rent', '2100000');
      expect(
        tester
            .widget<TextFormField>(field('lease-periodAmount'))
            .controller!
            .text,
        '1,800,000',
      );
      expect(
        find.text('Estimated full-period total: 1,800,000 VND'),
        findsOneWidget,
      );
      await press(tester, 'Create tenant and lease');
      expect(s.tenants.last['periodRentMinor'], 1800000);
    },
  );

  testWidgets(
    'payment sections remain reachable in both languages and window sizes with actual fonts',
    (tester) async {
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
          const Size(1440, 900),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final longStay in [false, true]) {
              final s = store();
              s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
              await mountReview(
                tester,
                longStay ? page(s.service) : booking(s.service),
                language: language,
                size: size,
                scale: scale,
              );
              if (longStay) {
                await room(tester, 'room-102');
                await fill(tester);
                await enter(tester, 'lease-deposit', '500000');
                await enter(tester, 'lease-periodAmount', '1400000');
                await enter(
                  tester,
                  'lease-periodReason',
                  'Khách thuê lâu dài — agreed returning-tenant price',
                );
              } else {
                await enter(
                  tester,
                  'ops-guest',
                  'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông',
                );
                await enter(tester, 'ops-night-1', '650000');
                await enter(tester, 'ops-depositAmount', '200000');
                await enter(
                  tester,
                  'ops-depositNote',
                  'Cọc phòng gia đình Nguyễn Minh Anh — chuyển khoản',
                );
                await reveal(tester, field('booking-deposit-paid'));
                await tester.tap(field('booking-deposit-paid'));
                await enter(tester, 'ops-payAmount', '300000');
                await enter(
                  tester,
                  'ops-payNote',
                  'Thanh toán một phần — khách còn lại trả sau',
                );
                await calculate(tester);
              }
              final payment = field(
                longStay ? 'lease-payment' : 'booking-payment',
              );
              await reveal(tester, payment);
              expect(
                tester.takeException(),
                isNull,
                reason: '$language $size $scale $longStay',
              );
              if (scale == 1 && size.width == 1440 ||
                  scale == 2 && size.width == 320) {
                await tester.runAsync(() async {
                  final boundary = tester.renderObject<RenderRepaintBoundary>(
                    field('capture'),
                  );
                  final image = await boundary.toImage();
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  final dir = Directory('.dart_tool/booking-payment')
                    ..createSync(recursive: true);
                  await File(
                    '${dir.path}/$language-${longStay ? 'long' : 'short'}-${size.width.toInt()}-$scale.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              final save = find.widgetWithText(
                FilledButton,
                longStay
                    ? (language == 'en'
                          ? 'Create tenant and lease'
                          : 'Tạo người thuê và hợp đồng')
                    : (language == 'en'
                          ? 'Confirm and save'
                          : 'Xác nhận và lưu'),
              );
              // Resolve translated button below without requiring a write.
              expect(save, findsOneWidget);
              {
                await reveal(tester, save);
                expect(
                  tester.getRect(save).overlaps(Offset.zero & size),
                  isTrue,
                );
              }
              if (!longStay &&
                  (scale == 1 && size.width == 1440 ||
                      scale == 2 && size.width == 320)) {
                await tester.runAsync(() async {
                  final boundary = tester.renderObject<RenderRepaintBoundary>(
                    field('capture'),
                  );
                  final image = await boundary.toImage();
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await File(
                    '.dart_tool/booking-payment/$language-total-${size.width.toInt()}-$scale.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            }
          }
        }
      }
    },
  );

  // 2026-10-14 (Tom): opening a booking showed "Fill in every price line" in
  // red. A two-hour slot in a room priced only per night now starts as one
  // night, and nothing typed wrong never shows an error.
  testWidgets(
    'a nightly room opened on a two-hour slot starts as one night, without a price error',
    (tester) async {
      final s = store();
      s.rooms.last
        ..remove('hourlyPrice')
        ..addAll({'dailyPrice': 300000, 'currency': 'VND'});
      await mountReview(
        tester,
        BookingWorkspaceScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          accountId: 'owner',
          service: s.service,
          initialRoomId: 'room-102',
          startNew: true,
          initialStart: '2026-10-14 10:00',
          initialEnd: '2026-10-14 12:00',
          onClose: () {},
        ),
        language: 'vi',
      );
      await calculate(tester);
      expect(
        find.text('Hãy điền đủ từng dòng giá, hoặc xóa dòng trống.'),
        findsNothing,
      );
      expect(
        tester.widget<TextFormField>(field('ops-endLocal')).controller!.text,
        '2026-10-15 12:00',
      );
      // "×", not "·", and the total.
      expect(
        find.descendant(
          of: field('booking-quote'),
          matching: find.text('300,000 VND × 1 đêm'),
        ),
        findsOneWidget,
      );
      // An empty surcharge line is not an error either; a half-filled one is.
      await press(tester, 'Thêm phụ phí');
      await calculate(tester);
      expect(field('booking-calculation-message'), findsNothing);
      await enter(tester, 'ops-surchargeAmount-0', '50000');
      await calculate(tester);
      expect(
        find.text('Hãy điền đủ từng dòng giá, hoặc xóa dòng trống.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the agreed price is the whole total, surcharges included', (
    tester,
  ) async {
    final s = store();
    s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
    await mountReview(tester, booking(s.service));
    await calculate(tester);
    await enter(tester, 'ops-guest', 'Anh');
    await press(tester, 'Add surcharge');
    await enter(tester, 'ops-surcharge-0', 'Extra bed');
    await enter(tester, 'ops-surchargeAmount-0', '100000');
    await calculate(tester);
    // 3 nights × 500,000 + 100,000.
    expect(
      find.descendant(
        of: field('booking-quote'),
        matching: find.text('500,000 VND × 3 nights = 1,500,000 VND'),
      ),
      findsOneWidget,
    );
    // No switch (2026-10-14): the calculated total is the grey hint.
    await reveal(tester, field('ops-agreedPrice'));
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: field('ops-agreedPrice'),
              matching: find.byType(TextField),
            ),
          )
          .decoration
          ?.hintText,
      '1,600,000 VND',
    );
    await enter(tester, 'ops-agreedPrice', '1500000');
    await enter(tester, 'ops-agreedReason', 'Regular guest');
    await calculate(tester);
    expect(
      tester.widget<Text>(field('booking-quote-calculated')).data,
      '1,600,000 VND',
    );
    await press(tester, 'Confirm and save');
    final b = s.operationalBookings.single;
    expect(b['totalPrice'], 1500000);
    expect((b['priceOverride'] as Map)['calculatedTotal'], 1600000);
    expect(tester.takeException(), isNull);
  });

  // 2026-10-14 (Tom): the agreed box left at the calculated total is no
  // price change: no reason needed, nothing crossed out, nothing stored.
  testWidgets(
    'an agreed total equal to the calculated one is not a price change',
    (tester) async {
      final s = store();
      s.rooms.last.addAll({'dailyPrice': 500000, 'currency': 'VND'});
      await mountReview(tester, booking(s.service));
      await calculate(tester);
      await enter(tester, 'ops-guest', 'Anh');
      await enter(tester, 'ops-agreedPrice', '1500000');
      await calculate(tester);
      expect(field('ops-agreedReason'), findsNothing);
      expect(field('booking-quote-calculated'), findsNothing);
      expect(find.text('Enter the agreed total and the reason.'), findsNothing);
      await press(tester, 'Confirm and save');
      final b = s.operationalBookings.single;
      expect(b['totalPrice'], 1500000);
      expect(b['priceOverride'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
