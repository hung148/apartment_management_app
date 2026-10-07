import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'room_rates_screen.dart' show parseRoomRate;
import 'property_contract_history.dart';
import 'back_steps.dart';
import '../../utils/app_number.dart';

bool contractDate(String value) {
  final d = DateTime.tryParse('${value}T00:00:00Z');
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      d != null &&
      d.year >= 2000 &&
      d.year <= 2199 &&
      d.toIso8601String().substring(0, 10) == value;
}

class PropertyContractScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;

  /// Null inside the organization workspace sections (U1): no Back button.
  final VoidCallback? onBack;
  const PropertyContractScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    this.onBack,
  });
  @override
  State<PropertyContractScreen> createState() => _PropertyContractScreenState();
}

class _PropertyContractScreenState extends State<PropertyContractScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final k in [
      'partyName',
      'partyPhone',
      'amount',
      'dueDay',
      'startDate',
      'endDate',
      'notes',
    ])
      k: TextEditingController(),
  };
  bool _busy = true, _saving = false;
  bool _history = false;
  int _generation = 0;
  String? _direction, _revision, _message;
  String _status = 'active', _currency = 'VND', _name = '';
  Map _legacy = {};
  Map<String, dynamic>? _pending;
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PropertyContractScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _pending = null;
      _history = false;
      _saving = false;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _clear() {
    _revision = null;
    _direction = null;
    _status = 'active';
    _name = '';
    _legacy = {};
    for (final c in _fields.values) {
      c.clear();
    }
  }

  Future<void> _load({bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
      _clear();
    });
    try {
      final response = await widget.service.propertyContract({
        'action': 'read',
        ..._identity,
      });
      if (!mounted || generation != _generation) return;
      final r = response['record'] as Map, c = r['contract'] as Map?;
      setState(() {
        _revision = r['revision'];
        _currency = r['currency'];
        _name = r['name'];
        _legacy = r['legacy'] as Map? ?? {};
        _direction = c?['direction'];
        _status = c?['status'] ?? 'active';
        for (final k in _fields.keys) {
          _fields[k]!.text = c?[k]?.toString() ?? '';
        }
        if (c != null) {
          final amount = c['amountMinor'] as int;
          _fields['amount']!.text = appMoneyInputText(amount, _currency);
        } else if (r['importedRentInMinor'] is int) {
          // Sheet import (2026-10-05): the rent the business pays for the
          // building in the old app; the owner adds the landlord and dates.
          _direction = 'rentIn';
          _fields['amount']!.text = appMoneyInputText(
            r['importedRentInMinor'] as int,
            _currency,
          );
        }
        _busy = false;
        _message = saved ? 'contract_saved' : null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _clear();
          _busy = false;
          _message = 'contract_unavailable';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _saving || _revision == null) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    _pending ??= {
      'action': 'update',
      ..._identity,
      'operationId': const Uuid().v4(),
      'revision': _revision,
      'currency': _currency,
      'contract': {
        'direction': _direction,
        'status': _status,
        'partyName': _fields['partyName']!.text.trim(),
        'partyPhone': _fields['partyPhone']!.text.trim(),
        'amountMinor': parseRoomRate(_fields['amount']!.text, _currency),
        'dueDay': int.parse(_fields['dueDay']!.text.trim()),
        'startDate': _fields['startDate']!.text.trim(),
        'endDate': _fields['endDate']!.text.trim().isEmpty
            ? null
            : _fields['endDate']!.text.trim(),
        'notes': _fields['notes']!.text.trim(),
      },
    };
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.service.propertyContract(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      _pending = null;
      _saving = false;
      await _load(saved: true);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _message = 'contract_uncertain';
        if (e is FirebaseFunctionsException) {
          if ([
            'permission-denied',
            'unauthenticated',
            'not-found',
          ].contains(e.code)) {
            _pending = null;
            _clear();
            _message = 'contract_unavailable';
          } else if (e.code == 'aborted') {
            _pending = null;
            _revision = null;
            _message = 'contract_conflict';
          } else if ([
            'invalid-argument',
            'failed-precondition',
            'already-exists',
          ].contains(e.code)) {
            _pending = null;
            _message = 'contract_rejected';
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_history) {
      return BackStep(
        onBack: () => setState(() => _history = false),
        child: PropertyContractHistory(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          service: widget.service,
          onBack: () => setState(() => _history = false),
        ),
      );
    }
    final t = AppTranslations.of(context),
        locked = _busy || _saving || _pending != null,
        editable = !locked && _revision != null;
    Widget field(
      String k,
      String label, {
      int? max,
      String? helper,
      String? Function(String)? check,
      int lines = 1,
    }) => Padding(
      key: ValueKey('contract-field-$k'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Semantics(
            label: label,
            child: TextFormField(
              key: ValueKey('contract-$k'),
              controller: _fields[k],
              enabled: !locked,
              readOnly: !editable,
              minLines: lines,
              maxLines: null,
              inputFormatters: k == 'amount' ? appMoneyInput(_currency) : null,
              decoration: InputDecoration(
                helperText: helper,
                helperMaxLines: 12,
                errorMaxLines: 12,
              ),
              validator: (v) {
                final value = (v ?? '').trim();
                if (max != null && value.length > max) {
                  return t['contract_invalid'];
                }
                return check?.call(value);
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
          constraints: WorkspacePageScope.constraints(context, 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.onBack != null)
                  TextButton(
                    onPressed: locked ? null : widget.onBack,
                    child: Text(t['workspace_title']),
                  ),
                Text(
                  t['contract_title'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(_name),
                const SizedBox(height: 16),
                Text(t['contract_help']),
                if (_busy || _saving) const LinearProgressIndicator(),
                if (_legacy.isNotEmpty)
                  ExpansionTile(
                    title: Text(t['contract_legacy']),
                    subtitle: Text(t['contract_legacy_help']),
                    children: [
                      for (final e in _legacy.entries)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${t['contract_legacy_${e.key}']}: ${e.value}',
                            ),
                          ),
                        ),
                    ],
                  ),
                if (_revision != null || _message == 'contract_conflict')
                  Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: ValueKey('contract-direction-$_direction'),
                          initialValue: _direction,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t['contract_direction'],
                            errorMaxLines: 4,
                          ),
                          items: [
                            for (final v in ['rentIn', 'rentOut'])
                              DropdownMenuItem(
                                value: v,
                                child: Text(t['contract_$v']),
                              ),
                          ],
                          onChanged: editable
                              ? (v) => setState(() => _direction = v)
                              : null,
                          validator: (v) =>
                              v == null ? t['contract_choose_direction'] : null,
                        ),
                        if (_direction != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(t['contract_${_direction}_help']),
                          ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          key: ValueKey('contract-status-$_status'),
                          initialValue: _status,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t['contract_status'],
                          ),
                          items: [
                            for (final v in ['active', 'ended'])
                              DropdownMenuItem(
                                value: v,
                                child: Text(t['contract_$v']),
                              ),
                          ],
                          onChanged: editable
                              ? (v) => setState(() => _status = v!)
                              : null,
                        ),
                        field(
                          'partyName',
                          t[_direction == 'rentIn'
                              ? 'contract_landlord'
                              : _direction == 'rentOut'
                              ? 'contract_tenant'
                              : 'contract_party'],
                          max: 160,
                          check: (v) =>
                              v.isEmpty ? t['contract_required'] : null,
                        ),
                        field('partyPhone', t['contract_phone'], max: 80),
                        field(
                          'amount',
                          '${t['contract_amount']} ($_currency)',
                          check: (v) => parseRoomRate(v, _currency) == null
                              ? t['contract_amount_invalid']
                              : null,
                        ),
                        field(
                          'dueDay',
                          t['contract_due'],
                          helper: t['contract_due_help'],
                          check: (v) {
                            final n = int.tryParse(v);
                            return n == null || n < 1 || n > 31
                                ? t['contract_due_invalid']
                                : null;
                          },
                        ),
                        field(
                          'startDate',
                          t['contract_start'],
                          helper: 'YYYY-MM-DD',
                          check: (v) => contractDate(v)
                              ? null
                              : t['contract_date_invalid'],
                        ),
                        field(
                          'endDate',
                          t['contract_end'],
                          helper: t['contract_end_help'],
                          check: (v) {
                            if (v.isEmpty) {
                              return _status == 'ended'
                                  ? t['contract_end_required']
                                  : null;
                            }
                            return !contractDate(v) ||
                                    v.compareTo(
                                          _fields['startDate']!.text.trim(),
                                        ) <
                                        0
                                ? t['contract_date_invalid']
                                : null;
                          },
                        ),
                        field(
                          'notes',
                          t['contract_notes'],
                          max: 2000,
                          lines: 3,
                        ),
                        const SizedBox(height: 20),
                        WsActions(
                          children: [
                            FilledButton(
                              onPressed: editable ? _save : null,
                              child: Text(t['contract_save']),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(t[_message!]),
                    ),
                  ),
                if (_revision != null)
                  WsActions(
                    children: [
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => setState(() => _history = true),
                        child: Text(t['contract_history']),
                      ),
                    ],
                  ),
                if (_pending != null)
                  WsActions(
                    children: [
                      OutlinedButton(
                        onPressed: _saving ? null : _save,
                        child: Text(t['contract_retry']),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                WsActions(
                  children: [
                    OutlinedButton(
                      onPressed: locked ? null : () => _load(),
                      child: Text(t['contract_reload']),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
