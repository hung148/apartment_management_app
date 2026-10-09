import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../services/organization_money.dart';
import '../../utils/money_conversion.dart';
import 'back_steps.dart';
import 'service_fee_text.dart';
import 'workspace_page_scope.dart';
import 'ws_ui.dart';
import '../../utils/app_number.dart';

/// B5: the service fees of one room — what applies, room-only prices, and
/// invoices with a line per person.
class RoomServiceFeesScreen extends StatefulWidget {
  final String organizationId, buildingId, roomId;
  final TeamService service;
  final VoidCallback onBack;

  /// Opens the building's service fees (the room dialog, 2026-10-05, Tom).
  final VoidCallback? onBuildingFees;
  const RoomServiceFeesScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.service,
    required this.onBack,
    this.onBuildingFees,
  });
  @override
  State<RoomServiceFeesScreen> createState() => _RoomServiceFeesScreenState();
}

class _RoomServiceFeesScreenState extends State<RoomServiceFeesScreen> {
  Map<String, dynamic>? _record;
  Map<String, dynamic>? _billing;
  bool _busy = true;
  String? _error, _saved;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RoomServiceFeesScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.roomId != widget.roomId ||
        old.service != widget.service) {
      _billing = null;
      _saved = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.serviceFees({
        'action': 'read',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'roomId': widget.roomId,
      });
      if (!mounted || generation != _generation) return;
      setState(
        () => _record = Map<String, dynamic>.from(data['record'] as Map),
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = null;
        _error = FeeText(context).error(e);
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _roomRate(Map fee) async {
    final record = _record;
    if (record == null || _busy) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _RoomRateDialog(
        service: widget.service,
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        roomId: widget.roomId,
        revision: record['roomRevision'] as int? ?? 0,
        currency: record['currency'] as String? ?? 'VND',
        today: record['today'] as String?,
        fee: fee,
      ),
    );
    if (saved == true && mounted) {
      setState(
        () => _saved = FeeText(
          context,
        ).tr('Room price saved.', 'Đã lưu giá phòng.'),
      );
      _load();
    }
  }

  /// "Room price" / "Not charged here" / "Property price".
  (String, WsTone) _source(FeeText x, Map fee) {
    final current = fee['current'] as Map?;
    if (current == null) {
      final off = _latestOverride(fee)?['mode'] == 'off';
      return (
        off
            ? x.tr('Off here', 'Tắt ở phòng')
            : x.tr('Not charged', 'Không thu'),
        WsTone.neutral,
      );
    }
    return current['roomRate'] == true
        ? (x.tr('Room price', 'Giá riêng'), WsTone.warning)
        : (x.tr('Property price', 'Giá chung'), WsTone.info);
  }

  Map? _latestOverride(Map fee) {
    final today = _record?['today'] as String?;
    final rows = (fee['overrides'] as List? ?? const []).cast<Map>();
    Map? found;
    for (final o in rows) {
      if (today == null || (o['effectiveDate'] as String).compareTo(today) <= 0)
        found = o;
    }
    return found;
  }

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context), record = _record;
    final currency = record?['currency'] as String? ?? 'VND';
    if (_billing != null && record != null) {
      return BackStep(
        onBack: () => setState(() => _billing = null),
        child: ServiceInvoiceForm(
          key: ValueKey('fee-invoice-${_billing!['id']}'),
          service: widget.service,
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          roomId: widget.roomId,
          roomNumber: record['roomNumber'] as String? ?? '',
          currency: currency,
          today: record['today'] as String?,
          tenants: (record['tenants'] as List? ?? const []).cast<Map>(),
          fee: _billing!,
          onDone: () {
            setState(() {
              _billing = null;
              _saved = x.tr(
                'Invoice created. It is in Money › Invoices.',
                'Đã tạo hóa đơn. Xem trong Thu chi › Hóa đơn.',
              );
            });
            _load();
          },
          onCancel: () => setState(() => _billing = null),
        ),
      );
    }
    final fees = (record?['fees'] as List? ?? const []).cast<Map>();
    final room = record?['roomNumber'] as String?;
    return WsPage(
      children: [
        WsHeader(
          back: PageTabScope.contains(context)
              ? null
              : WsBack(
                  label: x.tr('Rooms', 'Quản lý phòng'),
                  onPressed: widget.onBack,
                ),
          title: room == null || room.isEmpty
              ? x.tr('Service fees', 'Phí dịch vụ')
              : x.tr('Service fees · Room $room', 'Phí dịch vụ · Phòng $room'),
          help: x.tr(
            'Fees come from the property. A room price or "off" here applies to this room only.',
            'Phí lấy từ cài đặt tòa nhà. Giá riêng hoặc "không thu" ở đây chỉ áp dụng cho phòng này.',
          ),
          actions: [
            if (widget.onBuildingFees != null)
              OutlinedButton.icon(
                key: const ValueKey('room-fees-building'),
                onPressed: widget.onBuildingFees,
                icon: const Icon(Icons.apartment_outlined, size: 18),
                label: Text(x.tr('Building fees', 'Phí tòa nhà')),
              ),
          ],
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(),
          ),
        if (_saved != null)
          Semantics(
            liveRegion: true,
            child: WsNotice(_saved!, tone: WsTone.good),
          ),
        if (_error != null) ...[
          Semantics(liveRegion: true, child: WsNotice(_error!)),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              onPressed: _busy ? null : _load,
              child: Text(x.tr('Retry', 'Thử lại')),
            ),
          ),
        ],
        if (record != null && !_busy && fees.isEmpty)
          WsEmpty(
            icon: Icons.receipt_long_outlined,
            message: x.tr(
              'No service fees yet. Add them in Rooms › Service fees.',
              'Chưa có phí dịch vụ. Thêm trong Phòng › Phí dịch vụ.',
            ),
          ),
        for (final fee in fees)
          Builder(
            builder: (context) {
              final (label, tone) = _source(x, fee);
              final next = [
                for (final o
                    in (fee['overrides'] as List? ?? const []).cast<Map>())
                  if (record?['today'] != null &&
                      (o['effectiveDate'] as String).compareTo(
                            record!['today'] as String,
                          ) >
                          0)
                    switch (o['mode']) {
                      'off' => x.tr(
                        'Off from ${o['effectiveDate']}',
                        'Không thu từ ${o['effectiveDate']}',
                      ),
                      'rate' => x.tr(
                        'Room price ${x.money(o['rateMinor'] as num, o['currency'] as String? ?? currency)} from ${o['effectiveDate']}',
                        'Giá riêng ${x.money(o['rateMinor'] as num, o['currency'] as String? ?? currency)} từ ${o['effectiveDate']}',
                      ),
                      _ => x.tr(
                        'Property price from ${o['effectiveDate']}',
                        'Về giá chung từ ${o['effectiveDate']}',
                      ),
                    },
              ];
              return WsRecord(
                key: ValueKey('room-fee-${fee['id']}'),
                title: fee['name'] as String,
                pill: WsPill(label, tone: tone),
                details: [
                  '${x.basis(fee['basis'] as String)} · ${x.terms(fee, fee['current'] as Map?, currency)}',
                  if (fee['current'] != null && fee['basis'] != 'quantity')
                    x.rule((fee['current'] as Map)['rule'] as Map?),
                  ...next,
                ],
                actions: [
                  if (record?['canBill'] == true)
                    FilledButton(
                      key: ValueKey('room-fee-bill-${fee['id']}'),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              _saved = null;
                              _billing = Map<String, dynamic>.from(fee);
                            }),
                      child: Text(x.tr('Invoice', 'Lập hóa đơn')),
                    ),
                  if (record?['canPrice'] == true)
                    OutlinedButton(
                      key: ValueKey('room-fee-rate-${fee['id']}'),
                      onPressed: _busy ? null : () => _roomRate(fee),
                      child: Text(x.tr('Room price', 'Giá riêng')),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _RoomRateDialog extends StatefulWidget {
  final TeamService service;
  final String organizationId, buildingId, roomId, currency;
  final String? today;
  final int revision;
  final Map fee;
  const _RoomRateDialog({
    required this.service,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.currency,
    required this.today,
    required this.revision,
    required this.fee,
  });
  @override
  State<_RoomRateDialog> createState() => _RoomRateDialogState();
}

class _RoomRateDialogState extends State<_RoomRateDialog> {
  late final _money = MoneyForm(
    OrganizationMoney.shared.forOrganization(widget.organizationId),
  );
  String get _inputCurrency => _money.currency(widget.currency);
  final _form = GlobalKey<FormState>();
  late final _date = TextEditingController(text: widget.today ?? '');
  final _rate = TextEditingController(), _reason = TextEditingController();
  String _mode = 'rate';
  Map<String, dynamic>? _pending;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _date.dispose();
    _rate.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final x = FeeText(context);
    if (_busy || (_pending == null && !_form.currentState!.validate())) return;
    _pending ??= {
      'action': 'roomRate',
      'inputCurrency': _inputCurrency,
      'organizationId': widget.organizationId,
      'buildingId': widget.buildingId,
      'roomId': widget.roomId,
      'operationId': const Uuid().v4(),
      'revision': widget.revision,
      'reason': _reason.text.trim(),
      'feeId': widget.fee['id'],
      'override': {
        'effectiveDate': _date.text.trim(),
        'mode': _mode,
        if (_mode == 'rate') 'rateMinor': appParseMoney(_rate.text, _inputCurrency),
      },
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.serviceFees(_pending!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final uncertain = FeeText.uncertain(e);
      setState(() {
        if (!uncertain) _pending = null;
        _error = x.error(e, uncertain: uncertain);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context), locked = _busy || _pending != null;
    final billed = widget.fee['roomBilledThrough'] as String?;
    final required = x.tr('Required', 'Bắt buộc');
    return AlertDialog(
      scrollable: true,
      title: Text(x.tr('Room price', 'Giá riêng cho phòng')),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.fee['name'] as String,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: WsSpace.sm),
            Wrap(
              spacing: WsSpace.sm,
              runSpacing: WsSpace.sm,
              children: [
                for (final (mode, label) in [
                  ('rate', x.tr('Room price', 'Giá riêng')),
                  if (widget.fee['basis'] != 'quantity')
                    ('off', x.tr('Do not charge', 'Không thu')),
                  ('inherit', x.tr('Default', 'Giá chung')),
                ])
                  ChoiceChip(
                    key: ValueKey('room-rate-mode-$mode'),
                    label: Text(label),
                    selected: _mode == mode,
                    onSelected: locked
                        ? null
                        : (_) => setState(() => _mode = mode),
                  ),
              ],
            ),
            const SizedBox(height: WsSpace.md),
            if (billed != null)
              WsNotice(
                x.tr(
                  'Invoices cover days before $billed here.',
                  'Phòng này đã lập hóa đơn cho các ngày trước $billed.',
                ),
                tone: WsTone.info,
              ),
            TextFormField(
              key: const ValueKey('room-rate-date'),
              controller: _date,
              enabled: !locked,
              decoration: InputDecoration(
                labelText: x.tr('From (YYYY-MM-DD)', 'Áp dụng từ (YYYY-MM-DD)'),
              ),
              validator: (v) {
                final d = (v ?? '').trim();
                if (!feeDate(d))
                  return x.tr('Enter a valid date.', 'Nhập ngày hợp lệ.');
                if (billed != null && d.compareTo(billed) < 0)
                  return x.tr(
                    'Choose $billed or later.',
                    'Chọn từ $billed trở đi.',
                  );
                return null;
              },
            ),
            if (_mode == 'rate') ...[
              const SizedBox(height: WsSpace.md),
              TextFormField(
                key: const ValueKey('room-rate-amount'),
                controller: _rate,
                enabled: !locked,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: appMoneyInput(_inputCurrency),
                decoration: InputDecoration(
                  labelText: x.tr(
                    'Price ($_inputCurrency)',
                    'Giá ($_inputCurrency)',
                  ),
                ),
                validator: (v) => _money.parse(_rate, widget.currency) == null
                    ? x.tr(
                        'Enter an amount of 0 or more.',
                        'Nhập số tiền từ 0 trở lên.',
                      )
                    : null,
              ),
            ],
            const SizedBox(height: WsSpace.md),
            TextFormField(
              key: const ValueKey('room-rate-reason'),
              controller: _reason,
              enabled: !locked,
              maxLength: 1000,
              decoration: InputDecoration(labelText: x.tr('Reason', 'Lý do')),
              validator: (v) => (v ?? '').trim().isEmpty ? required : null,
            ),
            if (_error != null) WsNotice(_error!),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(x.tr('Close', 'Đóng')),
        ),
        FilledButton(
          key: const ValueKey('room-rate-save'),
          onPressed: _busy ? null : _save,
          child: Text(
            _pending != null ? x.tr('Retry', 'Thử lại') : x.tr('Save', 'Lưu'),
          ),
        ),
      ],
    );
  }
}

/// Bill one fee for one lease and period (or one service date and quantity).
/// The server prices it; the review shows a line per person.
class ServiceInvoiceForm extends StatefulWidget {
  final TeamService service;
  final String organizationId, buildingId, roomId, roomNumber, currency;
  final String? today;
  final List<Map> tenants;
  final Map<String, dynamic> fee;
  final VoidCallback onDone, onCancel;
  const ServiceInvoiceForm({
    super.key,
    required this.service,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.roomNumber,
    required this.currency,
    required this.today,
    required this.tenants,
    required this.fee,
    required this.onDone,
    required this.onCancel,
  });
  @override
  State<ServiceInvoiceForm> createState() => _ServiceInvoiceFormState();
}

class _ServiceInvoiceFormState extends State<ServiceInvoiceForm> {
  late final _conversion = OrganizationMoney.shared.forOrganization(widget.organizationId);
  String get _invoiceCurrency => _conversion?.currency ?? widget.currency;
  final _form = GlobalKey<FormState>();
  final _start = TextEditingController(),
      _end = TextEditingController(),
      _due = TextEditingController(),
      _quantity = TextEditingController(),
      _reason = TextEditingController();
  String? _tenant, _error;
  Map<String, dynamic>? _quote, _payload, _pending;
  bool _busy = false;

  bool get _quantityBasis => widget.fee['basis'] == 'quantity';
  bool get _locked => _busy || _pending != null;

  @override
  void initState() {
    super.initState();
    final today = widget.today;
    if (today != null) {
      // Default: this calendar month (or today for a one-off service).
      final first = '${today.substring(0, 8)}01';
      final next = DateTime.utc(
        int.parse(today.substring(0, 4)),
        int.parse(today.substring(5, 7)) + 1,
        1,
      );
      _start.text = _quantityBasis ? today : first;
      _end.text = addDays(next.toIso8601String().substring(0, 10), -1);
      _due.text = today;
    }
    final current = widget.tenants.where((t) => t['current'] == true).toList();
    if (current.length == 1) _tenant = current.single['id'] as String;
    if (widget.tenants.length == 1)
      _tenant = widget.tenants.single['id'] as String;
  }

  @override
  void dispose() {
    for (final c in [_start, _end, _due, _quantity, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _quantityMilli(String input) {
    final v = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(v)) return null;
    final parts = v.split('.');
    final milli =
        int.parse(parts[0]) * 1000 +
        (parts.length > 1 ? int.parse(parts[1].padRight(3, '0')) : 0);
    return milli > 0 && milli <= 1000000000 ? milli : null;
  }

  Future<void> _review() async {
    final x = FeeText(context);
    if (_busy || !_form.currentState!.validate()) return;
    if (_tenant == null) {
      setState(
        () => _error = x.tr(
          'Choose the tenant to bill.',
          'Chọn khách cần lập hóa đơn.',
        ),
      );
      return;
    }
    final start = _start.text.trim();
    final payload = {
      'kind': 'service',
      'inputCurrency': _invoiceCurrency,
      if (_conversion?.snapshotId != null) 'ratesId': _conversion!.snapshotId,
      'organizationId': widget.organizationId,
      'buildingId': widget.buildingId,
      'tenantId': _tenant,
      'roomId': widget.roomId,
      'feeId': widget.fee['id'],
      'quantityMilli': _quantityBasis ? _quantityMilli(_quantity.text) : null,
      'startDate': start,
      // The server's period ends before this date; people enter the last day.
      'endDate': _quantityBasis
          ? addDays(start, 1)
          : addDays(_end.text.trim(), 1),
      'dueDate': _due.text.trim(),
      'reason': _reason.text.trim(),
      'feesMinor': {
        for (final k in [
          'internetFee',
          'cableTVFee',
          'hotWaterFee',
          'lateFee',
          'taxAmount',
        ])
          k: 0,
      },
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.invoices({
        'action': 'quote',
        ...payload,
      });
      if (!mounted) return;
      setState(() {
        _quote = Map<String, dynamic>.from(data['record'] as Map);
        _payload = payload;
      });
    } catch (e) {
      if (mounted) setState(() => _error = x.error(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final x = FeeText(context);
    if (_busy) return;
    _pending ??= {
      'action': 'create',
      ..._payload!,
      'quoteRevision': _quote!['quoteRevision'],
      'operationId': const Uuid().v4(),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.invoices(_pending!);
      if (mounted) widget.onDone();
    } catch (e) {
      if (!mounted) return;
      final uncertain = FeeText.uncertain(e);
      setState(() {
        if (!uncertain) {
          // A changed price or a new invoice elsewhere: review again.
          _pending = null;
          _quote = null;
        }
        _error = x.error(e, uncertain: uncertain);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _date(
    TextEditingController c,
    String label,
    Key key, {
    String? Function(String)? extra,
  }) => TextFormField(
    key: key,
    controller: c,
    enabled: !_locked && _quote == null,
    decoration: InputDecoration(labelText: label, hintText: 'YYYY-MM-DD'),
    validator: (v) {
      final d = (v ?? '').trim();
      if (!feeDate(d))
        return FeeText(context).tr('Enter a valid date.', 'Nhập ngày hợp lệ.');
      return extra?.call(d);
    },
  );

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context), fee = widget.fee, quote = _quote;
    final unit = fee['unitLabel'] as String? ?? '';
    final editing = quote == null;
    return WsPage(
      maxWidth: 760,
      children: [
        WsHeader(
          back: WsBack(
            label: x.tr('Service fees', 'Phí dịch vụ'),
            onPressed: _locked ? null : widget.onCancel,
          ),
          title: x.tr('Invoice: ${fee['name']}', 'Hóa đơn: ${fee['name']}'),
          help: widget.roomNumber.isEmpty
              ? null
              : x.tr('Room ${widget.roomNumber}', 'Phòng ${widget.roomNumber}'),
        ),
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WsSection(
                title: x.tr('Tenant', 'Khách'),
                children: [
                  if (widget.tenants.isEmpty)
                    WsNotice(
                      x.tr(
                        'No lease has lived in this room yet.',
                        'Chưa có hợp đồng nào ở phòng này.',
                      ),
                      tone: WsTone.info,
                    ),
                  // A list, not chips: long names wrap instead of overflowing.
                  for (final t in widget.tenants)
                    ListTile(
                      key: ValueKey('fee-invoice-tenant-${t['id']}'),
                      contentPadding: EdgeInsets.zero,
                      enabled: editing && !_locked,
                      selected: _tenant == t['id'],
                      leading: Icon(
                        _tenant == t['id']
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text('${t['fullName']}'),
                      subtitle: t['current'] == true
                          ? null
                          : Text(x.tr('Moved out', 'Đã trả phòng')),
                      onTap: () => setState(() => _tenant = t['id'] as String),
                    ),
                ],
              ),
              WsSection(
                title: _quantityBasis
                    ? x.tr('Service', 'Dịch vụ')
                    : x.tr('Period', 'Kỳ thu'),
                children: [
                  if (_quantityBasis)
                    WsFieldRow(
                      children: [
                        _date(
                          _start,
                          x.tr('Service date', 'Ngày sử dụng'),
                          const ValueKey('fee-invoice-start'),
                        ),
                        TextFormField(
                          key: const ValueKey('fee-invoice-quantity'),
                          controller: _quantity,
                          enabled: !_locked && editing,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: unit.isEmpty
                                ? x.tr('Quantity', 'Số lượng')
                                : x.tr('Quantity ($unit)', 'Số lượng ($unit)'),
                          ),
                          validator: (v) => _quantityMilli(v ?? '') == null
                              ? x.tr(
                                  'Enter a quantity above 0 (up to 3 decimals).',
                                  'Nhập số lượng lớn hơn 0 (tối đa 3 số lẻ).',
                                )
                              : null,
                        ),
                      ],
                    )
                  else
                    WsFieldRow(
                      children: [
                        _date(
                          _start,
                          x.tr('From', 'Từ ngày'),
                          const ValueKey('fee-invoice-start'),
                        ),
                        _date(
                          _end,
                          x.tr('To (inclusive)', 'Đến hết ngày'),
                          const ValueKey('fee-invoice-end'),
                          extra: (d) {
                            final s = _start.text.trim();
                            if (feeDate(s) && d.compareTo(s) < 0)
                              return x.tr(
                                'Must be on or after the start.',
                                'Phải từ ngày bắt đầu trở đi.',
                              );
                            return null;
                          },
                        ),
                      ],
                    ),
                  const SizedBox(height: WsSpace.md),
                  WsFieldRow(
                    children: [
                      _date(
                        _due,
                        x.tr('Due date', 'Hạn thanh toán'),
                        const ValueKey('fee-invoice-due'),
                      ),
                      TextFormField(
                        key: const ValueKey('fee-invoice-reason'),
                        controller: _reason,
                        enabled: !_locked && editing,
                        maxLength: 1000,
                        decoration: InputDecoration(
                          labelText: x.tr('Note', 'Ghi chú'),
                          hintText: x.tr(
                            'e.g. Rubbish, September',
                            'VD: Phí rác tháng 9',
                          ),
                        ),
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? x.tr('Required', 'Bắt buộc')
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
              if (quote != null)
                WsSection(
                  title: x.tr('Review', 'Xem lại'),
                  children: [
                    if (quote['startDate'] != null && !_quantityBasis)
                      WsInfo(
                        x.tr('Period', 'Kỳ'),
                        '${periodText(quote['startDate'] as String, quote['endDate'] as String)} (${x.tr('${quote['periodDays']} days', '${quote['periodDays']} ngày')})',
                      ),
                    if (quote['terms'] is Map) ...[
                      WsInfo(
                        x.tr('Price', 'Giá'),
                        x.rate(fee, quote['terms'] as Map, _invoiceCurrency),
                      ),
                      if (!_quantityBasis)
                        WsInfo(
                          x.tr('Partial periods', 'Ở không đủ kỳ'),
                          x.rule(
                            (quote['terms'] as Map)['rule'] as Map?,
                            prefix: false,
                          ),
                        ),
                    ],
                    const Divider(),
                    for (final line
                        in (quote['lines'] as List? ?? const []).cast<Map>())
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          x.line(line, _invoiceCurrency, unitLabel: unit),
                        ),
                      ),
                    const Divider(),
                    Text(
                      '${x.tr('Total', 'Tổng tiền')}: ${x.money(quote['totalMinor'] as num, _invoiceCurrency)}',
                      key: const ValueKey('fee-invoice-total'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Semantics(liveRegion: true, child: WsNotice(_error!)),
        WsActions(
          children: [
            if (quote == null) ...[
              TextButton(
                onPressed: _busy ? null : widget.onCancel,
                child: Text(x.tr('Cancel', 'Hủy')),
              ),
              FilledButton(
                key: const ValueKey('fee-invoice-review'),
                onPressed: _busy || widget.tenants.isEmpty ? null : _review,
                child: Text(x.tr('Review', 'Xem lại')),
              ),
            ] else ...[
              if (_pending == null)
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _quote = null),
                  child: Text(x.tr('Edit', 'Sửa')),
                ),
              FilledButton(
                key: const ValueKey('fee-invoice-create'),
                onPressed: _busy ? null : _create,
                child: Text(
                  _pending != null
                      ? x.tr('Retry', 'Thử lại')
                      : x.tr('Create', 'Tạo hóa đơn'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
