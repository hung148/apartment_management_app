import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'property_contract_screen.dart' show contractDate;

class LeaseLifecycleScreen extends StatefulWidget {
  final String organizationId, buildingId, tenantId;
  final TeamService service;
  final VoidCallback onBack;
  const LeaseLifecycleScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.service,
    required this.onBack,
  });
  @override
  State<LeaseLifecycleScreen> createState() => _LeaseLifecycleScreenState();
}

class _LeaseLifecycleScreenState extends State<LeaseLifecycleScreen> {
  final _date = TextEditingController(), _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  Map<String, dynamic>? _record, _pending;
  List<Map<String, dynamic>> _rooms = [], _history = [];
  String _action = 'terms';
  String? _room, _parent, _message;
  bool _busy = true, _saving = false, _confirm = false, _showHistory = false;
  int _generation = 0;
  bool get _locked => _busy || _saving || _pending != null;
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'tenantId': widget.tenantId,
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LeaseLifecycleScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.tenantId != widget.tenantId ||
        old.service != widget.service) {
      _pending = null;
      _saving = false;
      _load();
    }
  }

  @override
  void dispose() {
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load({bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _record = null;
      _rooms = [];
      _history = [];
      _confirm = false;
      _showHistory = false;
      _message = null;
      _date.clear();
      _reason.clear();
      _room = null;
      _parent = null;
    });
    try {
      final r = await widget.service.leaseLifecycle({
        ..._identity,
        'action': 'read',
      });
      final rooms = await widget.service.leaseLifecycle({
        ..._identity,
        'action': 'destinations',
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = Map<String, dynamic>.from(r['record'] as Map);
        _rooms = (rooms['records'] as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        _action = _record!['isMainTenant'] == true ? 'terms' : 'moveOut';
        _date.text =
            (_action == 'terms'
                    ? _record!['contractEndDate']
                    : _record!['today'])
                as String? ??
            '';
        _message = saved ? 'lease_ops_saved' : null;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message = 'lease_ops_unavailable';
        });
      }
    }
  }

  Future<void> _readHistory() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _history = [];
      _showHistory = true;
    });
    try {
      final r = await widget.service.leaseLifecycle({
        ..._identity,
        'action': 'history',
      });
      if (mounted && generation == _generation) {
        setState(() {
          _history = (r['records'] as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _record = null;
          _message = 'lease_ops_unavailable';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      if (!_confirm) {
        setState(() => _confirm = true);
        return;
      }
      _pending = {
        ..._identity,
        'action': _action,
        'operationId': const Uuid().v4(),
        'revision': _record!['revision'],
        'timeZone': _record!['timeZone'],
        'reason': _reason.text.trim(),
        if (_action == 'terms')
          'contractEndDate': _date.text.trim().isEmpty
              ? null
              : _date.text.trim(),
        if (_action != 'terms') 'effectiveDate': _date.text.trim(),
        if (_action == 'move') 'destinationRoomId': _room,
        if (_action == 'move') 'destinationMainTenantId': _parent,
      };
    }
    final generation = ++_generation;
    setState(() => _saving = true);
    try {
      final result = await widget.service.leaseLifecycle(_pending!);
      if (!mounted || generation != _generation) return;
      _pending = null;
      _saving = false;
      if (result['buildingId'] != widget.buildingId) {
        widget.onBack();
        return;
      }
      await _load(saved: true);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        if (e is FirebaseFunctionsException &&
            ![
              'unavailable',
              'internal',
              'deadline-exceeded',
              'unknown',
            ].contains(e.code)) {
          _pending = null;
          _record = null;
          _rooms = [];
          _history = [];
          _confirm = false;
          _message = e.message == 'lease_handle_roommates_first'
              ? 'lease_ops_roommates'
              : e.code == 'already-exists'
              ? 'lease_ops_conflict'
              : 'lease_ops_unavailable';
        } else {
          _message = 'lease_ops_uncertain';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context), r = _record;
    final destinations = _rooms.where((v) => v['id'] == _room).firstOrNull;
    final parents = (destinations?['mainTenants'] as List? ?? []).cast<Map>();
    Widget field(
      String key,
      String label,
      TextEditingController c, {
      bool optional = false,
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
              controller: c,
              enabled: !_locked && !_confirm,
              maxLines: null,
              decoration: const InputDecoration(errorMaxLines: 8),
              validator: (v) {
                final text = (v ?? '').trim();
                if (text.isEmpty) {
                  return optional ? null : t['lease_ops_required'];
                }
                if (key == 'lease-ops-date' && !contractDate(text)) {
                  return t['lease_ops_date_error'];
                }
                if (text.length > 1000) return t['lease_ops_required'];
                return null;
              },
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
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton(
                    onPressed: _locked ? null : widget.onBack,
                    child: Text(t['tenant_contacts_title']),
                  ),
                  Text(
                    t['lease_ops_title'],
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(t['lease_ops_help']),
                  if (_busy || _saving) const LinearProgressIndicator(),
                  if (_message != null)
                    Semantics(liveRegion: true, child: Text(t[_message!])),
                  if (r != null) ...[
                    Text(r['fullName'] as String),
                    Text('${t['lease_form_timezone']}: ${r['timeZone']}'),
                    Text('${t['lease_ops_today']}: ${r['today']}'),
                    if (!_showHistory) ...[
                      for (final mode in [
                        if (r['isMainTenant'] == true) 'terms',
                        'move',
                        'moveOut',
                      ])
                        OutlinedButton(
                          onPressed: _locked
                              ? null
                              : () => setState(() {
                                  _action = mode;
                                  _confirm = false;
                                  _date.text =
                                      (mode == 'terms'
                                              ? r['contractEndDate']
                                              : r['today'])
                                          as String? ??
                                      '';
                                }),
                          child: Text(t['lease_ops_$mode']),
                        ),
                      Text(
                        t['lease_ops_$_action'],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (_action != 'terms' &&
                          (r['roommates'] as List).isNotEmpty) ...[
                        Text(t['lease_ops_roommates']),
                        for (final v in r['roommates'] as List)
                          Text('${v['fullName']} (${v['id']})'),
                      ],
                      if (_action == 'move') ...[
                        for (final room in _rooms)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: room['id'] == _room,
                            onChanged: _locked || _confirm
                                ? null
                                : (v) => setState(() {
                                    _room = room['id'] as String;
                                    _parent = null;
                                  }),
                            title: Text(
                              '${room['roomNumber']} (${room['buildingId']})',
                            ),
                          ),
                        if (r['isMainTenant'] != true) ...[
                          Text(t['lease_ops_parent']),
                          for (final parent in parents)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: parent['id'] == _parent,
                              onChanged: _locked || _confirm
                                  ? null
                                  : (v) => setState(
                                      () => _parent = parent['id'] as String,
                                    ),
                              title: Text(parent['fullName'] as String),
                            ),
                        ],
                        if (_rooms.isEmpty) Text(t['lease_ops_no_rooms']),
                      ],
                      field(
                        'lease-ops-date',
                        t[_action == 'terms'
                            ? 'lease_ops_end'
                            : 'lease_ops_effective'],
                        _date,
                        optional: _action == 'terms',
                      ),
                      field('lease-ops-reason', t['rent_plan_reason'], _reason),
                      const SizedBox(height: 16),
                      if (_confirm) Text(t['lease_ops_confirm_help']),
                      FilledButton(
                        onPressed:
                            _busy ||
                                _saving ||
                                r['status'] == 'moveOut' ||
                                (_action == 'move' &&
                                    (_room == null ||
                                        (r['isMainTenant'] != true &&
                                            _parent == null)))
                            ? null
                            : _save,
                        child: Text(
                          t[_pending != null
                              ? 'lease_ops_retry'
                              : _confirm
                              ? 'lease_ops_confirm'
                              : 'lease_ops_review'],
                        ),
                      ),
                      if (_confirm && _pending == null)
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _confirm = false),
                          child: Text(t['lease_ops_change']),
                        ),
                      OutlinedButton(
                        onPressed: _locked ? null : _readHistory,
                        child: Text(t['lease_ops_history']),
                      ),
                    ] else ...[
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _showHistory = false),
                        child: Text(t['lease_ops_title']),
                      ),
                      if (!_busy && _history.isEmpty)
                        Text(t['rent_history_empty']),
                      for (final row in _history)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(t['lease_ops_${row['action']}']),
                                Text('${row['createdAt']} / ${row['actorId']}'),
                                Text(
                                  '${t['rent_plan_reason']}: ${row['reason']}',
                                ),
                                for (final side in ['before', 'after']) ...[
                                  Text(t['rent_history_$side']),
                                  for (final k in [
                                    'buildingId',
                                    'roomId',
                                    'status',
                                    'contractEndDate',
                                    'occupancyStartDate',
                                    'moveOutDate',
                                  ])
                                    Text(
                                      '${t['lease_ops_$k']}: ${(row[side] as Map)[k] ?? '—'}',
                                    ),
                                ],
                              ],
                            ),
                          ),
                        ),
                    ],
                  ],
                  OutlinedButton(
                    onPressed: _locked ? null : () => _load(),
                    child: Text(t['lease_ops_reload']),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
