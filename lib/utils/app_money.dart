import 'package:intl/intl.dart';
import '../models/payment_model.dart';
import 'money_conversion.dart';

/// Currency is record data, never inferred from the current UI language.
class AppMoney {
  static MoneyConversion? displayConversion;
  static String code(String? currency) =>
      (currency == null || currency.trim().isEmpty)
      ? 'VND'
      : currency.trim().toUpperCase();
  static int fractionDigits(String currency) =>
      NumberFormat.currency(name: code(currency)).decimalDigits ?? 2;
  static String _pattern(String currency) {
    final digits = fractionDigits(currency);
    return '#,##0${digits == 0 ? '' : '.${List.filled(digits, '0').join()}'}';
  }
  static NumberFormat numberFormat(String currency) =>
      NumberFormat(_pattern(currency), 'en_US');
  static String rawFormat(num value, String currency) =>
      '${numberFormat(currency).format(value)} ${code(currency)}';
  static String format(num value, String currency) {
    final conversion = displayConversion;
    if (conversion == null || conversion.currency == code(currency)) return rawFormat(value, currency);
    try {
      return '≈ ${conversion.formatMinor((value * (fractionDigits(currency) == 0 ? 1 : 100)).round(), code(currency))}';
    } on StateError {
      // Missing rates must never relabel an amount or invent a conversion.
      return rawFormat(value, currency);
    }
  }
  static String excelFormat(String currency) =>
      '${_pattern(currency)} "${code(currency)}"';
  static List<String> currencies(Iterable<Payment> payments) =>
      (payments.map((p) => code(p.currency)).toSet().toList()..sort());
  static Map<String, double> totals(
    Iterable<Payment> payments,
    num Function(Payment) amount,
  ) {
    final result = <String, double>{};
    for (final payment in payments) {
      final currency = code(payment.currency);
      result[currency] = (result[currency] ?? 0) + amount(payment);
    }
    return result;
  }

  static List<Payment> only(Iterable<Payment> payments, String currency) =>
      payments.where((p) => code(p.currency) == code(currency)).toList();
}

