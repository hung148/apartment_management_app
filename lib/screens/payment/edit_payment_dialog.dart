part of 'view_edit_payment_dialogs.dart';

// Payment editing, line-item calculations, saving, and editor form helpers.
// ─────────────────────────────────────────────
// EDIT PAYMENT DIALOG
// ─────────────────────────────────────────────

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

class _EditPaymentDialogState extends State<EditPaymentDialog>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _notesController;
  late TextEditingController _taxAmountController;
  late TextEditingController _paidAmountController;
  late String? _selectedTenantId;
  late String? _selectedTenantName;
  late PaymentStatus _selectedPaymentStatus;
  late DateTime _dueDate;
  List<Tenant> _tenants = [];
  List<InvoiceLineItem> _lineItems = [];
  Room? _room;

  double get _totalAmount =>
      _lineItems.fold(0.0, (acc, item) => acc + item.amount);

  Timer? _resizeDebounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notesController = TextEditingController(text: widget.payment.notes);
    _taxAmountController = TextEditingController(
      text: CurrencyParser.format(widget.payment.taxAmount ?? 0),
    );
    _paidAmountController = TextEditingController(
      text: CurrencyParser.format(widget.payment.paidAmount),
    );
    _selectedTenantId = widget.payment.tenantId;
    _selectedTenantName = widget.payment.tenantName;
    _selectedPaymentStatus = widget.payment.status;
    _dueDate = widget.payment.dueDate;
    _lineItems = _parseLineItems(widget.payment);
    _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resizeDebounceTimer?.cancel();
    _notesController.dispose();
    _taxAmountController.dispose();
    _paidAmountController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _resizeDebounceTimer?.cancel();
    _resizeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

    });
  }



  Future<T?> _showTrackedDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) async {
    try {
      return await showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: builder,
      );
    } finally {
    }
  }

  Future<void> _loadData() async {
    try {
      final tenants = await widget.tenantService
          .getOrganizationTenants(widget.organization.id);
      final room = await widget.roomService.getRoomById(widget.payment.roomId);
      setState(() {
        _tenants = tenants;
        _room = room;
        if (_selectedTenantId != null &&
            !_tenants.any((t) => t.id == _selectedTenantId)) {
          _selectedTenantId = null;
          _selectedTenantName = null;
        }
      });
    } catch (e) {
      if (mounted) {
        final t = AppTranslations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  t.textWithParams('tenant_error', {'error': e.toString()}))),
        );
      }
    }
  }

  void _removeLineItem(String id) =>
      setState(() => _lineItems.removeWhere((item) => item.id == id));

  Future<void> _showAddLineItemDialog() async {
    PaymentType? selectedType;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    final elecStartCtrl = TextEditingController();
    final elecEndCtrl = TextEditingController();
    final elecPriceCtrl = TextEditingController();
    bool electricityUseDirectAmount = false;
    final waterStartCtrl = TextEditingController();
    final waterEndCtrl = TextEditingController();
    final waterPriceCtrl = TextEditingController();
    bool waterUseDirectAmount = false;
    DateTime? elecStartDate, elecEndDate;
    DateTime? waterStartDate, waterEndDate;
    DateTime? billingStart, billingEnd;

    // Rent unit-price (theo ngày/tháng/năm)
    RentPriceMode rentPriceMode = RentPriceMode.direct;
    final rentUnitPriceController = TextEditingController();
    final rentUnitQuantityController = TextEditingController();
    bool rentQuantityManuallyEdited = false;
    bool rentPriceManuallyEdited = false;

    // The selected tenant's on-file rent + contract period, used to auto-fill
    // the rent unit price and billing dates instead of asking the admin to
    // retype numbers that already exist on the tenant record. Falls back to
    // the room's default price if the tenant has no monthlyRent set.
    Tenant? tenant;
    try {
      tenant = _tenants.firstWhere((ten) => ten.id == _selectedTenantId);
    } catch (_) {
      tenant = null;
    }
    final room = _room;

    double? autoRentUnitPrice(RentPriceMode mode) {
      final monthly = tenant?.monthlyRent ?? room?.roomPrice;
      if (monthly == null || monthly <= 0) return null;
      switch (mode) {
        case RentPriceMode.daily:
          return monthly / 30;
        case RentPriceMode.monthly:
          return monthly;
        case RentPriceMode.yearly:
          return monthly * 12;
        case RentPriceMode.direct:
          return null;
      }
    }

    final result = await _showTrackedDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Re-resolve translations inside the dialog's build context
          final dt = AppTranslations.of(context);

          void calcAmount() {
            if (selectedType == PaymentType.electricity &&
                !electricityUseDirectAmount) {
              final s = double.tryParse(elecStartCtrl.text) ?? 0;
              final e = double.tryParse(elecEndCtrl.text) ?? 0;
              final p = CurrencyParser.parse(elecPriceCtrl.text);
              if (e >= s && p > 0) {
                amountController.text = CurrencyParser.format((e - s) * p);
              }
            } else if (selectedType == PaymentType.water &&
                !waterUseDirectAmount) {
              final s = double.tryParse(waterStartCtrl.text) ?? 0;
              final e = double.tryParse(waterEndCtrl.text) ?? 0;
              final p = CurrencyParser.parse(waterPriceCtrl.text);
              if (e >= s && p > 0) {
                amountController.text = CurrencyParser.format((e - s) * p);
              }
            }
          }

          double? autoRentQuantity() {
            if (billingStart == null || billingEnd == null) return null;
            final days = billingEnd!.difference(billingStart!).inDays + 1;
            if (days <= 0) return null;
            switch (rentPriceMode) {
              case RentPriceMode.daily:
                return days.toDouble();
              case RentPriceMode.monthly:
                return (days / 30).clamp(0.01, double.infinity);
              case RentPriceMode.yearly:
                return (days / 365).clamp(0.01, double.infinity);
              case RentPriceMode.direct:
                return null;
            }
          }

          void recalcRentAmount() {
            if (rentPriceMode == RentPriceMode.direct) return;
            if (!rentQuantityManuallyEdited) {
              final auto = autoRentQuantity();
              if (auto != null) {
                rentUnitQuantityController.text = rentPriceMode == RentPriceMode.daily
                    ? auto.toStringAsFixed(0)
                    : auto.toStringAsFixed(2);
              }
            }
            final price = CurrencyParser.parse(rentUnitPriceController.text);
            final qty = double.tryParse(rentUnitQuantityController.text) ?? 0;
            if (price > 0 && qty > 0) {
              amountController.text = CurrencyParser.format(price * qty);
            }
          }

          Widget modeToggle({
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
                          Text(meterLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: !useDirectAmount
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: !useDirectAmount
                                      ? color
                                      : Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                    width: 1,
                    height: 28,
                    color: color.withValues(alpha: 0.18)),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      onChanged(true);
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
                          Text(directLabel,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: useDirectAmount
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: useDirectAmount
                                      ? color
                                      : Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            );
          }

          return AppDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 500,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Dialog header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .primaryColor
                          .withValues(alpha: 0.06),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(20)),
                    ),
                    child: Row(children: [
                      Icon(Icons.add_circle_outline_rounded,
                          color: Theme.of(context).primaryColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(dt['add_item_dialog_title'],
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(context, null),
                      ),
                    ]),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Type selector
                          DropdownButtonFormField<PaymentType>(
                            initialValue: selectedType,
                            decoration: _inputDec(
                                dt['add_item_type_label'],
                                Icons.category_rounded),
                             items: PaymentType.values
                                .where((t) => t != PaymentType.buildingRent)
                                .map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Row(children: [
                                        Container(
                                          width: 10,
                                          height: 10,
                                          decoration: BoxDecoration(
                                            color: _typeColor(t),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(_typeLabels(dt)[t.name] ?? ''),
                                      ]),
                                    ))
                                .toList(),
                            onChanged: (v) => setDialogState(() {
                              selectedType = v;
                              // Seed the billing period from the tenant's
                              // contract the first time Rent is selected —
                              // only if the admin hasn't already picked dates.
                              if (v == PaymentType.rent &&
                                  billingStart == null &&
                                  billingEnd == null &&
                                  tenant != null) {
                                billingStart = tenant!.contractStartDate ??
                                    tenant.moveInDate;
                                billingEnd = tenant.contractEndDate;
                              }
                            }),
                          ),
                          const SizedBox(height: 16),

                          // --- Electricity ---
                          if (selectedType == PaymentType.electricity) ...[
                            _formSectionLabel(
                                dt['payment_type_electricity'],
                                Icons.bolt_rounded,
                                const Color(0xFFF59E0B)),
                            const SizedBox(height: 10),
                            modeToggle(
                              useDirectAmount: electricityUseDirectAmount,
                              color: const Color(0xFFF59E0B),
                              meterIcon: Icons.electric_meter_rounded,
                              meterLabel: dt['add_item_mode_meter'],
                              directLabel: dt['add_item_mode_direct'],
                              onChanged: (val) => setDialogState(
                                  () => electricityUseDirectAmount = val),
                            ),
                            if (!electricityUseDirectAmount) ...[
                              Row(children: [
                                Expanded(
                                    child: TextFormField(
                                  controller: elecStartCtrl,
                                  decoration: _inputDec(
                                      dt['add_item_start_reading'], null,
                                      suffix: 'kWh'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) {
                                    setDialogState(() {});
                                    calcAmount();
                                  },
                                )),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: CompactLocalizedDatePicker(
                                  labelText: dt['add_item_from_date'],
                                  initialDate: elecStartDate,
                                  onDateChanged: (d) =>
                                      setDialogState(() => elecStartDate = d),
                                )),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                    child: TextFormField(
                                  controller: elecEndCtrl,
                                  decoration: _inputDec(
                                      dt['add_item_end_reading'], null,
                                      suffix: 'kWh'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) {
                                    setDialogState(() {});
                                    calcAmount();
                                  },
                                )),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: CompactLocalizedDatePicker(
                                  labelText: dt['add_item_to_date'],
                                  initialDate: elecEndDate,
                                  onDateChanged: (d) {
                                    setDialogState(() => elecEndDate = d);
                                    calcAmount();
                                  },
                                )),
                              ]),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: elecPriceCtrl,
                                inputFormatters: [CurrencyInputFormatter(decimalDigits: widget.payment.currency == 'USD' ? 2 : 0)],
                                decoration: _inputDec(
                                    dt['add_item_elec_price'],
                                    Icons.price_change_rounded,
                                    suffix: '${widget.payment.currency}/kWh'),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (_) {
                                  setDialogState(() {});
                                  calcAmount();
                                },
                              ),
                              if (elecStartCtrl.text.isNotEmpty &&
                                  elecEndCtrl.text.isNotEmpty)
                                _calcPreviewChip(
                                  icon: Icons.bolt_rounded,
                                  color: const Color(0xFFF59E0B),
                                  label: dt['calc_preview_consumption_label'],
                                  usage:
                                      '${((double.tryParse(elecEndCtrl.text) ?? 0) - (double.tryParse(elecStartCtrl.text) ?? 0)).toStringAsFixed(1)} kWh',
                                ),
                            ],
                            const SizedBox(height: 16),
                          ],

                          // --- Water ---
                          if (selectedType == PaymentType.water) ...[
                            _formSectionLabel(
                                dt['payment_type_water'],
                                Icons.water_drop_rounded,
                                const Color(0xFF06B6D4)),
                            const SizedBox(height: 10),
                            modeToggle(
                              useDirectAmount: waterUseDirectAmount,
                              color: const Color(0xFF06B6D4),
                              meterIcon: Icons.water_rounded,
                              meterLabel: dt['add_item_mode_meter'],
                              directLabel: dt['add_item_mode_direct'],
                              onChanged: (val) => setDialogState(
                                  () => waterUseDirectAmount = val),
                            ),
                            if (!waterUseDirectAmount) ...[
                              Row(children: [
                                Expanded(
                                    child: TextFormField(
                                  controller: waterStartCtrl,
                                  decoration: _inputDec(
                                      dt['add_item_start_reading'], null,
                                      suffix: 'm³'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) {
                                    setDialogState(() {});
                                    calcAmount();
                                  },
                                )),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: CompactLocalizedDatePicker(
                                  labelText: dt['add_item_from_date'],
                                  initialDate: waterStartDate,
                                  onDateChanged: (d) =>
                                      setDialogState(() => waterStartDate = d),
                                )),
                              ]),
                              const SizedBox(height: 10),
                              Row(children: [
                                Expanded(
                                    child: TextFormField(
                                  controller: waterEndCtrl,
                                  decoration: _inputDec(
                                      dt['add_item_end_reading'], null,
                                      suffix: 'm³'),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) {
                                    setDialogState(() {});
                                    calcAmount();
                                  },
                                )),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: CompactLocalizedDatePicker(
                                  labelText: dt['add_item_to_date'],
                                  initialDate: waterEndDate,
                                  onDateChanged: (d) {
                                    setDialogState(() => waterEndDate = d);
                                    calcAmount();
                                  },
                                )),
                              ]),
                              const SizedBox(height: 10),
                              TextFormField(
                                controller: waterPriceCtrl,
                                inputFormatters: [CurrencyInputFormatter(decimalDigits: widget.payment.currency == 'USD' ? 2 : 0)],
                                decoration: _inputDec(
                                    dt['add_item_water_price'],
                                    Icons.price_change_rounded,
                                    suffix: '${widget.payment.currency}/m³'),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                onChanged: (_) {
                                  setDialogState(() {});
                                  calcAmount();
                                },
                              ),
                              if (waterStartCtrl.text.isNotEmpty &&
                                  waterEndCtrl.text.isNotEmpty)
                                _calcPreviewChip(
                                  icon: Icons.water_drop_rounded,
                                  color: const Color(0xFF06B6D4),
                                  label: dt['calc_preview_consumption_label'],
                                  usage:
                                      '${((double.tryParse(waterEndCtrl.text) ?? 0) - (double.tryParse(waterStartCtrl.text) ?? 0)).toStringAsFixed(1)} m³',
                                ),
                            ],
                            const SizedBox(height: 16),
                          ],

                          // --- Billing Period ---
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
                                onDateChanged: (d) => setDialogState(() {
                                  billingStart = d;
                                  if (selectedType == PaymentType.rent) {
                                    recalcRentAmount();
                                  }
                                }),
                              )),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: CompactLocalizedDatePicker(
                                labelText: dt['add_item_to_date'],
                                initialDate: billingEnd,
                                onDateChanged: (d) => setDialogState(() {
                                  billingEnd = d;
                                  if (selectedType == PaymentType.rent) {
                                    recalcRentAmount();
                                  }
                                }),
                              )),
                            ]),
                            const SizedBox(height: 16),
                          ],

                          // --- Rent unit-price (theo ngày/tháng/năm) ---
                          if (selectedType == PaymentType.rent) ...[
                            _formSectionLabel(
                                dt['add_item_rent_pricing_title'],
                                Icons.calculate_rounded,
                                const Color(0xFF6366F1)),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _rentModeChip(
                                  label: dt['add_item_mode_direct'],
                                  icon: Icons.edit_rounded,
                                  selected: rentPriceMode == RentPriceMode.direct,
                                  onTap: () => setDialogState(() {
                                    rentPriceMode = RentPriceMode.direct;
                                  }),
                                ),
                                _rentModeChip(
                                  label: dt['add_item_rent_daily'],
                                  icon: Icons.today_rounded,
                                  selected: rentPriceMode == RentPriceMode.daily,
                                  onTap: () => setDialogState(() {
                                    rentPriceMode = RentPriceMode.daily;
                                    rentQuantityManuallyEdited = false;
                                    if (!rentPriceManuallyEdited) {
                                      final auto = autoRentUnitPrice(rentPriceMode);
                                      if (auto != null) {
                                        rentUnitPriceController.text =
                                            CurrencyParser.format(auto);
                                      }
                                    }
                                    recalcRentAmount();
                                  }),
                                ),
                                _rentModeChip(
                                  label: dt['add_item_rent_monthly'],
                                  icon: Icons.calendar_view_month_rounded,
                                  selected: rentPriceMode == RentPriceMode.monthly,
                                  onTap: () => setDialogState(() {
                                    rentPriceMode = RentPriceMode.monthly;
                                    rentQuantityManuallyEdited = false;
                                    if (!rentPriceManuallyEdited) {
                                      final auto = autoRentUnitPrice(rentPriceMode);
                                      if (auto != null) {
                                        rentUnitPriceController.text =
                                            CurrencyParser.format(auto);
                                      }
                                    }
                                    recalcRentAmount();
                                  }),
                                ),
                                _rentModeChip(
                                  label: dt['add_item_rent_yearly'],
                                  icon: Icons.event_repeat_rounded,
                                  selected: rentPriceMode == RentPriceMode.yearly,
                                  onTap: () => setDialogState(() {
                                    rentPriceMode = RentPriceMode.yearly;
                                    rentQuantityManuallyEdited = false;
                                    if (!rentPriceManuallyEdited) {
                                      final auto = autoRentUnitPrice(rentPriceMode);
                                      if (auto != null) {
                                        rentUnitPriceController.text =
                                            CurrencyParser.format(auto);
                                      }
                                    }
                                    recalcRentAmount();
                                  }),
                                ),
                              ],
                            ),
                            if (rentPriceMode != RentPriceMode.direct) ...[
                              const SizedBox(height: 12),
                              ResponsiveFormRow(children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: rentUnitPriceController,
                                    inputFormatters: [CurrencyInputFormatter(decimalDigits: widget.payment.currency == 'USD' ? 2 : 0)],
                                    decoration: _inputDec(
                                        _rentUnitPriceLabel(dt, rentPriceMode),
                                        Icons.price_change_rounded,
                                        suffix: widget.payment.currency,
                                        helper: (tenant?.monthlyRent ??
                                                    room?.roomPrice) !=
                                                null
                                            ? dt['add_item_rent_price_auto_hint']
                                            : null),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    onChanged: (_) => setDialogState(() {
                                      rentPriceManuallyEdited = true;
                                      recalcRentAmount();
                                    }),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: rentUnitQuantityController,
                                    decoration: _inputDec(
                                        _rentQuantityLabel(dt, rentPriceMode),
                                        Icons.numbers_rounded),
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    onChanged: (_) => setDialogState(() {
                                      rentQuantityManuallyEdited = true;
                                      recalcRentAmount();
                                    }),
                                  ),
                                ),
                              ]),
                              if (rentUnitPriceController.text.isNotEmpty &&
                                  rentUnitQuantityController.text.isNotEmpty)
                                _calcPreviewChip(
                                  icon: Icons.calculate_rounded,
                                  color: const Color(0xFF6366F1),
                                  label: '',
                                  usage:
                                      '${rentUnitQuantityController.text} ${_rentUnitShort(dt, rentPriceMode)} × ${NumberFormat('#,##0.##', 'en_US').format(CurrencyParser.parse(rentUnitPriceController.text))} ${widget.payment.currency}',
                                ),
                              const SizedBox(height: 16),
                            ] else
                              const SizedBox(height: 16),
                          ],

                          // Amount
                          TextFormField(
                            controller: amountController,
                            inputFormatters: [CurrencyInputFormatter(decimalDigits: widget.payment.currency == 'USD' ? 2 : 0)],
                            decoration: _inputDec(dt['add_item_amount'],
                                Icons.payments_rounded,
                                suffix: widget.payment.currency),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            readOnly: (selectedType ==
                                        PaymentType.electricity &&
                                    !electricityUseDirectAmount) ||
                                (selectedType == PaymentType.water &&
                                    !waterUseDirectAmount) ||
                                (selectedType == PaymentType.rent &&
                                    rentPriceMode != RentPriceMode.direct),
                          ),
                          const SizedBox(height: 12),

                          TextFormField(
                            controller: descriptionController,
                            decoration: _inputDec(dt['add_item_description'],
                                Icons.notes_rounded),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Footer Actions
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Row(children: [
                      Expanded(
                          child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, null),
                        child: Text(dt['add_item_btn_cancel']),
                      )),
                      const SizedBox(width: 12),
                      Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: () {
                              if (selectedType != null &&
                                  amountController.text.isNotEmpty) {
                                final amount = CurrencyParser.parse(amountController.text);
                                if (amount > 0) {
                                  final r = <String, dynamic>{
                                    'type': selectedType!,
                                    'amount': amount,
                                    'description':
                                        descriptionController.text.isEmpty
                                            ? null
                                            : descriptionController.text,
                                  };

                                  if (selectedType ==
                                          PaymentType.electricity &&
                                      !electricityUseDirectAmount) {
                                    r['electricityStartReading'] =
                                        double.tryParse(elecStartCtrl.text);
                                    r['electricityStartDate'] = elecStartDate;
                                    r['electricityEndReading'] =
                                        double.tryParse(elecEndCtrl.text);
                                    r['electricityEndDate'] = elecEndDate;
                                    r['electricityPricePerUnit'] = CurrencyParser.parse(elecPriceCtrl.text);
                                  }
                                  if (selectedType == PaymentType.water &&
                                      !waterUseDirectAmount) {
                                    r['waterStartReading'] =
                                        double.tryParse(waterStartCtrl.text);
                                    r['waterStartDate'] = waterStartDate;
                                    r['waterEndReading'] =
                                        double.tryParse(waterEndCtrl.text);
                                    r['waterEndDate'] = waterEndDate;
                                    r['waterPricePerUnit'] = CurrencyParser.parse(waterPriceCtrl.text);
                                  }
                                  if (selectedType == PaymentType.rent ||
                                      selectedType == PaymentType.water) {
                                    r['billingStartDate'] = billingStart;
                                    r['billingEndDate'] = billingEnd;
                                  }
                                  if (selectedType == PaymentType.rent &&
                                      rentPriceMode != RentPriceMode.direct) {
                                    r['rentPriceMode'] = rentPriceMode;
                                    r['rentUnitPrice'] = CurrencyParser
                                        .parse(rentUnitPriceController.text);
                                    r['rentUnitQuantity'] = double.tryParse(
                                        rentUnitQuantityController.text);
                                  }
                                  Navigator.pop(context, r);
                                }
                              }
                            },
                            child: Text(dt['add_item_btn_add']),
                          )),
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
          rentPriceMode: result['rentPriceMode'] as RentPriceMode?,
          rentUnitPrice: result['rentUnitPrice'] as double?,
          rentUnitQuantity: result['rentUnitQuantity'] as double?,
        ));
      });
    }
  }

  // ── Line item list in edit dialog ─────────────
  Widget _buildEditLineItemsList(AppTranslations t) {
    if (_lineItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.grey.shade200, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 44, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(t['payment_items_empty'],
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
            const SizedBox(height: 4),
            Text(t['payment_items_empty_hint'],
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      );
    }

    final dateFormat = t.dateFormat;

    return Column(
      children: [
        ...List.generate(_lineItems.length, (index) {
          final item = _lineItems[index];
          final label = _typeLabels(t)[item.type.name] ?? item.type.name;
          final color = _typeColor(item.type);

          String detail = '';
          if (item.type == PaymentType.electricity &&
              item.electricityStartReading != null) {
            final usage = (item.electricityEndReading ?? 0) -
                (item.electricityStartReading ?? 0);
            detail = t.textWithParams('line_item_elec_detail', {
              'start': item.electricityStartReading,
              'end': item.electricityEndReading,
              'usage': usage.toStringAsFixed(1),
            });
          } else if (item.type == PaymentType.water &&
              item.waterStartReading != null) {
            final usage = (item.waterEndReading ?? 0) -
                (item.waterStartReading ?? 0);
            detail = t.textWithParams('line_item_water_detail', {
              'start': item.waterStartReading,
              'end': item.waterEndReading,
              'usage': usage.toStringAsFixed(1),
            });
          } else if (item.type == PaymentType.rent &&
              item.rentPriceMode != null &&
              item.rentPriceMode != RentPriceMode.direct &&
              item.rentUnitPrice != null &&
              item.rentUnitQuantity != null) {
            final unitShort = _rentUnitShort(t, item.rentPriceMode!);
            final qtyText = item.rentPriceMode == RentPriceMode.daily
                ? item.rentUnitQuantity!.toStringAsFixed(0)
                : item.rentUnitQuantity!.toStringAsFixed(2);
            detail =
                '$qtyText $unitShort × ${NumberFormat('#,##0.##', 'en_US').format(item.rentUnitPrice)} ${widget.payment.currency}/$unitShort'
                '${item.billingStartDate != null && item.billingEndDate != null ? ' · ${DateFormat(dateFormat).format(item.billingStartDate!)} - ${DateFormat(dateFormat).format(item.billingEndDate!)}' : ''}';
          } else if (item.billingStartDate != null) {
            detail = t.textWithParams('billing_period', {
              'start':
                  DateFormat(dateFormat).format(item.billingStartDate!),
              'end': DateFormat(dateFormat).format(item.billingEndDate!),
            });
          } else if (item.description != null) {
            detail = item.description!;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text('${index + 1}',
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              title: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: detail.isNotEmpty
                  ? Text(detail,
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
                      color: color.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${NumberFormat('#,##0.##', 'en_US').format(item.amount)} ${widget.payment.currency}',
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 13),
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t['payment_total_label'],
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      letterSpacing: 0.5)),
              Text(
                '${NumberFormat('#,##0.##', 'en_US').format(_totalAmount)} ${widget.payment.currency}',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).primaryColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _savePayment(AppTranslations t) async {
    if (!_formKey.currentState!.validate()) return;
    if (_lineItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t['payment_err_no_items'])),
      );
      return;
    }

    try {
      final lineItemsDescription = _lineItems.map((item) {
        final typeLabel = _typeLabels(t)[item.type.name] ?? item.type.name;
        final desc =
            item.description != null ? ' (${item.description})' : '';
        return '$typeLabel: ${NumberFormat('#,##0.##', 'en_US').format(item.amount)} ${widget.payment.currency}$desc';
      }).join('\n');

      final double tax = _taxAmountController.text.isEmpty
        ? 0
        : CurrencyParser.parse(_taxAmountController.text);
      final double totalToCollect =
          _totalAmount + tax + (widget.payment.lateFee ?? 0);

      final Map<String, dynamic> updates = {
        'tenantId': _selectedTenantId,
        'tenantName': _selectedTenantName,
        'amount': _totalAmount,
        'dueDate': _dueDate,
        'status': _selectedPaymentStatus.name,
        'description': lineItemsDescription,
        'notes':
            _notesController.text.isEmpty ? null : _notesController.text,
        'taxAmount': _taxAmountController.text.isEmpty
            ? null
            : CurrencyParser.parse(_taxAmountController.text),
      };

      if (_selectedPaymentStatus == PaymentStatus.paid) {
        updates['paidAmount'] = totalToCollect;
        updates['paidAt'] = widget.payment.paidAt != null
            ? Timestamp.fromDate(widget.payment.paidAt!)
            : Timestamp.now();
      } else if (_selectedPaymentStatus == PaymentStatus.partial) {
        updates['paidAmount'] = double.tryParse(
                _paidAmountController.text.replaceAll(',', '')) ??
            0.0;
        updates['paidAt'] = Timestamp.now();
      } else {
        updates['paidAmount'] = 0.0;
        updates['paidAt'] = null;
      }

      if (_lineItems.length == 1) {
        final item = _lineItems.first;
        if (item.electricityStartReading != null) {
          updates['electricityStartReading'] = item.electricityStartReading;
          updates['electricityStartDate'] = item.electricityStartDate;
          updates['electricityEndReading'] = item.electricityEndReading;
          updates['electricityEndDate'] = item.electricityEndDate;
          updates['electricityPricePerUnit'] = item.electricityPricePerUnit;
        }
        if (item.waterStartReading != null) {
          updates['waterStartReading'] = item.waterStartReading;
          updates['waterStartDate'] = item.waterStartDate;
          updates['waterEndReading'] = item.waterEndReading;
          updates['waterEndDate'] = item.waterEndDate;
          updates['waterPricePerUnit'] = item.waterPricePerUnit;
        }
        if (item.billingStartDate != null) {
          updates['billingStartDate'] = item.billingStartDate;
          updates['billingEndDate'] = item.billingEndDate;
        }
        if (item.type == PaymentType.rent) {
          updates['rentPriceMode'] = item.rentPriceMode?.name;
          updates['rentUnitPrice'] = item.rentUnitPrice;
          updates['rentUnitQuantity'] = item.rentUnitQuantity;
        }
      }

      await widget.paymentService.updatePayment(widget.payment.id, updates);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t['payment_save_success'])),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  t.textWithParams('payment_save_error', {'error': e.toString()}))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final isPhone = MediaQuery.of(context).size.width < 600;

    return AppDialog(
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
                // ── HEADER ─────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
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
                            Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.edit_rounded,
                          color: Theme.of(context).primaryColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['edit_payment'],
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

                // ── FORM ───────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Tenant
                          _sectionLabel(t['payment_section_tenant']),
                          DropdownButtonFormField<String?>(
                            initialValue: _tenants
                                    .any((ten) => ten.id == _selectedTenantId)
                                ? _selectedTenantId
                                : null,
                            decoration: _inputDec(t['tenant_label'],
                                Icons.person_outline_rounded),
                            items: [
                              DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text(t['no_data'])),
                              ..._tenants.map((ten) => DropdownMenuItem<String?>(
                                  value: ten.id,
                                  child: Text(ten.fullName))),
                            ],
                            onChanged: (v) {
                              if (v != null && v.isNotEmpty) {
                                final tenant =
                                    _tenants.firstWhere((ten) => ten.id == v);
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

                          // ── Line items
                          _sectionLabel(t['payment_section_items']),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                t.textWithParams('payment_item_count',
                                    {'count': _lineItems.length}),
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade500),
                              ),
                              ElevatedButton.icon(
                                onPressed: _showAddLineItemDialog,
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: Text(t['payment_add_item_btn']),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildEditLineItemsList(t),

                          // ── Payment settings
                          _sectionLabel(t['payment_section_settings']),
                          LocalizedDatePicker(
                            labelText: t['payment_due_date_label'],
                            prefixIcon: Icons.event_rounded,
                            required: true,
                            initialDate: _dueDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 365)),
                            onDateChanged: (date) {
                              if (date != null) {
                                setState(() => _dueDate = date);
                              }
                            },
                            validator: (date) => date == null
                                ? t['payment_err_due_date']
                                : null,
                          ),
                          const SizedBox(height: 12),

                          // Status selector
                          DropdownButtonFormField<PaymentStatus>(
                            initialValue: _selectedPaymentStatus,
                            decoration: _inputDec(
                                t['payment_status_label'],
                                Icons.flag_rounded),
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
                                  Text(_statusLabels(t)[s.name] ?? ''),
                                ]),
                              );
                            }).toList(),
                            onChanged: (v) => setState(
                                () => _selectedPaymentStatus = v!),
                          ),
                          const SizedBox(height: 12),

                          if (_selectedPaymentStatus ==
                              PaymentStatus.partial) ...[
                            TextFormField(
                              controller: _paidAmountController,
                              maxLength: 20,
                              inputFormatters: [CurrencyInputFormatter(decimalDigits: widget.payment.currency == 'USD' ? 2 : 0)],
                              decoration: _inputDec(
                                t['del_payment_total'],
                                Icons.payments_outlined,
                                suffix: widget.payment.currency,
                                helper:
                                    '${t['payment_total_label']} ${NumberFormat('#,##0.##', 'en_US').format(_totalAmount)} ${widget.payment.currency}',
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              validator: (v) {
                                final val = double.tryParse(
                                    v?.replaceAll(',', '') ?? '');
                                if (val == null || val <= 0) {
                                  return t['add_item_err_amount'];
                                }
                                if (val >= _totalAmount) {
                                  return t['payment_err_number'];
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 12),
                          ],

                          // ── Additional
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
                            inputFormatters: [CurrencyInputFormatter(decimalDigits: widget.payment.currency == 'USD' ? 2 : 0)],
                            decoration: _inputDec(t['payment_tax_label'],
                                Icons.receipt_rounded,
                                suffix: widget.payment.currency),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            validator: (v) {
                              if (v != null && v.isNotEmpty) {
                                if (CurrencyParser.tryParse(v) == null) {
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

                // ── FOOTER ─────────────────────────────
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      // Total preview
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .primaryColor
                              .withValues(alpha: 0.06),
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
                              '${NumberFormat('#,##0.##', 'en_US').format(_totalAmount)} ${widget.payment.currency}',
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
                                  borderRadius:
                                      BorderRadius.circular(10)),
                            ),
                            child: Text(t['cancel']),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.save_rounded, size: 18),
                            label: Text(t['payment_btn_save']),
                            style: ElevatedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(10)),
                            ),
                            onPressed: () => _savePayment(t),
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

// ─────────────────────────────────────────────
// FORM FIELD HELPERS
// ─────────────────────────────────────────────

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
  required IconData icon,
  required Color color,
  required String label,
  required String usage,
}) =>
    Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        if (label.isNotEmpty) ...[
          Text(label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(width: 4),
        ],
        Text(usage,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );

