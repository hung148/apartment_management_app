import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:apartment_management_project_2/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Helper class for invoice line items with meter readings
class InvoiceLineItem {
  String id;
  PaymentType type;
  double amount;
  String? description;

  double? electricityStartReading;
  DateTime? electricityStartDate;
  double? electricityEndReading;
  DateTime? electricityEndDate;
  double? electricityPricePerUnit;

  double? waterStartReading;
  DateTime? waterStartDate;
  double? waterEndReading;
  DateTime? waterEndDate;
  double? waterPricePerUnit;

  DateTime? billingStartDate;
  DateTime? billingEndDate;

  InvoiceLineItem({
    required this.id,
    required this.type,
    required this.amount,
    this.description,
    this.electricityStartReading,
    this.electricityStartDate,
    this.electricityEndReading,
    this.electricityEndDate,
    this.electricityPricePerUnit,
    this.waterStartReading,
    this.waterStartDate,
    this.waterEndReading,
    this.waterEndDate,
    this.waterPricePerUnit,
    this.billingStartDate,
    this.billingEndDate,
  });
}

// Returns a localized payment type label using translation keys that already
// exist in AppTranslations (payment_type_*).
String _typeLabel(PaymentType type, AppTranslations t) {
  const keyMap = {
    PaymentType.rent: 'payment_type_rent',
    PaymentType.electricity: 'payment_type_electricity',
    PaymentType.water: 'payment_type_water',
    PaymentType.internet: 'payment_type_internet',
    PaymentType.parking: 'payment_type_parking',
    PaymentType.maintenance: 'payment_type_maintenance',
    PaymentType.deposit: 'payment_type_deposit',
    PaymentType.penalty: 'payment_type_penalty',
    PaymentType.other: 'payment_type_other',
  };
  final key = keyMap[type];
  return key != null ? t[key] : type.name;
}

// Parse line items — identical logic to the original, kept here so this file
// is self-contained.
List<InvoiceLineItem> _parseLineItems(Payment payment) {
  if (payment.type == PaymentType.electricity &&
      payment.electricityStartReading != null) {
    return [
      InvoiceLineItem(
        id: payment.id,
        type: payment.type,
        amount: payment.amount,
        description: payment.description,
        electricityStartReading: payment.electricityStartReading,
        electricityStartDate: payment.electricityStartDate,
        electricityEndReading: payment.electricityEndReading,
        electricityEndDate: payment.electricityEndDate,
        electricityPricePerUnit: payment.electricityPricePerUnit,
      ),
    ];
  }

  if (payment.type == PaymentType.water &&
      payment.waterStartReading != null) {
    return [
      InvoiceLineItem(
        id: payment.id,
        type: payment.type,
        amount: payment.amount,
        description: payment.description,
        waterStartReading: payment.waterStartReading,
        waterStartDate: payment.waterStartDate,
        waterEndReading: payment.waterEndReading,
        waterEndDate: payment.waterEndDate,
        waterPricePerUnit: payment.waterPricePerUnit,
      ),
    ];
  }

  if (payment.type == PaymentType.rent &&
      payment.billingStartDate != null) {
    return [
      InvoiceLineItem(
        id: payment.id,
        type: payment.type,
        amount: payment.amount,
        description: payment.description,
        billingStartDate: payment.billingStartDate,
        billingEndDate: payment.billingEndDate,
      ),
    ];
  }

  final description = payment.description;
  if (description != null && description.contains('\n')) {
    final lines = description.split('\n');
    final items = <InvoiceLineItem>[];
    for (var line in lines) {
      final match =
          RegExp(r'^([^:]+):\s*([\d,]+)\s*VND(?:\s*\((.+)\))?$')
              .firstMatch(line.trim());
      if (match != null) {
        final typeLabel = match.group(1)?.trim() ?? '';
        final amountStr = match.group(2)?.replaceAll(',', '') ?? '0';
        final desc = match.group(3);

        // Reverse-map Vietnamese label → PaymentType for legacy descriptions.
        const labelToType = {
          'Tiền thuê': PaymentType.rent,
          'Tiền điện': PaymentType.electricity,
          'Tiền nước': PaymentType.water,
          'Tiền internet': PaymentType.internet,
          'Tiền gửi xe': PaymentType.parking,
          'Phí bảo trì': PaymentType.maintenance,
          'Tiền cọc': PaymentType.deposit,
          'Tiền phạt': PaymentType.penalty,
          'Khác': PaymentType.other,
        };

        items.add(InvoiceLineItem(
          id: DateTime.now().millisecondsSinceEpoch.toString() +
              items.length.toString(),
          type: labelToType[typeLabel] ?? PaymentType.other,
          amount: double.tryParse(amountStr) ?? 0,
          description: desc,
        ));
      }
    }
    if (items.isNotEmpty) return items;
  }

  return [
    InvoiceLineItem(
      id: payment.id,
      type: payment.type,
      amount: payment.amount,
      description: description,
      billingStartDate: payment.billingStartDate,
      billingEndDate: payment.billingEndDate,
    ),
  ];
}

