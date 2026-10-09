import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_money.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payment_command_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/payment_action_form.dart';
import 'payment_action_form_test.dart' show invoice;
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;

void main() {
  testWidgets(
    'rejected restored payment does not relabel the old amount in a new currency',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final money = OrganizationMoney.shared;
      money.clear();
      addTearDown(money.clear);
      money.configure(
        'org',
        'USD',
        ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 25000}, dates: {}),
      );
      var attempts = 0;
      final service = PaymentCommandService(
        transport: (_, data) async {
          attempts++;
          if (attempts == 1) throw StateError('lost response');
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'payment_currency_changed',
          );
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
      final amount = find.byKey(const ValueKey('payment-amount'));
      await reveal(tester, amount);
      await tester.enterText(amount, '10.25');
      await press(tester, 'Confirm recording');
      money.configure(
        'org',
        'VND',
        ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 27000}, dates: {}),
      );
      await mountReview(tester, form());
      await press(tester, 'Retry the same operation');
      final field = tester.widget<TextField>(
        find.descendant(of: amount, matching: find.byType(TextField)),
      );
      expect(field.decoration?.labelText, contains('USD'));
      expect(field.controller!.text, '10.25');
      expect(field.readOnly, isTrue);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm recording'),
            )
            .onPressed,
        isNull,
      );
      expect(attempts, 2);
    },
  );
  testWidgets(
    'converted payment retry preserves original entered currency after settings change',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final money = OrganizationMoney.shared;
      money.clear();
      addTearDown(money.clear);
      final ratesId = List.filled(64, 'a').join();
      money.configure(
        'org',
        'USD',
        ExchangeRateSnapshot(
          perUsd: {'USD': 1, 'VND': 25000},
          dates: {},
          snapshotId: ratesId,
        ),
      );
      final calls = <Map<String, dynamic>>[];
      final service = PaymentCommandService(
        transport: (_, data) async {
          calls.add(data);
          if (calls.length == 1) throw StateError('lost response');
          return {
            'operationId': data['operationId'],
            'recordedAt': '2026-10-08T12:00:00Z',
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
      final amount = find.byKey(const ValueKey('payment-amount'));
      await reveal(tester, amount);
      await tester.enterText(amount, '10.25');
      await press(tester, 'Confirm recording');
      expect(calls.single['amountMinor'], 256250);
      expect(calls.single['inputCurrency'], 'USD');
      expect(calls.single['inputAmountMinor'], 1025);
      expect(calls.single['ratesId'], ratesId);
      money.configure(
        'org',
        'VND',
        ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 27000}, dates: {}),
      );
      await mountReview(tester, form());
      expect(tester.widget<TextFormField>(amount).controller!.text, '10.25');
      await press(tester, 'Retry the same operation');
      expect(calls[1], calls[0]);
      expect(find.text('The server confirmed this operation.'), findsOneWidget);
    },
  );
}
