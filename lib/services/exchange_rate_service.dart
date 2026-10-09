import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/payment_model.dart';
import '../utils/app_money.dart';

/// A dated reference-rate snapshot. Never changes the source billing records.
class ExchangeRateSnapshot {
  final String? snapshotId;
  final Map<String, double> perUsd;
  final Map<String, String> dates;
  ExchangeRateSnapshot({
    required Map<String, double> perUsd,
    required Map<String, String> dates,
    this.snapshotId,
  }) : perUsd = Map.unmodifiable(perUsd),
       dates = Map.unmodifiable(dates);

  factory ExchangeRateSnapshot.fromServer(Map<String, dynamic> value) {
    final id = value['id'];
    if (id is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      throw const FormatException('Invalid exchange rate snapshot');
    }
    final rawRates = Map<String, dynamic>.from(value['perUsd'] as Map);
    final dates = Map<String, String>.from(value['dates'] as Map);
    final parsed = ExchangeRateSnapshot.fromRows([
      for (final entry in rawRates.entries)
        if (entry.key != 'USD')
          {'base': 'USD', 'quote': entry.key, 'rate': double.parse('${entry.value}'), 'date': dates[entry.key]},
    ]);
    return ExchangeRateSnapshot(perUsd: parsed.perUsd, dates: parsed.dates, snapshotId: id);
  }

  factory ExchangeRateSnapshot.fromRows(List<dynamic> rows) {
    final rates = <String, double>{'USD': 1};
    final dates = <String, String>{};
    for (final row in rows) {
      final item = Map<String, dynamic>.from(row as Map);
      final rate = (item['rate'] as num).toDouble();
      final quote = AppMoney.code(item['quote'] as String);
      final date = item['date'] as String;
      if (item['base'] != 'USD' ||
          !rate.isFinite ||
          rate <= 0 ||
          DateTime.tryParse(date) == null) {
        throw const FormatException('Invalid exchange rate');
      }
      rates[quote] = rate;
      dates[quote] = date;
    }
    if (rates.length < 2) throw const FormatException('Empty exchange rates');
    return ExchangeRateSnapshot(perUsd: rates, dates: dates);
  }

  double convert(num amount, String from, String to) {
    from = AppMoney.code(from);
    to = AppMoney.code(to);
    if (from == to) return amount.toDouble();
    if (!perUsd.containsKey(from) || !perUsd.containsKey(to)) {
      throw StateError('Missing exchange rate: $from / $to');
    }
    return amount / perUsd[from]! * perUsd[to]!;
  }

  /// Reporting-only projection. Quantities, meter readings and percentages
  /// deliberately remain unchanged. Never pass this projection to persistence.
  Payment project(Payment payment, String target) {
    double money(double value) => convert(value, payment.currency, target);
    double? optional(double? value) => value == null ? null : money(value);
    return payment.copyWith(
      currency: target,
      amount: money(payment.amount),
      paidAmount: money(payment.paidAmount),
      rentUnitPrice: optional(payment.rentUnitPrice),
      electricityPricePerUnit: optional(payment.electricityPricePerUnit),
      waterPricePerUnit: optional(payment.waterPricePerUnit),
      internetFee: optional(payment.internetFee),
      cableTVFee: optional(payment.cableTVFee),
      hotWaterFee: optional(payment.hotWaterFee),
      managementFee: optional(payment.managementFee),
      taxAmount: optional(payment.taxAmount),
      lateFee: optional(payment.lateFee),
    );
  }
}

class ExchangeRateService {
  static const _cacheKey = 'reference_exchange_rates_v2';
  final http.Client client;
  ExchangeRateService({http.Client? client}) : client = client ?? http.Client();

  Future<ExchangeRateSnapshot?> cached() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_cacheKey);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? ExchangeRateSnapshot.fromServer(Map<String, dynamic>.from(decoded))
          : ExchangeRateSnapshot.fromRows(decoded as List);
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheServerSnapshot(Map<String, dynamic> value) async {
    ExchangeRateSnapshot.fromServer(value);
    await (await SharedPreferences.getInstance()).setString(_cacheKey, jsonEncode(value));
  }

  Future<ExchangeRateSnapshot> refresh() async {
    final response = await client
        .get(Uri.https('api.frankfurter.dev', '/v2/rates', {'base': 'USD'}))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200)
      throw StateError('Exchange rates unavailable');
    final snapshot = ExchangeRateSnapshot.fromRows(
      jsonDecode(response.body) as List,
    );
    await (await SharedPreferences.getInstance()).setString(
      _cacheKey,
      response.body,
    );
    return snapshot;
  }

  void dispose() => client.close();
}

/// Organization-scoped display preferences used by detail routes and dialogs.
/// Input fields and persistence continue to use the original currency.
class ReportingMoney {
  static final _preferences =
      <String, ({String currency, ExchangeRateSnapshot? rates})>{};

  static void configure(
    String organizationId,
    String currency,
    ExchangeRateSnapshot? rates,
  ) {
    _preferences[organizationId] = (currency: currency, rates: rates);
  }

  static void select(String organizationId, String currency) {
    final current = _preferences[organizationId];
    _preferences[organizationId] = (currency: currency, rates: current?.rates);
  }

  static void clear() => _preferences.clear();
  static void forget(String organizationId) => _preferences.remove(organizationId);

  static String format(String organizationId, num amount, String source) {
    final preference = _preferences[organizationId];
    if (preference == null || preference.currency == AppMoney.code(source)) {
      return AppMoney.rawFormat(amount, source);
    }
    try {
      final value = preference.rates!.convert(
        amount,
        source,
        preference.currency,
      );
      return '≈ ${AppMoney.rawFormat(value, preference.currency)}';
    } catch (_) {
      return AppMoney.rawFormat(amount, source);
    }
  }

  static String? total(
    String organizationId,
    Iterable<Payment> payments,
    num Function(Payment) amount,
  ) {
    final values = payments.toList();
    final preference = _preferences[organizationId];
    final target =
        preference?.currency ??
        (values.isEmpty ? 'VND' : AppMoney.code(values.first.currency));
    var total = 0.0;
    var converted = false;
    try {
      for (final payment in values) {
        final source = AppMoney.code(payment.currency);
        if (source == target) {
          total += amount(payment);
        } else {
          total += preference!.rates!.convert(amount(payment), source, target);
          converted = true;
        }
      }
      return '${converted ? '≈ ' : ''}${AppMoney.rawFormat(total, target)}';
    } catch (_) {
      return null;
    }
  }
}
