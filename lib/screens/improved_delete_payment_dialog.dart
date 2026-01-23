import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Helper class for invoice line items
class InvoiceLineItem {
  String id;
  PaymentType type;
  double amount;
  String? description;

  InvoiceLineItem({
    required this.id,
    required this.type,
    required this.amount,
    this.description,
  });
}

// Parse line items from payment description
List<InvoiceLineItem> _parseLineItemsForDelete(Payment payment) {
  final description = payment.description;
  if (description == null || description.isEmpty) {
    // Legacy format: single line item
    return [
      InvoiceLineItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: payment.type,
        amount: payment.amount,
        description: null,
      ),
    ];
  }

  // Try to parse multi-line format
  final lines = description.split('\n');
  final items = <InvoiceLineItem>[];
  
  for (var line in lines) {
    // Format: "Tiền thuê: 5,000,000 VND (description)"
    final match = RegExp(r'^([^:]+):\s*([\d,]+)\s*VND(?:\s*\((.+)\))?$').firstMatch(line.trim());
    if (match != null) {
      final typeLabel = match.group(1)?.trim() ?? '';
      final amountStr = match.group(2)?.replaceAll(',', '') ?? '0';
      final desc = match.group(3);
      
      // Map label back to PaymentType
      PaymentType type = PaymentType.other;
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
      
      type = labelToType[typeLabel] ?? PaymentType.other;
      
      items.add(InvoiceLineItem(
        id: DateTime.now().millisecondsSinceEpoch.toString() + items.length.toString(),
        type: type,
        amount: double.tryParse(amountStr) ?? 0,
        description: desc,
      ));
    }
  }
  
  // If parsing failed, return single item
  if (items.isEmpty) {
    return [
      InvoiceLineItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: payment.type,
        amount: payment.amount,
        description: description,
      ),
    ];
  }
  
  return items;
}

// ========================================
// IMPROVED DELETE PAYMENT DIALOG
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

  Future<void> _deletePayment(BuildContext context) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Delete the payment
      final success = await paymentService.deletePayment(payment.id);

      // Close loading dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      if (success) {
        // Close confirmation dialog
        if (context.mounted) {
          Navigator.pop(context, true);
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đã xóa hóa đơn thành công'),
              backgroundColor: Colors.green,
            ),
          );

          // Call callback if provided
          onDeleted?.call();
        }
      } else {
        // Show error message
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lỗi khi xóa hóa đơn'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if still open
      if (context.mounted) {
        Navigator.pop(context);
      }

      // Show error message
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lineItems = _parseLineItemsForDelete(payment);
    final isMultiLine = lineItems.length > 1;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning, color: Colors.red[700]),
          const SizedBox(width: 12),
          const Text('Xóa Hóa Đơn'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bạn có chắc chắn muốn xóa hóa đơn này?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Payment details
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
                  _buildDetailRow('Người thuê:', payment.tenantName ?? 'Chưa xác định'),
                  const SizedBox(height: 8),
                  _buildDetailRow('Hạn thanh toán:', DateFormat('dd/MM/yyyy').format(payment.dueDate)),
                  const SizedBox(height: 8),
                  _buildDetailRow('Trạng thái:', payment.getStatusDisplayName()),
                  const SizedBox(height: 12),
                  
                  if (isMultiLine) ...[
                    const Divider(),
                    const SizedBox(height: 8),
                    const Text(
                      'Các khoản:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(lineItems.length, (index) {
                      final item = lineItems[index];
                      const labels = {
                        'rent': 'Tiền thuê',
                        'electricity': 'Tiền điện',
                        'water': 'Tiền nước',
                        'internet': 'Tiền internet',
                        'parking': 'Tiền gửi xe',
                        'maintenance': 'Phí bảo trì',
                        'deposit': 'Tiền cọc',
                        'penalty': 'Tiền phạt',
                        'other': 'Khác',
                      };
                      final typeLabel = labels[item.type.toString().split('.')[1]] ?? item.type.toString();
                      
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${index + 1}. $typeLabel',
                              style: const TextStyle(fontSize: 13),
                            ),
                            Text(
                              NumberFormat('#,###').format(item.amount) + ' đ',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    const Divider(),
                  ],
                  
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tổng tiền:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        NumberFormat('#,###').format(payment.amount) + ' VND',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
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
                  const Expanded(
                    child: Text(
                      'Hành động này không thể hoàn tác!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
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
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: () => _deletePayment(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Xóa Hóa Đơn'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}