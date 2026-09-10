import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/responsive_form_row.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';

// ─────────────────────────────────────────────────────────────
// DESIGN TOKENS (mirrors the calendar's indigo kPrimaryColor)
// ─────────────────────────────────────────────────────────────
class _DS {
  static const primary = Color(0xFF4F46E5);
  static const primaryDeep = Color(0xFF3730A3);
  static const primaryMid = Color(0xFF6366F1);
  static const primaryLight = Color(0xFFEEF2FF);
  static const surface = Color(0xFFF8FAFC);
  static const textPrimary = Color(0xFF1E1B4B);
  static const textSecondary = Color(0xFF64748B);
}

// How the "Giá" total is being produced for this booking.
enum _PriceMode {
  manual, // Staff types the total directly.
  hourlyRate, // Total = (đơn giá/giờ) × số giờ, recalculated live.
}

class BookingFormDialog extends StatefulWidget {
  final Organization organization;
  final Building building;
  final Room room;
  final RoomBooking? booking;
  final DateTime initialStart;
  final DateTime initialEnd;

  const BookingFormDialog({
    this.booking,
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
  late final String _bookingId = widget.booking?.id ?? const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    // Default to per-hour auto pricing when the room has a configured rate;
    // otherwise fall back to manual entry so staff aren't stuck with a 0đ field.
    _priceMode = widget.room.hasHourlyPricing
        ? _PriceMode.hourlyRate
        : _PriceMode.manual;
    _rateController.text = widget.room.hourlyPrice != null
        ? CurrencyParser.format(widget.room.hourlyPrice!)
        : '';
    _recalculatePrice();
    if (widget.booking case final booking?) {
      _start = booking.startTime;
      _end = booking.endTime;
      _priceMode = _PriceMode.manual;
      _nameController.text = booking.guestName;
      _phoneController.text = booking.guestPhone;
      _priceController.text = CurrencyParser.format(booking.totalPrice);
      _depositController.text = booking.depositAmount == null
          ? ''
          : CurrencyParser.format(booking.depositAmount!);
      _notesController.text = booking.notes ?? '';
    }
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
        _priceController.text = CurrencyParser.format(result.price);
      } catch (_) {
        _priceController.text = '0';
      }
      return;
    }

    if (_priceMode == _PriceMode.manual) return;

