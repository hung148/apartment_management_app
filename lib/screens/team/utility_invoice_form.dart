import 'workspace_page_scope.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'utility_tariff_form.dart' show utilityDate;

class UtilityInvoiceForm extends StatefulWidget {
  final TeamService service;
  final Map<String, dynamic> scope, reading;
  final VoidCallback onDone, onCancel;
  const UtilityInvoiceForm({
    super.key,
    required this.service,
    required this.scope,
    required this.reading,
    required this.onDone,
    required this.onCancel,
  });
  @override
  State<UtilityInvoiceForm> createState() => _UtilityInvoiceFormState();
}

class _UtilityInvoiceFormState extends State<UtilityInvoiceForm> {
  final _due = TextEditingController(), _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _tenants = [];
  Map<String, dynamic>? _quote, _payload, _pending;
  String? _tenant, _error;
  bool _busy = true;
  String tr(String en, String vi) =>
      AppTranslations.of(context).locale.languageCode == 'vi' ? vi : en;
  Map<String, dynamic> get identity => {
    'organizationId': widget.scope['organizationId'],
    'buildingId': widget.scope['buildingId'],
  };
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _due.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      _busy = true;
      _error = null;
      _tenants = [];
    });
    try {
      final data = await widget.service.invoices({
        'action': 'tenants',
        ...identity,
      });
      if (!mounted) return;
      setState(() {
        _tenants = (data['records'] as List)
            .map((x) => Map<String, dynamic>.from(x))
            .toList();
        _due.text = data['today'];
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'load');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> review() async {
    if (_busy || !_form.currentState!.validate() || _tenant == null) return;
    final payload = {
      'kind': 'utility',
      ...identity,
      'roomId': widget.scope['roomId'],
      'chargeType': widget.scope['kind'],
      'readingId': widget.reading['id'],
      'tenantId': _tenant,
      'startDate': widget.reading['startDate'],
      'endDate': widget.reading['date'],
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
      if (mounted)
        setState(() {
          _quote = Map<String, dynamic>.from(data['record']);
          _payload = payload;
        });
    } catch (_) {
      if (mounted) setState(() => _error = 'quote');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> confirm() async {
    if (_busy) return;
    final request =
        _pending ??
        {
          'action': 'create',
          ..._payload!,
          'quoteRevision': _quote!['quoteRevision'],
          'operationId': const Uuid().v4(),
        };
    setState(() {
      _busy = true;
      _pending = request;
      _error = null;
    });
    try {
      await widget.service.invoices(request);
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) setState(() => _error = 'save');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: ConstrainedBox(
        constraints: WorkspacePageScope.constraints(context, 760),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy ? null : widget.onCancel,
                  child: Text(tr('Back', 'Quay lại')),
                ),
              ),
              Text(
                tr('Invoice for measured usage', 'Hóa đơn theo chỉ số'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${widget.reading['startDate']} – ${widget.reading['date']}',
              ),
              Text(
                tr(
                  'Choose the tenant who occupied this room for the entire interval. Take separate readings at tenant handovers.',
                  'Chọn khách ở phòng trong toàn bộ kỳ ghi chỉ số. Cần ghi riêng chỉ số khi bàn giao giữa các khách.',
                ),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error == 'save'
                        ? tr(
                            'Invoice creation was not confirmed. Retry, or return and refresh the reading.',
                            'Chưa xác nhận tạo hóa đơn. Thử lại hoặc quay lại và tải lại chỉ số.',
                          )
                        : _error == 'quote'
                        ? tr(
                            'Cannot bill this interval. Check the tenant, dates and whether it is already billed.',
                            'Không thể tính tiền kỳ này. Kiểm tra khách, ngày và hóa đơn đã lập.',
                          )
                        : tr(
                            'Could not load tenants. Try again.',
                            'Không tải được khách. Hãy thử lại.',
                          ),
                  ),
                ),
              if (_error == 'load')
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: _busy ? null : load,
                    child: Text(tr('Retry', 'Thử lại')),
                  ),
                ),
              if (!_busy && _error != 'load' && _tenants.isEmpty)
                Text(
                  tr(
                    'No tenants are available for invoicing.',
                    'Chưa có khách để lập hóa đơn.',
                  ),
                ),
              if (_quote == null) ...[
                for (final tenant in _tenants)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tenant['fullName'] ?? ''),
                    value: _tenant == tenant['id'],
                    onChanged: _busy
                        ? null
                        : (_) => setState(() => _tenant = tenant['id']),
                  ),
                const SizedBox(height: 12),
                Text(tr('Due date', 'Hạn thanh toán')),
                TextFormField(
                  controller: _due,
                  enabled: !_busy,
                  decoration: const InputDecoration(hintText: 'YYYY-MM-DD'),
                  validator: (v) => utilityDate((v ?? '').trim())
                      ? null
                      : tr('Enter a valid date.', 'Nhập ngày hợp lệ.'),
                ),
                const SizedBox(height: 12),
                Text(tr('Reason', 'Lý do')),
                TextFormField(
                  controller: _reason,
                  enabled: !_busy,
                  maxLength: 1000,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? tr('Required', 'Bắt buộc')
                      : null,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _busy || _tenant == null ? null : review,
                    child: Text(tr('Review', 'Xem lại')),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Text(
                  '${tr('Total', 'Tổng tiền')}: ${_quote!['totalMinor'] / (_quote!['currency'] == 'USD' ? 100 : 1)} ${_quote!['currency']}',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : confirm,
                      child: Text(
                        _pending == null
                            ? tr('Create', 'Tạo')
                            : tr('Retry', 'Thử lại'),
                      ),
                    ),
                    if (_pending == null)
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _quote = null),
                        child: Text(tr('Edit', 'Sửa')),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
