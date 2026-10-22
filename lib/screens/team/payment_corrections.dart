import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';

/// Existing receipts are corrected in their stored currency; no new collection.
class PaymentCorrectionsButton extends StatelessWidget {
  final TeamService service;
  final String organizationId, buildingId;
  final String? bookingId, tenantId, paymentId;
  final bool iconOnly;
  final bool enabled;
  final Future<void> Function() onSaved;
  const PaymentCorrectionsButton({
    super.key,
    required this.service,
    required this.organizationId,
    required this.buildingId,
    this.bookingId,
    this.tenantId,
    this.paymentId,
    this.iconOnly = false,
    this.enabled = true,
    required this.onSaved,
  });
  @override
  Widget build(BuildContext context) {
    final vi = AppTranslations.of(context).locale.languageCode == 'vi';
    Future<void> open() async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => _ReceiptDialog(
          service: service,
          vi: vi,
          paymentId: paymentId,
          scope: {
            'organizationId': organizationId,
            'buildingId': buildingId,
            if (bookingId != null) 'bookingId': bookingId,
            if (tenantId != null) 'tenantId': tenantId,
          },
        ),
      );
      if (saved == true) await onSaved();
    }

    if (iconOnly) {
      return IconButton(
        key: ValueKey('edit-payment-$paymentId'),
        tooltip: vi ? 'Sửa' : 'Edit',
        icon: const Icon(Icons.edit_outlined),
        onPressed: enabled ? open : null,
      );
    }
    return TextButton.icon(
      key: const ValueKey('edit-recorded-payments'),
      icon: const Icon(Icons.edit_outlined),
      label: Text(vi ? 'Sửa thanh toán đã ghi nhận' : 'Edit recorded payments'),
      onPressed: enabled ? open : null,
    );
  }
}

