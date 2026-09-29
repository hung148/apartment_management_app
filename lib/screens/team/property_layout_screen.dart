import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import 'operational_widgets.dart';

class PropertyLayoutScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;
  final VoidCallback onBack;
  const PropertyLayoutScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.onBack,
  });
  @override
  State<PropertyLayoutScreen> createState() => _PropertyLayoutScreenState();
}

class _PropertyLayoutScreenState extends State<PropertyLayoutScreen> {
  final _fields = {
        for (final k in [
          'floors',
          'roomPrefix',
          'roomType',
          'roomArea',
          'floorRoomCounts',
        ])
          k: TextEditingController(),
      },
      _form = GlobalKey<FormState>();
  Map<String, dynamic>? _record, _pending;
  bool _busy = true;
  String? _message;
  int _generation = 0;
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
  void didUpdateWidget(covariant PropertyLayoutScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _pending = null;
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

  Future<void> _load({bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _record = null;
      _message = null;
    });
    try {
      final r = await widget.service.propertyLayout({
        ..._identity,
        'action': 'read',
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = Map<String, dynamic>.from(r['record'] as Map);
        final layout = _record!['layout'] as Map;
        for (final k in _fields.keys) {
          _fields[k]!.text = k == 'floorRoomCounts'
              ? (layout[k] as List).join(', ')
              : '${layout[k]}';
        }
        _busy = false;
        _message = saved ? 'saved' : null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message = 'unavailable';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      final floors = int.tryParse(_fields['floors']!.text),
          area = double.tryParse(
            _fields['roomArea']!.text.replaceAll(',', '.'),
          ),
          counts = _fields['floorRoomCounts']!.text
              .split(',')
              .map((v) => int.tryParse(v.trim()))
              .toList();
      if (floors == null ||
          area == null ||
          counts.any((v) => v == null) ||
          counts.length != floors) {
        setState(() => _message = 'required');
        return;
      }
      _pending = {
        ..._identity,
        'action': 'update',
        'operationId': const Uuid().v4(),
        'revision': _record!['revision'],
        'layout': {
          'floors': floors,
          'roomArea': area,
          'roomPrefix': _fields['roomPrefix']!.text.trim(),
          'roomType': _fields['roomType']!.text.trim(),
          'floorRoomCounts': counts,
        },
      };
    }
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      await widget.service.propertyLayout(_pending!);
      if (!mounted || generation != _generation) return;
      _pending = null;
      await _load(saved: true);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        if (e is FirebaseFunctionsException &&
            ![
              'unavailable',
              'internal',
              'deadline-exceeded',
              'unknown',
            ].contains(e.code)) {
          _pending = null;
          _record = null;
          _message = 'unavailable';
        } else {
          _message = 'uncertain';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _pending != null;
    String t(String k) => opsText(context, k);
    return opsPage(context, [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextButton(
              onPressed: locked ? null : widget.onBack,
              child: Text(t('back')),
            ),
            Text(
              t('propertyLayout'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(t('layoutHelp')),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) Text(t(_message!)),
            if (_record != null) ...[
              Text(_record!['name'] as String),
              for (final k in _fields.keys)
                opsField(
                  context,
                  k,
                  _fields[k]!,
                  enabled: !locked,
                  required: k != 'roomPrefix',
                ),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(t(_pending == null ? 'save' : 'retry')),
              ),
            ],
            OutlinedButton(
              onPressed: locked ? null : () => _load(),
              child: Text(t('reload')),
            ),
          ],
        ),
      ),
    ]);
  }
}
