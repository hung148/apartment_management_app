import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';

class BookingFormDialog extends StatefulWidget {
  final Organization organization;
  final Building building;
  final Room room;
  final DateTime initialStart;
  final DateTime initialEnd;

  const BookingFormDialog({
    required this.organization,
    required this.building,
    required this.room,
    required this.initialStart,
    required this.initialEnd,
    super.key,
  });

  @override
  State<BookingFormDialog> createState() => _BookingFormDialogState();
}

class _BookingFormDialogState extends State<BookingFormDialog> {
  final BookingService _bookingService = getIt<BookingService>();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  final _priceController = TextEditingController();
  final _depositController = TextEditingController();

  late DateTime _start;
  late DateTime _end;
  bool _isOvernight = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _recalculatePrice();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _priceController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  void _recalculatePrice() {
    try {
      final result = _bookingService.calculatePrice(
        room: widget.room,
        start: _start,
        end: _end,
        isOvernightPreset: _isOvernight,
      );
      _priceController.text = result.price.toStringAsFixed(0);
    } catch (_) {
      _priceController.text = '0';
    }
  }

  void _applyDurationPreset(Duration duration) {
    setState(() {
      _isOvernight = false;
      _end = _start.add(duration);
      _recalculatePrice();
    });
  }

  void _applyOvernightPreset() {
    setState(() {
      _isOvernight = true;
      // Default: 22:00 today -> 12:00 next day
      _start = DateTime(_start.year, _start.month, _start.day, 22);
      _end = DateTime(_start.year, _start.month, _start.day + 1, 12);
      _recalculatePrice();
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return;

    setState(() {
      final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _isOvernight = false;
      if (isStart) {
        _start = combined;
        if (!_end.isAfter(_start)) _end = _start.add(const Duration(hours: 1));
      } else {
        _end = combined;
      }
      _recalculatePrice();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'Giờ kết thúc phải sau giờ bắt đầu');
      return;
    }
    final minHours = widget.room.minBookingHours ?? 0;
    if (_end.difference(_start).inMinutes / 60.0 < minHours) {
      setState(() => _error = 'Thời gian đặt tối thiểu là $minHours giờ');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final booking = RoomBooking(
        id: '',
        organizationId: widget.organization.id,
        buildingId: widget.building.id,
        roomId: widget.room.id,
        guestName: _nameController.text.trim(),
        guestPhone: _phoneController.text.trim(),
        startTime: _start,
        endTime: _end,
        pricingType: _isOvernight ? BookingPricingType.overnight : BookingPricingType.hourly,
        totalPrice: double.tryParse(_priceController.text) ?? 0,
        depositAmount: _depositController.text.isEmpty ? null : double.tryParse(_depositController.text),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        createdAt: DateTime.now(),
      );

      await _bookingService.createBooking(booking);
      if (mounted) Navigator.of(context).pop(true);
    } on BookingConflictException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Lỗi: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Đặt phòng ${widget.room.roomNumber}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Tên khách', border: OutlineInputBorder()),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Bắt buộc' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phoneController,
                    decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder()),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Bắt buộc' : null,
                  ),
                  const SizedBox(height: 14),

                  Wrap(
                    spacing: 8,
                    children: [
                      ActionChip(label: const Text('1 giờ'), onPressed: () => _applyDurationPreset(const Duration(hours: 1))),
                      ActionChip(label: const Text('2 giờ'), onPressed: () => _applyDurationPreset(const Duration(hours: 2))),
                      ActionChip(label: const Text('3 giờ'), onPressed: () => _applyDurationPreset(const Duration(hours: 3))),
                      if (widget.room.overnightPrice != null)
                        ActionChip(label: const Text('Qua đêm'), onPressed: _applyOvernightPreset),
                    ],
                  ),
                  const SizedBox(height: 10),

                  InkWell(
                    onTap: () => _pickTime(true),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Nhận phòng', border: OutlineInputBorder()),
                      child: Text(fmt.format(_start)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    onTap: () => _pickTime(false),
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Trả phòng', border: OutlineInputBorder()),
                      child: Text(fmt.format(_end)),
                    ),
                  ),
                  const SizedBox(height: 10),

                  TextFormField(
                    controller: _priceController,
                    decoration: const InputDecoration(labelText: 'Giá (VND)', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    validator: (v) => (v == null || double.tryParse(v) == null) ? 'Không hợp lệ' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _depositController,
                    decoration: const InputDecoration(
                      labelText: 'Tiền cọc (VND, không bắt buộc)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(labelText: 'Ghi chú', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ],

                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Đặt phòng'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}