import 'package:intl/intl.dart';
import '../models/payment_model.dart';

/// Currency is record data, never inferred from the current UI language.
class AppMoney {
  static String code(String? currency) =>
      (currency == null || currency.trim().isEmpty)
      ? 'VND'
      : currency.trim().toUpperCase();
  static NumberFormat numberFormat(String currency) =>
      NumberFormat(code(currency) == 'VND' ? '#,##0' : '#,##0.00', 'en_US');
  static String format(num value, String currency) =>
      '${numberFormat(currency).format(value)} ${code(currency)}';
  static String excelFormat(String currency) =>
      '${code(currency) == 'VND' ? '#,##0' : '#,##0.00'} "${code(currency)}"';
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
