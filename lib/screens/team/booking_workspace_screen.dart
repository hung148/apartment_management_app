import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import 'operational_widgets.dart';

class BookingWorkspaceScreen extends StatefulWidget {
  final String organizationId, buildingId, accountId;
  final TeamService service;
  final VoidCallback onBack;
  const BookingWorkspaceScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.accountId,
    required this.service,
    required this.onBack,
  });
  @override
  State<BookingWorkspaceScreen> createState() => _BookingWorkspaceScreenState();
}

class _BookingWorkspaceScreenState extends State<BookingWorkspaceScreen> {
  final _fields = {
        for (final k in [
          'guest',
          'phone',
          'notes',
          'startLocal',
          'endLocal',
          'depositAmount',
          'amount',
          'reason',
          'overridePrice',
          'overrideReason',
        ])
          k: TextEditingController(),
      },
      _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _rows = [], _rooms = [];
  Map<String, dynamic>? _record, _quote, _pending;
  String? _cursor, _room, _message, _command, _status;
  String _mode = 'list',
      _pricing = 'hourly',
      _occurrence = 'first',
      _method = 'cash',
      _zone = '',
      _currency = 'VND';
  bool _busy = true, _canManage = false, _canPrice = false;
  int _generation = 0;
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
  };
  String get _journal =>
      'booking-pending:${jsonEncode([widget.accountId, widget.organizationId, widget.buildingId])}';
  bool get _locked => _busy || _pending != null;
  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant BookingWorkspaceScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.accountId != widget.accountId ||
        old.service != widget.service) {
      _generation++;
      _pending = null;
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
      if (mounted && generation == _generation) _deny();
    }
  }

  void _deny() {
    setState(() {
      _busy = false;
      _rows = [];
      _rooms = [];
      _record = null;
      _quote = null;
      _mode = 'list';
      _canManage = false;
      _message = 'unavailable';
      for (final c in _fields.values) {
        c.clear();
      }
    });
  }

  Future<void> _list({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _mode = 'list';
      _message = null;
      _record = null;
      _quote = null;
      _command = null;
      if (!more) {
        _rows = [];
        _cursor = null;
      }
    });
    try {
      final r = await widget.service.bookingWorkspace({
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
        _canManage = r['canManage'] == true;
        _zone = r['timeZone'] as String;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) _deny();
    }
  }

  Future<void> _read(String id) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _record = null;
      _rows = [];
      _quote = null;
      _command = null;
      _status = null;
    });
    try {
      final r = await widget.service.bookingWorkspace({
        ..._identity,
        'action': 'read',
        'bookingId': id,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = Map<String, dynamic>.from(r['record'] as Map);
        _currency = _record!['currency'] as String;
        _zone = _record!['timeZone'] as String;
        _mode = 'detail';
        _busy = false;
        _fields['reason']!.clear();
        _fields['amount']!.clear();
      });
    } catch (_) {
      if (mounted && generation == _generation) _deny();
    }
  }

  Future<void> _edit({bool create = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _quote = null;
      _message = null;
      if (create) _record = null;
    });
    try {
      final r = await widget.service.bookingWorkspace({
        ..._identity,
        'action': 'rooms',
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _rooms = (r['records'] as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        _zone = r['timeZone'] as String;
        _canPrice = r['canPrice'] == true;
        _fields['overridePrice']!.clear();
        _fields['overrideReason']!.clear();
        _room =
            _record?['roomId'] as String? ??
            _rooms.firstOrNull?['id'] as String?;
        _currency =
            _record?['currency'] as String? ??
            _rooms.where((v) => v['id'] == _room).firstOrNull?['currency']
                as String? ??
            'VND';
        _pricing = _record?['pricingType'] as String? ?? 'hourly';
        for (final k in [
          'guest',
          'phone',
          'notes',
          'startLocal',
          'endLocal',
          'depositAmount',
        ]) {
          _fields[k]!.text =
              '${_record?[{'guest': 'guestName', 'phone': 'guestPhone', 'depositAmount': 'depositAmount'}[k] ?? k] ?? (k == 'depositAmount' ? '0' : '')}';
        }
        _mode = 'edit';
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) _deny();
    }
  }

  Future<void> _review() async {
    if (!_form.currentState!.validate()) return;
    if (_canPrice &&
        _fields['overridePrice']!.text.trim().isNotEmpty &&
        (operationalMoney(_fields['overridePrice']!.text, _currency) == null ||
            _fields['overrideReason']!.text.trim().isEmpty)) {
      setState(() => _message = 'required');
      return;
    }
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final r = await widget.service.bookingWorkspace({
        ..._identity,
        'action': 'quote',
        'roomId': _room,
        'startLocal': _fields['startLocal']!.text.trim(),
        'endLocal': _fields['endLocal']!.text.trim(),
        'occurrence': _occurrence,
        'pricingType': _pricing,
        if (_canPrice && _fields['overridePrice']!.text.trim().isNotEmpty) ...{
          'overrideMinor': operationalMoney(
            _fields['overridePrice']!.text,
            _currency,
          ),
          'overrideReason': _fields['overrideReason']!.text.trim(),
        },
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _quote = Map<String, dynamic>.from(r['record'] as Map);
        _currency = _quote!['currency'] as String;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _quote = null;
          _message = 'unavailable';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      if (_mode == 'edit') {
        final deposit = operationalMoney(
          _fields['depositAmount']!.text,
          _currency,
        );
        if (deposit == null) {
          setState(() => _message = 'required');
          return;
        }
        _pending = {
          ..._identity,
          'action': 'save',
          'bookingId': _record?['id'] ?? const Uuid().v4(),
          'operationId': const Uuid().v4(),
          'revision': _record?['revision'],
          'roomId': _room,
          'roomRevision': _quote!['roomRevision'],
          'startLocal': _fields['startLocal']!.text.trim(),
          'endLocal': _fields['endLocal']!.text.trim(),
          'occurrence': _occurrence,
          'pricingType': _pricing,
          if (_canPrice &&
              _fields['overridePrice']!.text.trim().isNotEmpty) ...{
            'overrideMinor': operationalMoney(
              _fields['overridePrice']!.text,
              _currency,
            ),
            'overrideReason': _fields['overrideReason']!.text.trim(),
          },
          'guestName': _fields['guest']!.text.trim(),
          'guestPhone': _fields['phone']!.text.trim(),
          'notes': _fields['notes']!.text.trim(),
          'depositMinor': deposit,
        };
      } else {
        final amount = operationalMoney(_fields['amount']!.text, _currency);
        if (['payment', 'deposit', 'refund', 'refundRent'].contains(_command) &&
            (amount == null || amount <= 0)) {
          setState(() => _message = 'required');
          return;
        }
        _pending = {
          ..._identity,
          'action': 'command',
          'bookingId': _record!['id'],
          'operationId': const Uuid().v4(),
          'revision': _record!['revision'],
          'command': _command,
          'status': _status,
          'reason': _fields['reason']!.text.trim(),
          'paymentMethod': _method,
          'amountMinor': amount,
        };
      }
    }
    final generation = ++_generation, journal = _journal;
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(journal, jsonEncode(_pending))) {
        throw StateError('Storage');
      }
      if (!mounted || generation != _generation) return;
      final r = await widget.service.bookingWorkspace(_pending!);
      if (!await prefs.remove(journal)) throw StateError('Storage');
      if (!mounted || generation != _generation) return;
      _pending = null;
      await _read(r['id'] as String);
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
        _pending = null;
        _deny();
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
    Widget button(String k, VoidCallback? f) =>
        OutlinedButton(onPressed: f, child: Text(t(k)));
    Widget field(String k, {bool required = true}) => opsField(
      context,
      k,
      _fields[k]!,
      enabled: !_locked && _quote == null,
      required: required,
    );
    final r = _record;
    String money(num v) =>
        _currency == 'USD' ? v.toStringAsFixed(2) : v.toStringAsFixed(0);
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
              t('bookings'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(t('bookingHelp')),
            Text(_zone),
            if (_busy) const LinearProgressIndicator(),
            if (_message != null) Text(t(_message!)),
            if (_pending != null) button('retry', _busy ? null : _save),
            if (_mode == 'list' && _pending == null) ...[
              if (_canManage)
                button('create', _busy ? null : () => _edit(create: true)),
              for (final row in _rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${row['guestName']} / ${row['roomId']}'),
                        Text('${row['startLocal']} – ${row['endLocal']}'),
                        Text('${row['status']}'),
                        button(
                          'review',
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
            if (_mode == 'edit' && _pending == null) ...[
              for (final room in _rooms)
                CheckboxListTile(
                  value: _room == room['id'],
                  onChanged: _locked || _quote != null || r != null
                      ? null
                      : (_) => setState(() {
                          _room = room['id'] as String;
                          _currency = room['currency'] as String? ?? 'VND';
                        }),
                  title: Text(room['roomNumber'] as String),
                ),
              field('guest'),
              field('phone', required: false),
              field('startLocal'),
              field('endLocal'),
              for (final type in ['hourly', 'daily', 'overnight'])
                CheckboxListTile(
                  value: _pricing == type,
                  onChanged: _locked || _quote != null
                      ? null
                      : (_) => setState(() => _pricing = type),
                  title: Text(t(type)),
                ),
              Text(t('occurrence')),
              for (final value in ['first', 'second'])
                CheckboxListTile(
                  value: _occurrence == value,
                  onChanged: _locked || _quote != null
                      ? null
                      : (_) => setState(() => _occurrence = value),
                  title: Text(t(value)),
                ),
              if (_canPrice) ...[
                field('overridePrice', required: false),
                field('overrideReason', required: false),
              ],
              field('depositAmount'),
              field('notes', required: false),
              if (_quote == null)
                button('review', _busy ? null : _review)
              else ...[
                Text(
                  '${t('total')}: ${money((_quote!['totalMinor'] as num) / (_currency == 'USD' ? 100 : 1))} $_currency',
                ),
                Text('${_quote!['startTime']} – ${_quote!['endTime']} (UTC)'),
                button('confirm', _busy ? null : _save),
                button(
                  'edit',
                  _busy ? null : () => setState(() => _quote = null),
                ),
              ],
            ],
            if (_mode == 'detail' && r != null) ...[
              Text('${r['guestName']} / ${r['roomId']}'),
              Text('${r['startLocal']} – ${r['endLocal']}'),
              Text('${t('status')}: ${r['status']}'),
              Text('${t('total')}: ${r['totalPrice']} $_currency'),
              Text('${t('paid')}: ${r['paidAmount']} $_currency'),
              Text(
                '${t('depositAmount')}: ${r['depositPaidAmount']} / ${r['depositAmount']} $_currency',
              ),
              if (_command == null) ...[
                if (r['canManage'] == true &&
                    ['pending', 'confirmed', 'checkedIn'].contains(r['status']))
                  button('edit', _locked ? null : () => _edit()),
                if (r['canManage'] == true)
                  for (final status
                      in (r['status'] == 'pending'
                          ? ['confirmed', 'checkedIn', 'cancelled', 'noShow']
                          : r['status'] == 'confirmed'
                          ? ['checkedIn', 'cancelled', 'noShow']
                          : r['status'] == 'checkedIn'
                          ? ['cancelled']
                          : <String>[]))
                    button(
                      status,
                      _locked
                          ? null
                          : () => setState(() {
                              _command = 'status';
                              _status = status;
                            }),
                    ),
                if (r['canCollect'] == true &&
                    ['pending', 'confirmed', 'checkedIn'].contains(r['status']))
                  for (final action in [
                    'payment',
                    'deposit',
                    if (r['status'] == 'checkedIn' && r['canManage'] == true)
                      'checkout',
                  ])
                    button(
                      action,
                      _locked ? null : () => setState(() => _command = action),
                    ),
                if (r['canRefund'] == true)
                  for (final action in ['refund', 'refundRent'])
                    button(
                      action,
                      _locked ? null : () => setState(() => _command = action),
                    ),
              ] else ...[
                Text(t(_status ?? _command!)),
                Text(t('reviewWarning')),
                field('reason'),
                if ([
                  'payment',
                  'deposit',
                  'refund',
                  'refundRent',
                ].contains(_command))
                  field('amount'),
                for (final method in ['cash', 'bankTransfer'])
                  CheckboxListTile(
                    value: _method == method,
                    onChanged: _locked
                        ? null
                        : (_) => setState(() => _method = method),
                    title: Text(t(method)),
                  ),
                button('confirm', _locked ? null : _save),
                button(
                  'cancel',
                  _locked
                      ? null
                      : () => setState(() {
                          _command = null;
                          _status = null;
                        }),
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
