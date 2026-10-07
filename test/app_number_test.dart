import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_number.dart';

// One number style in every language (Tom, 2026-10-05): money with a comma
// between thousands and a dot before cents; kWh and other quantities with no
// thousands mark and a dot for decimals; money boxes group while typing.
void main() {
  test('money: comma thousands, dot cents, the currency after', () {
    expect(appMoneyMinor(5000000, 'VND'), '5,000,000 VND');
    expect(appMoneyMinor(200050, 'USD'), '2,000.50 USD');
    expect(appMoney(1660000, 'VND'), '1,660,000 VND');
    expect(appMoneyInputText(5000000, 'VND'), '5,000,000');
    expect(appMoneyInputText(200050, 'USD'), '2,000.50');
    expect(appMoneyInputValue(500000, 'VND'), '500,000');
  });

  test('quantities: no thousands mark, a dot for decimals', () {
    expect(appQuantityMilli(1200000), '1200');
    expect(appQuantityMilli(1200500), '1200.5');
    expect(appQuantityMilli(250), '0.25');
    expect(appQuantity(2.5, decimals: 2), '2.5');
    expect(appQuantity(3), '3');
  });

  test('typed money is read with or without the commas', () {
    expect(appParseMoney('5,000,000', 'VND'), 5000000);
    expect(appParseMoney('5000000', 'VND'), 5000000);
    expect(appParseMoney('5.000.000', 'VND'), 5000000, reason: 'older style');
    expect(appParseMoney('2,000.50', 'USD'), 200050);
    expect(appParseMoney('2000.5', 'USD'), 200050);
    expect(appParseMoney('0', 'VND'), 0);
    for (final bad in ['', '5,00', '1.5', '-5', 'abc', '5,000,000.5']) {
      expect(appParseMoney(bad, 'VND'), isNull, reason: bad);
    }
    expect(appParseMoney('2.505', 'USD'), isNull, reason: 'three decimals');
  });

  TextEditingValue type(TextInputFormatter f, String text, {String old = ''}) =>
      f.formatEditUpdate(
        TextEditingValue(text: old),
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );

  test('money boxes group the digits while typing', () {
    final vnd = appMoneyInput('VND').single;
    expect(type(vnd, '5000000').text, '5,000,000');
    expect(type(vnd, '5000000').selection.baseOffset, 9);
    expect(type(vnd, '5.000.000').text, '5,000,000', reason: 'pasted');
    expect(type(vnd, '50a', old: '50').text, '50', reason: 'letters refused');
    expect(type(vnd, '-5').text, '', reason: 'no minus here');
    final usd = appMoneyInput('USD').single;
    expect(type(usd, '2000.5').text, '2,000.5');
    expect(type(usd, '2000.505', old: '2,000.50').text, '2,000.50');
    final signed = appMoneyInput('VND', signed: true).single;
    expect(type(signed, '-150000').text, '-150,000');
  });

  // Area and other quantities typed in (2026-10-05): a dot for decimals; a
  // comma only as a thousands mark, never as a decimal.
  test('typed quantities', () {
    expect(appParseQuantity('25'), 25);
    expect(appParseQuantity('25.5', decimals: 2), 25.5);
    expect(appParseQuantity('1,200'), 1200);
    expect(appParseQuantity('1,200.5'), 1200.5);
    expect(appParseQuantity('25,5'), isNull);
    expect(appParseQuantity('25.555', decimals: 2), isNull);
    expect(appParseQuantity('abc'), isNull);
    expect(appParseQuantity('-3'), isNull);
  });
}
