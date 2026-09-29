import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'property_contract_screen.dart' show contractDate;
import 'room_rates_screen.dart' show parseRoomRate;

class TenantLeaseScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final String? mainTenantId;
  final TeamService service;
  final VoidCallback onBack;
  const TenantLeaseScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.onBack,
    this.mainTenantId,
  });
  @override
  State<TenantLeaseScreen> createState() => _TenantLeaseScreenState();
}

class _TenantLeaseScreenState extends State<TenantLeaseScreen> {
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final k in ['name', 'phone', 'start', 'end', 'rent', 'reason'])
      k: TextEditingController(),
  };
  List<Map<String, dynamic>> _rooms = [];
  Map<String, dynamic>? _record, _pending;
  String? _roomId, _cursor, _message;
  bool _busy = false, _saving = false, _done = false;
  int _generation = 0;
  bool get _roommate => widget.mainTenantId != null;
  Future<Map<String, dynamic>> _request(Map<String, dynamic> data) => _roommate
      ? widget.service.tenantRoommates(data)
      : widget.service.tenantLeases(data);
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    if (_roommate) 'mainTenantId': widget.mainTenantId,
  };
  bool get _locked => _busy || _saving || _pending != null;
  @override
  void initState() {
    super.initState();
    _roommate ? _prepare('') : _load();
  }

  @override
  void didUpdateWidget(covariant TenantLeaseScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service ||
        old.mainTenantId != widget.mainTenantId) {
      _pending = null;
      _saving = false;
      _done = false;
      _roomId = null;
      _record = null;
      for (final c in _fields.values) {
        c.clear();
      }
      _roommate ? _prepare('') : _load();
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
      if (!more) {
        _rooms = [];
        _cursor = null;
      }
    });
    try {
      final r = await _request({
        'action': 'rooms',
        ..._identity,
        if (more) 'cursor': _cursor,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        final known = _rooms.map((v) => v['id']).toSet();
        _rooms.addAll(
          (r['records'] as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .where((v) => known.add(v['id'])),
        );
        _cursor = r['nextCursor'] as String?;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _rooms = [];
          _cursor = null;
          _busy = false;
          _message = 'lease_form_unavailable';
        });
      }
    }
  }

  Future<void> _prepare(String id) async {
    final generation = ++_generation;
    setState(() {
      _roomId = id;
      _record = null;
      _rooms = [];
      _cursor = null;
      _busy = true;
      _message = null;
    });
    try {
      final r = await _request({
        'action': 'prepare',
        ..._identity,
        if (!_roommate) 'roomId': id,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = Map<String, dynamic>.from(r['record'] as Map);
        _busy = false;
        if (_fields['start']!.text.isEmpty) {
          _fields['start']!.text = _record!['today'] as String;
          if (_roommate &&
              (_record!['earliestDate'] as String).compareTo(
                    _fields['start']!.text,
                  ) >
                  0) {
            _fields['start']!.text = _record!['earliestDate'] as String;
          }
        }
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message =
              e is FirebaseFunctionsException &&
                  e.message == 'lease_property_timezone_required'
              ? 'lease_form_timezone_required'
              : 'lease_form_unavailable';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _saving || _record == null || _done) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    _pending ??= Map.unmodifiable({
      'action': 'create',
      ..._identity,
      if (!_roommate) 'roomId': _roomId,
      'operationId': const Uuid().v4(),
      'roomRevision': _record!['roomRevision'],
      'timeZone': _record!['timeZone'],
      if (!_roommate) 'currency': _record!['currency'],
      if (_roommate) 'mainRevision': _record!['mainRevision'],
      'fullName': _fields['name']!.text.trim(),
      'phoneNumber': _fields['phone']!.text.trim(),
      'moveInDate': _fields['start']!.text.trim(),
      if (!_roommate)
        'contractEndDate': _fields['end']!.text.trim().isEmpty
            ? null
            : _fields['end']!.text.trim(),
      if (!_roommate)
        'rentMinor': parseRoomRate(
          _fields['rent']!.text,
          _record!['currency'] as String,
        ),
      'backdateReason': _fields['reason']!.text.trim(),
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await _request(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      setState(() {
        _pending = null;
        _saving = false;
        _done = true;
        _message = _roommate ? 'roommate_form_saved' : 'lease_form_saved';
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _message = 'lease_form_uncertain';
        if (e is FirebaseFunctionsException) {
          if ([
            'permission-denied',
            'unauthenticated',
            'not-found',
          ].contains(e.code)) {
            _pending = null;
            _record = null;
            for (final c in _fields.values) {
              c.clear();
            }
            _message = 'lease_form_unavailable';
          } else if ([
            'aborted',
            'already-exists',
            'failed-precondition',
            'invalid-argument',
          ].contains(e.code)) {
            _pending = null;
            _record = null;
            _message = e.code == 'already-exists'
                ? 'lease_form_occupied'
                : 'lease_form_changed';
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context), r = _record;
    final past =
        r != null &&
        contractDate(_fields['start']!.text.trim()) &&
        _fields['start']!.text.trim().compareTo(r['today'] as String) < 0;
    Widget field(String key, {String? label, int max = 160}) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label ?? t['lease_form_$key']),
          const SizedBox(height: 8),
          Semantics(
            label: label ?? t['lease_form_$key'],
            child: TextFormField(
              key: ValueKey('lease-$key'),
              controller: _fields[key],
              enabled: !_locked,
              maxLines: null,
              decoration: const InputDecoration(errorMaxLines: 8),
              onChanged: key == 'start' ? (_) => setState(() {}) : null,
              validator: (value) {
                final v = (value ?? '').trim();
                if (v.length > max) return t['tenant_contacts_long'];
                if (key == 'name' && v.isEmpty) {
                  return t['tenant_contacts_required'];
                }
                if (key == 'rent' &&
                    parseRoomRate(v, r!['currency'] as String) == null) {
                  return t['lease_form_invalid_rent'];
                }
                if (key == 'start') {
                  if (!contractDate(v)) return t['lease_form_invalid_date'];
                  if (_roommate &&
                      v.compareTo(r!['earliestDate'] as String) < 0) {
                    return t['roommate_form_before_main'];
                  }
                  if (v.compareTo(r!['today'] as String) < 0 &&
                      r['canBackdate'] != true) {
                    return t['lease_form_no_backdate'];
                  }
                }
                if (key == 'end' &&
                    v.isNotEmpty &&
                    (!contractDate(v) ||
                        v.compareTo(_fields['start']!.text.trim()) < 0)) {
                  return t['lease_form_invalid_end'];
                }
                if (key == 'reason' && past && v.isEmpty) {
                  return t['lease_form_reason_required'];
                }
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton(
                  onPressed: _locked ? null : widget.onBack,
                  child: Text(t['tenant_contacts_title']),
                ),
                Text(
                  t[_roommate ? 'roommate_form_title' : 'lease_form_title'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(t[_roommate ? 'roommate_form_help' : 'lease_form_help']),
                if (_busy || _saving) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(t[_message!]),
                    ),
                  ),
                if (!_done && _roomId == null) ...[
                  OutlinedButton(
                    onPressed: _locked ? null : () => _load(),
                    child: Text(t['lease_form_reload_rooms']),
                  ),
                  if (!_busy && _message == null && _rooms.isEmpty)
                    Text(t['lease_form_empty']),
                  for (final room in _rooms)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton(
                        key: ValueKey('lease-room-${room['id']}'),
                        onPressed: _locked || room['monthly'] != true
                            ? null
                            : () => _prepare(room['id'] as String),
                        child: Text(
                          '${room['roomNumber']}\n${t[room['monthly'] == true ? 'lease_form_select_room' : 'lease_form_hourly']}',
                        ),
                      ),
                    ),
                  if (_cursor != null)
                    OutlinedButton(
                      onPressed: _locked ? null : () => _load(more: true),
                      child: Text(t['tenant_contacts_more']),
                    ),
                ],
                if (!_done && _roomId != null) ...[
                  if (r != null)
                    Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${r['roomNumber']}'),
                          if (_roommate) ...[
                            Text(
                              '${t['roommate_form_main']}: ${r['mainName']}',
                            ),
                            Text(
                              '${t['roommate_form_earliest']}: ${r['earliestDate']}',
                            ),
                          ],
                          Text('${t['lease_form_timezone']}: ${r['timeZone']}'),
                          Text('${t['lease_form_today']}: ${r['today']}'),
                          field('name'),
                          field('phone', max: 80),
                          field('start', max: 10),
                          if (!_roommate) field('end', max: 10),
                          if (!_roommate)
                            field(
                              'rent',
                              label:
                                  '${t['lease_form_rent']} (${r['currency']})',
                              max: 24,
                            ),
                          if (past && r['canBackdate'] == true)
                            field('reason', max: 1000),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _locked ? null : _save,
                            child: Text(
                              t[_roommate
                                  ? 'roommate_form_save'
                                  : 'lease_form_save'],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_pending != null)
                    OutlinedButton(
                      onPressed: _saving ? null : _save,
                      child: Text(
                        t[_roommate
                            ? 'roommate_form_retry'
                            : 'lease_form_retry'],
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _locked ? null : () => _prepare(_roomId!),
                    child: Text(
                      t[_roommate
                          ? 'roommate_form_reload'
                          : 'lease_form_reload'],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!_roommate)
                    OutlinedButton(
                      onPressed: _locked
                          ? null
                          : () {
                              setState(() {
                                _roomId = null;
                                _record = null;
                              });
                              _load();
                            },
                      child: Text(t['lease_form_change_room']),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
