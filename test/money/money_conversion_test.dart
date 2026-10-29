import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_money.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_money.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/money_conversion.dart';

void main() {
  test('missing rates keep form values in their explicitly labeled original currency', () {
    final form = MoneyForm(MoneyConversion(currency: 'USD', perUsd: {}));
    expect(form.currency('VND'), 'VND');
    expect(form.parseText('125000', 'VND'), 125000);
  });
  test('reference snapshots cannot change when provider maps are mutated', () {
    final rates = <String, double>{'USD': 1, 'VND': 25000};
    final dates = <String, String>{'VND': '2026-10-07'};
    final snapshot = ExchangeRateSnapshot(perUsd: rates, dates: dates);
    rates['VND'] = 27000;
    dates.clear();
    expect(snapshot.convert(25000, 'VND', 'USD'), 1);
    expect(snapshot.dates['VND'], '2026-10-07');
  });
  test(
    'changing currency updates reports and clearing removes report preferences',
    () {
      final money = OrganizationMoney.shared;
      addTearDown(money.clear);
      money.configure(
        'report',
        'USD',
        ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 25000}, dates: {}),
      );
      expect(ReportingMoney.format('report', 5000000, 'VND'), '≈ 200.00 USD');
      money.select('report', 'VND');
      expect(ReportingMoney.format('report', 200, 'USD'), '≈ 5,000,000 VND');
      money.clear();
      expect(ReportingMoney.format('report', 200, 'USD'), '200.00 USD');
    },
  );
  test(
    'active organization display converts once and clears on account change',
    () {
      final money = OrganizationMoney.shared;
      addTearDown(money.clear);
      money.configure(
        'a',
        'USD',
        ExchangeRateSnapshot(perUsd: {'USD': 1, 'VND': 25000}, dates: {}),
      );
      money.activate('a');
      expect(AppMoney.format(5000000, 'VND'), '≈ 200.00 USD');
      expect(AppMoney.format(200, 'USD'), '200.00 USD');
      expect(AppMoney.rawFormat(5000000, 'VND'), '5,000,000 VND');
      money.activate('b');
      expect(AppMoney.format(5000000, 'VND'), '5,000,000 VND');
      money.clear();
      expect(AppMoney.displayConversion, isNull);
    },
  );

  final usd = MoneyConversion(
    currency: 'USD',
    perUsd: {'VND': '25000'},
    date: '2026-10-07',
  );
  test(
    'minor-unit conversion uses exact rates and symmetric half rounding',
    () {
      expect(usd.convertMinor(5000000, 'VND', 'USD'), 20000);
      expect(usd.convertMinor(20000, 'USD', 'VND'), 5000000);
      expect(usd.convertMinor(125, 'VND', 'USD'), 1);
      expect(usd.convertMinor(-125, 'VND', 'USD'), -1);
      expect(usd.convertMinor(124, 'VND', 'USD'), 0);
      expect(usd.convertMinor(123, 'VND', 'VND'), 123);
      expect(() => usd.convertMinor(1, 'EUR', 'USD'), throwsStateError);
    },
  );
  test(
    'unchanged fields retain different exact originals despite equal display rounding',
    () {
      final a = MoneyInputBinding(
        conversion: usd,
        sourceCurrency: 'VND',
        originalMinor: 5000001,
      );
      final b = MoneyInputBinding(
        conversion: usd,
        sourceCurrency: 'VND',
        originalMinor: 5000002,
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      expect(a.controller.text, '200.00');
      expect(b.controller.text, a.controller.text);
      expect(a.sourceMinor, 5000001);
      expect(b.sourceMinor, 5000002);
      a.controller.text = '201.25';
      expect(a.sourceMinor, 5031250);
      expect(b.sourceMinor, 5000002);
    },
  );
  test(
    'new input and clear use selected currency without changing rate snapshot',
    () {
      final rates = {'VND': '25000'};
      final snapshot = MoneyConversion(currency: 'USD', perUsd: rates);
      final field = MoneyInputBinding(
        conversion: snapshot,
        sourceCurrency: 'VND',
      );
      addTearDown(field.dispose);
      rates['VND'] = '27000';
      field.controller.text = '10.00';
      expect(field.sourceMinor, 250000);
      field.controller.clear();
      expect(field.sourceMinor, isNull);
      field.controller.text = 'bad';
      expect(field.sourceMinor, isNull);
    },
  );
}
