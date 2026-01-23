import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Helper class for invoice line items with meter readings
class InvoiceLineItem {
  String id;
  PaymentType type;
  double amount;
  String? description;
  
  // Electricity fields
  double? electricityStartReading;
  DateTime? electricityStartDate;
  double? electricityEndReading;
  DateTime? electricityEndDate;
  double? electricityPricePerUnit;
  
  // Water fields
  double? waterStartReading;
  DateTime? waterStartDate;
  double? waterEndReading;
  DateTime? waterEndDate;
  double? waterPricePerUnit;
  
  // Billing period
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

// Parse line items from payment with meter readings support
List<InvoiceLineItem> _parseLineItemsForDelete(Payment payment) {
  // For single-type payments with meter readings, create detailed line item
  if (payment.type == PaymentType.electricity && payment.electricityStartReading != null) {
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
  
  if (payment.type == PaymentType.water && payment.waterStartReading != null) {
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
  
  if (payment.type == PaymentType.rent && payment.billingStartDate != null) {
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
  
  // Try to parse multi-line format from description
  final description = payment.description;
  if (description != null && description.contains('\n')) {
    final lines = description.split('\n');
    final items = <InvoiceLineItem>[];
    
    for (var line in lines) {
      final match = RegExp(r'^([^:]+):\s*([\d,]+)\s*VND(?:\s*\((.+)\))?$').firstMatch(line.trim());
      if (match != null) {
        final typeLabel = match.group(1)?.trim() ?? '';
        final amountStr = match.group(2)?.replaceAll(',', '') ?? '0';
        final desc = match.group(3);
        
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
    
    if (items.isNotEmpty) return items;
  }
  
  // Default: single line item
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

  Widget _buildLineItemCard(InvoiceLineItem item, int index) {
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
    final typeLabel = labels[item.type.name] ?? item.type.name;
    
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${index + 1}. $typeLabel',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                NumberFormat('#,###').format(item.amount) + ' đ',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          // Electricity meter readings
          if (item.type == PaymentType.electricity && item.electricityStartReading != null) ...[
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chỉ số đầu',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                      Text(
                        '${item.electricityStartReading} kWh',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      if (item.electricityStartDate != null)
                        Text(
                          DateFormat('dd/MM/yyyy').format(item.electricityStartDate!),
                          style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chỉ số cuối',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                      Text(
                        '${item.electricityEndReading} kWh',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      if (item.electricityEndDate != null)
                        Text(
                          DateFormat('dd/MM/yyyy').format(item.electricityEndDate!),
                          style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tiêu thụ: ${((item.electricityEndReading ?? 0) - (item.electricityStartReading ?? 0)).toStringAsFixed(1)} kWh',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
          
          // Water meter readings
          if (item.type == PaymentType.water && item.waterStartReading != null) ...[
            const SizedBox(height: 6),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chỉ số đầu',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                      Text(
                        '${item.waterStartReading} m³',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      if (item.waterStartDate != null)
                        Text(
                          DateFormat('dd/MM/yyyy').format(item.waterStartDate!),
                          style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chỉ số cuối',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                      Text(
                        '${item.waterEndReading} m³',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      if (item.waterEndDate != null)
                        Text(
                          DateFormat('dd/MM/yyyy').format(item.waterEndDate!),
                          style: TextStyle(fontSize: 9, color: Colors.grey[500]),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Tiêu thụ: ${((item.waterEndReading ?? 0) - (item.waterStartReading ?? 0)).toStringAsFixed(1)} m³',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
          
          // Billing period
          if (item.billingStartDate != null && item.billingEndDate != null) ...[
            const SizedBox(height: 6),
            Text(
              'Kỳ: ${DateFormat('dd/MM/yyyy').format(item.billingStartDate!)} - ${DateFormat('dd/MM/yyyy').format(item.billingEndDate!)}',
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
          ],
          
          // Description
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.description!,
              style: TextStyle(fontSize: 10, color: Colors.grey[600], fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
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
                    ...List.generate(
                      lineItems.length,
                      (index) => _buildLineItemCard(lineItems[index], index),
                    ),
                    const SizedBox(height: 8),
                  ] else if (lineItems.isNotEmpty) ...[
                    // Show single item details
                    const Divider(),
                    const SizedBox(height: 8),
                    _buildLineItemCard(lineItems.first, 0),
                    const SizedBox(height: 8),
                  ],
                  
                  if (isMultiLine || lineItems.isNotEmpty)
                    const Divider(),
                  
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
                  
                  // Show late fee if present
                  if (payment.lateFee != null && payment.lateFee! > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Phí trễ hạn:',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red,
                          ),
                        ),
                        Text(
                          '+ ${NumberFormat('#,###').format(payment.lateFee!)} VND',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Divider(),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'TỔNG THANH TOÁN:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          NumberFormat('#,###').format(payment.totalAmount) + ' VND',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  ],
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