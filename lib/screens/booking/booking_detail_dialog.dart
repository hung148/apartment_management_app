import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_notifier.dart';

// ─────────────────────────────────────────────────────────────
// DESIGN TOKENS (mirrors the calendar's indigo kPrimaryColor)
// ─────────────────────────────────────────────────────────────
class _DS {
  static const primary       = Color(0xFF4F46E5);
  static const primaryDeep   = Color(0xFF3730A3);
  static const primaryMid    = Color(0xFF6366F1);
  static const primaryLight  = Color(0xFFEEF2FF);
  static const surface       = Color(0xFFF8FAFC);
  static const textPrimary   = Color(0xFF1E1B4B);
  static const textSecondary = Color(0xFF64748B);
  static const danger        = Color(0xFFA32D2D);
  static const dangerDeep    = Color(0xFF7A1F1F);
}

class BookingDetailDialog extends StatefulWidget {
  final RoomBooking booking;
  const BookingDetailDialog({required this.booking, super.key});

  @override
  State<BookingDetailDialog> createState() => _BookingDetailDialogState();
}

class _BookingDetailDialogState extends State<BookingDetailDialog> {
  final BookingService _bookingService = getIt<BookingService>();
  final PaymentsNotifier _paymentsNotifier = getIt<PaymentsNotifier>();

  late RoomBooking _booking;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _booking = widget.booking;
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return '${formatter.format(amount)} ₫';
  }

  Color _statusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return const Color(0xFFEF9F27);
      case BookingStatus.confirmed:
        return const Color(0xFF185FA5);
      case BookingStatus.checkedIn:
        return const Color(0xFF3B6D11);
      case BookingStatus.checkedOut:
        return Colors.grey.shade500;
      case BookingStatus.cancelled:
      case BookingStatus.noShow:
        return Colors.grey.shade400;
    }
  }

  Color _statusColorDeep(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return const Color(0xFFB9740D);
      case BookingStatus.confirmed:
        return const Color(0xFF0F3F6E);
      case BookingStatus.checkedIn:
        return const Color(0xFF264D0C);
      case BookingStatus.checkedOut:
        return Colors.grey.shade700;
      case BookingStatus.cancelled:
      case BookingStatus.noShow:
        return Colors.grey.shade600;
    }
  }

  Future<void> _refresh() async {
    final updated = await _bookingService.getBookingById(_booking.id);
    if (updated != null && mounted) setState(() => _booking = updated);
  }

  Future<void> _runAction(Future<bool> Function() action, {VoidCallback? onSuccess}) async {
    setState(() => _busy = true);
    try {
      final success = await action();
      if (success) {
        await _refresh();
        onSuccess?.call();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkIn() => _runAction(() => _bookingService.checkIn(_booking.id));

  Future<void> _checkOut() async {
    final method = await _showPaymentMethodDialog();
    if (method == null) return;
    await _runAction(
      () => _bookingService.checkOut(_booking.id, paymentMethod: method),
      onSuccess: () => _paymentsNotifier.refreshPayments(_booking.organizationId),
    );
  }

  Future<PaymentMethod?> _showPaymentMethodDialog() {
    IconData iconFor(PaymentMethod m) {
      final name = m.name.toLowerCase();
      if (name.contains('cash') || name.contains('tien_mat')) return Icons.payments_rounded;
      if (name.contains('card') || name.contains('the')) return Icons.credit_card_rounded;
      if (name.contains('bank') || name.contains('transfer') || name.contains('chuyen_khoan')) {
        return Icons.account_balance_rounded;
      }
      return Icons.account_balance_wallet_rounded;
    }

    return showDialog<PaymentMethod>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: Colors.white,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                    child: const Icon(Icons.wallet_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Phương thức thanh toán',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: PaymentMethod.values.map((m) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: _DS.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(ctx, m),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.18)),
                            ),
                            child: Row(children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: _DS.primaryLight,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Icon(iconFor(m), size: 17, color: _DS.primary),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  m.name,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600, color: _DS.textPrimary),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade400),
                            ]),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
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
                    colors: [_DS.danger, _DS.dangerDeep],
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
                      child: const Icon(Icons.event_busy_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Hủy đặt phòng',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Lý do (không bắt buộc)',
                        prefixIcon: const Icon(Icons.notes_rounded, size: 18, color: _DS.textSecondary),
                        filled: true,
                        fillColor: _DS.surface,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.22)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _DS.danger, width: 1.8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _DS.textSecondary,
                            side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Đóng', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx, controller.text),
                          style: FilledButton.styleFrom(
                            backgroundColor: _DS.danger,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text('Xác nhận hủy',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
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
    if (reason == null) return;
    await _runAction(() => _bookingService.cancelBooking(_booking.id, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final statusColor = _statusColor(_booking.status);
    final statusColorDeep = _statusColorDeep(_booking.status);
    final isSmall = MediaQuery.of(context).size.width < 600;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isSmall ? double.infinity : 440,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [statusColor, statusColorDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _booking.guestName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _booking.guestPhone,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _booking.getStatusDisplayName(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(true),
                    icon: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            // ── Details ──────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _DS.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                  ),
                  child: Column(
                    children: [
                      _detailRow(Icons.login_rounded, 'Nhận phòng', fmt.format(_booking.startTime)),
                      _detailRow(Icons.logout_rounded, 'Trả phòng', fmt.format(_booking.endTime)),
                      _detailRow(Icons.schedule_rounded, 'Thời lượng',
                          '${_booking.durationHours.toStringAsFixed(1)} giờ'),
                      _detailRow(Icons.payments_rounded, 'Tổng tiền', _formatCurrency(_booking.totalPrice),
                          valueColor: _DS.primary, bold: true),
                      _detailRow(Icons.check_circle_outline_rounded, 'Đã thanh toán',
                          _formatCurrency(_booking.paidAmount)),
                      if (_booking.depositAmount != null)
                        _detailRow(Icons.savings_rounded, 'Tiền cọc',
                            _formatCurrency(_booking.depositAmount!)),
                      if (_booking.notes != null && _booking.notes!.isNotEmpty)
                        _detailRow(Icons.notes_rounded, 'Ghi chú', _booking.notes!, isLast: true),
                    ],
                  ),
                ),
              ),
            ),
            // ── Actions ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: _busy
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: _DS.primary)),
                    )
                  : Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_booking.status == BookingStatus.pending ||
                            _booking.status == BookingStatus.confirmed)
                          FilledButton.icon(
                            onPressed: _checkIn,
                            icon: const Icon(Icons.login_rounded, size: 16),
                            label: const Text('Nhận phòng'),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF3B6D11),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        if (_booking.status == BookingStatus.checkedIn)
                          FilledButton.icon(
                            onPressed: _checkOut,
                            icon: const Icon(Icons.logout_rounded, size: 16),
                            label: const Text('Trả phòng'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _DS.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        if (_booking.isActive)
                          OutlinedButton.icon(
                            onPressed: _cancel,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _DS.danger,
                              side: BorderSide(color: _DS.danger.withValues(alpha: 0.4)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text('Hủy'),
                          ),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _DS.textSecondary,
                            side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Đóng', style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade400),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: valueColor ?? _DS.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
