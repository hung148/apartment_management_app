import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import 'app_functions.dart';
import 'read_cache.dart';

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
  addStaff,
  changeInvitationEmail,
  revokeInvitation,
  acceptInvitation,
  requestAccess,
  reviewRequest,
  setAccess,
}

class TeamPage {
  final List<Map<String, dynamic>> records;
  final String? nextCursor;
  final Map<String, dynamic>? actor;
  TeamPage(Map<String, dynamic> data)
    : records = List.unmodifiable(
        (data['records'] as List).map(
          (r) => Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(r as Map),
          ),
        ),
      ),
      nextCursor = data['nextCursor'] as String?,
      actor = data['actor'] is Map
          ? Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(data['actor'] as Map),
            )
          : null;
}

/// The server's reason key (e.g. 'role_changed') from a callable error, or ''.
/// Platforms report it differently (web may wrap the message or put it in
/// details), so this searches both for one of the expected keys.
String serverReason(Object error, Iterable<String> known) {
  if (error is! FirebaseFunctionsException) return '';
  final text = '${error.message ?? ''} ${error.details ?? ''}';
  for (final key in known) {
    if (RegExp(
      '(^|[^A-Za-z0-9_-])${RegExp.escape(key)}(\$|[^A-Za-z0-9_-])',
    ).hasMatch(text))
      return key;
  }
  return '';
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
/// Instances hold no organization data or permission cache. The only copy is
/// the device copy ([ReadCache], 2026-10-06): used to SHOW a screen right away
/// while the server is asked again; never for deciding what may be changed.
class TeamService {
  final TeamTransport _transport;
  final ReadCache? _cache;

  /// The app's own service uses the device copy; a service with a test
  /// transport does not, unless a test passes [cache].
  TeamService({TeamTransport? transport, ReadCache? cache})
    : _transport = transport == null
          ? _firebase
          // A test transport: count its changes like the app's calls do.
          : ((name, data) {
              ServerWrites.note(name, data);
              return transport(name, data);
            }),
      _cache = cache ?? (transport == null ? ReadCache.shared : null);

  /// The saved copy first (when there is one), then the server's answer, which
  /// replaces the copy. An access error wipes the organization's copy.
  Stream<Saved<Map<String, dynamic>>> _live(
    String call,
    Map<String, dynamic> payload,
  ) async* {
    final cache = _cache;
    final saved = await cache?.read(call, payload);
    if (saved != null) yield saved;
    final fresh = await _fresh(call, payload);
    yield Saved(fresh, saved: false, at: DateTime.now());
  }

  Future<Map<String, dynamic>> _fresh(
    String call,
    Map<String, dynamic> payload,
  ) async {
    final org = payload['organizationId'] as String?;
    try {
      final data = await _transport(call, payload);
      _cache?.write(call, payload, data, organizationId: org);
      return data;
    } catch (e) {
      if (org != null && ReadCache.isAccessError(e)) {
        await _cache?.forgetOrganization(org);
      }
      rethrow;
    }
  }

  /// The saved copy of a read this screen assembles itself (e.g. all pages of
  /// the building list), or null.
  Future<Map<String, dynamic>?> saved(
    String what,
    String organizationId,
  ) async =>
      (await _cache?.read(what, {'organizationId': organizationId}))?.data;

  /// Saves such a read after the server answered it.
  void save(String what, String organizationId, Map<String, dynamic> data) =>
      _cache?.write(
        what,
        {'organizationId': organizationId},
        data,
        organizationId: organizationId,
      );

  /// The last account check that opened one workplace (2026-10-09, speed):
  /// the workspace opens from it at once, locked until the fresh check.
  Future<Map<String, dynamic>?> savedAccountEntry() async =>
      (await _cache?.read('accountEntry', const {}))?.data;

  /// Keeps the fresh check; it belongs to that workplace, so wiping the
  /// organization's copy wipes it too.
  void saveAccountEntry(String organizationId, Map<String, dynamic> data) =>
      _cache?.write(
        'accountEntry',
        const {},
        data,
        organizationId: organizationId,
      );

  /// Wipes the organization's copy (e.g. the server refused access).
  Future<void> forgetSaved(String organizationId) async =>
      _cache?.forgetOrganization(organizationId);

  static Future<Map<String, dynamic>> _firebase(
    String callable,
    Map<String, dynamic> data,
  ) async {
    final response = await appCallable(callable).call(data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> agreements(Map<String, dynamic> data) =>
      _transport('ownershipAgreements', data);

  /// The organizations this account owns or co-owns (version 2), for the home
  /// screen's co-ownership page (2026-10-06).
  Future<List<({String id, String name})>> ownedOrganizations() async {
    final out = <({String id, String name})>[];
    String? cursor;
    do {
      final page = await _transport('listMyOrganizations', {'cursor': ?cursor});
      for (final raw in page['records'] as List? ?? const []) {
        final r = Map<String, dynamic>.from(raw as Map);
        if (r['owner'] == true && r['accessVersion'] == 2) {
          out.add((id: '${r['id']}', name: '${r['name'] ?? ''}'));
        }
      }
      cursor = page['nextCursor'] as String?;
    } while (cursor != null);
    return out;
  }

  Future<Map<String, dynamic>?> myAccess(String organizationId) async {
    final data = await _fresh('readTeam', {
      'organizationId': organizationId,
      'view': TeamView.myAccess.name,
    });
    return _accessRecord(data);
  }

  /// The saved copy of [myAccess], or null (2026-10-06, device copy).
  Future<Map<String, dynamic>?> savedMyAccess(String organizationId) async {
    final saved = await _cache?.read('readTeam', {
      'organizationId': organizationId,
      'view': TeamView.myAccess.name,
    });
    return saved == null ? null : _accessRecord(saved.data);
  }

  static Map<String, dynamic>? _accessRecord(Map<String, dynamic> data) {
    final record = data['record'];
    return record == null
        ? null
        : Map<String, dynamic>.unmodifiable(
            Map<String, dynamic>.from(record as Map),
          );
  }

  /// R2: joins every organization that pre-approved this account's verified
  /// email. Results: [{organizationId, organizationName, status: joined|skipped}].
  Future<Map<String, dynamic>> claimMyInvitations() =>
      _transport('claimMyInvitations', {});

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

  /// Display-only saved first page of the staff list (with the caller's access
  /// as it was), followed by the server's fresh page (2026-10-09, device copy).
  Stream<Saved<TeamPage>> staffPageLive(String organizationId) =>
      _live('readTeam', {
        'organizationId': organizationId,
        'view': TeamView.staff.name,
        'limit': 25,
      }).map((s) => Saved(TeamPage(s.data), saved: s.saved, at: s.at));

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

  /// Organization roles (R1): templates + organization roles with member counts
  /// and what this account may do with each (canEdit / canDelete / canAssign).
  Future<Map<String, dynamic>> roles(String organizationId) => _transport(
    'orgRoles',
    {'organizationId': organizationId, 'action': 'list'},
  );

  /// action: 'save' (roleId absent = create) or 'delete'. Keep the operation
  /// for retries; editing the form means preparing a new one.
  TeamOperation prepareRole(
    String organizationId,
    String action,
    Map<String, dynamic> fields,
  ) {
    if (!{'save', 'delete'}.contains(action) ||
        fields.keys.any({'organizationId', 'action', 'operationId'}.contains)) {
      throw ArgumentError('Invalid role operation');
    }
    final id = const Uuid().v4();
    return TeamOperation._(id, {
      ...fields,
      'organizationId': organizationId,
      'action': action,
      'operationId': id,
    });
  }

  Future<Map<String, dynamic>> executeRole(TeamOperation operation) =>
      _transport('orgRoles', operation.payload);

  Future<Map<String, dynamic>> mutatePayment(Map<String, dynamic> payload) =>
      _transport('mutateStandalonePayment', payload);

  Future<Map<String, dynamic>> mutateTask(Map<String, dynamic> payload) =>
      _transport('mutateHousekeepingTask', payload);

  Future<Map<String, dynamic>> tenantContacts(Map<String, dynamic> payload) =>
      _transport('tenantContacts', payload);

  /// Display-only saved tenant list, followed by an authoritative fresh list.
  /// Deliberately excludes contact edits and private tenant detail requests.
  Stream<Saved<Map<String, dynamic>>> tenantListLive(
    Map<String, dynamic> payload,
  ) {
    if (payload['action'] != 'list') {
      throw ArgumentError('Only tenant list reads may use this stream');
    }
    return _live('tenantContacts', payload);
  }

  Future<Map<String, dynamic>> tenantLeases(Map<String, dynamic> payload) =>
      _transport('tenantLeases', payload);

  Future<Map<String, dynamic>> tenantRoommates(Map<String, dynamic> payload) =>
      _transport('tenantRoommates', payload);

  Future<Map<String, dynamic>> leaseLifecycle(Map<String, dynamic> payload) =>
      _transport('leaseLifecycle', payload);

  /// B7 technical problems (list, report, update, fix, reopen; B7b photos:
  /// addPhoto, photo, removePhoto).
  Future<Map<String, dynamic>> technicalProblems(
    Map<String, dynamic> payload,
  ) => _transport('technicalProblems', payload);

  /// B7b Google Drive connection (status, connect, disconnect).
  Future<Map<String, dynamic>> googleDrive(Map<String, dynamic> payload) =>
      _transport('googleDrive', payload);

  /// Sheet import (2026-10-05): preview, apply, saveSheet. Owner only.
  Future<Map<String, dynamic>> importSheet(Map<String, dynamic> payload) =>
      _transport('importSheet', payload);

  /// Display-only saved invoice list, followed by the server's fresh list
  /// (2026-10-09, device copy). Only the first page of the list: never a
  /// single invoice, a quote or a change.
  Stream<Saved<Map<String, dynamic>>> invoiceListLive(
    Map<String, dynamic> payload,
  ) {
    if (payload['action'] != 'list' || payload['cursor'] != null) {
      throw ArgumentError(
        'Only the first invoice list page may use this stream',
      );
    }
    return _live('invoices', payload);
  }

  Future<Map<String, dynamic>> invoices(Map<String, dynamic> payload) =>
      _transport('invoices', payload);

  Future<Map<String, dynamic>> propertyLayout(Map<String, dynamic> payload) =>
      _transport('propertyLayout', payload);

  Future<Map<String, dynamic>> bookingWorkspace(Map<String, dynamic> payload) =>
      _transport('bookingWorkspace', payload);

  // The booking form's options (rooms, staff, receiving accounts, price list,
  // what the person may do), 2026-10-09 speed: kept in memory for this
  // account, so the form opens at once and asks the server again behind it.
  // Only for showing: the server checks every save itself.
  final _bookingOptions = <String, Map<String, dynamic>>{};
  final _bookingOptionsLoading = <String, Future<Map<String, dynamic>>>{};
  String _optionsKey(String organizationId, String buildingId) =>
      '${_cache?.account ?? ''}|$organizationId|$buildingId';
  static Map<String, dynamic> _copy(Map<String, dynamic> m) =>
      jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

  /// The options shown last time in this session, or null.
  Map<String, dynamic>? savedBookingOptions(
    String organizationId,
    String buildingId,
  ) {
    final v = _bookingOptions[_optionsKey(organizationId, buildingId)];
    return v == null ? null : _copy(v);
  }

  /// Asks the server (one request at a time per building) and keeps the answer.
  Future<Map<String, dynamic>> bookingOptions(
    String organizationId,
    String buildingId,
  ) {
    final key = _optionsKey(organizationId, buildingId);
    final loading = _bookingOptionsLoading[key] ??= () async {
      try {
        final r = await bookingWorkspace({
          'organizationId': organizationId,
          'buildingId': buildingId,
          'action': 'rooms',
        });
        _bookingOptions[key] = r;
        return r;
      } catch (e) {
        if (ReadCache.isAccessError(e)) _bookingOptions.remove(key);
        rethrow;
      } finally {
        _bookingOptionsLoading.remove(key);
      }
    }();
    return loading.then(_copy);
  }

  /// Loads the options ahead (the calendar, when it shows a building), so
  /// even the first "Đặt phòng" opens at once. Failures are ignored here.
  void prefetchBookingOptions(String organizationId, String buildingId) {
    if (_bookingOptions.containsKey(_optionsKey(organizationId, buildingId))) {
      return;
    }
    bookingOptions(organizationId, buildingId).ignore();
  }

  /// The building's saved prices changed in the form: the kept options too.
  void keepBookingPrices(
    String organizationId,
    String buildingId,
    String? currency,
    List<int> prices,
  ) {
    final kept = _bookingOptions[_optionsKey(organizationId, buildingId)];
    for (final r in (kept?['records'] as List? ?? const [])) {
      if (r is Map &&
          (currency == null || (r['currency'] ?? 'VND') == currency)) {
        r['savedNightPricesMinor'] = List<int>.of(prices);
      }
    }
  }

  /// C1–C3 calendar: rooms of every visible property and the stays in
  /// {organizationId, from, to} (property-local dates, `to` exclusive).
  Future<Map<String, dynamic>> calendarView(Map<String, dynamic> payload) =>
      _transport('calendarView', payload);

  /// [calendarView], saved copy first (2026-10-06, device copy).
  Stream<Saved<Map<String, dynamic>>> calendarViewLive(
    Map<String, dynamic> payload,
  ) => _live('calendarView', payload);

  Future<Map<String, dynamic>> tenantRent(Map<String, dynamic> payload) =>
      _transport('tenantRent', payload);

  Future<Map<String, dynamic>> propertyContract(Map<String, dynamic> payload) =>
      _transport('propertyContract', payload);

  Future<Map<String, dynamic>> organizationCurrency(
    Map<String, dynamic> payload,
  ) => _transport('organizationSettings', payload);

  Future<Map<String, dynamic>> propertyDetails(Map<String, dynamic> payload) =>
      _transport('propertyDetails', payload);

  Future<Map<String, dynamic>> roomDetails(Map<String, dynamic> payload) =>
      _transport('roomDetails', payload);
  Future<Map<String, dynamic>> utilityReadings(Map<String, dynamic> payload) =>
      _transport('utilityReadings', payload);

  /// B5 service fee definitions and room rates (billing goes through invoices).
  Future<Map<String, dynamic>> serviceFees(Map<String, dynamic> payload) =>
      _transport('serviceFees', payload);

  Future<Map<String, dynamic>> roomRates(Map<String, dynamic> payload) =>
      _transport('roomRates', payload);

  Future<Map<String, dynamic>> roomBookingSettings(
    Map<String, dynamic> payload,
  ) => _transport('roomBookingSettings', payload);

  Future<Map<String, dynamic>> transferOrganization(
    Map<String, dynamic> payload,
  ) => _transport('transferOrganization', payload);
}