    final rate =
        CurrencyParser.tryParse(_rateController.text) ??
        widget.room.hourlyPrice ??
        0;
    final hours = _end.difference(_start).inMinutes / 60.0;
    final total = hours > 0 ? rate * hours : 0.0;
    _priceController.text = CurrencyParser.format(total);
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
      locale: AppTranslations.of(context).locale,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    _applyPicked(
      isStart,
      DateTime(date.year, date.month, date.day, initial.hour, initial.minute),
    );
  }

  Future<void> _pickClock(bool isStart) async {
    final initial = isStart ? _start : _end;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    _applyPicked(
      isStart,
      DateTime(
        initial.year,
        initial.month,
        initial.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // Captured before the awaits below so no BuildContext is used across an async gap.
    final t = AppTranslations.of(context);
    if (!_end.isAfter(_start)) {
      setState(() => _error = t['booking_form_end_after_start']);
      return;
    }
    final minHours = widget.room.minBookingHours ?? 0;
    if (_end.difference(_start).inMinutes / 60.0 < minHours) {
      setState(
        () => _error = t.textWithParams('booking_form_min_hours', {
          'hours': minHours,
        }),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final booking = RoomBooking(
        id: _bookingId,
        organizationId: widget.organization.id,
        buildingId: widget.building.id,
        roomId: widget.room.id,
        guestName: _nameController.text.trim(),
        guestPhone: _phoneController.text.trim(),
        guestIdNumber: widget.booking?.guestIdNumber,
        numberOfGuests: widget.booking?.numberOfGuests ?? 1,
        source: widget.booking?.source ?? BookingSource.walkIn,
        startTime: _start,
        endTime: _end,
        pricingType:
            widget.booking?.pricingType ??
            (_isOvernight
                ? BookingPricingType.overnight
                : BookingPricingType.hourly),
        currency: (widget.booking?.currency ?? widget.room.currency),
        totalPrice: CurrencyParser.tryParse(_priceController.text) ?? 0,
        depositAmount: _depositController.text.isEmpty
            ? null
            : CurrencyParser.tryParse(_depositController.text),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        createdAt: DateTime.now(),
      );

      if (widget.booking == null) {
        await _bookingService.createBooking(booking);
      } else {
        await _bookingService.updateBooking(_bookingId, booking.toMap());
      }
      if (mounted) Navigator.of(context).pop(true);
    } on BookingConflictException catch (e) {
      if (mounted) setState(() => _error = t[e.message]);
    } catch (e) {
      setState(() => _error = t.textWithParams('error', {'error': e}));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final fmt = DateFormat(t.dateTimeFormat);
    final isSmall = MediaQuery.of(context).size.width < 600;
    final hours = _end.difference(_start).inMinutes / 60.0;

    return AppDialog(
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
                      _sectionLabel(
                        Icons.person_rounded,
                        t['booking_form_guest_section'],
                      ),
                      const SizedBox(height: 10),
                      _styledField(
                        controller: _nameController,
                        label: t['booking_form_guest_name'],
                        icon: Icons.person_outline_rounded,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? t['booking_form_required']
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _styledField(
                        controller: _phoneController,
                        label: t['phone'],
                        icon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? t['booking_form_required']
                            : null,
                      ),

                      const SizedBox(height: 20),
                      _sectionLabel(
                        Icons.schedule_rounded,
                        t['booking_form_time_section'],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _durationChip(
                            t.textWithParams('booking_form_duration_hours', {
                              'count': 1,
                            }),
                            _isDurationSelected(const Duration(hours: 1)),
                            () =>
                                _applyDurationPreset(const Duration(hours: 1)),
                          ),
                          _durationChip(
                            t.textWithParams('booking_form_duration_hours', {
                              'count': 2,
                            }),
                            _isDurationSelected(const Duration(hours: 2)),
                            () =>
                                _applyDurationPreset(const Duration(hours: 2)),
                          ),
                          _durationChip(
                            t.textWithParams('booking_form_duration_hours', {
                              'count': 3,
                            }),
                            _isDurationSelected(const Duration(hours: 3)),
                            () =>
                                _applyDurationPreset(const Duration(hours: 3)),
                          ),
                          if (widget.room.overnightPrice != null)
                            _durationChip(
                              t['booking_form_overnight'],
                              _isOvernight,
                              _applyOvernightPreset,
                              icon: Icons.nightlight_round,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 2, bottom: 8),
                        child: Text(
                          t['booking_form_custom_range_hint'],
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),
                      _dateTimeCard(
                        label: t['booking_check_in'],
                        icon: Icons.login_rounded,
                        value: _start,
                        onTapDate: () => _pickDate(true),
                        onTapTime: () => _pickClock(true),
                      ),
                      const SizedBox(height: 10),
                      _dateTimeCard(
                        label: t['booking_check_out'],
                        icon: Icons.logout_rounded,
                        value: _end,
                        onTapDate: () => _pickDate(false),
                        onTapTime: () => _pickClock(false),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _DS.primaryLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.hourglass_bottom_rounded,
                              size: 14,
                              color: _DS.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hours > 0
                                    ? t.textWithParams(
                                        'booking_form_actual_duration',
                                        {
                                          'hours': hours.toStringAsFixed(1),
                                          'currency':
                                              (widget.booking?.currency ??
                                              widget.room.currency),
                                          'range':
                                              '${fmt.format(_start)} → ${fmt.format(_end)}',
                                        },
                                      )
                                    : t['booking_form_end_after_start'],
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: hours > 0
                                      ? _DS.primary
                                      : const Color(0xFFA32D2D),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),
                      _sectionLabel(
                        Icons.payments_rounded,
                        t['booking_form_payment_section'],
                      ),
                      const SizedBox(height: 10),

                      if (!_isOvernight) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _durationChip(
                              t['booking_form_price_manual'],
                              _priceMode == _PriceMode.manual,
                              () => _setPriceMode(_PriceMode.manual),
                              icon: Icons.edit_rounded,
                            ),
                            _durationChip(
                              t['room_rental_mode_hourly'],
                              _priceMode == _PriceMode.hourlyRate,
                              () => _setPriceMode(_PriceMode.hourlyRate),
                              icon: Icons.calculate_rounded,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_priceMode == _PriceMode.hourlyRate) ...[
                          _styledField(
                            controller: _rateController,
                            label: t['booking_form_hourly_rate'],
                            icon: Icons.sell_rounded,
                            keyboardType: TextInputType.number,
                            suffixText:
                                '${(widget.booking?.currency ?? widget.room.currency)}/${t['unit_hours']}',
                            onChanged: (_) => setState(_recalculatePrice),
                            validator: (v) {
                              if (_priceMode != _PriceMode.hourlyRate)
                                return null;
                              final r = CurrencyParser.tryParse(v ?? '');
                              if (r == null || r <= 0)
                                return t['booking_form_invalid'];
                              return null;
                            },
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              top: 6,
                              left: 4,
                              bottom: 4,
                            ),
                            child: Text(
                              hours > 0
                                  ? t.textWithParams(
                                      'booking_form_price_breakdown',
                                      {
                                        'hours': hours.toStringAsFixed(1),
                                        'currency':
                                            (widget.booking?.currency ??
                                            widget.room.currency),
                                        'rate':
                                            NumberFormat(
                                              '#,##0.##',
                                              'en_US',
                                            ).format(
                                              CurrencyParser.tryParse(
                                                    _rateController.text,
                                                  ) ??
                                                  0,
                                            ),
                                      },
                                    )
                                  : t['booking_form_price_hint'],
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ],

                      ResponsiveFormRow(
                        children: [
                          Expanded(
                            child: _styledField(
                              controller: _priceController,
                              label: t['booking_form_price'],
                              icon: Icons.sell_rounded,
                              keyboardType: TextInputType.number,
                              suffixText:
                                  (widget.booking?.currency ??
                                  widget.room.currency),
                              readOnly:
                                  !_isOvernight &&
                                  _priceMode == _PriceMode.hourlyRate,
                              validator: (v) =>
                                  (v == null ||
                                      CurrencyParser.tryParse(v) == null)
                                  ? t['booking_form_invalid']
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _styledField(
                              controller: _depositController,
                              label: t['payment_type_deposit'],
                              icon: Icons.savings_rounded,
                              keyboardType: TextInputType.number,
                              suffixText:
                                  (widget.booking?.currency ??
                                  widget.room.currency),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _styledField(
                        controller: _notesController,
                        label: t['booking_form_notes'],
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
    final t = AppTranslations.of(context);
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.booking != null
                      ? t['booking_edit']
                      : t.textWithParams('booking_form_title', {
                          'room': widget.room.roomNumber,
                        }),
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
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  // ── SECTION LABEL ────────────────────────────────────────────
  Widget _sectionLabel(IconData icon, String label) {
    return Row(
      children: [
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
        Expanded(
          child: Divider(
            color: _DS.primary.withValues(alpha: 0.15),
            thickness: 1,
          ),
        ),
      ],
    );
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
      inputFormatters: [
        if (controller == _priceController ||
            controller == _rateController ||
            controller == _depositController)
          CurrencyInputFormatter(decimalDigits: 2),
      ],
      keyboardType: suffixText != null
          ? const TextInputType.numberWithOptions(decimal: true)
          : keyboardType,
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
            color: readOnly
                ? _DS.primary.withValues(alpha: 0.25)
                : Colors.grey.withValues(alpha: 0.22),
          ),
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
  Widget _durationChip(
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
  }) {
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
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : _DS.textSecondary,
              ),
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
    final dateFmt = DateFormat(AppTranslations.of(context).dateFormat);
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
          Row(
            children: [
              Icon(icon, size: 14, color: _DS.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
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
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: _DS.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.edit_rounded,
              size: 11,
              color: _DS.primary.withValues(alpha: 0.5),
            ),
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
        border: Border.all(
          color: const Color(0xFFA32D2D).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: Color(0xFFA32D2D),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFA32D2D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ACTIONS ──────────────────────────────────────────────────
  Widget _buildActions() {
    final t = AppTranslations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving
                  ? null
                  : () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: _DS.textSecondary,
                side: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                t['cancel'],
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_rounded, size: 17),
              label: Text(
                _saving
                    ? t['booking_form_saving']
                    : widget.booking != null
                    ? t['save']
                    : t['booking_form_submit'],
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _DS.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
