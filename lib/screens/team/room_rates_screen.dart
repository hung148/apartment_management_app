import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';

const rateFields = ['roomPrice', 'hourlyPrice', 'dailyPrice', 'overnightPrice'];
int? parseRoomRate(String text, String currency) {
  final value = text.trim().replaceAll(',', '.');
  if (!RegExp(
    currency == 'USD' ? r'^\d+(?:\.\d{1,2})?$' : r'^\d+$',
  ).hasMatch(value)) {
    return null;
  }
  final parts = value.split('.'), whole = int.tryParse(parts[0]);
  if (whole == null) return null;
  final minor = currency == 'USD'
      ? whole * 100 +
            int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'))
      : whole;
  return minor > 0 && minor <= 1000000000000 ? minor : null;
}

class RoomRatesScreen extends StatefulWidget {
  final String organizationId, buildingId, roomId;
  final TeamService service;
  final VoidCallback onBack;
  const RoomRatesScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.service,
    required this.onBack,
  });
  @override
  State<RoomRatesScreen> createState() => _RoomRatesScreenState();
}

class _RoomRatesScreenState extends State<RoomRatesScreen> {
  final _prices = {
    for (final field in rateFields) field: TextEditingController(),
  };
  final _threshold = TextEditingController(), _form = GlobalKey<FormState>();
  String? _revision, _message;
  String _currency = 'VND', _mode = 'monthly', _name = '';
  bool _busy = true, _saving = false;
  int _generation = 0;
  Map<String, dynamic>? _pending;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RoomRatesScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.roomId != widget.roomId ||
        old.service != widget.service) {
      _pending = null;
      _saving = false;
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in _prices.values) {
      c.dispose();
    }
    _threshold.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'roomId': widget.roomId,
  };
  void _clear() {
    for (final c in _prices.values) {
      c.clear();
    }
    _threshold.clear();
    _revision = null;
    _name = '';
  }

  Future<void> _load({bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
      _clear();
    });
    try {
      final response = await widget.service.roomRates({
        'action': 'read',
        ..._identity,
      });
      if (!mounted || generation != _generation) return;
      final row = Map<String, dynamic>.from(response['record'] as Map);
      setState(() {
        _revision = row['revision'] as String;
        _currency = row['currency'] as String;
        _mode = row['rentalMode'] as String;
        _name = row['roomNumber'] as String;
        final rates = row['ratesMinor'] as Map;
        for (final field in rateFields) {
          final value = (rates[field] as num?)?.toInt();
          _prices[field]!.text = value == null
              ? ''
              : _currency == 'USD'
              ? '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}'
              : value.toString();
        }
        _threshold.text = row['dailyPriceThresholdHours']?.toString() ?? '';
        _busy = false;
        _message = saved ? 'rates_saved' : null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message = 'rates_unavailable';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || _saving || _revision == null) return;
    if (_pending == null && !(_form.currentState?.validate() ?? false)) return;
    _pending ??= Map.unmodifiable({
      'action': 'update',
      ..._identity,
      'operationId': const Uuid().v4(),
      'revision': _revision,
      'rentalMode': _mode,
      'ratesMinor': {
        for (final field in rateFields)
          field: _prices[field]!.text.trim().isEmpty
              ? null
              : parseRoomRate(_prices[field]!.text, _currency),
      },
      'dailyPriceThresholdHours': _threshold.text.trim().isEmpty
          ? null
          : int.tryParse(_threshold.text.trim()),
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.service.roomRates(Map.of(_pending!));
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
        _message = 'rates_uncertain';
        if (error is FirebaseFunctionsException) {
          if ([
            'permission-denied',
            'unauthenticated',
            'not-found',
          ].contains(error.code)) {
            _pending = null;
            _clear();
            _message = 'rates_unavailable';
          } else if (error.code == 'aborted') {
            _pending = null;
            _revision = null;
            _message = 'rates_conflict';
          } else if ([
            'invalid-argument',
            'failed-precondition',
            'already-exists',
          ].contains(error.code)) {
            _pending = null;
            _message = error.message == 'room_rates_active_bookings'
                ? 'rates_active_bookings'
                : error.message == 'room_rates_active_tenants'
                ? 'rates_active_tenants'
                : 'rates_rejected';
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
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextButton(
                onPressed: _saving ? null : widget.onBack,
                child: Text(t['room_directory']),
              ),
              Text(
                t['rates_title'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_name.isNotEmpty) Text(_name),
              const SizedBox(height: 16),
              if (_busy || _saving) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(t[_message!])),
              if (_revision != null || _message == 'rates_conflict')
                Form(
                  key: _form,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('${t['rates_currency']} $_currency'),
                      Text(t['rates_info']),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        key: ValueKey('rates-mode-$_mode'),
                        initialValue: _mode,
                        isExpanded: true,
                        selectedItemBuilder: (context) => [
                          for (final mode in ['monthly', 'hourly', 'both'])
                            Text(
                              t['rates_mode_$mode'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                        itemHeight: null,
                        decoration: InputDecoration(labelText: t['rates_mode']),
                        items: [
                          for (final mode in ['monthly', 'hourly', 'both'])
                            DropdownMenuItem(
                              value: mode,
                              child: Text(t['rates_mode_$mode']),
                            ),
                        ],
                        onChanged: editable
                            ? (v) => setState(() => _mode = v!)
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t['rates_mode_$_mode'],
                        key: const ValueKey('rates-selected-mode'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t[_currency == 'USD'
                            ? 'rates_usd_hint'
                            : 'rates_vnd_hint'],
                      ),
                      for (final field in rateFields) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          key: ValueKey('rates-$field'),
                          controller: _prices[field],
                          enabled: !locked,
                          readOnly: !editable,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: t['rates_$field'],
                            errorMaxLines: 8,
                          ),
                          validator: (v) {
                            final required =
                                field == 'roomPrice' && _mode != 'hourly' ||
                                field == 'hourlyPrice' && _mode != 'monthly';
                            if ((v ?? '').trim().isEmpty) {
                              return required ? t['room_rate_required'] : null;
                            }
                            return parseRoomRate(v!, _currency) == null
                                ? t['rates_invalid']
                                : null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('rates-threshold'),
                        controller: _threshold,
                        enabled: !locked,
                        readOnly: !editable,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: t['rates_threshold'],
                          errorMaxLines: 8,
                        ),
                        validator: (v) {
                          final value = (v ?? '').trim();
                          final daily = _prices['dailyPrice']!.text
                              .trim()
                              .isNotEmpty;
                          final hours = int.tryParse(value);
                          return daily
                              ? (hours == null || hours < 1 || hours > 24
                                    ? t['rates_threshold_invalid']
                                    : null)
                              : (value.isEmpty
                                    ? null
                                    : t['rates_threshold_clear']);
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_revision != null)
                        FilledButton(
                          onPressed: _busy || _saving ? null : _save,
                          child: Text(
                            t[_pending == null ? 'rates_save' : 'rates_retry'],
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: locked ? null : () => _load(),
                child: Text(t['rates_reload']),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
