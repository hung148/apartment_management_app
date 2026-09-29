import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'team_screen.dart';
import 'team_display.dart';
import 'activity_history.dart';
import 'housekeeping_screen.dart';
import 'property_details_screen.dart';
import 'property_contract_screen.dart';
import 'room_directory.dart';
import 'invoice_screen.dart';
import 'property_layout_screen.dart';
import 'booking_workspace_screen.dart';
import 'operational_widgets.dart';
import 'tenant_contacts_screen.dart';
import 'payment_action_form.dart';
import '../../services/payment_command_service.dart';

class RoleWorkspace extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  const RoleWorkspace({
    super.key,
    required this.organizationId,
    required this.service,
  });
  @override
  State<RoleWorkspace> createState() => _RoleWorkspaceState();
}

class _RoleWorkspaceState extends State<RoleWorkspace> {
  TeamAccess? _access;
  List<Map<String, dynamic>> _properties = [], _records = [];
  String? _building, _view, _cursor;
  bool _busy = true, _failed = false, _team = false;
  bool _activity = false;
  bool _tasks = false;
  bool _propertyDetails = false;
  bool _propertyContract = false;
  String? _newProperty;
  bool _rooms = false;
  bool _tenants = false;
  String? _operationPage;
  String _accountId = '';
  Map<String, dynamic>? _payment;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RoleWorkspace old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.service != widget.service) {
      _team = false;
      _activity = false;
      _tasks = false;
      _propertyDetails = false;
      _propertyContract = false;
      _newProperty = null;
      _rooms = false;
      _tenants = false;
      _operationPage = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      _access = null;
      _payment = null;
      _accountId = '';
      _properties = [];
      _records = [];
      _view = null;
      _building = null;
      _cursor = null;
    });
    try {
      final raw = await widget.service.myAccess(widget.organizationId);
      final access = TeamAccess.fromMap(raw ?? {});
      if (access.role == null || access.status != 'active') {
        throw StateError('No active access');
      }
      final properties = <Map<String, dynamic>>[];
      String? cursor;
      do {
        final page = await widget.service.workspace(
          widget.organizationId,
          'properties',
          cursor: cursor,
        );
        properties.addAll(page.records);
        cursor = page.nextCursor;
      } while (cursor != null);
      if (!mounted || generation != _generation) return;
      setState(() {
        _access = access;
        _accountId = raw?['ownerId'] as String? ?? '';
        _properties = properties;
        _building = properties.firstOrNull?['id'] as String?;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  Future<void> _read(String view, {bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      _view = view;
      if (!more) {
        _records = [];
        _cursor = null;
      }
    });
    try {
      final page = await widget.service.workspace(
        widget.organizationId,
        view,
        buildingId: _building,
        cursor: more ? _cursor : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _records = [if (more) ..._records, ...page.records];
        _cursor = page.nextCursor;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _records = [];
          _properties = [];
          _building = null;
          _access = null;
          _cursor = null;
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context), access = _access;
    final money = NumberFormat.decimalPattern(t.locale.languageCode);
    if (_operationPage != null && _building != null) {
      void back() {
        setState(() => _operationPage = null);
        _load();
      }

      if (_operationPage == 'invoices') {
        return InvoiceScreen(
          organizationId: widget.organizationId,
          buildingId: _building!,
          accountId: _accountId,
          service: widget.service,
          onBack: back,
        );
      }
      if (_operationPage == 'bookings') {
        return BookingWorkspaceScreen(
          organizationId: widget.organizationId,
          buildingId: _building!,
          accountId: _accountId,
          service: widget.service,
          onBack: back,
        );
      }
      return PropertyLayoutScreen(
        organizationId: widget.organizationId,
        buildingId: _building!,
        service: widget.service,
        onBack: back,
      );
    }
    if (_tenants && _building != null) {
      return TenantContactsScreen(
        organizationId: widget.organizationId,
        buildingId: _building!,
        service: widget.service,
        onBack: () {
          setState(() => _tenants = false);
          _load();
        },
      );
    }
    if (_rooms && _building != null) {
      return RoomDirectory(
        canDelete:
            access != null &&
            access.allBuildings &&
            access.allows(TeamPermission.manageOrganization),
        organizationId: widget.organizationId,
        buildingId: _building!,
        service: widget.service,
        onBack: () {
          setState(() => _rooms = false);
          _load();
        },
      );
    }
    if (_propertyContract && _building != null) {
      return PropertyContractScreen(
        organizationId: widget.organizationId,
        buildingId: _building!,
        service: widget.service,
        onBack: () {
          setState(() => _propertyContract = false);
          _load();
        },
      );
    }
    if (_newProperty != null || (_propertyDetails && _building != null)) {
      return PropertyDetailsScreen(
        organizationId: widget.organizationId,
        buildingId: _newProperty ?? _building!,
        create: _newProperty != null,
        canDelete:
            access != null &&
            access.allBuildings &&
            access.allows(TeamPermission.manageOrganization),
        service: widget.service,
        onBack: () {
          setState(() {
            _propertyDetails = false;
            _newProperty = null;
          });
          _load();
        },
      );
    }
    if (_tasks && _building != null) {
      return HousekeepingScreen(
        organizationId: widget.organizationId,
        buildingId: _building!,
        service: widget.service,
        onBack: () {
          setState(() => _tasks = false);
          _load();
        },
      );
    }
    if (_payment != null) {
      return PaymentActionForm(
        key: ValueKey('${widget.organizationId}-${_payment!['id']}'),
        organizationId: widget.organizationId,
        accountId: _accountId,
        invoice: _payment!,
        service: PaymentCommandService(
          transport: (_, data) => widget.service.mutatePayment(data),
        ),
        onBack: () {
          setState(() => _payment = null);
          _read('paymentActions');
        },
        onDenied: () {
          setState(() => _payment = null);
          _load();
        },
      );
    }
    if (_activity) {
      return ActivityHistory(
        organizationId: widget.organizationId,
        service: widget.service,
        onBack: () {
          setState(() => _activity = false);
          _load();
        },
      );
    }
    String statusLabel(Object? value) {
      final status = switch (value) {
        'checkedIn' => 'checked_in',
        'checkedOut' => 'checked_out',
        'noShow' => 'no_show',
        _ => value?.toString() ?? '',
      };
      final key =
          '${_view == 'bookings' ? 'booking' : 'payment'}_status_$status';
      return t.translationKeys.contains(key) ? t[key] : t['workspace_unknown'];
    }

    if (_team && access != null) {
      return Column(
        children: [
          TextButton(
            onPressed: () => setState(() => _team = false),
            child: Text(t['workspace_title']),
          ),
          Expanded(
            child: TeamScreen(
              organizationId: widget.organizationId,
              service: widget.service,
            ),
          ),
        ],
      );
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t['workspace_title'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (access != null)
                Text(
                  t['team_role_${access.role!.name}'],
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              if (_busy) const LinearProgressIndicator(),
              if (_failed) Text(t['workspace_denied']),
              OutlinedButton(
                onPressed: _busy ? null : _load,
                child: Text(t['team_refresh']),
              ),
              if (access != null) ...[
                Text(t['workspace_read_only']),
                if (access.allows(TeamPermission.readOwnActivity))
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _activity = true),
                    child: Text(t['activity_title']),
                  ),
                if ((access.allBuildings &&
                        access.allows(TeamPermission.manageTeam)) ||
                    access.allows(TeamPermission.readOwnActivity))
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _team = true),
                    child: Text(
                      t[access.allBuildings &&
                              access.allows(TeamPermission.manageTeam)
                          ? 'team_title'
                          : 'team_profile'],
                    ),
                  ),
                if (access.allBuildings &&
                    access.allows(TeamPermission.manageProperty))
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () =>
                              setState(() => _newProperty = const Uuid().v4()),
                    child: Text(t['property_create']),
                  ),
                if (_properties.isEmpty) Text(t['workspace_no_properties']),
                if (_properties.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _building,
                    key: ValueKey(_building),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: t['workspace_property'],
                    ),
                    items: _properties
                        .map(
                          (p) => DropdownMenuItem(
                            value: p['id'] as String,
                            child: Text(
                              p['name'] as String? ?? p['id'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                            _building = v;
                            _records = [];
                            _view = null;
                            _cursor = null;
                          }),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _properties.firstWhere((p) => p['id'] == _building)['name']
                            as String? ??
                        '',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in {
                        'invoices': TeamPermission.readFinancialReports,
                        'bookings': TeamPermission.readBookings,
                        'propertyLayout': TeamPermission.manageProperty,
                      }.entries)
                        if (access.allows(entry.value, buildingId: _building))
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _operationPage = entry.key,
                                  ),
                            child: Text(opsText(context, entry.key)),
                          ),
                      if (access.allows(
                        TeamPermission.manageProperty,
                        buildingId: _building,
                      ))
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _rooms = true),
                          child: Text(t['room_directory']),
                        ),
                      if (access.allows(
                        TeamPermission.manageLease,
                        buildingId: _building,
                      ))
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _tenants = true),
                          child: Text(t['tenant_contacts_title']),
                        ),
                      if (access.allows(
                        TeamPermission.manageProperty,
                        buildingId: _building,
                      ))
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _propertyDetails = true),
                          child: Text(t['property_details']),
                        ),
                      if (access.allows(
                            TeamPermission.manageProperty,
                            buildingId: _building,
                          ) &&
                          access.allows(
                            TeamPermission.manageLease,
                            buildingId: _building,
                          ))
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _propertyContract = true),
                          child: Text(t['contract_title']),
                        ),
                      if (access.allows(
                            TeamPermission.manageProperty,
                            buildingId: _building,
                          ) ||
                          access.allows(
                            TeamPermission.readAssignedTasks,
                            buildingId: _building,
                          ))
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _tasks = true),
                          child: Text(t['tasks_title']),
                        ),
                      if (access.allows(
                            TeamPermission.collectPayments,
                            buildingId: _building,
                          ) ||
                          access.allows(
                            TeamPermission.refundPayments,
                            buildingId: _building,
                          ))
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _read('paymentActions'),
                          child: Text(t['workspace_paymentActions']),
                        ),
                      if (access.allows(
                        TeamPermission.readBookings,
                        buildingId: _building,
                      ))
                        OutlinedButton(
                          onPressed: _busy ? null : () => _read('bookings'),
                          child: Text(t['workspace_bookings']),
                        ),
                      if (access.allows(
                        TeamPermission.readFinancialReports,
                        buildingId: _building,
                      ))
                        OutlinedButton(
                          onPressed: _busy ? null : () => _read('financial'),
                          child: Text(t['workspace_financial']),
                        ),
                    ],
                  ),
                ],
                if (_view != null) ...[
                  Text(
                    t['workspace_$_view'],
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (!_busy && _records.isEmpty) Text(t['workspace_empty']),
                  for (final r in _records)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${t['workspace_room']}: ${r['roomId'] ?? ''}',
                            ),
                            if (_view == 'bookings') ...[
                              Text(r['guestName'] as String? ?? ''),
                              Text(
                                '${teamDate(r['startTime'], t)} – ${teamDate(r['endTime'], t)}',
                              ),
                            ] else ...[
                              if (r['direction'] != null)
                                Text(
                                  opsText(context, r['direction'] as String),
                                ),
                              Text(
                                '${t['workspace_amount']}: ${money.format(r['amount'] is num ? r['amount'] : 0)} ${r['currency'] ?? ''}',
                              ),
                              Text(
                                '${t['workspace_paid']}: ${money.format(r['paidAmount'] is num ? r['paidAmount'] : 0)} ${r['currency'] ?? ''}',
                              ),
                            ],
                            Text(
                              '${t['workspace_status']}: ${statusLabel(r['status'])}',
                            ),
                            if (_view == 'paymentActions' &&
                                (r['canCollect'] == true ||
                                    r['canRefund'] == true))
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() => _payment = r),
                                child: Text(t['payment_action_title']),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_cursor != null)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _read(_view!, more: true),
                      child: Text(t['workspace_more']),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
