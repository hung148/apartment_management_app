import 'workspace_page_scope.dart';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'utility_tariff_form.dart';
import 'utility_invoice_form.dart';
import 'ws_ui.dart';
import '../../utils/app_number.dart';

// Meter numbers use a dot for decimals; a comma only as a thousands mark
// ("1,200" is one thousand two hundred, never 1.2) (2026-10-05, Tom).
int? meterMilli(String input) {
  var value = input.trim();
  if (value.contains(',')) {
    if (!RegExp(r'^\d{1,3}(,\d{3})+(\.\d*)?$').hasMatch(value)) return null;
    value = value.replaceAll(',', '');
  }
  if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(value)) return null;
  final parts = value.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final result =
      whole * 1000 +
      int.parse(parts.length == 1 ? '0' : parts[1].padRight(3, '0'));
  return result <= 1000000000000 ? result : null;
}

class UtilityReadingsScreen extends StatefulWidget {
  final String organizationId, buildingId, roomId;
  final TeamService service;
  final VoidCallback onBack;
  const UtilityReadingsScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.service,
    required this.onBack,
  });
  @override
  State<UtilityReadingsScreen> createState() => _UtilityReadingsScreenState();
}

class _UtilityReadingsScreenState extends State<UtilityReadingsScreen> {
  final _date = TextEditingController(),
      _reading = TextEditingController(),
      _oldFinal = TextEditingController(),
      _newStart = TextEditingController(),
      _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  Map<String, dynamic>? _record, _pending, _invoiceReading;
  List<Map<String, dynamic>> _history = [];
  String _kind = 'electricity';
  String? _cursor;
  bool _loading = true, _saving = false, _reset = false;
  String? _error;
  // Where the message shows: 'top' (loading), 'form', 'tariff' or
  // 'reading:<id>' — next to the button that caused it.
  String _errorAt = 'top';
  int _generation = 0;
  String tr(String en, String vi) =>
      AppTranslations.of(context).locale.languageCode == 'vi' ? vi : en;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant UtilityReadingsScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.roomId != widget.roomId ||
        old.service != widget.service) {
      _pending = null;
      _invoiceReading = null;
      _saving = false;
      _reset = false;
      for (final controller in [
        _date,
        _reading,
        _oldFinal,
        _newStart,
        _reason,
      ]) {
        controller.clear();
      }
      _load();
    }
  }

  @override
  void dispose() {
    for (final c in [_date, _reading, _oldFinal, _newStart, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _scope => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'roomId': widget.roomId,
    'kind': _kind,
  };
  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _record = null;
        _history = [];
        _cursor = null;
      }
    });
    try {
      final data = await widget.service.utilityReadings({
        'action': 'read',
        ..._scope,
        if (more) 'cursor': _cursor,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = Map<String, dynamic>.from(data['record']);
        _history = [
          if (more) ..._history,
          ...(data['records'] as List).map((x) => Map<String, dynamic>.from(x)),
        ];
        _cursor = data['nextCursor'];
      });
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() {
          _error = 'load';
          _errorAt = 'top';
        });
    } finally {
      if (mounted && generation == _generation)
        setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || (_pending == null && !_form.currentState!.validate()))
      return;
    final request =
        _pending ??
        {
          'action': 'record',
          ..._scope,
          'operationId': const Uuid().v4(),
          'revision': _record!['revision'],
          'date': _date.text.trim(),
          'readingMilli': meterMilli(_reading.text),
          'reason': _reason.text.trim(),
          'oldFinalMilli': _reset ? meterMilli(_oldFinal.text) : null,
          'newStartMilli': _reset ? meterMilli(_newStart.text) : null,
        };
    await _submit(request, at: _pending != null ? _errorAt : 'form');
  }

  Future<void> _reverse(Map<String, dynamic> row) async {
    if (_saving) return;
    final readingId = row['id'] as String;
    // An invoiced reading cannot be corrected until its invoice is voided:
    // say so in the dialog instead of letting the server refuse it.
    final reason = await showDialog<String>(
      context: context,
      builder: (context) =>
          _UtilityCorrectionDialog(invoiced: row['invoiceId'] != null),
    );
    if (!mounted || reason == null) return;
    await _submit({
      'action': 'reverse',
      ..._scope,
      'operationId': const Uuid().v4(),
      'revision': _record!['revision'],
      'readingId': readingId,
      'reason': reason,
    }, at: 'reading:$readingId');
  }

  Future<void> _saveTariff(Map<String, dynamic> tariff) => _submit({
    'action': 'tariff',
    ..._scope,
    'operationId': const Uuid().v4(),
    'revision': _record!['revision'],
    'propertyRevision': _record!['propertyRevision'],
    ...tariff,
  }, at: 'tariff');
  Future<void> _submit(
    Map<String, dynamic> request, {
    required String at,
  }) async {
    if (_saving) return;
    final generation = _generation;
    setState(() {
      _saving = true;
      _pending = request;
      _error = null;
      _errorAt = at;
    });
    try {
      await widget.service.utilityReadings(request);
      if (!mounted || generation != _generation) return;
      setState(() {
        _pending = null;
        _reset = false;
        _saving = false;
      });
      for (final c in [_date, _reading, _oldFinal, _newStart, _reason]) {
        c.clear();
      }
      await _load();
    } on FirebaseFunctionsException catch (e) {
      if (mounted && generation == _generation)
        setState(() {
          final reason = serverReason(e, const [
            'utility_void_invoice_first',
            'utility_tariff_boundary_required',
            'utility_tariff_required',
            'utility_changed',
            'utility_tariff_past_reading',
            'utility_tariff_date_exists',
          ]);
          _error = reason.isNotEmpty ? reason : e.code;
          if (['permission-denied', 'unauthenticated'].contains(e.code)) {
            _record = null;
            _history = [];
            _pending = null;
          } else if ([
            'aborted',
            'invalid-argument',
            'failed-precondition',
            'resource-exhausted',
          ].contains(e.code)) {
            _pending = null;
          }
        });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = 'save');
    } finally {
      if (mounted && generation == _generation) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invoiceReading != null)
      return UtilityInvoiceForm(
        key: ValueKey(_invoiceReading!['id']),
        service: widget.service,
        scope: _scope,
        reading: _invoiceReading!,
        onDone: () {
          setState(() => _invoiceReading = null);
          _load();
        },
        onCancel: () {
          setState(() => _invoiceReading = null);
          _load();
        },
      );
    final locked = _loading || _saving || _pending != null;
    String errorText() {
      if (_error == 'utility_void_invoice_first')
        return tr(
          'Refund payments and void the linked invoice before correcting this reading.',
          'Hoàn tiền và hủy hóa đơn liên kết trước khi sửa chỉ số.',
        );
      if (_error == 'utility_tariff_boundary_required')
        return tr(
          'Record a meter reading on the price-change date first.',
          'Hãy ghi chỉ số vào ngày đổi giá trước.',
        );
      if (_error == 'utility_tariff_required')
        return tr(
          'Set a price effective on or before the previous reading date.',
          'Đặt giá có hiệu lực từ ngày ghi chỉ số trước hoặc sớm hơn.',
        );
      if (_error == 'utility_changed')
        return tr(
          'Another change was saved. Reload before trying again.',
          'Dữ liệu đã thay đổi. Tải lại trước khi thử lại.',
        );
      if (_error == 'utility_tariff_past_reading')
        return tr(
          'The price date is before an existing reading. Use a later date.',
          'Ngày áp dụng giá trước chỉ số đã ghi. Hãy chọn ngày sau.',
        );
      if (_error == 'utility_tariff_date_exists')
        return tr(
          'A price already exists on that date. Choose another date.',
          'Đã có giá cho ngày này. Hãy chọn ngày khác.',
        );
      if (_error == 'load')
        return tr(
          'Could not load readings. Try again.',
          'Không tải được chỉ số. Hãy thử lại.',
        );
      return _pending != null
          ? tr(
              'Save was not confirmed. Retry this exact request or reload before editing.',
              'Chưa xác nhận lưu. Thử lại yêu cầu này hoặc tải lại trước khi sửa.',
            )
          : tr(
              'Could not save. Check the dates, readings and your access, then reload.',
              'Không thể lưu. Kiểm tra ngày, chỉ số và quyền truy cập, rồi tải lại.',
            );
    }

    // The message for [place], next to the button that caused it. Retry only
    // where trying again can work: a failed load, or a save whose result is
    // unknown. A changed record offers Reload. Refusals the person must fix
    // elsewhere (void the invoice, choose another date) get no button.
    // Without a record (access lost) every message shows at the top.
    List<Widget> notice(String place) {
      if (_error == null) return const [];
      final here = _record == null ? place == 'top' : _errorAt == place;
      if (!here) return const [];
      final retry = _error == 'load' || _pending != null;
      final reload = _pending != null || _error == 'utility_changed';
      return [
        Semantics(liveRegion: true, child: WsNotice(errorText())),
        if (retry || reload)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (retry)
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : (_pending == null ? _load : _save),
                    child: Text(tr('Retry', 'Thử lại')),
                  ),
                if (reload)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() => _pending = null);
                            _load();
                          },
                    child: Text(tr('Reload', 'Tải lại')),
                  ),
              ],
            ),
          ),
      ];
    }

    Widget field(
      TextEditingController controller,
      String label, {
      bool quantity = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: !locked,
        keyboardType: quantity
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        validator: (v) => controller == _date
            ? utilityDate((v ?? '').trim())
                  ? null
                  : tr('Enter a valid date.', 'Nhập ngày hợp lệ.')
            : quantity
            ? (meterMilli(v ?? '') == null
                  ? tr(
                      'Enter a non-negative reading (up to 3 decimals).',
                      'Nhập chỉ số không âm (tối đa 3 số lẻ).',
                    )
                  : null)
            : ((v ?? '').trim().isEmpty ? tr('Required', 'Bắt buộc') : null),
      ),
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: WorkspacePageScope.constraints(context, 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!PageTabScope.contains(context))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving ? null : widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                    label: Text(tr('Back', 'Quay lại')),
                  ),
                ),
              Text(
                tr('Electricity & water readings', 'Chỉ số điện và nước'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final kind in ['electricity', 'water'])
                    ChoiceChip(
                      label: Text(
                        kind == 'electricity'
                            ? tr('Electricity', 'Điện')
                            : tr('Water', 'Nước'),
                      ),
                      selected: _kind == kind,
                      onSelected: locked
                          ? null
                          : (_) {
                              setState(() {
                                _kind = kind;
                                _reset = false;
                                for (final c in [
                                  _date,
                                  _reading,
                                  _oldFinal,
                                  _newStart,
                                  _reason,
                                ]) {
                                  c.clear();
                                }
                              });
                              _load();
                            },
                    ),
                ],
              ),
              if (_loading || _saving) const LinearProgressIndicator(),
              ...notice('top'),
              if (_record != null) ...[
                const SizedBox(height: 16),
                Text('${tr('Room', 'Phòng')}: ${_record!['roomNumber']}'),
                Text(
                  _record!['lastDate'] == null
                      ? tr(
                          'The first reading is a baseline, with no charge.',
                          'Chỉ số đầu là mốc bắt đầu, chưa tính tiền.',
                        )
                      : '${tr('Previous', 'Chỉ số trước')}: ${appQuantityMilli(_record!['lastReadingMilli'] as num)} · ${_record!['lastDate']}',
                ),
                if ((_record!['roomTariffs'] as List? ?? []).isEmpty &&
                    (_record!['propertyTariffs'] as List? ?? []).isEmpty)
                  Text(
                    tr(
                      'Set a tariff before recording consumption.',
                      'Cần đặt đơn giá trước khi ghi mức tiêu thụ.',
                    ),
                  ),
                for (final source in ['propertyTariffs', 'roomTariffs'])
                  for (final rate in (_record![source] as List? ?? []))
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${source == 'propertyTariffs' ? tr('Property price', 'Giá tòa nhà') : tr('Room price', 'Giá phòng')} · ${rate['effectiveDate']}',
                          ),
                          if (rate['tariff'] == null)
                            Text(
                              tr(
                                'Use property default',
                                'Dùng giá mặc định của tòa nhà',
                              ),
                            )
                          else
                            for (final band in rate['tariff']['bands'])
                              Text(
                                '${band['throughMilli'] == null ? tr('Remaining usage', 'Mức tiêu thụ còn lại') : '${tr('Up to', 'Đến')} ${appQuantityMilli(band['throughMilli'] as num)}'}: ${appMoneyMinor(band['priceMinor'] as num, '${rate['tariff']['currency']}')} / ${_kind == 'electricity' ? 'kWh' : 'm³'}',
                              ),
                        ],
                      ),
                    ),
                const SizedBox(height: 16),
                Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      field(
                        _date,
                        tr(
                          'Reading date (YYYY-MM-DD)',
                          'Ngày ghi (YYYY-MM-DD)',
                        ),
                      ),
                      field(
                        _reading,
                        tr('Meter reading', 'Chỉ số đồng hồ'),
                        quantity: true,
                      ),
                      if (_record!['lastDate'] != null)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            tr(
                              'Meter replaced or reset',
                              'Đã thay hoặc đặt lại đồng hồ',
                            ),
                          ),
                          value: _reset,
                          onChanged: locked
                              ? null
                              : (v) => setState(() => _reset = v!),
                        ),
                      if (_reset) ...[
                        field(
                          _oldFinal,
                          tr(
                            'Old meter final reading',
                            'Chỉ số cuối đồng hồ cũ',
                          ),
                          quantity: true,
                        ),
                        field(
                          _newStart,
                          tr(
                            'New meter initial reading',
                            'Chỉ số đầu đồng hồ mới',
                          ),
                          quantity: true,
                        ),
                      ],
                      field(_reason, tr('Note / reason', 'Ghi chú / lý do')),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: locked ? null : _save,
                          child: Text(tr('Save', 'Lưu')),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...notice('form'),
                    ],
                  ),
                ),
                if (_record!['canPrice'] == true) ...[
                  const SizedBox(height: 24),
                  UtilityTariffForm(
                    organizationId: widget.organizationId,
                    key: ValueKey(
                      '$_kind-${_record!['revision']}-${_record!['propertyRevision']}',
                    ),
                    currency: _record!['currency'] ?? 'VND',
                    locked: locked,
                    onSave: _saveTariff,
                  ),
                  const SizedBox(height: 8),
                  ...notice('tariff'),
                ],
                const SizedBox(height: 24),
                Text(
                  tr('Reading history', 'Lịch sử chỉ số'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_history.isEmpty)
                  Text(tr('No readings yet.', 'Chưa có chỉ số.')),
                for (final row in _history.reversed)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${row['date']} · ${appQuantityMilli(row['readingMilli'] as num)}',
                          ),
                          if (row['calculation'] != null)
                            Text(
                              '${appQuantityMilli(row['calculation']['usageMilli'] as num)} ${_kind == 'electricity' ? 'kWh' : 'm³'} · ${appMoneyMinor(row['calculation']['amountMinor'] as num, '${row['calculation']['currency']}')}',
                            ),
                          Text(row['reason'] ?? ''),
                          if (row['reversedAt'] != null)
                            Text(
                              tr(
                                'Reversed — original retained',
                                'Đã hủy chỉ số — giữ bản gốc',
                              ),
                            )
                          else if (row['invoiceId'] != null)
                            Text(tr('Invoiced', 'Đã lập hóa đơn'))
                          else if (_record!['canBill'] == true &&
                              row['calculation'] != null &&
                              (row['calculation']['amountMinor'] as num) > 0)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton(
                                onPressed: locked
                                    ? null
                                    : () =>
                                          setState(() => _invoiceReading = row),
                                child: Text(tr('Invoice', 'Hóa đơn')),
                              ),
                            ),
                          if (row['reversedAt'] == null &&
                              row['id'] == _record!['lastReadingId'] &&
                              _record!['canPrice'] == true)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: locked ? null : () => _reverse(row),
                                child: Text(tr('Correct', 'Sửa chỉ số')),
                              ),
                            ),
                          ...notice('reading:${row['id']}'),
                        ],
                      ),
                    ),
                  ),
                if (_cursor != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: locked ? null : () => _load(more: true),
                      child: Text(tr('More', 'Xem thêm')),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UtilityCorrectionDialog extends StatefulWidget {
  final bool invoiced;
  const _UtilityCorrectionDialog({this.invoiced = false});
  @override
  State<_UtilityCorrectionDialog> createState() =>
      _UtilityCorrectionDialogState();
}

class _UtilityCorrectionDialogState extends State<_UtilityCorrectionDialog> {
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vi = AppTranslations.of(context).locale.languageCode == 'vi';
    if (widget.invoiced) {
      return AlertDialog(
        scrollable: true,
        title: Text(vi ? 'Sửa chỉ số cuối' : 'Correct latest reading'),
        content: Text(
          vi
              ? 'Chỉ số này đã có hóa đơn. Hãy hoàn tiền và hủy hóa đơn đó trước, rồi sửa chỉ số.'
              : 'This reading is on an invoice. Refund payments and void that invoice first, then correct the reading.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(vi ? 'Đóng' : 'Close'),
          ),
        ],
      );
    }
    return AlertDialog(
      scrollable: true,
      title: Text(vi ? 'Sửa chỉ số cuối' : 'Correct latest reading'),
      content: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              vi
                  ? 'Hủy chỉ số cuối rồi nhập lại. Bản gốc và lý do vẫn được lưu. Nếu đã lập hóa đơn, cần hoàn tiền và hủy hóa đơn trước.'
                  : 'Reverse the latest reading, then enter its replacement. The original and reason remain in history. Refund and void any linked invoice first.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: reason,
              maxLength: 1000,
              decoration: InputDecoration(labelText: vi ? 'Lý do' : 'Reason'),
              validator: (v) => (v ?? '').trim().isEmpty
                  ? (vi ? 'Bắt buộc' : 'Required')
                  : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(vi ? 'Đóng' : 'Close'),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate())
              Navigator.pop(context, reason.text.trim());
          },
          child: Text(vi ? 'Xác nhận' : 'Confirm'),
        ),
      ],
    );
  }
}
