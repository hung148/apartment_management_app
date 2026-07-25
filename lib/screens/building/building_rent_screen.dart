import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_notifier.dart';

/// Full-screen replacement for the old "Building rent" dialog.
class BuildingRentScreen extends StatefulWidget {
  final Organization organization;
  final Building building;

  const BuildingRentScreen({
    required this.organization,
    required this.building,
    super.key,
  });

  @override
  State<BuildingRentScreen> createState() => _BuildingRentScreenState();
}

class _BuildingRentScreenState extends State<BuildingRentScreen> {
  final PaymentService _paymentService = getIt<PaymentService>();
  final PaymentsNotifier _paymentsNotifier = getIt<PaymentsNotifier>();

  // Bump this to force the FutureBuilder to refetch after adding a payment.
  int _refreshTick = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final building = widget.building;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF854F0B),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t['building_rent_tab_label'],
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(building.name,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
          ],
        ),
      ),
      body: FutureBuilder<List<Payment>>(
        key: ValueKey(_refreshTick),
        future: _paymentService.getBuildingRentPayments(
            widget.organization.id, building.id),
        builder: (context, snapshot) {
          final payments = snapshot.data ?? [];
          final isLoading = snapshot.connectionState == ConnectionState.waiting;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Renter info card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAEEDA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFF854F0B).withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rentInfoRow(
                          t['building_renter_name_label'], building.renterName ?? '—'),
                      _rentInfoRow(
                          t['building_renter_phone_label'], building.renterPhone ?? '—'),
                      _rentInfoRow(
                          t['building_rent_amount_label'],
                          building.rentAmount != null
                              ? _formatCurrency(building.rentAmount!)
                              : '—'),
                      _rentInfoRow(t['building_rent_due_day_label'],
                          building.rentDueDay?.toString() ?? '—'),
                      if (building.rentContractStart != null)
                        _rentInfoRow(
                            t['building_rent_contract_start_label'],
                            DateFormat('dd/MM/yyyy').format(building.rentContractStart!)),
                      if (building.rentContractEnd != null)
                        _rentInfoRow(
                            t['building_rent_contract_end_label'],
                            DateFormat('dd/MM/yyyy').format(building.rentContractEnd!)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(t['building_rent_payment_history'],
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    TextButton.icon(
                      onPressed: () async {
                        final changed =
                            await _showBuildingRentPaymentDialog(building);
                        if (changed == true) setState(() => _refreshTick++);
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(t['building_rent_add_payment']),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (payments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(t['building_rent_no_payments'],
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    ),
                  )
                else
                  ...payments.map((p) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_formatCurrency(p.amount),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${t['due_date_label']}: ${DateFormat('dd/MM/yyyy').format(p.dueDate)}',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _getPaymentStatusColor(p.status).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(p.getStatusDisplayName(),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: _getPaymentStatusColor(p.status))),
                            ),
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: Icon(Icons.more_vert,
                                  size: 18, color: Colors.grey.shade400),
                              onSelected: (action) =>
                                  _handleBuildingRentPaymentAction(action, p),
                              itemBuilder: (menuContext) => [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(children: [
                                    const Icon(Icons.edit, size: 18),
                                    const SizedBox(width: 8),
                                    Text(t['edit_payment']),
                                  ]),
                                ),
                                if (p.status != PaymentStatus.paid)
                                  PopupMenuItem(
                                    value: 'mark_paid',
                                    child: Row(children: [
                                      const Icon(Icons.check_circle_outline_rounded,
                                          size: 18, color: Colors.green),
                                      const SizedBox(width: 8),
                                      Text(t['mark_as_paid']),
                                    ]),
                                  ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(children: [
                                    const Icon(Icons.delete, size: 18, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Text(t['delete_payment'],
                                        style: const TextStyle(color: Colors.red)),
                                  ]),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _rentInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  /// Shared dialog for both adding a new building-rent payment and editing an
  /// existing one. Pass [existing] to edit; omit it to add a new payment.
  Future<bool?> _showBuildingRentPaymentDialog(
    Building building, {
    Payment? existing,
  }) async {
    final t = AppTranslations.of(context);
    final isEditing = existing != null;
    final amountController =
        TextEditingController(text: isEditing ? existing.amount.toStringAsFixed(0) : '');
    final descController = TextEditingController(text: existing?.description ?? '');
    DateTime dueDate = existing?.dueDate ?? DateTime.now().add(const Duration(days: 7));

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(isEditing
              ? t['edit_payment']
              : t['building_rent_add_payment']),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t['building_rent_amount_label'],
                    suffixText: 'VND',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t['due_date_label']),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(dueDate)),
                  trailing: const Icon(Icons.calendar_today_rounded, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: dueDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setDialogState(() => dueDate = picked);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: t['payment_notes_label'],
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t['cancel']),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim());
                if (amount == null || amount <= 0) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(t['add_item_err_amount'])),
                  );
                  return;
                }
                final description = descController.text.trim().isEmpty
                    ? null
                    : descController.text.trim();

                bool success;
                if (isEditing) {
                  success = await _paymentsNotifier.updatePayment(
                    existing.id,
                    {
                      'amount': amount,
                      'dueDate': Timestamp.fromDate(dueDate),
                      'description': description,
                    },
                    organizationId: widget.organization.id,
                  );
                } else {
                  final id = await _paymentsNotifier.addBuildingRentPayment(
                    organizationId: widget.organization.id,
                    buildingId: building.id,
                    amount: amount,
                    dueDate: dueDate,
                    description: description,
                  );
                  success = id != null;
                }

                if (dialogContext.mounted) Navigator.pop(dialogContext, success);
              },
              child: Text(t['building_save']),
            ),
          ],
        ),
      ),
    );

    amountController.dispose();
    descController.dispose();
    return result;
  }

  void _handleBuildingRentPaymentAction(String action, Payment payment) {
    switch (action) {
      case 'edit':
        _showBuildingRentPaymentDialog(widget.building, existing: payment)
            .then((changed) {
          if (changed == true) setState(() => _refreshTick++);
        });
        break;
      case 'mark_paid':
        _markBuildingRentPaymentPaid(payment);
        break;
      case 'delete':
        _confirmDeleteBuildingRentPayment(payment);
        break;
    }
  }

  Future<void> _markBuildingRentPaymentPaid(Payment payment) async {
    final t = AppTranslations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final success = await _paymentsNotifier.updatePaymentStatus(payment.id, PaymentStatus.paid).then((_) => true).catchError((_) => false);
    if (!mounted) return;
    if (success) {
      setState(() => _refreshTick++);
      messenger.showSnackBar(SnackBar(
        content: Text(t['mark_as_paid_success']),
        backgroundColor: const Color(0xFF3B6D11),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(t['generic_error']),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _confirmDeleteBuildingRentPayment(Payment payment) async {
    final t = AppTranslations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t['delete_payment']),
        content: Text(t['building_rent_delete_payment_confirm']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t['cancel']),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t['delete'], style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final success = await _paymentsNotifier.deletePayment(payment.id).then((_) => true).catchError((_) => false);
    if (!mounted) return;
    if (success) {
      setState(() => _refreshTick++);
      messenger.showSnackBar(SnackBar(
        content: Text(t['delete_payment_success']),
        backgroundColor: const Color(0xFF3B6D11),
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(t['generic_error']),
        backgroundColor: Colors.red,
      ));
    }
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return '${formatter.format(amount)} ₫';
  }

  Color _getPaymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.pending:
        return Colors.orange;
      case PaymentStatus.paid:
        return Colors.green;
      case PaymentStatus.overdue:
        return Colors.red;
      case PaymentStatus.cancelled:
        return Colors.grey;
      case PaymentStatus.refunded:
        return Colors.purple;
      case PaymentStatus.partial:
        return Colors.blue;
    }
  }
}