import '../../utils/money_conversion.dart';
import '../../services/organization_money.dart';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import 'back_steps.dart';
import 'operational_widgets.dart';
import 'ws_ui.dart';
import 'service_fee_text.dart';
import 'period_invoice_form.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';

class InvoiceScreen extends StatefulWidget {
  final String organizationId, buildingId, accountId;
  final TeamService service;

  /// Null inside the organization workspace sections (U1): no Back button
  /// on the list; Back still returns from a booking/invoice to the list.
  final VoidCallback? onBack;
  const InvoiceScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.accountId,
    required this.service,
    this.onBack,
  });
  @override
  State<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<InvoiceScreen> {
  MoneyForm _conversion = MoneyForm(null);
  String get _inputCurrency => _conversion.currency(_currency);
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
  // B6: the period invoice form is open.
  bool _period = false;
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
        _conversion = MoneyForm(
          OrganizationMoney.shared.forOrganization(widget.organizationId),
        );
        _fields['due']!.text = _record!['dueDate'] as String? ?? '';
        for (final k in fees) {
          _conversion.set(
            _fields[k]!,
            (_record!['feesMinor'] as Map?)?[k] as int? ?? 0,
            _currency,
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

  // Grouped: 5,000,000 (2026-10-05, Tom); the currency follows where shown.
  String _money(int minor) => appMoneyMinor(minor, _currency);

  /// What the invoice is for, in words ("Thu · Hóa đơn kỳ").
  String _kindText(BuildContext context, Map row) {
    final x = FeeText(context), calc = row['calculation'] as Map?;
    final what = switch (row['kind']) {
      'period' => x.tr('Period invoice', 'Hóa đơn kỳ'),
      'settlement' => x.tr('Move-out settlement', 'Quyết toán trả phòng'),
      'tenantRent' => x.tr('Rent', 'Tiền thuê'),
      'buildingRent' => x.tr('Property rent', 'Thuê tòa nhà'),
      'service' => '${calc?['feeName'] ?? x.tr('Service fee', 'Phí dịch vụ')}',
      'utility' => utilityName(
        x,
        '${calc?['chargeType'] ?? row['type'] ?? 'electricity'}',
      ),
      // Sheet import (2026-10-05): an expense from the old app ("Chi phí").
      'expense' => [
        '${calc?['category'] ?? ''}',
        '${calc?['content'] ?? ''}',
      ].where((s) => s.isNotEmpty).join(': '),
      // B7: a repair recorded from a technical problem.
      'repair' =>
        '${x.tr('Repair', 'Sửa chữa')}: ${calc?['title'] ?? ''}${calc?['roomNumber'] == null ? '' : ' (${calc?['roomNumber']})'}',
      _ => '',
    };
    final direction = opsText(context, '${row['direction'] ?? 'income'}');
    return what.isEmpty ? direction : '$direction · $what';
  }

  /// Dates as people read them: the last day included (meter readings keep
  /// their reading dates).
  String _dates(Map row) {
    final s = row['startDate'] as String?, e = row['endDate'] as String?;
    if (s == null || e == null) return '';
    // A move-out settlement with no rent left to charge covers no days: show
    // the move-out date alone instead of an end before the start.
    if (s == e) return s;
    return row['kind'] == 'utility' ? '$s – $e' : periodText(s, e);
  }

  /// Status shown: unpaid invoices past their due date are "Quá hạn".
  String _status(Map row) =>
      row['overdue'] == true ? 'overdue' : '${row['status']}';
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
        _conversion = MoneyForm(
          OrganizationMoney.shared.forOrganization(widget.organizationId),
        );
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
      final value = _conversion.parse(_fields[k]!, _currency);
      if (value == null) return null;
      result[k] = value;
    }
    return result;
  }

  Map<String, dynamic> get _charge => _kind == 'charge'
      ? {
          'chargeType': _chargeType,
          'unitPriceMinor': _conversion.parse(_fields['unitPrice']!, _currency),
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
        'inputCurrency': _currency,
        if (_conversion.conversion?.snapshotId != null)
          'ratesId': _conversion.conversion!.snapshotId,
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
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _quote = null;
          _busy = false;
          // Overlapping periods are now refused at review (B6).
          _message =
              serverReason(e, const ['invoice_period_exists']) ==
                  'invoice_period_exists'
              ? 'periodExists'
              : 'unavailable';
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
      final amount = _conversion.parse(_fields['amount']!, _currency);
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
          'inputCurrency': _currency,
          if (_conversion.conversion?.snapshotId != null)
            'ratesId': _conversion.conversion!.snapshotId,
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

  WsTone _tone(Object? status) => switch (status) {
    'paid' => WsTone.good,
    'pending' || 'partial' => WsTone.warning,
    'overdue' => WsTone.bad,
    _ => WsTone.neutral,
  };

  String _statusLabel(BuildContext context, Object? status) {
    final tr = AppTranslations.of(context);
    return tr.translationKeys.contains('payment_status_$status')
        ? tr['payment_status_$status']
        : '$status';
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => opsText(context, k);
    if (_period) {
      return BackStep(
        onBack: () => setState(() => _period = false),
        child: PeriodInvoiceForm(
          service: widget.service,
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          backLabel: t('back'),
          onCancel: () => setState(() => _period = false),
          onDone: () {
            setState(() => _period = false);
            _list();
          },
        ),
      );
    }
    Widget button(String key, VoidCallback? on) =>
        OutlinedButton(onPressed: on, child: Text(t(key)));
    Widget field(String k, {bool required = true}) => opsField(
      context,
      k,
      _fields[k]!,
      enabled: !_locked && _quote == null && (!fees.contains(k) || _canPrice),
      required: required,
      // Money boxes group the digits as you type (2026-10-05, Tom).
      formatters: k == 'unitPrice' || k == 'amount' || fees.contains(k)
          ? appMoneyInput(_inputCurrency)
          : null,
    );
    return BackStep(
      enabled: _mode != 'list',
      onBack: () {
        if (!_locked) _list();
      },
      child: opsPage(context, [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WsHeader(
                back: _mode != 'list' || widget.onBack != null
                    ? WsBack(
                        label: t('back'),
                        onPressed: _locked
                            ? null
                            : (_mode == 'list' ? widget.onBack : () => _list()),
                      )
                    : null,
                title: t('invoices'),
                help: t('invoiceHelp'),
                actions: [
                  // B6: the usual next step for leases is the period invoice.
                  if (_mode == 'list' && _pending == null && _canCreate)
                    FilledButton.icon(
                      key: const ValueKey('invoice-period'),
                      onPressed: _busy
                          ? null
                          : () => setState(() => _period = true),
                      icon: const Icon(Icons.receipt_long_outlined, size: 18),
                      label: Text(
                        FeeText(context).tr('Period invoice', 'Hóa đơn kỳ'),
                      ),
                    ),
                  if (_mode == 'list' && _pending == null && _canCreate)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _new,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(t('create')),
                    ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),
              if (_message != null)
                Semantics(
                  liveRegion: true,
                  child: WsNotice(t(_message!), tone: WsTone.info),
                ),
              if (_pending != null)
                button(
                  'retry',
                  _busy ? null : () => _mutate(_pending!['action'] as String),
                ),
              if (_mode == 'list' && _pending == null) ...[
                for (final row in _rows)
                  WsRecord(
                    tone: _tone(_status(row)),
                    title: '${row['tenantName'] ?? ''}',
                    pill: WsPill(
                      _statusLabel(context, _status(row)),
                      tone: _tone(_status(row)),
                    ),
                    details: [
                      _kindText(context, row),
                      _dates(row),
                      row['totalMinor'] == null
                          ? '${t('total')}: —'
                          : '${t('total')}: ${FeeText(context).money(row['totalMinor'] as num, '${row['currency']}')}'
                                '${row['status'] == 'partial' ? ' · ${t('paid')}: ${FeeText(context).money(row['paidMinor'] as num, '${row['currency']}')}' : ''}',
                    ],
                    actions: [
                      button(
                        'edit',
                        _busy ? null : () => _read(row['id'] as String),
                      ),
                    ],
                  ),
                if (_rows.isEmpty && !_busy)
                  WsEmpty(
                    icon: Icons.receipt_long_outlined,
                    message: t('empty'),
                  ),
                if (_cursor != null)
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => _list(more: true),
                      child: Text(t('more')),
                    ),
                  ),
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
                              _currency =
                                  tenant['currency'] as String? ?? 'VND';
                              for (final k in fees) {
                                _fields[k]!.text = '0';
                              }
                            }),
                      title: Text(
                        '${tenant['fullName']} (${tenant['roomId']})',
                      ),
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
                Text('${t('currency')}: $_inputCurrency'),
                for (final k in fees) field(k),
                field('reason'),
                if (_quote == null)
                  button('review', _busy ? null : _review)
                else ...[
                  Text(
                    '${t('total')}: ${_money(_quote!['totalMinor'] as int)}',
                  ),
                  Text(
                    '${t(_quote!['direction'] as String)} / ${_quote!['days']} ${t('days')}',
                  ),
                  for (final line in _quote!['lines'] as List)
                    Text(
                      '${line['startDate']} – ${line['endDate']}: ${_money(line['rateMinor'] as int)} / ${line['monthDays']}',
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
                                '${t('total')}: ${_money((row[side] as Map)['totalMinor'] as int)}',
                              ),
                              Text(
                                '${t('paid')}: ${appMoney((row[side] as Map)['paidAmount'] as num, _currency)}',
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
                // No internal IDs: the tenant, what it is for, and the dates.
                Text(
                  '${_record!['tenantName']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('${_kindText(context, _record!)} · ${_dates(_record!)}'),
                if (const ['period', 'settlement'].contains(_record!['kind']) &&
                    _record!['calculation'] is Map)
                  for (final line
                      in ((_record!['calculation'] as Map)['lines'] as List? ??
                              const [])
                          .cast<Map>())
                    Builder(
                      builder: (context) {
                        final (label, amount) = describePeriodLine(
                          FeeText(context),
                          line,
                        );
                        return Text(
                          '$label: ${signedMoney(FeeText(context), amount, _currency)}',
                        );
                      },
                    ),
                // B5: which fee, and how each person's share was worked out.
                if (_record!['kind'] == 'service' &&
                    _record!['calculation'] is Map) ...[
                  Text(
                    '${(_record!['calculation'] as Map)['feeName'] ?? ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  for (final line
                      in ((_record!['calculation'] as Map)['lines'] as List? ??
                              const [])
                          .cast<Map>())
                    Text(
                      FeeText(context).line(
                        line,
                        _currency,
                        unitLabel:
                            '${(_record!['calculation'] as Map)['unitLabel'] ?? ''}',
                      ),
                    ),
                ],
                if ('${_record!['notes'] ?? ''}'.trim().isNotEmpty)
                  Text('${_record!['notes']}'),
                const SizedBox(height: WsSpace.xs),
                // Align: a pill sized to its text, not stretched across the page.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: WsPill(
                    _statusLabel(context, _status(_record!)),
                    tone: _tone(_status(_record!)),
                  ),
                ),
                const SizedBox(height: WsSpace.xs),
                Text(
                  '${t('total')}: ${_record!['totalMinor'] == null ? '—' : FeeText(context).money(_record!['totalMinor'] as num, _currency)}',
                ),
                Text(
                  '${t('paid')}: ${FeeText(context).money(_record!['paidMinor'] as num, _currency)}',
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
              // Only as wide as its label (not a full-width bar).
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: button('reload', _locked ? null : () => _list()),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
