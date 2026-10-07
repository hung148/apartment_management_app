import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import '../services/team_service.dart';
import '../models/team_access.dart';
part 'operational_preview.dart';

/// Disposable UI fixtures. This transport never contacts Firebase.
class TeamPreviewStore {
  Map<String,dynamic>? ownershipTransfer;
  /// "Today" at the preview property (YYYY-MM-DD); tests may set it.
  String previewToday = () {
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${n.year}-${two(n.month)}-${two(n.day)}';
  }();

  final tenants = <Map<String, dynamic>>[
    {
      'id': 'tenant-anh',
      'isMainTenant': true,
      'moveInLocalDate': '2026-09-01',
      'canAddRoommate': true,
      'canEditRent': true,
      'monthlyRentMinor': 1500000,
      'currency': 'VND',
      'buildingId': 'riverside',
      'roomId': 'room-101',
      'fullName': 'Nguyễn Thị Minh Anh — gia đình Riverside',
      'phoneNumber': '0901234567',
      'status': 'active',
      'revision': '1:0',
    },
    {
      'id': 'tenant-linh',
      'buildingId': 'riverside',
      'roomId': 'room-102',
      'fullName': 'Trần Mỹ Linh',
      'phoneNumber': '',
      'status': 'moveOut',
      'revision': '1:0',
    },
  ];
  final rooms = <Map<String, dynamic>>[
    {
      'id': 'room-101',
      'buildingId': 'riverside',
      'roomNumber': '101 — Phòng gia đình Riverside',
      'roomType': 'Phòng gia đình hướng sông',
      'area': 45.5,
      'revision': '1:0',
    },
    {
      'id': 'room-102',
      'buildingId': 'riverside',
      'roomNumber': '102',
      'roomType': 'Tiêu chuẩn',
      'area': 30,
      'revision': '1:0',
    },
  ];
  final invoiceHistories = <String, List<Map<String, dynamic>>>{};
  final operationalInvoices = <Map<String, dynamic>>[];
  final operationalBookings = <Map<String, dynamic>>[];
  final tasks = <Map<String, dynamic>>[
    {
      'id': 'clean-101',
      'roomId': 'room-101',
      'assigneeId': 'preview-housekeeper',
      'title': 'Dọn phòng gia đình Riverside — thay khăn và kiểm tra vật dụng',
      'status': 'assigned',
      'buildingId': 'riverside',
    },
  ];
  final payment = <String, dynamic>{
    'id': 'payment',
    'roomId': 'Room 101 — Riverside',
    'amount': 1500000,
    'paidAmount': 500000,
    'currency': 'VND',
    'status': 'partial',
  };
  // Account-level fixtures are separate from the role inside this workplace.
  String accountMode = 'owner';
  String? staffConflict;
  final ownerEmails = <String>{};
  final otherEmployerEmails = <String>{};
  final additionalWorkplaceEmails = <String>{};
  bool additionalWorkplacePermissionInBoth = false;
  final accountWorkplaces = <Map<String, dynamic>>[
    {
      'id': 'preview',
      'name': 'Riverside — Khu căn hộ phía Đông',
      'createdBy': 'preview-owner',
      'createdAt': '2026-01-01T00:00:00Z',
      'accessVersion': 2,
    },
  ];
  String workspaceRole = 'owner';
  bool assignedOnly = false;
  bool priceOverride = true;
  final activity = <Map<String, dynamic>>[
    {
      'id': 'sample-event',
      'actorId': 'preview-owner',
      'action': 'setAccess',
      'targetId': 'sample-account',
      'createdAt': '2026-09-25T12:00:00Z',
      'reason': 'Coverage changed — Điều chỉnh phân công cơ sở Riverside',
      'before': {'role': 'receptionist', 'buildingScope': 'all'},
      'after': {
        'role': 'receptionist',
        'buildingScope': 'selected',
        'buildingIds': ['riverside'],
      },
    },
  ];
  late final service = TeamService(transport: call);
  void addOperationalSamples() {
    activity.addAll([
      {
        'id': 'sample-payment',
        'actorId': 'preview-receptionist',
        'action': 'booking_payment',
        'targetId': 'booking-101',
        'createdAt': '2026-09-25T13:00:00Z',
        'before': {'roomId': 'room-101', 'currency': 'VND', 'paidAmount': 0},
        'after': {
          'roomId': 'room-101',
          'currency': 'VND',
          'paidAmount': 500000,
          'changedFields': ['paidAmount'],
        },
      },
      {
        'id': 'sample-move',
        'actorId': 'preview-manager',
        'action': 'lease_move',
        'targetId': 'lease-101',
        'createdAt': '2026-09-25T14:00:00Z',
        'before': {'roomId': 'room-101', 'buildingId': 'riverside'},
        'after': {
          'roomId': 'room-202',
          'buildingId': 'garden',
          'changedFields': ['roomId', 'buildingId'],
        },
      },
    ]);
  }

  final Map<String, Map<String, dynamic>> completed = {};
  final contractHistory = <String, List<Map<String, dynamic>>>{};
  final leaseHistory = <String, List<Map<String, dynamic>>>{};
  final rentHistory = <String, List<Map<String, dynamic>>>{};
  final accounts = <Map<String, dynamic>>[
    {
      'id': 'legacy_preview',
      'organizationId': 'preview',
      'ownerId': 'legacy',
      'displayName': 'Nguyễn Văn An — tài khoản cần xét duyệt',
      'email': 'an@example.com',
      'role': 'member',
      'status': 'assignmentRequired',
      'canManageAccess': true,
    },
  ];
  final List<Map<String, dynamic>> staff = [
    {
      'id': 'anh',
      'displayName': 'Nguyễn Thị Minh Anh',
      'code': 'NV-001',
      'email': 'anh@example.com',
      'phone': '0901234567',
      'employmentStatus': 'active',
      'canEditProfile': true,
    },
    {
      'id': 'linh',
      'displayName': 'Trần Mỹ Linh — Riverside reception',
      'code': 'NV-002',
      'email': 'linh@example.com',
      'employmentStatus': 'active',
      'canEditProfile': true,
    },
  ];
  static Map<String, dynamic> grant([String role = 'receptionist']) => {
    'accessVersion': 2,
    'role': role,
    'status': 'active',
    'buildingScope': 'all',
    'buildingIds': <String>[],
    'permissionOverrides': <String, bool>{},
  };
  final buildings = <Map<String, dynamic>>[
    {'id': 'riverside', 'name': 'Riverside — Khu căn hộ phía Đông'},
    {'id': 'garden', 'name': 'Garden Homestay'},
  ];
  late final invitations = <Map<String, dynamic>>[
    {
      'id': 'demo-invite',
      'staffId': 'linh',
      'email': 'linh@example.com',
      'status': 'pending',
      'access': grant(),
      'expiresAt': '2035-01-01T00:00:00Z',
      'canRevoke': true,
    },
  ];
  final requests = <Map<String, dynamic>>[
    {
      'id': 'demo-request',
      'displayName': 'Nguyễn Thị Minh Anh',
      'email': 'anh@example.com',
      'status': 'pending',
      'canReview': true,
    },
  ];

  /// Edited templates and organization roles (R1 preview; the server is the authority).
  final roleDocs = <String, Map<String, dynamic>>{};
  var _roleSequence = 0;
  final _roleOperations = <String, Map<String, dynamic>>{};

