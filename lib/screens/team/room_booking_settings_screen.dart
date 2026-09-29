import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import 'operating_schedule_editor.dart';
import '../../utils/localizations/app_localizations.dart';

int? bookingMinute(String value, {bool closing = false}) {
  if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(value.trim())) return null;
  final p = value.trim().split(':').map(int.parse).toList(),
      minute = p[0] * 60 + p[1];
  return p[1] < 60 && (p[0] < 24 || closing && p[0] == 24 && p[1] == 0)
      ? minute
      : null;
}

class RoomBookingSettingsScreen extends StatefulWidget {
  final String organizationId, buildingId, roomId;
  final TeamService service;
  final VoidCallback onBack;
  const RoomBookingSettingsScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.service,
    required this.onBack,
  });
  @override
  State<RoomBookingSettingsScreen> createState() =>
      _RoomBookingSettingsScreenState();
}

class _RoomBookingSettingsScreenState extends State<RoomBookingSettingsScreen> {
  final _minimum = TextEditingController(),
      _buffer = TextEditingController(),
      _open = TextEditingController(),
      _close = TextEditingController();
  final _form = GlobalKey<FormState>();
  String? _revision, _zone, _message;
  String _name = '';
  bool _busy = true, _saving = false, _limited = false;
  int _generation = 0;
  Map<String, dynamic>? _pending;
  bool _weekly = false;
  ScheduleDraft _schedule = ScheduleDraft.daily(null, null);
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'roomId': widget.roomId,
  };
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RoomBookingSettingsScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.roomId != widget.roomId ||
        old.service != widget.service) {
      _saving = false;
      _pending = null;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [_minimum, _buffer, _open, _close]) {
      c.dispose();
    }
    super.dispose();
  }

  void _clear() {
    for (final c in [_minimum, _buffer, _open, _close]) {
      c.clear();
    }
    _revision = null;
    _zone = null;
    _name = '';
    _limited = false;
    _weekly = false;
    _schedule = ScheduleDraft.daily(null, null);
  }

  Future<void> _load({bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
      _clear();
    });
    try {
      final response = await widget.service.roomBookingSettings({
        'action': 'read',
        ..._identity,
      });
      if (!mounted || generation != _generation) return;
      final r = response['record'] as Map;
      String time(Object? v) => v is int
          ? '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}'
          : '';
      setState(() {
        _revision = r['revision'] as String;
        _zone = r['timeZone'] as String?;
        _name = r['roomNumber'] as String;
        _minimum.text = '${r['minBookingHours']}';
        _buffer.text = '${r['cleaningBufferMinutes']}';
        _weekly = r['operatingSchedule'] != null;
        _schedule = _weekly
            ? ScheduleDraft.fromMap(r['operatingSchedule'] as Map)
            : ScheduleDraft.daily(
                r['operatingHoursStartMin'] as int?,
                r['operatingHoursEndMin'] as int?,
              );
        _limited =
            _weekly ||
            r['operatingHoursStartMin'] != null ||
            r['operatingHoursEndMin'] != null;
        _open.text = time(r['operatingHoursStartMin']);
        _close.text = time(r['operatingHoursEndMin']);
        _busy = false;
        _message = saved ? 'settings_saved' : null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message = 'settings_unavailable';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _saving || _revision == null) return;
    if (_pending == null && !(_form.currentState?.validate() ?? false)) return;
    if (_pending == null && _limited && _weekly && _schedule.toMap() == null) {
      setState(() => _message = 'schedule_invalid');
      return;
    }
    _pending ??= Map.unmodifiable({
      'action': 'update',
      ..._identity,
      'operationId': const Uuid().v4(),
      'revision': _revision,
      'timeZone': _zone,
      'minBookingHours': int.parse(_minimum.text.trim()),
      'cleaningBufferMinutes': int.parse(_buffer.text.trim()),
      'operatingSchedule': _limited && _weekly ? _schedule.toMap() : null,
      'operatingHoursStartMin': _limited && !_weekly
          ? bookingMinute(_open.text)
          : null,
      'operatingHoursEndMin': _limited && !_weekly
          ? bookingMinute(_close.text, closing: true)
          : null,
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.service.roomBookingSettings(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _pending = null;
      });
      await _load(saved: true);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _message = 'settings_uncertain';
        if (error is FirebaseFunctionsException) {
          if ([
            'permission-denied',
            'unauthenticated',
            'not-found',
          ].contains(error.code)) {
            _pending = null;
            _clear();
            _message = 'settings_unavailable';
          } else if (error.code == 'aborted') {
            _pending = null;
            _revision = null;
            _message = 'settings_conflict';
          } else if ([
            'invalid-argument',
            'failed-precondition',
            'already-exists',
          ].contains(error.code)) {
            _pending = null;
            _message = error.message == 'settings_existing_conflict'
                ? 'settings_existing_conflict'
                : error.message == 'settings_timezone_required'
                ? 'settings_timezone_required'
                : 'settings_rejected';
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context),
        locked = _busy || _saving || _pending != null,
        editable = !locked && _revision != null;
    Widget integer(String key, TextEditingController controller, int max) =>
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: TextFormField(
            key: ValueKey(key),
            controller: controller,
            enabled: !locked,
            readOnly: !editable,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t[key], errorMaxLines: 6),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              return n == null || n < 0 || n > max ? t['${key}_invalid'] : null;
            },
          ),
        );
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextButton(
                onPressed: _saving || _pending != null ? null : widget.onBack,
                child: Text(t['room_directory']),
              ),
              Text(
                t['settings_title'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_name.isNotEmpty) Text(_name),
              const SizedBox(height: 16),
              if (_busy || _saving) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(t[_message!])),
              if (_revision != null || _message == 'settings_conflict')
                Form(
                  key: _form,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t['settings_info']),
                      Text(
                        '${t['property_timezone']}: ${_zone ?? t['team_unspecified']}',
                      ),
                      if (_zone == null) Text(t['settings_timezone_required']),
                      integer('settings_minimum', _minimum, 168),
                      integer('settings_buffer', _buffer, 1440),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(t['settings_limit']),
                        value: _limited,
                        onChanged: editable && _zone != null
                            ? (v) => setState(() => _limited = v!)
                            : null,
                      ),
                      if (_limited) ...[
                        OutlinedButton(
                          onPressed: editable
                              ? () => setState(() {
                                  if (!_weekly) {
                                    _schedule = ScheduleDraft.daily(
                                      bookingMinute(_open.text),
                                      bookingMinute(_close.text, closing: true),
                                    );
                                  } else {
                                    if (bookingMinute(_open.text) == null) {
                                      _open.text = '09:00';
                                    }
                                    if (bookingMinute(
                                          _close.text,
                                          closing: true,
                                        ) ==
                                        null) {
                                      _close.text = '17:00';
                                    }
                                  }
                                  _weekly = !_weekly;
                                })
                              : null,
                          child: Text(
                            t[_weekly
                                ? 'schedule_use_daily'
                                : 'schedule_use_weekly'],
                          ),
                        ),
                        if (_weekly)
                          OperatingScheduleEditor(
                            draft: _schedule,
                            enabled: editable,
                          ),
                      ],
                      if (_limited && !_weekly) ...[
                        Text(t['settings_hours_hint']),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('settings_open'),
                          controller: _open,
                          enabled: !locked,
                          readOnly: !editable,
                          decoration: InputDecoration(
                            labelText: t['settings_open'],
                            errorMaxLines: 6,
                          ),
                          validator: (v) => bookingMinute(v ?? '') == null
                              ? t['settings_time_invalid']
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('settings_close'),
                          controller: _close,
                          enabled: !locked,
                          readOnly: !editable,
                          decoration: InputDecoration(
                            labelText: t['settings_close'],
                            errorMaxLines: 6,
                          ),
                          validator: (v) {
                            final end = bookingMinute(v ?? '', closing: true),
                                start = bookingMinute(_open.text);
                            return end == null || start == null || end == start
                                ? t['settings_time_invalid']
                                : null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_revision != null)
                        FilledButton(
                          onPressed: _busy || _saving ? null : _save,
                          child: Text(
                            t[_pending == null
                                ? 'settings_save'
                                : 'settings_retry'],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: locked ? null : () => _load(),
                child: Text(t['settings_reload']),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
