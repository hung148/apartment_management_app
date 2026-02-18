import 'dart:async';

import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/models/rooms_model.dart';
import 'package:apartment_management_project_2/models/tenants_model.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';
import 'package:apartment_management_project_2/services/room_service.dart';
import 'package:apartment_management_project_2/services/tenants_service.dart';
import 'package:apartment_management_project_2/utils/currency_formatter.dart';
import 'package:apartment_management_project_2/widgets/date_picker.dart';
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
  final Room? room; // Optional: if provided, filter tenants to only this room

  const ImprovedPaymentFormDialog({
    super.key,
    required this.organization,
    required this.buildingService,
    required this.roomService,
    required this.tenantService,
    required this.paymentService,
    this.room, // Optional room parameter
  });

  @override
  State<ImprovedPaymentFormDialog> createState() => _ImprovedPaymentFormDialogState();
}

class _ImprovedPaymentFormDialogState extends State<ImprovedPaymentFormDialog> with WidgetsBindingObserver {
  // Track how many overlays (dialogs/bottom sheets) are currently open
  int _overlayCount = 0;
  bool _isSaving = false;

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
  List<Tenant> _allTenants = []; // All tenants (filtered by room if provided)
  List<Tenant> _availableTenants = []; // Currently available tenants for selection
  
  // List of invoice line items
  List<InvoiceLineItem> _lineItems = [];
  
  // Calculate total amount from all line items
  double get _totalAmount => _lineItems.fold(0.0, (sum, item) => sum + item.amount);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    
    // If room is provided, pre-select building and room
    if (widget.room != null) {
      _selectedBuildingId = widget.room!.buildingId;
      _selectedRoomId = widget.room!.id;
    }
    
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Load everything for the organization
      final results = await Future.wait([
        widget.buildingService.getOrganizationBuildings(widget.organization.id),
        widget.roomService.getOrganizationRooms(widget.organization.id),
        widget.tenantService.getOrganizationTenants(widget.organization.id),
      ]);

