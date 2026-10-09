import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../services/organization_money.dart';
import '../../utils/money_conversion.dart';
import 'service_fee_text.dart';
import 'ws_ui.dart';
import '../../utils/app_number.dart';

/// B6: one invoice for a lease payment period — rent and service fees for the
/// period, meter readings not billed yet, and manual lines (late fee,
/// discount, damage, other). The server prices everything (PERIOD_INVOICES.md).
class PeriodInvoiceForm extends StatefulWidget {
  final TeamService service;
  final String organizationId, buildingId;

  /// Null: choose the lease first.
  final String? tenantId;
  final VoidCallback onDone, onCancel;
  final String backLabel;
  const PeriodInvoiceForm({
    super.key,
    required this.service,
    required this.organizationId,
    required this.buildingId,
    this.tenantId,
    required this.onDone,
    required this.onCancel,
    required this.backLabel,
  });
  @override
  State<PeriodInvoiceForm> createState() => _PeriodInvoiceFormState();
}

class _LineDraft {
  String kind = 'late';
  bool percent = false;
  final label = TextEditingController();
  final amount = TextEditingController();
  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

class _PeriodInvoiceFormState extends State<PeriodInvoiceForm> {
  late final _money = MoneyForm(OrganizationMoney.shared.forOrganization(widget.organizationId));
  String get _inputCurrency => _money.currency(_currency);
  final _form = GlobalKey<FormState>();
  final _start = TextEditingController(),
      _end = TextEditingController(),
      _due = TextEditingController(),
      _reason = TextEditingController();
  final _lines = <_LineDraft>[];
  List<Map> _tenants = const [];
  String? _tenant, _error;
  Map<String, dynamic>? _preview, _quote, _payload, _pending;
  bool _busy = true, _rent = true;
  final _fees = <String>{}, _readings = <String>{};
  // 2026-10-04: the lease's surcharges; the amount can change for this period.
  final _charges = <String, TextEditingController>{};
  final _chargeOn = <String>{};
  int _generation = 0;

  bool get _locked => _busy || _pending != null;
  bool get _editing => _quote == null;
  String get _currency => _preview?['currency'] as String? ?? 'VND';

  @override
  void initState() {
    super.initState();
    _tenant = widget.tenantId;
    _tenant == null ? _loadTenants() : _loadPreview();
  }

