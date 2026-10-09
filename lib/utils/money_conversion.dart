import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'app_money.dart';
import 'app_number.dart';

/// Immutable rates for one display/input session. All arithmetic uses minor
/// units and integer ratios; rates are decimal strings, never binary floats.
class MoneyConversion {
  final String currency;
  final Map<String, String> perUsd;
  final String? date;
  final String? snapshotId;
  MoneyConversion({
    required this.currency,
    required Map<String, String> perUsd,
    this.date,
    this.snapshotId,
  }) : perUsd = Map.unmodifiable(perUsd);

  bool canConvert(String source) {
    if (source == currency) return true;
    try {
      _rate(source);
      _rate(currency);
      return true;
    } on StateError {
      return false;
    }
  }

  (BigInt, BigInt) _rate(String code) {
    final value = code == 'USD' ? '1' : perUsd[code];
    if (value == null || !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(value)) {
      throw StateError('Missing or invalid exchange rate: $code');
    }
    final parts = value.split('.');
    final numerator = BigInt.parse(parts.join());
    if (numerator <= BigInt.zero) throw StateError('Invalid exchange rate');
    return (
      numerator,
      BigInt.from(10).pow(parts.length == 2 ? parts[1].length : 0),
    );
  }

  int convertMinor(int amount, String from, String to) {
    if (from == to) return amount;
    final (source, sourceDenominator) = _rate(from);
    final (target, targetDenominator) = _rate(to);
    final numerator =
        BigInt.from(amount) *
        target *
        sourceDenominator *
        BigInt.from(appMoneyScale(to));
    final denominator =
        source * targetDenominator * BigInt.from(appMoneyScale(from));
    // Half away from zero, including refunds and credit lines.
    final magnitude =
        (numerator.abs() * BigInt.two + denominator) ~/
        (denominator * BigInt.two);
    final signed = numerator.isNegative ? -magnitude : magnitude;
    if (signed.abs() > BigInt.from(9007199254740991))
      throw StateError('Converted amount is too large');
    return signed.toInt();
  }

  String formatMinor(int amount, String source) => AppMoney.rawFormat(
    convertMinor(amount, source, currency) / appMoneyScale(currency),
    currency,
  );
}

/// One binding per money field: exact original value survives an unchanged
/// round trip, even when two source amounts round to the same displayed value.
/// The immutable conversion is pinned for the lifetime of the open form.
class MoneyInputBinding {
  final MoneyConversion conversion;
  final String sourceCurrency;
  final int? originalMinor;
  late final String initialText;
  late final TextEditingController controller;
  MoneyInputBinding({
    required this.conversion,
    required this.sourceCurrency,
    this.originalMinor,
  }) {
    initialText = originalMinor == null
        ? ''
        : appMoneyInputText(
            conversion.convertMinor(
              originalMinor!,
              sourceCurrency,
              currency,
            ),
            currency,
          );
    controller = TextEditingController(text: initialText);
  }
  String get currency => conversion.canConvert(sourceCurrency)
      ? conversion.currency : sourceCurrency;
  int? get sourceMinor {
    if (controller.text == initialText) return originalMinor;
    final entered = appParseMoney(controller.text, currency);
    if (entered == null) return null;
    final value = conversion.convertMinor(entered, currency, sourceCurrency);
    return value <= 1000000000000 ? value : null;
  }

  List<TextInputFormatter> get formatters => appMoneyInput(currency);
  void dispose() => controller.dispose();
}

/// Adapter for existing forms that already own their text controllers.
/// Call [set] when loading a monetary field; use [parse] when saving it.
class MoneyForm {
  final MoneyConversion? conversion;
  final Map<
    TextEditingController,
    ({String text, int? original, String source})
  >
  _originals = {};
  MoneyForm(this.conversion);
  String currency(String source) => conversion?.canConvert(source) == true
      ? conversion!.currency : source;

  void set(TextEditingController controller, int? minor, String source) {
    final displayed = minor == null
        ? null
        : conversion?.convertMinor(minor, source, currency(source)) ?? minor;
    final text = displayed == null
        ? ''
        : appMoneyInputText(displayed, currency(source));
    _originals[controller] = (text: text, original: minor, source: source);
    controller.text = text;
  }

  int? parse(TextEditingController controller, String source) {
    final original = _originals[controller];
    if (original != null &&
        original.source == source &&
        controller.text == original.text)
      return original.original;
    return parseText(controller.text, source);
  }

  /// Parse a newly entered value that has no original amount to preserve.
  int? parseText(String text, String source) {
    final entered = appParseMoney(text, currency(source));
    if (entered == null) return null;
    final value =
        conversion?.convertMinor(entered, currency(source), source) ?? entered;
    return value <= 1000000000000 ? value : null;
  }
}
