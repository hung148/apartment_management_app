part of 'room_detail.dart';

// Payment list, summary cards, dialog actions, and quick PDF export.
// The room detail screen owns state, services, lifecycle, and subscriptions.
extension _RoomDetailPayments on _RoomDetailScreenState {
  // ═══════════════════════════════════════════════════════════════
  // BUILD PAYMENTS TAB
  // ═══════════════════════════════════════════════════════════════
  Widget _buildPaymentsTab() {
    return ListenableBuilder(
      listenable: widget.paymentsNotifier,
      builder: (context, _) {
        final t = AppTranslations.of(context);
        final allPayments = widget.paymentsNotifier.payments
            .where((p) => p.roomId == widget.room.id)
            .toList();

        return FutureBuilder<Membership?>(
          future: _getMyMembership(),
          builder: (context, membershipSnapshot) {
            final isAdmin = membershipSnapshot.hasData &&
                membershipSnapshot.data!.role == 'admin';

            if (allPayments.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: AppThemePalette.primaryLight,
                          shape: BoxShape.circle),
                      child: Icon(Icons.receipt_long_outlined,
                          size: 48, color: AppThemePalette.primaryMid),
                    ),
                    const SizedBox(height: 12),
                    Text(t['room_detail_no_payments'],
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    Text(t['room_detail_no_payments_hint'],
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500)),
                    if (isAdmin) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _showAddPaymentDialog,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppThemePalette.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add_rounded,
                            color: Colors.white),
                        label: Text(t['room_detail_create_invoice'],
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              );
            }

            final sorted = List<Payment>.from(allPayments)
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

            final pending = sorted
                .where((p) => p.status == PaymentStatus.pending)
                .length;
            final overdue = sorted.where((p) => p.isOverdue).length;
            final paid =
                sorted.where((p) => p.status == PaymentStatus.paid).length;
            final totalCollected = ReportingMoney.total(widget.organization.id, sorted, (p) {
              if (p.status == PaymentStatus.paid)
                return p.paidAmount > 0 ? p.paidAmount : p.totalWithAllFees;
              return p.paidAmount;
            });

            return ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    children: [
                      _payKpiCell(pending.toString(),
                          t['room_detail_kpi_pending'],
                          const Color(0xFF854F0B)),
                      _kpiDivider(),
                      _payKpiCell(overdue.toString(),
                          t['room_detail_kpi_overdue'],
                          const Color(0xFFA32D2D)),
                      _kpiDivider(),
                      _payKpiCell(paid.toString(),
                          t['room_detail_kpi_collected'],
                          const Color(0xFF3B6D11)),
                      _kpiDivider(),
                      _payKpiCell(
                          totalCollected ?? '—',
                          t['room_detail_kpi_total'],
                          const Color(0xFF185FA5)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _sectionLabel(
                    t['room_detail_section_invoices'], sorted.length),
                const SizedBox(height: 8),
                ...sorted.map((p) => _buildRichPaymentCard(p, isAdmin)),
              ],
            );
          },
        );
      },
    );
  }

  Widget _payKpiCell(String value, String label, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _kpiDivider() =>
      Container(width: 0.5, height: 38, color: Colors.grey.shade200);

  Widget _buildRichPaymentCard(Payment payment, bool isAdmin) {
    final t = AppTranslations.of(context);
    final statusColor = _getPaymentStatusColor(payment.status);
    final words = (payment.tenantName ?? '?').trim().split(' ');
    final initials = words.length >= 2
        ? '${words.first[0]}${words.last[0]}'.toUpperCase()
        : (payment.tenantName?.isNotEmpty == true
            ? payment.tenantName![0].toUpperCase()
            : '?');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
              color: statusColor.withOpacity(0.08),
              blurRadius: 14,
              offset: const Offset(0, 4))
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showPaymentDetailDialog(payment, isAdmin),
        child: Column(
          children: [
            Container(height: 4, color: statusColor),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12)),
                    child: Center(
                      child: Text(initials,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: statusColor)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(payment.tenantName ?? '—',
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(payment.getStatusDisplayName(t),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: statusColor)),
                          ),
                        ]),
                        const SizedBox(height: 4),
                        Text(_formatCurrency(payment.totalAmount,payment.currency),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _tenantInfoChip(
                                Icons.label_outline_rounded,
                                _getPaymentTypeDisplayName(
                                    context, payment.type),
                                Colors.grey.shade600),
                            _tenantInfoChip(
                                Icons.calendar_today_outlined,
                                t.textWithParams('room_detail_due_date_chip',
                                    {'date': _formatDate(payment.dueDate)}),
                                payment.isOverdue
                                    ? const Color(0xFFA32D2D)
                                    : Colors.grey.shade600),
                            if (payment.paidAt != null)
                              _tenantInfoChip(
                                  Icons.check_circle_outline_rounded,
                                  _formatDate(payment.paidAt!),
                                  const Color(0xFF3B6D11)),
                            if (payment.status == PaymentStatus.partial &&
                                payment.remainingAmount > 0)
                              _tenantInfoChip(
                                  Icons.pending_outlined,
                                  t.textWithParams(
                                      'room_detail_remaining_chip', {
                                    'amount': _formatCurrency(
                                        payment.remainingAmount, payment.currency)
                                  }),
                                  const Color(0xFF185FA5)),
                            if (payment.isOverdue)
                              _tenantInfoChip(
                                  Icons.warning_amber_rounded,
                                  t.textWithParams(
                                      'room_detail_overdue_chip',
                                      {'days': payment.daysOverdue}),
                                  const Color(0xFFA32D2D)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    Builder(
                      builder: (btnContext) => IconButton(
                        icon: Icon(Icons.more_vert_rounded,
                            size: 18, color: Colors.grey.shade600),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          final td = AppTranslations.of(btnContext);
                          final RenderBox button =
                              btnContext.findRenderObject() as RenderBox;
                          final RenderBox overlay =
                              Overlay.of(btnContext).context.findRenderObject()
                                  as RenderBox;
                          final Offset buttonTopLeft = button.localToGlobal(
                              Offset.zero,
                              ancestor: overlay);
                          final Offset buttonBottomRight =
                              button.localToGlobal(
                                  button.size.bottomRight(Offset.zero),
                                  ancestor: overlay);
                          final RelativeRect position =
                              RelativeRect.fromLTRB(
                            buttonTopLeft.dx,
                            buttonBottomRight.dy,
                            overlay.size.width - buttonBottomRight.dx,
                            overlay.size.height - buttonTopLeft.dy,
                          );
                          showMenu<String>(
                            context: btnContext,
                            position: position,
                            items: [
                              PopupMenuItem(
                                value: 'view',
                                child: Row(children: [
                                  Icon(Icons.visibility_rounded,
                                      size: 18, color: AppThemePalette.primary),
                                  const SizedBox(width: 8),
                                  Text(td['room_detail_pay_menu_view']),
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(children: [
                                  Icon(Icons.edit_rounded,
                                      size: 18,
                                      color: Colors.orange.shade700),
                                  const SizedBox(width: 8),
                                  Text(td['room_detail_pay_menu_edit']),
                                ]),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(children: [
                                  Icon(Icons.delete_rounded,
                                      size: 18, color: Colors.red.shade700),
                                  const SizedBox(width: 8),
                                  Text(td['room_detail_pay_menu_delete'],
                                      style: TextStyle(
                                          color: Colors.red.shade700)),
                                ]),
                              ),
                            ],
                          ).then((value) {
                            if (value == 'view')
                              _showPaymentDetailDialog(payment, isAdmin);
                            else if (value == 'edit')
                              _showEditPaymentDialog(payment);
                            else if (value == 'delete')
                              _showDeletePaymentDialog(payment);
                          });
                        },
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

  Color _getPaymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:   return Colors.orange;
      case PaymentStatus.paid:      return Colors.green;
      case PaymentStatus.overdue:   return Colors.red;
      case PaymentStatus.cancelled: return Colors.grey;
      case PaymentStatus.refunded:  return Colors.purple;
      case PaymentStatus.partial:   return AppThemePalette.primary;
    }
  }

  String _getPaymentTypeDisplayName(BuildContext context, PaymentType type) {
    final t = AppTranslations.of(context);
    switch (type) {
      case PaymentType.rent:        return t['payment_type_rent'];
      case PaymentType.electricity: return t['payment_type_electricity'];
      case PaymentType.water:       return t['payment_type_water'];
      case PaymentType.internet:    return t['payment_type_internet'];
      case PaymentType.parking:     return t['payment_type_parking'];
      case PaymentType.maintenance: return t['payment_type_maintenance'];
      case PaymentType.deposit:     return t['payment_type_deposit'];
      case PaymentType.penalty:     return t['payment_type_penalty'];
      case PaymentType.buildingRent: return t['payment_type_building_rent'];
      case PaymentType.hourlyRent: return t['payment_type_hourly_rent'];
      case PaymentType.other:       return t['payment_type_other'];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // PAYMENT METHODS
  // ═══════════════════════════════════════════════════════════════
  void _showAddPaymentDialog() {
    _showTrackedDialog(
      context: context,
      builder: (context) => ImprovedPaymentFormDialog(
        organization: widget.organization,
        buildingService: widget.buildingService,
        roomService: widget.roomService,
        tenantService: widget.tenantService,
        paymentService: widget.paymentService,
        room: widget.room,
      ),
    ).then((result) {
      if (result == true)
        widget.paymentsNotifier
            .loadRoomPayments(widget.room.id, widget.organization.id);
    });
  }

  void _showPaymentDetailDialog(Payment payment, bool isAdmin) async {
    if (!mounted) return;
    _showTrackedDialog(
      context: context,
      builder: (context) => ViewPaymentDetailsDialog(
        payment: payment,
        isAdmin: isAdmin,
        roomService: widget.roomService,
        buildingService: widget.buildingService,
        organization: widget.organization,
        paymentService: widget.paymentService,
        tenantService: widget.tenantService,
        onEdit: () => _showEditPaymentDialog(payment),
      ),
    );
  }

  void _showEditPaymentDialog(Payment payment) {
    _showTrackedDialog(
      context: context,
      builder: (context) => EditPaymentDialog(
        payment: payment,
        organization: widget.organization,
        buildingService: widget.buildingService,
        roomService: widget.roomService,
        tenantService: widget.tenantService,
        paymentService: widget.paymentService,
      ),
    ).then((result) {
      if (result == true)
        widget.paymentsNotifier
            .loadRoomPayments(widget.room.id, widget.organization.id);
    });
  }

  void _showDeletePaymentDialog(Payment payment) {
    _showTrackedDialog(
      context: context,
      builder: (context) => DeletePaymentDialog(
        payment: payment,
        paymentService: widget.paymentService,
        onDeleted: () => widget.paymentsNotifier
            .loadRoomPayments(widget.room.id, widget.organization.id),
      ),
    );
  }

  Future<void> _showPDFPreview(Payment payment, Tenant? tenant) async {
    await PaymentPDFExporter.showPDFPreview(
      context: context,
      payment: payment,
      organization: widget.organization,
      tenant: tenant,
      room: widget.room,
      roomNumber: widget.room.roomNumber,
    );
  }

  Future<void> _exportPDFQuick(Payment payment, Tenant? tenant) async {
    await PaymentPDFExporter.quickExportPDF(
      context: context,
      payment: payment,
      organization: widget.organization,
      tenant: tenant,
      room: widget.room,
      roomNumber: widget.room.roomNumber,
    );
  }

}