// ========================================
// DELETE PAYMENT DIALOG
// ========================================
class DeletePaymentDialog extends StatelessWidget {
  final Payment payment;
  final PaymentService paymentService;
  final VoidCallback? onDeleted;

  const DeletePaymentDialog({
    super.key,
    required this.payment,
    required this.paymentService,
    this.onDeleted,
  });

  Future<void> _deletePayment(BuildContext context, AppTranslations t) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final success = await paymentService.deletePayment(payment.id);

      if (context.mounted) Navigator.pop(context);

      if (success) {
        if (context.mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t['del_payment_success']),
            backgroundColor: Colors.green,
          ));
          onDeleted?.call();
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t['del_payment_error']),
            backgroundColor: Colors.red,
          ));
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(t.textWithParams('del_payment_error_detail', {'error': e})),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Widget _buildLineItemCard(InvoiceLineItem item, int index, AppTranslations t) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final label = _typeLabel(item.type, t);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${index + 1}. $label',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                '${NumberFormat('#,###').format(item.amount)} đ',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          // ── Electricity meter readings ──────────────────────────────────
          if (item.type == PaymentType.electricity &&
              item.electricityStartReading != null) ...[
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['meter_start_reading'],
                          style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                      Text('${item.electricityStartReading} kWh',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                      if (item.electricityStartDate != null)
                        Text(dateFormat.format(item.electricityStartDate!),
                            style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['meter_end_reading'],
                          style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                      Text('${item.electricityEndReading} kWh',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                      if (item.electricityEndDate != null)
                        Text(dateFormat.format(item.electricityEndDate!),
                            style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.textWithParams('meter_consumption_kwh', {
                'value': ((item.electricityEndReading ?? 0) -
                        (item.electricityStartReading ?? 0))
                    .toStringAsFixed(1),
              }),
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],

          // ── Water meter readings ────────────────────────────────────────
          if (item.type == PaymentType.water &&
              item.waterStartReading != null) ...[
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['meter_start_reading'],
                          style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                      Text('${item.waterStartReading} m³',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                      if (item.waterStartDate != null)
                        Text(dateFormat.format(item.waterStartDate!),
                            style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['meter_end_reading'],
                          style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                      Text('${item.waterEndReading} m³',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                      if (item.waterEndDate != null)
                        Text(dateFormat.format(item.waterEndDate!),
                            style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              t.textWithParams('meter_consumption_m3', {
                'value': ((item.waterEndReading ?? 0) -
                        (item.waterStartReading ?? 0))
                    .toStringAsFixed(1),
              }),
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],

          // ── Billing period ──────────────────────────────────────────────
          if (item.billingStartDate != null && item.billingEndDate != null) ...[
            const SizedBox(height: 6),
            Text(
              t.textWithParams('billing_period', {
                'start': dateFormat.format(item.billingStartDate!),
                'end': dateFormat.format(item.billingEndDate!),
              }),
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],

          // ── Description ─────────────────────────────────────────────────
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.description!,
              style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label,
              style: TextStyle(color: Colors.grey[700], fontSize: 14)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final lineItems = _parseLineItems(payment);
    final isMultiLine = lineItems.length > 1;
    final dateFormat = DateFormat('dd/MM/yyyy');

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning, color: Colors.red[700]),
          const SizedBox(width: 12),
          Text(t['del_payment_title']),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Confirmation question ──────────────────────────────────────
            Text(
              t['del_payment_confirm_question'],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // ── Payment summary card ───────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDetailRow(
                    t['del_payment_tenant'],
                    payment.tenantName ?? t['del_payment_unknown_tenant'],
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    t['del_payment_due_date'],
                    dateFormat.format(payment.dueDate),
                  ),
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    t['del_payment_status'],
                    payment.getStatusDisplayName(),
                  ),

                  // ── Line items ───────────────────────────────────────────
                  if (isMultiLine || lineItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    if (isMultiLine)
                      Text(
                        t['del_payment_items_label'],
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    if (isMultiLine) const SizedBox(height: 8),
                    ...List.generate(
                      lineItems.length,
                      (i) => _buildLineItemCard(lineItems[i], i, t),
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                  ],

                  // ── Totals ───────────────────────────────────────────────
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(t['del_payment_total'],
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        '${NumberFormat('#,###').format(payment.amount)} VND',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.red[700]),
                      ),
                    ],
                  ),

                  if (payment.lateFee != null && payment.lateFee! > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t['del_payment_late_fee'],
                            style: const TextStyle(
                                fontSize: 13, color: Colors.red)),
                        Text(
                          '+ ${NumberFormat('#,###').format(payment.lateFee!)} VND',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.red),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Divider(),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(t['del_payment_grand_total'],
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(
                          '${NumberFormat('#,###').format(payment.totalAmount)} VND',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.red[700]),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Cannot-undo warning ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.red[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t['del_payment_cannot_undo'],
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t['cancel']),
        ),
        ElevatedButton(
          onPressed: () => _deletePayment(context, t),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: Text(t['del_payment_action']),
        ),
      ],
    );
  }
}