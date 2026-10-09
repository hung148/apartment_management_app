import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../services/organization_money.dart';
import '../../utils/money_conversion.dart';
import 'period_invoice_form.dart' show utilityName, signedMoney;
import 'service_fee_text.dart';
import 'ws_ui.dart';
import '../../utils/app_number.dart';

/// B6b: "Trả phòng và quyết toán". Ends the lease (when still open) and settles
/// the money in one step: final charges up to the move-out day, an optional
/// credit for rent paid ahead, the deposit applied to every unpaid invoice,
/// then a refund or the amount still owed. The server prices everything
/// (PERIOD_INVOICES.md, "B6b").
class MoveOutSettlementForm extends StatefulWidget {
  final TeamService service;
  final String organizationId, buildingId, tenantId;
  final VoidCallback onDone, onCancel;
  final String backLabel;
  const MoveOutSettlementForm({
    super.key,
    required this.service,
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.onDone,
    required this.onCancel,
    required this.backLabel,
  });
  @override
  State<MoveOutSettlementForm> createState() => _MoveOutSettlementFormState();
}

class _LineDraft {
  String kind = 'damage';
  bool percent = false;
  final label = TextEditingController();
  final amount = TextEditingController();
  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

class _MoveOutSettlementFormState extends State<MoveOutSettlementForm> {
  late final _money = MoneyForm(
    OrganizationMoney.shared.forOrganization(widget.organizationId),
  );
  String get _inputCurrency => _money.currency(_currency);
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController(), _reason = TextEditingController();
  final _lines = <_LineDraft>[];
  final _fees = <String>{}, _readings = <String>{};
  Map<String, dynamic>? _preview, _quote, _payload, _pending, _done;
  String? _error, _refundMethod, _refundAccount;
  bool _busy = true, _rent = true, _credit = false, _creditFees = false;
  int _generation = 0;

  bool get _locked => _busy || _pending != null;
  bool get _editing => _quote == null;
  String get _currency => _preview?['currency'] as String? ?? 'VND';

  @override
  void initState() {
    super.initState();
    _load(null);
  }

  @override
  void dispose() {
    _date.dispose();
    _reason.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _scope => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'tenantId': widget.tenantId,
  };

  String _readingKey(Map r) => '${r['roomId']}/${r['kind']}/${r['readingId']}';