  static String _hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Map<String, dynamic> _roles(Map<String, dynamic> d) {
    if (d['organizationId'] != 'preview') reject();
    final owner = workspaceRole == 'owner' && !assignedOnly;
    if (!['owner', 'administrator'].contains(workspaceRole) || assignedOnly) {
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'team_access_denied',
      );
    }
    Map<String, dynamic>? current(String id) => roleDocs.containsKey(id)
        ? (roleDocs[id]!['deleted'] == true ? null : roleDocs[id])
        : TeamPolicy.isTemplate(id) && id != 'owner'
        ? {
            'id': id,
            'template': id,
            'name': '',
            'color': _hex(TeamPolicy.templateColors[id]!),
            'grants': TeamPolicy.encode(TeamPolicy.templates[id]!),
            'revision': 0,
          }
        : null;
    int holders(String id) => accounts
        .where((a) => a['role'] == id && a['status'] != 'revoked')
        .length;
    int invites(String id) => invitations
        .where(
          (i) =>
              i['status'] == 'pending' && (i['access'] as Map?)?['role'] == id,
        )
        .length;
    if (d['action'] == 'list') {
      final ids = [
        ...TeamPolicy.templateIds.where((r) => r != 'owner'),
        ...roleDocs.keys.where((k) => !TeamPolicy.isTemplate(k)),
      ];
      return {
        'roles': [
          {
            'id': 'owner',
            'template': 'owner',
            'name': '',
            'color': _hex(TeamPolicy.templateColors['owner']!),
            'grants': TeamPolicy.encode(TeamPolicy.templates['owner']!),
            'revision': 0,
            'fixed': true,
            'members': 1,
            'pendingInvitations': 0,
            'canEdit': false,
            'canDelete': false,
            'canAssign': false,
          },
          for (final id in ids)
            if (current(id) case final role?)
              {
                ...role,
                'fixed': false,
                'members': holders(id),
                'pendingInvitations': invites(id),
                'canEdit': owner,
                'canDelete': owner && holders(id) == 0 && invites(id) == 0,
                'canAssign':
                    TeamPolicy.level(TeamPolicy.parse(role['grants'])) <
                    (owner ? 3 : 1),
              },
        ],
        'canCreate': owner,
        'myRole': workspaceRole,
        'myLevel': owner ? 3 : 1,
      };
    }
    final operation = d['operationId'] as String;
    if (_roleOperations[operation] case final done?) return done;
    if (!owner)
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'role_edit_denied',
      );
    final creating = d['roleId'] == null;
    final id = creating ? 'r_preview${++_roleSequence}' : d['roleId'] as String;
    final before = creating ? null : current(id);
    if (!creating && before == null) {
      throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'role_not_found',
      );
    }
    if (!creating && before!['revision'] != d['expectedRevision']) {
      throw FirebaseFunctionsException(
        code: 'aborted',
        message: 'role_changed',
      );
    }
    final revision = ((before?['revision'] as int?) ?? 0) + 1;
    Map<String, dynamic> result;
    if (d['action'] == 'delete') {
      if (holders(id) + invites(id) > 0) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'role_in_use',
        );
      }
      roleDocs[id] = {...before!, 'deleted': true, 'revision': revision};
      result = {'roleId': id, 'deleted': true};
    } else {
      final name = (d['name'] as String).trim();
      final taken = roleDocs.entries.any(
        (e) =>
            e.key != id &&
            e.value['deleted'] != true &&
            (e.value['name'] as String).toLowerCase() == name.toLowerCase(),
      );
      if (taken)
        throw FirebaseFunctionsException(
          code: 'already-exists',
          message: 'role_name_exists',
        );
      roleDocs[id] = {
        'id': id,
        'template': before?['template'],
        'name': name,
        'color': (d['color'] as String).toUpperCase(),
        'grants': Map<String, dynamic>.from(d['grants'] as Map),
        'revision': revision,
      };
      for (final a in accounts.where((a) => a['role'] == id)) {
        a['roleGrants'] = roleDocs[id]!['grants'];
        a['roleName'] = name;
      }
      result = {'roleId': id, 'revision': revision};
    }
    _roleOperations[operation] = result;
    return result;
  }

  /// C1–C3 calendar fixture: the preview rooms with one lease (paid, with a
  /// roommate), one Airbnb short stay with only the deposit paid, and a stay
  /// this role may not open, placed inside whatever month is asked for.
  Map<String, dynamic> _calendarPreview(Map<String, dynamic> d) {
    if (d['organizationId'] != 'preview') reject();
    final access = TeamAccess.fromMap(grant(workspaceRole));
    final first = DateTime.parse('${d['from']}T00:00:00Z');
    final last = DateTime.tryParse('${d['to']}T00:00:00Z');
    // Three months are asked for (2026-10-04): the samples go in the middle one.
    final from = last != null && last.difference(first).inDays > 40
        ? DateTime.utc(first.year, first.month + 1)
        : first;
    String at(int days, String time) {
      final t = from.add(Duration(days: days));
      return '${t.toIso8601String().substring(0, 10)} $time';
    }

    final now = DateTime.now();
    final today =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final leases = access.allows(TeamPermission.manageLease);
    final bookings = access.allows(TeamPermission.readBookings);
    final property = [
      for (final b in buildings)
        if (!assignedOnly || b['id'] == 'riverside')
          {
            'id': b['id'],
            'name': b['name'],
            'timeZone': 'Asia/Ho_Chi_Minh',
            'today': today,
            'now':
                '$today ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
            'canCreateBookings': access.allows(TeamPermission.createBookings),
            'canLease': leases,
            'canReadProblems': true,
            'canReportProblems':
                access.allows(TeamPermission.manageProperty) ||
                leases ||
                bookings,
            'rooms': [
              for (final r in rooms.where((r) => r['buildingId'] == b['id']))
                {
                  'id': r['id'],
                  'roomNumber': r['roomNumber'],
                  'shortStay': true,
                  'monthly': true,
                  'blocked': false,
                  'problems': <Map<String, dynamic>>[],
                },
            ],
            'bars': b['id'] != 'riverside'
                ? <Map<String, dynamic>>[]
                : [
                    {
                      'id': 'lease:tenant-anh',
                      'type': 'lease',
                      'roomId': 'room-101',
                      'kind': 'long',
                      'start': at(-20, '12:00'),
                      'end': null,
                      'plannedEnd': at(300, '12:00').substring(0, 10),
                      'status': 'staying',
                      'canOpen': leases,
                      'problem': false,
                      if (!leases) ...{'name': '', 'anonymous': true},
                      if (leases) ...{
                        'recordId': 'tenant-anh',
                        'name': tenants.first['fullName'],
                        'phone': true,
                        'roommates': 1,
                        'periodMonths': 1,
                        'pay': 'paid',
                        'paidUntil': at(10, '00:00'),
                      },
                    },
                    {
                      'id': 'booking:preview-airbnb',
                      'type': 'booking',
                      'roomId': 'room-102',
                      'kind': bookings ? 'deposit' : 'short',
                      'start': at(2, '14:00'),
                      'end': at(4, '11:30'),
                      'status': 'upcoming',
                      'canOpen': bookings,
                      'problem': false,
                      if (!bookings) ...{'name': '', 'anonymous': true},
                      if (bookings) ...{
                        'recordId': 'preview-airbnb',
                        'name': 'Trần Văn Bình — khách Airbnb',
                        'phone': true,
                        'platform': 'airbnb',
                        'pay': 'deposit',
                        'paidFraction': 0,
                        'paidUntil': at(2, '14:00'),
                      },
                    },
                  ],
          },
    ];
    final visible =
        access.allows(TeamPermission.readBookings) ||
        access.allows(TeamPermission.createBookings) ||
        leases ||
        access.allows(TeamPermission.manageProperty);
    return {
      'from': d['from'],
      'to': d['to'],
      'properties': visible ? property : <Map<String, dynamic>>[],
    };
  }

  Never reject() => throw FirebaseFunctionsException(
    code: 'failed-precondition',
    message: 'Preview record unavailable',
  );
  Map<String, dynamic> record(List<Map<String, dynamic>> rows, Object? id) =>
      rows.firstWhere((r) => r['id'] == id, orElse: () => reject());

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> data,
  ) async {
    // Clone all responses, just as a callable serialization boundary would.
    return Map<String, dynamic>.from(
      jsonDecode(jsonEncode(_handle(name, data))) as Map,
    );
  }

  Map<String, dynamic> _handle(String name, Map<String, dynamic> d) {
    if(name=='transferOrganization') {
      if(d['action']=='read')return {'owner':workspaceRole=='owner',
        'candidates':workspaceRole=='owner'?[{'id':'preview-manager','name':'Nguyễn Thị Minh Anh — Quản lý Riverside'}]:[],
        'proposal':ownershipTransfer==null?null:{...ownershipTransfer!, 'canAccept':workspaceRole=='manager'}};
      if(d['action']=='propose'&&workspaceRole=='owner') {
        ownershipTransfer={'id':d['proposalId'],'recipientName':'Nguyễn Thị Minh Anh — Quản lý Riverside'};return {'status':'pending'};
      }
      if(d['action']=='cancel'&&workspaceRole=='owner') {ownershipTransfer=null;return {'status':'cancelled'};}
      if(d['action']=='accept'&&workspaceRole=='manager'&&ownershipTransfer!=null) {workspaceRole='owner';ownershipTransfer=null;return {'status':'complete'};}
      throw FirebaseFunctionsException(code:'failed-precondition',message:'org_transfer_changed');
    }
    if(name == 'ownershipAgreements') throw FirebaseFunctionsException(code: 'failed-precondition', message: 'organization_governance_retired');
    if (name == 'claimMyInvitations')
      return {'results': <Map<String, dynamic>>[]};
    if (name == 'listMyOrganizations')
      return {
        'accountPolicy': {
          'mode': accountMode,
          'canCreate': accountMode == 'normal' && accountWorkplaces.isEmpty,
          if (staffConflict != null) 'staffConflict': staffConflict,
        },
        'records': accountWorkplaces,
        'nextCursor': null,
      };
    if (name == 'organizationSettings' &&
        const ['create', 'createLegacy', 'restore'].contains(d['action']) &&
        (accountMode != 'normal' || accountWorkplaces.isNotEmpty)) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'org_staff_account',
      );
    }
    if (name == 'calendarView') return _calendarPreview(d);
    final operational = _operationalPreview(name, d);
    if (operational != null) return operational;
    if (name == 'leaseLifecycle') {
      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          (assignedOnly && d['buildingId'] != 'riverside')) {
        reject();
      }
      final tenant = record(tenants, d['tenantId']),
          building = record(buildings, d['buildingId']);
      final key = 'lease-$workspaceRole-${d['operationId']}';
      if (completed.containsKey(key)) return completed[key]!;
      if (tenant['buildingId'] != d['buildingId']) reject();
      if (d['action'] == 'history') {
        return {'records': leaseHistory[d['tenantId']] ?? []};
      }
      if (d['action'] == 'destinations') {
        return {
          'records': rooms
              .where(
                (v) =>
                    v['id'] != tenant['roomId'] &&
                    (!assignedOnly || v['buildingId'] == 'riverside'),
              )
              .map(
                (v) => {
                  ...v,
                  'mainTenants': tenants
                      .where(
                        (t) =>
                            t['roomId'] == v['id'] &&
                            t['isMainTenant'] == true &&
                            t['status'] == 'active',
                      )
                      .toList(),
                },
              )
              .toList(),
        };
      }
      final zone = building['timeZone'];
      if (zone == null) reject();
      final linked = tenants
          .where(
            (t) =>
                t['mainTenantId'] == tenant['id'] &&
                ['active', 'suspended'].contains(t['status']),
          )
          .toList();
      if (d['action'] == 'read') {
        return {
          'record': {
            ...tenant,
            'timeZone': zone,
            'today': '2026-09-27',
            'startDate': tenant['moveInLocalDate'] ?? '2026-09-01',
            'contractEndDate': tenant['contractEndLocalDate'],
            'roommates': linked,
            'canBackdate': workspaceRole != 'manager',
          },
        };
      }
      if (d['revision'] != tenant['revision']) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
      }
      if (d['action'] != 'terms' && linked.isNotEmpty) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'lease_handle_roommates_first',
        );
      }
      final before = Map<String, dynamic>.from(tenant);
      if (d['action'] == 'terms') {
        tenant['contractEndLocalDate'] = d['contractEndDate'];
      }
      if (d['action'] == 'moveOut') {
        tenant['status'] = 'moveOut';
        tenant['moveOutDate'] = d['effectiveDate'];
        tenant['canEditRent'] = false;
        tenant['canAddRoommate'] = false;
      }
      if (d['action'] == 'move') {
        final room = record(rooms, d['destinationRoomId']);
        if (tenants.any(
              (t) => t['roomId'] == room['id'] && t['status'] == 'active',
            ) &&
            tenant['isMainTenant'] == true) {
          throw FirebaseFunctionsException(
            code: 'already-exists',
            message: 'Occupied',
          );
        }
        tenant['roomId'] = room['id'];
        tenant['buildingId'] = room['buildingId'];
        tenant['mainTenantId'] = d['destinationMainTenantId'];
      }
      tenant['revision'] =
          '${int.parse((tenant['revision'] as String).split(':').first) + 1}:0';
      leaseHistory.putIfAbsent(tenant['id'] as String, () => []).insert(0, {
        'id': key,
        'action': d['action'],
        'actorId': 'preview-$workspaceRole',
        'createdAt': '2026-09-27T12:00:00Z',
        'reason': d['reason'],
        'before': before,
        'after': Map.of(tenant),
      });
      return completed[key] = {
        'tenantId': tenant['id'],
        'buildingId': tenant['buildingId'],
        'roomId': tenant['roomId'],
      };
    }
    if (name == 'tenantRent') {
      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          (workspaceRole == 'manager' && !priceOverride) ||
          (assignedOnly && d['buildingId'] != 'riverside')) {
        reject();
      }
      final building = record(buildings, d['buildingId']),
          tenant = record(tenants, d['tenantId']);
      if (tenant['buildingId'] != d['buildingId']) reject();
      if (d['action'] == 'history') {
        final rows = rentHistory[d['tenantId']] ?? [],
            offset = d['cursor'] == null
                ? 0
                : rows.indexWhere((r) => r['id'] == d['cursor']) + 1;
        final page = rows.skip(offset).take(20).toList();
        return {
          'records': page,
          'nextCursor': offset + page.length < rows.length
              ? page.last['id']
              : null,
        };
      }
      final key = 'rent-$workspaceRole-${d['operationId']}';
      if (d['action'] != 'read' && completed.containsKey(key)) {
        return completed[key]!;
      }
      final zone = tenant['rentTimeZone'] ?? building['timeZone'];
      if (zone == null ||
          tenant['isMainTenant'] != true ||
          !['active', 'suspended'].contains(tenant['status'])) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'unavailable',
        );
      }
      final changes = List<Map<String, dynamic>>.from(
            tenant['rentSchedule'] as List? ?? [],
          ),
          base = tenant['monthlyRentMinor'] as int;
      var current = base;
      for (final c in changes) {
        if ((c['effectiveDate'] as String).compareTo('2026-09-27') <= 0) {
          current = c['amountMinor'] as int;
        }
      }
      if (d['action'] == 'read') {
        return {
          'record': {
            'fullName': tenant['fullName'],
            'roomId': tenant['roomId'],
            'revision': tenant['revision'],
            'currency': tenant['currency'] ?? 'VND',
            'timeZone': zone,
            'today': '2026-09-27',
            'startDate': tenant['moveInLocalDate'],
            'baseMinor': base,
            'currentMinor': current,
            'changes': changes,
          },
        };
      }
      if (d['revision'] != tenant['revision'] || d['timeZone'] != zone) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'changed');
      }
      if ((d['effectiveDate'] as String).compareTo('2026-09-27') <= 0 ||
          (d['reason'] as String).trim().isEmpty) {
        throw FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'date',
        );
      }
      final before = changes
          .where((c) => c['effectiveDate'] == d['effectiveDate'])
          .firstOrNull;
      changes.removeWhere((c) => c['effectiveDate'] == d['effectiveDate']);
      if (d['action'] == 'schedule') {
        changes.add({
          'effectiveDate': d['effectiveDate'],
          'amountMinor': d['amountMinor'],
        });
      }
      changes.sort(
        (a, b) => (a['effectiveDate'] as String).compareTo(
          b['effectiveDate'] as String,
        ),
      );
      tenant['rentSchedule'] = changes;
      rentHistory.putIfAbsent(tenant['id'] as String, () => []).insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'createdAt': '2026-09-27T12:00:00Z',
        'effectiveDate': d['effectiveDate'],
        'timeZone': zone,
        'currency': tenant['currency'] ?? 'VND',
        'reason': d['reason'],
        'before': before == null ? null : Map.of(before),
        'after': d['action'] == 'cancel'
            ? null
            : {
                'effectiveDate': d['effectiveDate'],
                'amountMinor': d['amountMinor'],
              },
      });
      tenant['rentTimeZone'] = zone;
      tenant['revision'] =
          '${int.parse((tenant['revision'] as String).split(':').first) + 1}:0';
      return completed[key] = {'tenantId': tenant['id']};
    }
    if (name == 'tenantRoommates') {
      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          (assignedOnly && d['buildingId'] != 'riverside')) {
        reject();
      }
      final building = record(buildings, d['buildingId']),
          main = record(tenants, d['mainTenantId']);
      if (main['buildingId'] != d['buildingId']) reject();
      final key = 'roommate-$workspaceRole-${d['operationId']}';
      if (d['action'] == 'create' && completed.containsKey(key)) {
        return completed[key]!;
      }
      if (main['isMainTenant'] != true ||
          main['status'] != 'active' ||
          main['moveOutDate'] != null) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'unavailable',
        );
      }
      if (building['timeZone'] == null) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'lease_property_timezone_required',
        );
      }
      final room = record(rooms, main['roomId']);
      if (d['action'] == 'prepare') {
        return {
          'record': {
            'mainName': main['fullName'],
            'mainRevision': main['revision'],
            'roomRevision': room['revision'],
            'roomNumber': room['roomNumber'],
            'timeZone': building['timeZone'],
            'today': '2026-09-27',
            'earliestDate': main['moveInLocalDate'],
            'canBackdate': workspaceRole != 'manager',
          },
        };
      }
      if (d['mainRevision'] != main['revision'] ||
          d['roomRevision'] != room['revision'] ||
          d['timeZone'] != building['timeZone']) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'changed');
      }
      if ((d['moveInDate'] as String).compareTo(
            main['moveInLocalDate'] as String,
          ) <
          0) {
        throw FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'before main',
        );
      }
      if ((d['moveInDate'] as String).compareTo('2026-09-27') < 0) {
        if (workspaceRole == 'manager') reject();
        if ((d['backdateReason'] as String).trim().isEmpty) {
          throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'reason',
          );
        }
      }
      tenants.add({
        'id': key,
        'buildingId': d['buildingId'],
        'roomId': main['roomId'],
        'mainTenantId': main['id'],
        'isMainTenant': false,
        'fullName': d['fullName'],
        'phoneNumber': d['phoneNumber'],
        'status': 'active',
        'moveInLocalDate': d['moveInDate'],
        'revision': '1:0',
        // CCCD and tạm trú (2026-10-04), stored like the server does.
        if (d['nationalId'] != null) 'nationalId': d['nationalId'],
        if (d['residenceRegistered'] != null)
          'residenceRegistered': d['residenceRegistered'],
        if (d['residenceDate'] != null)
          'residenceRegisteredLocalDate': d['residenceDate'],
      });
      room['revision'] =
          '${int.parse((room['revision'] as String).split(':').first) + 1}:0';
      activity.insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'action': 'roommate_created',
        'targetId': key,
        'createdAt': '2026-09-27T12:00:00Z',
        'after': {
          'buildingId': d['buildingId'],
          'roomId': main['roomId'],
          'mainTenantId': main['id'],
        },
      });
      return completed[key] = {'tenantId': key};
    }
    if (name == 'tenantLeases') {
      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          (assignedOnly && d['buildingId'] != 'riverside')) {
        reject();
      }
      final building = record(buildings, d['buildingId']);
      // 2026-10-04: a lease's surcharges edited later.
      if (d['action'] == 'surcharges') {
        final row = record(tenants, d['tenantId']);
        if (row['buildingId'] != d['buildingId'] || row['isMainTenant'] != true)
          reject();
        final rows = [
          for (final (i, c) in (d['surcharges'] as List).indexed)
            {
              ...Map<String, dynamic>.from(c as Map),
              'id':
                  (c['id'] as String?) ??
                  'sc_${row['id']}_${DateTime.now().microsecondsSinceEpoch}_$i',
            },
        ];
        row['surcharges'] = rows;
        return {'surcharges': rows};
      }
      if (d['action'] == 'rooms') {
        final rows =
            rooms
                .where(
                  (r) =>
                      r['buildingId'] == d['buildingId'] &&
                      (d['cursor'] == null ||
                          (r['id'] as String).compareTo(d['cursor'] as String) >
                              0),
                )
                .toList()
              ..sort(
                (a, b) => (a['id'] as String).compareTo(b['id'] as String),
              );
        return {
          'records': rows
              .take(25)
              .map(
                (r) => {
                  'id': r['id'],
                  'roomNumber': r['roomNumber'],
                  // 2026-10-04: every room takes leases.
                  'monthly': true,
                },
              )
              .toList(),
          'nextCursor': rows.length > 25 ? rows[24]['id'] : null,
        };
      }
      final room = record(rooms, d['roomId']);
      if (room['buildingId'] != d['buildingId']) reject();
      final key = 'lease-$workspaceRole-${d['operationId']}';
      if (d['action'] == 'create' && completed.containsKey(key)) {
        return completed[key]!;
      }
      if (building['timeZone'] == null) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'lease_property_timezone_required',
        );
      }
      final currency = room['currency'] ?? building['currency'] ?? 'VND';
      if (d['action'] == 'prepare') {
        return {
          'record': {
            'roomNumber': room['roomNumber'],
            'roomRevision': room['revision'],
            'currency': currency,
            'timeZone': building['timeZone'],
            'today': '2026-09-27',
            'canBackdate': workspaceRole != 'manager',
            'canPrice': workspaceRole != 'manager' || priceOverride,
          },
        };
      }
      if (d['roomRevision'] != room['revision'] ||
          d['timeZone'] != building['timeZone'] ||
          d['currency'] != currency) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'changed');
      }
      if ((d['moveInDate'] as String).compareTo('2026-09-27') < 0) {
        if (workspaceRole == 'manager') reject();
        if ((d['backdateReason'] as String).trim().isEmpty) {
          throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'reason',
          );
        }
      }
      if (tenants.any(
        (t) =>
            t['roomId'] == d['roomId'] &&
            ['active', 'suspended'].contains(t['status']),
      )) {
        throw FirebaseFunctionsException(
          code: 'already-exists',
          message: 'occupied',
        );
      }
      tenants.add({
        'id': key,
        'buildingId': d['buildingId'],
        'roomId': d['roomId'],
        'fullName': d['fullName'],
        'phoneNumber': d['phoneNumber'],
        'status': 'active',
        'isMainTenant': true,
        'canAddRoommate': true,
        'canEditRent': true,
        'moveInLocalDate': d['moveInDate'],
        'contractEndLocalDate': d['contractEndDate'],
        'monthlyRentMinor': d['rentMinor'],
        'currency': currency,
        'revision': '1:0',
        // B3 details, stored like the server does (deposit only when given).
        for (final k in [
          'nationalId',
          'residenceRegistered',
          'staffInChargeId',
          'depositMethod',
          'depositNote',
        ])
          if (d[k] != null) k: d[k],
        if (d['periodMonths'] != null) 'paymentPeriodMonths': d['periodMonths'],
        if (d['dueDay'] != null) 'paymentDueDay': d['dueDay'],
        if (d['periodMonths'] != null)
          'periodRentMinor':
              d['periodAmountMinor'] ??
              (d['rentMinor'] as int) * (d['periodMonths'] as int),
        if (d['depositMinor'] != null) 'deposit': d['depositMinor'],
        if (d['depositMinor'] != null) 'depositMinor': d['depositMinor'],
        if (d['surcharges'] != null)
          'surcharges': [
            for (final (i, c) in (d['surcharges'] as List).indexed)
              {...Map<String, dynamic>.from(c as Map), 'id': 'sc_${key}_$i'},
          ],
      });
      for (final (i, c) in ((d['coTenants'] as List?) ?? const []).indexed) {
        final m = Map<String, dynamic>.from(c as Map);
        tenants.add({
          'id': '$key-co$i',
          'buildingId': d['buildingId'],
          'roomId': d['roomId'],
          'fullName': m['fullName'],
          'phoneNumber': m['phoneNumber'] ?? '',
          if (m['nationalId'] != null) 'nationalId': m['nationalId'],
          'residenceRegistered': m['residenceRegistered'] == true,
          'status': 'active',
          'isMainTenant': false,
          'mainTenantId': key,
          'moveInLocalDate': d['moveInDate'],
          'currency': currency,
          'revision': '1:0',
        });
      }
      room['revision'] =
          '${int.parse((room['revision'] as String).split(':').first) + 1}:0';
      activity.insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'action': 'lease_create',
        'targetId': key,
        'createdAt': '2026-09-27T12:00:00Z',
        'after': {
          'buildingId': d['buildingId'],
          'roomId': d['roomId'],
          'status': 'active',
          'currency': currency,
        },
      });
      return completed[key] = {'tenantId': key};
    }
    // Like the server projection: permissions and the main tenant's name.
    Map<String, dynamic> contact(Map<String, dynamic> r) => {
      ...r,
      'stayStatus': r['status'] == 'moveOut'
          ? 'checkedOut'
          : '${r['moveInLocalDate'] ?? ''}'.compareTo('2026-09-27') > 0
          ? (((r['depositMinor'] as num?) ?? 0) > 0
                ? 'deposited'
                : 'notCheckedIn')
          : 'staying',
      'canReadRentHistory': workspaceRole != 'manager' || priceOverride,
      'canEditRent':
          r['canEditRent'] == true &&
          (workspaceRole != 'manager' || priceOverride),
      if (r['mainTenantId'] != null)
        'mainTenantName':
            tenants
                .where((t) => t['id'] == r['mainTenantId'])
                .firstOrNull?['fullName'] ??
            '',
    };
    if (name == 'tenantContacts') {
      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          (assignedOnly && d['buildingId'] != 'riverside')) {
        reject();
      }
      record(buildings, d['buildingId']);
      if (d['action'] == 'list') {
        final rows =
            tenants
                .where(
                  (r) =>
                      r['buildingId'] == d['buildingId'] &&
                      (d['cursor'] == null ||
                          (r['id'] as String).compareTo(d['cursor'] as String) >
                              0),
                )
                .toList()
              ..sort(
                (a, b) => (a['id'] as String).compareTo(b['id'] as String),
              );
        return {
          'records': rows.take(25).map(contact).toList(),
          'nextCursor': rows.length > 25 ? rows[24]['id'] : null,
        };
      }
      final row = record(tenants, d['tenantId']);
      if (row['buildingId'] != d['buildingId']) reject();
      if (d['action'] == 'read') {
        return {
          'record': {
            ...contact(row),
            // The people living with a main tenant (2026-10-04).
            'roommates': [
              if (row['isMainTenant'] == true)
                for (final t in tenants)
                  if (t['mainTenantId'] == row['id'] &&
                      t['status'] == 'active' &&
                      t['moveOutLocalDate'] == null)
                    {
                      'id': t['id'],
                      'fullName': t['fullName'],
                      'moveInLocalDate': t['moveInLocalDate'] ?? '',
                    },
            ],
          },
        };
      }
      final key = 'tenant-contact-$workspaceRole-${d['operationId']}';
      if (completed.containsKey(key)) return completed[key]!;
      if (row['revision'] != d['revision']) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
      }
      row['fullName'] = d['fullName'];
      row['phoneNumber'] = d['phoneNumber'];
      row['revision'] =
          '${int.parse((row['revision'] as String).split(':').first) + 1}:0';
      activity.insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'action': 'tenant_contact_updated',
        'targetId': row['id'],
        'createdAt': '2026-09-27T12:00:00Z',
        'after': {
          'buildingId': row['buildingId'],
          'roomId': row['roomId'],
          'changedFields': ['fullName', 'phoneNumber'],
        },
      });
      return completed[key] = {'tenantId': row['id']};
    }
    if (name == 'propertyContract') {
      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          (assignedOnly && d['buildingId'] != 'riverside')) {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Denied',
        );
      }
      final b = record(buildings, d['buildingId']);
      if (d['action'] == 'history') {
        final rows = contractHistory[d['buildingId']] ?? [];
        final cursor = d['cursor'];
        final index = cursor == null
            ? -1
            : rows.indexWhere((r) => r['id'] == cursor);
        if (cursor != null && index < 0) reject();
        final page = rows.skip(index + 1).take(20).toList();
        return {
          'records': jsonDecode(jsonEncode(page)),
          'nextCursor': index + 1 + page.length < rows.length
              ? page.last['id']
              : null,
        };
      }

      if (d['action'] == 'read') {
        return {
          'record': {
            'name': b['name'],
            'revision': b['revision'] ?? '1:0',
            'currency': b['currency'] ?? 'VND',
            'contract': b['rentalContract'],
            'legacy': {
              for (final k in [
                'renterName',
                'renterPhone',
                'rentAmount',
                'rentDueDay',
                'rentContractStart',
                'rentContractEnd',
                'renterNotes',
              ])
                if (b[k] != null) k: b[k],
            },
          },
        };
      }
      final key = 'contract-$workspaceRole-${d['operationId']}';
      if (completed.containsKey(key)) return completed[key]!;
      if ((b['revision'] ?? '1:0') != d['revision'] ||
          (b['currency'] ?? 'VND') != d['currency']) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
      }
      contractHistory.putIfAbsent(b['id'] as String, () => []).insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'currency': b['currency'] ?? 'VND',
        'createdAt': '2026-09-27T12:00:00.000Z',
        'before': jsonDecode(jsonEncode(b['rentalContract'])),
        'after': jsonDecode(jsonEncode(d['contract'])),
      });
      b['rentalContract'] = jsonDecode(jsonEncode(d['contract']));
      b['revision'] =
          '${int.parse(((b['revision'] ?? '1:0') as String).split(':').first) + 1}:0';
      activity.insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'action': 'property_contract_updated',
        'targetId': b['id'],
        'createdAt': '2026-09-27T12:00:00Z',
        'after': {
          'buildingId': b['id'],
          'direction': d['contract']['direction'],
          'status': d['contract']['status'],
        },
      });
      return completed[key] = {'buildingId': b['id']};
    }
    if (name == 'roomBookingSettings') {
      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          (assignedOnly && d['buildingId'] != 'riverside')) {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Denied',
        );
      }
      final building = record(buildings, d['buildingId']),
          room = record(rooms, d['roomId']);
      if (room['buildingId'] != d['buildingId']) reject();
      const fields = [
        'minBookingHours',
        'cleaningBufferMinutes',
        'operatingHoursStartMin',
        'operatingHoursEndMin',
        'operatingSchedule',
      ];
      if (d['action'] == 'read') {
        return {
          'record': {
            'roomNumber': room['roomNumber'],
            'revision': room['revision'],
            'timeZone': building['timeZone'],
            for (final f in fields)
              f:
                  room[f] ??
                  (f == 'minBookingHours' || f == 'cleaningBufferMinutes'
                      ? 0
                      : null),
          },
        };
      }
      final key = 'settings-$workspaceRole-${d['operationId']}';
      if (completed.containsKey(key)) return completed[key]!;
      if (room['revision'] != d['revision'] ||
          building['timeZone'] != d['timeZone']) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
      }
      if ((d['operatingHoursStartMin'] != null ||
              d['operatingSchedule'] != null) &&
          building['timeZone'] == null) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'settings_timezone_required',
        );
      }
      for (final f in fields) {
        room[f] = d[f];
      }
      room['revision'] =
          '${int.parse((room['revision'] as String).split(':').first) + 1}:0';
      activity.insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'action': 'room_booking_settings_updated',
        'targetId': room['id'],
        'createdAt': '2026-09-26T12:00:00Z',
        'after': {
          for (final f in fields) f: room[f],
          'timeZone': building['timeZone'],
        },
      });
      final result = <String, dynamic>{'roomId': room['id']};
      completed[key] = result;
      return result;
    }
    if (name == 'roomRates') {
      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          !priceOverride ||
          (assignedOnly && d['buildingId'] != 'riverside')) {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Denied',
        );
      }
      final room = record(rooms, d['roomId']);
      if (room['buildingId'] != d['buildingId']) reject();
      final currency = room['currency'] ?? 'VND',
          factor = currency == 'USD' ? 100 : 1;
      // Same as the server (2026-10-04): monthly, per night, per hour; an
      // older day price is shown as the night price.
      const fields = ['roomPrice', 'nightlyPrice', 'hourlyPrice'];
      num? stored(String f) =>
          (f == 'nightlyPrice'
                  ? room['nightlyPrice'] ?? room['dailyPrice']
                  : room[f])
              as num?;
      if (d['action'] == 'read') {
        return {
          'record': {
            'roomId': room['id'],
            'roomNumber': room['roomNumber'],
            'currency': currency,
            'rentalMode': 'both',
            'revision': room['revision'],
            'ratesMinor': {
              for (final f in fields)
                f: stored(f) == null ? null : (stored(f)! * factor).round(),
            },
          },
        };
      }
      final key = 'rates-$workspaceRole-${d['operationId']}';
      if (completed.containsKey(key)) return completed[key]!;
      if (room['revision'] != d['revision']) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
      }
      final rates = d['ratesMinor'] as Map;
      if (d.containsKey('dailyPriceThresholdHours') ||
          rates.keys.toSet().difference(fields.toSet()).isNotEmpty) {
        reject();
      }
      // Every room takes both; each price is optional (2026-10-04).
      room['rentalMode'] = 'both';
      room['dailyPrice'] = null;
      room['overnightPrice'] = null;
      room['dailyPriceThresholdHours'] = null;
      for (final f in fields) {
        room[f] = rates[f] == null ? null : (rates[f] as num) / factor;
      }
      room['revision'] =
          '${int.parse((room['revision'] as String).split(':').first) + 1}:0';
      activity.insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'action': 'room_rates_updated',
        'targetId': room['id'],
        'createdAt': '2026-09-26T12:00:00Z',
        'after': {
          'currency': currency,
          'rentalMode': room['rentalMode'],
          for (final f in fields) f: room[f],
        },
      });
      final result = <String, dynamic>{'roomId': room['id']};
      completed[key] = result;
      return result;
    }
    if (name == 'roomDetails') {
      if (d['action'] == 'delete') {
        if (d['organizationId'] != 'preview' ||
            assignedOnly ||
            !['owner', 'administrator'].contains(workspaceRole)) {
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Denied',
          );
        }
        final key = 'room-$workspaceRole-${d['operationId']}';
        if (completed.containsKey(key)) return completed[key]!;
        final row = record(rooms, d['roomId']);
        record(buildings, d['buildingId']);
        if (row['buildingId'] != d['buildingId']) reject();
        if (d['revision'] != (row['revision'] ?? '1:0')) {
          throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
        }
        if (tasks.any((r) => r['roomId'] == row['id']) ||
            activity.any(
              (a) =>
                  (a['before'] as Map?)?['roomId'] == row['id'] ||
                  (a['after'] as Map?)?['roomId'] == row['id'],
            )) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'room_not_empty',
          );
        }
        rooms.remove(row);
        activity.insert(0, {
          'id': key,
          'actorId': 'preview-$workspaceRole',
          'action': 'room_deleted',
          'targetId': row['id'],
          'createdAt': '2026-09-26T12:00:00Z',
          'before': {
            'buildingId': row['buildingId'],
            'roomNumber': row['roomNumber'],
          },
          'after': null,
        });
        final result = <String, dynamic>{'roomId': row['id'], 'deleted': true};
        completed[key] = result;
        return result;
      }

      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          (assignedOnly && d['buildingId'] != 'riverside')) {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Preview access denied',
        );
      }
      final building = record(buildings, d['buildingId']);
      if (d['action'] == 'prepareCreate') {
        return {
          'record': {
            'id': d['roomId'],
            'roomNumber': building['roomPrefix'] ?? '',
            'roomType': building['roomType'] ?? '',
            'area': building['roomArea'] ?? 0,
            'revision': 'new',
            'currency': building['currency'] ?? 'VND',
          },
        };
      }
      final creating = d['action'] == 'create';
      final key = 'room-$workspaceRole-${d['operationId']}';
      if (d['action'] != 'read' && completed.containsKey(key)) {
        return completed[key]!;
      }
      if (creating && rooms.any((r) => r['id'] == d['roomId'])) reject();
      final row = creating
          ? <String, dynamic>{
              'id': d['roomId'],
              'buildingId': d['buildingId'],
              'revision': '0:0',
              'currency': building['currency'] ?? 'VND',
              'rentalMode': 'both',
            }
          : record(rooms, d['roomId']);
      if (row['buildingId'] != d['buildingId']) reject();
      if (d['action'] == 'read') return {'record': Map.of(row)};
      if (!creating && d['revision'] != row['revision']) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
      }
      if (rooms.any(
        (r) =>
            r['id'] != row['id'] &&
            r['buildingId'] == row['buildingId'] &&
            (r['roomNumber'] as String).trim().toLowerCase() ==
                (d['roomNumber'] as String).trim().toLowerCase(),
      )) {
        throw FirebaseFunctionsException(
          code: 'already-exists',
          message: 'Duplicate',
        );
      }
      final before = {
        for (final field in ['roomNumber', 'roomType', 'area'])
          field: row[field],
      };
      for (final field in ['roomNumber', 'roomType', 'area']) {
        row[field] = d[field];
      }
      row['revision'] =
          '${int.parse((row['revision'] as String).split(':').first) + 1}:0';
      if (creating) rooms.add(row);
      activity.insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'action': creating ? 'room_created' : 'room_details_updated',
        'targetId': row['id'],
        'createdAt': '2026-09-26T12:00:00Z',
        'before': creating ? null : before,
        'after': {
          for (final field in ['roomNumber', 'roomType', 'area'])
            field: row[field],
        },
      });
      final result = <String, dynamic>{'roomId': row['id']};
      completed[key] = result;
      return result;
    }
    if (name == 'propertyDetails') {
      if (d['action'] == 'delete') {
        if (d['organizationId'] != 'preview' ||
            assignedOnly ||
            !['owner', 'administrator'].contains(workspaceRole)) {
          throw FirebaseFunctionsException(
            code: 'permission-denied',
            message: 'Denied',
          );
        }
        final key = 'property-$workspaceRole-${d['operationId']}';
        if (completed.containsKey(key)) return completed[key]!;
        final row = record(buildings, d['buildingId']);
        if (d['revision'] != (row['revision'] ?? '1:0')) {
          throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
        }
        if (row['rentalContract'] != null ||
            rooms.any((r) => r['buildingId'] == row['id']) ||
            tasks.any((r) => r['buildingId'] == row['id'])) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'property_not_empty',
          );
        }
        buildings.remove(row);
        activity.insert(0, {
          'id': key,
          'actorId': 'preview-$workspaceRole',
          'action': 'property_deleted',
          'targetId': row['id'],
          'createdAt': '2026-09-26T12:00:00Z',
          'before': {'name': row['name'], 'address': row['address']},
          'after': null,
        });
        final result = <String, dynamic>{
          'buildingId': row['id'],
          'deleted': true,
        };
        completed[key] = result;
        return result;
      }

      final creating = d['action'] == 'create';
      final preparing = d['action'] == 'prepareCreate';
      if (d['organizationId'] != 'preview' ||
          !['owner', 'administrator', 'manager'].contains(workspaceRole) ||
          (assignedOnly &&
              (creating || preparing || d['buildingId'] != 'riverside'))) {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Preview access denied',
        );
      }
      if (preparing) {
        return {
          'record': {
            'id': d['buildingId'],
            'name': '',
            'address': '',
            'timeZone': 'Asia/Ho_Chi_Minh',
            'currency': 'VND',
            'revision': 'new',
            'canSetRoomPrices': true,
            'exploitationCostMinor': null,
          },
        };
      }
      if (creating) {
        final key = 'property-$workspaceRole-${d['operationId']}';
        if (completed.containsKey(key)) return completed[key]!;
        if (buildings.any((row) => row['id'] == d['buildingId'])) {
          throw FirebaseFunctionsException(
            code: 'already-exists',
            message: 'Property exists',
          );
        }
        buildings.add({
          'id': d['buildingId'],
          'name': d['name'],
          'address': d['address'],
          'timeZone': d['timeZone'],
          'currency': d['currency'],
          'exploitationCostMinor': d['exploitationCostMinor'],
          'revision': '1:0',
        });
        for(final (index,room) in ((d['rooms'] as List?)??[]).indexed) {
          final r=Map<String,dynamic>.from(room as Map);
          rooms.add({'id':'${d['buildingId']}-initial-$index','buildingId':d['buildingId'],
            'organizationId':'preview','roomNumber':r['roomNumber'],'roomType':r['roomType'],
            'area':r['area']??0,'currency':d['currency'],'rentalMode':'both',
            for(final k in ['roomPrice','nightlyPrice','hourlyPrice']) k:
              r['ratesMinor'][k]==null?null:(r['ratesMinor'][k] as num)/(d['currency']=='USD'?100:1)});
        }
        activity.insert(0, {
          'id': key,
          'actorId': 'preview-$workspaceRole',
          'action': 'property_created',
          'targetId': d['buildingId'],
          'createdAt': '2026-09-26T12:00:00Z',
          'after': {
            'name': d['name'],
            'address': d['address'],
            'timeZone': d['timeZone'],
            'currency': d['currency'],
          },
        });
        final result = <String, dynamic>{'buildingId': d['buildingId']};
        completed[key] = result;
        return result;
      }
      final row = record(buildings, d['buildingId']);
      if (d['action'] == 'read') {
        return {
          'record': {
            'id': row['id'],
            'name': row['name'],
            'address': row['address'] ?? '14 Tân Thái, Đà Nẵng',
            'timeZone': row['timeZone'],
            'currency': row['currency'] ?? 'VND',
            'exploitationCostMinor': row['exploitationCostMinor'],
            'revision': row['revision'] ?? '1:0',
          },
        };
      }
      final key = 'property-$workspaceRole-${d['operationId']}';
      if (completed.containsKey(key)) return completed[key]!;
      if (d['revision'] != (row['revision'] ?? '1:0')) {
        throw FirebaseFunctionsException(code: 'aborted', message: 'Changed');
      }
      if (d.containsKey('timeZone')) {
        if (d['timeZone'] != row['timeZone'] &&
            rooms.any(
              (r) =>
                  r['buildingId'] == row['id'] &&
                  (r['operatingSchedule'] != null ||
                      r['operatingHoursStartMin'] != null ||
                      r['operatingHoursEndMin'] != null),
            )) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'property_timezone_in_use',
          );
        }
        row['timeZone'] = d['timeZone'];
      }
      if(d.containsKey('exploitationCostMinor')) row['exploitationCostMinor']=d['exploitationCostMinor'];
      row['name'] = d['name'];
      row['address'] = d['address'];
      row['revision'] =
          '${int.parse((row['revision'] as String? ?? '1:0').split(':').first) + 1}:0';
      activity.insert(0, {
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'action': 'property_details_updated',
        'targetId': row['id'],
        'createdAt': '2026-09-26T12:00:00Z',
        'after': {'name': d['name'], 'address': d['address']},
      });
      final result = <String, dynamic>{'buildingId': row['id']};
      completed[key] = result;
      return result;
    }
    if (name == 'mutateHousekeepingTask') {
      if (d['organizationId'] != 'preview') reject();
      final manager = [
        'owner',
        'administrator',
        'manager',
      ].contains(workspaceRole);
      final key = 'task-$workspaceRole-${d['operationId']}';
      if (completed.containsKey(key)) return completed[key]!;
      if (d['action'] == 'assign') {
        if (!manager || d['assigneeId'] != 'preview-housekeeper') reject();
        tasks.add({
          'id': d['taskId'],
          'title': d['title'],
          'roomId': d['roomId'],
          'assigneeId': d['assigneeId'],
          'buildingId': d['buildingId'],
          'status': 'assigned',
        });
      } else {
        final task = record(tasks, d['taskId']);
        if (!manager && task['assigneeId'] != 'preview-$workspaceRole') {
          reject();
        }
        task['status'] = d['status'];
      }
      final result = {
        'taskId': d['taskId'],
        'status': d['status'] ?? 'assigned',
      };
      completed[key] = result;
      return result;
    }
    if (name == 'mutateStandalonePayment') {
      if (d['paymentId'] != 'payment') {
        final row = record(operationalInvoices, d['paymentId']);
        if (row['direction'] == 'expense' ||
            ![
              'owner',
              'administrator',
              'manager',
              'receptionist',
              'accountant',
            ].contains(workspaceRole) ||
            (d['action'] == 'refund' &&
                ![
                  'owner',
                  'administrator',
                  'accountant',
                ].contains(workspaceRole))) {
          reject();
        }
        final key = 'invoice-payment-$workspaceRole-${d['operationId']}';
        if (completed.containsKey(key)) return completed[key]!;
        final next =
            (row['paidMinor'] as int) +
            (d['action'] == 'collect' ? 1 : -1) * (d['amountMinor'] as int);
        if (next < 0 || next > (row['totalMinor'] as int)) {
          throw FirebaseFunctionsException(
            code: 'failed-precondition',
            message: 'Amount',
          );
        }
        row['paidMinor'] = next;
        row['status'] = next == row['totalMinor']
            ? 'paid'
            : next == 0
            ? 'refunded'
            : 'partial';
        row['revision'] =
            '${int.parse((row['revision'] as String).split(':').first) + 1}:0';
        return completed[key] = {
          'paymentId': row['id'],
          'operationId': d['operationId'],
          'paidMinor': next,
          'totalMinor': row['totalMinor'],
          'currency': row['currency'],
          'status': row['status'],
          'recordedAt': '2026-09-27T12:00:00Z',
        };
      }

      if (d['organizationId'] != 'preview' || d['paymentId'] != 'payment') {
        reject();
      }
      final collect = [
        'owner',
        'administrator',
        'manager',
        'receptionist',
        'accountant',
      ].contains(workspaceRole);
      final refund = [
        'owner',
        'administrator',
        'accountant',
      ].contains(workspaceRole);
      if (d['action'] == 'collect' ? !collect : !refund) reject();
      final key = 'payment-$workspaceRole-${d['operationId']}';
      if (completed.containsKey(key)) return completed[key]!;
      final amount = d['amountMinor'] as int;
      final old = payment['paidAmount'] as int;
      final next = old + (d['action'] == 'collect' ? amount : -amount);
      if (amount <= 0 || next < 0 || next > (payment['amount'] as int)) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Invalid balance',
        );
      }
      payment['paidAmount'] = next;
      payment['status'] = next == payment['amount']
          ? 'paid'
          : next == 0
          ? 'refunded'
          : 'partial';
      final result = {
        'paymentId': 'payment',
        'operationId': d['operationId'],
        'paidMinor': next,
        'totalMinor': payment['amount'],
        'currency': 'VND',
        'status': payment['status'],
        'recordedAt': DateTime.now().toUtc().toIso8601String(),
      };
      completed[key] = result;
      activity.add({
        'id': key,
        'actorId': 'preview-$workspaceRole',
        'action': d['action'] == 'collect' ? 'paymentCollect' : 'paymentRefund',
        'targetId': 'payment',
        'createdAt': result['recordedAt'],
        'before': {'paidAmount': old},
        'after': {'paidAmount': next},
      });
      return result;
    }
    if (name == 'readWorkspace') {
      if (d['organizationId'] != 'preview') reject();
      if (d['view'] == 'properties') {
        return {
          'records': assignedOnly ? buildings.take(1).toList() : buildings,
        };
      }
      if (assignedOnly && d['buildingId'] != 'riverside') reject();
      if (d['view'] == 'rooms') {
        if (!['owner', 'administrator', 'manager'].contains(workspaceRole)) {
          reject();
        }
        return {
          'records': rooms
              .where((r) => r['buildingId'] == d['buildingId'])
              .map((r) => {...r, 'canEditRates': priceOverride})
              .toList(),
        };
      }
      if (['tasks', 'taskRooms', 'taskAssignees'].contains(d['view'])) {
        final manager = [
          'owner',
          'administrator',
          'manager',
        ].contains(workspaceRole);
        if (d['view'] == 'tasks') {
          if (!manager && workspaceRole != 'housekeeper') reject();
          return {
            'records': tasks
                .where(
                  (r) =>
                      r['buildingId'] == d['buildingId'] &&
                      (manager || r['assigneeId'] == 'preview-$workspaceRole'),
                )
                .toList(),
          };
        }
        if (!manager) reject();
        return {
          'records': d['view'] == 'taskRooms'
              ? rooms
                    .where((r) => r['buildingId'] == d['buildingId'])
                    .map((r) => {'id': r['id'], 'roomNumber': r['roomNumber']})
                    .toList()
              : [
                  {
                    'id': 'cleaner',
                    'ownerId': 'preview-housekeeper',
                    'displayName': 'Nguyễn Thị Lan — Nhân viên dọn phòng',
                  },
                ],
        };
      }
      if (d['view'] == 'paymentActions') {
        final collect = [
          'owner',
          'administrator',
          'manager',
          'receptionist',
          'accountant',
        ].contains(workspaceRole);
        final refund = [
          'owner',
          'administrator',
          'accountant',
        ].contains(workspaceRole);
        if (!collect && !refund) reject();
        return {
          'records': [
            {...payment, 'canCollect': collect, 'canRefund': refund},
            for (final row in operationalInvoices.where(
              (v) =>
                  v['buildingId'] == d['buildingId'] &&
                  v['direction'] != 'expense' &&
                  v['status'] != 'cancelled',
            ))
              {
                ...row,
                'amount':
                    (row['amountMinor'] as num) /
                    (row['currency'] == 'USD' ? 100 : 1),
                'paidAmount':
                    (row['paidMinor'] as num) /
                    (row['currency'] == 'USD' ? 100 : 1),
                for (final fee in [
                  'internetFee',
                  'cableTVFee',
                  'hotWaterFee',
                  'lateFee',
                  'taxAmount',
                ])
                  fee:
                      ((row['feesMinor'] as Map)[fee] as num) /
                      (row['currency'] == 'USD' ? 100 : 1),
                'canCollect': collect,
                'canRefund': refund,
              },
          ],
        };
      }
      if (d['view'] == 'bookings' &&
          ![
            'owner',
            'administrator',
            'manager',
            'receptionist',
            'accountant',
          ].contains(workspaceRole)) {
        reject();
      }
      if (d['view'] == 'financial' &&
          ![
            'owner',
            'administrator',
            'manager',
            'accountant',
          ].contains(workspaceRole)) {
        reject();
      }
      return {
        'records': [
          d['view'] == 'bookings'
              ? {
                  'id': 'booking',
                  'roomId': 'Room 101 — Riverside',
                  'guestName': 'Nguyễn Thị Minh Anh — Khách lưu trú dài ngày',
                  'startTime': '2026-09-25T14:00:00Z',
                  'endTime': '2026-09-27T10:00:00Z',
                  'status': 'confirmed',
                }
              : {
                  'id': 'payment',
                  'roomId': 'Room 101 — Riverside',
                  'amount': 1500000,
                  'paidAmount': 500000,
                  'currency': 'VND',
                  'status': 'partial',
                },
        ],
      };
    }
    if (name == 'orgRoles') return _roles(d);
    if (name == 'readTeam') {
      if (d['organizationId'] != 'preview') reject();
      final admin =
          ['owner', 'administrator'].contains(workspaceRole) && !assignedOnly;
      if (d['view'] == 'myAccess') {
        return {
          'record': {
            ...grant(workspaceRole),
            'ownerId': 'preview-$workspaceRole',
            if (assignedOnly) ...{
              'buildingScope': 'selected',
              'buildingIds': ['riverside'],
            },
          },
        };
      }
      final rows = switch (d['view']) {
        'access' => accounts,
        'staff' =>
          admin
              ? staff
              : staff
                    .where((s) => s['accountId'] == 'preview-$workspaceRole')
                    .toList(),
        'buildings' => buildings,
        'invitations' => invitations,
        'requests' => requests,
        'activity' =>
          activity
              .where(
                (r) =>
                    (admin || r['actorId'] == 'preview-$workspaceRole') &&
                    (d['actorId'] == null || r['actorId'] == d['actorId']),
              )
              .toList(),
        'myRequests' =>
          requests.where((r) => r['id'] == 'local-request').toList(),
        _ => <Map<String, dynamic>>[],
      };
      if (d['view'] == 'activity') {
        rows.sort((a, b) {
          final byTime = DateTime.parse(
            b['createdAt'] as String,
          ).compareTo(DateTime.parse(a['createdAt'] as String));
          return byTime != 0
              ? byTime
              : (b['id'] as String).compareTo(a['id'] as String);
        });
        var start = 0;
        if (d['cursor'] != null) {
          final index = rows.indexWhere((r) => r['id'] == d['cursor']);
          if (index < 0) reject();
          start = index + 1;
        }
        final limit = d['limit'] as int? ?? 25;
        final page = rows.skip(start).take(limit).toList();
        return {
          'records': page,
          'nextCursor': start + page.length < rows.length
              ? page.last['id']
              : null,
        };
      }
      return {'records': rows, 'nextCursor': null};
    }
    if (name == 'lookupTeamInvitation') {
      final invite = record(invitations, d['invitationId']);
      return {
        ...invite,
        'invitationId': invite['id'],
        'organizationId': 'preview',
        'organizationName': 'Riverside • Local preview',
        'canAccept': invite['status'] == 'pending',
        'properties': buildings
            .where(
              (b) =>
                  (invite['access'] as Map)['buildingScope'] == 'all' ||
                  ((invite['access'] as Map)['buildingIds'] as List).contains(
                    b['id'],
                  ),
            )
            .toList(),
      };
    }
    if (name != 'mutateTeam') reject();
    final operation = d['operationId'] as String;
    if (completed.containsKey(operation)) return completed[operation]!;
    final result = <String, dynamic>{'ok': true};
    if (const [
          'addStaff',
          'invite',
          'changeInvitationEmail',
          'acceptInvitation',
          'requestAccess',
          'reviewRequest',
          'setAccess',
        ].contains(d['action']) &&
        d['status'] != 'revoked' &&
        d['decision'] != 'reject') {
      final address =
          ((d['profile'] as Map?)?['email'] ??
                  d['email'] ??
                  accounts
                      .where((a) => a['ownerId'] == d['userId'])
                      .firstOrNull?['email'] ??
                  '')
              .toString()
              .trim()
              .toLowerCase();
      final reason = ownerEmails.contains(address)
          ? 'team_owner_account'
          : otherEmployerEmails.contains(address)
          ? 'team_other_employer'
          : additionalWorkplaceEmails.contains(address)
          ? 'team_other_employer'
          : null;
      if (reason != null)
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: reason,
        );
    }
    switch (d['action']) {
      case 'requestAccess':
        if (d['organizationId'] != 'preview' ||
            d['inviteCode'] != 'demo-code') {
          reject();
        }
        if (requests.any((r) => r['id'] == 'local-request')) {
          throw FirebaseFunctionsException(
            code: 'already-exists',
            message: 'team_request_exists',
          );
        }
        requests.add({
          'id': 'local-request',
          'displayName': d['displayName'],
          'email': 'requester@example.com',
          'status': 'pending',
          'canReview': true,
        });
        result.addAll({'requestId': 'local-request', 'status': 'pending'});
      case 'saveStaff':
        final profile = Map<String, dynamic>.from(d['profile'] as Map);
        if (staff.any(
          (s) => s['code'] == profile['code'] && s['id'] != d['staffId'],
        )) {
          throw FirebaseFunctionsException(
            code: 'already-exists',
            message: 'team_staff_code_exists',
          );
        }
        if (d['staffId'] == null) {
          staff.add({...profile, 'id': operation, 'canEditProfile': true});
        } else {
          record(staff, d['staffId']).addAll(profile);
        }
      case 'addStaff':
        final profile = Map<String, dynamic>.from(d['profile'] as Map);
        final email = (profile['email'] as String).trim().toLowerCase();
        if (invitations.any(
          (i) => i['email'] == email && i['status'] == 'pending',
        )) {
          throw FirebaseFunctionsException(
            code: 'already-exists',
            message: 'team_email_already_invited',
          );
        }
        staff.add({
          ...profile,
          'email': email,
          'id': operation,
          'code': 'S${staff.length + 1}',
          'employmentStatus': 'active',
          'accountId': null,
          'canEditProfile': true,
        });
        invitations.add({
          'id': operation,
          'staffId': operation,
          'email': email,
          'access': d['access'],
          'status': 'pending',
          'expiresAt': null,
          'canRevoke': true,
        });
        result.addAll({'staffId': operation, 'invitationId': operation});
      case 'changeInvitationEmail':
        record(invitations, d['invitationId'])['email'] = (d['email'] as String)
            .trim()
            .toLowerCase();
      case 'invite':
        invitations.add({
          'id': operation,
          'staffId': d['staffId'],
          'email': d['email'],
          'access': d['access'],
          'status': 'pending',
          'expiresAt': '2035-01-01T00:00:00Z',
          'canRevoke': true,
        });
        result['invitationId'] = operation;
      case 'revokeInvitation':
        record(
          invitations,
          d['invitationId'],
        ).addAll({'status': 'revoked', 'canRevoke': false});
      case 'reviewRequest':
        final request = record(requests, d['requestId']);
        if (request['status'] != 'pending') reject();
        if (d['decision'] == 'approve') _link(d['staffId'], d['access']);
        request.addAll({
          'status': d['decision'] == 'approve' ? 'approved' : 'rejected',
          'canReview': false,
        });
      case 'acceptInvitation':
        final invite = record(invitations, d['invitationId']);
        if (invite['status'] != 'pending') reject();
        _link(invite['staffId'], invite['access']);
        invite.addAll({'status': 'accepted', 'canRevoke': false});
      case 'setAccess':
        final profile = staff
            .where((s) => s['accountId'] == d['userId'])
            .firstOrNull;
        final updated = {
          ...Map<String, dynamic>.from(d['access'] as Map),
          'status': d['status'],
        };
        if (profile != null) profile['accountAccess'] = updated;
        final account = accounts
            .where((s) => s['ownerId'] == d['userId'])
            .firstOrNull;
        if (account != null) account.addAll(updated);
        if (profile == null && account == null) reject();
      default:
        reject();
    }
    completed[operation] = result;
    activity.add({
      'id': operation,
      'actorId': 'preview-owner',
      'action': d['action'],
      'targetId':
          d['staffId'] ??
          d['requestId'] ??
          d['invitationId'] ??
          d['userId'] ??
          operation,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'reason': d['reason'],
      'after':
          d['profile'] ??
          d['access'] ??
          {'status': result['status'] ?? d['decision'] ?? 'completed'},
    });
    return result;
  }

  void _link(Object? id, Object? access) {
    final profile = record(staff, id);
    if (profile['accountId'] != null) reject();
    profile.addAll({
      'accountId': 'preview-$id',
      'accountAccess': {
        ...Map<String, dynamic>.from(access as Map),
        'status': 'active',
      },
      'canManageAccess': true,
    });
  }
}
