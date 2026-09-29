import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'tenant_lease_screen.dart';
import 'tenant_rent_screen.dart';
import 'tenant_rent_history.dart';
import 'lease_lifecycle_screen.dart';

class TenantContactsScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;
  final VoidCallback onBack;
  const TenantContactsScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.onBack,
  });
  @override
  State<TenantContactsScreen> createState() => _TenantContactsScreenState();
}

class _TenantContactsScreenState extends State<TenantContactsScreen> {
  final _name = TextEditingController(), _phone = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _pending;
  String? _selected, _revision, _cursor, _message;
  String _room = '', _status = '';
  bool _busy = true, _saving = false;
  bool _creating = false;
  String? _roommateMain;
  String? _rentTenant, _rentHistoryTenant, _leaseTenant;
  int _generation = 0;
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
  };
  @override
  void initState() {
    super.initState();
    _list();
  }

  @override
  void didUpdateWidget(covariant TenantContactsScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _selected = null;
      _creating = false;
      _roommateMain = null;
      _rentTenant = null;
      _rentHistoryTenant = null;
      _leaseTenant = null;
      _pending = null;
      _saving = false;
      _clear();
      _list();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _clear() {
    _name.clear();
    _phone.clear();
    _revision = null;
    _room = '';
    _status = '';
  }

  Future<void> _list({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
      _selected = null;
      _clear();
      if (!more) {
        _rows = [];
        _cursor = null;
      }
    });
    try {
      final result = await widget.service.tenantContacts({
        'action': 'list',
        ..._identity,
        if (more) 'cursor': _cursor,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        final known = _rows.map((v) => v['id']).toSet();
        _rows.addAll(
          (result['records'] as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .where((v) => known.add(v['id'])),
        );
        _cursor = result['nextCursor'] as String?;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _rows = [];
          _cursor = null;
          _busy = false;
          _message = 'tenant_contacts_unavailable';
        });
      }
    }
  }

  Future<void> _read(String id, {bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _selected = id;
      _busy = true;
      _rows = [];
      _cursor = null;
      _message = null;
      _clear();
    });
    try {
      final result = await widget.service.tenantContacts({
        'action': 'read',
        ..._identity,
        'tenantId': id,
      });
      if (!mounted || generation != _generation) return;
      final row = result['record'] as Map;
      setState(() {
        _name.text = row['fullName'] as String;
        _phone.text = row['phoneNumber'] as String;
        _room = row['roomId'] as String;
        _status = row['status'] as String;
        _revision = row['revision'] as String;
        _busy = false;
        _message = saved ? 'tenant_contacts_saved' : null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _clear();
          _busy = false;
          _message = 'tenant_contacts_unavailable';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _saving || _revision == null) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    _pending ??= Map.unmodifiable({
      'action': 'update',
      ..._identity,
      'tenantId': _selected,
      'revision': _revision,
      'operationId': const Uuid().v4(),
      'fullName': _name.text.trim(),
      'phoneNumber': _phone.text.trim(),
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.service.tenantContacts(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      _pending = null;
      _saving = false;
      await _read(_selected!, saved: true);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _message = 'tenant_contacts_uncertain';
        if (e is FirebaseFunctionsException) {
          if ([
            'permission-denied',
            'unauthenticated',
            'not-found',
          ].contains(e.code)) {
            _pending = null;
            _clear();
            _message = 'tenant_contacts_unavailable';
          } else if (e.code == 'aborted') {
            _pending = null;
            _revision = null;
            _message = 'tenant_contacts_conflict';
          } else if ([
            'invalid-argument',
            'failed-precondition',
            'already-exists',
          ].contains(e.code)) {
            _pending = null;
            _message = 'tenant_contacts_rejected';
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_leaseTenant != null) {
      return LeaseLifecycleScreen(
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        tenantId: _leaseTenant!,
        service: widget.service,
        onBack: () {
          setState(() => _leaseTenant = null);
          _list();
        },
      );
    }
    if (_rentHistoryTenant != null) {
      return TenantRentHistory(
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        tenantId: _rentHistoryTenant!,
        service: widget.service,
        backLabelKey: 'tenant_contacts_title',
        onBack: () {
          setState(() => _rentHistoryTenant = null);
          _list();
        },
      );
    }
    if (_rentTenant != null) {
      return TenantRentScreen(
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        tenantId: _rentTenant!,
        service: widget.service,
        onBack: () {
          setState(() => _rentTenant = null);
          _list();
        },
      );
    }
    if (_creating) {
      return TenantLeaseScreen(
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        service: widget.service,
        mainTenantId: _roommateMain,
        onBack: () {
          setState(() => _creating = false);
          _list();
        },
      );
    }
    final t = AppTranslations.of(context),
        locked = _busy || _saving || _pending != null,
        editable = !locked && _revision != null;
    String status(String value) =>
        ['active', 'inactive', 'suspended', 'moveOut'].contains(value)
        ? t['tenant_contacts_$value']
        : t['team_unspecified'];
    Widget field(
      String key,
      String label,
      TextEditingController controller,
      int max, {
      bool required = false,
    }) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Semantics(
            label: label,
            child: TextFormField(
              key: ValueKey(key),
              controller: controller,
              enabled: !locked,
              readOnly: !editable,
              maxLines: null,
              decoration: const InputDecoration(errorMaxLines: 8),
              validator: (v) => required && (v ?? '').trim().isEmpty
                  ? t['tenant_contacts_required']
                  : (v ?? '').trim().length > max
                  ? t['tenant_contacts_long']
                  : null,
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton(
                  onPressed: locked
                      ? null
                      : (_selected == null ? widget.onBack : () => _list()),
                  child: Text(
                    t[_selected == null
                        ? 'workspace_title'
                        : 'tenant_contacts_title'],
                  ),
                ),
                Text(
                  t[_selected == null
                      ? 'tenant_contacts_title'
                      : 'tenant_contacts_edit'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(t['tenant_contacts_help']),
                if (_busy || _saving) const LinearProgressIndicator(),
                if (_selected == null) ...[
                  FilledButton(
                    onPressed: locked
                        ? null
                        : () => setState(() {
                            _roommateMain = null;
                            _creating = true;
                          }),
                    child: Text(t['lease_form_title']),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: locked ? null : () => _list(),
                    child: Text(t['tenant_contacts_refresh']),
                  ),
                  if (!_busy && _message == null && _rows.isEmpty)
                    Text(t['tenant_contacts_empty']),
                  for (final row in _rows)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(row['fullName'] as String? ?? ''),
                            Text(row['phoneNumber'] as String? ?? ''),
                            Text(
                              '${t['tenant_contacts_room']}: ${row['roomId']}',
                            ),
                            Text(
                              '${t['tenant_contacts_status']}: ${status(row['status'] as String? ?? '')}',
                            ),
                            OutlinedButton(
                              key: ValueKey('tenant-contact-${row['id']}'),
                              onPressed: locked
                                  ? null
                                  : () => _read(row['id'] as String),
                              child: Text(t['tenant_contacts_edit']),
                            ),
                            if (row['mainTenantId'] != null)
                              Text(
                                '${t['roommate_form_link']}: ${row['mainTenantId']}',
                              ),
                            OutlinedButton(
                              key: ValueKey('lease-ops-${row['id']}'),
                              onPressed: locked
                                  ? null
                                  : () => setState(
                                      () => _leaseTenant = row['id'] as String,
                                    ),
                              child: Text(t['lease_ops_title']),
                            ),
                            if (row['canReadRentHistory'] == true)
                              OutlinedButton(
                                key: ValueKey('rent-history-open-${row['id']}'),
                                onPressed: locked
                                    ? null
                                    : () => setState(
                                        () => _rentHistoryTenant =
                                            row['id'] as String,
                                      ),
                                child: Text(t['rent_history_title']),
                              ),
                            if (row['canEditRent'] == true) ...[
                              const SizedBox(height: 8),
                              OutlinedButton(
                                key: ValueKey('rent-plan-${row['id']}'),
                                onPressed: locked
                                    ? null
                                    : () => setState(
                                        () => _rentTenant = row['id'] as String,
                                      ),
                                child: Text(t['rent_plan_title']),
                              ),
                            ],
                            if (row['canAddRoommate'] == true) ...[
                              const SizedBox(height: 8),
                              OutlinedButton(
                                key: ValueKey('add-roommate-${row['id']}'),
                                onPressed: locked
                                    ? null
                                    : () => setState(() {
                                        _roommateMain = row['id'] as String;
                                        _creating = true;
                                      }),
                                child: Text(t['roommate_form_title']),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (_cursor != null)
                    OutlinedButton(
                      onPressed: locked ? null : () => _list(more: true),
                      child: Text(t['tenant_contacts_more']),
                    ),
                ] else ...[
                  if (_revision != null ||
                      _message == 'tenant_contacts_conflict')
                    Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${t['tenant_contacts_room']}: $_room'),
                          Text(
                            '${t['tenant_contacts_status']}: ${status(_status)}',
                          ),
                          field(
                            'tenant-contact-name',
                            t['tenant_contacts_name'],
                            _name,
                            160,
                            required: true,
                          ),
                          field(
                            'tenant-contact-phone',
                            t['tenant_contacts_phone'],
                            _phone,
                            80,
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: editable ? _save : null,
                            child: Text(t['tenant_contacts_save']),
                          ),
                        ],
                      ),
                    ),
                  if (_pending != null)
                    OutlinedButton(
                      onPressed: _saving ? null : _save,
                      child: Text(t['tenant_contacts_retry']),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: locked ? null : () => _read(_selected!),
                    child: Text(t['tenant_contacts_reload']),
                  ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(t[_message!]),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
