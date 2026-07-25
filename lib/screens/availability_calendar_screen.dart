import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/booking/booking_form_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/booking/booking_detail_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';

const Color kPrimaryColor = Color(0xFF4F46E5);
const Color kBgColor = Color(0xFFF8FAFC);

class AvailabilityCalendarScreen extends StatefulWidget {
  /// If null, the screen loads every building in the organization and lets
  /// the user pick one via the header dropdown. If provided, that building
  /// is preselected but the user can still switch away from it.
  final Building? initialBuilding;
  final Organization organization;

  const AvailabilityCalendarScreen({
    this.initialBuilding,
    required this.organization,
    super.key,
  });

  @override
  State<AvailabilityCalendarScreen> createState() => _AvailabilityCalendarScreenState();
}

enum _ViewMode { day, month }

class _RoomDayStatus {
  final Room room;
  final bool occupied;
  final DateTime? earliestTime;
  final Color? color;
  const _RoomDayStatus({required this.room, required this.occupied, this.earliestTime, this.color});
}

class _AvailabilityCalendarScreenState extends State<AvailabilityCalendarScreen> {
  final RoomService _roomService = getIt<RoomService>();
  final BookingService _bookingService = getIt<BookingService>();
  final BuildingService _buildingService = getIt<BuildingService>();
  final TenantService _tenantService = getIt<TenantService>();

  _ViewMode _viewMode = _ViewMode.day;
  DateTime _selectedDate = DateTime.now();

  List<Building> _buildings = [];
  Building? _selectedBuilding;
  bool _loadingBuildings = true;

  List<Room> _hourlyRooms = [];
  Map<String, List<RoomBooking>> _dayBookings = {};
  List<RoomBooking> _monthBookings = [];
  Map<String, Tenant> _activeTenantByRoomId = {};
  bool _loading = true;

  static const int _startHour = 0;
  static const int _endHour = 24;

  @override
  void initState() {
    super.initState();
    _loadBuildings();
  }

  Future<void> _loadBuildings() async {
    setState(() => _loadingBuildings = true);
    final all = await _buildingService.getOrganizationBuildings(widget.organization.id);
    final managed = all.where((b) => !b.isRented).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    Building? initial;
    if (widget.initialBuilding != null) {
      initial = managed.where((b) => b.id == widget.initialBuilding!.id).firstOrNull ??
          (managed.isNotEmpty ? managed.first : null);
    } else {
      initial = managed.isNotEmpty ? managed.first : null;
    }

    if (!mounted) return;
    setState(() {
      _buildings = managed;
      _selectedBuilding = initial;
      _loadingBuildings = false;
    });

    if (_selectedBuilding != null) await _loadRoomsForSelectedBuilding();
  }

  Future<void> _onBuildingChanged(Building? building) async {
    if (building == null || building.id == _selectedBuilding?.id) return;
    setState(() {
      _selectedBuilding = building;
      _hourlyRooms = [];
      _dayBookings = {};
      _monthBookings = [];
      _activeTenantByRoomId = {};
    });
    await _loadRoomsForSelectedBuilding();
  }

