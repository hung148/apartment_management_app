import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'team_service.dart';
import 'app_functions.dart';

/// Retain the same operation after a timeout or connection failure.
/// A new operation means a new financial action, even with identical amounts.
class PaymentOperation {
  final String id;
  final String _payload;

  PaymentOperation._(this.id, Map<String, dynamic> payload)
    : _payload = jsonEncode(payload);

  Map<String, dynamic> get payload =>
      jsonDecode(_payload) as Map<String, dynamic>;

  factory PaymentOperation.restore(String encoded) {
    final data = Map<String, dynamic>.from(jsonDecode(encoded) as Map);
    final id = data['operationId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Invalid payment operation');
    }
    return PaymentOperation._(id, data);
  }
}

/// Persist before sending. Storage failure blocks sending; no financial fallback.
/// Account/organization/invoice isolation prevents another login replaying it.
class PaymentJournal {
  String key(String account, String organization, String payment) =>
      'pending-payment:${jsonEncode([account, organization, payment])}';
  Future<PaymentOperation?> load(String key) async {
    final value = (await SharedPreferences.getInstance()).getString(key);
    return value == null ? null : PaymentOperation.restore(value);
  }

  Future<void> save(String key, PaymentOperation operation) async {
    if (!await (await SharedPreferences.getInstance()).setString(
      key,
      jsonEncode(operation.payload),
    )) {
      throw StateError('Payment retry storage unavailable');
    }
  }

  Future<void> clear(String key) async {
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw StateError('Payment retry storage unavailable');
    }
  }
}

/// Version-2 standalone invoices only. No direct Firestore/offline fallback.
/// Amounts are integer dong for VND and cents for USD; the server checks currency.
class PaymentCommandService {
  final TeamTransport _transport;

  PaymentCommandService({TeamTransport? transport})
    : _transport = transport ?? _firebase;

  static Future<Map<String, dynamic>> _firebase(
    String callable,
    Map<String, dynamic> data,
  ) async {
    final response = await appCallable(callable)
        .call(data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  PaymentOperation collect({
    required String organizationId,
    required String paymentId,
    required int amountMinor,
    required String paymentMethod,
  }) => _prepare({
    'organizationId': organizationId,
    'paymentId': paymentId,
    'action': 'collect',
    'amountMinor': amountMinor,
    'paymentMethod': paymentMethod,
  });

  PaymentOperation refund({
    required String organizationId,
    required String paymentId,
    required int amountMinor,
    required String reason,
  }) => _prepare({
    'organizationId': organizationId,
    'paymentId': paymentId,
    'action': 'refund',
    'amountMinor': amountMinor,
    'reason': reason,
  });

  PaymentOperation _prepare(Map<String, dynamic> fields) {
    final id = const Uuid().v4();
    return PaymentOperation._(id, {...fields, 'operationId': id});
  }

  Future<Map<String, dynamic>> execute(PaymentOperation operation) =>
      _transport('mutateStandalonePayment', operation.payload);
}
