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
  Timer? _nowTimer;
  final ScrollController _headerHController = ScrollController();
  final ScrollController _bodyHController = ScrollController();
  double _pixelsPerHour = 60.0;

  static const double _timeColWidth = 56.0;
  static const double _roomColWidth = 170.0;

  double get _dayGridHeight => _pixelsPerHour * (_endHour - _startHour);

  @override
  void initState() {
    super.initState();
    _loadBuildings();
    _nowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _viewMode == _ViewMode.day) setState(() {});
    });
    _bodyHController.addListener(() {
      if (_headerHController.hasClients && _headerHController.offset != _bodyHController.offset) {
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

  // ── DAY VIEW: Google-Calendar-style vertical timeline ──────────────
  Widget _buildDayView() {
    if (_hourlyRooms.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLegend(),
        _buildZoomControls(),
        Expanded(
          child: Column(
            children: [
              // Sticky header row: room names, synced horizontally with grid below
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                ),
                child: Row(
                  children: [
                    SizedBox(width: _timeColWidth),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _headerHController,
                        physics: const NeverScrollableScrollPhysics(),
                        child: Row(
                          children: _hourlyRooms.map((room) {
                            final tenantOccupied = _isTenantOccupiedOnDate(room.id, _selectedDate);
                            return Container(
                              width: _roomColWidth,
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                              decoration: BoxDecoration(
                                border: Border(left: BorderSide(color: Colors.grey.shade200)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    room.roomNumber,
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (tenantOccupied)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFCEBEB),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Khách dài hạn',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFA32D2D)),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable grid body
              Expanded(
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTimeLabelsColumn(),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          controller: _bodyHController,
                          child: SizedBox(
                            width: _roomColWidth * _hourlyRooms.length,
                            height: _dayGridHeight,
                            child: Stack(
                              children: [
                                CustomPaint(
                                  size: Size(_roomColWidth * _hourlyRooms.length, _dayGridHeight),
                                  painter: _HourGridPainter(
                                    pixelsPerHour: _pixelsPerHour,
                                    hourCount: _endHour - _startHour,
                                    columnWidth: _roomColWidth,
                                    columnCount: _hourlyRooms.length,
                                  ),
                                ),
                                ..._buildOutOfHoursOverlays(),
                                ..._buildRoomEventColumns(),
                                if (DateUtils.isSameDay(_selectedDate, DateTime.now())) _buildNowLine(),
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
          ),
        ),
      ],
    );
  }

  Widget _buildTimeLabelsColumn() {
    final hours = List.generate(_endHour - _startHour, (i) => _startHour + i);
    return SizedBox(
      width: _timeColWidth,
      height: _dayGridHeight,
      child: Stack(
        children: hours.map((h) {
          return Positioned(
            top: (h - _startHour) * _pixelsPerHour - 6,
            right: 8,
            child: Text(
              '${h.toString().padLeft(2, '0')}:00',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
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
      if (room.operatingHoursStartMin == null || room.operatingHoursEndMin == null) continue;
      final startMin = room.operatingHoursStartMin!;
      final endMin = room.operatingHoursEndMin!;
      final left = i * _roomColWidth;

      if (startMin > _startHour * 60) {
        widgets.add(Positioned(
          left: left,
          top: 0,
          width: _roomColWidth,
          height: (startMin - _startHour * 60) / 60 * _pixelsPerHour,
          child: Container(color: Colors.grey.shade100.withValues(alpha: 0.7)),
        ));
      }
      if (endMin < _endHour * 60) {
        widgets.add(Positioned(
          left: left,
          top: (endMin - _startHour * 60) / 60 * _pixelsPerHour,
          width: _roomColWidth,
          height: (_endHour * 60 - endMin) / 60 * _pixelsPerHour,
          child: Container(color: Colors.grey.shade100.withValues(alpha: 0.7)),
        ));
      }
    }
    return widgets;
  }

  List<Widget> _buildRoomEventColumns() {
    final widgets = <Widget>[];
    for (int i = 0; i < _hourlyRooms.length; i++) {
      final room = _hourlyRooms[i];
      final left = i * _roomColWidth;
      final tenantOccupied = _isTenantOccupiedOnDate(room.id, _selectedDate);

      if (tenantOccupied) {
        widgets.add(Positioned(
          left: left + 2,
          top: 0,
          width: _roomColWidth - 4,
          height: _dayGridHeight,
          child: Container(color: const Color(0xFFFCEBEB).withValues(alpha: 0.5)),
        ));
        continue;
      }

      // Tap-to-create layer (added first so events painted after sit on top and stay tappable)
      widgets.add(Positioned(
        left: left,
        top: 0,
        width: _roomColWidth,
        height: _dayGridHeight,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) {
            final minutesFromStart = (details.localPosition.dy / _pixelsPerHour * 60).round();
            final snapped = (minutesFromStart ~/ 30) * 30;
            final start = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _startHour)
                .add(Duration(minutes: snapped));
            if (!_withinOperatingHours(room, start.hour)) return;
            _openBookingForm(room, start, start.add(const Duration(hours: 1)));
          },
        ),
      ));

      final bookings = (_dayBookings[room.id] ?? []).toList();
      final columns = _layoutOverlapColumns(bookings);
      final colCount = columns.isEmpty ? 1 : columns.length;

      for (int c = 0; c < columns.length; c++) {
        for (final booking in columns[c]) {
          final dayStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _startHour);
          final startMinutes = booking.startTime.difference(dayStart).inMinutes.clamp(0, (_endHour - _startHour) * 60);
          final endMinutes = booking.endTime.difference(dayStart).inMinutes.clamp(0, (_endHour - _startHour) * 60);
          if (endMinutes <= startMinutes) continue;

          final top = startMinutes / 60 * _pixelsPerHour;
          final height = (endMinutes - startMinutes) / 60 * _pixelsPerHour;
          final eventWidth = (_roomColWidth - 4) / colCount;
          final eventLeft = left + 2 + c * eventWidth;

          widgets.add(Positioned(
            left: eventLeft,
            top: top,
            width: eventWidth - 2,
            height: height,
            child: GestureDetector(
              onTap: () => _openBookingDetail(booking),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 1),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(booking.status),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 3, offset: const Offset(0, 1)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      booking.guestName,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (height > 30)
                      Text(
                        '${DateFormat('HH:mm').format(booking.startTime)}–${DateFormat('HH:mm').format(booking.endTime)}',
                        style: const TextStyle(fontSize: 9, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
          ));
        }
      }
    }
    return widgets;
  }

  List<List<RoomBooking>> _layoutOverlapColumns(List<RoomBooking> bookings) {
    final sorted = [...bookings]..sort((a, b) => a.startTime.compareTo(b.startTime));
    final columns = <List<RoomBooking>>[];
    for (final b in sorted) {
      var placed = false;
      for (final col in columns) {
        if (!col.last.endTime.isAfter(b.startTime)) {
          col.add(b);
          placed = true;
          break;
        }
      }
      if (!placed) columns.add([b]);
    }
    return columns;
  }

  Widget _buildNowLine() {
    final now = DateTime.now();
    final dayStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _startHour);
    final minutesFromStart = now.difference(dayStart).inMinutes;
    final top = minutesFromStart / 60 * _pixelsPerHour;
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 2),
              decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            ),
            Expanded(child: Container(height: 1.5, color: Colors.red)),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    final items = <MapEntry<String, Color>>[
      const MapEntry('Chờ xác nhận', Color(0xFFEF9F27)),
      const MapEntry('Đã xác nhận', Color(0xFF185FA5)),
      const MapEntry('Đã nhận phòng', Color(0xFF3B6D11)),
      MapEntry('Đã trả phòng', Colors.grey.shade400),
      MapEntry('Đã huỷ / Không đến', Colors.grey.shade300),
    ];
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.spaceEvenly,
        runAlignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: items.map((e) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: e.value, borderRadius: BorderRadius.circular(3)),
              ),
              const SizedBox(width: 4),
              Text(e.key, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(right: 8, bottom: 4),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 18),
            onPressed: () => setState(() => _pixelsPerHour = (_pixelsPerHour - 15).clamp(30, 150).toDouble()),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 18),
            onPressed: () => setState(() => _pixelsPerHour = (_pixelsPerHour + 15).clamp(30, 150).toDouble()),
          ),
        ],
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

class _HourGridPainter extends CustomPainter {
  final double pixelsPerHour;
  final int hourCount;
  final double columnWidth;
  final int columnCount;

  _HourGridPainter({
    required this.pixelsPerHour,
    required this.hourCount,
    required this.columnWidth,
    required this.columnCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final hourPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;
    final halfHourPaint = Paint()
      ..color = Colors.grey.shade100
      ..strokeWidth = 1;
    final colPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;

    for (int h = 0; h <= hourCount; h++) {
      final y = h * pixelsPerHour;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hourPaint);
      if (h < hourCount) {
        final halfY = y + pixelsPerHour / 2;
        canvas.drawLine(Offset(0, halfY), Offset(size.width, halfY), halfHourPaint);
      }
    }
    for (int c = 0; c <= columnCount; c++) {
      final x = c * columnWidth;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), colPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HourGridPainter oldDelegate) {
    return oldDelegate.pixelsPerHour != pixelsPerHour ||
        oldDelegate.hourCount != hourCount ||
        oldDelegate.columnWidth != columnWidth ||
        oldDelegate.columnCount != columnCount;
  }
}