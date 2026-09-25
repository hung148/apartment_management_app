import 'package:phan_mem_quan_ly_can_ho/widgets/searchable_select_field.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/exchange_rate_service.dart';
import 'package:flutter/services.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/building/room/room_detail.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/payment/payment_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/booking/booking_form_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/booking/booking_detail_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';

class AvailabilityCalendarScreen extends StatefulWidget {
  /// If null, the screen loads every building in the organization and lets
  /// the user pick one via the header dropdown. If provided, that building
  /// is preselected but the user can still switch away from it.
  final Building? initialBuilding;
  final Organization organization;

  /// When true the screen is hosted inside another screen's tab bar, so it
  /// skips its own AppBar (and back button) and shows a compact toolbar with
  /// the building picker and day/month switch instead.
  final bool embedded;

  /// Extra right-hand padding for the embedded toolbar, so the host screen can
  /// reserve the top-right corner for a control of its own.
  final double trailingInset;

  const AvailabilityCalendarScreen({
    this.initialBuilding,
    required this.organization,
    this.embedded = false,
    this.trailingInset = 0,
    super.key,
  });

  @override
  State<AvailabilityCalendarScreen> createState() =>
      _AvailabilityCalendarScreenState();
}

enum _ViewMode { day, week, month, agenda }

class _RoomDayStatus {
  final Room room;
  final bool occupied;
  final DateTime? earliestTime;
  final Color? color;
  const _RoomDayStatus({
    required this.room,
    required this.occupied,
    this.earliestTime,
    this.color,
  });
}

