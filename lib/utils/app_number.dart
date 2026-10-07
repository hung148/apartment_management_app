import 'package:flutter/services.dart';

import 'app_money.dart';

// One way to write numbers in every language (Tom, 2026-10-05):
// - money: a comma between thousands, a dot before cents
//   (5,000,000 VND · 2,000.50 USD), in Vietnamese and in English alike;
// - kWh, m³, kg and other quantities: no thousands mark, a dot for decimals
//   (1000 kWh · 1200.5 kWh), so a reading never looks like a decimal;
// - money input boxes group the digits while typing (5000000 → 5,000,000).

/// The currency's cents per unit: 100 for USD, 1 for VND.
int appMoneyScale(String currency) =>
    AppMoney.fractionDigits(currency) == 0 ? 1 : 100;

/// An amount in minor units with its currency: "5,000,000 VND".
String appMoneyMinor(num minor, String currency) =>
    AppMoney.format(minor / appMoneyScale(currency), currency);

/// An amount in whole units with its currency: "2,000.50 USD".
String appMoney(num value, String currency) => AppMoney.format(value, currency);

/// The number only, grouped, for an input box: "5,000,000" / "2,000.50".
String appMoneyInputText(num minor, String currency) =>
    AppMoney.numberFormat(currency).format(minor / appMoneyScale(currency));

/// The same for an amount already in whole units (2000.5 → "2,000.50").
String appMoneyInputValue(num value, String currency) =>
    AppMoney.numberFormat(currency).format(value);

/// A quantity (kWh, m³, kg, hours): no thousands mark, up to [decimals]
/// decimals with a dot, no trailing zeros: 1000 · 1200.5 · 0.25.
String appQuantity(num value, {int decimals = 3}) {
  var text = value.toStringAsFixed(decimals);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return text == '-0' ? '0' : text;
}

/// Typed quantity (area, kWh): a dot for decimals; a comma only as a
/// thousands mark ("1,200" is 1200, never 1.2). Null when not valid.
double? appParseQuantity(String text, {int decimals = 3}) {
  var value = text.trim();
  if (value.contains(',')) {
    if (!RegExp(r'^\d{1,3}(,\d{3})+(\.\d*)?$').hasMatch(value)) return null;
    value = value.replaceAll(',', '');
  }
  if (!RegExp('^\\d+(?:\\.\\d{1,$decimals})?\$').hasMatch(value)) return null;
  return double.tryParse(value);
}

/// A quantity kept in thousandths (meter readings): 1200500 → "1200.5".
String appQuantityMilli(num milli) => appQuantity(milli / 1000);

/// Typed money to minor units, or null when it is not a valid amount.
/// Accepts "5,000,000", "5000000", "2,000.50"; also the older "5.000.000"
/// for currencies without cents. Never negative.
int? appParseMoney(String text, String currency) {
  var value = text.trim().replaceAll(' ', '');
  if (value.isEmpty) return null;
  final cents = appMoneyScale(currency) == 100;
  if (!cents && RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(value)) {
    value = value.replaceAll('.', '');
  }
  // Commas are only allowed as thousands marks in the right places.
  if (value.contains(',')) {
    if (!RegExp(r'^\d{1,3}(,\d{3})+(\.\d*)?$').hasMatch(value)) return null;
    value = value.replaceAll(',', '');
  }
  if (!RegExp(cents ? r'^\d+(\.\d{1,2})?$' : r'^\d+$').hasMatch(value)) {
    return null;
  }
  final parts = value.split('.');
  final whole = int.tryParse(parts[0]);
  if (whole == null) return null;
  final minor = cents
      ? whole * 100 +
            (parts.length > 1 ? int.parse(parts[1].padRight(2, '0')) : 0)
      : whole;
  return minor <= 1000000000000 ? minor : null;
}

/// The input formatters for a money box in [currency]: groups the digits as
/// you type (5000000 → 5,000,000); cents only for USD; a leading "-" only
/// when [signed] (lines that subtract).
List<TextInputFormatter> appMoneyInput(
  String currency, {
  bool signed = false,
}) => [
  AppMoneyInputFormatter(
    decimals: appMoneyScale(currency) == 100 ? 2 : 0,
    signed: signed,
  ),
];

class AppMoneyInputFormatter extends TextInputFormatter {
  final int decimals;
  final bool signed;
  AppMoneyInputFormatter({this.decimals = 0, this.signed = false});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed || newValue.text.isEmpty) {
      return newValue;
    }
    var text = newValue.text;
    var sign = '';
    if (signed && text.startsWith('-')) {
      sign = '-';
      text = text.substring(1);
    }
    // A pasted "5.000.000" (whole amounts) is read as five million.
    if (decimals == 0 && RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(text)) {
      text = text.replaceAll('.', '');
    }
    final raw = text.replaceAll(',', '');
    if (!RegExp(decimals > 0 ? r'^\d*(\.\d*)?$' : r'^\d*$').hasMatch(raw)) {
      return oldValue;
    }
    final parts = raw.split('.');
    if (parts.length > 1 && parts[1].length > decimals) return oldValue;
    final grouped = parts.first.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    final formatted = sign + grouped + (parts.length > 1 ? '.${parts[1]}' : '');

    // Keep the caret after the same digit it was after.
    int caret(int offset) {
      if (offset < 0) return formatted.length;
      final count = newValue.text
          .substring(0, offset.clamp(0, newValue.text.length))
          .replaceAll(',', '')
          .length;
      if (count == 0) return 0;
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != ',') seen++;
        if (seen == count) return i + 1;
      }
      return formatted.length;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: caret(newValue.selection.baseOffset),
        extentOffset: caret(newValue.selection.extentOffset),
      ),
    );
  }
}
