part of 'view_edit_payment_dialogs.dart';

// Payment details, related room/tenant loading, and viewing actions.
// ─────────────────────────────────────────────
// VIEW PAYMENT DETAILS DIALOG
// ─────────────────────────────────────────────

class ViewPaymentDetailsDialog extends StatefulWidget {
  final Payment payment;
  final bool isAdmin;
  final VoidCallback? onEdit;
  final Organization organization;
  final RoomService roomService;
  final BuildingService buildingService;
  final PaymentService paymentService;
  final TenantService tenantService;

  const ViewPaymentDetailsDialog({
    super.key,
    required this.payment,
    required this.isAdmin,
    required this.organization,
    required this.roomService,
    required this.buildingService,
    required this.paymentService,
    required this.tenantService,
    this.onEdit,
  });

  @override
  State<ViewPaymentDetailsDialog> createState() =>
      _ViewPaymentDetailsDialogState();
}

class _ViewPaymentDetailsDialogState extends State<ViewPaymentDetailsDialog>
    with WidgetsBindingObserver {
  Room? _room;
  Building? _building;
  Tenant? _tenant;
  bool _isLoadingRoomData = true;
  Timer? _resizeDebounceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadRoomAndBuildingData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resizeDebounceTimer?.cancel();
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

  Future<void> _loadRoomAndBuildingData() async {
    try {
      final room = await widget.roomService.getRoomById(widget.payment.roomId);
      if (room != null && mounted) {
        setState(() => _room = room);
        final building =
            await widget.buildingService.getBuildingById(room.buildingId);
        if (building != null && mounted) {
          setState(() => _building = building);
        }
        if (widget.payment.tenantId != null) {
          final tenant =
              await widget.tenantService.getTenantById(widget.payment.tenantId!);
          if (tenant != null && mounted) {
            setState(() => _tenant = tenant);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading room/building data: $e');
    } finally {
      if (mounted) setState(() => _isLoadingRoomData = false);
    }
  }

  Future<void> _exportToPDF() async {
    await PaymentPDFExporter.showPDFPreview(
      context: context,
      payment: widget.payment,
      organization: widget.organization,
      roomNumber: _room?.roomNumber,
      buildingName: _building?.name,
      email: _tenant?.email ?? '',
    );
  }

  Future<void> _exportToExcel() async {
    await PaymentExcelExporter.exportPayment(
      context: context,
      payment: widget.payment,
      organization: widget.organization,
      roomNumber: _room?.roomNumber,
      buildingName: _building?.name,
      tenantEmail: _tenant?.email ?? '',
    );
  }

  // ── Line item card ──────────────────────────
  Widget _buildLineItemCard(
      InvoiceLineItem item, int index, AppTranslations t) {
    final label = _typeLabels(t)[item.type.name] ?? item.type.name;
    final color = _typeColor(item.type);
    final dateFormat = t.dateFormat;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      if (item.billingStartDate != null &&
                          item.billingEndDate != null)
                        Text(
                          '${DateFormat(dateFormat).format(item.billingStartDate!)} → ${DateFormat(dateFormat).format(item.billingEndDate!)}',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    ReportingMoney.format(widget.payment.organizationId, item.amount, widget.payment.currency),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Meter readings (electricity)
          if (item.type == PaymentType.electricity &&
              item.electricityStartReading != null) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      _meterCell(
                          t['meter_start_reading'],
                          '${item.electricityStartReading} kWh',
                          date: item.electricityStartDate,
                          dateFormat: dateFormat),
                      Container(
                          width: 1, height: 40, color: Colors.grey.shade100),
                      _meterCell(
                          t['meter_end_reading'],
                          '${item.electricityEndReading} kWh',
                          date: item.electricityEndDate,
                          dateFormat: dateFormat),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _consumptionRow(
                    icon: Icons.bolt_rounded,
                    color: const Color(0xFFF59E0B),
                    label: t['calc_preview_consumption_label'],
                    value: t.textWithParams('meter_consumption_kwh', {
                      'value': ((item.electricityEndReading ?? 0) -
                              (item.electricityStartReading ?? 0))
                          .toStringAsFixed(1),
                    }),
                    rate: item.electricityPricePerUnit != null
                        ? '× ${ReportingMoney.format(widget.payment.organizationId, item.electricityPricePerUnit!, widget.payment.currency)}/kWh'
                        : null,
                  ),
                ],
              ),
            ),
          ],

          // Meter readings (water)
          if (item.type == PaymentType.water &&
              item.waterStartReading != null) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      _meterCell(
                          t['meter_start_reading'],
                          '${item.waterStartReading} m³',
                          date: item.waterStartDate,
                          dateFormat: dateFormat),
                      Container(
                          width: 1, height: 40, color: Colors.grey.shade100),
                      _meterCell(
                          t['meter_end_reading'],
                          '${item.waterEndReading} m³',
                          date: item.waterEndDate,
                          dateFormat: dateFormat),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _consumptionRow(
                    icon: Icons.water_drop_rounded,
                    color: const Color(0xFF06B6D4),
                    label: t['calc_preview_consumption_label'],
                    value: t.textWithParams('meter_consumption_m3', {
                      'value': ((item.waterEndReading ?? 0) -
                              (item.waterStartReading ?? 0))
                          .toStringAsFixed(1),
                    }),
                    rate: item.waterPricePerUnit != null
                        ? '× ${ReportingMoney.format(widget.payment.organizationId, item.waterPricePerUnit!, widget.payment.currency)}/m³'
                        : null,
                  ),
                ],
              ),
            ),
          ],

          // Rent unit-price breakdown (theo ngày/tháng/năm)
          if (item.type == PaymentType.rent &&
              item.rentPriceMode != null &&
              item.rentPriceMode != RentPriceMode.direct &&
              item.rentUnitPrice != null &&
              item.rentUnitQuantity != null) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: _consumptionRow(
                icon: Icons.calculate_rounded,
                color: const Color(0xFF6366F1),
                label: '',
                value:
                    '${item.rentPriceMode == RentPriceMode.daily ? item.rentUnitQuantity!.toStringAsFixed(0) : item.rentUnitQuantity!.toStringAsFixed(2)} ${_rentUnitShort(t, item.rentPriceMode!)}',
                rate:
                    '× ${ReportingMoney.format(widget.payment.organizationId, item.rentUnitPrice!, widget.payment.currency)}/${_rentUnitShort(t, item.rentPriceMode!)}',
              ),
            ),
          ],

          if (item.description != null && item.description!.isNotEmpty) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.notes_rounded,
                      size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(item.description!,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _meterCell(String label, String value,
          {DateTime? date, required String dateFormat}) =>
      Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              if (date != null)
                Text(DateFormat(dateFormat).format(date),
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ),
      );

  Widget _consumptionRow({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    String? rate,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            if (label.isNotEmpty) ...[
              Text(label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 6),
            ],
            Text(value,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color)),
            if (rate != null) ...[
              const SizedBox(width: 6),
              Text(rate,
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
            ],
          ],
        ),
      );

  // ── Amount rows ─────────────────────────────
  Widget _amountRow(String label, double amount,
          {Color? color, bool large = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: large ? 15 : 13,
                  fontWeight: large ? FontWeight.w700 : FontWeight.w500,
                  color: color ?? Colors.grey.shade700,
                )),
            Text(
              ReportingMoney.format(widget.payment.organizationId, amount, widget.payment.currency),
              style: TextStyle(
                fontSize: large ? 17 : 14,
                fontWeight: FontWeight.w700,
                color: color ?? Colors.grey.shade800,
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final isPhone = MediaQuery.of(context).size.width < 600;
    final payment = widget.payment;
    final lineItems = _parseLineItems(payment);
    final statusColor = _statusColor(payment.status);
    final dateFormat = t.dateFormat;

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
                // ── HEADER ──────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        statusColor.withValues(alpha: 0.9),
                        statusColor.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 12, 20),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(_statusIcon(payment.status),
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t['view_details'],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                )),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                _statusLabels(t)[payment.status.name] ??
                                    payment.getStatusDisplayName(t),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // ── BODY ────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Info card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade100),
                          ),
                          child: Column(
                            children: [
                              _infoRow(
                                Icons.person_outline_rounded,
                                t['tenant_label'],
                                payment.tenantName ?? t['tenant_unknown'],
                              ),
                              if (_room != null)
                                _infoRow(
                                  Icons.door_front_door_outlined,
                                  t['tenant_detail_room'],
                                  _room!.roomNumber,
                                ),
                              if (_building != null)
                                _infoRow(
                                  Icons.apartment_rounded,
                                  t['tenant_detail_building'],
                                  _building!.name,
                                ),
                              _infoRow(
                                Icons.calendar_today_rounded,
                                t['due_date_label'],
                                DateFormat(dateFormat).format(payment.dueDate),
                              ),
                              if (payment.paidAt != null)
                                _infoRow(
                                  Icons.check_circle_outline_rounded,
                                  t['excel_col_paid_date'],
                                  DateFormat(dateFormat).format(payment.paidAt!),
                                  valueColor: const Color(0xFF22C55E),
                                ),
                            ],
                          ),
                        ),

                        _sectionLabel(t['payment_section_items']),

                        ...List.generate(lineItems.length,
                            (i) => _buildLineItemCard(lineItems[i], i, t)),

                        _sectionLabel(t['pdf_section_payment_summary']),

                        // Totals card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade100),
                          ),
                          child: Column(
                            children: [
                              _amountRow(t['payment_total_label'],
                                  payment.amount),
                              if (payment.lateFee != null &&
                                  payment.lateFee! > 0)
                                _amountRow(t['del_payment_late_fee'],
                                    payment.lateFee!,
                                    color: const Color(0xFFEF4444)),
                              if (payment.taxAmount != null &&
                                  payment.taxAmount! > 0)
                                _amountRow(t['payment_tax_label'],
                                    payment.taxAmount!,
                                    color: const Color(0xFFF59E0B)),
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Divider(color: Colors.grey.shade200),
                              ),
                              _amountRow(t['del_payment_grand_total'],
                                  payment.totalAmount,
                                  color: statusColor,
                                  large: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // ── FOOTER ──────────────────────────────
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      if (widget.isAdmin && widget.onEdit != null && widget.payment.bookingId == null)
                        Row(children: [
                          Expanded(
                            child: _actionButton(
                              label: t['edit'],
                              icon: Icons.edit_rounded,
                              color: const Color(0xFF3B82F6),
                              onTap: () {
                                Navigator.pop(context);
                                widget.onEdit!();
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _actionButton(
                              label: t['delete'],
                              icon: Icons.delete_rounded,
                              color: const Color(0xFFEF4444),
                              onTap: () => _showDeleteConfirmation(t),
                            ),
                          ),
                        ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: _actionButton(
                            label: t['export_pdf'],
                            icon: Icons.picture_as_pdf_rounded,
                            color: const Color(0xFFF59E0B),
                            loading: _isLoadingRoomData,
                            onTap: _isLoadingRoomData ? null : _exportToPDF,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _actionButton(
                            label: t['export_excel'],
                            icon: Icons.table_chart_rounded,
                            color: const Color(0xFF22C55E),
                            loading: _isLoadingRoomData,
                            onTap: _isLoadingRoomData ? null : _exportToExcel,
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

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    bool loading = false,
  }) =>
      Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (loading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: color),
                  )
                else
                  Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ],
            ),
          ),
        ),
      );

  void _showDeleteConfirmation(AppTranslations t) {
    _showTrackedDialog(
      context: context,
      builder: (ctx) => AppAlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Text(t['del_payment_title']),
        ]),
        content: Text(t['del_payment_cannot_undo']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t['cancel']),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await widget.paymentService.deletePayment(widget.payment.id);
              if (mounted) {
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(t['del_payment_success'])),
                );
              }
            },
            child: Text(t['delete']),
          ),
        ],
      ),
    );
  }
}
