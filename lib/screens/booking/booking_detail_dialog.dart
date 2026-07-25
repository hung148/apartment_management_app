import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_notifier.dart';

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
    final method = await showDialog<PaymentMethod>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Phương thức thanh toán'),
        children: PaymentMethod.values
            .map((m) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, m),
                  child: Text(m.name),
                ))
            .toList(),
      ),
    );
    if (method == null) return;
    await _runAction(
      () => _bookingService.checkOut(_booking.id, paymentMethod: method),
      onSuccess: () => _paymentsNotifier.refreshPayments(_booking.organizationId),
    );
  }

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Hủy đặt phòng'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Lý do (không bắt buộc)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Xác nhận hủy'),
            ),
          ],
        );
      },
    );
    if (reason == null) return;
    await _runAction(() => _bookingService.cancelBooking(_booking.id, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_booking.guestName,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_booking.getStatusDisplayName(), style: const TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(_booking.guestPhone, style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 16),

              _detailRow('Nhận phòng', fmt.format(_booking.startTime)),
              _detailRow('Trả phòng', fmt.format(_booking.endTime)),
              _detailRow('Thời lượng', '${_booking.durationHours.toStringAsFixed(1)} giờ'),
              _detailRow('Tổng tiền', _formatCurrency(_booking.totalPrice)),
              _detailRow('Đã thanh toán', _formatCurrency(_booking.paidAmount)),
              if (_booking.depositAmount != null)
                _detailRow('Tiền cọc', _formatCurrency(_booking.depositAmount!)),
              if (_booking.notes != null && _booking.notes!.isNotEmpty)
                _detailRow('Ghi chú', _booking.notes!),

              const SizedBox(height: 18),
              if (_busy)
                const Center(child: CircularProgressIndicator())
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_booking.status == BookingStatus.pending || _booking.status == BookingStatus.confirmed)
                      ElevatedButton.icon(
                        onPressed: _checkIn,
                        icon: const Icon(Icons.login_rounded, size: 16),
                        label: const Text('Nhận phòng'),
                      ),
                    if (_booking.status == BookingStatus.checkedIn)
                      ElevatedButton.icon(
                        onPressed: _checkOut,
                        icon: const Icon(Icons.logout_rounded, size: 16),
                        label: const Text('Trả phòng'),
                      ),
                    if (_booking.isActive)
                      OutlinedButton.icon(
                        onPressed: _cancel,
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                        icon: const Icon(Icons.close_rounded, size: 16),
                        label: const Text('Hủy'),
                      ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Đóng'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}