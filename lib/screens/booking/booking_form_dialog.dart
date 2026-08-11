import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';

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
}

// How the "Giá" total is being produced for this booking.
enum _PriceMode {
  manual,     // Staff types the total directly.
  hourlyRate, // Total = (đơn giá/giờ) × số giờ, recalculated live.
}

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
  final _rateController = TextEditingController();
  final _depositController = TextEditingController();

  late DateTime _start;
  late DateTime _end;
  bool _isOvernight = false;
  late _PriceMode _priceMode;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    // Default to per-hour auto pricing when the room has a configured rate;
    // otherwise fall back to manual entry so staff aren't stuck with a 0đ field.
    _priceMode = widget.room.hasHourlyPricing ? _PriceMode.hourlyRate : _PriceMode.manual;
    _rateController.text = widget.room.hourlyPrice != null
        ? widget.room.hourlyPrice!.toStringAsFixed(0)
        : '';
    _recalculatePrice();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _priceController.dispose();
    _rateController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  /// Overnight preset always uses the room's fixed overnight price.
  /// Otherwise: manual mode leaves whatever the staff typed alone; hourlyRate
  /// mode recomputes total = rate × duration every time start/end/rate change.
  void _recalculatePrice() {
    if (_isOvernight) {
      try {
        final result = _bookingService.calculatePrice(
          room: widget.room,
          start: _start,
          end: _end,
          isOvernightPreset: true,
        );
        _priceController.text = result.price.toStringAsFixed(0);
      } catch (_) {
        _priceController.text = '0';
      }
      return;
    }

    if (_priceMode == _PriceMode.manual) return;

    final rate = double.tryParse(_rateController.text) ?? widget.room.hourlyPrice ?? 0;
    final hours = _end.difference(_start).inMinutes / 60.0;
    final total = hours > 0 ? rate * hours : 0.0;
    _priceController.text = total.toStringAsFixed(0);
  }

  bool _isDurationSelected(Duration duration) =>
      !_isOvernight && _end.difference(_start) == duration;

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

  void _setPriceMode(_PriceMode mode) {
    setState(() {
      _priceMode = mode;
      if (mode == _PriceMode.hourlyRate) _recalculatePrice();
    });
  }

  /// Date and time are now two separate, independently-tappable controls
  /// (see _dateTimeCard) instead of one control that chained a date dialog
  /// into a time dialog — that chaining was the "can only change the date"
  /// bug: whichever picker step got skipped/dismissed, nothing committed.
  void _applyPicked(bool isStart, DateTime combined) {
    setState(() {
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

  Future<void> _pickDate(bool isStart) async {
    final initial = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    _applyPicked(isStart, DateTime(date.year, date.month, date.day, initial.hour, initial.minute));
  }

  Future<void> _pickClock(bool isStart) async {
    final initial = isStart ? _start : _end;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !mounted) return;
    _applyPicked(isStart, DateTime(initial.year, initial.month, initial.day, time.hour, time.minute));
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
    final isSmall = MediaQuery.of(context).size.width < 600;
    final hours = _end.difference(_start).inMinutes / 60.0;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isSmall ? double.infinity : 460,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionLabel(Icons.person_rounded, 'THÔNG TIN KHÁCH'),
                      const SizedBox(height: 10),
                      _styledField(
                        controller: _nameController,
                        label: 'Tên khách',
                        icon: Icons.person_outline_rounded,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Bắt buộc' : null,
                      ),
                      const SizedBox(height: 12),
                      _styledField(
                        controller: _phoneController,
                        label: 'Số điện thoại',
                        icon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Bắt buộc' : null,
                      ),

                      const SizedBox(height: 20),
                      _sectionLabel(Icons.schedule_rounded, 'THỜI GIAN'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _durationChip('1 giờ', _isDurationSelected(const Duration(hours: 1)),
                              () => _applyDurationPreset(const Duration(hours: 1))),
                          _durationChip('2 giờ', _isDurationSelected(const Duration(hours: 2)),
                              () => _applyDurationPreset(const Duration(hours: 2))),
                          _durationChip('3 giờ', _isDurationSelected(const Duration(hours: 3)),
                              () => _applyDurationPreset(const Duration(hours: 3))),
                          if (widget.room.overnightPrice != null)
                            _durationChip('Qua đêm', _isOvernight, _applyOvernightPreset,
                                icon: Icons.nightlight_round),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 8),
                        child: Text(
                          'Hoặc chọn ngày và giờ riêng bên dưới — nhận và trả phòng có thể khác ngày.',
                          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                        ),
                      ),
                      _dateTimeCard(
                        label: 'Nhận phòng',
                        icon: Icons.login_rounded,
                        value: _start,
                        onTapDate: () => _pickDate(true),
                        onTapTime: () => _pickClock(true),
                      ),
                      const SizedBox(height: 10),
                      _dateTimeCard(
                        label: 'Trả phòng',
                        icon: Icons.logout_rounded,
                        value: _end,
                        onTapDate: () => _pickDate(false),
                        onTapTime: () => _pickClock(false),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: _DS.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.hourglass_bottom_rounded, size: 14, color: _DS.primary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hours > 0
                                    ? 'Thời lượng thực tế: ${hours.toStringAsFixed(1)} giờ (${fmt.format(_start)} → ${fmt.format(_end)})'
                                    : 'Giờ trả phòng phải sau giờ nhận phòng',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: hours > 0 ? _DS.primary : const Color(0xFFA32D2D),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      _sectionLabel(Icons.payments_rounded, 'THANH TOÁN'),
                      const SizedBox(height: 10),

                      if (!_isOvernight) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _durationChip('Nhập tay', _priceMode == _PriceMode.manual,
                                () => _setPriceMode(_PriceMode.manual),
                                icon: Icons.edit_rounded),
                            _durationChip('Theo giờ', _priceMode == _PriceMode.hourlyRate,
                                () => _setPriceMode(_PriceMode.hourlyRate),
                                icon: Icons.calculate_rounded),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_priceMode == _PriceMode.hourlyRate) ...[
                          _styledField(
                            controller: _rateController,
                            label: 'Đơn giá / giờ',
                            icon: Icons.sell_rounded,
                            keyboardType: TextInputType.number,
                            suffixText: 'VND/giờ',
                            onChanged: (_) => setState(_recalculatePrice),
                            validator: (v) {
                              if (_priceMode != _PriceMode.hourlyRate) return null;
                              final r = double.tryParse(v ?? '');
                              if (r == null || r <= 0) return 'Không hợp lệ';
                              return null;
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 4, bottom: 4),
                            child: Text(
                              hours > 0
                                  ? '${hours.toStringAsFixed(1)} giờ × ${NumberFormat('#,###', 'vi_VN').format(double.tryParse(_rateController.text) ?? 0)} đ/giờ'
                                  : 'Chọn giờ nhận/trả phòng hợp lệ để tính giá',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ],

                      Row(
                        children: [
                          Expanded(
                            child: _styledField(
                              controller: _priceController,
                              label: 'Giá',
                              icon: Icons.sell_rounded,
                              keyboardType: TextInputType.number,
                              suffixText: 'VND',
                              readOnly: !_isOvernight && _priceMode == _PriceMode.hourlyRate,
                              validator: (v) =>
                                  (v == null || double.tryParse(v) == null) ? 'Không hợp lệ' : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _styledField(
                              controller: _depositController,
                              label: 'Tiền cọc',
                              icon: Icons.savings_rounded,
                              keyboardType: TextInputType.number,
                              suffixText: 'VND',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _styledField(
                        controller: _notesController,
                        label: 'Ghi chú',
                        icon: Icons.notes_rounded,
                        maxLines: 2,
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        _errorBanner(_error!),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
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
          child: const Icon(Icons.event_available_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Đặt phòng ${widget.room.roomNumber}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                widget.building.name,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
    );
  }

  // ── SECTION LABEL ────────────────────────────────────────────
  Widget _sectionLabel(IconData icon, String label) {
    return Row(children: [
      Icon(icon, size: 14, color: _DS.primary),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _DS.primary,
          letterSpacing: 0.8,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: _DS.primary.withValues(alpha: 0.15), thickness: 1)),
    ]);
  }

  // ── STYLED FIELD ─────────────────────────────────────────────
  Widget _styledField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    TextInputType? keyboardType,
    String? suffixText,
    bool readOnly = false,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      readOnly: readOnly,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixText,
        prefixIcon: Icon(icon, size: 18, color: _DS.textSecondary),
        filled: true,
        fillColor: readOnly ? _DS.primaryLight : _DS.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: readOnly ? _DS.primary.withValues(alpha: 0.25) : Colors.grey.withValues(alpha: 0.22)),
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

  // ── DURATION / MODE CHIP ─────────────────────────────────────
  Widget _durationChip(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? _DS.primary : _DS.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _DS.primary : Colors.grey.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected ? Colors.white : _DS.textSecondary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : _DS.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── DATE/TIME CARD ────────────────────────────────────────────
  // Date and time are separate tappable chips on purpose: tapping the whole
  // card used to chain a date dialog straight into a time dialog, and if
  // that second dialog got skipped (back button, tap outside, etc.) nothing
  // was saved — from the user's side it looked like "only the date changes".
  // Two direct single-purpose buttons remove that failure mode entirely.
  Widget _dateTimeCard({
    required String label,
    required IconData icon,
    required DateTime value,
    required VoidCallback onTapDate,
    required VoidCallback onTapTime,
  }) {
    final dateFmt = DateFormat('dd/MM/yyyy');
    final timeFmt = DateFormat('HH:mm');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _DS.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: _DS.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _miniPickerChip(
                  icon: Icons.calendar_today_rounded,
                  text: dateFmt.format(value),
                  onTap: onTapDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniPickerChip(
                  icon: Icons.access_time_rounded,
                  text: timeFmt.format(value),
                  onTap: onTapTime,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniPickerChip({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _DS.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _DS.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _DS.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.edit_rounded, size: 11, color: _DS.primary.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFCEBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFA32D2D).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFA32D2D)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Color(0xFFA32D2D), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── ACTIONS ──────────────────────────────────────────────────
  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.1))),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: _DS.textSecondary,
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_rounded, size: 17),
            label: Text(_saving ? 'Đang lưu...' : 'Đặt phòng',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            style: FilledButton.styleFrom(
              backgroundColor: _DS.primary,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }
}