class _ReceiptDialog extends StatefulWidget {
  final TeamService service;
  final Map<String, dynamic> scope;
  final bool vi;
  final String? paymentId;
  const _ReceiptDialog({
    required this.service,
    required this.scope,
    required this.vi,
    this.paymentId,
  });
  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  final amount = TextEditingController(),
      date = TextEditingController(),
      note = TextEditingController();
  final form = GlobalKey<FormState>();
  List<Map<String, dynamic>> rows = [];
  Map<String, dynamic>? selected, pending;
  bool busy = true, changed = false;
  String? error;
  String w(String en, String vi) => widget.vi ? vi : en;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    amount.dispose();
    date.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
      rows = [];
      selected = null;
    });
    try {
      final result = await widget.service.mutatePayment({
        ...widget.scope,
        'action': 'receipts',
      });
      if (!mounted) return;
      setState(() {
        rows = (result['records'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        selected = null;
      });
      if (widget.paymentId != null) {
        final matches = rows.where(
          (r) =>
              r['paymentId'] == widget.paymentId && r['receiptId'] == 'booking',
        );
        if (matches.length == 1) {
          edit(matches.single);
        } else {
          setState(() {
            rows = [];
            error = w(
              'This payment is no longer available to edit.',
              'Thanh toán này không còn có thể chỉnh sửa.',
            );
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = w(
            'Could not load payments. Try again.',
            'Không tải được thanh toán. Hãy thử lại.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void edit(Map<String, dynamic> row) {
    amount.text = appMoneyInputText(
      row['amountMinor'] as num,
      row['currency'] as String,
    );
    date.text = '${row['paidOn']}';
    note.text = '${row['note']}';
    setState(() {
      selected = row;
      error = null;
    });
  }

  Future<void> save() async {
    if (pending == null) {
      if (!form.currentState!.validate()) return;
      pending = {
        ...widget.scope,
        'action': 'correctReceipt',
        'operationId': const Uuid().v4(),
        'paymentId': selected!['paymentId'],
        'receiptId': selected!['receiptId'],
        'revision': selected!['revision'],
        'amountMinor': appParseMoney(
          amount.text,
          selected!['currency'] as String,
        ),
        'paidOn': date.text.trim(),
        'note': note.text.trim(),
      };
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.service.mutatePayment(pending!);
      if (!mounted) return;
      pending = null;
      changed = true;
      if (widget.paymentId != null) {
        Navigator.pop(context, true);
        return;
      }
      await load();
    } catch (e) {
      if (!mounted) return;
      // Keep the exact operation for network failures; known rejections allow editing.
      final message = '$e';
      if ([
        'invalid-argument',
        'failed-precondition',
        'permission-denied',
        'aborted',
        'not-found',
      ].any(message.contains)) {
        pending = null;
      }
      setState(
        () => error = w(
          'Could not save. Check the amount/date and your access. Reload if this payment changed.',
          'Không lưu được. Kiểm tra số tiền/ngày và quyền truy cập. Tải lại nếu thanh toán đã thay đổi.',
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && pending == null && !changed,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !busy && pending == null) Navigator.pop(context, changed);
    },
    child: AlertDialog(
      title: Text(w('Recorded payments', 'Thanh toán đã ghi nhận')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (changed && selected == null)
                Text(w('Correction saved.', 'Đã lưu chỉnh sửa.')),
              if (selected == null && !busy) ...[
                if (rows.isEmpty && error == null)
                  Text(
                    w(
                      'No recorded payments.',
                      'Chưa có thanh toán được ghi nhận.',
                    ),
                  ),
                for (final row in rows)
                  ListTile(
                    title: Text(
                      '${appMoneyMinor(row['amountMinor'] as num, row['currency'] as String)} · ${row['paidOn']}',
                    ),
                    subtitle: Text('${row['note']}'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () => edit(row),
                  ),
              ],
              if (selected != null)
                Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${w('Amount', 'Số tiền')} (${selected!['currency']})',
                      ),
                      const SizedBox(height: 8),
                      Semantics(
                        label:
                            '${w('Amount', 'Số tiền')} (${selected!['currency']})',
                        child: TextFormField(
                          key: const ValueKey('receipt-amount'),
                          controller: amount,
                          readOnly: busy || pending != null,
                          inputFormatters: appMoneyInput(
                            selected!['currency'] as String,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (v) {
                            final value = appParseMoney(
                              v ?? '',
                              selected!['currency'] as String,
                            );
                            return value == null || value <= 0
                                ? w(
                                    'Enter a valid amount.',
                                    'Nhập số tiền hợp lệ.',
                                  )
                                : null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(w('Payment date', 'Ngày thanh toán')),
                      const Text('YYYY-MM-DD'),
                      const SizedBox(height: 8),
                      Semantics(
                        label: w('Payment date', 'Ngày thanh toán'),
                        child: TextFormField(
                          key: const ValueKey('receipt-date'),
                          controller: date,
                          readOnly: busy || pending != null,
                          validator: (v) =>
                              RegExp(
                                r'^\d{4}-\d{2}-\d{2}$',
                              ).hasMatch(v?.trim() ?? '')
                              ? null
                              : w('Enter YYYY-MM-DD.', 'Nhập YYYY-MM-DD.'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(w('Note', 'Ghi chú')),
                      const SizedBox(height: 8),
                      Semantics(
                        label: w('Note', 'Ghi chú'),
                        child: TextFormField(
                          key: const ValueKey('receipt-note'),
                          controller: note,
                          readOnly: busy || pending != null,
                          maxLength: 500,
                          minLines: 1,
                          maxLines: 4,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy || pending != null
              ? null
              : () => Navigator.pop(context, changed),
          child: Text(w('Close', 'Đóng')),
        ),
        TextButton(
          onPressed: busy || pending != null ? null : load,
          child: Text(w('Reload', 'Tải lại')),
        ),
        if (selected != null)
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              pending != null
                  ? w('Retry same save', 'Thử lưu lại')
                  : w('Save correction', 'Lưu chỉnh sửa'),
            ),
          ),
      ],
    ),
  );
}
