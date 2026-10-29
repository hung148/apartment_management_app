import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/money_conversion.dart';
import '../../services/organization_money.dart';
import '../../utils/localizations/app_localizations.dart';

// 2026-10-04: monthly price, price per night. Day and overnight prices
// (and the day-price hour threshold) are gone. 2026-10-26: no flat price per
// hour either; hourly bookings pick one of the building's hourly templates.
const rateFields = ['roomPrice', 'nightlyPrice'];

String _w(BuildContext c, String en, String vi) =>
    AppTranslations.of(c).locale.languageCode == 'vi' ? vi : en;

/// A price above 0 in minor units ("5,000,000" → 5000000), or null.
int? parseRoomRate(String text, String currency) {
  final minor = appParseMoney(text, currency);
  return minor != null && minor > 0 ? minor : null;
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
  final _moneyBindings = <String, MoneyInputBinding>{};
  String get _inputCurrency =>
      _moneyBindings.values.firstOrNull?.currency ?? _currency;
  int? _rate(String field) => _moneyBindings.containsKey(field)
      ? _moneyBindings[field]!.sourceMinor
      : parseRoomRate(_prices[field]!.text, _currency);
  final _form = GlobalKey<FormState>();

  /// "Use the building price" per field (PRICE_DEFAULTS.md): the building's
  /// price, or null when the building has none in this room's currency.
  final _follows = <String, bool>{};
  Map<String, int?> _building = {};
  String? _revision, _message;
  String _currency = 'VND', _name = '';
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
    for (final binding in _moneyBindings.values) {
      binding.dispose();
    }
    for (final c in _prices.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'roomId': widget.roomId,
  };
  void _clear() {
    for (final binding in _moneyBindings.values) {
      binding.dispose();
    }
    _moneyBindings.clear();
    for (final c in _prices.values) {
      c.clear();
    }
    _revision = null;
    _name = '';
    _follows.clear();
    _building = {};
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
        _name = row['roomNumber'] as String;
        final rates = row['ratesMinor'] as Map;
        final follows = (row['follows'] as Map?) ?? const {};
        final building = row['buildingPrices'] as Map?;
        _building = {
          for (final f in rateFields) f: (building?[f] as num?)?.toInt(),
        };
        for (final f in rateFields) {
          _follows[f] = follows[f] == true && _building[f] != null;
        }
        for (final field in rateFields) {
          final value = (rates[field] as num?)?.toInt();
          final conversion = OrganizationMoney.shared.forOrganization(
            widget.organizationId,
          );
          if (conversion != null) {
            _moneyBindings[field] = MoneyInputBinding(
              conversion: conversion,
              sourceCurrency: _currency,
              originalMinor: value,
            );
          }
          _prices[field]!.text = value == null
              ? ''
              : appMoneyInputText(value, _currency);
        }
        _busy = false;
        _message = saved ? 'rates_saved' : null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _clear();
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
      'followBuilding': [
        for (final f in rateFields)
          if (_follows[f] == true) f,
      ],
      'ratesMinor': {
        for (final field in rateFields)
          field: _follows[field] == true
              ? _building[field]
              : (_moneyBindings[field]?.controller ?? _prices[field]!).text
                  .trim()
                  .isEmpty
              ? null
              : _rate(field),
      },
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
        editable = !locked && _revision != null,
        inDialog = DialogPageScope.contains(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: WorkspacePageScope.constraints(context, 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!PageTabScope.contains(context))
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _saving ? null : widget.onBack,
                    child: Text(
                      inDialog
                          ? DialogPageScope.back(context)
                          : t['room_directory'],
                    ),
                  ),
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
                      Text('${t['rates_currency']} $_inputCurrency'),
                      Text(t['rates_info']),
                      const SizedBox(height: 16),
                      // 2026-10-04: no rental mode; every room takes short stays
                      // and leases, and each price is optional.
                      Text(
                        t[_inputCurrency == 'USD'
                            ? 'rates_usd_hint'
                            : 'rates_vnd_hint'],
                      ),
                      for (final field in rateFields) ...[
                        const SizedBox(height: 16),
                        if (_building[field] != null)
                          SwitchListTile(
                            key: ValueKey('rates-follow-$field'),
                            contentPadding: EdgeInsets.zero,
                            value: _follows[field] == true,
                            onChanged: editable
                                ? (v) => setState(() {
                                    _follows[field] = v;
                                    final c = _prices[field]!;
                                    if (!v &&
                                        !_moneyBindings.containsKey(field) &&
                                        c.text.trim().isEmpty) {
                                      c.text = appMoneyInputText(
                                        _building[field]!,
                                        _currency,
                                      );
                                    }
                                  })
                                : null,
                            title: Text(
                              '${t['rates_$field']}: ${_w(context, 'use the building price', 'dùng giá của cơ sở')}',
                            ),
                          ),
                        if (_follows[field] == true)
                          InputDecorator(
                            key: ValueKey('rates-$field-building'),
                            decoration: InputDecoration(
                              labelText: t['rates_$field'],
                              enabled: false,
                              helperText: _w(
                                context,
                                'Changes when the building price changes.',
                                'Đổi theo khi giá của cơ sở đổi.',
                              ),
                              helperMaxLines: 3,
                            ),
                            child: Text(
                              '${appMoneyInputText(_building[field]!, _currency)} $_currency',
                            ),
                          )
                        else
                        TextFormField(
                          key: ValueKey('rates-$field'),
                          controller:
                              _moneyBindings[field]?.controller ??
                              _prices[field],
                          enabled: !locked,
                          readOnly: !editable,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: appMoneyInput(_inputCurrency),
                          decoration: InputDecoration(
                            labelText: t['rates_$field'],
                            errorMaxLines: 8,
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) return null;
                            return (_rate(field) ?? 0) <= 0
                                ? t['rates_invalid']
                                : null;
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      if (_revision != null)
                        WsActions(
                          children: [
                            FilledButton(
                              onPressed: _busy || _saving ? null : _save,
                              child: Text(
                                t[_pending == null
                                    ? 'rates_save'
                                    : 'rates_retry'],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              if (!inDialog || (_revision == null && !_busy))
                WsActions(
                  children: [
                    OutlinedButton(
                      onPressed: locked ? null : () => _load(),
                      child: Text(t['rates_reload']),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
