import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import 'operational_widgets.dart';

class InvoiceScreen extends StatefulWidget {
  final String organizationId, buildingId, accountId;
  final TeamService service;
  final VoidCallback onBack;
  const InvoiceScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.accountId,
    required this.service,
    required this.onBack,
  });
  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  static const fees = [
    'internetFee',
    'cableTVFee',
    'hotWaterFee',
    'lateFee',
    'taxAmount',
  ];
  final _fields = {
    for (final k in [
      'start',
      'end',
      'due',
      'reason',
      'amount',
      'unitPrice',
      'quantity',
      ...fees,
    ])
      k: TextEditingController(),
  };
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _rows = [], _tenants = [];
  Map<String, dynamic>? _record, _quote, _pending;
  String? _cursor, _tenant, _message, _historyCursor;
  List<Map<String, dynamic>> _history = [];
  bool _showHistory = false;
  String _chargeType = 'electricity', _propertyCurrency = 'VND';
  String _kind = 'tenantRent',
      _mode = 'list',
      _method = 'cash',
      _currency = 'VND';
  bool _busy = true, _canCreate = false, _canPrice = false;
  int _generation = 0;
  String get _journal =>
      'invoice-pending:${jsonEncode([widget.accountId, widget.organizationId, widget.buildingId])}';
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
  };
  bool get _locked => _busy || _pending != null;
  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant InvoiceScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.accountId != widget.accountId ||
        old.service != widget.service) {
      _generation++;
      _pending = null;
      _record = null;
      _quote = null;
      _init();
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _rows = [];
      _record = null;
      _quote = null;
    });
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_journal);
      if (!mounted || generation != _generation) return;
      if (raw != null) {
        setState(() {
          _pending = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          _busy = false;
          _message = 'uncertain';
        });
        return;
      }
      await _list();
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message = 'unavailable';
        });
      }
    }
  }

  Future<void> _list({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _mode = 'list';
      _showHistory = false;
      _history = [];
      _record = null;
      _quote = null;
      _message = null;
      if (!more) {
        _rows = [];
        _cursor = null;
      }
    });
    try {
      final r = await widget.service.invoices({
        ..._identity,
        'action': 'list',
        if (more) 'cursor': _cursor,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _rows.map((v) => v['id']).toSet();
        _rows.addAll(
          (r['records'] as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .where((v) => ids.add(v['id'])),
        );
        _cursor = r['nextCursor'] as String?;
        _canCreate = r['canCreate'] == true;
        _canPrice = r['canPrice'] == true;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _rows = [];
          _busy = false;
          _message = 'unavailable';
        });
      }
    }
  }

  Future<void> _read(String id) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _record = null;
      _quote = null;
      _rows = [];
      _message = null;
    });
    try {
      final r = await widget.service.invoices({
        ..._identity,
        'action': 'read',
        'invoiceId': id,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = Map<String, dynamic>.from(r['record'] as Map);
        _currency = _record!['currency'] as String;
        _fields['due']!.text = _record!['dueDate'] as String? ?? '';
        for (final k in fees) {
          _fields[k]!.text = _money(
            (_record!['feesMinor'] as Map?)?[k] as int? ?? 0,
          );
        }
        _fields['reason']!.clear();
        _mode = 'detail';
        _showHistory = false;
        _history = [];
        _busy = false;
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

  Future<void> _readHistory({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _showHistory = true;
      if (!more) {
        _history = [];
        _historyCursor = null;
      }
    });
    try {
      final r = await widget.service.invoices({
        ..._identity,
        'action': 'history',
        'invoiceId': _record!['id'],
        if (more) 'cursor': _historyCursor,
      });
      if (mounted && generation == _generation) {
        setState(() {
          _history.addAll(
            (r['records'] as List).map(
              (v) => Map<String, dynamic>.from(v as Map),
            ),
          );
          _historyCursor = r['nextCursor'] as String?;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _history = [];
          _record = null;
          _busy = false;
          _message = 'unavailable';
        });
      }
    }
  }

  String _money(int minor) =>
      _currency == 'USD' ? (minor / 100).toStringAsFixed(2) : '$minor';
  Future<void> _new() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _record = null;
      _quote = null;
      _message = null;
      _tenants = [];
    });
    try {
      final r = await widget.service.invoices({
        ..._identity,
        'action': 'tenants',
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _tenants = (r['records'] as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        _tenant = _tenants.firstOrNull?['id'] as String?;
        _propertyCurrency = r['currency'] as String? ?? 'VND';
        _currency = _kind == 'buildingRent'
            ? (r['currency'] as String? ?? 'VND')
            : (_tenants.firstOrNull?['currency'] as String? ??
                  r['currency'] as String? ??
                  'VND');
        for (final k in fees) {
          _fields[k]!.text = '0';
        }
        _fields['start']!.text = r['today'] as String;
        _fields['end']!.clear();
        _fields['due']!.text = r['today'] as String;
        _fields['reason']!.clear();
        _mode = 'create';
        _busy = false;
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

  Map<String, dynamic>? _fees() {
    final result = <String, dynamic>{};
    for (final k in fees) {
      final value = operationalMoney(_fields[k]!.text, _currency);
      if (value == null) return null;
      result[k] = value;
    }
    return result;
  }

  Map<String, dynamic> get _charge => _kind == 'charge'
      ? {
          'chargeType': _chargeType,
          'unitPriceMinor': operationalMoney(
            _fields['unitPrice']!.text,
            _currency,
          ),
          'quantityMilli':
              RegExp(
                r'^\d+(?:[.,]\d{1,3})?$',
              ).hasMatch(_fields['quantity']!.text.trim())
              ? (double.parse(_fields['quantity']!.text.replaceAll(',', '.')) *
                        1000)
                    .round()
              : null,
        }
      : {};

  Future<void> _review() async {
    if (!_form.currentState!.validate()) return;
    final values = _fees();
    if (values == null) {
      setState(() => _message = 'required');
      return;
    }
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final r = await widget.service.invoices({
        ..._identity,
        'action': 'quote',
        'kind': _kind,
        'tenantId': _kind == 'buildingRent' ? null : _tenant,
        ..._charge,
        'startDate': _fields['start']!.text.trim(),
        'endDate': _fields['end']!.text.trim(),
        'dueDate': _fields['due']!.text.trim(),
        'feesMinor': values,
        'reason': _fields['reason']!.text.trim(),
      });
      if (mounted && generation == _generation) {
        setState(() {
          _quote = Map<String, dynamic>.from(r['record'] as Map);
          _currency = _quote!['currency'] as String;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _quote = null;
          _busy = false;
          _message = 'unavailable';
        });
      }
    }
  }

  Future<void> _mutate(String action) async {
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      final f = _fees();
      if ((action == 'edit' || action == 'create') && f == null) {
        setState(() => _message = 'required');
        return;
      }
      final amount = operationalMoney(_fields['amount']!.text, _currency);
      if (['payExpense', 'reverseExpense'].contains(action) &&
          (amount == null || amount <= 0)) {
        setState(() => _message = 'required');
        return;
      }
      _pending = {
        ..._identity,
        'action': action,
        'operationId': const Uuid().v4(),
        'reason': _fields['reason']!.text.trim(),
        if (action == 'create') ...{
          'kind': _kind,
          'tenantId': _kind == 'buildingRent' ? null : _tenant,
          ..._charge,
          'startDate': _fields['start']!.text.trim(),
          'endDate': _fields['end']!.text.trim(),
          'dueDate': _fields['due']!.text.trim(),
          'feesMinor': f,
          'quoteRevision': _quote!['quoteRevision'],
        } else ...{
          'invoiceId': _record!['id'],
          'revision': _record!['revision'],
        },
        if (action == 'edit') ...{
          'dueDate': _fields['due']!.text.trim(),
          'feesMinor': f,
        },
        if (['payExpense', 'reverseExpense'].contains(action)) ...{
          'amountMinor': amount,
          'paymentMethod': _method,
        },
      };
    }
    final generation = ++_generation, journal = _journal;
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(journal, jsonEncode(_pending))) {
        throw StateError('Storage');
      }
      if (!mounted || generation != _generation) return;
      final result = await widget.service.invoices(_pending!);
      if (!await prefs.remove(journal)) throw StateError('Storage');
      if (!mounted || generation != _generation) return;
      _pending = null;
      await _read(result['invoiceId'] as String);
      if (mounted) setState(() => _message = 'saved');
    } catch (e) {
      if (!mounted || generation != _generation) return;
      if (e is FirebaseFunctionsException &&
          ![
            'unavailable',
            'internal',
            'deadline-exceeded',
            'unknown',
          ].contains(e.code)) {
        try {
          await (await SharedPreferences.getInstance()).remove(journal);
        } catch (_) {}
        if (!mounted || generation != _generation) return;
        setState(() {
          _pending = null;
          _record = null;
          _quote = null;
          _rows = [];
          _busy = false;
          _message = 'unavailable';
        });
      } else {
        setState(() {
          _busy = false;
          _message = 'uncertain';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => opsText(context, k);
    Widget button(String key, VoidCallback? on) =>
        OutlinedButton(onPressed: on, child: Text(t(key)));
    Widget field(String k, {bool required = true}) => opsField(
      context,
      k,
      _fields[k]!,
      enabled: !_locked && _quote == null && (!fees.contains(k) || _canPrice),
      required: required,
    );
    return opsPage(context, [
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            button(
              'back',
              _locked
                  ? null
                  : (_mode == 'list' ? widget.onBack : () => _list()),
            ),
            Text(
              t('invoices'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(t('invoiceHelp')),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null)
              Semantics(liveRegion: true, child: Text(t(_message!))),
            if (_pending != null)
              button(
                'retry',
                _busy ? null : () => _mutate(_pending!['action'] as String),
              ),
            if (_mode == 'list' && _pending == null) ...[
              if (_canCreate) button('create', _busy ? null : _new),
              for (final row in _rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${row['tenantName']} / ${row['id']}'),
                        Text(
                          '${t(row['direction'] as String)} • ${row['status']}',
                        ),
                        Text(
                          '${row['startDate'] ?? ''} – ${row['endDate'] ?? ''}',
                        ),
                        Text(
                          '${t('total')}: ${row['totalMinor'] == null
                              ? '—'
                              : row['currency'] == 'USD'
                              ? ((row['totalMinor'] as num) / 100).toStringAsFixed(2)
                              : row['totalMinor']} ${row['currency']}',
                        ),
                        button(
                          'edit',
                          _busy ? null : () => _read(row['id'] as String),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_rows.isEmpty && !_busy) Text(t('empty')),
              if (_cursor != null)
                button('more', _busy ? null : () => _list(more: true)),
            ],
            if (_mode == 'create' && _pending == null) ...[
              for (final kind in [
                'tenantRent',
                'buildingRent',
                if (_canPrice) 'charge',
              ])
                CheckboxListTile(
                  value: _kind == kind,
                  onChanged: _locked || _quote != null
                      ? null
                      : (_) => setState(() {
                          _kind = kind;
                          _currency = kind == 'buildingRent'
                              ? _propertyCurrency
                              : (_tenants
                                            .where((v) => v['id'] == _tenant)
                                            .firstOrNull?['currency']
                                        as String? ??
                                    'VND');
                          for (final k in fees) {
                            _fields[k]!.text = '0';
                          }
                        }),
                  title: Text(t(kind)),
                ),
              if (_kind != 'buildingRent')
                for (final tenant in _tenants)
                  CheckboxListTile(
                    value: _tenant == tenant['id'],
                    onChanged: _locked || _quote != null
                        ? null
                        : (_) => setState(() {
                            _tenant = tenant['id'] as String;
                            _currency = tenant['currency'] as String? ?? 'VND';
                            for (final k in fees) {
                              _fields[k]!.text = '0';
                            }
                          }),
                    title: Text('${tenant['fullName']} (${tenant['roomId']})'),
                  ),
              if (_kind == 'charge') ...[
                for (final type in [
                  'electricity',
                  'water',
                  'internet',
                  'parking',
                  'maintenance',
                  'deposit',
                  'penalty',
                  'other',
                ])
                  CheckboxListTile(
                    value: _chargeType == type,
                    onChanged: _locked || _quote != null
                        ? null
                        : (_) => setState(() => _chargeType = type),
                    title: Text(t(type)),
                  ),
                field('unitPrice'),
                field('quantity'),
              ],
              field('start'),
              field('end'),
              field('due'),
              Text('${t('currency')}: $_currency'),
              for (final k in fees) field(k),
              field('reason'),
              if (_quote == null)
                button('review', _busy ? null : _review)
              else ...[
                Text(
                  '${t('total')}: ${_money(_quote!['totalMinor'] as int)} $_currency',
                ),
                Text(
                  '${t(_quote!['direction'] as String)} / ${_quote!['days']} ${t('days')}',
                ),
                for (final line in _quote!['lines'] as List)
                  Text(
                    '${line['startDate']} – ${line['endDate']}: ${_money(line['rateMinor'] as int)} $_currency / ${line['monthDays']}',
                  ),
                button('confirm', _busy ? null : () => _mutate('create')),
                button(
                  'edit',
                  _busy ? null : () => setState(() => _quote = null),
                ),
              ],
            ],
            if (_showHistory) ...[
              for (final row in _history)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${row['createdAt']} / ${row['actorId']}'),
                        Text(t(row['action'] as String)),
                        Text('${row['reason']}'),
                        for (final side in ['before', 'after'])
                          if (row[side] != null) ...[
                            Text(t(side)),
                            Text(
                              '${t('total')}: ${_money((row[side] as Map)['totalMinor'] as int)} $_currency',
                            ),
                            Text(
                              '${t('paid')}: ${(row[side] as Map)['paidAmount']} $_currency',
                            ),
                            Text(
                              '${t('status')}: ${(row[side] as Map)['status']}',
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
              if (_historyCursor != null)
                button('more', _busy ? null : () => _readHistory(more: true)),
              button(
                'back',
                _busy ? null : () => setState(() => _showHistory = false),
              ),
            ],
            if (_record != null && _mode != 'create' && !_showHistory) ...[
              Text('${_record!['tenantName']} / ${_record!['id']}'),
              Text(
                '${t(_record!['direction'] as String)} • ${_record!['status']}',
              ),
              Text(
                '${t('total')}: ${_record!['totalMinor'] == null ? '—' : _money(_record!['totalMinor'] as int)} $_currency',
              ),
              Text(
                '${t('paid')}: ${_money(_record!['paidMinor'] as int)} $_currency',
              ),
              button('history', _locked ? null : () => _readHistory()),
              field('reason'),
              if (_record!['canEdit'] == true) ...[
                field('due'),
                for (final k in fees) field(k),
                button('save', _locked ? null : () => _mutate('edit')),
                button('void', _locked ? null : () => _mutate('void')),
              ],
              if (_record!['canSettle'] == true ||
                  _record!['canReverse'] == true) ...[
                field('amount'),
                for (final method in ['cash', 'bankTransfer'])
                  CheckboxListTile(
                    value: _method == method,
                    onChanged: _locked
                        ? null
                        : (_) => setState(() => _method = method),
                    title: Text(t(method)),
                  ),
                Text(t('reviewWarning')),
                if (_record!['canSettle'] == true)
                  button(
                    'payExpense',
                    _locked ? null : () => _mutate('payExpense'),
                  ),
                if (_record!['canReverse'] == true)
                  button(
                    'reverseExpense',
                    _locked ? null : () => _mutate('reverseExpense'),
                  ),
              ],
            ],
            button('reload', _locked ? null : () => _list()),
          ],
        ),
      ),
    ]);
  }
}
