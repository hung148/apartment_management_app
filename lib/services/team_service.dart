import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';

typedef TeamTransport =
    Future<Map<String, dynamic>> Function(
      String callable,
      Map<String, dynamic> data,
    );

enum TeamView {
  buildings,
  myAccess,
  myRequests,
  staff,
  access,
  invitations,
  requests,
  activity,
}

enum TeamAction {
  saveStaff,
  invite,
  revokeInvitation,
  acceptInvitation,
  requestAccess,
  reviewRequest,
  setAccess,
}

class TeamPage {
  final List<Map<String, dynamic>> records;
  final String? nextCursor;
  TeamPage(Map<String, dynamic> data)
    : records = List.unmodifiable(
        (data['records'] as List).map(
          (r) => Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(r as Map),
          ),
        ),
      ),
      nextCursor = data['nextCursor'] as String?;
}

/// Keep this object for retries. Editing input means preparing a new operation.
class TeamOperation {
  final String id;
  final String _payload;
  TeamOperation._(this.id, Map<String, dynamic> payload)
    : _payload = jsonEncode(payload);
  Map<String, dynamic> get payload =>
      jsonDecode(_payload) as Map<String, dynamic>;
}

/// No direct Firestore access: server controls role-specific projections.
/// Instances hold no organization data or permission cache.
class TeamService {
  final TeamTransport _transport;
  TeamService({TeamTransport? transport}) : _transport = transport ?? _firebase;

  static Future<Map<String, dynamic>> _firebase(
    String callable,
    Map<String, dynamic> data,
  ) async {
    final response = await FirebaseFunctions.instance
        .httpsCallable(callable)
        .call(data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>?> myAccess(String organizationId) async {
    final data = await _transport('readTeam', {
      'organizationId': organizationId,
      'view': TeamView.myAccess.name,
    });
    final record = data['record'];
    return record == null
        ? null
        : Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(record as Map),
          );
  }

  Future<Map<String, dynamic>> invitation(String invitationId) =>
      _transport('lookupTeamInvitation', {'invitationId': invitationId.trim()});

  Future<TeamPage> workspace(
    String organizationId,
    String view, {
    String? buildingId,
    String? cursor,
  }) async => TeamPage(
    await _transport('readWorkspace', {
      'organizationId': organizationId,
      'view': view,
      'buildingId': ?buildingId,
      'cursor': ?cursor,
    }),
  );

  Future<TeamPage> page(
    String organizationId,
    TeamView view, {
    int limit = 25,
    String? cursor,
    String? actorId,
  }) async {
    if (view == TeamView.myAccess ||
        limit < 1 ||
        limit > 100 ||
        (actorId != null && view != TeamView.activity)) {
      throw ArgumentError('Invalid team page request');
    }
    return TeamPage(
      await _transport('readTeam', {
        'organizationId': organizationId,
        'view': view.name,
        'limit': limit,
        'cursor': ?cursor,
        'actorId': ?actorId,
      }),
    );
  }

  TeamOperation prepare(
    String organizationId,
    TeamAction action,
    Map<String, dynamic> fields,
  ) {
    if (fields.keys.any({'organizationId', 'action', 'operationId'}.contains)) {
      throw ArgumentError('Operation envelope cannot be overridden');
    }
    final id = const Uuid().v4();
    return TeamOperation._(id, {
      ...fields,
      'organizationId': organizationId,
      'action': action.name,
      'operationId': id,
    });
  }

  /// Errors propagate: the UI must retain the operation after uncertain failures,
  /// and must never display stale data as a successful fallback on access denial.
  Future<Map<String, dynamic>> execute(TeamOperation operation) =>
      _transport('mutateTeam', operation.payload);

  Future<Map<String, dynamic>> mutatePayment(Map<String, dynamic> payload) =>
      _transport('mutateStandalonePayment', payload);

  Future<Map<String, dynamic>> mutateTask(Map<String, dynamic> payload) =>
      _transport('mutateHousekeepingTask', payload);

  Future<Map<String, dynamic>> tenantContacts(Map<String, dynamic> payload) =>
      _transport('tenantContacts', payload);

  Future<Map<String, dynamic>> tenantLeases(Map<String, dynamic> payload) =>
      _transport('tenantLeases', payload);

  Future<Map<String, dynamic>> tenantRoommates(Map<String, dynamic> payload) =>
      _transport('tenantRoommates', payload);

  Future<Map<String, dynamic>> leaseLifecycle(Map<String, dynamic> payload) =>
      _transport('leaseLifecycle', payload);

  Future<Map<String, dynamic>> invoices(Map<String, dynamic> payload) =>
      _transport('invoices', payload);

  Future<Map<String, dynamic>> propertyLayout(Map<String, dynamic> payload) =>
      _transport('propertyLayout', payload);

  Future<Map<String, dynamic>> bookingWorkspace(Map<String, dynamic> payload) =>
      _transport('bookingWorkspace', payload);

  Future<Map<String, dynamic>> tenantRent(Map<String, dynamic> payload) =>
      _transport('tenantRent', payload);

  Future<Map<String, dynamic>> propertyContract(Map<String, dynamic> payload) =>
      _transport('propertyContract', payload);

  Future<Map<String, dynamic>> propertyDetails(Map<String, dynamic> payload) =>
      _transport('propertyDetails', payload);

  Future<Map<String, dynamic>> roomDetails(Map<String, dynamic> payload) =>
      _transport('roomDetails', payload);

  Future<Map<String, dynamic>> roomRates(Map<String, dynamic> payload) =>
      _transport('roomRates', payload);

  Future<Map<String, dynamic>> roomBookingSettings(
    Map<String, dynamic> payload,
  ) => _transport('roomBookingSettings', payload);
}