  /// Loads what can be settled for [date] (null: today, or the recorded
  /// move-out day of a lease that has already ended).
  Future<void> _load(String? date) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _quote = null;
    });
    try {
      final data = await widget.service.leaseLifecycle({
        'action': 'settlementPreview',
        if (_money.conversion?.snapshotId != null)
          'ratesId': _money.conversion!.snapshotId,
        ..._scope,
        'effectiveDate': ?date,
      });
      if (!mounted || generation != _generation) return;
      final p = Map<String, dynamic>.from(data['record'] as Map);
      setState(() {
        _preview = p;
        _date.text = p['moveOutDate'] as String;
        _rent = p['rent'] != null;
        _fees
          ..clear()
          ..addAll([
            for (final f in (p['fees'] as List).cast<Map>()) f['id'] as String,
          ]);
        _readings
          ..clear()
          ..addAll([
            for (final r in (p['readings'] as List).cast<Map>()) _readingKey(r),
          ]);
        if ((p['credits'] as List).isEmpty) _credit = false;
        if ((p['feeCredits'] as List? ?? const []).isEmpty) _creditFees = false;
      });
    } catch (e) {
      if (mounted && generation == _generation)
        setState(() => _error = _message(FeeText(context), e));
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
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
      } else {
        final text = l.amount.text.trim();
        final negative = l.kind == 'other' && text.startsWith('-');
        final v = _money.parseText(
          negative ? text.substring(1) : text,
          _currency,
        );
        if (v == null || v == 0)
          return x.tr(
            'Enter an amount above 0 for each line.',
            'Nhập số tiền lớn hơn 0 cho mỗi dòng.',
          );
      }
    }
    return null;
  }

  Map<String, dynamic> _choice() => {
    'inputCurrency': _currency,
    'effectiveDate': _date.text.trim(),
    'includeRent': _rent && _preview!['rent'] != null,
    'serviceFeeIds': [
      for (final f in (_preview!['fees'] as List).cast<Map>())
        if (_fees.contains(f['id'])) f['id'],
    ],
    'readings': [
      for (final r in (_preview!['readings'] as List).cast<Map>())
        if (_readings.contains(_readingKey(r)))
          {
            'roomId': r['roomId'],
            'kind': r['kind'],
            'readingId': r['readingId'],
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
    'creditRent': _credit,
    'creditFees': _creditFees,
    'refundMethod': _refundMethod,
    'refundAccountId': _refundMethod == 'bankTransfer' ? _refundAccount : null,
    'dueDate': _preview!['today'],
    'reason': _reason.text.trim(),
  };

  Future<void> _review() async {
    final x = FeeText(context);
    if (_busy || !_form.currentState!.validate()) return;
    final linesError = _linesError(x);
    if (linesError != null) {
      setState(() => _error = linesError);
      return;
    }
    final payload = _choice();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.service.leaseLifecycle({
        'action': 'settlementQuote',
        if (_money.conversion?.snapshotId != null)
          'ratesId': _money.conversion!.snapshotId,
        ..._scope,
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

  Future<void> _confirm() async {
    final x = FeeText(context);
    if (_busy) return;
    final refund = (_quote!['refundMinor'] as num) > 0;
    if (refund && _refundMethod == null) {
      setState(
        () => _error = x.tr(
          'Choose how the money is returned.',
          'Chọn cách trả lại tiền cho khách.',
        ),
      );
      return;
    }
    // The refund way is part of what was reviewed; re-quote if it changed.
    final payload = {
      ..._payload!,
      'refundMethod': _refundMethod,
      'refundAccountId': _refundMethod == 'bankTransfer'
          ? _refundAccount
          : null,
    };
    if (_pending == null &&
        (payload['refundMethod'] != _payload!['refundMethod'] ||
            payload['refundAccountId'] != _payload!['refundAccountId'])) {
      setState(() => _busy = true);
      try {
        final data = await widget.service.leaseLifecycle({
          'action': 'settlementQuote',
          if (_money.conversion?.snapshotId != null)
            'ratesId': _money.conversion!.snapshotId,
          ..._scope,
          ...payload,
        });
        _quote = Map<String, dynamic>.from(data['record'] as Map);
        _payload = payload;
      } catch (e) {
        if (mounted) setState(() => _error = _message(x, e));
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    _pending ??= {
      'action': 'settle',
      if (_money.conversion?.snapshotId != null)
        'ratesId': _money.conversion!.snapshotId,
      ..._scope,
      ..._payload!,
      'operationId': const Uuid().v4(),
      'revision': _preview!['revision'],
      'timeZone': _preview!['timeZone'],
      'quoteRevision': _quote!['quoteRevision'],
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.service.leaseLifecycle(_pending!);
      if (mounted) setState(() => _done = Map<String, dynamic>.from(result));
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
    'settlement_currency_changed',
    'settlement_rates_required',
    'currency_rates_required',
    'settlement_original_rates_required',
    'lease_handle_roommates_first',
    'lease_actual_date_required',
    'invoice_backdate_owner_required',
    'settlement_exists',
    'settlement_keep_exceeds_deposit',
    'settlement_total_negative',
    'settlement_lines_need_price_authority',
    'settlement_refund_needs_permission',
    'settlement_refund_method_required',
    'settlement_changed',
    'settlement_item_unavailable',
    'settlement_discount_needs_rent',
    'settlement_date_fixed',
    'settlement_lease_not_open',
    'utility_already_billed',
    'utility_tenant_boundary_required',
    'utility_reading_reversed',
  ];

  String _message(FeeText x, Object e, {bool uncertain = false}) =>
      _reasonText(x, serverReason(e, _keys)) ??
      x.error(e, uncertain: uncertain);

  /// What a server reason key means for the person, or null if unknown.
  String? _reasonText(FeeText x, String key) {
    switch (key) {
      case 'settlement_currency_changed':
        return x.tr('The currency changed. Reopen the settlement and review it again.', 'Tiền tệ đã thay đổi. Mở lại quyết toán và kiểm tra lại.');
      case 'settlement_rates_required':
      case 'currency_rates_required':
        return x.tr(
          'Exchange rates are needed to include invoices in other currencies. Refresh currency rates in Account, then reopen this settlement.',
          'Cần tỷ giá để tính các hóa đơn khác tiền tệ. Làm mới tỷ giá trong Tài khoản rồi mở lại quyết toán.',
        );
      case 'settlement_original_rates_required':
        return x.tr(
          'A prepaid invoice is missing its original exchange rate. Review that invoice before settling; it has not been omitted.',
          'Hóa đơn trả trước thiếu tỷ giá gốc. Kiểm tra hóa đơn đó trước khi quyết toán; hóa đơn không bị bỏ qua.',
        );
      case 'lease_handle_roommates_first':
        return x.tr(
          'Move out the people living with this tenant first.',
          'Cho người ở cùng trả phòng trước.',
        );
      case 'lease_actual_date_required':
        return x.tr(
          'The move-out day must be after the move-in day and not in the future.',
          'Ngày trả phòng phải sau ngày vào ở và không ở tương lai.',
        );
      case 'invoice_backdate_owner_required':
        return x.tr(
          'Dates before today need the "Enter past dates" permission.',
          'Ngày trước hôm nay cần quyền "Nhập ngày trong quá khứ".',
        );
      case 'settlement_exists':
        return x.tr(
          'This lease is already settled.',
          'Hợp đồng này đã quyết toán.',
        );
      case 'settlement_keep_exceeds_deposit':
        return x.tr(
          'The deposit kept cannot be more than the deposit.',
          'Số tiền giữ cọc không được lớn hơn tiền cọc.',
        );
      case 'settlement_total_negative':
        return x.tr(
          'The final charges cannot be below 0. Check the minus lines.',
          'Tổng thu thêm không được âm. Kiểm tra các dòng trừ.',
        );
      case 'settlement_lines_need_price_authority':
        return x.tr(
          'Extra lines and rent credit need permission to change prices.',
          'Dòng khác và hoàn tiền thuê cần quyền điều chỉnh giá.',
        );
      case 'settlement_refund_needs_permission':
        return x.tr(
          'Giving back rent already paid needs refund permission.',
          'Hoàn lại tiền thuê đã thu cần quyền hoàn tiền.',
        );
      case 'settlement_refund_method_required':
        return x.tr(
          'Choose how the money is returned.',
          'Chọn cách trả lại tiền cho khách.',
        );
      case 'settlement_changed':
        return x.tr(
          'Something changed meanwhile. Review again.',
          'Dữ liệu vừa thay đổi. Hãy xem lại.',
        );
      case 'settlement_item_unavailable':
        return x.tr(
          'An item is no longer available. Reload.',
          'Một khoản không còn. Hãy tải lại.',
        );
      case 'settlement_discount_needs_rent':
        return x.tr(
          'A percent discount needs the rent on this settlement.',
          'Giảm theo % cần có tiền thuê.',
        );
      case 'settlement_date_fixed':
      case 'settlement_lease_not_open':
        return x.tr(
          'The lease changed. Reload.',
          'Hợp đồng đã thay đổi. Hãy tải lại.',
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
    }
    return null;
  }

  String _kindLabel(FeeText x, String kind) => switch (kind) {
    'late' => x.tr('Late fee', 'Phí trễ hạn'),
    'discount' => x.tr('Discount', 'Giảm giá'),
    'damage' => x.tr('Damage', 'Hư hỏng'),
    'keepDeposit' => x.tr('Keep deposit', 'Giữ cọc'),
    _ => x.tr('Other', 'Khác'),
  };

  String _invoiceName(FeeText x, Map i) {
    final what = switch (i['kind']) {
      'period' => x.tr('Period invoice', 'Hóa đơn kỳ'),
      'tenantRent' => x.tr('Rent', 'Tiền thuê'),
      'service' => x.tr('Service fee', 'Phí dịch vụ'),
      'utility' => x.tr('Electricity / water', 'Điện nước'),
      'charge' => x.tr('Other charge', 'Khoản thu khác'),
      _ => x.tr('Invoice', 'Hóa đơn'),
    };
    final s = i['startDate'] as String?, e = i['endDate'] as String?;
    return s == null || e == null
        ? what
        : '$what ${i['kind'] == 'utility' ? '$s – $e' : periodText(s, e)}';
  }

  /// One line of the final charges: label and signed amount.
  (String, num) _line(FeeText x, Map l) {
    switch (l['type']) {
      case 'rent':
        return (
          '${x.tr('Rent', 'Tiền thuê')} ${periodText(l['startDate'] as String, l['endDate'] as String)} (${x.tr('${l['days']} days', '${l['days']} ngày')})',
          l['amountMinor'] as num,
        );
      case 'service':
        return (
          '${l['feeName']} ${periodText(l['startDate'] as String, l['endDate'] as String)}',
          l['amountMinor'] as num,
        );
      case 'utility':
        return (
          '${utilityName(x, l['kind'] as String)} ${l['startDate']} – ${l['endDate']}',
          l['amountMinor'] as num,
        );
      default:
        return (
          '${_kindLabel(x, l['kind'] as String)}: ${l['label']}${l['percent'] != null ? ' (${l['percent']}%)' : ''}',
          l['amountMinor'] as num,
        );
    }
  }

  Widget _row(String label, String amount, {TextStyle? style, Key? key}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: WsSpace.xs),
        // Wrap: on narrow screens the amount moves under the label; never cut.
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: WsSpace.md,
          children: [
            Text(label, style: style),
            Text(amount, key: key, style: style),
          ],
        ),
      );

  Widget _check(
    Key key,
    bool value,
    String title,
    String? subtitle,
    ValueChanged<bool> onChanged,
  ) => CheckboxListTile(
    key: key,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    value: value,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    onChanged: _locked || !_editing
        ? null
        : (v) => setState(() => onChanged(v ?? false)),
  );

  @override
  Widget build(BuildContext context) {
    final x = FeeText(context), p = _preview, quote = _quote, done = _done;
    String money(num v) => x.money(v, _currency);
    final open = p?['open'] == true;
    final title = open || p == null
        ? x.tr('Move out and settle', 'Trả phòng và quyết toán')
        : x.tr('Move-out settlement', 'Quyết toán trả phòng');
    if (done != null) {
      final refund = done['refundMinor'] as num,
          owed = done['owedMinor'] as num;
      return WsPage(
        maxWidth: 760,
        children: [
          WsHeader(
            back: WsBack(label: widget.backLabel, onPressed: widget.onDone),
            title: title,
          ),
          WsNotice(
            refund > 0
                ? x.tr(
                    'Settled. Return ${money(refund)} to the tenant.',
                    'Đã quyết toán. Trả lại khách ${money(refund)}.',
                  )
                : owed > 0
                ? x.tr(
                    'Settled. The tenant still owes ${money(owed)}; it stays on the invoices.',
                    'Đã quyết toán. Khách còn nợ ${money(owed)}, vẫn nằm trên các hóa đơn.',
                  )
                : x.tr(
                    'Settled. Nothing is owed either way.',
                    'Đã quyết toán. Hai bên không còn nợ nhau.',
                  ),
            key: const ValueKey('settlement-done'),
            tone: WsTone.good,
          ),
          WsActions(
            children: [
              FilledButton(
                key: const ValueKey('settlement-finish'),
                onPressed: widget.onDone,
                child: Text(x.tr('Done', 'Xong')),
              ),
            ],
          ),
        ],
      );
    }
    final fees = (p?['fees'] as List? ?? const []).cast<Map>();
    final readings = (p?['readings'] as List? ?? const []).cast<Map>();
    final credits = (p?['credits'] as List? ?? const []).cast<Map>();
    final feeCredits = (p?['feeCredits'] as List? ?? const []).cast<Map>();
    final unpaid = (p?['openInvoices'] as List? ?? const []).cast<Map>();
    final accounts = (p?['accounts'] as List? ?? const []).cast<Map>();
    final lastReading = (p?['lastReading'] as Map?) ?? const {};
    final canPrice = p?['canPrice'] == true;
    final moveOut = _date.text.trim();
    final staleMeters = [
      for (final kind in const ['electricity', 'water'])
        if (lastReading[kind] is String &&
            (lastReading[kind] as String).compareTo(moveOut) < 0)
          kind,
    ];
    final problem = p?['dateProblem'] as String?;
    return WsPage(
      maxWidth: 760,
      children: [
        WsHeader(
          back: WsBack(
            label: widget.backLabel,
            onPressed: _locked ? null : widget.onCancel,
          ),
          title: title,
          help: p == null
              ? null
              : '${p['tenantName']} · ${x.tr('deposit', 'tiền cọc')} ${money(p['depositMinor'] as num)}',
        ),
        if (p != null)
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WsSection(
                  title: x.tr('Move-out day', 'Ngày trả phòng'),
                  children: [
                    TextFormField(
                      key: const ValueKey('settlement-date'),
                      controller: _date,
                      enabled: !_locked && _editing && p['dateFixed'] != true,
                      decoration: InputDecoration(
                        labelText: x.tr(
                          'Move-out day (not charged)',
                          'Ngày trả phòng (không tính tiền)',
                        ),
                        hintText: 'YYYY-MM-DD',
                        helperText: p['dateFixed'] == true
                            ? x.tr(
                                'The lease already ended on this day.',
                                'Hợp đồng đã kết thúc ngày này.',
                              )
                            : null,
                      ),
                      validator: (v) => feeDate((v ?? '').trim())
                          ? null
                          : x.tr('Enter a valid date.', 'Nhập ngày hợp lệ.'),
                      onFieldSubmitted: (v) {
                        if (feeDate(v.trim()) && v.trim() != p['moveOutDate'])
                          _load(v.trim());
                      },
                    ),
                    if (p['dateFixed'] != true &&
                        moveOut != p['moveOutDate'] &&
                        feeDate(moveOut))
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton(
                          key: const ValueKey('settlement-date-apply'),
                          onPressed: _locked ? null : () => _load(moveOut),
                          child: Text(x.tr('Recalculate', 'Tính lại')),
                        ),
                      ),
                    if (problem == 'lease_handle_roommates_first') ...[
                      const SizedBox(height: WsSpace.sm),
                      WsNotice(
                        '${x.tr('Move out the people living with this tenant first:', 'Cho người ở cùng trả phòng trước:')} ${(p['roommates'] as List).map((r) => r['fullName']).join(', ')}',
                        key: const ValueKey('settlement-roommates'),
                        tone: WsTone.warning,
                      ),
                    ] else if (problem != null) ...[
                      const SizedBox(height: WsSpace.sm),
                      WsNotice(
                        _reasonText(x, problem) ?? problem,
                        tone: WsTone.warning,
                      ),
                    ],
                  ],
                ),
                if (unpaid.isNotEmpty)
                  WsSection(
                    title: x.tr('Unpaid invoices', 'Hóa đơn chưa thu đủ'),
                    children: [
                      for (final i in unpaid)
                        _row(
                          _invoiceName(x, i),
                          money(i['balanceMinor'] as num),
                        ),
                      Text(
                        x.tr(
                          'The deposit pays these first.',
                          'Tiền cọc trừ vào các hóa đơn này trước.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                WsSection(
                  title: x.tr(
                    'Charge up to the move-out day',
                    'Thu thêm đến ngày trả phòng',
                  ),
                  children: [
                    if (p['rent'] != null)
                      _check(
                        const ValueKey('settlement-rent'),
                        _rent,
                        '${x.tr('Rent', 'Tiền thuê')} ${periodText((p['rent'] as Map)['startDate'] as String, (p['rent'] as Map)['endDate'] as String)}',
                        '${x.tr('${(p['rent'] as Map)['days']} days', '${(p['rent'] as Map)['days']} ngày')} · ${money((p['rent'] as Map)['amountMinor'] as num)}',
                        (v) => _rent = v,
                      ),
                    for (final f in fees)
                      _check(
                        ValueKey('settlement-fee-${f['id']}'),
                        _fees.contains(f['id']),
                        '${f['name']}',
                        '${x.basis(f['basis'] as String)} · ${periodText(f['startDate'] as String, moveOut)}',
                        (v) => v
                            ? _fees.add(f['id'] as String)
                            : _fees.remove(f['id']),
                      ),
                    for (final r in readings)
                      _check(
                        ValueKey('settlement-reading-${r['readingId']}'),
                        _readings.contains(_readingKey(r)),
                        '${utilityName(x, r['kind'] as String)} ${r['startDate']} – ${r['date']}',
                        '${x.quantity(r['usageMilli'] as int)} ${r['kind'] == 'electricity' ? 'kWh' : 'm³'} · ${money(r['amountMinor'] as num)}',
                        (v) => v
                            ? _readings.add(_readingKey(r))
                            : _readings.remove(_readingKey(r)),
                      ),
                    if (p['rent'] == null && fees.isEmpty && readings.isEmpty)
                      Text(
                        x.tr(
                          'Nothing left to bill up to this day.',
                          'Không còn khoản nào chưa thu đến ngày này.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    for (final kind in staleMeters) ...[
                      const SizedBox(height: WsSpace.sm),
                      WsNotice(
                        x.tr(
                          'The last ${kind == 'electricity' ? 'electricity' : 'water'} reading is from ${lastReading[kind]}. Record the reading of the move-out day first if usage should be billed.',
                          'Chỉ số ${kind == 'electricity' ? 'điện' : 'nước'} cuối ghi ngày ${lastReading[kind]}. Hãy ghi chỉ số ngày trả phòng trước nếu cần thu tiền dùng.',
                        ),
                        key: ValueKey('settlement-meter-$kind'),
                        tone: WsTone.info,
                      ),
                    ],
                  ],
                ),
                if (credits.isNotEmpty || feeCredits.isNotEmpty)
                  WsSection(
                    title: x.tr('Paid ahead', 'Tiền trả trước'),
                    children: [
                      if (credits.isNotEmpty)
                        _check(
                          const ValueKey('settlement-credit'),
                          _credit,
                          x.tr(
                            'Give back the rent for days not lived',
                            'Hoàn tiền thuê những ngày chưa ở',
                          ),
                          [
                            for (final c in credits)
                              '${periodText(c['startDate'] as String, c['endDate'] as String)} · ${money(c['creditMinor'] as num)}',
                          ].join('\n'),
                          (v) => _credit = v,
                        ),
                      // Each fee priced again with its own short-stay rule; a
                      // fee whose rule keeps the full charge is not listed.
                      if (feeCredits.isNotEmpty)
                        _check(
                          const ValueKey('settlement-credit-fees'),
                          _creditFees,
                          x.tr(
                            'Give back service fees for days not lived',
                            'Hoàn phí dịch vụ những ngày chưa ở',
                          ),
                          [
                            for (final c in feeCredits)
                              '${c['feeName']} ${periodText(c['startDate'] as String, c['endDate'] as String)} · ${money(c['creditMinor'] as num)}',
                          ].join('\n'),
                          (v) => _creditFees = v,
                        ),
                      if (!canPrice)
                        Text(
                          x.tr(
                            'Needs permission to change prices.',
                            'Cần quyền điều chỉnh giá.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                WsSection(
                  title: x.tr('Other lines', 'Dòng khác'),
                  trailing: canPrice && _editing && _lines.length < 20
                      ? TextButton.icon(
                          key: const ValueKey('settlement-add-line'),
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
                          'Damage, late fee, keeping part of the deposit, or anything else.',
                          'Hư hỏng, phí trễ hạn, giữ một phần cọc hoặc khoản khác.',
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
                            'damage',
                            'late',
                            'keepDeposit',
                            'discount',
                            'other',
                          ])
                            ChoiceChip(
                              key: ValueKey('settlement-line-$i-$kind'),
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
                            key: ValueKey('settlement-line-$i-label'),
                            controller: _lines[i].label,
                            enabled: !_locked && _editing,
                            maxLength: 80,
                            decoration: InputDecoration(
                              labelText: _lines[i].kind == 'keepDeposit'
                                  ? x.tr('Reason', 'Lý do')
                                  : x.tr('Description', 'Mô tả'),
                              hintText: _lines[i].kind == 'keepDeposit'
                                  ? x.tr(
                                      'e.g. left before the contract end',
                                      'VD: phá hợp đồng',
                                    )
                                  : null,
                            ),
                          ),
                          TextFormField(
                            key: ValueKey('settlement-line-$i-amount'),
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
                              key: ValueKey('settlement-line-$i-vnd'),
                              label: Text(_inputCurrency),
                              selected: !_lines[i].percent,
                              onSelected: _locked || !_editing
                                  ? null
                                  : (_) => setState(
                                      () => _lines[i].percent = false,
                                    ),
                            ),
                            ChoiceChip(
                              key: ValueKey('settlement-line-$i-percent'),
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
                      key: const ValueKey('settlement-reason'),
                      controller: _reason,
                      enabled: !_locked && _editing,
                      maxLength: 1000,
                      decoration: InputDecoration(
                        labelText: x.tr('Note', 'Ghi chú'),
                        hintText: x.tr(
                          'e.g. Moved out, keys returned',
                          'VD: Đã trả phòng, nhận lại chìa khóa',
                        ),
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? x.tr('Required', 'Bắt buộc')
                          : null,
                    ),
                  ],
                ),
                if (quote != null) _reviewSection(x, quote, accounts),
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
                onPressed: _busy ? null : () => _load(null),
                child: Text(x.tr('Retry', 'Thử lại')),
              ),
            ),
        ],
        if (p != null)
          WsActions(
            children: [
              if (quote == null) ...[
                TextButton(
                  onPressed: _busy ? null : widget.onCancel,
                  child: Text(x.tr('Cancel', 'Hủy')),
                ),
                FilledButton(
                  key: const ValueKey('settlement-review'),
                  onPressed: _busy || problem != null ? null : _review,
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
                  key: const ValueKey('settlement-confirm'),
                  onPressed: _busy ? null : _confirm,
                  child: Text(
                    _pending != null
                        ? x.tr('Retry', 'Thử lại')
                        : x.tr('Confirm', 'Xác nhận'),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _reviewSection(FeeText x, Map quote, List<Map> accounts) {
    String money(num v) => x.money(v, _currency);
    final lines = (quote['lines'] as List).cast<Map>();
    final credits = (quote['credits'] as List).cast<Map>();
    final applications = (quote['applications'] as List).cast<Map>();
    final unpaid = {
      for (final i in (_preview!['openInvoices'] as List).cast<Map>())
        i['id']: i,
    };
    final refund = quote['refundMinor'] as num,
        owed = quote['owedMinor'] as num;
    final strong = Theme.of(context).textTheme.titleMedium;
    return WsSection(
      title: x.tr('Review', 'Xem lại'),
      children: [
        if (lines.isNotEmpty) ...[
          Text(
            x.tr('Final charges', 'Thu thêm'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          for (final l in lines)
            Builder(
              builder: (context) {
                final (label, amount) = _line(x, l);
                return _row(label, signedMoney(x, amount, _currency));
              },
            ),
          _row(
            x.tr('Final invoice', 'Hóa đơn cuối'),
            money(quote['finalMinor'] as num),
          ),
          const Divider(),
        ],
        // Read top to bottom as the tenant's money: deposit, plus rent paid
        // ahead coming back, minus what it pays; the last line is the result.
        _row(x.tr('Deposit', 'Tiền cọc'), money(quote['depositMinor'] as num)),
        for (final c in credits)
          _row(
            c['kind'] == 'fee'
                ? '${x.tr('Fee credit', 'Hoàn phí')} ${c['feeName']} ${periodText(c['startDate'] as String, c['endDate'] as String)}'
                : '${x.tr('Rent credit', 'Hoàn tiền thuê')} ${periodText(c['startDate'] as String, c['endDate'] as String)}',
            '+${money(c['creditMinor'] as num)}',
          ),
        for (final a in applications)
          _row(
            a['invoiceId'] == 'final'
                ? x.tr(
                    'Deposit pays the final invoice',
                    'Cọc trừ vào hóa đơn cuối',
                  )
                : '${x.tr('Deposit pays', 'Cọc trừ vào')} ${unpaid[a['invoiceId']] == null ? x.tr('an invoice', 'hóa đơn') : _invoiceName(x, unpaid[a['invoiceId']]!)}',
            signedMoney(x, -(a['amountMinor'] as num), _currency),
          ),
        const Divider(),
        if (refund > 0)
          _row(
            x.tr('Return to the tenant', 'Trả lại khách'),
            money(refund),
            style: strong,
            key: const ValueKey('settlement-refund'),
          )
        else if (owed > 0)
          _row(
            x.tr('Tenant still owes', 'Khách còn nợ'),
            money(owed),
            style: strong,
            key: const ValueKey('settlement-owed'),
          )
        else
          _row(
            x.tr('Nothing owed either way', 'Hai bên không còn nợ'),
            money(0),
            style: strong,
            key: const ValueKey('settlement-even'),
          ),
        if (refund > 0) ...[
          const SizedBox(height: WsSpace.md),
          Text(
            x.tr('How is it returned?', 'Trả lại bằng cách nào?'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: WsSpace.sm),
          Wrap(
            spacing: WsSpace.sm,
            runSpacing: WsSpace.sm,
            children: [
              ChoiceChip(
                key: const ValueKey('settlement-refund-cash'),
                label: Text(x.tr('Cash', 'Tiền mặt')),
                selected: _refundMethod == 'cash',
                onSelected: _locked
                    ? null
                    : (_) => setState(() {
                        _refundMethod = 'cash';
                        _error = null;
                      }),
              ),
              ChoiceChip(
                key: const ValueKey('settlement-refund-bank'),
                label: Text(x.tr('Bank transfer', 'Chuyển khoản')),
                selected: _refundMethod == 'bankTransfer',
                onSelected: _locked
                    ? null
                    : (_) => setState(() {
                        _refundMethod = 'bankTransfer';
                        _error = null;
                      }),
              ),
            ],
          ),
          if (_refundMethod == 'bankTransfer' && accounts.isNotEmpty) ...[
            const SizedBox(height: WsSpace.sm),
            Wrap(
              spacing: WsSpace.sm,
              runSpacing: WsSpace.sm,
              children: [
                for (final a in accounts)
                  ChoiceChip(
                    key: ValueKey('settlement-account-${a['id']}'),
                    label: Text('${a['label']}'),
                    selected: _refundAccount == a['id'],
                    onSelected: _locked
                        ? null
                        : (_) => setState(
                            () => _refundAccount = a['id'] as String,
                          ),
                  ),
              ],
            ),
          ],
        ],
        if (owed > 0) ...[
          const SizedBox(height: WsSpace.sm),
          Text(
            x.tr(
              'What is still owed stays on the invoices to collect later.',
              'Số còn nợ vẫn nằm trên các hóa đơn để thu sau.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        if (_preview!['open'] == true) ...[
          const SizedBox(height: WsSpace.sm),
          Text(
            x.tr(
              'Confirming also ends the lease on ${quote['moveOutDate']}. This cannot be undone.',
              'Xác nhận cũng kết thúc hợp đồng ngày ${quote['moveOutDate']}. Không thể hoàn tác.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ] else ...[
          const SizedBox(height: WsSpace.sm),
          Text(
            x.tr('This cannot be undone.', 'Không thể hoàn tác.'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