  Future<void> _loadRoomsForSelectedBuilding() async {
    if (_selectedBuilding == null) return;
    final rooms = await _roomService.getBuildingRooms(widget.organization.id, _selectedBuilding!.id);
    final tenants = await _tenantService.getBuildingTenants(widget.organization.id, _selectedBuilding!.id);
    if (!mounted) return;

    final hourlyRooms = rooms.where((r) => r.supportsHourlyBooking).toList()
      ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));
    final hourlyRoomIds = hourlyRooms.map((r) => r.id).toSet();

    setState(() {
      _hourlyRooms = hourlyRooms;
      _activeTenantByRoomId = {
        for (final t in tenants.where((t) => t.status == TenantStatus.active && hourlyRoomIds.contains(t.roomId)))
          t.roomId: t,
      };
    });
    await _loadCurrentView();
  }

  Future<void> _loadCurrentView() async {
    if (_selectedBuilding == null) return;
    setState(() => _loading = true);
    if (_viewMode == _ViewMode.day) {
      final data = await _bookingService.getBuildingBookingsForDay(
        widget.organization.id,
        _selectedBuilding!.id,
        _selectedDate,
      );
      if (mounted) setState(() => _dayBookings = data);
    } else {
      final bookings = await _bookingService.getBuildingBookingsForMonth(
        widget.organization.id,
        _selectedBuilding!.id,
        _selectedDate,
      );
      if (mounted) setState(() => _monthBookings = bookings);
    }
    if (mounted) setState(() => _loading = false);
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
    setState(() => _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + months, 1));
    _loadCurrentView();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgColor,
      appBar: AppBar(
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: _loadingBuildings || _buildings.isEmpty
            ? const Text('Lịch phòng theo giờ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))
            : _buildBuildingDropdown(),
        actions: [
          if (!_loadingBuildings && _buildings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: SegmentedButton<_ViewMode>(
                  style: SegmentedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    foregroundColor: Colors.white,
                    selectedBackgroundColor: Colors.white,
                    selectedForegroundColor: kPrimaryColor,
                  ),
                  segments: const [
                    ButtonSegment(value: _ViewMode.day, label: Text('Ngày')),
                    ButtonSegment(value: _ViewMode.month, label: Text('Tháng')),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (s) {
                    setState(() => _viewMode = s.first);
                    _loadCurrentView();
                  },
                ),
              ),
            ),
        ],
      ),
      body: _loadingBuildings
          ? const Center(child: CircularProgressIndicator())
          : _buildings.isEmpty
              ? Center(
                  child: Text(
                    'Tổ chức chưa có toà nhà nào có thể quản lý phòng.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : Column(
                  children: [
                    _buildDateNav(),
                    if (_hourlyRooms.isEmpty && !_loading)
                      Expanded(
                        child: Center(
                          child: Text(
                            'Toà nhà này chưa có phòng nào bật chế độ cho thuê theo giờ.\nVào Sửa phòng để bật.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : (_viewMode == _ViewMode.day ? _buildDayView() : _buildMonthView()),
                      ),
                  ],
                ),
    );
  }

  // ── Building dropdown (in app bar) ──────────────────────────────────
  Widget _buildBuildingDropdown() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<Building>(
        value: _selectedBuilding,
        dropdownColor: kPrimaryColor,
        iconEnabledColor: Colors.white,
        selectedItemBuilder: (context) => _buildings
            .map((b) => Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Lịch phòng theo giờ',
                          style: TextStyle(fontSize: 11, color: Colors.white70)),
                      Text(b.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ))
            .toList(),
        items: _buildings
            .map((b) => DropdownMenuItem(
                  value: b,
                  child: Text(b.name, style: const TextStyle(color: Colors.white)),
                ))
            .toList(),
        onChanged: _onBuildingChanged,
      ),
    );
  }

  // ── Date nav bar ──────────────────────────────────────────────────
  Widget _buildDateNav() {
    final label = _viewMode == _ViewMode.day
        ? DateFormat('EEEE, dd/MM/yyyy', 'vi_VN').format(_selectedDate)
        : DateFormat('MM/yyyy').format(_selectedDate);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _viewMode == _ViewMode.day ? _shiftDay(-1) : _shiftMonth(-1),
          ),
          Expanded(
            child: Center(
              child: Text(label,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => _viewMode == _ViewMode.day ? _shiftDay(1) : _shiftMonth(1),
          ),
          TextButton(
            onPressed: () => _goToDay(DateTime.now()),
            child: const Text('Hôm nay'),
          ),
        ],
      ),
    );
  }

  // ── DAY VIEW: hour grid ──────────────────────────────────────────
  Widget _buildDayView() {
    const roomColWidth = 84.0;
    const hourColWidth = 56.0;
    final hours = List.generate(_endHour - _startHour, (i) => _startHour + i);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: roomColWidth, height: 36),
                ...hours.map((h) => Container(
                      width: hourColWidth,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200)),
                      child: Text('${h.toString().padLeft(2, '0')}h',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    )),
              ],
            ),
            ...(_hourlyRooms.map((room) {
              final bookings = _dayBookings[room.id] ?? [];
              final tenantOccupied = _isTenantOccupiedOnDate(room.id, _selectedDate);
              return Row(
                children: [
                  Container(
                    width: roomColWidth,
                    height: 52,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      color: Colors.grey.shade50,
                    ),
                    child: Text(room.roomNumber,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (tenantOccupied)
                    Container(
                      width: hourColWidth * hours.length,
                      height: 52,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade200),
                        color: const Color(0xFFFCEBEB),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.person_pin_circle_rounded, size: 14, color: Color(0xFFA32D2D)),
                          const SizedBox(width: 6),
                          Text(
                            'Đã có khách thuê dài hạn',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFA32D2D)),
                          ),
                        ],
                      ),
                    )
                  else
                    ...hours.map((h) {
                      final cellStart = DateTime(
                          _selectedDate.year, _selectedDate.month, _selectedDate.day, h);
                      final cellEnd = cellStart.add(const Duration(hours: 1));
                      final withinOperatingHours = _withinOperatingHours(room, h);
                      final booking = bookings.cast<RoomBooking?>().firstWhere(
                            (b) => b != null && b.startTime.isBefore(cellEnd) && b.endTime.isAfter(cellStart),
                            orElse: () => null,
                          );

                      Color cellColor;
                      if (!withinOperatingHours) {
                        cellColor = Colors.grey.shade100;
                      } else if (booking != null) {
                        cellColor = _statusColor(booking.status);
                      } else {
                        cellColor = Colors.white;
                      }

                      return GestureDetector(
                        onTap: !withinOperatingHours
                            ? null
                            : () => booking != null
                                ? _openBookingDetail(booking)
                                : _openBookingForm(room, cellStart, cellEnd),
                        child: Container(
                          width: hourColWidth,
                          height: 52,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200),
                            color: cellColor,
                          ),
                          alignment: Alignment.center,
                          child: booking != null
                              ? Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Text(
                                    booking.guestName,
                                    style: const TextStyle(
                                        fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : null,
                        ),
                      );
                    }),
                ],
              );
            })),
          ],
        ),
      ),
    );
  }

  bool _withinOperatingHours(Room room, int hour) {
    if (room.operatingHoursStartMin == null || room.operatingHoursEndMin == null) return true;
    final minuteOfDay = hour * 60;
    return minuteOfDay >= room.operatingHoursStartMin! && minuteOfDay < room.operatingHoursEndMin!;
  }

  List<_RoomDayStatus> _roomStatusesForDay(DateTime day) {
    final dayEnd = day.add(const Duration(days: 1));
    final statuses = _hourlyRooms.map((room) {
      final roomBookings = _monthBookings
          .where((b) => b.roomId == room.id && b.startTime.isBefore(dayEnd) && b.endTime.isAfter(day))
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

  bool _isTenantOccupiedOnDate(String roomId, DateTime date) {
    final tenant = _activeTenantByRoomId[roomId];
    if (tenant == null) return false;
    final dayEnd = date.add(const Duration(days: 1));
    final moveOut = tenant.moveOutDate ?? DateTime(2999);
    return tenant.moveInDate.isBefore(dayEnd) && moveOut.isAfter(date);
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
        return Colors.grey.shade400;
      case BookingStatus.cancelled:
      case BookingStatus.noShow:
        return Colors.grey.shade300;
    }
  }

  // ── MONTH VIEW: occupancy heatmap ────────────────────────────────
  Widget _buildMonthView() {
    final monthStart = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    final leadingBlanks = monthStart.weekday % 7;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7']
                .map((d) => Expanded(
                      child: Center(
                        child: Text(d,
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.55,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: leadingBlanks + daysInMonth,
              itemBuilder: (context, index) {
                if (index < leadingBlanks) return const SizedBox.shrink();
                final day = index - leadingBlanks + 1;
                final date = DateTime(_selectedDate.year, _selectedDate.month, day);
                final isToday = DateUtils.isSameDay(date, DateTime.now());
                final statuses = _roomStatusesForDay(date);

                const maxChipsShown = 6;
                final visible = statuses.take(maxChipsShown).toList();
                final overflow = statuses.length - visible.length;

                return InkWell(
                  onTap: () => _goToDay(date),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isToday ? kPrimaryColor : Colors.grey.shade200,
                        width: isToday ? 1.6 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$day',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isToday ? kPrimaryColor : Colors.black87,
                            )),
                        const SizedBox(height: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const NeverScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ...visible.map((s) {
                                  if (s.occupied && s.color != null) {
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 3),
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: s.color!.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(5),
                                        border: Border.all(color: s.color!, width: 0.8),
                                      ),
                                      child: Text(
                                        s.room.roomNumber,
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: s.color),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      s.room.roomNumber,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey.shade400),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────
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
    if (created == true) _loadCurrentView();
  }

  Future<void> _openBookingDetail(RoomBooking booking) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => BookingDetailDialog(booking: booking),
    );
    if (changed == true) _loadCurrentView();
  }
}