      setState(() {
        _buildings = results[0] as List<Building>;
        _rooms = results[1] as List<Room>;
        
        // Filter tenants based on whether a room was provided
        final allOrgTenants = (results[2] as List<Tenant>)
            .where((t) => t.status == TenantStatus.active)
            .toList();
        
        if (widget.room != null) {
          // If room is provided, only show tenants in that room
          _allTenants = allOrgTenants.where((t) => t.roomId == widget.room!.id).toList();
          _availableTenants = _allTenants;
          
          // Auto-select tenant if there's only one
          if (_allTenants.length == 1) {
            _selectedTenantId = _allTenants.first.id;
            _selectedTenantName = _allTenants.first.fullName;
          }
        } else {
          // If no room provided, show all active tenants
          _allTenants = allOrgTenants;
          _availableTenants = _allTenants;
        }
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
  }

  void _onTenantSelected(String? tenantId) {
    if (tenantId == null) {
      setState(() {
        _selectedTenantId = null;
        _selectedTenantName = null;
        // Only reset building/room if not pre-set by widget.room
        if (widget.room == null) {
          _selectedBuildingId = null;
          _selectedRoomId = null;
        }
      });
      return;
    }

    // Find the selected tenant
    final tenant = _allTenants.firstWhere((t) => t.id == tenantId);
    
    setState(() {
      _selectedTenantId = tenantId;
      _selectedTenantName = tenant.fullName;
      // Only update building/room if not pre-set by widget.room
      if (widget.room == null) {
        _selectedBuildingId = tenant.buildingId;
        _selectedRoomId = tenant.roomId;
      }
    });
    
    if ((tenant.monthlyRent ?? 0) > 0 && _lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gợi ý: Thêm mục tiền thuê ${NumberFormat('#,###').format(tenant.monthlyRent)}đ?'),
          action: SnackBarAction(
            label: 'Thêm ngay', 
            onPressed: () {
              setState(() {
                _lineItems.add(InvoiceLineItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  type: PaymentType.rent,
                  amount: tenant.monthlyRent ?? 0,
                  description: 'Tiền thuê tháng ${DateTime.now().month}/${DateTime.now().year}',
                ));
              });
            }
          ),
        )
      );
    }
  }

  Future<void> _loadRooms() async {
    if (_selectedBuildingId == null) return;
    try {
      final rooms = await widget.roomService.getBuildingRooms(_selectedBuildingId!, widget.organization.id);
      setState(() {
        _rooms = rooms;
        // Only reset room/tenant if not pre-set by widget.room
        if (widget.room == null) {
          _selectedRoomId = null;
          _selectedTenantId = null;
          _selectedTenantName = null;
          _availableTenants = [];
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải phòng: $e')),
        );
      }
    }
  }

  // Load tenants for selected room
  Future<void> _loadTenantsForRoom() async {
    if (_selectedRoomId == null) {
      setState(() {
        if (widget.room == null) {
          _availableTenants = [];
          _selectedTenantId = null;
          _selectedTenantName = null;
        }
      });
      return;
    }

    try {
      // Filter tenants based on the room
      final filteredTenants = _allTenants.where((tenant) {
        return tenant.roomId == _selectedRoomId;
      }).toList();
      
      setState(() {
        _availableTenants = filteredTenants;
        
        // Auto-select tenant if there's only one tenant in the room
        if (_availableTenants.length == 1) {
          _selectedTenantId = _availableTenants.first.id;
          _selectedTenantName = _availableTenants.first.fullName;
        } else if (widget.room == null) {
          // Only reset if not pre-set by widget.room
          _selectedTenantId = null;
          _selectedTenantName = null;
        }
      });
      
      // Show info message
      if (mounted) {
        if (_availableTenants.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không có người thuê nào trong phòng này'),
              duration: Duration(seconds: 2),
            ),
          );
        } else if (_availableTenants.length == 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã tự động chọn: ${_availableTenants.first.fullName}'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải người thuê: $e')),
        );
      }
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
    
    final result = await _showTrackedDialog<Map<String, dynamic>?>(
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
                    initialValue: selectedType,
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
                    
                    // Start reading and date
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
                          child: CompactLocalizedDatePicker(
                            labelText: 'Từ ngày',
                            initialDate: electricityStartDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) {
                              setDialogState(() => electricityStartDate = date);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // End reading and date
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
                          child: CompactLocalizedDatePicker(
                            labelText: 'Đến ngày',
                            initialDate: electricityEndDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) {
                              setDialogState(() {
                                electricityEndDate = date;
                                calculateAmount();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    TextFormField(
                      controller: electricityPriceController,
                      inputFormatters: [CurrencyInputFormatter()],
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
                    
                    // Start reading and date
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
                          child: CompactLocalizedDatePicker(
                            labelText: 'Từ ngày',
                            initialDate: waterStartDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) {
                              setDialogState(() => waterStartDate = date);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // End reading and date
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
                          child: CompactLocalizedDatePicker(
                            labelText: 'Đến ngày',
                            initialDate: waterEndDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) {
                              setDialogState(() {
                                waterEndDate = date;
                                calculateAmount();
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    TextFormField(
                      controller: waterPriceController,
                      inputFormatters: [CurrencyInputFormatter()],
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
                          child: CompactLocalizedDatePicker(
                            labelText: 'Từ ngày',
                            initialDate: billingStart,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            onDateChanged: (date) {
                              setDialogState(() => billingStart = date);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: 'Đến ngày',
                            initialDate: billingEnd,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            onDateChanged: (date) {
                              setDialogState(() => billingEnd = date);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  // Amount
                  TextFormField(
                    controller: amountController,
                    inputFormatters: [CurrencyInputFormatter()],
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
    if (!_formKey.currentState!.validate() || _isSaving) return; // Guard 1

    setState(() => _isSaving = true); // Start saving state

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
          // Safety check: only pop if the dialog is still active
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context, true);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã tạo hóa đơn thành công')),
            );
          }
        }
    } catch (e) {
      if (mounted) setState(() => _isSaving = false); // Reset on error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lưu hóa đơn: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  // Debounce timer for resize handling
  Timer? _resizeDebounceTimer;

  // Guard to prevent overlapping dismiss calls
  bool _isDismissing = false;

  // ─── Called whenever screen size / metrics change ───
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // Cancel any pending debounce before setting a new one
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final screenWidth = MediaQuery.sizeOf(context).width;
      final screenHeight = MediaQuery.sizeOf(context).height;
      if (screenWidth < 360 || screenHeight < 600) {
        _dismissAllOverlays();
      }
    });
  }

  // Pops all open dialogs/bottom sheets by popping until only the base route remains.
  Future<void> _dismissAllOverlays() async {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;

    try {
      final nav = Navigator.of(context);
      while (nav.canPop()) {
        nav.pop();
        // Yield to the framework between each pop so it can finish
        // destroying the previous overlay before we pop the next one.
        // This prevents back-to-back surface destruction that triggers EGL errors.
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) break;
      }
    } finally {
      _isDismissing = false;
    }
  }

  // ─── Overlay helpers ───

  Future<T?> _showTrackedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    _overlayCount++;
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    } finally {
      if (mounted) _overlayCount--;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // Determine if we're in "room mode" (showing only tenants from specific room)
    final bool isRoomMode = widget.room != null;
    final String dialogTitle = isRoomMode 
        ? 'Thêm Hóa Đơn - Phòng ${widget.room!.roomNumber}' 
        : 'Thêm Hóa Đơn';
    
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
                      Expanded(
                        child: Text(
                          dialogTitle,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                            // TENANT SELECTION - Filtered if room is provided
                            isRoomMode
                              ? // 1. Show a simple Dropdown if we are in a specific room
                              DropdownButtonFormField<String>(
                                  initialValue: _selectedTenantId,
                                  decoration: InputDecoration(
                                    labelText: 'Chọn người thuê *',
                                    prefixIcon: const Icon(Icons.person),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  items: _availableTenants.map((tenant) {
                                    return DropdownMenuItem<String>(
                                      value: tenant.id,
                                      child: Text('${tenant.fullName} (${tenant.phoneNumber})'),
                                    );
                                  }).toList(),
                                  onChanged: _onTenantSelected,
                                  validator: (v) => v == null ? 'Vui lòng chọn người thuê' : null,
                                )
                              : // 2. Show the Autocomplete search only if we are in organization-wide mode
                              Autocomplete<Tenant>(
                                  displayStringForOption: (Tenant t) => '${t.fullName} (${t.phoneNumber})',
                                  optionsBuilder: (TextEditingValue textEditingValue) {
                                    if (textEditingValue.text == '') {
                                      return const Iterable<Tenant>.empty();
                                    }
                                    return _availableTenants.where((Tenant t) {
                                      final nameMatches = t.fullName.toLowerCase().contains(textEditingValue.text.toLowerCase());
                                      final phoneMatches = t.phoneNumber.contains(textEditingValue.text);
                                      return nameMatches || phoneMatches;
                                    });
                                  },
                                  onSelected: (Tenant selection) {
                                    _onTenantSelected(selection.id);
                                  },
                                  fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                                    return TextFormField(
                                      controller: textEditingController,
                                      focusNode: focusNode,
                                      decoration: InputDecoration(
                                        labelText: 'Tìm người thuê (Tên hoặc SĐT) *',
                                        prefixIcon: const Icon(Icons.search),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        suffixIcon: textEditingController.text.isNotEmpty 
                                          ? IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () {
                                                textEditingController.clear();
                                                _onTenantSelected(null);
                                              },
                                            )
                                          : null,
                                      ),
                                      validator: (v) => _selectedTenantId == null ? 'Vui lòng chọn người thuê' : null,
                                    );
                                  },
                                  optionsViewBuilder: (context, onSelected, options) {
                                    return Align(
                                      alignment: Alignment.topLeft,
                                      child: Material(
                                        elevation: 4.0,
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 400),
                                          child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            shrinkWrap: true,
                                            itemCount: options.length,
                                            itemBuilder: (BuildContext context, int index) {
                                              final Tenant option = options.elementAt(index);
                                              return ListTile(
                                                title: Text(option.fullName),
                                                subtitle: Text('SĐT: ${option.phoneNumber}'),
                                                onTap: () => onSelected(option),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                          const SizedBox(height: 16),

                            // READ-ONLY BUILDING INFO
                            TextFormField(
                              key: ValueKey('building_$_selectedBuildingId'),
                              readOnly: true,
                              initialValue: _selectedBuildingId != null 
                                  ? _buildings.firstWhere((b) => b.id == _selectedBuildingId, orElse: () => Building(id: '', address: 'N/A', name: 'N/A', organizationId: '', createdAt: DateTime.now())).name
                                  : 'Chưa xác định',
                              decoration: InputDecoration(
                                labelText: 'Toà nhà',
                                filled: true,
                                fillColor: Colors.grey[100],
                                prefixIcon: const Icon(Icons.business),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // READ-ONLY ROOM INFO
                            TextFormField(
                              key: ValueKey('room_$_selectedRoomId'),
                              readOnly: true,
                              initialValue: _selectedRoomId != null 
                                  ? _rooms.firstWhere((r) => r.id == _selectedRoomId, orElse: () => Room(id: '', area: 0.0, roomType: '', organizationId: '', buildingId: '', roomNumber: 'N/A', createdAt: DateTime.now())).roomNumber
                                  : 'Chưa xác định',
                              decoration: InputDecoration(
                                labelText: 'Phòng',
                                filled: true,
                                fillColor: Colors.grey[100],
                                prefixIcon: const Icon(Icons.door_front_door),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),

                            const SizedBox(height: 12),
                            
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
                            LocalizedDatePicker(
                              labelText: 'Hạn thanh toán',
                              prefixIcon: Icons.event,
                              required: true,
                              initialDate: DateTime.now().add(const Duration(days: 30)), // Default: 30 days from now
                              firstDate: DateTime.now(), // Can't set due date in the past
                              lastDate: DateTime.now().add(const Duration(days: 365)), // Maximum 1 year ahead
                              onDateChanged: (date) {
                                setState(() {
                                  _dueDate = date;
                                });
                              },
                              validator: (date) {
                                if (date == null) {
                                  return 'Vui lòng chọn hạn thanh toán';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                            
                            // Status
                            DropdownButtonFormField<PaymentStatus>(
                              initialValue: _selectedPaymentStatus,
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
                              inputFormatters: [CurrencyInputFormatter()],
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