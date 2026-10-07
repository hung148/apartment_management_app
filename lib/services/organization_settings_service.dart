import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../models/organization_model.dart';
import 'team_service.dart' show TeamTransport;
import 'app_functions.dart';

/// A bank or e-wallet account deposits and payments are received into (B8-lite).
class PaymentAccount {
  final String id;
  final String label;
  const PaymentAccount(this.id, this.label);
}

/// Details of a version-2 organization plus what the current account may do.
class OrganizationSettings {
  final Organization organization;
  final String role;
  final bool canManage;
  final bool canClose;
  final bool canLeave;
  final List<PaymentAccount> paymentAccounts;
  const OrganizationSettings({
    required this.organization,
    required this.role,
    required this.canManage,
    required this.canClose,
    required this.canLeave,
    this.paymentAccounts = const [],
  });
}

/// An organization the current account closed that can still be restored.
class ClosedOrganization {
  final String id;
  final String name;
  final DateTime closedAt;
  final DateTime purgeAfter;
  const ClosedOrganization(this.id, this.name, this.closedAt, this.purgeAfter);

  /// Whole days left before permanent removal (0 on the last day).
  int daysLeft(DateTime now) =>
      purgeAfter.difference(now).inDays.clamp(0, 30);
}

/// Version-2 organizations reject direct client writes. Every call goes
/// through the `organizationSettings` function, which checks current access.
class OrganizationSettingsService {
  final TeamTransport _transport;
  final String Function() _newOperationId;
  OrganizationSettingsService({
    TeamTransport? transport,
    String Function()? newOperationId,
  }) : _transport = transport ?? _firebase,
       _newOperationId = newOperationId ?? (() => const Uuid().v4());

  static Future<Map<String, dynamic>> _firebase(
    String callable,
    Map<String, dynamic> data,
  ) async {
    final response = await appCallable(callable)
        .call(data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  static const fieldNames = [
    'name', 'address', 'phone', 'email',
    'taxCode', 'bankName', 'bankAccountNumber', 'bankAccountName',
  ];

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  Future<OrganizationSettings> read(String organizationId) async {
    final row = await _transport('organizationSettings', {
      'action': 'read',
      'organizationId': organizationId,
    });
    String? text(String key) => row[key] is String ? row[key] as String : null;
    return OrganizationSettings(
      organization: Organization(
        id: organizationId,
        name: text('name') ?? '',
        address: text('address'),
        phone: text('phone'),
        email: text('email'),
        taxCode: text('taxCode'),
        bankName: text('bankName'),
        bankAccountNumber: text('bankAccountNumber'),
        bankAccountName: text('bankAccountName'),
        createdBy: text('createdBy') ?? '',
        // Missing on some migrated records; epoch is shown rather than failing.
        createdAt: _date(row['createdAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        updatedAt: _date(row['updatedAt']),
        inviteCode: '',
        accessVersion: 2,
      ),
      role: text('role') ?? '',
      canManage: row['canManage'] == true,
      canClose: row['canClose'] == true,
      canLeave: row['canLeave'] == true,
      paymentAccounts: [
        for (final a in (row['paymentAccounts'] as List? ?? const []))
          if (a is Map && a['id'] is String && a['label'] is String)
            PaymentAccount(a['id'] as String, a['label'] as String),
      ],
    );
  }

  /// Replaces the list of receiving accounts. Reuse [operationId] to retry.
  Future<void> saveAccounts(
    String organizationId,
    List<PaymentAccount> accounts, {
    required String operationId,
  }) => _transport('organizationSettings', {
    'action': 'accounts',
    'organizationId': organizationId,
    'operationId': operationId,
    'accounts': [
      for (final a in accounts) {'id': a.id, 'label': a.label},
    ],
  });

  /// Sends every field; an empty value clears it. Unknown keys are refused.
  Future<void> update(String organizationId, Map<String, String?> fields) {
    if (fields.keys.any((k) => !fieldNames.contains(k))) {
      throw ArgumentError('Unknown organization field');
    }
    return _transport('organizationSettings', {
      'action': 'update',
      'organizationId': organizationId,
      'operationId': _newOperationId(),
      'fields': {for (final k in fieldNames) k: (fields[k] ?? '').trim()},
    });
  }

  Future<void> leave(String organizationId) =>
      _transport('organizationSettings', {
        'action': 'leave',
        'organizationId': organizationId,
        'operationId': _newOperationId(),
      });

  /// A fresh operation ID. Keep it and reuse it to retry the same copy.
  String newOperation() => _newOperationId();

  /// How many records a copy would duplicate, per collection. Also checks
  /// that the caller may copy from the source into the target.
  Future<Map<String, int>> copyPreview(String sourceId, String targetId) async {
    final data = await _transport('organizationSettings', {
      'action': 'copyPreview',
      'organizationId': sourceId,
      'targetOrganizationId': targetId,
    });
    return {
      for (final e in data.entries)
        if (e.value is num) e.key: (e.value as num).toInt(),
    };
  }

  /// Copies properties, rooms, tenants, bookings, invoices and their history
  /// into the target with new IDs. Retrying with the same [operationId]
  /// resumes onto the same records instead of duplicating them.
  Future<Map<String, dynamic>> copy(
    String sourceId,
    String targetId, {
    required String operationId,
  }) => _transport('organizationSettings', {
    'action': 'copy',
    'organizationId': sourceId,
    'operationId': operationId,
    'targetOrganizationId': targetId,
  });

  /// Creates a version-2 organization owned by the caller and returns its ID.
  /// Retrying with the same [operationId] returns the same organization.
  Future<String> create(Map<String, String?> fields, {required String operationId, bool legacy = false}) async {
    if (fields.keys.any((k) => !fieldNames.contains(k))) {
      throw ArgumentError('Unknown organization field');
    }
    final row = await _transport('organizationSettings', {
      'action': legacy ? 'createLegacy' : 'create',
      'operationId': operationId,
      'fields': {for (final k in fieldNames) k: (fields[k] ?? '').trim()},
    });
    return row['organizationId'] as String;
  }

  /// Closed organizations this account can still restore, soonest removal first.
  Future<List<ClosedOrganization>> closedList() async {
    final data = await _transport('organizationSettings', {'action': 'closedList'});
    final rows = [
      for (final raw in (data['records'] as List? ?? const []))
        if (raw is Map)
          ClosedOrganization(
            raw['id'] as String,
            raw['name'] as String? ?? '',
            DateTime.parse(raw['closedAt'] as String),
            DateTime.parse(raw['purgeAfter'] as String),
          ),
    ]..sort((a, b) => a.purgeAfter.compareTo(b.purgeAfter));
    return rows;
  }

  /// Reopens a closed organization; members get their previous access back.
  Future<void> restore(String organizationId) => _transport('organizationSettings', {
    'action': 'restore',
    'organizationId': organizationId,
    'operationId': _newOperationId(),
  });

  /// Owner only. Everyone loses access immediately; records are retained
  /// until the server's purge date. Safe to call again after an interruption.
  Future<void> close(String organizationId, String confirmName) =>
      _transport('organizationSettings', {
        'action': 'close',
        'organizationId': organizationId,
        'operationId': _newOperationId(),
        'confirmName': confirmName,
      });
}
