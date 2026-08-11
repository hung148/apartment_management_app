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
import 'package:phan_mem_quan_ly_can_ho/widgets/date_picker.dart';

// ─────────────────────────────────────────────────────────────
// DESIGN TOKENS (amber accent — mirrors the "rented" theme used
// for this building type elsewhere in the app, e.g. BuildingDialog's
// _DS but tuned to the amber palette already used for rent UI)
// ─────────────────────────────────────────────────────────────
class _DS {
  static const primary       = Color(0xFF854F0B);
  static const primaryDeep   = Color(0xFF5E3806);
  static const primaryMid    = Color(0xFF9C5E0E);
  static const primaryLight  = Color(0xFFFAEEDA);
  static const surface       = Color(0xFFFBF8F3);
  static const textPrimary   = Color(0xFF35260F);
  static const textSecondary = Color(0xFF8A7660);
}

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
      backgroundColor: _DS.surface,
      appBar: AppBar(
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_DS.primaryMid, _DS.primaryDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(t['back'],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          )),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.real_estate_agent_rounded,
                  size: 18, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t['building_rent_tab_label'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis),
                  Text(building.name,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _renterInfoCard(t, building),
                const SizedBox(height: 20),
                _sectionLabel(
                    Icons.receipt_long_rounded, t['building_rent_payment_history']),
                const SizedBox(height: 10),
                _addPaymentButton(t, building),
                const SizedBox(height: 12),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                        child: CircularProgressIndicator(color: _DS.primary)),
                  )
                else if (payments.isEmpty)
                  _emptyPaymentsState(t)
                else
                  ...payments.map((p) => _paymentCard(t, p)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── RENTER INFO CARD ─────────────────────────────────────────
  Widget _renterInfoCard(AppTranslations t, Building building) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: _DS.primary.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 5, color: _DS.primary),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: _DS.primaryLight,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.person_rounded,
                          color: _DS.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            building.renterName ?? '—',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _DS.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.phone_rounded,
                                  size: 12, color: Colors.grey.shade400),
                              const SizedBox(width: 4),
                              Text(
                                building.renterPhone ?? '—',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _DS.primaryLight,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.real_estate_agent_rounded,
                              size: 11, color: _DS.primary),
                          const SizedBox(width: 4),
                          Text(t['building_management_rented'],
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _DS.primary,
                              )),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _statChip(
                      value: building.rentAmount != null
                          ? _formatCurrency(building.rentAmount!)
                          : '—',
                      label: t['building_rent_amount_label'],
                    ),
                    const SizedBox(width: 8),
                    _statChip(
                      value: building.rentDueDay?.toString() ?? '—',
                      label: t['building_rent_due_day_label'],
                    ),
                  ],
                ),
                if (building.rentContractStart != null ||
                    building.rentContractEnd != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _DS.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event_note_rounded,
                            size: 15, color: Colors.grey.shade500),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${building.rentContractStart != null ? DateFormat('dd/MM/yyyy').format(building.rentContractStart!) : '—'}'
                            '  →  '
                            '${building.rentContractEnd != null ? DateFormat('dd/MM/yyyy').format(building.rentContractEnd!) : '—'}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statChip({required String value, required String label}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: _DS.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _DS.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── SECTION LABEL ────────────────────────────────────────────
  Widget _sectionLabel(IconData icon, String label) {
    return Row(children: [
      Icon(icon, size: 14, color: _DS.primary),
      const SizedBox(width: 6),
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _DS.primary,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Divider(color: _DS.primary.withValues(alpha: 0.15), thickness: 1),
      ),
    ]);
  }

  // ── ADD PAYMENT BUTTON ───────────────────────────────────────
  Widget _addPaymentButton(AppTranslations t, Building building) {
    return Material(
      color: _DS.primaryLight,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        hoverColor: _DS.primary.withValues(alpha: 0.08),
        onTap: () async {
          final changed = await _showBuildingRentPaymentDialog(building);
          if (changed == true) setState(() => _refreshTick++);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _DS.primary, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.add_rounded, color: _DS.primary, size: 20),
              const SizedBox(width: 6),
              Text(t['building_rent_add_payment'],
                  style: const TextStyle(
                    color: _DS.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyPaymentsState(AppTranslations t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded, size: 44, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(t['building_rent_no_payments'],
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }

  // ── PAYMENT CARD ──────────────────────────────────────────────
  Widget _paymentCard(AppTranslations t, Payment p) {
    final statusColor = _getPaymentStatusColor(p.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.payments_rounded, size: 18, color: statusColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_formatCurrency(p.amount),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _DS.textPrimary)),
                  const SizedBox(height: 2),
                  Text(
                    '${t['due_date_label']}: ${DateFormat('dd/MM/yyyy').format(p.dueDate)}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(p.getStatusDisplayName(),
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
            ),
            const SizedBox(width: 2),
            Builder(
              builder: (buttonContext) => IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade400),
                onPressed: () => _showPaymentActionMenu(buttonContext, p),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the payment row's action menu, positioning it below the button by
  /// default but flipping above whenever there isn't enough room underneath
  /// (e.g. the row sits near the bottom of the screen).
  Future<void> _showPaymentActionMenu(BuildContext buttonContext, Payment p) async {
    final t = AppTranslations.of(context);

    final RenderBox button = buttonContext.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;

    final buttonTopLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final buttonSize = button.size;

    // Rough estimated menu height based on how many items will render.
    final itemCount = p.status != PaymentStatus.paid ? 3 : 2;
    final estimatedMenuHeight = itemCount * 48.0 + 16;

    const belowGap = 6.0;
    const aboveGap = 14.0;

    final spaceBelow =
        overlay.size.height - (buttonTopLeft.dy + buttonSize.height);
    final spaceAbove = buttonTopLeft.dy;
    final openAbove =
        spaceBelow < estimatedMenuHeight && spaceAbove > spaceBelow;

    final position = RelativeRect.fromLTRB(
      buttonTopLeft.dx,
      openAbove
          ? buttonTopLeft.dy - estimatedMenuHeight - aboveGap
          : buttonTopLeft.dy + buttonSize.height + belowGap,
      overlay.size.width - (buttonTopLeft.dx + buttonSize.width),
      openAbove ? overlay.size.height - buttonTopLeft.dy + aboveGap : 0,
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            const Icon(Icons.edit_rounded, size: 18, color: _DS.primary),
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
            const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
            const SizedBox(width: 8),
            Text(t['delete_payment'], style: const TextStyle(color: Colors.red)),
          ]),
        ),
      ],
    );

    if (action != null) _handleBuildingRentPaymentAction(action, p);
  }

  /// Shared dialog for both adding a new building-rent payment and editing an
  /// existing one. Pass [existing] to edit; omit it to add a new payment.
  Future<bool?> _showBuildingRentPaymentDialog(
    Building building, {
    Payment? existing,
  }) async {
    final t = AppTranslations.of(context);
    final isEditing = existing != null;
    final amountController = TextEditingController(
        text: isEditing ? existing.amount.toStringAsFixed(0) : '');
    final descController = TextEditingController(text: existing?.description ?? '');
    DateTime dueDate = existing?.dueDate ?? DateTime.now().add(const Duration(days: 7));
    String? amountError;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final isSmall = MediaQuery.of(dialogContext).size.width < 600;
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            elevation: 0,
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isSmall ? MediaQuery.of(dialogContext).size.width * 0.95 : 480,
                maxHeight: MediaQuery.of(dialogContext).size.height * 0.9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_DS.primaryMid, _DS.primaryDeep],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isEditing ? Icons.edit_rounded : Icons.add_card_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          isEditing ? t['edit_payment'] : t['building_rent_add_payment'],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        icon: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.close_rounded,
                              color: Colors.white, size: 18),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ]),
                  ),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dialogField(
                            controller: amountController,
                            label: t['building_rent_amount_label'],
                            icon: Icons.payments_rounded,
                            keyboardType: TextInputType.number,
                            suffixText: 'VND',
                            errorText: amountError,
                            onChanged: (_) {
                              if (amountError != null) {
                                setDialogState(() => amountError = null);
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                          CompactLocalizedDatePicker(
                            labelText: t['due_date_label'],
                            initialDate: dueDate,
                            onDateChanged: (d) {
                              if (d != null) setDialogState(() => dueDate = d);
                            },
                          ),
                          const SizedBox(height: 14),
                          _dialogField(
                            controller: descController,
                            label: t['payment_notes_label'],
                            icon: Icons.notes_rounded,
                            maxLines: 2,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  // Actions
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                          top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
                      borderRadius:
                          const BorderRadius.vertical(bottom: Radius.circular(24)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _DS.textSecondary,
                            side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(t['cancel'],
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () async {
                            final amount = double.tryParse(amountController.text.trim());
                            if (amount == null || amount <= 0) {
                              setDialogState(
                                  () => amountError = t['add_item_err_amount']);
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
                                renterName: building.renterName,
                              );
                              success = id != null;
                            }

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, success);
                            }
                          },
                          icon: Icon(
                              isEditing ? Icons.save_rounded : Icons.add_rounded,
                              size: 17),
                          label: Text(t['building_save'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          style: FilledButton.styleFrom(
                            backgroundColor: _DS.primary,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
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

    amountController.dispose();
    descController.dispose();
    return result;
  }

  Widget _dialogField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? suffixText,
    String? errorText,
    Function(String)? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixText,
        errorText: errorText,
        prefixIcon: Icon(icon, size: 18, color: _DS.textSecondary),
        filled: true,
        fillColor: _DS.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.22)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _DS.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.4),
        ),
        labelStyle: const TextStyle(fontSize: 13, color: _DS.textSecondary),
      ),
    );
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
    final success = await _paymentsNotifier
        .updatePaymentStatus(payment.id, PaymentStatus.paid)
        .then((_) => true)
        .catchError((_) => false);
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
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFD64545), Color(0xFFA32D2D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.delete_outline_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t['delete_payment'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  children: [
                    Text(
                      t['building_rent_delete_payment_confirm'],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: _DS.textPrimary),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _DS.textSecondary,
                            side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(t['cancel'],
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFA32D2D),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: Text(t['delete'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
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
    );
    if (confirm != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final success = await _paymentsNotifier
        .deletePayment(payment.id)
        .then((_) => true)
        .catchError((_) => false);
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