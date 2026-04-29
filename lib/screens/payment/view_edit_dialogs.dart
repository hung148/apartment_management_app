import 'dart:async';

import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/payment_excel_export.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/payment_pdf_export.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/currency_formatter.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/date_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────
// SHARED HELPERS & CONSTANTS
// ─────────────────────────────────────────────

Map<String, String> _typeLabels(AppTranslations t) => {
  'rent': t['payment_type_rent'],
  'electricity': t['payment_type_electricity'],
  'water': t['payment_type_water'],
  'internet': t['payment_type_internet'],
  'parking': t['payment_type_parking'],
  'maintenance': t['payment_type_maintenance'],
  'deposit': t['payment_type_deposit'],
  'penalty': t['payment_type_penalty'],
  'other': t['payment_type_other'],
};

Map<String, String> _statusLabels(AppTranslations t) => {
  'pending': t['status_pending'],
  'paid': t['status_paid'],
  'overdue': t['status_overdue'],
  'cancelled': t['status_cancelled'],
  'refunded': t['status_refunded'],
  'partial': t['status_partial'],
};

Color _statusColor(PaymentStatus status) {
  switch (status) {
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

IconData _statusIcon(PaymentStatus status) {
  switch (status) {
    case PaymentStatus.paid:
      return Icons.check_circle_rounded;
    case PaymentStatus.pending:
      return Icons.schedule_rounded;
    case PaymentStatus.overdue:
      return Icons.warning_amber_rounded;
    case PaymentStatus.cancelled:
      return Icons.cancel_rounded;
    case PaymentStatus.refunded:
      return Icons.undo_rounded;
    case PaymentStatus.partial:
      return Icons.incomplete_circle_rounded;
  }
}

Color _typeColor(PaymentType type) {
  switch (type) {
    case PaymentType.rent:
      return const Color(0xFF6366F1);
    case PaymentType.electricity:
      return const Color(0xFFF59E0B);
    case PaymentType.water:
      return const Color(0xFF06B6D4);
    case PaymentType.internet:
      return const Color(0xFF8B5CF6);
    case PaymentType.parking:
      return const Color(0xFF10B981);
    case PaymentType.maintenance:
      return const Color(0xFFEF4444);
    case PaymentType.deposit:
      return const Color(0xFF3B82F6);
    case PaymentType.penalty:
      return const Color(0xFFDC2626);
    case PaymentType.other:
      return const Color(0xFF6B7280);
  }
}

// ─────────────────────────────────────────────
// InvoiceLineItem MODEL
// ─────────────────────────────────────────────

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

List<InvoiceLineItem> _parseLineItems(Payment payment) {
  if (payment.type == PaymentType.electricity &&
      payment.electricityStartReading != null) {
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

  final description = payment.description;
  if (description != null && description.contains('\n')) {
    final lines = description.split('\n');
    final items = <InvoiceLineItem>[];
    for (var line in lines) {
      final match = RegExp(r'^([^:]+):\s*([\d,]+)\s*VND(?:\s*\((.+)\))?$')
          .firstMatch(line.trim());
      if (match != null) {
        final typeLabel = match.group(1)?.trim() ?? '';
        final amountStr = match.group(2)?.replaceAll(',', '') ?? '0';
        final desc = match.group(3);
        const labelToType = {
          'Tiền thuê': PaymentType.rent,
          'Rent': PaymentType.rent,
          'Tiền điện': PaymentType.electricity,
          'Electricity': PaymentType.electricity,
          'Tiền nước': PaymentType.water,
          'Water': PaymentType.water,
          'Tiền internet': PaymentType.internet,
          'Internet': PaymentType.internet,
          'Tiền gửi xe': PaymentType.parking,
          'Parking': PaymentType.parking,
          'Phí bảo trì': PaymentType.maintenance,
          'Maintenance': PaymentType.maintenance,
          'Tiền cọc': PaymentType.deposit,
          'Deposit': PaymentType.deposit,
          'Tiền phạt': PaymentType.penalty,
          'Penalty': PaymentType.penalty,
          'Khác': PaymentType.other,
          'Other': PaymentType.other,
        };
        items.add(InvoiceLineItem(
          id: DateTime.now().millisecondsSinceEpoch.toString() +
              items.length.toString(),
          type: labelToType[typeLabel] ?? PaymentType.other,
          amount: double.tryParse(amountStr) ?? 0,
          description: desc,
        ));
      }
    }
    if (items.isNotEmpty) return items;
  }

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

// ─────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────

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

Widget _infoRow(IconData icon, String label, String value,
    {Color? valueColor}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.grey.shade800,
            ),
          ),
        ),
      ],
    ),
  );
}

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
  bool _isDismissing = false;

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
      final sz = MediaQuery.sizeOf(context);
      if (sz.width < 360 || sz.height < 600) _dismissAllOverlays();
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
                    '${NumberFormat('#,###').format(item.amount)} đ',
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
                        ? '× ${NumberFormat('#,###').format(item.electricityPricePerUnit)} đ/kWh'
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
                        ? '× ${NumberFormat('#,###').format(item.waterPricePerUnit)} đ/m³'
                        : null,
                  ),
                ],
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
                      size: 14, color: Colors.grey.shade400),
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
                        fontSize: 10, color: Colors.grey.shade400)),
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
            Text(label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            const SizedBox(width: 6),
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
              '${NumberFormat('#,###').format(amount)} VND',
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
                          color: Colors.white.withOpacity(0.2),
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
                                    payment.getStatusDisplayName(),
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
                      if (widget.isAdmin && widget.onEdit != null)
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
                              onTap: () => _showDeleteConfirmation(context, t),
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

  void _showDeleteConfirmation(BuildContext context, AppTranslations t) {
    _showTrackedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
  int _overlayCount = 0;
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

  double get _totalAmount =>
      _lineItems.fold(0.0, (sum, item) => sum + item.amount);

  Timer? _resizeDebounceTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notesController = TextEditingController(text: widget.payment.notes);
    _taxAmountController = TextEditingController(
      text: widget.payment.taxAmount?.toString() ?? '0.0',
    );
    _paidAmountController = TextEditingController(
      text: widget.payment.paidAmount.toStringAsFixed(0),
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
      final sz = MediaQuery.sizeOf(context);
      if (sz.width < 360 || sz.height < 600) _dismissAllOverlays();
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

  Future<void> _loadData() async {
    try {
      final tenants = await widget.tenantService
          .getOrganizationTenants(widget.organization.id);
      setState(() {
        _tenants = tenants;
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
    final t = AppTranslations.of(context);
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
                amountController.text = ((e - s) * p).toStringAsFixed(0);
              }
            } else if (selectedType == PaymentType.water &&
                !waterUseDirectAmount) {
              final s = double.tryParse(waterStartCtrl.text) ?? 0;
              final e = double.tryParse(waterEndCtrl.text) ?? 0;
              final p = CurrencyParser.parse(waterPriceCtrl.text);
              if (e >= s && p > 0) {
                amountController.text = ((e - s) * p).toStringAsFixed(0);
              }
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
                border: Border.all(color: color.withOpacity(0.18)),
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

          return Dialog(
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
                      padding: const EdgeInsets.all(20),
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
                            onChanged: (v) => setDialogState(
                                () => selectedType = v),
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
                                  keyboardType: TextInputType.number,
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
                                  keyboardType: TextInputType.number,
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
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: _inputDec(
                                    dt['add_item_elec_price'],
                                    Icons.price_change_rounded,
                                    suffix: 'đ/kWh'),
                                keyboardType: TextInputType.number,
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
                                  keyboardType: TextInputType.number,
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
                                  keyboardType: TextInputType.number,
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
                                inputFormatters: [CurrencyInputFormatter()],
                                decoration: _inputDec(
                                    dt['add_item_water_price'],
                                    Icons.price_change_rounded,
                                    suffix: 'đ/m³'),
                                keyboardType: TextInputType.number,
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
                                onDateChanged: (d) =>
                                    setDialogState(() => billingStart = d),
                              )),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: CompactLocalizedDatePicker(
                                labelText: dt['add_item_to_date'],
                                initialDate: billingEnd,
                                onDateChanged: (d) =>
                                    setDialogState(() => billingEnd = d),
                              )),
                            ]),
                            const SizedBox(height: 16),
                          ],

                          // Amount
                          TextFormField(
                            controller: amountController,
                            inputFormatters: [CurrencyInputFormatter()],
                            decoration: _inputDec(dt['add_item_amount'],
                                Icons.payments_rounded,
                                suffix: 'VND'),
                            keyboardType: TextInputType.number,
                            readOnly: (selectedType ==
                                        PaymentType.electricity &&
                                    !electricityUseDirectAmount) ||
                                (selectedType == PaymentType.water &&
                                    !waterUseDirectAmount),
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
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
            const SizedBox(height: 4),
            Text(t['payment_items_empty_hint'],
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
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
                  color: color.withOpacity(0.12),
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
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${NumberFormat('#,###').format(item.amount)} đ',
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
            color: Theme.of(context).primaryColor.withOpacity(0.06),
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
                '${NumberFormat('#,###').format(_totalAmount)} VND',
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
        return '$typeLabel: ${NumberFormat('#,###').format(item.amount)} VND$desc';
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
                // ── HEADER ─────────────────────────────
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
                            value: _tenants
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
                                  child: Text(ten.fullName ?? ''))),
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
                              inputFormatters: [CurrencyInputFormatter()],
                              decoration: _inputDec(
                                t['del_payment_total'],
                                Icons.payments_outlined,
                                suffix: 'VND',
                                helper:
                                    '${t['payment_total_label']} ${NumberFormat('#,###').format(_totalAmount)} VND',
                              ),
                              keyboardType: TextInputType.number,
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
                            inputFormatters: [CurrencyInputFormatter()],
                            decoration: _inputDec(t['payment_tax_label'],
                                Icons.receipt_rounded,
                                suffix: 'VND'),
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            validator: (v) {
                              if (v != null && v.isNotEmpty) {
                                if (double.tryParse(v) == null) {
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
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Text(usage,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );