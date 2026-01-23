import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/screens/payment_pdf_export.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
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
List<InvoiceLineItem> _parseLineItems(Payment payment) {
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
// VIEW PAYMENT DETAILS DIALOG
// ========================================
class ViewPaymentDetailsDialog extends StatelessWidget {
  final Payment payment;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final Organization organization;

  const ViewPaymentDetailsDialog({
    super.key,
    required this.payment,
    required this.isAdmin,
    required this.organization,
    this.onEdit,
  });

  Color _getPaymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return Colors.green;
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.overdue:
        return Colors.red;
      case PaymentStatus.cancelled:
        return Colors.grey;
      case PaymentStatus.refunded:
        return Colors.blue;
      case PaymentStatus.partial:
        return Colors.amber;
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    final lineItems = _parseLineItems(payment);
    
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : 600.0,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getPaymentStatusColor(payment.status).withOpacity(0.2),
                    child: Icon(
                      payment.status == PaymentStatus.paid
                          ? Icons.check_circle
                          : Icons.pending,
                      color: _getPaymentStatusColor(payment.status),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chi Tiết Hóa Đơn',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          payment.getStatusDisplayName(),
                          style: TextStyle(
                            fontSize: 12,
                            color: _getPaymentStatusColor(payment.status),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            
            // Body
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Basic Info
                      _buildDetailRow('Người Thuê', payment.tenantName ?? 'Chưa xác định'),
                      _buildDetailRow('Hạn Thanh Toán', DateFormat('dd/MM/yyyy').format(payment.dueDate)),
                      if (payment.paidAt != null)
                        _buildDetailRow('Ngày Thanh Toán', DateFormat('dd/MM/yyyy').format(payment.paidAt!)),
                      
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      
                      // Line Items Section
                      const Text(
                        'Chi Tiết Các Khoản',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
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
                        
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: Colors.grey[50],
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: Theme.of(context).primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        typeLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (item.description != null)
                                        Text(
                                          item.description!,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Text(
                                  NumberFormat('#,###').format(item.amount) + ' đ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      
                      const SizedBox(height: 8),
                      const Divider(thickness: 2),
                      const SizedBox(height: 8),
                      
                      // Total
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TỔNG CỘNG:',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            NumberFormat('#,###').format(payment.amount) + ' VND',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                      
                      // Notes
                      if (payment.notes != null && payment.notes!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                        const Text(
                          'Ghi Chú',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          payment.notes!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            
            const Divider(height: 1),
            
            // Footer Buttons
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Đóng'),
                    ),
                  ),
                  if (isAdmin) ...[
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onEdit!();
                        },
                        icon: const Icon(Icons.edit),
                        label: const Text('Chỉnh Sửa'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          PaymentPDFExporter.showPDFPreview(
                            context: context,
                            payment: payment,
                            organization: organization,
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tính năng xuất PDF - Xem hướng dẫn tích hợp'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Xuất PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ] else if (onEdit == null)
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tính năng xuất PDF - Xem hướng dẫn tích hợp'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Xuất PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================
// EDIT PAYMENT DIALOG
// ========================================
class EditPaymentDialog extends StatefulWidget {
  final Payment payment;
  final Organization organization;
  final BuildingService buildingService;
  final RoomService roomService;
  final TenantService tenantService;
  final PaymentService paymentService;

  const EditPaymentDialog({
    super.key,
    required this.payment,
    required this.organization,
    required this.buildingService,
    required this.roomService,
    required this.tenantService,
    required this.paymentService,
  });

  @override
  State<EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends State<EditPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _notesController;
  
  late String? _selectedTenantId;
  late String? _selectedTenantName;
  late PaymentStatus _selectedPaymentStatus;
  late DateTime _dueDate;
  
  List<Tenant> _tenants = [];
  List<InvoiceLineItem> _lineItems = [];
  
  double get _totalAmount => _lineItems.fold(0.0, (sum, item) => sum + item.amount);

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.payment.notes);
    _selectedTenantId = widget.payment.tenantId;
    _selectedTenantName = widget.payment.tenantName;
    _selectedPaymentStatus = widget.payment.status;
    _dueDate = widget.payment.dueDate;
    
    // Parse existing line items
    _lineItems = _parseLineItems(widget.payment);
    
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final tenants = await widget.tenantService.getOrganizationTenants(widget.organization.id);
      setState(() {
        _tenants = tenants;
        
        // Validate that _selectedTenantId exists in the tenants list
        if (_selectedTenantId != null) {
          final tenantExists = _tenants.any((t) => t.id == _selectedTenantId);
          if (!tenantExists) {
            // If the tenant ID doesn't exist in the list, set to null
            _selectedTenantId = null;
            _selectedTenantName = null;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    
    if (picked != null) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _showAddLineItemDialog() async {
    PaymentType? selectedType;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Thêm Mục Hóa Đơn'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<PaymentType>(
                    value: selectedType,
                    decoration: InputDecoration(
                      labelText: 'Loại thanh toán *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: PaymentType.values.map((t) {
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
                      return DropdownMenuItem(
                        value: t, 
                        child: Text(labels[t.toString().split('.')[1]] ?? ''),
                      );
                    }).toList(),
                    onChanged: (v) => setDialogState(() => selectedType = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Số tiền *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixText: 'VND',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: 'Mô tả',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedType != null && amountController.text.isNotEmpty) {
                    final amount = double.tryParse(amountController.text);
                    if (amount != null && amount > 0) {
                      Navigator.pop(context, {
                        'type': selectedType!,
                        'amount': amount,
                        'description': descriptionController.text.isEmpty ? null : descriptionController.text,
                      });
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Vui lòng nhập số tiền hợp lệ')),
                      );
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vui lòng điền đầy đủ thông tin')),
                    );
                  }
                },
                child: const Text('Thêm'),
              ),
            ],
          );
        },
      ),
    );
    
    if (result != null) {
      setState(() {
        _lineItems.add(InvoiceLineItem(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: result['type'] as PaymentType,
          amount: result['amount'] as double,
          description: result['description'] as String?,
        ));
      });
    }
  }

  void _removeLineItem(String id) {
    setState(() {
      _lineItems.removeWhere((item) => item.id == id);
    });
  }

  Widget _buildLineItemsList() {
    if (_lineItems.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.receipt_long, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(
                'Chưa có mục nào',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        ...List.generate(_lineItems.length, (index) {
          final item = _lineItems[index];
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
          
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(typeLabel),
              subtitle: item.description != null 
                  ? Text(item.description!, style: const TextStyle(fontSize: 12))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    NumberFormat('#,###').format(item.amount) + ' đ',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _removeLineItem(item.id),
                  ),
                ],
              ),
            ),
          );
        }),
        const Divider(thickness: 2),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TỔNG CỘNG:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                NumberFormat('#,###').format(_totalAmount) + ' VND',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _savePayment() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng thêm ít nhất một mục hóa đơn')),
      );
      return;
    }

    try {
      // Create description from line items
      final lineItemsDescription = _lineItems.map((item) {
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
        final desc = item.description != null ? ' (${item.description})' : '';
        return '${typeLabel}: ${NumberFormat('#,###').format(item.amount)} VND$desc';
      }).join('\n');

      // Update payment
      await widget.paymentService.updatePayment(
        widget.payment.id,
        {
          'tenantId': _selectedTenantId,
          'tenantName': _selectedTenantName,
          'amount': _totalAmount,
          'dueDate': _dueDate,
          'status': _selectedPaymentStatus.name,
          'description': lineItemsDescription,
          'notes': _notesController.text.isEmpty ? null : _notesController.text,
        },
      );
      
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã cập nhật hóa đơn thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật hóa đơn: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.width < 600;
    
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isPhone ? MediaQuery.of(context).size.width * 0.95 : 600.0,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.edit),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Chỉnh Sửa Hóa Đơn',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                
                // Body
                Expanded(
                  child: SingleChildScrollView(
                    child: Form(
                      key: _formKey,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Tenant Selection
                            DropdownButtonFormField<String?>(
                              value: _tenants.any((t) => t.id == _selectedTenantId) ? _selectedTenantId : null,
                              decoration: InputDecoration(
                                labelText: 'Người thuê',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(value: null, child: Text('Không chọn')),
                                ..._tenants.map((t) => DropdownMenuItem<String?>(value: t.id, child: Text(t.fullName ?? ''))).toList(),
                              ],
                              onChanged: (v) {
                                if (v != null && v.isNotEmpty) {
                                  final tenant = _tenants.firstWhere((t) => t.id == v);
                                  setState(() {
                                    _selectedTenantId = v;
                                    _selectedTenantName = tenant.fullName;
                                  });
                                } else {
                                  setState(() {
                                    _selectedTenantId = null;
                                    _selectedTenantName = null;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 24),
                            
                            // Line Items Section
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Các Mục Hóa Đơn',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                ElevatedButton.icon(
                                  onPressed: _showAddLineItemDialog,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Thêm Mục'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildLineItemsList(),
                            const SizedBox(height: 24),
                            
                            // Due Date
                            TextFormField(
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Hạn thanh toán *',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.calendar_today),
                                  onPressed: _selectDate,
                                ),
                              ),
                              controller: TextEditingController(
                                text: DateFormat('dd/MM/yyyy').format(_dueDate),
                              ),
                            ),
                            const SizedBox(height: 12),
                            
                            // Status
                            DropdownButtonFormField<PaymentStatus>(
                              value: _selectedPaymentStatus,
                              decoration: InputDecoration(
                                labelText: 'Trạng thái *',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: PaymentStatus.values.map((s) {
                                const labels = {
                                  'pending': 'Chờ thanh toán',
                                  'paid': 'Đã thanh toán',
                                  'overdue': 'Quá hạn',
                                  'cancelled': 'Đã hủy',
                                  'refunded': 'Đã hoàn tiền',
                                  'partial': 'Thanh toán 1 phần',
                                };
                                return DropdownMenuItem(value: s, child: Text(labels[s.toString().split('.')[1]] ?? ''));
                              }).toList(),
                              onChanged: (v) => setState(() => _selectedPaymentStatus = v!),
                            ),
                            const SizedBox(height: 12),
                            
                            // Notes
                            TextFormField(
                              controller: _notesController,
                              decoration: InputDecoration(
                                labelText: 'Ghi chú',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                
                const Divider(height: 1),
                
                // Footer Buttons
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Hủy'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _savePayment,
                          child: const Text('Lưu'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}