  @override
  void dispose() {
    for (final c in [_start, _end, _due, _reason]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.dispose();
    }
    for (final c in _charges.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _scope => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
  };

  Future<void> _loadTenants() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.invoices({
        'action': 'tenants',
        ..._scope,
      });
      if (!mounted || generation != _generation) return;
      setState(() => _tenants = (data['records'] as List).cast<Map>());
    } catch (e) {
      if (mounted && generation == _generation)
        setState(() => _error = FeeText(context).error(e));
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _loadPreview() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _preview = null;
      _quote = null;
    });
    try {
      final data = await widget.service.invoices({
        'action': 'periodPreview',
        if (_money.conversion?.snapshotId != null)
          'ratesId': _money.conversion!.snapshotId,
        ..._scope,
        'tenantId': _tenant,
      });
      if (!mounted || generation != _generation) return;
      final p = Map<String, dynamic>.from(data['record'] as Map);
      final s = p['suggestion'] as Map?;
      setState(() {
        _preview = p;
        if (s != null) {
          _start.text = s['startDate'] as String;
          _end.text = addDays(s['endDate'] as String, -1);
          _due.text = s['dueDate'] as String;
        }
        // A fee already billed past the start stays unticked (B6 live check).
        _fees
          ..clear()
          ..addAll([
            for (final f in (p['fees'] as List).cast<Map>())
              if (s == null || _feeOpen(f, s['startDate'] as String))
                f['id'] as String,
          ]);
        _readings
          ..clear()
          ..addAll([
            for (final r in (p['readings'] as List).cast<Map>()) _readingKey(r),
          ]);
        for (final c in _charges.values) {
          c.dispose();
        }
        _charges.clear();
        _chargeOn.clear();
        for (final c in (p['surcharges'] as List? ?? const []).cast<Map>()) {
          final id = c['id'] as String, minor = c['amountMinor'] as int;
          _charges[id] = TextEditingController();
          _money.set(_charges[id]!, minor, _currencyOf(p));
          if (c['billed'] != true) _chargeOn.add(id);
        }
      });
    } catch (e) {
      if (mounted && generation == _generation)
        setState(() => _error = FeeText(context).error(e));
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  static String _currencyOf(Map p) => p['currency'] as String? ?? 'VND';
  List<Map> get _surcharges =>
      (_preview?['surcharges'] as List? ?? const []).cast<Map>();

  String _readingKey(Map r) => '${r['roomId']}/${r['kind']}/${r['readingId']}';

  /// Why the invoice has no electricity line, from the lease's latest reading.
  String _noElectricity(FeeText x, Map? last) {
    final date = last?['date'] as String?;
    return switch (last?['status']) {
      'invoiced' => x.tr(
        'Electricity: usage up to $date is already on an invoice. Record a new reading on the lease page to bill more.',
        'Tiền điện: đã lập hóa đơn đến chỉ số ngày $date. Ghi chỉ số mới trên trang hợp đồng để thu tiếp.',
      ),
      'noCharge' => x.tr(
        'Electricity: the reading of $date is the starting point (or has no price). Record the next reading on the lease page.',
        'Tiền điện: chỉ số ngày $date là mốc bắt đầu (hoặc chưa có giá). Ghi chỉ số tiếp theo trên trang hợp đồng.',
      ),
      _ => x.tr(
        'Electricity: no meter reading yet. Record one on the lease page (Electricity, Record reading).',
        'Tiền điện: chưa có chỉ số. Ghi chỉ số trên trang hợp đồng (Tiền điện, Ghi chỉ số).',
      ),
    };
  }

  /// Can this fee go on a period starting at [start]? Not if an invoice already
  /// covers it past that day (billedUntil is the day after the last billed day).
  bool _feeOpen(Map f, String start) {
    final until = f['billedUntil'] as String?;
    return until == null || !feeDate(start) || until.compareTo(start) <= 0;
  }

  String? _linesError(FeeText x) {
    for (final l in _lines) {
      if (l.label.text.trim().isEmpty)
        return x.tr('Each line needs a description.', 'Mỗi dòng cần mô tả.');
      if (l.kind == 'discount' && l.percent) {
        final p = int.tryParse(l.amount.text.trim());
        if (p == null || p < 1 || p > 100)
          return x.tr(
            'Enter a percent from 1 to 100.',
            'Nhập phần trăm từ 1 đến 100.',
          );
        if (!_rent)
          return x.tr(
            'A percent discount needs the rent on this invoice.',
            'Giảm theo % cần có tiền thuê trên hóa đơn.',
          );
      } else {
        final text = l.amount.text.trim();
        final negative = l.kind == 'other' && text.startsWith('-');
        final v = _money.parseText(negative ? text.substring(1) : text, _currency);
        if (v == null || v == 0)
          return x.tr(
            'Enter an amount above 0 for each line.',
            'Nhập số tiền lớn hơn 0 cho mỗi dòng.',
          );
      }
    }
    return null;
  }

  Future<void> _review() async {
    final x = FeeText(context);
    if (_busy || !_form.currentState!.validate()) return;
    for (final c in _surcharges) {
      if (!_chargeOn.contains(c['id'])) continue;
      final v = _money.parse(_charges[c['id']]!, _currency);
      if (v == null || v <= 0) {
        setState(
          () => _error = x.tr(
            'Enter an amount above 0 for each surcharge.',
            'Nhập số tiền lớn hơn 0 cho mỗi phụ thu.',
          ),
        );
        return;
      }
    }
    final linesError = _linesError(x);
    if (linesError != null) {
      setState(() => _error = linesError);
      return;
    }
    final readings = [
      for (final r in (_preview!['readings'] as List).cast<Map>())
        if (_readings.contains(_readingKey(r)))
          {
            'roomId': r['roomId'],
            'kind': r['kind'],
            'readingId': r['readingId'],
          },
    ];
    final payload = {
      if (_money.conversion?.snapshotId != null)
        'ratesId': _money.conversion!.snapshotId,
      'kind': 'period',
      'inputCurrency': _currency,
      ..._scope,
      'tenantId': _tenant,
      'startDate': _start.text.trim(),
      'endDate': addDays(_end.text.trim(), 1),
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
      'includeRent': _rent,
      'serviceFeeIds': [
        for (final f in (_preview!['fees'] as List).cast<Map>())
          if (_fees.contains(f['id']) && _feeOpen(f, _start.text.trim()))
            f['id'],
      ],
      'readings': readings,
      if (_surcharges.any((c) => _chargeOn.contains(c['id'])))
        'surcharges': [
          for (final c in _surcharges)
            if (_chargeOn.contains(c['id']))
              {
                'id': c['id'],
                'amountMinor': _money.parse(
                  _charges[c['id']]!,
                  _currency,
                ),
              },
        ],
      'lines': [
        for (final l in _lines)
          if (l.kind == 'discount' && l.percent)
            {
              'kind': 'discount',
              'label': l.label.text.trim(),
              'percent': int.parse(l.amount.text.trim()),
            }
          else
            {
              'kind': l.kind,
              'label': l.label.text.trim(),
              'amountMinor': () {
                final text = l.amount.text.trim();
                final negative = l.kind == 'other' && text.startsWith('-');
                final v = _money.parseText(
                  negative ? text.substring(1) : text,
                  _currency,
                )!;
                return negative ? -v : v;
              }(),
            },
      ],
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
      if (mounted) setState(() => _error = _message(x, e));
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
          _pending = null;
          _quote = null;
        }
        _error = _message(x, e, uncertain: uncertain);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _keys = [
    'period_empty',
    'period_total_not_positive',
    'period_discount_needs_rent',
    'period_quantity_fee',
    'period_lines_need_price_authority',
    'period_no_rent_days',
    'utility_already_billed',
    'utility_tenant_boundary_required',
    'utility_reading_reversed',
    'invoice_period_exists',
    'period_surcharge_billed',
    'period_surcharge_unknown',
  ];

  String _message(FeeText x, Object e, {bool uncertain = false}) {
    switch (serverReason(e, _keys)) {
      case 'period_empty':
        return x.tr(
          'Choose at least one thing to bill.',
          'Chọn ít nhất một khoản để thu.',
        );
      case 'period_total_not_positive':
        return x.tr(
          'The total must be above 0. Check the discount lines.',
          'Tổng tiền phải lớn hơn 0. Kiểm tra các dòng giảm giá.',
        );
      case 'period_discount_needs_rent':
        return x.tr(
          'A percent discount needs the rent on this invoice.',
          'Giảm theo % cần có tiền thuê trên hóa đơn.',
        );
      case 'period_lines_need_price_authority':
        return x.tr(
          'Adding lines needs permission to change prices.',
          'Thêm dòng cần quyền điều chỉnh giá.',
        );
      case 'period_no_rent_days':
        return x.tr(
          'The lease has no days in this period.',
          'Hợp đồng không có ngày nào trong kỳ này.',
        );
      case 'utility_already_billed':
        return x.tr(
          'A meter reading is already on another invoice. Reload.',
          'Một chỉ số đã có hóa đơn khác. Hãy tải lại.',
        );
      case 'utility_tenant_boundary_required':
        return x.tr(
          'A meter reading covers days outside this lease.',
          'Một chỉ số có ngày ngoài hợp đồng này.',
        );
      case 'utility_reading_reversed':
        return x.tr(
          'A meter reading was corrected. Reload.',
          'Một chỉ số đã được sửa. Hãy tải lại.',
        );
      case 'period_surcharge_billed':
        return x.tr(
          'A surcharge is already billed for this period (or once already). Untick it.',
          'Một khoản phụ thu đã có hóa đơn cho kỳ này (hoặc đã thu một lần). Hãy bỏ chọn.',
        );
      case 'period_surcharge_unknown':
        return x.tr(
          'The surcharges changed. Reload.',
          'Phụ thu đã thay đổi. Hãy tải lại.',
        );
      case 'invoice_period_exists':
        return x.tr(
          'Rent or a fee is already billed for some of these days.',
          'Tiền thuê hoặc một khoản phí đã có hóa đơn cho một phần những ngày này.',
        );
    }
    return x.error(e, uncertain: uncertain);
  }

  String _kindLabel(FeeText x, String kind) => switch (kind) {
    'late' => x.tr('Late fee', 'Phí trễ hạn'),
    'discount' => x.tr('Discount', 'Giảm giá'),
    'damage' => x.tr('Damage', 'Hư hỏng'),
    _ => x.tr('Other', 'Khác'),
  };

  String _utilityName(FeeText x, String kind) => utilityName(x, kind);
  String _unit(String kind) => utilityUnit(kind);
  (String, num) _quoteLine(FeeText x, Map l) => describePeriodLine(x, l);

  String _signed(FeeText x, num minor) => signedMoney(x, minor, _currency);

  Widget _date(
    TextEditingController c,
    String label,
    Key key, {
    String? Function(String)? extra,
  }) => TextFormField(
    key: key,
    controller: c,
    enabled: !_locked && _editing,
    onChanged: (_) => setState(() {}),
    decoration: InputDecoration(labelText: label, hintText: 'YYYY-MM-DD'),
    validator: (v) {
      final d = (v ?? '').trim();
      if (!feeDate(d))
        return FeeText(context).tr('Enter a valid date.', 'Nhập ngày hợp lệ.');
      return extra?.call(d);
    },
  );

  Widget _check(
    Key key,
    bool value,
    String title,
    String? subtitle,
    ValueChanged<bool> onChanged, {
    bool enabled = true,
  }) => CheckboxListTile(
    key: key,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    value: value,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    onChanged: _locked || !_editing || !enabled
        ? null
        : (v) => setState(() => onChanged(v ?? false)),
  );

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context), p = _preview, quote = _quote;
    final fees = (p?['fees'] as List? ?? const []).cast<Map>();
    final readings = (p?['readings'] as List? ?? const []).cast<Map>();
    final canPrice = p?['canPrice'] == true;
    return WsPage(
      maxWidth: 760,
      children: [
        WsHeader(
          back: WsBack(
            label: widget.backLabel,
            onPressed: _locked ? null : widget.onCancel,
          ),
          title: x.tr('Period invoice', 'Hóa đơn kỳ'),
          help: p == null
              ? x.tr(
                  'Rent and fees for the period, plus usage not billed yet.',
                  'Tiền thuê và phí của kỳ, cộng điện nước chưa thu.',
                )
              : '${p['tenantName']} · ${x.tr('every ${p['periodMonths']} months', 'mỗi ${p['periodMonths']} tháng')}${p['dueDay'] != null ? x.tr(', due day ${p['dueDay']}', ', hạn ngày ${p['dueDay']}') : ''}',
        ),
        if (widget.tenantId == null && p == null)
          WsSection(
            title: x.tr('Lease', 'Hợp đồng'),
            children: [
              if (!_busy && _tenants.isEmpty && _error == null)
                WsNotice(
                  x.tr(
                    'No leases in this property yet.',
                    'Tòa nhà chưa có hợp đồng.',
                  ),
                  tone: WsTone.info,
                ),
              for (final t in _tenants)
                ListTile(
                  key: ValueKey('period-tenant-${t['id']}'),
                  contentPadding: EdgeInsets.zero,
                  enabled: !_busy,
                  leading: const Icon(Icons.person_outline),
                  title: Text('${t['fullName']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _tenant = t['id'] as String;
                    _loadPreview();
                  },
                ),
            ],
          ),
        if (p != null && p['finished'] == true)
          WsNotice(
            x.tr(
              'This lease has no period left to bill.',
              'Hợp đồng không còn kỳ nào để thu.',
            ),
            tone: WsTone.info,
          ),
        if (p != null && p['finished'] != true)
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WsSection(
                  title: x.tr('Period', 'Kỳ thu'),
                  children: [
                    WsFieldRow(
                      children: [
                        _date(
                          _start,
                          x.tr('From', 'Từ ngày'),
                          const ValueKey('period-start'),
                        ),
                        _date(
                          _end,
                          x.tr('To (inclusive)', 'Đến hết ngày'),
                          const ValueKey('period-end'),
                          extra: (d) {
                            final s = _start.text.trim();
                            return feeDate(s) && d.compareTo(s) < 0
                                ? x.tr(
                                    'Must be on or after the start.',
                                    'Phải từ ngày bắt đầu trở đi.',
                                  )
                                : null;
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: WsSpace.md),
                    _date(
                      _due,
                      x.tr('Due date', 'Hạn thanh toán'),
                      const ValueKey('period-due'),
                    ),
                    // The period already started: dates before today need the
                    // "Enter past dates" permission (set by the owner in roles).
                    if (p['canBackdate'] != true &&
                        [_start.text.trim(), _due.text.trim()].any(
                          (d) => feeDate(d) && d.compareTo('${p['today']}') < 0,
                        )) ...[
                      const SizedBox(height: WsSpace.md),
                      WsNotice(
                        x.tr(
                          'This period starts before today. Ask the owner to give your role "Enter past dates" in Roles and permissions.',
                          'Kỳ này bắt đầu trước hôm nay. Nhờ chủ nhà cấp quyền "Nhập ngày trong quá khứ" cho vai trò của bạn trong Phân quyền.',
                        ),
                        key: const ValueKey('period-backdate-notice'),
                        tone: WsTone.warning,
                      ),
                    ],
                  ],
                ),
                WsSection(
                  title: x.tr('On this invoice', 'Các khoản thu'),
                  children: [
                    _check(
                      const ValueKey('period-rent'),
                      _rent,
                      x.tr('Rent', 'Tiền thuê'),
                      p['periodRentMinor'] != null
                          ? x.tr(
                              '${x.money(p['periodRentMinor'] as num, _currency)} for a whole period',
                              '${x.money(p['periodRentMinor'] as num, _currency)} cho một kỳ đủ',
                            )
                          : null,
                      (v) => _rent = v,
                    ),
                    for (final f in fees)
                      _check(
                        ValueKey('period-fee-${f['id']}'),
                        _fees.contains(f['id']) &&
                            _feeOpen(f, _start.text.trim()),
                        '${f['name']}',
                        f['billedUntil'] == null
                            ? x.basis(f['basis'] as String)
                            : '${x.basis(f['basis'] as String)} · ${x.tr('billed through ${addDays(f['billedUntil'] as String, -1)}', 'đã thu đến hết ${addDays(f['billedUntil'] as String, -1)}')}',
                        (v) => v
                            ? _fees.add(f['id'] as String)
                            : _fees.remove(f['id']),
                        enabled: _feeOpen(f, _start.text.trim()),
                      ),
                    for (final r in readings)
                      _check(
                        ValueKey('period-reading-${r['readingId']}'),
                        _readings.contains(_readingKey(r)),
                        '${_utilityName(x, r['kind'] as String)} ${r['startDate']} – ${r['date']}',
                        '${x.quantity(r['usageMilli'] as int)} ${_unit(r['kind'] as String)} · ${x.money(r['amountMinor'] as num, r['currency'] as String? ?? _currency)}',
                        (v) => v
                            ? _readings.add(_readingKey(r))
                            : _readings.remove(_readingKey(r)),
                      ),
                    // Surcharges (phụ thu): tick, and change this period's amount if needed.
                    for (final c in _surcharges) ...[
                      _check(
                        ValueKey('period-surcharge-${c['id']}'),
                        _chargeOn.contains(c['id']),
                        // Water (2026-10-04): its own name, per person per month.
                        c['kind'] == 'water'
                            ? '${c['label']}'
                            : '${x.tr('Surcharge', 'Phụ thu')}: ${c['label']}',
                        [
                          c['basis'] == 'person'
                              ? x.tr(
                                  'per person × ${c['count']}',
                                  'theo người × ${c['count']}',
                                )
                              : x.tr('per room', 'theo phòng'),
                          switch (c['frequency']) {
                            'once' => x.tr('once', 'một lần'),
                            'month' => x.tr(
                              'per month × months of the period',
                              'mỗi tháng × số tháng của kỳ',
                            ),
                            _ => x.tr('every period', 'mỗi kỳ'),
                          },
                          if (c['billed'] == true)
                            x.tr('already billed', 'đã thu'),
                        ].join(' · '),
                        (v) => v
                            ? _chargeOn.add(c['id'] as String)
                            : _chargeOn.remove(c['id']),
                        enabled: c['billed'] != true,
                      ),
                      if (_chargeOn.contains(c['id']))
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 48,
                            bottom: WsSpace.sm,
                          ),
                          child: TextFormField(
                            key: ValueKey('period-surcharge-${c['id']}-amount'),
                            controller: _charges[c['id']],
                            // Another amount than the lease's is a price change.
                            enabled: !_locked && _editing && canPrice,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: appMoneyInput(_inputCurrency),
                            decoration: InputDecoration(
                              labelText:
                                  c['frequency'] == 'month' &&
                                      c['basis'] != 'person'
                                  ? x.tr(
                                      'Per month ($_inputCurrency)',
                                      'Mỗi tháng ($_inputCurrency)',
                                    )
                                  : c['frequency'] == 'month'
                                  ? x.tr(
                                      'Per person per month ($_inputCurrency)',
                                      'Mỗi người mỗi tháng ($_inputCurrency)',
                                    )
                                  : c['basis'] == 'person'
                                  ? x.tr(
                                      'Amount per person ($_inputCurrency)',
                                      'Số tiền mỗi người ($_inputCurrency)',
                                    )
                                  : x.tr(
                                      'Amount ($_inputCurrency)',
                                      'Số tiền ($_inputCurrency)',
                                    ),
                            ),
                          ),
                        ),
                    ],
                    if (fees.isEmpty && readings.isEmpty && _surcharges.isEmpty)
                      Text(
                        x.tr(
                          'No service fees in force and no unbilled meter readings.',
                          'Không có phí dịch vụ đang áp dụng và không có chỉ số điện nước chưa thu.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    // No electricity line: say why (2026-10-04, Tom: "how does
                    // tiền điện get billed?"). Readings are recorded on the
                    // lease page and billed behind, on the next period invoice.
                    if (p != null &&
                        !readings.any((r) => r['kind'] == 'electricity') &&
                        (p['lastElectricity'] as Map?)?['status'] != 'unbilled')
                      Padding(
                        padding: const EdgeInsets.only(top: WsSpace.xs),
                        child: Text(
                          _noElectricity(x, p['lastElectricity'] as Map?),
                          key: const ValueKey('period-no-electricity'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
                WsSection(
                  title: x.tr('Other lines', 'Dòng khác'),
                  trailing: canPrice && _editing && _lines.length < 20
                      ? TextButton.icon(
                          key: const ValueKey('period-add-line'),
                          onPressed: _locked
                              ? null
                              : () => setState(() => _lines.add(_LineDraft())),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(x.tr('Add line', 'Thêm dòng')),
                        )
                      : null,
                  children: [
                    if (!canPrice)
                      Text(
                        x.tr(
                          'Adding lines needs permission to change prices.',
                          'Thêm dòng cần quyền điều chỉnh giá.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else if (_lines.isEmpty)
                      Text(
                        x.tr(
                          'Late fee, discount, damage or anything else.',
                          'Phí trễ hạn, giảm giá, hư hỏng hoặc khoản khác.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    for (var i = 0; i < _lines.length; i++) ...[
                      if (i > 0) const Divider(),
                      Wrap(
                        spacing: WsSpace.sm,
                        runSpacing: WsSpace.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final kind in const [
                            'late',
                            'discount',
                            'damage',
                            'other',
                          ])
                            ChoiceChip(
                              key: ValueKey('period-line-$i-$kind'),
                              label: Text(_kindLabel(x, kind)),
                              selected: _lines[i].kind == kind,
                              onSelected: _locked || !_editing
                                  ? null
                                  : (_) =>
                                        setState(() => _lines[i].kind = kind),
                            ),
                          IconButton(
                            tooltip: x.tr('Remove line', 'Bỏ dòng'),
                            onPressed: _locked || !_editing
                                ? null
                                : () => setState(
                                    () => _lines.removeAt(i).dispose(),
                                  ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: WsSpace.sm),
                      WsFieldRow(
                        children: [
                          TextFormField(
                            key: ValueKey('period-line-$i-label'),
                            controller: _lines[i].label,
                            enabled: !_locked && _editing,
                            maxLength: 80,
                            decoration: InputDecoration(
                              labelText: x.tr('Description', 'Mô tả'),
                            ),
                          ),
                          TextFormField(
                            key: ValueKey('period-line-$i-amount'),
                            controller: _lines[i].amount,
                            enabled: !_locked && _editing,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            inputFormatters: appMoneyInput(
                              _inputCurrency,
                              signed: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  _lines[i].kind == 'discount' &&
                                      _lines[i].percent
                                  ? x.tr(
                                      'Percent of rent',
                                      'Phần trăm tiền thuê',
                                    )
                                  : x.tr(
                                      'Amount ($_inputCurrency)',
                                      'Số tiền ($_inputCurrency)',
                                    ),
                              helperText: _lines[i].kind == 'other'
                                  ? x.tr(
                                      'Use - to subtract',
                                      'Dùng dấu - để trừ',
                                    )
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      if (_lines[i].kind == 'discount')
                        Wrap(
                          spacing: WsSpace.sm,
                          children: [
                            ChoiceChip(
                              key: ValueKey('period-line-$i-vnd'),
                              label: Text(_inputCurrency),
                              selected: !_lines[i].percent,
                              onSelected: _locked || !_editing
                                  ? null
                                  : (_) => setState(
                                      () => _lines[i].percent = false,
                                    ),
                            ),
                            ChoiceChip(
                              key: ValueKey('period-line-$i-percent'),
                              label: const Text('%'),
                              selected: _lines[i].percent,
                              onSelected: _locked || !_editing
                                  ? null
                                  : (_) => setState(
                                      () => _lines[i].percent = true,
                                    ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
                WsSection(
                  title: x.tr('Note', 'Ghi chú'),
                  children: [
                    TextFormField(
                      key: const ValueKey('period-reason'),
                      controller: _reason,
                      enabled: !_locked && _editing,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        labelText: x.tr('Note', 'Ghi chú'),
                        hintText: x.tr('e.g. Period 1', 'VD: Kỳ 1'),
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? x.tr('Required', 'Bắt buộc')
                          : null,
                    ),
                  ],
                ),
                if (quote != null)
                  WsSection(
                    title: x.tr('Review', 'Xem lại'),
                    children: [
                      for (final l
                          in (quote['lines'] as List? ?? const []).cast<Map>())
                        Builder(
                          builder: (context) {
                            final (label, amount) = _quoteLine(x, l);
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: WsSpace.xs,
                              ),
                              // Wrap: on narrow screens or large text the
                              // amount moves under the label instead of
                              // overflowing; amounts are never cut.
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                spacing: WsSpace.md,
                                children: [
                                  Text(label),
                                  Text(_signed(x, amount)),
                                ],
                              ),
                            );
                          },
                        ),
                      const Divider(),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: WsSpace.md,
                        children: [
                          Text(
                            x.tr('Total', 'Tổng tiền'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            x.money(quote['totalMinor'] as num, _currency),
                            key: const ValueKey('period-total'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) ...[
          Semantics(liveRegion: true, child: WsNotice(_error!)),
          if (p == null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : (_tenant == null ? _loadTenants : _loadPreview),
                child: Text(x.tr('Retry', 'Thử lại')),
              ),
            ),
        ],
        if (p != null && p['finished'] != true)
          WsActions(
            children: [
              if (quote == null) ...[
                TextButton(
                  onPressed: _busy ? null : widget.onCancel,
                  child: Text(x.tr('Cancel', 'Hủy')),
                ),
                FilledButton(
                  key: const ValueKey('period-review'),
                  onPressed: _busy ? null : _review,
                  child: Text(x.tr('Review', 'Xem lại')),
                ),
              ] else ...[
                if (_pending == null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _quote = null),
                    child: Text(x.tr('Edit', 'Sửa')),
                  ),
                FilledButton(
                  key: const ValueKey('period-create'),
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

String utilityName(FeeText x, String kind) =>
    kind == 'electricity' ? x.tr('Electricity', 'Điện') : x.tr('Water', 'Nước');
String utilityUnit(String kind) => kind == 'electricity' ? 'kWh' : 'm³';
String signedMoney(FeeText x, num minor, String currency) =>
    minor < 0 ? '−${x.money(-minor, currency)}' : x.money(minor, currency);

/// One line of a period invoice (review and invoice details): label + amount.
(String, num) describePeriodLine(FeeText x, Map l) {
  switch (l['type']) {
    case 'rent':
      final how = l['basis'] == 'period'
          ? x.tr('${l['months']} months', '${l['months']} tháng')
          : l['basis'] == 'days'
          ? x.tr('${l['days']} days', '${l['days']} ngày')
          : '';
      return (
        '${x.tr('Rent', 'Tiền thuê')} ${periodText(l['startDate'] as String, l['endDate'] as String)}${how.isEmpty ? '' : ' ($how)'}',
        l['amountMinor'] as num,
      );
    case 'service':
      final people = (l['people'] as List? ?? const []).length;
      return (
        '${l['feeName']}${people > 1 ? x.tr(' · $people people', ' · $people người') : ''}',
        l['amountMinor'] as num,
      );
    case 'surcharge':
      final count = (l['count'] as num?) ?? 1;
      // Per month (water): "× 3 months", or a part month as a fraction.
      final f = l['monthsFraction'] as List?;
      final months = f == null
          ? ''
          : f[1] == 1
          ? x.tr(' × ${f[0]} months', ' × ${f[0]} tháng')
          : x.tr(' × ${f[0]}/${f[1]} month', ' × ${f[0]}/${f[1]} tháng');
      final people = count > 1
          ? ' ($count ${x.tr('people', 'người')}$months)'
          : (months.isEmpty ? '' : ' (${months.trim()})');
      return (
        '${l['kind'] == 'water' ? '${l['label']}' : '${x.tr('Surcharge', 'Phụ thu')}: ${l['label']}'}$people',
        l['amountMinor'] as num,
      );
    case 'utility':
      return (
        '${utilityName(x, l['kind'] as String)} ${l['startDate']} – ${l['endDate']}: ${x.quantity(l['usageMilli'] as int)} ${utilityUnit(l['kind'] as String)}',
        l['amountMinor'] as num,
      );
    default:
      // Settlement (B6b) "keep deposit" lines say what they are.
      final keep = l['kind'] == 'keepDeposit'
          ? '${x.tr('Keep deposit', 'Giữ cọc')}: '
          : '';
      return (
        '$keep${l['label']}${l['percent'] != null ? ' (${l['percent']}%)' : ''}',
        l['amountMinor'] as num,
      );
  }
}
