import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/booking_workspace_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import '../lease/tenant_lease_test.dart' show store;
import '../team/team_review_test.dart' show mountReview;
import '../property/room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;

Map<String, dynamic> savedBooking() => {
  'id': 'saved',
  'revision': '1:0',
  'buildingId': 'riverside',
  'roomId': 'room-102',
  'roomNumber': '102',
  'guestName': 'Nguyễn Thị Minh Anh — Riverside family',
  'guestPhone': '0901234567',
  'notes': 'Keep notes',
  'currency': 'VND',
  'totalPrice': 500000,
  'paidAmount': 150000,
  'depositAmount': 0,
  'depositPaidAmount': 0,
  'depositRefundedAmount': 0,
  'status': 'checkedIn',
  'pricingType': 'nightly',
  'nightPrices': [500000],
  'startLocal': '2026-10-10 14:00',
  'endLocal': '2026-10-11 12:00',
  'startTime': '2026-10-10T07:00:00Z',
  'endTime': '2026-10-11T05:00:00Z',
  'rentPayments': [
    {
      'paymentId': 'p1',
      'amount': 50000,
      'paidOn': '2026-10-03',
      'paymentMethod': 'cash',
      'note': 'First payment',
    },
    {
      'paymentId': 'p2',
      'amount': 100000,
      'paidOn': '2026-10-04',
      'paymentMethod': 'bankTransfer',
      'note': 'Thanh toán một phần — ghi chú dài của khách',
    },
  ],
  // The payment list (2026-10-24) reads these in the preview store.
  'previewReceipts': [
    {
      'paymentId': 'p1',
      'kind': 'room',
      'paidOn': '2026-10-03',
      'amountMinor': 50000,
      'methodId': 'cash',
      'note': 'First payment',
      'revision': 'r-p1',
    },
    {
      'paymentId': 'p2',
      'kind': 'room',
      'paidOn': '2026-10-04',
      'amountMinor': 100000,
      'methodId': 'bankTransfer',
      'note': 'Thanh toán một phần — ghi chú dài của khách',
      'revision': 'r-p2',
    },
  ],
};
Widget page(TeamService service) => BookingWorkspaceScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  accountId: 'owner',
  initialRecordId: 'saved',
  service: service,
  onBack: () {},
  onClose: () {},
);
TeamService withProblems(dynamic s) => TeamService(
  transport: (name, data) async => name == 'technicalProblems'
      ? {'records': [], 'canReport': true}
      : s.call(name, data),
);
Finder key(String value) => find.byKey(ValueKey(value));
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'direct form edits exact payment without losing unsaved guest and note',
    (tester) async {
      final s = store();
      s.rooms.last['dailyPrice'] = 500000;
      s.operationalBookings.add(savedBooking());
      Map<String, dynamic>? correction;
      final service = TeamService(
        transport: (name, data) async {
          if (data['action'] == 'receipt') correction = Map.of(data);
          return s.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      expect(key('ops-guest'), findsOneWidget);
      expect(key('booking-edit'), findsNothing);
      await enter(tester, 'ops-guest', 'Unsaved guest');
      await enter(tester, 'ops-notes', 'Unsaved note');
      await reveal(tester, key('booking-payment-edit-1'));
      await tester.tap(key('booking-payment-edit-1'));
      await tester.pumpAndSettle();
      await tester.enterText(key('payment-amount'), '125000');
      await tester.tap(key('payment-save'));
      await tester.pumpAndSettle();
      expect(correction?['paymentId'], 'p2');
      expect(correction?['receiptRevision'], 'r-p2');
      expect(s.operationalBookings.single['paidAmount'], 175000);
      expect(
        tester.widget<TextFormField>(key('ops-guest')).controller!.text,
        'Unsaved guest',
      );
      expect(
        tester.widget<TextFormField>(key('ops-notes')).controller!.text,
        'Unsaved note',
      );
      expect(find.textContaining('125,000 VND'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'inline checkout changes only status and preserves unrelated drafts',
    (tester) async {
      final s = store();
      s.rooms.last['dailyPrice'] = 500000;
      s.operationalBookings.add(savedBooking());
      await mountReview(tester, page(withProblems(s)));
      await enter(tester, 'ops-guest', 'Draft guest');
      expect(key('booking-checkout-reason'), findsOneWidget);
      expect(key('booking-cancel-reason'), findsOneWidget);
      expect(
        tester.getTopLeft(key('room-problems-open')).dy,
        lessThan(tester.getTopLeft(key('booking-checkout-section')).dy),
      );
      expect(
        tester.widget<TextFormField>(key('ops-guest')).controller!.text,
        'Draft guest',
      );
      await enter(tester, 'booking-checkout-reason', 'Guest left');
      await reveal(tester, key('booking-checkout'));
      await tester.tap(key('booking-checkout'));
      await tester.pumpAndSettle();
      expect(s.operationalBookings.single['status'], 'checkedOut');
      expect(s.operationalBookings.single['paidAmount'], 150000);
      expect(
        tester.widget<TextFormField>(key('ops-guest')).controller!.text,
        'Draft guest',
      );
      expect(key('ops-guest'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  // Refunds are a payment type now (2026-10-24); see booking_payments_test.
  for (final action in ['cancel']) {
    testWidgets(
      'inline $action validates its own fields and sends the command',
      (tester) async {
        final s = store();
        s.rooms.last['dailyPrice'] = 500000;
        s.operationalBookings.add(savedBooking());
        final commands = <Map<String, dynamic>>[];
        final service = TeamService(
          transport: (name, data) async {
            if (name == 'technicalProblems')
              return {'records': [], 'canReport': true};
            if (data['action'] == 'command') {
              commands.add(Map<String, dynamic>.of(data));
              return {'id': 'saved'};
            }
            return s.call(name, data);
          },
        );
        await mountReview(tester, page(service));
        await reveal(tester, key('booking-$action'));
        await tester.tap(key('booking-$action'));
        await tester.pumpAndSettle();
        expect(commands, isEmpty);
        await enter(tester, 'booking-$action-reason', 'Requested by guest');
        await reveal(tester, key('booking-$action'));
        await tester.tap(key('booking-$action'));
        await tester.pumpAndSettle();
        expect(commands, hasLength(1));
        expect(commands.single['reason'], 'Requested by guest');
        expect(commands.single['command'], 'status');
        expect(commands.single['status'], 'cancelled');
        expect(key('ops-guest'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'inline interrupted command retries the same operation and retains drafts',
    (tester) async {
      final s = store();
      s.rooms.last['dailyPrice'] = 500000;
      s.operationalBookings.add(savedBooking());
      final commands = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (name, data) async {
          if (name == 'technicalProblems')
            return {'records': [], 'canReport': true};
          if (data['action'] == 'command') {
            commands.add(Map<String, dynamic>.of(data));
            if (commands.length == 1)
              throw FirebaseFunctionsException(
                code: 'unavailable',
                message: 'Offline',
              );
            return {'id': 'saved'};
          }
          return s.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await enter(tester, 'ops-guest', 'Unsaved guest');
      await enter(
        tester,
        'booking-cancel-reason',
        'Keep separate cancellation draft',
      );
      await enter(tester, 'booking-checkout-reason', 'Guest left');
      await reveal(tester, key('booking-checkout'));
      await tester.tap(key('booking-checkout'));
      await tester.pumpAndSettle();
      expect(commands, hasLength(1));
      expect(key('booking-checkout'), findsNothing);
      await press(tester, 'Retry identical request');
      expect(commands, hasLength(2));
      expect(commands.last, commands.first);
      expect(
        tester.widget<TextFormField>(key('ops-guest')).controller!.text,
        'Unsaved guest',
      );
      expect(
        tester
            .widget<TextFormField>(key('booking-cancel-reason'))
            .controller!
            .text,
        'Keep separate cancellation draft',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'cancelled bookings show actual status and disable editing and checkout',
    (tester) async {
      final s = store();
      s.rooms.last['dailyPrice'] = 500000;
      s.operationalBookings.add(savedBooking()..['status'] = 'cancelled');
      await mountReview(tester, page(withProblems(s)));
      expect(tester.widget<TextFormField>(key('ops-guest')).enabled, isFalse);
      expect(key('booking-stay-notCheckedIn'), findsNothing);
      expect(
        tester.widget<OutlinedButton>(key('booking-checkout')).onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(key('booking-cancel')).onPressed,
        isNull,
      );
      // Refunds go through "Thêm lần thanh toán" → Hoàn tiền (2026-10-24).
      expect(key('booking-refund-rent'), findsNothing);
      expect(
        tester.widget<OutlinedButton>(key('booking-add-payment')).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final collect in [false, true]) {
    testWidgets('read-only booking preserves collection access: $collect', (
      tester,
    ) async {
      final s = store();
      s.rooms.last['dailyPrice'] = 500000;
      s.operationalBookings.add(savedBooking());
      var quotes = 0;
      final service = TeamService(
        transport: (name, data) async {
          if (name == 'technicalProblems')
            return {'records': [], 'canReport': false};
          if (name == 'bookingWorkspace' && data['action'] == 'quote') quotes++;
          final result = await s.call(name, data);
          if (name == 'bookingWorkspace' && data['action'] == 'receipts') {
            return {...result, 'canCollect': collect, 'canEdit': false};
          }
          if (name == 'bookingWorkspace' && data['action'] == 'read') {
            return {
              ...result,
              'record': {
                ...(result['record'] as Map),
                'canManage': false,
                'canCollect': collect,
                'canRefund': false,
              },
            };
          }
          return result;
        },
      );
      await mountReview(tester, page(service));
      expect(tester.widget<TextFormField>(key('ops-guest')).enabled, isFalse);
      expect(
        tester.widget<OutlinedButton>(key('booking-checkout')).onPressed,
        isNull,
      );
      // The payments are listed either way; adding needs "Thu tiền" and
      // changing one "Sửa lần thanh toán".
      expect(key('booking-payment-row-1'), findsOneWidget);
      expect(key('booking-payment-edit-1'), findsNothing);
      expect(
        tester.widget<OutlinedButton>(key('booking-add-payment')).onPressed,
        collect ? isNotNull : isNull,
      );
      expect(quotes, 0);
      if (collect) {
        await reveal(tester, key('booking-add-payment'));
        await tester.tap(key('booking-add-payment'));
        await tester.pumpAndSettle();
        expect(key('payment-method'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(key('ops-guest')).enabled, isFalse);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'saved form payment icons actions and technical issues fit populated layouts',
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
            final s = store();
            s.rooms.last['dailyPrice'] = 500000;
            s.operationalBookings.add(savedBooking());
            await mountReview(
              tester,
              page(withProblems(s)),
              language: language,
              size: size,
              scale: scale,
            );
            await reveal(tester, key('booking-payment-edit-1'));
            expect(
              key('booking-payment-edit-1').hitTestable(),
              findsOneWidget,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$language $size $scale',
            );
            if (language == 'vi' &&
                ((size.width == 320 && scale == 2) ||
                    (size.width == 1440 && scale == 1))) {
              await tester.runAsync(() async {
                final image = await tester
                    .renderObject<RenderRepaintBoundary>(key('capture'))
                    .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(
                  '.dart_tool/booking-direct',
                ).create(recursive: true);
                await File(
                  '.dart_tool/booking-direct/payment-${size.width.toInt()}-$scale.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            final checkout = key('booking-checkout'),
                cancel = key('booking-cancel');
            expect(
              tester.getTopLeft(checkout).dy,
              lessThan(tester.getTopLeft(cancel).dy),
            );
            await reveal(tester, cancel);
            expect(cancel.hitTestable(), findsOneWidget);
            if (language == 'vi' &&
                ((size.width == 320 && scale == 2) ||
                    (size.width == 1440 && scale == 1))) {
              await tester.runAsync(() async {
                final image = await tester
                    .renderObject<RenderRepaintBoundary>(key('capture'))
                    .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '.dart_tool/booking-direct/actions-${size.width.toInt()}-$scale.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await reveal(tester, key('room-problems-open'));
            expect(key('room-problems-open').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          }
        }
      }
    },
  );
}