class _AvailabilityCalendarScreenState
    extends State<AvailabilityCalendarScreen> {
  Color get kPrimaryColor => Theme.of(context).colorScheme.primary;

  final RoomService _roomService = getIt<RoomService>();
  final BookingService _bookingService = getIt<BookingService>();
  final BuildingService _buildingService = getIt<BuildingService>();
  final TenantService _tenantService = getIt<TenantService>();

  String? _rangeRoomId;
  DateTime? _rangeStart;
  DateTime? _rangeHover;

  void _clearRange() {
    if (_rangeStart != null)
      setState(() {
        _rangeRoomId = null;
        _rangeStart = null;
        _rangeHover = null;
      });
  }

  DateTime _slotAt(double x) {
    final minutes = ((x / _pixelsPerHour * 60) / 30).round() * 30;
    return DateUtils.dateOnly(
      _selectedDate,
    ).add(Duration(minutes: minutes.clamp(0, 1440)));
  }

  void _selectSlot(Room room, DateTime time) {
    final t = AppTranslations.of(context);
    if (!room.supportsHourlyBooking) {
      _clearRange();
      _openRoomPanel(room);
      return;
    }
    if (_rangeStart == null || _rangeRoomId != room.id) {
      if (!DateUtils.isSameDay(time, _selectedDate) ||
          !_withinOperatingHours(room, time.hour))
        return;
      setState(() {
        _rangeRoomId = room.id;
        _rangeStart = time;
        _rangeHover = null;
      });
      return;
    }
    final start = _rangeStart!;
    final buffer = Duration(minutes: room.cleaningBufferMinutes ?? 0);
    final conflict = (_dayBookings[room.id] ?? []).any(
      (b) =>
          b.isActive &&
          start.subtract(buffer).isBefore(b.endTime) &&
          time.add(buffer).isAfter(b.startTime),
    );
    final endMinute = time
        .difference(DateUtils.dateOnly(_selectedDate))
        .inMinutes;
    final invalidHours =
        room.operatingHoursEndMin != null &&
        endMinute > room.operatingHoursEndMin!;
    if (time.difference(start).inMinutes < (room.minBookingHours ?? 1) * 60 ||
        invalidHours ||
        conflict) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t[conflict ? 'booking_conflict' : 'calendar_range_invalid'],
          ),
        ),
      );
      return;
    }
    _clearRange();
    _openBookingForm(room, start, time);
  }

  Widget _rangeInstructions() {
    final t = AppTranslations.of(context);
    final room = _allRooms.where((r) => r.id == _rangeRoomId).firstOrNull;
    return Container(
      key: const ValueKey('calendar-range-instructions'),
      width: double.infinity,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _rangeStart == null
            ? Colors.white
            : Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimaryColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app_outlined, size: 20, color: kPrimaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _rangeStart == null
                  ? t['calendar_range_hint']
                  : t.textWithParams('calendar_range_end', {
                      'room': room?.roomNumber ?? '',
                      'time': DateFormat.Hm().format(_rangeStart!),
                    }),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (_rangeStart != null)
            TextButton(onPressed: _clearRange, child: Text(t['cancel'])),
        ],
      ),
    );
  }

  _ViewMode _viewMode = _ViewMode.day;
  DateTime _selectedDate = DateTime.now();

  List<Building> _buildings = [];
  Building? _selectedBuilding;
  bool _loadingBuildings = true;

  List<Room> _allRooms = [];
  String _search = '';
  String _roomFilter = 'all';
  String? _loadError;
  int _inventoryRequest = 0;
  List<Tenant> _allTenants = [];
  List<Room> get _hourlyRooms => _allRooms.where((room) {
    final guests = _allTenants
        .where((t) => t.roomId == room.id)
        .map((t) => t.fullName)
        .join(' ');
    if (!('${room.roomNumber} ${room.roomType} $guests'.toLowerCase()).contains(
      _search.toLowerCase(),
    ))
      return false;
    final leased = _isTenantOccupiedOnDate(room.id, _selectedDate);
    final booked = (_dayBookings[room.id] ?? []).any((b) => b.isActive);
    return switch (_roomFilter) {
      'available' => !leased && !booked,
      'booked' => booked,
      'leased' => leased,
      _ => true,
    };
  }).toList();
  Map<String, List<RoomBooking>> _dayBookings = {};
  List<RoomBooking> _monthBookings = [];
  bool _loading = true;
  int _viewRequest = 0;

  static const int _startHour = 0;
  static const int _endHour = 24;
  Timer? _nowTimer;

  // Header (hour labels) scrolls horizontally in lockstep with the grid body.
  final ScrollController _headerHController = ScrollController();
  final ScrollController _bodyHController = ScrollController();
  double _pixelsPerHour = 80.0;

  // Room labels are a sticky left column; rows scroll vertically together
  // with the grid body via a single shared vertical scroll view.
  double get _roomLabelColWidth =>
      MediaQuery.sizeOf(context).width < 600 ? 110 : 170;
  static const double _timeHeaderHeight = 32.0;
  double _calendarLineHeight(String text, double size, {FontWeight? weight}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: size, fontWeight: weight,
        ),
      ),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.localeOf(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  double? _cachedRoomRowHeight;
  double get _roomRowHeight => _cachedRoomRowHeight ??= _measureRoomRowHeight();

  double _measureRoomRowHeight() {
    // Include the label's padding (8) and bottom border (1). Text inherits
    // the theme's line height, which is not necessarily fontSize * 1.5.
    var labelHeight = 9 + _calendarLineHeight('101', 13, weight: FontWeight.w700);
    final rooms = _hourlyRooms;
    if (rooms.any((room) => _isTenantOccupiedOnDate(room.id, _selectedDate))) {
      // Badge: top margin (4), vertical padding (4), two borders (1.6).
      labelHeight += 9.6 + _calendarLineHeight(
        AppTranslations.of(context)['calendar_long_term_guest'], 9,
        weight: FontWeight.w700,
      );
    } else if (rooms.any((room) => room.hasHourlyPricing)) {
      labelHeight += _calendarLineHeight('0', 10);
    }
    final lanes = _dayBookings.values.fold<int>(1, (count, bookings) {
      final length = _layoutOverlapLanes(bookings).length;
      return length > count ? length : count;
    });
    // Each booking lane includes vertical content padding and its gap.
    final events = 4 + lanes * (10 +
      _calendarLineHeight('Guest', 11, weight: FontWeight.w700) +
      _calendarLineHeight('00:00', 9));
    return [48.0, labelHeight, events]
        .reduce((a, b) => a > b ? a : b).ceilToDouble();
  }

  double get _dayGridWidth => _pixelsPerHour * (_endHour - _startHour);
  double get _roomsGridHeight => _roomRowHeight * _hourlyRooms.length;

  @override
  void initState() {
    super.initState();
    _loadBuildings();
    _nowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _viewMode == _ViewMode.day) setState(() {});
    });
    _bodyHController.addListener(() {
      if (_headerHController.hasClients &&
          _headerHController.offset != _bodyHController.offset) {
        _headerHController.jumpTo(_bodyHController.offset);
      }
    });
  }

  @override
  void dispose() {
    _nowTimer?.cancel();
    _headerHController.dispose();
    _bodyHController.dispose();
    super.dispose();
  }

  Future<void> _loadBuildings() async {
    setState(() {
      _loadingBuildings = true;
      _loadError = null;
    });
    try {
      final all = await _buildingService.getOrganizationBuildings(
        widget.organization.id,
        requireServer: true,
      );
      final managed = all.where((b) => !b.isRented).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      final selectedId = _selectedBuilding?.id ?? widget.initialBuilding?.id;
      setState(() {
        _buildings = managed;
        _selectedBuilding =
            managed.where((b) => b.id == selectedId).firstOrNull ??
            managed.firstOrNull;
        _loadingBuildings = false;
      });
      if (_selectedBuilding != null)
        await _loadRoomsForSelectedBuilding();
      else
        setState(() => _loading = false);
    } catch (_) {
      if (mounted)
        setState(() {
          _loadError = 'calendar_load_failed';
          _loadingBuildings = false;
          _loading = false;
        });
    }
  }

  Future<void> _onBuildingChanged(Building? building) async {
    if (building == null || building.id == _selectedBuilding?.id) return;
    ++_viewRequest;
    setState(() {
      _selectedBuilding = building;
      _allRooms = [];
      _allTenants = [];
      _dayBookings = {};
      _monthBookings = [];
    });
    await _loadRoomsForSelectedBuilding();
  }

  Future<void> _loadRoomsForSelectedBuilding() async {
    _clearRange();
    final building = _selectedBuilding;
    if (building == null) return;
    final request = ++_inventoryRequest;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _roomService.getBuildingRooms(
          widget.organization.id,
          building.id,
          requireServer: true,
        ),
        _tenantService.getBuildingTenants(
          widget.organization.id,
          building.id,
          requireServer: true,
        ),
      ]);
      if (!mounted || request != _inventoryRequest) return;
      setState(() {
        _allRooms = (results[0] as List<Room>)
          ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
        _allTenants = results[1] as List<Tenant>;
      });
      await _loadCurrentView();
    } catch (_) {
      if (mounted && request == _inventoryRequest)
        setState(() {
          _loading = false;
          _loadError = 'calendar_load_failed';
        });
    }
  }

  Future<void> _loadCurrentView() async {
    _clearRange();
    final building = _selectedBuilding;
    if (building == null) return;
    final request = ++_viewRequest;
    final date = _selectedDate;
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final data = await _bookingService.getBuildingBookingsForDay(
        widget.organization.id,
        building.id,
        date,
      );
      final month = await _bookingService.getBuildingBookingsForMonth(
        widget.organization.id,
        building.id,
        date,
      );
      var bookings = month;
      if (_viewMode == _ViewMode.week) {
        final end = date.add(const Duration(days: 6));
        if (end.month != date.month) {
          final next = await _bookingService.getBuildingBookingsForMonth(
            widget.organization.id,
            building.id,
            end,
          );
          bookings = {
            for (final b in [...month, ...next]) b.id: b,
          }.values.toList();
        }
      }
      if (!mounted || request != _viewRequest) return;
      setState(() {
        _dayBookings = data;
        _monthBookings = bookings;
        _loading = false;
      });
    } catch (_) {
      if (mounted && request == _viewRequest)
        setState(() {
          _loading = false;
          _loadError = 'calendar_load_failed';
        });
    }
  }

  void _goToDay(DateTime date) {
    setState(() {
      _selectedDate = date;
      _viewMode = _ViewMode.day;
    });
    _loadCurrentView();
  }

  void _shiftDay(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _loadCurrentView();
  }

  void _shiftMonth(int months) {
    setState(
      () => _selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month + months,
        1,
      ),
    );
    _loadCurrentView();
  }

  @override
  Widget build(BuildContext context) {
    _cachedRoomRowHeight = null;
    final t = AppTranslations.of(context);
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _clearRange},
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          appBar: widget.embedded
              ? null
              : AppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  flexibleSpace: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppThemePalette.primaryDeep, AppThemePalette.primary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  titleSpacing: 0,
                  title: _loadingBuildings || _buildings.isEmpty
                      ? Text(
                          t['calendar_title'],
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : _buildBuildingDropdown(),
                ),
          body: _buildCalendarBody(),
        ),
      ),
    );
  }

  Widget _buildViewModeSelector() {
    final t = AppTranslations.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _ViewMode.values.map((mode) {
          final selected = mode == _viewMode;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(t['calendar_view_${mode.name}']),
              selected: selected,
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              color: WidgetStateProperty.resolveWith((states) =>
                  states.contains(WidgetState.selected)
                      ? primary
                      : Theme.of(context).colorScheme.surface),
              side: BorderSide(color: selected ? primary : const Color(0xFFE2E8F0)),
              labelStyle: TextStyle(
                color: selected ? Colors.white : const Color(0xFF475569),
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              onSelected: (_) {
                setState(() => _viewMode = mode);
                _loadCurrentView();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCalendarBody() {
    final t = AppTranslations.of(context);
    if (_loadError != null)
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text(t[_loadError!], textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadBuildings,
                icon: const Icon(Icons.refresh),
                label: Text(t['retry']),
              ),
            ],
          ),
        ),
      );
    return _loadingBuildings
        ? const Center(child: CircularProgressIndicator())
        : _buildings.isEmpty
        ? Center(
            child: Text(
              t['calendar_no_buildings'],
              style: TextStyle(color: Colors.grey.shade500),
            ),
          )
        : Column(
            children: [
              _buildWorkspaceToolbar(),
              SizedBox(
                height: MediaQuery.textScalerOf(context).scale(16) > 24 ? 80 : 48,
                child: _viewMode == _ViewMode.day && _rangeStart != null
                    ? _rangeInstructions()
                    : _buildDateNav(),
              ),
              if (_hourlyRooms.isEmpty && !_loading)
                Expanded(
                  child: Center(
                    child: Text(
                      t['calendar_no_matching_rooms'],
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ),
                )
              else
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : switch (_viewMode) {
                          _ViewMode.day => _buildDayView(),
                          _ViewMode.week => _buildWeekView(),
                          _ViewMode.month => _buildMonthView(),
                          _ViewMode.agenda => _buildAgendaView(),
                        },
                ),
            ],
          );
  }

  // ── Building dropdown (in app bar) ──────────────────────────────────
  Widget _buildBuildingDropdown({bool toolbar = false}) {
    final t = AppTranslations.of(context);
    final dropdown = InkWell(
      key: const ValueKey('calendar-building-selector'),
      onTap: () async {
        final building = await showSearchableOptions<Building>(
          context: context,
          title: t['tenant_move_room_building'],
          options: _buildings,
          labelOf: (building) => building.name,
          selected: _selectedBuilding,
        );
        if (mounted && building != null) _onBuildingChanged(building);
      },
      child: Row(children: [
        Expanded(child: Text.rich(
          TextSpan(children: [
            if (!toolbar) TextSpan(
              text: '${t['calendar_title']}  ·  ',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            TextSpan(text: _selectedBuilding?.name ?? '', style: TextStyle(
              fontSize: toolbar ? 14 : 16,
              fontWeight: FontWeight.w600,
              color: toolbar ? Theme.of(context).colorScheme.onSurface : Colors.white,
            )),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        )),
        Icon(Icons.search, size: 20,
          color: toolbar ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.white),
      ]),
    );
    if (!toolbar) return dropdown;
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(
          text: _selectedBuilding?.name ?? '',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = (painter.width + 32).clamp(48.0, 180.0)
          .clamp(0.0, constraints.maxWidth);
      painter.dispose();
      return Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: SizedBox(width: width, height: 48, child: dropdown),
      );
    });
  }

  // ── Date nav bar ──────────────────────────────────────────────────
  Widget _buildDateNav() {
    final t = AppTranslations.of(context);
    final label = _viewMode != _ViewMode.month
        ? '${t.weekdayName(_selectedDate)}, ${DateFormat(t.dateFormat).format(_selectedDate)}'
        : DateFormat('MM/yyyy').format(_selectedDate);

    return Container(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: t['calendar_previous'],
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _viewMode == _ViewMode.month
                ? _shiftMonth(-1)
                : _shiftDay(_viewMode == _ViewMode.week ? -7 : -1),
          ),
          Expanded(
            child: Center(
              child: TextButton(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    locale: t.locale,
                    initialDate: _selectedDate,
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100),
                  );
                  if (date != null && mounted) {
                    setState(() => _selectedDate = date);
                    _loadCurrentView();
                  }
                },
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: t['calendar_next'],
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => _viewMode == _ViewMode.month
                ? _shiftMonth(1)
                : _shiftDay(_viewMode == _ViewMode.week ? 7 : 1),
          ),
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            onPressed: () => _goToDay(DateTime.now()),
            child: Text(t['calendar_today']),
          ),
        ],
      ),
    );
  }

  // ── DAY VIEW: room rows × horizontal time axis (hotel-chart style) ──
  Widget _buildDayView() {
    if (_hourlyRooms.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _buildLegend()),
            _buildZoomControls(),
          ],
        ),
        Expanded(
          child: Column(
            children: [
              // Sticky top header: hour labels, synced horizontally with grid below
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _roomLabelColWidth,
                      height: _timeHeaderHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _headerHController,
                          physics: const NeverScrollableScrollPhysics(),
                          child: _buildTimeHeaderRow(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable grid body: room labels (sticky left) + horizontally
              // scrollable timeline, both inside one shared vertical scroll.
              Expanded(
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildRoomLabelsColumn(),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _bodyHController,
                          child: ColoredBox(
                            color: Theme.of(context).colorScheme.surface,
                            child: SizedBox(
                              width: _dayGridWidth,
                              height: _roomsGridHeight,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                ),
                                child: Stack(
                                  children: [
                                    CustomPaint(
                                      size: Size(_dayGridWidth, _roomsGridHeight),
                                      painter: _TimeGridPainter(
                                        pixelsPerHour: _pixelsPerHour,
                                        hourCount: _endHour - _startHour,
                                        rowHeight: _roomRowHeight,
                                        rowCount: _hourlyRooms.length,
                                        hourLineColor: Theme.of(context)
                                            .colorScheme
                                            .outline
                                            .withValues(alpha: 0.46),
                                        halfHourLineColor: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: 0.7),
                                        rowLineColor: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: 0.9),
                                      ),
                                    ),
                                    ..._buildOutOfHoursOverlays(),
                                    ..._buildRoomEventRows(),
                                    if (DateUtils.isSameDay(
                                      _selectedDate,
                                      DateTime.now(),
                                    ))
                                      _buildNowLine(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimeHeaderRow() {
    final hours = List.generate(_endHour - _startHour, (i) => _startHour + i);
    return SizedBox(
      width: _dayGridWidth,
      height: _timeHeaderHeight,
      child: Stack(
        children: hours.map((h) {
          return Positioned(
            left: (h - _startHour) * _pixelsPerHour,
            top: 0,
            bottom: 0,
            child: Container(
              width: _pixelsPerHour,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRoomLabelsColumn() {
    final t = AppTranslations.of(context);
    return SizedBox(
      width: _roomLabelColWidth,
      height: _roomsGridHeight,
      child: Column(
        children: _hourlyRooms.map((room) {
          final tenantOccupied = _isTenantOccupiedOnDate(
            room.id,
            _selectedDate,
          );
          return InkWell(
            onTap: () => _openRoomPanel(room),
            child: Container(
              key: ValueKey('calendar-room-label-${room.id}'),
              height: _roomRowHeight,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  right: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    room.roomNumber,
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (tenantOccupied)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA32D2D).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(
                            0xFFA32D2D,
                          ).withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: Text(
                        t['calendar_long_term_guest'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFA32D2D),
                        ),
                      ),
                    )
                  else if (room.hasHourlyPricing)
                    Text(
                      t.textWithParams('calendar_price_per_hour', {
                        'price': ReportingMoney.format(room.organizationId, room.hourlyPrice!, room.currency),
                        'currency': '',
                      }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                      ),
                    ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildOutOfHoursOverlays() {
    final widgets = <Widget>[];
    for (int i = 0; i < _hourlyRooms.length; i++) {
      final room = _hourlyRooms[i];
      if (room.operatingHoursStartMin == null ||
          room.operatingHoursEndMin == null)
        continue;
      final startMin = room.operatingHoursStartMin!;
      final endMin = room.operatingHoursEndMin!;
      final top = i * _roomRowHeight;

      if (startMin > _startHour * 60) {
        widgets.add(
          Positioned(
            top: top,
            left: 0,
            height: _roomRowHeight,
            width: (startMin - _startHour * 60) / 60 * _pixelsPerHour,
            child: Container(
              color: Colors.grey.shade100.withValues(alpha: 0.7),
            ),
          ),
        );
      }
      if (endMin < _endHour * 60) {
        widgets.add(
          Positioned(
            top: top,
            left: (endMin - _startHour * 60) / 60 * _pixelsPerHour,
            height: _roomRowHeight,
            width: (_endHour * 60 - endMin) / 60 * _pixelsPerHour,
            child: Container(
              color: Colors.grey.shade100.withValues(alpha: 0.7),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _buildRoomEventRows() {
    final widgets = <Widget>[];
    for (int i = 0; i < _hourlyRooms.length; i++) {
      final room = _hourlyRooms[i];
      final top = i * _roomRowHeight;
      final tenantOccupied = _isTenantOccupiedOnDate(room.id, _selectedDate);

      if (tenantOccupied) {
        widgets.add(
          Positioned(
            top: top + 2,
            left: 0,
            width: _dayGridWidth,
            height: _roomRowHeight - 4,
            child: InkWell(
              onTap: () => _openRoomPanel(room),
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _tenantOnDate(room.id, _selectedDate)?.fullName ?? '',
                  maxLines: 1,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFA32D2D).withValues(alpha: 0.22),
                  border: Border.all(
                    color: const Color(0xFFA32D2D).withValues(alpha: 0.45),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
        );
        continue;
      }

      // Tap-to-create layer (added first so events painted after sit on top and stay tappable)
      widgets.add(
        Positioned(
          top: top,
          left: 0,
          width: _dayGridWidth,
          height: _roomRowHeight,
          child: MouseRegion(
            cursor: SystemMouseCursors.precise,
            onHover: (event) {
              if (_rangeRoomId == room.id) {
                final time = _slotAt(event.localPosition.dx);
                if (time != _rangeHover) setState(() => _rangeHover = time);
              }
            },
            child: GestureDetector(
              key: ValueKey('calendar-slot-${room.id}'),
              behavior: HitTestBehavior.translucent,
              onTapUp: (details) =>
                  _selectSlot(room, _slotAt(details.localPosition.dx)),
            ),
          ),
        ),
      );
      if (_rangeRoomId == room.id && _rangeStart != null) {
        final startMinutes = _rangeStart!
            .difference(DateUtils.dateOnly(_selectedDate))
            .inMinutes;
        final end = (_rangeHover != null && _rangeHover!.isAfter(_rangeStart!))
            ? _rangeHover!
            : _rangeStart!.add(const Duration(minutes: 30));
        widgets.add(
          Positioned(
            top: top + 3,
            left: startMinutes / 60 * _pixelsPerHour,
            width: end.difference(_rangeStart!).inMinutes / 60 * _pixelsPerHour,
            height: _roomRowHeight - 6,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: kPrimaryColor.withValues(alpha: 0.18),
                  border: Border.all(color: kPrimaryColor, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        );
      }

      final bookings = (_dayBookings[room.id] ?? []).toList();
      final lanes = _layoutOverlapLanes(bookings);
      final laneCount = lanes.isEmpty ? 1 : lanes.length;

      for (int c = 0; c < lanes.length; c++) {
        for (final booking in lanes[c]) {
          final dayStart = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            _startHour,
          );
          final startMinutes = booking.startTime
              .difference(dayStart)
              .inMinutes
              .clamp(0, (_endHour - _startHour) * 60);
          final endMinutes = booking.endTime
              .difference(dayStart)
              .inMinutes
              .clamp(0, (_endHour - _startHour) * 60);
          if (endMinutes <= startMinutes) continue;

          final left = startMinutes / 60 * _pixelsPerHour;
          final width = (endMinutes - startMinutes) / 60 * _pixelsPerHour;
          final eventHeight = (_roomRowHeight - 4) / laneCount;
          final eventTop = top + 2 + c * eventHeight;

          widgets.add(
            Positioned(
              left: left,
              top: eventTop,
              width: width - 2,
              height: eventHeight - 2,
              child: GestureDetector(
                onTap: () => _openBookingDetail(booking),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(booking.status),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              booking.guestName,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (width > 70)
                              Text(
                                '${DateFormat('HH:mm').format(booking.startTime)}–${DateFormat('HH:mm').format(booking.endTime)}',
                                style: const TextStyle(
                                  fontSize: 9,
                                  color: Colors.white70,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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
    }
    return widgets;
  }

  /// Assigns overlapping bookings within a room's row into stacked lanes
  /// (sub-rows). Non-overlapping bookings share the same lane.
  List<List<RoomBooking>> _layoutOverlapLanes(List<RoomBooking> bookings) {
    final sorted = [...bookings]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final lanes = <List<RoomBooking>>[];
    for (final b in sorted) {
      var placed = false;
      for (final lane in lanes) {
        if (!lane.last.endTime.isAfter(b.startTime)) {
          lane.add(b);
          placed = true;
          break;
        }
      }
      if (!placed) lanes.add([b]);
    }
    return lanes;
  }

  Widget _buildNowLine() {
    final now = DateTime.now();
    final dayStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startHour,
    );
    final minutesFromStart = now.difference(dayStart).inMinutes;
    final left = minutesFromStart / 60 * _pixelsPerHour;
    return Positioned(
      top: 0,
      bottom: 0,
      left: left,
      child: IgnorePointer(
        child: Column(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 2),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(child: Container(width: 1.5, color: Colors.red)),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final t = AppTranslations.of(context);
    final items = <MapEntry<String, Color>>[
      MapEntry(t['booking_status_pending'], const Color(0xFFEF9F27)),
      MapEntry(t['booking_status_confirmed'], const Color(0xFF185FA5)),
      MapEntry(t['booking_status_checked_in'], const Color(0xFF3B6D11)),
      MapEntry(t['booking_status_checked_out'], Colors.grey.shade400),
      MapEntry(t['booking_status_cancelled_or_no_show'], Colors.grey.shade300),
    ];
    return Container(
      height: 32,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: items.map((e) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: e.value,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  e.key,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(width: 14),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.only(right: 6),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: AppTranslations.of(context)['calendar_zoom_out'],
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.zoom_out, size: 18),
            onPressed: () => setState(
              () => _pixelsPerHour = (_pixelsPerHour - 15)
                  .clamp(40, 200)
                  .toDouble(),
            ),
          ),
          IconButton(
            tooltip: AppTranslations.of(context)['calendar_zoom_in'],
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.zoom_in, size: 18),
            onPressed: () => setState(
              () => _pixelsPerHour = (_pixelsPerHour + 15)
                  .clamp(40, 200)
                  .toDouble(),
            ),
          ),
        ],
      ),
    );
  }

  bool _withinOperatingHours(Room room, int hour) {
    if (room.operatingHoursStartMin == null ||
        room.operatingHoursEndMin == null)
      return true;
    final minuteOfDay = hour * 60;
    return minuteOfDay >= room.operatingHoursStartMin! &&
        minuteOfDay < room.operatingHoursEndMin!;
  }

  List<_RoomDayStatus> _roomStatusesForDay(DateTime day) {
    final dayEnd = day.add(const Duration(days: 1));
    final statuses = _hourlyRooms.map((room) {
      final roomBookings =
          _monthBookings
              .where(
                (b) =>
                    b.roomId == room.id &&
                    !b.isCancelled &&
                    b.startTime.isBefore(dayEnd) &&
                    b.endTime.isAfter(day),
              )
              .toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));

      final tenantOccupied = _isTenantOccupiedOnDate(room.id, day);

      DateTime? earliest;
      Color? color;
      if (tenantOccupied) {
        earliest = day;
        color = const Color(0xFFA32D2D); // long-term tenant
      } else if (roomBookings.isNotEmpty) {
        earliest = roomBookings.first.startTime;
        color = _statusColor(roomBookings.first.status);
      }

      return _RoomDayStatus(
        room: room,
        occupied: tenantOccupied || roomBookings.isNotEmpty,
        earliestTime: earliest,
        color: color,
      );
    }).toList();

    statuses.sort((a, b) {
      if (a.occupied != b.occupied) return a.occupied ? -1 : 1;
      if (a.occupied) return a.earliestTime!.compareTo(b.earliestTime!);
      return a.room.roomNumber.compareTo(b.room.roomNumber);
    });
    return statuses;
  }

  Tenant? _tenantOnDate(String roomId, DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    for (final tenant in _allTenants) {
      if (tenant.roomId != roomId) continue;
      if (tenant.status != TenantStatus.active &&
          tenant.status != TenantStatus.moveOut)
        continue;
      if (tenant.status == TenantStatus.moveOut && tenant.moveOutDate == null)
        continue;
      if (tenant.moveInDate.isBefore(end) &&
          (tenant.moveOutDate ?? DateTime(2999)).isAfter(start))
        return tenant;
    }
    return null;
  }

  bool _isTenantOccupiedOnDate(String roomId, DateTime date) =>
      _tenantOnDate(roomId, date) != null;

  Color _statusColor(BookingStatus status) {
    switch (status) {
      case BookingStatus.pending:
        return const Color(0xFFEF9F27);
      case BookingStatus.confirmed:
        return const Color(0xFF185FA5);
      case BookingStatus.checkedIn:
        return const Color(0xFF3B6D11);
      case BookingStatus.checkedOut:
        return Colors.grey.shade400;
      case BookingStatus.cancelled:
      case BookingStatus.noShow:
        return Colors.grey.shade300;
    }
  }

  // ── MONTH VIEW: occupancy heatmap ────────────────────────────────
  Widget _buildMonthView() {
    final t = AppTranslations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final material = MaterialLocalizations.of(context);
    final firstWeekday = material.firstDayOfWeekIndex;
    final monthStart = DateTime(_selectedDate.year, _selectedDate.month);
    final days = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    final blanks = (monthStart.weekday % 7 - firstWeekday + 7) % 7;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(t['calendar_day_hint']),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: List.generate(
              7,
              (i) => Expanded(
                child: Center(
                  child: Text(
                    t.shortWeekdayName(
                      DateTime(2026, 9, 6 + (i + firstWeekday) % 7),
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: compact ? 100 : 155,
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
            ),
            itemCount: ((blanks + days + 6) ~/ 7) * 7,
            itemBuilder: (context, index) {
              final day = index - blanks + 1;
              if (day < 1 || day > days) return const SizedBox.shrink();
              final date = DateTime(
                _selectedDate.year,
                _selectedDate.month,
                day,
              );
              final statuses = _roomStatusesForDay(date);
              final occupied = statuses.where((s) => s.occupied).length;
              final free = statuses.length - occupied;
              final today = DateUtils.isSameDay(date, DateTime.now());
              final occupiedLabel = t.textWithParams(
                'calendar_occupied_count',
                {'count': '$occupied'},
              );
              final freeLabel = t.textWithParams('calendar_free_count', {
                'count': '$free',
              });
              return Semantics(
                button: true,
                label: '${t.formatLongDate(date)}, $occupiedLabel, $freeLabel',
                child: Tooltip(
                  message: '$occupiedLabel\n$freeLabel',
                  child: Material(
                    color: today
                        ? scheme.primaryContainer
                        : scheme.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: today ? kPrimaryColor : scheme.outlineVariant,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _goToDay(date),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$day',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: today ? kPrimaryColor : scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: statuses.isEmpty
                                  ? 0
                                  : occupied / statuses.length,
                              color: kPrimaryColor,
                              backgroundColor: scheme.surfaceContainerHighest,
                              minHeight: 5,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Text(
                                compact
                                    ? '$occupied/${statuses.length}'
                                    : '$occupiedLabel\n$freeLabel',
                                style: TextStyle(fontSize: compact ? 10 : 12),
                                maxLines: 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceToolbar() {
    final t = AppTranslations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: EdgeInsets.fromLTRB(10, 2, 10 + (widget.embedded ? widget.trailingInset : 0), 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1000 || MediaQuery.textScalerOf(context).scale(14) > 18;
          final search = SizedBox(
            height: 36,
            width: compact ? null : 280,
            child: TextFormField(
              initialValue: _search,
              onChanged: (v) => setState(() => _search = v),
              decoration: InputDecoration(
                hintText: t['calendar_search'],
                prefixIcon: const Icon(Icons.search, size: 19),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                filled: true,
                fillColor: scheme.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              ),
            ),
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                tooltip: t['calendar_filter'],
                initialValue: _roomFilter,
                icon: Icon(
                  Icons.filter_list_rounded,
                  color: _roomFilter == 'all'
                      ? scheme.onSurfaceVariant
                      : kPrimaryColor,
                ),
                onSelected: (v) => setState(() => _roomFilter = v),
                itemBuilder: (_) => ['all', 'available', 'booked', 'leased']
                    .map((value) => PopupMenuItem(
                          value: value,
                          child: Text(t['calendar_filter_$value']),
                        ))
                    .toList(),
              ),
              IconButton(
                tooltip: t['refresh'],
                visualDensity: VisualDensity.compact,
                onPressed: _loading ? null : _loadRoomsForSelectedBuilding,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          );
          final viewMenu = PopupMenuButton<_ViewMode>(
            key: const ValueKey('calendar-view-menu'),
            tooltip: t['calendar_view_${_viewMode.name}'],
            initialValue: _viewMode,
            onSelected: (mode) {
              _clearRange();
              setState(() => _viewMode = mode);
              _loadCurrentView();
            },
            itemBuilder: (_) => _ViewMode.values.map((mode) =>
              CheckedPopupMenuItem(
                key: ValueKey('calendar-view-${mode.name}'),
                value: mode,
                checked: mode == _viewMode,
                child: Text(t['calendar_view_${mode.name}']),
              ),
            ).toList(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 110, minHeight: 48),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(child: Text(t['calendar_view_${_viewMode.name}'],
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13))),
                  const Icon(Icons.expand_more, size: 18),
                ]),
              ),
            ),
          );
          return Row(
            key: const ValueKey('calendar-workspace-toolbar'),
            children: [
              if (widget.embedded) ...[
                if (compact)
                  Expanded(child: _buildBuildingDropdown(toolbar: true))
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: _buildBuildingDropdown(toolbar: true),
                  ),
                const SizedBox(width: 8),
              ],
              if (compact) viewMenu else _buildViewModeSelector(),
              if (!widget.embedded && compact) const Spacer(),
              if (compact)
                IconButton(
                  tooltip: t['calendar_search'],
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(t['calendar_search']),
                      content: SizedBox(width: 360, child: search),
                      actions: [TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(MaterialLocalizations.of(context).closeButtonLabel),
                      )],
                    ),
                  ),
                )
              else ...[
                const SizedBox(width: 12),
                Expanded(child: Align(alignment: Alignment.centerLeft, child: search)),
                const SizedBox(width: 8),
              ],
              actions,
            ],
          );
        },
      ),
    );
  }

  List<RoomBooking> _bookingsOn(
    String roomId,
    DateTime date, {
    bool includeHistory = false,
  }) {
    final start = DateUtils.dateOnly(date),
        end = DateUtils.dateOnly(date).add(const Duration(days: 1));
    return _monthBookings
        .where(
          (b) =>
              b.roomId == roomId &&
              (includeHistory || !b.isCancelled) &&
              b.startTime.isBefore(end) &&
              b.endTime.isAfter(start),
        )
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Widget _buildAgendaView() {
    final t = AppTranslations.of(context);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _hourlyRooms.length,
      itemBuilder: (context, index) {
        final room = _hourlyRooms[index],
            tenant = _tenantOnDate(_hourlyRooms[index].id, _selectedDate);
        final bookings = _bookingsOn(
          room.id,
          _selectedDate,
          includeHistory: true,
        );
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    room.roomNumber,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(room.roomType),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openRoomPanel(room),
                ),
                if (tenant != null &&
                    _isTenantOccupiedOnDate(room.id, _selectedDate))
                  ListTile(
                    leading: const Icon(Icons.home),
                    title: Text(tenant.fullName),
                    subtitle: Text(t['calendar_long_term_guest']),
                    onTap: () => _openRoomPanel(room),
                  ),
                ...bookings.map(
                  (b) => ListTile(
                    leading: Icon(Icons.event, color: _statusColor(b.status)),
                    title: Text(
                      '${b.guestName} · ${b.getStatusDisplayName(t)}',
                    ),
                    subtitle: Text(
                      '${DateFormat(t.dateTimeFormat).format(b.startTime)} – ${DateFormat(t.dateTimeFormat).format(b.endTime)}',
                    ),
                    onTap: () => _openBookingDetail(b),
                  ),
                ),
                if (bookings.isEmpty &&
                    !_isTenantOccupiedOnDate(room.id, _selectedDate))
                  ListTile(
                    title: Text(t['calendar_filter_available']),
                    trailing: const Icon(Icons.add),
                    onTap: () => _openRoomPanel(room),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeekView() {
    final t = AppTranslations.of(context);
    const cellWidth = 150.0, rowHeight = 148.0;
    final days = List.generate(
      7,
      (i) => DateUtils.dateOnly(_selectedDate).add(Duration(days: i)),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(t['calendar_week_hint']),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: _roomLabelColWidth,
                  child: Column(
                    children: [
                      const SizedBox(height: 48),
                      ..._hourlyRooms.map(
                        (room) => SizedBox(
                          height: rowHeight,
                          child: ListTile(
                            title: Text(room.roomNumber),
                            onTap: () => _openRoomPanel(room),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: cellWidth * 7,
                      child: Column(
                        children: [
                          Row(
                            children: days
                                .map(
                                  (d) => SizedBox(
                                    width: cellWidth,
                                    height: 48,
                                    child: Center(
                                      child: Text(
                                        '${t.shortWeekdayName(d)} ${DateFormat(t.dateFormatShort).format(d)}',
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          ..._hourlyRooms.map(
                            (room) => Row(
                              children: days.map((date) {
                                final bookings = _bookingsOn(room.id, date);
                                final leased = _isTenantOccupiedOnDate(
                                  room.id,
                                  date,
                                );
                                return SizedBox(
                                  width: cellWidth,
                                  height: rowHeight,
                                  child: Card(
                                    color: leased
                                        ? const Color(0xFFFFF1F2)
                                        : null,
                                    child: InkWell(
                                      onTap: () =>
                                          _openRoomPanel(room, date: date),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (leased)
                                              Text(
                                                _tenantOnDate(
                                                      room.id,
                                                      date,
                                                    )?.fullName ??
                                                    t['calendar_long_term_guest'],
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ...bookings
                                                .take(2)
                                                .map(
                                                  (b) => Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          bottom: 4,
                                                        ),
                                                    child: InkWell(
                                                      onTap: () =>
                                                          _openBookingDetail(b),
                                                      child: Text(
                                                        b.guestName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          color: _statusColor(
                                                            b.status,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            if (!leased && bookings.isEmpty)
                                              const Icon(
                                                Icons.add,
                                                color: Colors.grey,
                                              ),
                                            const Spacer(),
                                            if (bookings.length > 2)
                                              Text(
                                                '+${bookings.length - 2}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                          ],
                                        ),
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
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openRoomPanel(Room room, {DateTime? date}) async {
    final t = AppTranslations.of(context);
    final day = date ?? _selectedDate;
    final bookings = _bookingsOn(room.id, day, includeHistory: true);
    final tenants = _allTenants
        .where(
          (tenant) =>
              tenant.roomId == room.id && tenant.status == TenantStatus.active,
        )
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                '${room.roomNumber} · ${room.roomType}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(t.formatLongDate(day)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (room.supportsHourlyBooking &&
                      !_isTenantOccupiedOnDate(room.id, day))
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: Text(t['calendar_new_booking']),
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        final start = DateTime(
                          day.year,
                          day.month,
                          day.day,
                          DateTime.now().hour,
                        );
                        _openBookingForm(
                          room,
                          start,
                          start.add(Duration(hours: room.minBookingHours ?? 1)),
                        );
                      },
                    ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.meeting_room),
                    label: Text(t['calendar_room_details']),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openRoomDetails(room);
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.payments),
                    label: Text(t['calendar_new_payment']),
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openRoomPayment(room);
                    },
                  ),
                ],
              ),
              const Divider(height: 28),
              ...tenants.map(
                (tenant) => ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(tenant.fullName),
                  subtitle: Text(
                    '${tenant.phoneNumber}\n${t['calendar_long_term_guest']}',
                  ),
                  isThreeLine: true,
                  onTap: () => _showTenantDetails(tenant),
                ),
              ),
              ...bookings.map(
                (booking) => ListTile(
                  leading: Icon(
                    Icons.event,
                    color: _statusColor(booking.status),
                  ),
                  title: Text(booking.guestName),
                  subtitle: Text(
                    '${DateFormat(t.dateTimeFormat).format(booking.startTime)} – ${DateFormat(t.dateTimeFormat).format(booking.endTime)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openBookingDetail(booking);
                  },
                ),
              ),
              if (tenants.isEmpty && bookings.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(t['calendar_filter_available']),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTenantDetails(Tenant tenant) => showDialog<void>(
    context: context,
    builder: (context) {
      final t = AppTranslations.of(context);
      return AppAlertDialog(
        title: Text(tenant.fullName),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t['phone']}: ${tenant.phoneNumber}'),
              Text('${t['email']}: ${tenant.email ?? ''}'),
              Text(
                '${t['tenant_field_move_in_date']}: ${DateFormat(t.dateFormat).format(tenant.moveInDate)}',
              ),
              if (tenant.monthlyRent != null)
                Text(
                  '${t['tenant_field_rent']}: ${ReportingMoney.format(tenant.organizationId, tenant.monthlyRent!, tenant.currency)}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t['close']),
          ),
        ],
      );
    },
  );

  Future<void> _openRoomDetails(Room room) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            RoomDetailScreen(room: room, organization: widget.organization),
      ),
    );
    if (mounted) await _loadRoomsForSelectedBuilding();
  }

  Future<void> _openRoomPayment(Room room) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => ImprovedPaymentFormDialog(
        organization: widget.organization,
        buildingService: _buildingService,
        roomService: _roomService,
        tenantService: _tenantService,
        paymentService: getIt<PaymentService>(),
        room: room,
      ),
    );
    if (mounted) await _loadRoomsForSelectedBuilding();
  }

  Future<void> _editBooking(RoomBooking booking) async {
    final room = _allRooms.where((r) => r.id == booking.roomId).firstOrNull;
    if (room == null || _selectedBuilding == null) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => BookingFormDialog(
        organization: widget.organization,
        building: _selectedBuilding!,
        room: room,
        booking: booking,
        initialStart: booking.startTime,
        initialEnd: booking.endTime,
      ),
    );
    if (mounted) await _loadRoomsForSelectedBuilding();
  }

  Future<void> _openBookingForm(Room room, DateTime start, DateTime end) async {
    if (_selectedBuilding == null) return;
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => BookingFormDialog(
        organization: widget.organization,
        building: _selectedBuilding!,
        room: room,
        initialStart: start,
        initialEnd: end,
      ),
    );
    if (created == true) _loadRoomsForSelectedBuilding();
  }

  Future<void> _openBookingDetail(RoomBooking booking) async {
    _clearRange();
    await showDialog<bool>(
      context: context,
      builder: (_) => BookingDetailDialog(
        booking: booking,
        onEdit: () => _editBooking(booking),
      ),
    );
    if (mounted) _loadRoomsForSelectedBuilding();
  }
}

class _TimeGridPainter extends CustomPainter {
  final double pixelsPerHour;
  final int hourCount;
  final double rowHeight;
  final int rowCount;
  final Color hourLineColor;
  final Color halfHourLineColor;
  final Color rowLineColor;

  _TimeGridPainter({
    required this.pixelsPerHour,
    required this.hourCount,
    required this.rowHeight,
    required this.rowCount,
    required this.hourLineColor,
    required this.halfHourLineColor,
    required this.rowLineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = hourLineColor
      ..strokeWidth = 1;
    final halfHourPaint = Paint()
      ..color = halfHourLineColor
      ..strokeWidth = 1;
    final rowPaint = Paint()
      ..color = rowLineColor
      ..strokeWidth = 1;

    // Vertical lines: one per hour (darker) + one per half-hour (lighter).
    for (int h = 0; h <= hourCount; h++) {
      final x = h * pixelsPerHour;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), hourPaint);
      if (h < hourCount) {
        final halfX = x + pixelsPerHour / 2;
        canvas.drawLine(
          Offset(halfX, 0),
          Offset(halfX, size.height),
          halfHourPaint,
        );
      }
    }
    // Horizontal lines: one per room row.
    for (int r = 0; r <= rowCount; r++) {
      final y = r * rowHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimeGridPainter oldDelegate) {
    return oldDelegate.pixelsPerHour != pixelsPerHour ||
        oldDelegate.hourCount != hourCount ||
        oldDelegate.rowHeight != rowHeight ||
        oldDelegate.rowCount != rowCount ||
        oldDelegate.hourLineColor != hourLineColor ||
        oldDelegate.halfHourLineColor != halfHourLineColor ||
        oldDelegate.rowLineColor != rowLineColor;
  }
}

