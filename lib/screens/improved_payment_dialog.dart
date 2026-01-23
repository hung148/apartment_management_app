import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
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

class ImprovedPaymentFormDialog extends StatefulWidget {
  final Organization organization;
  final BuildingService buildingService;
  final RoomService roomService;
  final TenantService tenantService;
  final PaymentService paymentService;

  const ImprovedPaymentFormDialog({
    super.key,
    required this.organization,
    required this.buildingService,
    required this.roomService,
    required this.tenantService,
    required this.paymentService,
  });

  @override
  State<ImprovedPaymentFormDialog> createState() => _ImprovedPaymentFormDialogState();
}

class _ImprovedPaymentFormDialogState extends State<ImprovedPaymentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _paidAmountController;
  late TextEditingController _currencyController;
  late TextEditingController _transactionIdController;
  late TextEditingController _receiptNumberController;
  late TextEditingController _descriptionController;
  late TextEditingController _notesController;
  late TextEditingController _lateFeeController;
  late TextEditingController _recurringParentIdController;

  String? _selectedBuildingId;
  String? _selectedRoomId;
  String? _selectedTenantId;
  String? _selectedTenantName;
  PaymentStatus? _selectedPaymentStatus;
  PaymentMethod? _selectedPaymentMethod;
  
  DateTime? _billingStartDate;
  DateTime? _billingEndDate;
  DateTime? _dueDate;
  DateTime? _paidAt;
  
  bool _isRecurring = false;

  List<Building> _buildings = [];
  List<Room> _rooms = [];
  List<Tenant> _tenants = [];
  
  // NEW: List of invoice line items
  List<InvoiceLineItem> _lineItems = [];
  
  // Calculate total amount from all line items
  double get _totalAmount => _lineItems.fold(0.0, (sum, item) => sum + item.amount);

  @override
  void initState() {
    super.initState();
    _paidAmountController = TextEditingController(text: '0.0');
    _currencyController = TextEditingController(text: 'VND');
    _transactionIdController = TextEditingController();
    _receiptNumberController = TextEditingController();
    _descriptionController = TextEditingController();
    _notesController = TextEditingController();
    _lateFeeController = TextEditingController(text: '0.0');
    _recurringParentIdController = TextEditingController();
    
    _selectedPaymentStatus = PaymentStatus.pending;
    _dueDate = DateTime.now().add(const Duration(days: 30));
    
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final buildings = await widget.buildingService.getOrganizationBuildings(widget.organization.id);
      final tenants = await widget.tenantService.getOrganizationTenants(widget.organization.id);
      
      setState(() {
        _buildings = buildings;
        _tenants = tenants;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
        );
      }
    }
  }

  Future<void> _loadRooms() async {
    if (_selectedBuildingId == null) return;
    try {
      final rooms = await widget.roomService.getBuildingRooms(_selectedBuildingId!);
      setState(() {
        _rooms = rooms;
        _selectedRoomId = null; // Reset room selection
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải phòng: $e')),
        );
      }
    }
  }

  Future<void> _selectDate(String dateType) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _getDueDate(dateType),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    
    if (picked != null) {
      setState(() {
        switch (dateType) {
          case 'billingStart':
            _billingStartDate = picked;
            break;
          case 'billingEnd':
            _billingEndDate = picked;
            break;
          case 'due':
            _dueDate = picked;
            break;
          case 'paid':
            _paidAt = picked;
            break;
        }
      });
    }
  }

  DateTime _getDueDate(String dateType) {
    switch (dateType) {
      case 'billingStart':
        return _billingStartDate ?? DateTime.now();
      case 'billingEnd':
        return _billingEndDate ?? DateTime.now();
      case 'due':
        return _dueDate ?? DateTime.now().add(const Duration(days: 30));
      case 'paid':
        return _paidAt ?? DateTime.now();
      default:
        return DateTime.now();
    }
  }

  // NEW: Show dialog to add a line item
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

  // NEW: Remove a line item
  void _removeLineItem(String id) {
    setState(() {
      _lineItems.removeWhere((item) => item.id == id);
    });
  }

  // NEW: Build line items list widget
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
              const SizedBox(height: 8),
              Text(
                'Nhấn nút "Thêm Mục" để bắt đầu',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
    
    if (_selectedBuildingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn toà nhà')),
      );
      return;
    }
    if (_selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn phòng')),
      );
      return;
    }
    if (_lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng thêm ít nhất một mục hóa đơn')),
      );
      return;
    }
    if (_dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn hạn thanh toán')),
      );
      return;
    }

    try {
      // Create a description from all line items
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

      // Use the first line item's type as the main type, or 'other' if multiple types
      final uniqueTypes = _lineItems.map((e) => e.type).toSet();
      final primaryType = uniqueTypes.length == 1 ? _lineItems.first.type : PaymentType.other;

      final payment = Payment(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        organizationId: widget.organization.id,
        buildingId: _selectedBuildingId!,
        roomId: _selectedRoomId!,
        tenantId: _selectedTenantId,
        tenantName: _selectedTenantName ?? 'Unknown',
        type: primaryType,
        status: _selectedPaymentStatus ?? PaymentStatus.pending,
        amount: _totalAmount, // Use the calculated total
        paidAmount: double.parse(_paidAmountController.text),
        currency: _currencyController.text,
        paymentMethod: _selectedPaymentMethod,
        transactionId: _transactionIdController.text.isEmpty ? null : _transactionIdController.text,
        receiptNumber: _receiptNumberController.text.isEmpty ? null : _receiptNumberController.text,
        billingStartDate: _billingStartDate,
        billingEndDate: _billingEndDate,
        dueDate: _dueDate!,
        createdAt: DateTime.now(),
        paidAt: _paidAt,
        paidBy: null,
        description: lineItemsDescription, // Save line items as description
        notes: _notesController.text.isEmpty ? null : _notesController.text,
        metadata: null,
        lateFee: _lateFeeController.text.isEmpty ? null : double.parse(_lateFeeController.text),
        isRecurring: _isRecurring,
        recurringParentId: _recurringParentIdController.text.isEmpty ? null : _recurringParentIdController.text,
      );

      await widget.paymentService.addPayment(payment);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã tạo hóa đơn thành công')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lưu hóa đơn: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _paidAmountController.dispose();
    _currencyController.dispose();
    _transactionIdController.dispose();
    _receiptNumberController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _lateFeeController.dispose();
    _recurringParentIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth,
              maxHeight: constraints.maxHeight,
            ),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Thêm Hóa Đơn',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
                            // Building Selection
                            DropdownButtonFormField<String>(
                              value: _selectedBuildingId,
                              decoration: InputDecoration(
                                labelText: 'Toà nhà *',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: _buildings.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
                              onChanged: (v) {
                                setState(() => _selectedBuildingId = v);
                                _loadRooms();
                              },
                              validator: (v) => v == null ? 'Chọn toà nhà' : null,
                            ),
                            const SizedBox(height: 12),
                            
                            // Room Selection
                            DropdownButtonFormField<String>(
                              value: _selectedRoomId,
                              decoration: InputDecoration(
                                labelText: 'Phòng *',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              items: _rooms.map((r) => DropdownMenuItem(value: r.id, child: Text(r.roomNumber ?? ''))).toList(),
                              onChanged: (v) => setState(() => _selectedRoomId = v),
                              validator: (v) => v == null ? 'Chọn phòng' : null,
                            ),
                            const SizedBox(height: 12),
                            
                            // Tenant Selection
                            DropdownButtonFormField<String?>(
                              value: _selectedTenantId,
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
                                  final tenant = _tenants.firstWhere((t) => t.id == v, orElse: () => _tenants.first);
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
                            
                            // NEW: Line Items Section
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
                                  onPressed: () => _selectDate('due'),
                                ),
                              ),
                              controller: TextEditingController(
                                text: _dueDate != null ? DateFormat('dd/MM/yyyy').format(_dueDate!) : '',
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
                              onChanged: (v) => setState(() => _selectedPaymentStatus = v),
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
                            const SizedBox(height: 24),
                            
                            // Action Buttons
                            Row(
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
                          ],
                        ),
                      ),
                    ),
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