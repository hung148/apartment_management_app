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
  
  // Billing period (for rent, water)
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
  late TextEditingController _taxAmountController;
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
  
  // List of invoice line items
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
    _taxAmountController = TextEditingController(text: '0.0');
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
        _selectedRoomId = null;
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

  // Show dialog to add a line item with meter readings support
  Future<void> _showAddLineItemDialog() async {
    PaymentType? selectedType;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    
    // Electricity fields
    final electricityStartReadingController = TextEditingController();
    DateTime? electricityStartDate;
    final electricityEndReadingController = TextEditingController();
    DateTime? electricityEndDate;
    final electricityPriceController = TextEditingController();
    
    // Water fields
    final waterStartReadingController = TextEditingController();
    DateTime? waterStartDate;
    final waterEndReadingController = TextEditingController();
    DateTime? waterEndDate;
    final waterPriceController = TextEditingController();
    
    // Billing period fields
    DateTime? billingStart;
    DateTime? billingEnd;
    
    // Load last readings if room is selected
    if (_selectedRoomId != null) {
      final lastElecReading = await widget.paymentService.getLastElectricityReading(_selectedRoomId!);
      final lastWaterReading = await widget.paymentService.getLastWaterReading(_selectedRoomId!);
      
      if (lastElecReading != null) {
        electricityStartReadingController.text = lastElecReading['reading']?.toString() ?? '';
        electricityStartDate = lastElecReading['date'];
        electricityPriceController.text = lastElecReading['pricePerUnit']?.toString() ?? '';
      }
      
      if (lastWaterReading != null) {
        waterStartReadingController.text = lastWaterReading['reading']?.toString() ?? '';
        waterStartDate = lastWaterReading['date'];
        waterPriceController.text = lastWaterReading['pricePerUnit']?.toString() ?? '';
      }
    }
    
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Auto-calculate amount for electricity and water
          void calculateAmount() {
            if (selectedType == PaymentType.electricity) {
              final startReading = double.tryParse(electricityStartReadingController.text) ?? 0;
              final endReading = double.tryParse(electricityEndReadingController.text) ?? 0;
              final price = double.tryParse(electricityPriceController.text) ?? 0;
              final usage = endReading - startReading;
              if (usage > 0 && price > 0) {
                amountController.text = (usage * price).toStringAsFixed(0);
              }
            } else if (selectedType == PaymentType.water) {
              final startReading = double.tryParse(waterStartReadingController.text) ?? 0;
              final endReading = double.tryParse(waterEndReadingController.text) ?? 0;
              final price = double.tryParse(waterPriceController.text) ?? 0;
              final usage = endReading - startReading;
              if (usage > 0 && price > 0) {
                amountController.text = (usage * price).toStringAsFixed(0);
              }
            }
          }
          
          return AlertDialog(
            title: const Text('Thêm Mục Hóa Đơn'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Payment Type
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
                        child: Text(labels[t.name] ?? ''),
                      );
                    }).toList(),
                    onChanged: (v) => setDialogState(() => selectedType = v),
                  ),
                  const SizedBox(height: 16),
                  
                  // Electricity Fields
                  if (selectedType == PaymentType.electricity) ...[
                    const Text(
                      'Chỉ số điện',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: electricityStartReadingController,
                            decoration: InputDecoration(
                              labelText: 'Chỉ số đầu *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Từ ngày',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today, size: 20),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: electricityStartDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => electricityStartDate = picked);
                                  }
                                },
                              ),
                            ),
                            controller: TextEditingController(
                              text: electricityStartDate != null 
                                  ? DateFormat('dd/MM/yyyy').format(electricityStartDate!) 
                                  : '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: electricityEndReadingController,
                            decoration: InputDecoration(
                              labelText: 'Chỉ số cuối *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Đến ngày',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today, size: 20),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: electricityEndDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => electricityEndDate = picked);
                                  }
                                },
                              ),
                            ),
                            controller: TextEditingController(
                              text: electricityEndDate != null 
                                  ? DateFormat('dd/MM/yyyy').format(electricityEndDate!) 
                                  : '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: electricityPriceController,
                      decoration: InputDecoration(
                        labelText: 'Giá điện (VND/kWh) *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => calculateAmount(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Water Fields
                  if (selectedType == PaymentType.water) ...[
                    const Text(
                      'Chỉ số nước',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: waterStartReadingController,
                            decoration: InputDecoration(
                              labelText: 'Chỉ số đầu *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Từ ngày',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today, size: 20),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: waterStartDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => waterStartDate = picked);
                                  }
                                },
                              ),
                            ),
                            controller: TextEditingController(
                              text: waterStartDate != null 
                                  ? DateFormat('dd/MM/yyyy').format(waterStartDate!) 
                                  : '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: waterEndReadingController,
                            decoration: InputDecoration(
                              labelText: 'Chỉ số cuối *',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Đến ngày',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today, size: 20),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: waterEndDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now(),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => waterEndDate = picked);
                                  }
                                },
                              ),
                            ),
                            controller: TextEditingController(
                              text: waterEndDate != null 
                                  ? DateFormat('dd/MM/yyyy').format(waterEndDate!) 
                                  : '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: waterPriceController,
                      decoration: InputDecoration(
                        labelText: 'Giá nước (VND/m³) *',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => calculateAmount(),
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Billing Period (for Rent and Water)
                  if (selectedType == PaymentType.rent || selectedType == PaymentType.water) ...[
                    const Text(
                      'Kỳ thanh toán',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Từ ngày',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today, size: 20),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: billingStart ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => billingStart = picked);
                                  }
                                },
                              ),
                            ),
                            controller: TextEditingController(
                              text: billingStart != null 
                                  ? DateFormat('dd/MM/yyyy').format(billingStart!) 
                                  : '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Đến ngày',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.calendar_today, size: 20),
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: billingEnd ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) {
                                    setDialogState(() => billingEnd = picked);
                                  }
                                },
                              ),
                            ),
                            controller: TextEditingController(
                              text: billingEnd != null 
                                  ? DateFormat('dd/MM/yyyy').format(billingEnd!) 
                                  : '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Amount
                  TextFormField(
                    controller: amountController,
                    decoration: InputDecoration(
                      labelText: 'Số tiền *',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixText: 'VND',
                    ),
                    keyboardType: TextInputType.number,
                    readOnly: selectedType == PaymentType.electricity || selectedType == PaymentType.water,
                  ),
                  const SizedBox(height: 16),
                  
                  // Description
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
                      final result = <String, dynamic>{
                        'type': selectedType!,
                        'amount': amount,
                        'description': descriptionController.text.isEmpty ? null : descriptionController.text,
                      };
                      
                      // Add electricity data
                      if (selectedType == PaymentType.electricity) {
                        result['electricityStartReading'] = double.tryParse(electricityStartReadingController.text);
                        result['electricityStartDate'] = electricityStartDate;
                        result['electricityEndReading'] = double.tryParse(electricityEndReadingController.text);
                        result['electricityEndDate'] = electricityEndDate;
                        result['electricityPricePerUnit'] = double.tryParse(electricityPriceController.text);
                      }
                      
                      // Add water data
                      if (selectedType == PaymentType.water) {
                        result['waterStartReading'] = double.tryParse(waterStartReadingController.text);
                        result['waterStartDate'] = waterStartDate;
                        result['waterEndReading'] = double.tryParse(waterEndReadingController.text);
                        result['waterEndDate'] = waterEndDate;
                        result['waterPricePerUnit'] = double.tryParse(waterPriceController.text);
                      }
                      
                      // Add billing period
                      if (selectedType == PaymentType.rent || selectedType == PaymentType.water) {
                        result['billingStartDate'] = billingStart;
                        result['billingEndDate'] = billingEnd;
                      }
                      
                      Navigator.pop(context, result);
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
          electricityStartReading: result['electricityStartReading'] as double?,
          electricityStartDate: result['electricityStartDate'] as DateTime?,
          electricityEndReading: result['electricityEndReading'] as double?,
          electricityEndDate: result['electricityEndDate'] as DateTime?,
          electricityPricePerUnit: result['electricityPricePerUnit'] as double?,
          waterStartReading: result['waterStartReading'] as double?,
          waterStartDate: result['waterStartDate'] as DateTime?,
          waterEndReading: result['waterEndReading'] as double?,
          waterEndDate: result['waterEndDate'] as DateTime?,
          waterPricePerUnit: result['waterPricePerUnit'] as double?,
          billingStartDate: result['billingStartDate'] as DateTime?,
          billingEndDate: result['billingEndDate'] as DateTime?,
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
          final typeLabel = labels[item.type.name] ?? item.type.name;
          
          // Build detailed description
          String detailText = '';
          if (item.type == PaymentType.electricity && item.electricityStartReading != null) {
            final usage = (item.electricityEndReading ?? 0) - (item.electricityStartReading ?? 0);
            detailText = 'Từ ${item.electricityStartReading} đến ${item.electricityEndReading} (${usage.toStringAsFixed(1)} kWh)';
          } else if (item.type == PaymentType.water && item.waterStartReading != null) {
            final usage = (item.waterEndReading ?? 0) - (item.waterStartReading ?? 0);
            detailText = 'Từ ${item.waterStartReading} đến ${item.waterEndReading} (${usage.toStringAsFixed(1)} m³)';
          } else if (item.billingStartDate != null && item.billingEndDate != null) {
            detailText = '${DateFormat('dd/MM').format(item.billingStartDate!)} - ${DateFormat('dd/MM/yyyy').format(item.billingEndDate!)}';
          } else if (item.description != null) {
            detailText = item.description!;
          }
          
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
              subtitle: detailText.isNotEmpty 
                  ? Text(detailText, style: const TextStyle(fontSize: 12))
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
      // If there's only one line item, create a single payment with full details
      if (_lineItems.length == 1) {
        final item = _lineItems.first;
        
        final payment = Payment(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          organizationId: widget.organization.id,
          buildingId: _selectedBuildingId!,
          roomId: _selectedRoomId!,
          tenantId: _selectedTenantId,
          tenantName: _selectedTenantName ?? 'Unknown',
          type: item.type,
          status: _selectedPaymentStatus ?? PaymentStatus.pending,
          amount: item.amount,
          paidAmount: double.parse(_paidAmountController.text),
          currency: _currencyController.text,
          paymentMethod: _selectedPaymentMethod,
          transactionId: _transactionIdController.text.isEmpty ? null : _transactionIdController.text,
          receiptNumber: _receiptNumberController.text.isEmpty ? null : _receiptNumberController.text,
          billingStartDate: item.billingStartDate,
          billingEndDate: item.billingEndDate,
          dueDate: _dueDate!,
          electricityStartReading: item.electricityStartReading,
          electricityStartDate: item.electricityStartDate,
          electricityEndReading: item.electricityEndReading,
          electricityEndDate: item.electricityEndDate,
          electricityPricePerUnit: item.electricityPricePerUnit,
          waterStartReading: item.waterStartReading,
          waterStartDate: item.waterStartDate,
          waterEndReading: item.waterEndReading,
          waterEndDate: item.waterEndDate,
          waterPricePerUnit: item.waterPricePerUnit,
          createdAt: DateTime.now(),
          paidAt: _paidAt,
          paidBy: null,
          description: item.description,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          metadata: null,
          lateFee: _lateFeeController.text.isEmpty ? null : double.parse(_lateFeeController.text),
          taxAmount: _taxAmountController.text.isEmpty ? null : double.parse(_taxAmountController.text),
          isRecurring: _isRecurring,
          recurringParentId: _recurringParentIdController.text.isEmpty ? null : _recurringParentIdController.text,
        );

        await widget.paymentService.addPayment(payment);
      } else {
        // Multiple line items: create a combined payment with description
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
          final typeLabel = labels[item.type.name] ?? item.type.name;
          final desc = item.description != null ? ' (${item.description})' : '';
          return '${typeLabel}: ${NumberFormat('#,###').format(item.amount)} VND$desc';
        }).join('\n');

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
          amount: _totalAmount,
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
          description: lineItemsDescription,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          metadata: null,
          lateFee: _lateFeeController.text.isEmpty ? null : double.parse(_lateFeeController.text),
          taxAmount: _taxAmountController.text.isEmpty ? null : double.parse(_taxAmountController.text),
          isRecurring: _isRecurring,
          recurringParentId: _recurringParentIdController.text.isEmpty ? null : _recurringParentIdController.text,
        );

        await widget.paymentService.addPayment(payment);
      }
      
      if (mounted) {
        print('ImprovedPaymentFormDialog: Payment saved successfully, returning true');
        Navigator.pop(context, true);
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
    _taxAmountController.dispose();
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
                                return DropdownMenuItem(value: s, child: Text(labels[s.name] ?? ''));
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
                            const SizedBox(height: 12),
                            
                            // Tax Amount
                            TextFormField(
                              controller: _taxAmountController,
                              decoration: InputDecoration(
                                labelText: 'Tiền thuế (VND)',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) {
                                if (v!.isNotEmpty) {
                                  try {
                                    double.parse(v);
                                  } catch (e) {
                                    return 'Vui lòng nhập số hợp lệ';
                                  }
                                }
                                return null;
                              },
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