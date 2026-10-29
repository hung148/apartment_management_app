import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/payment_corrections.dart';
import '../team/team_review_test.dart' show mountReview;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'payment icon selects the exact receipt and returns after saving',
    (tester) async {
      Map<String, dynamic>? saved;
      var refreshed = false;
      final service = TeamService(
        transport: (name, data) async {
          if (data['action'] == 'correctReceipt') {
            saved = data;
            return {};
          }
          return {
            'records': [
              for (final id in ['first', 'second'])
                {
                  'paymentId': id,
                  'receiptId': 'booking',
                  'revision': 'v-$id',
                  'amountMinor': id == 'first' ? 100000 : 200000,
                  'currency': 'VND',
                  'paidOn': '2026-10-14',
                  'note': 'Note $id',
                },
            ],
          };
        },
      );
      await mountReview(
        tester,
        PaymentCorrectionsButton(
          service: service,
          organizationId: 'o',
          buildingId: 'b',
          bookingId: 'k',
          paymentId: 'second',
          iconOnly: true,
          onSaved: () async {
            refreshed = true;
          },
        ),
      );
      final icon = find.byKey(const ValueKey('edit-payment-second'));
      expect(tester.widget<IconButton>(icon).tooltip, 'Edit');
      expect(find.text('Edit recorded payments'), findsNothing);
      await tester.tap(icon);
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('receipt-note')))
            .controller!
            .text,
        'Note second',
      );
      await tester.enterText(
        find.byKey(const ValueKey('receipt-amount')),
        '150000',
      );
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();
      expect(saved?['paymentId'], 'second');
      expect(saved?['receiptId'], 'booking');
      expect(saved?['amountMinor'], 150000);
      expect(refreshed, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
  testWidgets('missing exact payment never opens a different receipt', (
    tester,
  ) async {
    final service = TeamService(
      transport: (name, data) async => {
        'records': [
          {
            'paymentId': 'other',
            'receiptId': 'booking',
            'revision': 'v',
            'amountMinor': 100,
            'currency': 'VND',
            'paidOn': '2026-10-14',
            'note': 'Other',
          },
        ],
      },
    );
    await mountReview(
      tester,
      PaymentCorrectionsButton(
        service: service,
        organizationId: 'o',
        buildingId: 'b',
        bookingId: 'k',
        paymentId: 'missing',
        iconOnly: true,
        onSaved: () async {},
      ),
    );
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(
      find.text('This payment is no longer available to edit.'),
      findsOneWidget,
    );
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('Save correction'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
  testWidgets('load failure can retry and empty receipts are explained', (
    tester,
  ) async {
    var fail = true;
    final service = TeamService(
      transport: (name, data) async {
        if (fail)
          throw FirebaseFunctionsException(
            code: 'unavailable',
            message: 'Offline',
          );
        return {'records': []};
      },
    );
    await mountReview(
      tester,
      PaymentCorrectionsButton(
        service: service,
        organizationId: 'o',
        buildingId: 'b',
        tenantId: 't',
        onSaved: () async {},
      ),
    );
    await tester.tap(find.byKey(const ValueKey('edit-recorded-payments')));
    await tester.pumpAndSettle();
    expect(find.text('Could not load payments. Try again.'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Reload'));
    await tester.pumpAndSettle();
    expect(find.text('No recorded payments.'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });
  testWidgets(
    'uncertain correction retries the same request and rejects invalid amounts locally',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (name, data) async {
          if (data['action'] == 'correctReceipt') {
            calls.add(data);
            if (calls.length == 1)
              throw FirebaseFunctionsException(
                code: 'unavailable',
                message: 'Offline',
              );
            return {};
          }
          return {
            'records': [
              {
                'paymentId': 'p',
                'receiptId': 'r',
                'revision': 'v',
                'amountMinor': 300000,
                'currency': 'VND',
                'paidOn': '2026-10-14',
                'note': 'Receipt',
              },
            ],
          };
        },
      );
      await mountReview(
        tester,
        PaymentCorrectionsButton(
          service: service,
          organizationId: 'o',
          buildingId: 'b',
          bookingId: 'k',
          onSaved: () async {},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('edit-recorded-payments')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Receipt'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('receipt-amount')), '0');
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.enterText(
        find.byKey(const ValueKey('receipt-amount')),
        '250000',
      );
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('receipt-amount')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await tester.tap(find.text('Retry same save'));
      await tester.pumpAndSettle();
      expect(calls.length, 2);
      expect(calls[0], calls[1]);
      expect(find.text('Correction saved.'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );
  for (final booking in [true, false]) {
    testWidgets(
      'correct existing ${booking ? 'short stay' : 'lease'} payment',
      (tester) async {
        Map<String, dynamic>? saved;
        var refreshed = false;
        final service = TeamService(
          transport: (name, data) async {
            if (data['action'] == 'correctReceipt') {
              saved = data;
              return {};
            }
            return {
              'records': [
                {
                  'paymentId': 'p',
                  'receiptId': 'r',
                  'revision': 'v',
                  'amountMinor': saved?['amountMinor'] ?? 300000,
                  'currency': 'VND',
                  'paidOn': saved?['paidOn'] ?? '2026-10-14',
                  'note': saved?['note'] ?? 'Original note',
                },
              ],
            };
          },
        );
        await mountReview(
          tester,
          PaymentCorrectionsButton(
            service: service,
            organizationId: 'o',
            buildingId: 'b',
            bookingId: booking ? 'k' : null,
            tenantId: booking ? null : 't',
            onSaved: () async {
              refreshed = true;
            },
          ),
        );
        await tester.tap(find.byKey(const ValueKey('edit-recorded-payments')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Original note'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('receipt-amount')),
          '250000',
        );
        await tester.enterText(
          find.byKey(const ValueKey('receipt-date')),
          '2026-10-13',
        );
        await tester.enterText(
          find.byKey(const ValueKey('receipt-note')),
          'Corrected note',
        );
        await tester.tap(find.text('Save correction'));
        await tester.pumpAndSettle();
        expect(saved?['amountMinor'], 250000);
        expect(saved?['paidOn'], '2026-10-13');
        expect(saved?['receiptId'], 'r');
        expect(find.text('Corrected note'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        expect(refreshed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'populated correction dialog fits languages sizes scales and themes',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final service = TeamService(
        transport: (name, data) async => {
          'records': [
            {
              'paymentId': 'p',
              'receiptId': 'r',
              'revision': 'v',
              'amountMinor': 300000,
              'currency': 'VND',
              'paidOn': '2026-10-14',
              'note': 'Thanh toán một phần — gia đình Nguyễn Thị Minh Anh',
            },
          ],
        },
      );
      for (final language in ['en', 'vi'])
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 900),
        ])
          for (final scale in [1.0, 1.3, 2.0])
            for (final brightness in [Brightness.light, Brightness.dark]) {
              await mountReview(
                tester,
                PaymentCorrectionsButton(
                  service: service,
                  organizationId: 'o',
                  buildingId: 'b',
                  bookingId: 'k',
                  onSaved: () async {},
                ),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await tester.tap(
                find.byKey(const ValueKey('edit-recorded-payments')),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.byType(ListTile));
              await tester.pumpAndSettle();
              expect(
                tester.takeException(),
                isNull,
                reason: '$language $size $scale $brightness',
              );
              if (language == 'vi' &&
                  ((size.width == 320 && scale == 2) ||
                      (size.width == 1440 && scale == 1))) {
                await tester.runAsync(() async {
                  final boundary = tester.renderObject<RenderRepaintBoundary>(
                    find.byKey(const ValueKey('capture')),
                  );
                  final image = await boundary.toImage();
                  final bytes = await image.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
                  await Directory(
                    '.dart_tool/payment-corrections',
                  ).create(recursive: true);
                  await File(
                    '.dart_tool/payment-corrections/$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
              final close = find.text(language == 'vi' ? 'Đóng' : 'Close');
              await tester.ensureVisible(
                find.byKey(const ValueKey('receipt-note')),
              );
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await tester.ensureVisible(close);
              await tester.tap(close);
              await tester.pumpAndSettle();
            }
    },
  );
}
