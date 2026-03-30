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

// ─── Shared helpers (mirrors the View/Edit file) ──────────────────────────────

const _typeColors = <String, Color>{
  'rent': Color(0xFF6366F1),
  'electricity': Color(0xFFF59E0B),
  'water': Color(0xFF06B6D4),
  'internet': Color(0xFF8B5CF6),
  'parking': Color(0xFF10B981),
  'maintenance': Color(0xFFEF4444),
  'deposit': Color(0xFF3B82F6),
  'penalty': Color(0xFFDC2626),
  'other': Color(0xFF6B7280),
};

Color _typeColor(PaymentType type) =>
    _typeColors[type.name] ?? const Color(0xFF6B7280);

// ─── InvoiceLineItem ──────────────────────────────────────────────────────────

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

  Color _statusColor(PaymentStatus s) {
    switch (s) {
      case PaymentStatus.paid:
        return const Color(0xFF22C55E);
      case PaymentStatus.pending:
        return const Color(0xFFF59E0B);
      case PaymentStatus.overdue:
        return const Color(0xFFEF4444);
      case PaymentStatus.cancelled:
        return const Color(0xFF6B7280);
      case PaymentStatus.refunded:
        return const Color(0xFF3B82F6);
      case PaymentStatus.partial:
        return const Color(0xFFF97316);
    }
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
          duration: const Duration(seconds: 5),
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
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            },
          ),
          dismissDirection: DismissDirection.down,
          showCloseIcon: true,
        ),
      );
    }
  }

  // ─── Add line item dialog ────────────────────────────────────────────────────

  Future<void> _showAddLineItemDialog() async {
    final t = AppTranslations.of(context);
    PaymentType? selectedType;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    // Electricity fields
    final electricityStartReadingController = TextEditingController();
    DateTime? electricityStartDate;
    final electricityEndReadingController = TextEditingController();
    DateTime? electricityEndDate;
    final electricityPriceController = TextEditingController();
    // Toggle: true = enter amount directly, false = use meter readings
    bool electricityUseDirectAmount = false;

    // Water fields
    final waterStartReadingController = TextEditingController();
    DateTime? waterStartDate;
    final waterEndReadingController = TextEditingController();
    DateTime? waterEndDate;
    final waterPriceController = TextEditingController();
    // Toggle: true = enter amount directly, false = use meter readings
    bool waterUseDirectAmount = false;

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
          final dt = AppTranslations.of(context);

          void calculateAmount() {
            // Only auto-calculate when NOT in direct-amount mode
            if (selectedType == PaymentType.electricity &&
                !electricityUseDirectAmount) {
              final start =
                  double.tryParse(electricityStartReadingController.text) ?? 0;
              final end =
                  double.tryParse(electricityEndReadingController.text) ?? 0;
              final price = CurrencyParser.parse(electricityPriceController.text);
              final usage = end - start;
              if (usage > 0 && price > 0) {
                amountController.text = (usage * price).toStringAsFixed(0);
              }
            } else if (selectedType == PaymentType.water &&
                !waterUseDirectAmount) {
              final start =
                  double.tryParse(waterStartReadingController.text) ?? 0;
              final end = double.tryParse(waterEndReadingController.text) ?? 0;
              final price = CurrencyParser.parse(waterPriceController.text);
              final usage = end - start;
              if (usage > 0 && price > 0) {
                amountController.text = (usage * price).toStringAsFixed(0);
              }
            }
          }

          // ── Small helper: mode toggle chip ─────────────────────────────
          Widget _modeToggle({
            required bool useDirectAmount,
            required Color color,
            required IconData meterIcon,
            required String meterLabel,
            required String directLabel,
            required ValueChanged<bool> onChanged,
          }) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.18)),
              ),
              child: Row(children: [
                // Meter readings tab
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: !useDirectAmount
                            ? color.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(9)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(meterIcon,
                              size: 14,
                              color: !useDirectAmount
                                  ? color
                                  : Colors.grey.shade500),
                          const SizedBox(width: 5),
                          Text(
                            meterLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: !useDirectAmount
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: !useDirectAmount
                                  ? color
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Divider
                Container(
                    width: 1,
                    height: 28,
                    color: color.withValues(alpha: 0.18)),
                // Direct amount tab
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      onChanged(true);
                      // Clear auto-calculated amount so user starts fresh
                      amountController.clear();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: useDirectAmount
                            ? color.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(9)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.edit_rounded,
                              size: 14,
                              color: useDirectAmount
                                  ? color
                                  : Colors.grey.shade500),
                          const SizedBox(width: 5),
                          Text(
                            directLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: useDirectAmount
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: useDirectAmount
                                  ? color
                                  : Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            );
          }

          final typeColor =
              selectedType != null ? _typeColor(selectedType!) : Colors.grey;

          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 500,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Dialog header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.06),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).primaryColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.add_circle_outline_rounded,
                            color: Theme.of(context).primaryColor, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(dt['add_item_dialog_title'],
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context, null),
                      ),
                    ]),
                  ),

                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Type dropdown
                          DropdownButtonFormField<PaymentType>(
                            initialValue: selectedType,
                            decoration: _inputDec(
                                dt['add_item_type_label'], Icons.category_rounded),
                            items: PaymentType.values
                                .map((type) => DropdownMenuItem(
                                      value: type,
                                      child: Row(children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: _typeColor(type),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(_typeLabel(dt, type)),
                                      ]),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setDialogState(() => selectedType = v),
                          ),
                          const SizedBox(height: 16),

                          // ── Electricity fields ──────────────────────────
                          if (selectedType == PaymentType.electricity) ...[
                            _formSectionLabel(dt['add_item_elec_title'],
                                Icons.bolt_rounded, const Color(0xFFF59E0B)),
                            const SizedBox(height: 10),

                            // Mode toggle
                            _modeToggle(
                              useDirectAmount: electricityUseDirectAmount,
                              color: const Color(0xFFF59E0B),
                              meterIcon: Icons.electric_meter_rounded,
                              meterLabel: dt['add_item_mode_meter'],
                              directLabel: dt['add_item_mode_direct'],
                              onChanged: (val) => setDialogState(
                                  () => electricityUseDirectAmount = val),
                            ),

                            // Meter reading fields (hidden when direct mode)
                            if (!electricityUseDirectAmount) ...[
                              Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: electricityStartReadingController,
                                    maxLength: 10,
                                    decoration: _inputDec(
                                        dt['add_item_start_reading'], null,
                                        suffix: 'kWh'),
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) {
                                      setDialogState(() {});
                                      calculateAmount();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
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
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: electricityEndReadingController,
                                    maxLength: 10,
                                    decoration: _inputDec(
                                        dt['add_item_end_reading'], null,
                                        suffix: 'kWh'),
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) {
                                      setDialogState(() {});
                                      calculateAmount();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
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
                              ]),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: electricityPriceController,
                                maxLength: 15,
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: _inputDec(dt['add_item_elec_price'],
                                    Icons.price_change_rounded,
                                    suffix: 'đ/kWh'),
                                keyboardType: TextInputType.number,
                                onChanged: (_) {
                                  setDialogState(() {});
                                  calculateAmount();
                                },
                              ),
                              if (electricityStartReadingController.text
                                      .isNotEmpty &&
                                  electricityEndReadingController.text.isNotEmpty)
                                _calcPreviewChip(
                                  t: dt,
                                  icon: Icons.bolt_rounded,
                                  color: const Color(0xFFF59E0B),
                                  usage:
                                      '${((double.tryParse(electricityEndReadingController.text) ?? 0) - (double.tryParse(electricityStartReadingController.text) ?? 0)).toStringAsFixed(1)} kWh',
                                ),
                              const SizedBox(height: 16),
                            ],
                          ],

                          // ── Water fields ────────────────────────────────
                          if (selectedType == PaymentType.water) ...[
                            _formSectionLabel(dt['add_item_water_title'],
                                Icons.water_drop_rounded,
                                const Color(0xFF06B6D4)),
                            const SizedBox(height: 10),

                            // Mode toggle
                            _modeToggle(
                              useDirectAmount: waterUseDirectAmount,
                              color: const Color(0xFF06B6D4),
                              meterIcon: Icons.water_rounded,
                              meterLabel: dt['add_item_mode_meter'],
                              directLabel: dt['add_item_mode_direct'],
                              onChanged: (val) => setDialogState(
                                  () => waterUseDirectAmount = val),
                            ),

                            // Meter reading fields (hidden when direct mode)
                            if (!waterUseDirectAmount) ...[
                              Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: waterStartReadingController,
                                    maxLength: 10,
                                    decoration: _inputDec(
                                        dt['add_item_start_reading'], null,
                                        suffix: 'm³'),
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) {
                                      setDialogState(() {});
                                      calculateAmount();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
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
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: waterEndReadingController,
                                    maxLength: 10,
                                    decoration: _inputDec(
                                        dt['add_item_end_reading'], null,
                                        suffix: 'm³'),
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) {
                                      setDialogState(() {});
                                      calculateAmount();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
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
                              ]),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: waterPriceController,
                                maxLength: 15,
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: _inputDec(dt['add_item_water_price'],
                                    Icons.price_change_rounded,
                                    suffix: 'đ/m³'),
                                keyboardType: TextInputType.number,
                                onChanged: (_) {
                                  setDialogState(() {});
                                  calculateAmount();
                                },
                              ),
                              if (waterStartReadingController.text.isNotEmpty &&
                                  waterEndReadingController.text.isNotEmpty)
                                _calcPreviewChip(
                                  t: dt,
                                  icon: Icons.water_drop_rounded,
                                  color: const Color(0xFF06B6D4),
                                  usage:
                                      '${((double.tryParse(waterEndReadingController.text) ?? 0) - (double.tryParse(waterStartReadingController.text) ?? 0)).toStringAsFixed(1)} m³',
                                ),
                              const SizedBox(height: 16),
                            ],
                          ],

                          // Billing period (rent or water)
                          if (selectedType == PaymentType.rent ||
                              selectedType == PaymentType.water) ...[
                            _formSectionLabel(
                                dt['add_item_billing_period'],
                                Icons.date_range_rounded,
                                const Color(0xFF6366F1)),
                            const SizedBox(height: 10),
                            Row(children: [
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
                              const SizedBox(width: 10),
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
                            ]),
                            const SizedBox(height: 16),
                          ],

                          // Amount — always editable in direct mode,
                          // read-only (auto-calculated) in meter mode
                          TextFormField(
                            controller: amountController,
                            maxLength: 20,
                            inputFormatters: [CurrencyInputFormatter()],
                            decoration: _inputDec(
                                dt['add_item_amount'], Icons.payments_rounded,
                                suffix: 'VND'),
                            keyboardType: TextInputType.number,
                            // Editable when: not electricity/water, OR in direct mode
                            readOnly: (selectedType == PaymentType.electricity &&
                                    !electricityUseDirectAmount) ||
                                (selectedType == PaymentType.water &&
                                    !waterUseDirectAmount),
                          ),
                          const SizedBox(height: 12),

                          // Description
                          TextFormField(
                            controller: descriptionController,
                            maxLength: 200,
                            decoration: _inputDec(
                                dt['add_item_description'], Icons.notes_rounded),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Dialog footer
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(dt['add_item_btn_cancel']),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(dt['add_item_btn_add']),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            if (selectedType != null &&
                                amountController.text.isNotEmpty) {
                              final amount = CurrencyParser.parse(amountController.text);
                              if (amount > 0) {
                                final res = <String, dynamic>{
                                  'type': selectedType!,
                                  'amount': amount,
                                  'description':
                                      descriptionController.text.isEmpty
                                          ? null
                                          : descriptionController.text,
                                };
                                // Only save meter reading data when not in direct mode
                                if (selectedType == PaymentType.electricity &&
                                    !electricityUseDirectAmount) {
                                  res['electricityStartReading'] =
                                      double.tryParse(
                                          electricityStartReadingController
                                              .text);
                                  res['electricityStartDate'] =
                                      electricityStartDate;
                                  res['electricityEndReading'] = double.tryParse(
                                      electricityEndReadingController.text);
                                  res['electricityEndDate'] = electricityEndDate;
                                  res['electricityPricePerUnit'] =
                                      double.tryParse(
                                          electricityPriceController.text);
                                }
                                if (selectedType == PaymentType.water &&
                                    !waterUseDirectAmount) {
                                  res['waterStartReading'] = double.tryParse(
                                      waterStartReadingController.text);
                                  res['waterStartDate'] = waterStartDate;
                                  res['waterEndReading'] = double.tryParse(
                                      waterEndReadingController.text);
                                  res['waterEndDate'] = waterEndDate;
                                  res['waterPricePerUnit'] = double.tryParse(
                                      waterPriceController.text);
                                }
                                if (selectedType == PaymentType.rent ||
                                    selectedType == PaymentType.water) {
                                  res['billingStartDate'] = billingStart;
                                  res['billingEndDate'] = billingEnd;
                                }
                                Navigator.pop(context, res);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content:
                                            Text(dt['add_item_err_amount'])));
                              }
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text(dt['add_item_err_required'])));
                            }
                          },
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
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
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 44, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(t['payment_items_empty'],
                style:
                    TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            const SizedBox(height: 4),
            Text(t['payment_items_empty_hint'],
                style:
                    TextStyle(color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
    }

    return Column(
      children: [
        ...List.generate(_lineItems.length, (index) {
          final item = _lineItems[index];
          final typeLabel = _typeLabel(t, item.type);
          final color = _typeColor(item.type);

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

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              title: Text(typeLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: detailText.isNotEmpty
                  ? Text(detailText,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500))
                  : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${NumberFormat('#,###').format(item.amount)} đ',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_rounded,
                        color: Colors.red.shade400, size: 20),
                    onPressed: () => _removeLineItem(item.id),
                  ),
                ],
              ),
            ),
          );
        }),

        // Total row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t['payment_total_label'],
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.grey.shade700,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                '${NumberFormat('#,###').format(_totalAmount)} VND',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
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
          tenantName: _selectedTenantName ?? t['tenant_unknown'],
          type: item.type,
          status: _selectedPaymentStatus ?? PaymentStatus.pending,
          amount: item.amount,
          paidAmount: CurrencyParser.parse(_paidAmountController.text),
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
              : CurrencyParser.parse(_lateFeeController.text),
          taxAmount: _taxAmountController.text.isEmpty
              ? null
              : CurrencyParser.parse(_taxAmountController.text),
          isRecurring: _isRecurring,
          recurringParentId: _recurringParentIdController.text.isEmpty
              ? null
              : _recurringParentIdController.text,
        );
        await widget.paymentService.addPayment(payment);
      } else {
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
          tenantName: _selectedTenantName ?? t['tenant_unknown'],
          type: primaryType,
          status: _selectedPaymentStatus ?? PaymentStatus.pending,
          amount: _totalAmount,
          paidAmount: CurrencyParser.parse(_paidAmountController.text),
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
              : CurrencyParser.parse(_lateFeeController.text),
          taxAmount: _taxAmountController.text.isEmpty
              ? null
              : CurrencyParser.parse(_taxAmountController.text),
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

  // ─── Resize / overlay helpers ──────────────────────────────────────────────

  Timer? _resizeDebounceTimer;
  bool _isDismissing = false;

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
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
    final bool isPhone = MediaQuery.of(context).size.width < 600;
    final bool isRoomMode = widget.room != null;
    final String dialogTitle = isRoomMode
        ? t.textWithParams(
            'payment_dialog_title_room', {'room': widget.room!.roomNumber})
        : t['payment_dialog_title'];

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.all(isPhone ? 12 : 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isPhone ? MediaQuery.of(context).size.width : 580,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Scaffold(
            backgroundColor: const Color(0xFFF8F9FA),
            body: Column(
              children: [
                // ── HEADER ─────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color:
                            Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.receipt_long_rounded,
                          color: Theme.of(context).primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dialogTitle,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(t['payment_dialog_subtitle'],
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ]),
                ),

                // ── BODY ───────────────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Tenant section
                          _sectionLabel(t['payment_section_tenant']),

                          if (isRoomMode)
                            DropdownButtonFormField<String>(
                              initialValue: _selectedTenantId,
                              decoration: _inputDec(
                                  t['payment_select_tenant'],
                                  Icons.person_outline_rounded),
                              items: _availableTenants
                                  .map((tenant) => DropdownMenuItem<String>(
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
                              optionsBuilder: (TextEditingValue value) {
                                if (value.text.isEmpty) {
                                  return const Iterable<Tenant>.empty();
                                }
                                return _availableTenants.where((tn) =>
                                    tn.fullName.toLowerCase().contains(
                                        value.text.toLowerCase()) ||
                                    tn.phoneNumber.contains(value.text));
                              },
                              onSelected: (Tenant selection) =>
                                  _onTenantSelected(selection.id),
                              fieldViewBuilder: (context, textCtrl, focusNode,
                                  onFieldSubmitted) {
                                return TextFormField(
                                  controller: textCtrl,
                                  focusNode: focusNode,
                                  decoration: _inputDec(
                                    t['payment_search_tenant'],
                                    Icons.search_rounded,
                                  ).copyWith(
                                    suffixIcon: textCtrl.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear),
                                            onPressed: () {
                                              textCtrl.clear();
                                              _onTenantSelected(null);
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
                                    borderRadius: BorderRadius.circular(12),
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                          maxHeight: 200, maxWidth: 400),
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
                                            onTap: () => onSelected(opt),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),

                          const SizedBox(height: 12),

                          // Building & room (read-only)
                          Row(children: [
                            Expanded(
                              child: TextFormField(
                                key: ValueKey('building_$_selectedBuildingId'),
                                readOnly: true,
                                initialValue: _selectedBuildingId != null
                                    ? _buildings
                                        .firstWhere(
                                            (b) => b.id == _selectedBuildingId,
                                            orElse: () => Building(
                                                id: '',
                                                address: 'N/A',
                                                name: 'N/A',
                                                organizationId: '',
                                                createdAt: DateTime.now()))
                                        .name
                                    : t['payment_building_unknown'],
                                decoration: _inputDec(
                                  t['payment_building_label'],
                                  Icons.apartment_rounded,
                                ).copyWith(
                                  filled: true,
                                  fillColor: Colors.grey.shade100,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
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
                                decoration: _inputDec(
                                  t['payment_room_label'],
                                  Icons.door_front_door_outlined,
                                ).copyWith(
                                  filled: true,
                                  fillColor: Colors.grey.shade100,
                                ),
                              ),
                            ),
                          ]),

                          // ── Line items section
                          _sectionLabel(t['payment_section_items']),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                t.textWithParams('payment_item_count',
                                    {'count': _lineItems.length}),
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade500),
                              ),
                              ElevatedButton.icon(
                                onPressed: _showAddLineItemDialog,
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: Text(t['payment_add_item_btn']),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildLineItemsList(t),

                          // ── Payment settings section
                          _sectionLabel(t['payment_section_settings']),

                          LocalizedDatePicker(
                            labelText: t['payment_due_date_label'],
                            prefixIcon: Icons.event_rounded,
                            required: true,
                            initialDate:
                                DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                            onDateChanged: (date) =>
                                setState(() => _dueDate = date),
                            validator: (date) => date == null
                                ? t['payment_err_due_date']
                                : null,
                          ),
                          const SizedBox(height: 12),

                          // Status dropdown with colour dots
                          DropdownButtonFormField<PaymentStatus>(
                            initialValue: _selectedPaymentStatus,
                            decoration: _inputDec(
                                t['payment_status_label'], Icons.flag_rounded),
                            items: PaymentStatus.values.map((s) {
                              final color = _statusColor(s);
                              return DropdownMenuItem(
                                value: s,
                                child: Row(children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_statusLabel(t, s)),
                                ]),
                              );
                            }).toList(),
                            onChanged: (v) =>
                                setState(() => _selectedPaymentStatus = v),
                          ),
                          const SizedBox(height: 12),

                          // ── Additional section
                          _sectionLabel(t['payment_section_additional']),

                          TextFormField(
                            controller: _notesController,
                            maxLength: 500,
                            decoration: _inputDec(t['payment_notes_label'],
                                Icons.sticky_note_2_rounded),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _taxAmountController,
                            maxLength: 20,
                            inputFormatters: [CurrencyInputFormatter()],
                            decoration: _inputDec(t['payment_tax_label'],
                                Icons.receipt_rounded,
                                suffix: 'VND'),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            validator: (v) {
                              if (v != null && v.isNotEmpty) {
                                try {
                                  double.parse(v);
                                } catch (_) {
                                  return t['payment_err_number'];
                                }
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── FOOTER ─────────────────────────────────────────────────
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      // Total preview
                      if (_lineItems.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .primaryColor
                                .withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(t['payment_total_label'],
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600)),
                              Text(
                                '${NumberFormat('#,###').format(_totalAmount)} VND',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),

                      Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: Text(t['payment_btn_cancel']),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Icon(Icons.save_rounded, size: 18),
                            label: Text(t['payment_btn_save']),
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _isSaving ? null : _savePayment,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Shared form helpers (same API as the View/Edit file) ─────────────────────

InputDecoration _inputDec(String label, IconData? icon,
        {String? suffix, String? helper}) =>
    InputDecoration(
      labelText: label,
      helperText: helper,
      prefixIcon: icon != null ? Icon(icon, size: 18) : null,
      suffixText: suffix,
      counterText: '',
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );

/// Divider with label in the middle — mirrors `_sectionLabel` in the View/Edit file.
Widget _sectionLabel(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(children: [
        Expanded(child: Divider(color: Colors.grey.shade200)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Colors.grey.shade500,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.grey.shade200)),
      ]),
    );

Widget _formSectionLabel(String label, IconData icon, Color color) =>
    Row(children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
      const SizedBox(width: 8),
      Text(label,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: Colors.grey.shade700)),
    ]);

Widget _calcPreviewChip({
  required AppTranslations t,
  required IconData icon,
  required Color color,
  required String usage,
}) =>
    Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(t['calc_preview_consumption_label'],
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Text(usage,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );