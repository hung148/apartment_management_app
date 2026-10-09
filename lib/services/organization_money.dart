import 'package:flutter/foundation.dart';
import '../utils/money_conversion.dart';
import '../utils/app_money.dart';
import 'exchange_rate_service.dart';
import 'team_service.dart';
import 'read_cache.dart';

/// Organization-keyed display configuration; never a replacement for source
/// records. Forms take an immutable snapshot instead of following live changes.
class OrganizationMoney extends ChangeNotifier {
  static final shared = OrganizationMoney();
  String? _active;
  void activate(String id) {
    _active = id;
    AppMoney.displayConversion = _snapshots[id];
  }

  final Map<String, MoneyConversion> _snapshots = {};
  final Map<String, ExchangeRateSnapshot> _rates = {};
  final Map<String, int> _generations = {};
  final Set<String> _loading = {}, _failed = {};
  bool isLoading(String id) => _loading.contains(id);
  bool refreshFailed(String id) => _failed.contains(id);
  void select(String id, String currency) {
    // Invalidate an in-flight load of the previous setting.
    _generations[id] = (_generations[id] ?? 0) + 1;
    _loading.remove(id);
    ReportingMoney.select(id, currency);
    final current = _snapshots[id];
    _snapshots[id] = MoneyConversion(
        currency: currency,
        perUsd: current?.perUsd ?? {},
        date: current?.date,
        snapshotId: current?.snapshotId,
      );
      if (_active == id) AppMoney.displayConversion = _snapshots[id];
      notifyListeners();
  }

  MoneyConversion? forOrganization(String id) => _snapshots[id];

  Future<void> load(
    String id,
    TeamService service, {
    ExchangeRateService? exchange,
  }) async {
    final generation = (_generations[id] ?? 0) + 1;
    _generations[id] = generation;
    _loading.add(id);
    _failed.remove(id);
    notifyListeners();
    final provider = exchange ?? ExchangeRateService();
    try {
      final settings = await service.organizationCurrency({
        'action': 'readCurrency',
        'organizationId': id,
      });
      final currency = settings['currency'] as String;
      final cached = await provider.cached();
      if (_generations[id] != generation) return;
      // A successful setting read must take effect even when rates are offline.
      // An empty snapshot preserves the explicit original-currency fallback.
      configure(id, currency, cached ?? _rates[id] ?? ExchangeRateSnapshot(
        perUsd: const {'USD': 1}, dates: const {},
      ));
      final ExchangeRateSnapshot rates;
      if (exchange != null) {
        rates = await provider.refresh();
      } else {
        final response = await service.organizationCurrency({
          'action': 'readRates', 'organizationId': id,
        });
        rates = ExchangeRateSnapshot.fromServer(response);
        await provider.cacheServerSnapshot(response);
      }
      if (_generations[id] == generation) configure(id, currency, rates);
    } catch (error) {
      if (_generations[id] == generation) {
        _failed.add(id);
        if (ReadCache.isAccessError(error)) {
          _snapshots.remove(id);
          _rates.remove(id);
          ReportingMoney.forget(id);
          if (_active == id) AppMoney.displayConversion = null;
        }
      }
      rethrow;
    } finally {
      if (_generations[id] == generation) {
        _loading.remove(id);
        notifyListeners();
      }
      if (exchange == null) provider.dispose();
    }
  }

  void configure(String id, String currency, ExchangeRateSnapshot rates) {
    _rates[id] = rates;
    final dates = rates.dates.values.toList()..sort();
    _snapshots[id] = MoneyConversion(
      currency: currency,
      perUsd: {for (final e in rates.perUsd.entries) e.key: e.value.toString()},
      date: dates.isEmpty ? null : dates.first,
      snapshotId: rates.snapshotId,
    );
    if (_active == id) AppMoney.displayConversion = _snapshots[id];
    ReportingMoney.configure(id, currency, rates);
    notifyListeners();
  }

  void clear() {
    for (final id in _generations.keys.toList()) {
      _generations[id] = _generations[id]! + 1;
    }
    _snapshots.clear();
    _rates.clear();
    _loading.clear();
    _failed.clear();
    ReportingMoney.clear();
    _active = null;
    AppMoney.displayConversion = null;
    notifyListeners();
  }
}
