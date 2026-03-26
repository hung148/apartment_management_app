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
import 'package:apartment_management_project_2/utils/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ─── InvoiceLineItem (unchanged) ──────────────────────────────────────────────
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

// ─── Widget ───────────────────────────────────────────────────────────────────
class ImprovedPaymentFormDialog extends StatefulWidget {
  final Organization organization;
  final BuildingService buildingService;
  final RoomService roomService;
  final TenantService tenantService;
  final PaymentService paymentService;
  final Room? room;

  const ImprovedPaymentFormDialog({
    super.key,
    required this.organization,
    required this.buildingService,
    required this.roomService,
    required this.tenantService,
    required this.paymentService,
    this.room,
  });

  @override
  State<ImprovedPaymentFormDialog> createState() =>
      _ImprovedPaymentFormDialogState();
}

class _ImprovedPaymentFormDialogState extends State<ImprovedPaymentFormDialog>
    with WidgetsBindingObserver {
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
  List<Tenant> _allTenants = [];
  List<Tenant> _availableTenants = [];
  List<InvoiceLineItem> _lineItems = [];

  double get _totalAmount =>
      _lineItems.fold(0.0, (sum, item) => sum + item.amount);

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /// Translate a [PaymentType] to its display label.
  String _typeLabel(AppTranslations t, PaymentType type) {
    const keyMap = {
      'rent': 'payment_type_rent',
      'electricity': 'payment_type_electricity',
      'water': 'payment_type_water',
      'internet': 'payment_type_internet',
      'parking': 'payment_type_parking',
      'maintenance': 'payment_type_maintenance',
      'deposit': 'payment_type_deposit',
      'penalty': 'payment_type_penalty',
      'other': 'payment_type_other',
    };
    return t[keyMap[type.name] ?? type.name];
  }

  /// Translate a [PaymentStatus] to its display label.
  String _statusLabel(AppTranslations t, PaymentStatus s) {
    const keyMap = {
      'pending': 'status_pending',
      'paid': 'status_paid',
      'overdue': 'status_overdue',
      'cancelled': 'status_cancelled',
      'refunded': 'status_refunded',
      'partial': 'status_partial',
    };
    return t[keyMap[s.name] ?? s.name];
  }

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

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

    if (widget.room != null) {
      _selectedBuildingId = widget.room!.buildingId;
      _selectedRoomId = widget.room!.id;
    }

    _loadData();
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

  // ─── Data loading ────────────────────────────────────────────────────────────

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        widget.buildingService.getOrganizationBuildings(widget.organization.id),
        widget.roomService.getOrganizationRooms(widget.organization.id),
        widget.tenantService.getOrganizationTenants(widget.organization.id),
      ]);

      setState(() {
        _buildings = results[0] as List<Building>;
        _rooms = results[1] as List<Room>;

        final allOrgTenants = (results[2] as List<Tenant>)
            .where((t) => t.status == TenantStatus.active)
            .toList();

        if (widget.room != null) {
          _allTenants =
              allOrgTenants.where((t) => t.roomId == widget.room!.id).toList();
          _availableTenants = _allTenants;
          if (_allTenants.length == 1) {
            _selectedTenantId = _allTenants.first.id;
            _selectedTenantName = _allTenants.first.fullName;
          }
        } else {
          _allTenants = allOrgTenants;
          _availableTenants = _allTenants;
        }
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
  }

  // ─── Tenant selection ────────────────────────────────────────────────────────

  void _onTenantSelected(String? tenantId) {
    final t = AppTranslations.of(context);

    if (tenantId == null) {
      setState(() {
        _selectedTenantId = null;
        _selectedTenantName = null;
        if (widget.room == null) {
          _selectedBuildingId = null;
          _selectedRoomId = null;
        }
      });
      return;
    }

    final tenant = _allTenants.firstWhere((t) => t.id == tenantId);

    setState(() {
      _selectedTenantId = tenantId;
      _selectedTenantName = tenant.fullName;
      if (widget.room == null) {
        _selectedBuildingId = tenant.buildingId;
        _selectedRoomId = tenant.roomId;
      }
    });

    if ((tenant.monthlyRent ?? 0) > 0 && _lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(t.textWithParams('payment_rent_suggestion',
              {'amount': NumberFormat('#,###').format(tenant.monthlyRent)})),
          action: SnackBarAction(
            label: t['payment_suggestion_add'],
            onPressed: () {
              setState(() {
                _lineItems.add(InvoiceLineItem(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  type: PaymentType.rent,
                  amount: tenant.monthlyRent ?? 0,
                  description: t.textWithParams('payment_rent_month_desc', {
                    'month': DateTime.now().month,
                    'year': DateTime.now().year,
                  }),
                ));
              });
            },
          ),
        ),
      );
    }
  }

  Future<void> _loadRooms() async {
    if (_selectedBuildingId == null) return;
    final t = AppTranslations.of(context);
    try {
      final rooms = await widget.roomService
          .getBuildingRooms(_selectedBuildingId!, widget.organization.id);
      setState(() {
        _rooms = rooms;
        if (widget.room == null) {
          _selectedRoomId = null;
          _selectedTenantId = null;
          _selectedTenantName = null;
          _availableTenants = [];
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                t.textWithParams('payment_err_load_rooms', {'error': e}))));
      }
    }
  }

  Future<void> _loadTenantsForRoom() async {
    final t = AppTranslations.of(context);

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
      final filtered =
          _allTenants.where((tn) => tn.roomId == _selectedRoomId).toList();

      setState(() {
        _availableTenants = filtered;
        if (_availableTenants.length == 1) {
          _selectedTenantId = _availableTenants.first.id;
          _selectedTenantName = _availableTenants.first.fullName;
        } else if (widget.room == null) {
          _selectedTenantId = null;
          _selectedTenantName = null;
        }
      });

      if (mounted) {
        if (_availableTenants.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t['payment_no_tenants_room']),
            duration: const Duration(seconds: 2),
          ));
        } else if (_availableTenants.length == 1) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t.textWithParams(
                'payment_auto_selected', {'name': _availableTenants.first.fullName})),
            duration: const Duration(seconds: 2),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                t.textWithParams('payment_err_load_tenants', {'error': e}))));
      }
    }
  }

  // ─── Add line item dialog ────────────────────────────────────────────────────

  Future<void> _showAddLineItemDialog() async {
    final t = AppTranslations.of(context);
    PaymentType? selectedType;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    final electricityStartReadingController = TextEditingController();
    DateTime? electricityStartDate;
    final electricityEndReadingController = TextEditingController();
    DateTime? electricityEndDate;
    final electricityPriceController = TextEditingController();

    final waterStartReadingController = TextEditingController();
    DateTime? waterStartDate;
    final waterEndReadingController = TextEditingController();
    DateTime? waterEndDate;
    final waterPriceController = TextEditingController();

    DateTime? billingStart;
    DateTime? billingEnd;

    if (_selectedRoomId != null) {
      final lastElec = await widget.paymentService
          .getLastElectricityReading(_selectedRoomId!, widget.organization.id);
      final lastWater = await widget.paymentService
          .getLastWaterReading(_selectedRoomId!, widget.organization.id);

      if (lastElec != null) {
        electricityStartReadingController.text =
            lastElec['reading']?.toString() ?? '';
        electricityStartDate = lastElec['date'];
        electricityPriceController.text =
            lastElec['pricePerUnit']?.toString() ?? '';
      }
      if (lastWater != null) {
        waterStartReadingController.text =
            lastWater['reading']?.toString() ?? '';
        waterStartDate = lastWater['date'];
        waterPriceController.text =
            lastWater['pricePerUnit']?.toString() ?? '';
      }
    }

    final result = await _showTrackedDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Capture translations inside the dialog builder so it picks up
          // the dialog's inherited locale correctly.
          final dt = AppTranslations.of(context);

          void calculateAmount() {
            if (selectedType == PaymentType.electricity) {
              final start =
                  double.tryParse(electricityStartReadingController.text) ?? 0;
              final end =
                  double.tryParse(electricityEndReadingController.text) ?? 0;
              final price =
                  double.tryParse(electricityPriceController.text) ?? 0;
              final usage = end - start;
              if (usage > 0 && price > 0) {
                amountController.text = (usage * price).toStringAsFixed(0);
              }
            } else if (selectedType == PaymentType.water) {
              final start =
                  double.tryParse(waterStartReadingController.text) ?? 0;
              final end =
                  double.tryParse(waterEndReadingController.text) ?? 0;
              final price =
                  double.tryParse(waterPriceController.text) ?? 0;
              final usage = end - start;
              if (usage > 0 && price > 0) {
                amountController.text = (usage * price).toStringAsFixed(0);
              }
            }
          }

          return AlertDialog(
            title: Text(dt['add_item_dialog_title']),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Payment Type
                  DropdownButtonFormField<PaymentType>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      labelText: dt['add_item_type_label'],
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    items: PaymentType.values
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(_typeLabel(dt, type)),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedType = v),
                  ),
                  const SizedBox(height: 16),

                  // Electricity fields
                  if (selectedType == PaymentType.electricity) ...[
                    Text(dt['add_item_elec_title'],
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: electricityStartReadingController,
                            maxLength: 10,
                            decoration: InputDecoration(
                              counterText: '',
                              labelText: dt['add_item_start_reading'],
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: dt['add_item_from_date'],
                            initialDate: electricityStartDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) => setDialogState(
                                () => electricityStartDate = date),
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
                            maxLength: 10,
                            decoration: InputDecoration(
                              counterText: '',
                              labelText: dt['add_item_end_reading'],
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: dt['add_item_to_date'],
                            initialDate: electricityEndDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) => setDialogState(() {
                              electricityEndDate = date;
                              calculateAmount();
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: electricityPriceController,
                      maxLength: 15,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: dt['add_item_elec_price'],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => calculateAmount(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Water fields
                  if (selectedType == PaymentType.water) ...[
                    Text(dt['add_item_water_title'],
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: waterStartReadingController,
                            maxLength: 10,
                            decoration: InputDecoration(
                              counterText: '',
                              labelText: dt['add_item_start_reading'],
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: dt['add_item_from_date'],
                            initialDate: waterStartDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) =>
                                setDialogState(() => waterStartDate = date),
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
                            maxLength: 10,
                            decoration: InputDecoration(
                              counterText: '',
                              labelText: dt['add_item_end_reading'],
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            keyboardType: TextInputType.number,
                            onChanged: (_) => calculateAmount(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: dt['add_item_to_date'],
                            initialDate: waterEndDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            onDateChanged: (date) => setDialogState(() {
                              waterEndDate = date;
                              calculateAmount();
                            }),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: waterPriceController,
                      maxLength: 15,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: InputDecoration(
                        counterText: '',
                        labelText: dt['add_item_water_price'],
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => calculateAmount(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Billing period (rent or water)
                  if (selectedType == PaymentType.rent ||
                      selectedType == PaymentType.water) ...[
                    Text(dt['add_item_billing_period'],
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: dt['add_item_from_date'],
                            initialDate: billingStart,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            onDateChanged: (date) =>
                                setDialogState(() => billingStart = date),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CompactLocalizedDatePicker(
                            labelText: dt['add_item_to_date'],
                            initialDate: billingEnd,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            onDateChanged: (date) =>
                                setDialogState(() => billingEnd = date),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Amount
                  TextFormField(
                    controller: amountController,
                    maxLength: 20,
                    inputFormatters: [CurrencyInputFormatter()],
                    decoration: InputDecoration(
                      counterText: '',
                      labelText: dt['add_item_amount'],
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      suffixText: 'VND',
                    ),
                    keyboardType: TextInputType.number,
                    readOnly: selectedType == PaymentType.electricity ||
                        selectedType == PaymentType.water,
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextFormField(
                    controller: descriptionController,
                    maxLength: 200,
                    decoration: InputDecoration(
                      counterText: '',
                      labelText: dt['add_item_description'],
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: Text(dt['add_item_btn_cancel']),
              ),
              ElevatedButton(
                onPressed: () {
                  if (selectedType != null &&
                      amountController.text.isNotEmpty) {
                    final amount =
                        double.tryParse(amountController.text);
                    if (amount != null && amount > 0) {
                      final res = <String, dynamic>{
                        'type': selectedType!,
                        'amount': amount,
                        'description': descriptionController.text.isEmpty
                            ? null
                            : descriptionController.text,
                      };
                      if (selectedType == PaymentType.electricity) {
                        res['electricityStartReading'] = double.tryParse(
                            electricityStartReadingController.text);
                        res['electricityStartDate'] = electricityStartDate;
                        res['electricityEndReading'] = double.tryParse(
                            electricityEndReadingController.text);
                        res['electricityEndDate'] = electricityEndDate;
                        res['electricityPricePerUnit'] =
                            double.tryParse(electricityPriceController.text);
                      }
                      if (selectedType == PaymentType.water) {
                        res['waterStartReading'] = double.tryParse(
                            waterStartReadingController.text);
                        res['waterStartDate'] = waterStartDate;
                        res['waterEndReading'] =
                            double.tryParse(waterEndReadingController.text);
                        res['waterEndDate'] = waterEndDate;
                        res['waterPricePerUnit'] =
                            double.tryParse(waterPriceController.text);
                      }
                      if (selectedType == PaymentType.rent ||
                          selectedType == PaymentType.water) {
                        res['billingStartDate'] = billingStart;
                        res['billingEndDate'] = billingEnd;
                      }
                      Navigator.pop(context, res);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(dt['add_item_err_amount'])));
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(dt['add_item_err_required'])));
                  }
                },
                child: Text(dt['add_item_btn_add']),
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
          electricityStartReading:
              result['electricityStartReading'] as double?,
          electricityStartDate: result['electricityStartDate'] as DateTime?,
          electricityEndReading: result['electricityEndReading'] as double?,
          electricityEndDate: result['electricityEndDate'] as DateTime?,
          electricityPricePerUnit:
              result['electricityPricePerUnit'] as double?,
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

  // ─── Line items list ─────────────────────────────────────────────────────────

  void _removeLineItem(String id) {
    setState(() => _lineItems.removeWhere((item) => item.id == id));
  }

  Widget _buildLineItemsList(AppTranslations t) {
    if (_lineItems.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.receipt_long, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 8),
              Text(t['payment_items_empty'],
                  style: TextStyle(color: Colors.grey[600])),
              const SizedBox(height: 8),
              Text(t['payment_items_empty_hint'],
                  style:
                      TextStyle(color: Colors.grey[500], fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        ...List.generate(_lineItems.length, (index) {
          final item = _lineItems[index];
          final typeLabel = _typeLabel(t, item.type);

          String detailText = '';
          if (item.type == PaymentType.electricity &&
              item.electricityStartReading != null) {
            final usage = (item.electricityEndReading ?? 0) -
                (item.electricityStartReading ?? 0);
            detailText = t.textWithParams('line_item_elec_detail', {
              'start': item.electricityStartReading,
              'end': item.electricityEndReading,
              'usage': usage.toStringAsFixed(1),
            });
          } else if (item.type == PaymentType.water &&
              item.waterStartReading != null) {
            final usage = (item.waterEndReading ?? 0) -
                (item.waterStartReading ?? 0);
            detailText = t.textWithParams('line_item_water_detail', {
              'start': item.waterStartReading,
              'end': item.waterEndReading,
              'usage': usage.toStringAsFixed(1),
            });
          } else if (item.billingStartDate != null &&
              item.billingEndDate != null) {
            detailText =
                '${DateFormat('dd/MM').format(item.billingStartDate!)} - '
                '${DateFormat('dd/MM/yyyy').format(item.billingEndDate!)}';
          } else if (item.description != null) {
            detailText = item.description!;
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).primaryColor.withOpacity(0.1),
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
                  ? Text(detailText,
                      style: const TextStyle(fontSize: 12))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${NumberFormat('#,###').format(item.amount)} đ',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
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
          padding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t['payment_total_label'],
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              Text(
                '${NumberFormat('#,###').format(_totalAmount)} VND',
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

  // ─── Save ────────────────────────────────────────────────────────────────────

  Future<void> _savePayment() async {
    final t = AppTranslations.of(context);

    if (!_formKey.currentState!.validate() || _isSaving) return;
    setState(() => _isSaving = true);

    if (!_formKey.currentState!.validate()) return;

    if (_selectedBuildingId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t['payment_err_building'])));
      setState(() => _isSaving = false);
      return;
    }
    if (_selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t['payment_err_room'])));
      setState(() => _isSaving = false);
      return;
    }
    if (_lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t['payment_err_no_items'])));
      setState(() => _isSaving = false);
      return;
    }
    if (_dueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t['payment_err_due_date'])));
      setState(() => _isSaving = false);
      return;
    }

    try {
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
          transactionId: _transactionIdController.text.isEmpty
              ? null
              : _transactionIdController.text,
          receiptNumber: _receiptNumberController.text.isEmpty
              ? null
              : _receiptNumberController.text,
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
          lateFee: _lateFeeController.text.isEmpty
              ? null
              : double.parse(_lateFeeController.text),
          taxAmount: _taxAmountController.text.isEmpty
              ? null
              : double.parse(_taxAmountController.text),
          isRecurring: _isRecurring,
          recurringParentId: _recurringParentIdController.text.isEmpty
              ? null
              : _recurringParentIdController.text,
        );
        await widget.paymentService.addPayment(payment);
      } else {
        // Multiple line items — build combined description
        final lineItemsDescription = _lineItems.map((item) {
          final label = _typeLabel(t, item.type);
          final desc =
              item.description != null ? ' (${item.description})' : '';
          return '$label: ${NumberFormat('#,###').format(item.amount)} VND$desc';
        }).join('\n');

        final uniqueTypes = _lineItems.map((e) => e.type).toSet();
        final primaryType = uniqueTypes.length == 1
            ? _lineItems.first.type
            : PaymentType.other;

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
          transactionId: _transactionIdController.text.isEmpty
              ? null
              : _transactionIdController.text,
          receiptNumber: _receiptNumberController.text.isEmpty
              ? null
              : _receiptNumberController.text,
          billingStartDate: _billingStartDate,
          billingEndDate: _billingEndDate,
          dueDate: _dueDate!,
          createdAt: DateTime.now(),
          paidAt: _paidAt,
          paidBy: null,
          description: lineItemsDescription,
          notes: _notesController.text.isEmpty ? null : _notesController.text,
          metadata: null,
          lateFee: _lateFeeController.text.isEmpty
              ? null
              : double.parse(_lateFeeController.text),
          taxAmount: _taxAmountController.text.isEmpty
              ? null
              : double.parse(_taxAmountController.text),
          isRecurring: _isRecurring,
          recurringParentId: _recurringParentIdController.text.isEmpty
              ? null
              : _recurringParentIdController.text,
        );
        await widget.paymentService.addPayment(payment);
      }

      if (mounted && Navigator.of(context).canPop()) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t['payment_save_success'])));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                t.textWithParams('payment_save_error', {'error': e}))));
      }
    }
  }

  // ─── Resize / overlay helpers (unchanged logic) ───────────────────────────────

  Timer? _resizeDebounceTimer;
  bool _isDismissing = false;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer =
        Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final w = MediaQuery.sizeOf(context).width;
      final h = MediaQuery.sizeOf(context).height;
      if (w < 360 || h < 600) _dismissAllOverlays();
    });
  }

  Future<void> _dismissAllOverlays() async {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;
    try {
      final nav = Navigator.of(context);
      while (nav.canPop()) {
        nav.pop();
        await Future.delayed(const Duration(milliseconds: 50));
        if (!mounted) break;
      }
    } finally {
      _isDismissing = false;
    }
  }

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

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final bool isRoomMode = widget.room != null;
    final String dialogTitle = isRoomMode
        ? t.textWithParams(
            'payment_dialog_title_room', {'room': widget.room!.roomNumber})
        : t['payment_dialog_title'];

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        child: Text(dialogTitle,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 48, minHeight: 48),
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
                            // Tenant selection
                            if (isRoomMode)
                              DropdownButtonFormField<String>(
                                initialValue: _selectedTenantId,
                                decoration: InputDecoration(
                                  labelText: t['payment_select_tenant'],
                                  prefixIcon:
                                      const Icon(Icons.person),
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                ),
                                items: _availableTenants
                                    .map((tenant) =>
                                        DropdownMenuItem<String>(
                                          value: tenant.id,
                                          child: Text(
                                              '${tenant.fullName} (${tenant.phoneNumber})'),
                                        ))
                                    .toList(),
                                onChanged: _onTenantSelected,
                                validator: (v) => v == null
                                    ? t['payment_err_tenant']
                                    : null,
                              )
                            else
                              Autocomplete<Tenant>(
                                displayStringForOption: (Tenant tn) =>
                                    '${tn.fullName} (${tn.phoneNumber})',
                                optionsBuilder:
                                    (TextEditingValue value) {
                                  if (value.text.isEmpty) {
                                    return const Iterable<Tenant>.empty();
                                  }
                                  return _availableTenants.where((tn) =>
                                      tn.fullName.toLowerCase().contains(
                                          value.text.toLowerCase()) ||
                                      tn.phoneNumber
                                          .contains(value.text));
                                },
                                onSelected: (Tenant selection) =>
                                    _onTenantSelected(selection.id),
                                fieldViewBuilder: (context,
                                    textCtrl,
                                    focusNode,
                                    onFieldSubmitted) {
                                  return TextFormField(
                                    controller: textCtrl,
                                    focusNode: focusNode,
                                    decoration: InputDecoration(
                                      labelText:
                                          t['payment_search_tenant'],
                                      prefixIcon:
                                          const Icon(Icons.search),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      suffixIcon:
                                          textCtrl.text.isNotEmpty
                                              ? IconButton(
                                                  icon: const Icon(
                                                      Icons.clear),
                                                  onPressed: () {
                                                    textCtrl.clear();
                                                    _onTenantSelected(
                                                        null);
                                                  },
                                                )
                                              : null,
                                    ),
                                    validator: (v) =>
                                        _selectedTenantId == null
                                            ? t['payment_err_tenant']
                                            : null,
                                  );
                                },
                                optionsViewBuilder:
                                    (context, onSelected, options) {
                                  return Align(
                                    alignment: Alignment.topLeft,
                                    child: Material(
                                      elevation: 4.0,
                                      child: ConstrainedBox(
                                        constraints:
                                            const BoxConstraints(
                                                maxHeight: 200,
                                                maxWidth: 400),
                                        child: ListView.builder(
                                          padding: EdgeInsets.zero,
                                          shrinkWrap: true,
                                          itemCount: options.length,
                                          itemBuilder: (context, i) {
                                            final Tenant opt =
                                                options.elementAt(i);
                                            return ListTile(
                                              title: Text(opt.fullName),
                                              subtitle: Text(
                                                  t.textWithParams(
                                                      'payment_tenant_phone_prefix',
                                                      {'phone': opt.phoneNumber})),
                                              onTap: () =>
                                                  onSelected(opt),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(height: 16),

                            // Read-only building
                            TextFormField(
                              key: ValueKey(
                                  'building_$_selectedBuildingId'),
                              readOnly: true,
                              initialValue: _selectedBuildingId != null
                                  ? _buildings
                                      .firstWhere(
                                          (b) =>
                                              b.id == _selectedBuildingId,
                                          orElse: () => Building(
                                              id: '',
                                              address: 'N/A',
                                              name: 'N/A',
                                              organizationId: '',
                                              createdAt: DateTime.now()))
                                      .name
                                  : t['payment_building_unknown'],
                              decoration: InputDecoration(
                                labelText: t['payment_building_label'],
                                filled: true,
                                fillColor: Colors.grey[100],
                                prefixIcon:
                                    const Icon(Icons.business),
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Read-only room
                            TextFormField(
                              key: ValueKey('room_$_selectedRoomId'),
                              readOnly: true,
                              initialValue: _selectedRoomId != null
                                  ? _rooms
                                      .firstWhere(
                                          (r) => r.id == _selectedRoomId,
                                          orElse: () => Room(
                                              id: '',
                                              area: 0.0,
                                              roomType: '',
                                              organizationId: '',
                                              buildingId: '',
                                              roomNumber: 'N/A',
                                              createdAt: DateTime.now()))
                                      .roomNumber
                                  : t['payment_building_unknown'],
                              decoration: InputDecoration(
                                labelText: t['payment_room_label'],
                                filled: true,
                                fillColor: Colors.grey[100],
                                prefixIcon: const Icon(
                                    Icons.door_front_door),
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Line items header
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(t['payment_line_items_title'],
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                                ElevatedButton.icon(
                                  onPressed: _showAddLineItemDialog,
                                  icon: const Icon(Icons.add),
                                  label: Text(t['payment_add_item_btn']),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildLineItemsList(t),
                            const SizedBox(height: 24),

                            // Due date
                            LocalizedDatePicker(
                              labelText: t['payment_due_date_label'],
                              prefixIcon: Icons.event,
                              required: true,
                              initialDate: DateTime.now()
                                  .add(const Duration(days: 30)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now()
                                  .add(const Duration(days: 365)),
                              onDateChanged: (date) =>
                                  setState(() => _dueDate = date),
                              validator: (date) => date == null
                                  ? t['payment_err_due_date']
                                  : null,
                            ),
                            const SizedBox(height: 12),

                            // Status
                            DropdownButtonFormField<PaymentStatus>(
                              initialValue: _selectedPaymentStatus,
                              decoration: InputDecoration(
                                labelText: t['payment_status_label'],
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                              items: PaymentStatus.values
                                  .map((s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(_statusLabel(t, s)),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(
                                  () => _selectedPaymentStatus = v),
                            ),
                            const SizedBox(height: 12),

                            // Notes
                            TextFormField(
                              controller: _notesController,
                              maxLength: 500,
                              decoration: InputDecoration(
                                counterText: '',
                                labelText: t['payment_notes_label'],
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),

                            // Tax
                            TextFormField(
                              controller: _taxAmountController,
                              maxLength: 20,
                              inputFormatters: [CurrencyInputFormatter()],
                              decoration: InputDecoration(
                                counterText: '',
                                labelText: t['payment_tax_label'],
                                border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              validator: (v) {
                                if (v!.isNotEmpty) {
                                  try {
                                    double.parse(v);
                                  } catch (_) {
                                    return t['payment_err_number'];
                                  }
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 24),

                            // Action buttons
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context),
                                    child: Text(t['payment_btn_cancel']),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _savePayment,
                                    child: Text(t['payment_btn_save']),
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