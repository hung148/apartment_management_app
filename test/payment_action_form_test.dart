import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/payment_action_form.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payment_command_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;
import 'access_editor_test.dart' show choose;

const invoice = {
  'id': 'invoice-101',
  'roomId': 'Riverside — Phòng gia đình dài hạn 101',
  'currency': 'VND',
  'amount': 1000000,
  'paidAmount': 500000,
  'canCollect': true,
  'canRefund': true,
};

class FailedJournal extends PaymentJournal {
  @override
  Future<PaymentOperation?> load(String key) async => null;
  @override
  Future<void> save(String key, PaymentOperation operation) async =>
      throw StateError('storage');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'lost response survives reopening with exact operation and no double payment',
    (tester) async {
      final calls = <Map<String, dynamic>>[];
      final service = PaymentCommandService(
        transport: (_, data) async {
          calls.add(data);
          if (calls.length == 1) throw StateError('lost response after commit');
          return {
            'operationId': data['operationId'],
            'recordedAt': '2026-09-26T12:00:00Z',
          };
        },
      );
      Widget form() => PaymentActionForm(
        key: UniqueKey(),
        organizationId: 'org',
        accountId: 'user',
        invoice: invoice,
        service: service,
        onBack: () {},
        onDenied: () {},
      );
      await mountReview(tester, form());
      await reveal(tester, find.byKey(const ValueKey('payment-amount')));
      await tester.enterText(
        find.byKey(const ValueKey('payment-amount')),
        '250000',
      );
      await press(tester, 'Confirm recording');
      expect(calls.length, 1);
      await mountReview(tester, form());
      expect(
        find.textContaining('Confirmation was not received'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const ValueKey('payment-amount')),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      await press(tester, 'Retry the same operation');
      expect(calls[0], calls[1]);
      expect(find.text('The server confirmed this operation.'), findsOneWidget);
      expect(
        await PaymentJournal().load(
          PaymentJournal().key('user', 'org', 'invoice-101'),
        ),
        isNull,
      );
    },
  );
  testWidgets(
    'storage failure sends nothing and denied access never reports success',
    (tester) async {
      var calls = 0, denied = false;
      final service = PaymentCommandService(
        transport: (_, data) async {
          calls++;
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Denied',
          );
        },
      );
      await mountReview(
        tester,
        PaymentActionForm(
          organizationId: 'org',
          accountId: 'user',
          invoice: invoice,
          service: service,
          journal: FailedJournal(),
          onBack: () {},
          onDenied: () => denied = true,
        ),
      );
      await reveal(tester, find.byKey(const ValueKey('payment-amount')));
      await tester.enterText(
        find.byKey(const ValueKey('payment-amount')),
        '100',
      );
      await press(tester, 'Confirm recording');
      expect(calls, 0);
      await mountReview(
        tester,
        PaymentActionForm(
          key: UniqueKey(),
          organizationId: 'org',
          accountId: 'user',
          invoice: invoice,
          service: service,
          onBack: () {},
          onDenied: () => denied = true,
        ),
      );
      await reveal(tester, find.byKey(const ValueKey('payment-amount')));
      await tester.enterText(
        find.byKey(const ValueKey('payment-amount')),
        '100',
      );
      await press(tester, 'Confirm recording');
      expect(calls, 1);
      expect(denied, isTrue);
      expect(find.text('The server confirmed this operation.'), findsNothing);
      expect(
        await PaymentJournal().load(
          PaymentJournal().key('other-user', 'org', 'invoice-101'),
        ),
        isNull,
      );
    },
  );
  testWidgets('refund requires reason and exact USD cents', (tester) async {
    final calls = <Map<String, dynamic>>[];
    final service = PaymentCommandService(
      transport: (_, data) async {
        calls.add(data);
        return {
          'operationId': data['operationId'],
          'recordedAt': '2026-09-26T12:00:00Z',
        };
      },
    );
    await mountReview(
      tester,
      PaymentActionForm(
        organizationId: 'org',
        accountId: 'user',
        invoice: {...invoice, 'currency': 'USD', 'canCollect': false},
        service: service,
        onBack: () {},
        onDenied: () {},
      ),
    );
    final amount = find.byKey(const ValueKey('payment-amount')),
        reason = find.byKey(const ValueKey('payment-reason'));
    await reveal(tester, amount);
    await tester.enterText(amount, '0.291');
    await press(tester, 'Confirm recording');
    expect(calls, isEmpty);
    await reveal(tester, amount);
    await tester.enterText(amount, '0.29');
    await press(tester, 'Confirm recording');
    expect(calls, isEmpty);
    await reveal(tester, reason);
    await tester.enterText(reason, 'Duplicate charge');
    await press(tester, 'Confirm recording');
    expect(calls.single['amountMinor'], 29);
    expect(calls.single['reason'], 'Duplicate charge');
    expect(calls.single.containsKey('paymentMethod'), isFalse);
  });
  testWidgets(
    'payment form populated and uncertain states fit locales sizes scales themes',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final language in ['en', 'vi']) {
        final t = AppTranslations(Locale(language));
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 1000),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final brightness in Brightness.values) {
              SharedPreferences.setMockInitialValues({});
              await mountReview(
                tester,
                PaymentActionForm(
                  key: UniqueKey(),
                  organizationId: 'org',
                  accountId: 'user',
                  invoice: invoice,
                  service: PaymentCommandService(
                    transport: (_, data) async =>
                        throw StateError('lost response'),
                  ),
                  onBack: () {},
                  onDenied: () {},
                ),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await choose(
                tester,
                'payment-action-collect',
                t['payment_action_refund'],
              );
              await reveal(
                tester,
                find.byKey(const ValueKey('payment-amount')),
              );
              await tester.enterText(
                find.byKey(const ValueKey('payment-amount')),
                '250000',
              );
              await reveal(
                tester,
                find.byKey(const ValueKey('payment-reason')),
              );
              await tester.enterText(
                find.byKey(const ValueKey('payment-reason')),
                'Hoàn lại khoản thanh toán trùng — Riverside phòng gia đình',
              );
              await tester.pumpAndSettle();
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              await press(tester, t['payment_action_confirm']);
              await reveal(tester, find.text(t['payment_action_retry']));
              expect(
                find.text(t['payment_action_retry']).hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              final hint = find.text(t['payment_action_decimal']);
              expect(
                tester.renderObject<RenderParagraph>(hint).didExceedMaxLines,
                isFalse,
                reason: 'Currency precision instructions must not be truncated',
              );
              if (const bool.fromEnvironment('PAYMENT_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/payment-form-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
            }
          }
        }
      }
    },
  );
}
