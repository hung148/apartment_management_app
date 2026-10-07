import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'month_calendar.dart';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import '../../models/team_access.dart';
import '../team/back_steps.dart';
import '../team/booking_workspace_screen.dart';
import '../team/housekeeping_screen.dart';
import '../team/property_contract_screen.dart';
import '../team/property_details_screen.dart';
import '../team/property_layout_screen.dart';
import '../team/room_directory.dart';
import '../team/service_fees_screen.dart';
import '../team/technical_problems_screen.dart';
import '../team/tenant_contacts_screen.dart';
import '../team/tenant_lease_screen.dart';
import '../team/workspace_page_scope.dart';
import '../team/ws_ui.dart';
import 'package:uuid/uuid.dart';

/// Calendar texts (en, vi).
String calText(BuildContext context, String key) {
  final vi = AppTranslations.of(context).locale.languageCode == 'vi';
  const labels = <String, List<String>>{
    'today': ['Today', 'Hôm nay'],
    'modeDay': ['Day', 'Ngày'],
    'modeMonth': ['Month', 'Tháng'],
    'newBuilding': ['New building', 'Tạo tòa nhà'],
    'newStay': ['Book', 'Đặt phòng'],
    'cleaning': ['Cleaning', 'Dọn phòng'],
    'assignCleaning': ['Assign cleaning', 'Giao dọn phòng'],
    // A cleaning's own states (2026-10-05, Tom), not a stay's.
    'cleanTodo': ['Not started', 'Chưa bắt đầu'],
    'cleanDoing': ['In progress', 'Đang dọn'],
    'cleanDone': ['Finished', 'Đã xong'],
    'cleanCircles': ['Cleaning status', 'Trạng thái dọn phòng'],
    'cleanPlanned': ['Planned: {d}', 'Dự kiến: {d}'],
    'cleanActual': ['Worked: {d}', 'Thực tế: {d}'],
    'needsCleaning': ['Needs cleaning', 'Cần dọn phòng'],
    'newRoom': ['New room', 'Tạo phòng'],
    'firstBuilding': [
      'Create your first building to start the calendar.',
      'Tạo tòa nhà đầu tiên để bắt đầu dùng lịch.',
    ],
    'prev': ['Previous month', 'Tháng trước'],
    'next': ['Next month', 'Tháng sau'],
    'allProperties': ['All properties', 'Tất cả tòa nhà'],
    'property': ['Property', 'Tòa nhà'],
    'filterAll': ['All rooms', 'Tất cả phòng'],
    'filterFree': ['Free today', 'Trống hôm nay'],
    'filterTaken': ['Occupied today', 'Có khách hôm nay'],
    'filterProblem': ['Problems', 'Có sự cố'],
    'legend': ['Legend', 'Chú thích'],
    'refresh': ['Refresh', 'Tải lại'],
    'compact': ['Smaller rows', 'Thu gọn'],
    'expand': ['Bigger rows', 'Mở rộng'],
    'noProperties': [
      'There is no property you can see on the calendar.',
      'Chưa có tòa nhà nào bạn được xem lịch.',
    ],
    'noRooms': ['No rooms yet', 'Chưa có phòng'],
    'noMatch': ['No room matches this filter.', 'Không có phòng phù hợp.'],
    'error': [
      'Could not load the calendar. Check the connection and try again.',
      'Không tải được lịch. Kiểm tra kết nối rồi thử lại.',
    ],
    'denied': [
      'You no longer have access to this calendar.',
      'Bạn không còn quyền xem lịch này.',
    ],
    'retry': ['Retry', 'Thử lại'],
    'needsTimeZone': [
      'Set this property\'s time zone first (Settings › Property).',
      'Cần đặt múi giờ cho tòa nhà này trước (Cài đặt › Tòa nhà).',
    ],
    'shortStay': ['Short stay', 'Ngắn ngày'],
    'longStay': ['Long-term lease', 'Thuê dài hạn'],
    'depositOnly': [
      'Deposit paid – not checked in',
      'Đã đặt cọc – chưa check in',
    ],
    'deposited': [
      'Deposit paid – not checked in',
      'Đã đặt cọc – chưa check in',
    ],
    'circles': ['Circle = status', 'Vòng tròn = trạng thái'],
    'statusDeposit': ['Deposit paid', 'Đã cọc'],
    'otherStay': [
      'Taken (you can\'t open it)',
      'Đã có người (bạn không xem được)',
    ],
    'taken': ['Taken', 'Đã có người'],
    'paid': ['Paid in full', 'Đã trả đủ'],
    'deposit': ['Only the deposit paid', 'Mới đặt cọc'],
    'due': ['Still owed', 'Còn nợ'],
    'paidPart': ['Darker part = already paid', 'Phần tô đậm = đã trả'],
    'periodLine': [
      'Line = start of a payment period',
      'Vạch ngang = đầu kỳ thanh toán',
    ],
    'colours': ['Colour = kind of stay', 'Màu = loại thuê'],
    'dots': ['Dot = payment', 'Chấm = thanh toán'],
    'icons': ['Icons', 'Biểu tượng'],
    'upcoming': ['Not checked in yet', 'Chưa check in'],
    'staying': ['Staying', 'Đang ở'],
    'out': ['Checked out', 'Đã check out'],
    'problem': ['Technical problem in the room', 'Phòng có sự cố'],
    'phone': ['Has a phone number', 'Có số điện thoại'],
    'paidUntil': ['Paid until {d}', 'Đã trả đến {d}'],
    'nothingPaid': ['Nothing paid yet', 'Chưa trả tiền'],
    'contractEnd': ['Contract ends {d}', 'Hợp đồng đến {d}'],
    'openEnded': ['No end date', 'Không thời hạn'],
    'roommates': ['{n} living with them', '{n} người ở cùng'],
    'staff': ['Staff: {n}', 'Nhân viên: {n}'],
    'newShort': ['New short stay', 'Đặt phòng ngắn ngày'],
    'newLong': ['New lease', 'Hợp đồng dài hạn'],
    'report': ['Report a problem', 'Báo sự cố'],
    'problems': ['Problems', 'Sự cố'],
    'seeProblems': ['See problems', 'Xem sự cố'],
    'roomBlocked': [
      'This room is closed while a problem is open.',
      'Phòng đang tạm ngừng cho thuê vì có sự cố.',
    ],
    'noAction': [
      'You can\'t add anything in this room.',
      'Bạn không có quyền thêm gì ở phòng này.',
    ],
    'cantOpen': [
      'You don\'t have access to this stay.',
      'Bạn không có quyền xem lượt thuê này.',
    ],
    'close': ['Close', 'Đóng'],
    'room': ['Room {n}', 'Phòng {n}'],
    'openProblems': ['{n} open problem(s)', '{n} sự cố đang mở'],
    'other': ['Other', 'Khác'],
  };
  final pair = labels[key];
  if (pair == null) return key;
  return vi ? pair[1] : pair[0];
}

// The booking platform (Airbnb, Agoda…) is not shown on the calendar
// (2026-10-04, Tom): it is on the booking page.

/// Calendar coordinates are property-local wall-clock times kept in UTC
/// [DateTime]s, so the device's own time zone and DST never move a bar.
DateTime? calStamp(String? s) {
  if (s == null || s.length < 10) return null;
  final y = int.tryParse(s.substring(0, 4)),
      m = int.tryParse(s.substring(5, 7)),
      d = int.tryParse(s.substring(8, 10));
  if (y == null || m == null || d == null) return null;
  var h = 12, mi = 0;
  if (s.length >= 16) {
    h = int.tryParse(s.substring(11, 13)) ?? 12;
    mi = int.tryParse(s.substring(14, 16)) ?? 0;
  }
  return DateTime.utc(y, m, d, h, mi);
}

String _two(int v) => v.toString().padLeft(2, '0');
String calYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

class CalProperty {
  final String id, name;
  final DateTime? today;

  /// The property's wall clock when the calendar was loaded (for the red
  /// "now" line); older servers send none.
  final DateTime? now;
  final bool needsTimeZone,
      canCreateBookings,
      canLease,
      canReadProblems,
      canReportProblems;

  /// Cleaning on the calendar (2026-10-05, Tom): a cleaner sees only cleaning
  /// ([cleaningOnly]); a manager can assign it.
  final bool cleaningOnly, canAssignCleaning, canReadCleaning;
  final List<CalRoom> rooms;
  final List<CalBar> bars;
  CalProperty.fromMap(Map<String, dynamic> m)
    : id = '${m['id']}',
      name = '${m['name'] ?? ''}',
      today = calStamp(m['today'] as String?),
      now = calStamp(m['now'] as String?),
      needsTimeZone = m['needsTimeZone'] == true,
      canCreateBookings = m['canCreateBookings'] == true,
      canLease = m['canLease'] == true,
      canReadProblems = m['canReadProblems'] == true,
      canReportProblems = m['canReportProblems'] == true,
      cleaningOnly = m['cleaningOnly'] == true,
      canAssignCleaning = m['canAssignCleaning'] == true,
      canReadCleaning = m['canReadCleaning'] == true,
      rooms = [
        for (final r in (m['rooms'] as List? ?? const []))
          CalRoom.fromMap(Map<String, dynamic>.from(r as Map)),
      ],
      bars = [
        for (final b in (m['bars'] as List? ?? const []))
          CalBar.fromMap(Map<String, dynamic>.from(b as Map)),
      ];
}

class CalRoom {
  final String id, number;
  final bool shortStay, monthly, blocked;

  /// A guest left after the room's last finished cleaning (2026-10-05).
  final bool needsCleaning;
  final List<String> problems;
  CalRoom.fromMap(Map<String, dynamic> m)
    : id = '${m['id']}',
      number = '${m['roomNumber'] ?? ''}',
      shortStay = m['shortStay'] == true,
      monthly = m['monthly'] == true,
      blocked = m['blocked'] == true,
      needsCleaning = m['needsCleaning'] == true,
      problems = [
        for (final p in (m['problems'] as List? ?? const []))
          '${(p as Map)['title'] ?? ''}',
      ];
}

class CalBar {
  final String id, type, roomId, kind, status, name;
  final String? recordId, pay, platform, channel, staffName;
  final DateTime start;
  final DateTime? end, plannedEnd, paidUntil;

  /// A cleaning bar (type 'cleaning', 2026-10-05): what to do, the planned
  /// window and the real work time; [name] is the cleaner.
  final String title;
  final String? taskStatus;
  final DateTime? plannedStart, actualStart, actualEnd;
  final double? paidFraction;
  final bool canOpen, anonymous, phone, problem;

  /// A deposit is paid (2026-10-04; older servers: a "deposit" kind or payment).
  final bool deposit;
  final int roommates, periodMonths;
  CalBar.fromMap(Map<String, dynamic> m)
    : id = '${m['id']}',
      type = '${m['type']}',
      roomId = '${m['roomId']}',
      kind = '${m['kind'] ?? 'short'}',
      status = '${m['status'] ?? 'upcoming'}',
      name = '${m['name'] ?? ''}',
      recordId = m['recordId'] as String?,
      pay = m['pay'] as String?,
      platform = m['platform'] as String?,
      channel = m['channel'] as String?,
      staffName = (m['staffName'] as String?)?.trim().isEmpty == true
          ? null
          : m['staffName'] as String?,
      start = calStamp(m['start'] as String?) ?? DateTime.utc(1970),
      end = calStamp(m['end'] as String?),
      plannedEnd = calStamp(m['plannedEnd'] as String?),
      title = '${m['title'] ?? ''}',
      taskStatus = m['taskStatus'] as String?,
      plannedStart = calStamp(m['plannedStart'] as String?),
      actualStart = calStamp(m['actualStart'] as String?),
      actualEnd = calStamp(m['actualEnd'] as String?),
      paidUntil = calStamp(m['paidUntil'] as String?),
      paidFraction = (m['paidFraction'] as num?)?.toDouble(),
      canOpen = m['canOpen'] == true,
      anonymous = m['anonymous'] == true,
      phone = m['phone'] == true,
      problem = m['problem'] == true,
      deposit =
          m['deposit'] == true ||
          m['kind'] == 'deposit' ||
          m['pay'] == 'deposit',
      roommates = (m['roommates'] as num?)?.toInt() ?? 0,
      periodMonths = math.max(1, (m['periodMonths'] as num?)?.toInt() ?? 1);

  /// Covers [at] (property-local).
  bool covers(DateTime at) =>
      !start.isAfter(at) && (end == null || end!.isAfter(at));
}

/// Two colours only (2026-10-04, Tom): short stay and long-term lease. A stay
/// someone may not open has the same colour; the status is the circle.
/// How strong a bar's colour is (2026-10-04, Tom: "more opaque", then
/// "stronger"): the paid part and the part still to pay. Names and end labels
/// sit on a light box, so they stay readable on the strong paid colour.
const calPaidAlpha = 0.85, calDueAlpha = 0.40;

/// Corner radius of a day-view bar: rounder, like the month pills
/// (2026-10-05, Tom).
const calBarRadius = 12.0;

Color calKindColor(BuildContext context, CalBar? bar, {String? kind}) =>
    switch (kind ?? (bar?.type == 'lease' ? 'long' : bar?.kind)) {
      'long' => const Color(0xFF2E7D6B),
      // Cleaning (2026-10-05): purple, apart from stays and status colours.
      'cleaning' => const Color(0xFF7B5EA7),
      _ => const Color(0xFF3567B0),
    };

/// A cleaning's details for the hover card (2026-10-05): what, who, the
/// planned window, the real work time and the state.
String calCleaningInfo(BuildContext context, CalBar bar, String roomNumber) {
  String two(int v) => v.toString().padLeft(2, '0');
  String t(DateTime d) =>
      '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  String hm(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
  final ps = bar.plannedStart, pe = bar.plannedEnd;
  final as = bar.actualStart, ae = bar.actualEnd;
  return [
    calText(context, 'room').replaceAll('{n}', roomNumber),
    calBarName(context, bar),
    if (bar.title.trim().isNotEmpty) bar.title.trim(),
    if (ps != null && pe != null)
      calText(
        context,
        'cleanPlanned',
      ).replaceAll('{d}', '${t(ps)} – ${hm(pe)}'),
    if (as != null)
      calText(
        context,
        'cleanActual',
      ).replaceAll('{d}', '${t(as)} – ${ae == null ? '…' : hm(ae)}'),
    calText(context, calCleaningStatus(bar)),
  ].join('\n');
}

/// 'cleanTodo' (assigned), 'cleanDoing' (started), 'cleanDone'.
String calCleaningStatus(CalBar bar) => switch (bar.taskStatus) {
  'completed' => 'cleanDone',
  'inProgress' => 'cleanDoing',
  _ => 'cleanTodo',
};

/// What a bar says: the guest, "taken" for a stay this person may not open,
/// or "Dọn phòng · <cleaner>" for a cleaning.
String calBarName(BuildContext context, CalBar bar) {
  if (bar.anonymous) return calText(context, 'taken');
  if (bar.type == 'cleaning') {
    final who = bar.name.trim();
    return who.isEmpty
        ? calText(context, 'cleaning')
        : '${calText(context, 'cleaning')} · $who';
  }
  return bar.name.isEmpty ? '—' : bar.name;
}

/// The stay's status (2026-10-04): đã đặt cọc – chưa check in ('deposited'),
/// chưa check in ('upcoming'), đang ở ('staying'), đã check out ('out').
/// A cleaning has its own (2026-10-05, Tom): chưa bắt đầu ('cleanTodo'),
/// đang dọn ('cleanDoing'), đã xong ('cleanDone').
String calStayStatus(CalBar bar) => bar.type == 'cleaning'
    ? calCleaningStatus(bar)
    : bar.status == 'staying' || bar.status == 'out'
    ? bar.status
    : bar.deposit
    ? 'deposited'
    : 'upcoming';

Color calStatusColor(String status) => switch (status) {
  'deposited' => const Color(0xFFE08A00),
  'staying' => const Color(0xFF2E9E5B),
  'out' => const Color(0xFF5F6B7A),
  'cleanTodo' => const Color(0xFF7B5EA7),
  'cleanDoing' => const Color(0xFF1E88E5),
  // Not the stay green: a finished cleaning must not read as 'staying'.
  'cleanDone' => const Color(0xFF00897B),
  _ => const Color(0xFF7A8594),
};

/// The status circle: hollow while nobody has paid or checked in yet.
BoxDecoration calStatusDecoration(String status) =>
    status == 'upcoming' || status == 'cleanTodo'
    ? BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: calStatusColor(status), width: 1.6),
      )
    : BoxDecoration(
        shape: BoxShape.circle,
        color: calStatusColor(status),
        border: Border.all(color: Colors.white, width: 1),
      );

/// C1–C3: one calendar for every property the person can see. Rooms are the
/// columns (grouped by property), days are the rows. Tapping a stay opens its
/// page in a dialog; tapping an empty day offers a new stay for that room.
class RoomCalendar extends StatefulWidget {
  final String organizationId, accountId;
  final TeamService service;

  /// What this person may do (create buildings/rooms, building and room
  /// pages). Null: only the calendar itself (stays are checked by the server).
  final TeamAccess? access;

  /// First month shown (tests); defaults to this month.
  final DateTime? initialMonth;
  const RoomCalendar({
    super.key,
    required this.organizationId,
    required this.accountId,
    required this.service,
    this.access,
    this.initialMonth,
  });
  @override
  State<RoomCalendar> createState() => _RoomCalendarState();
}

class _RoomCalendarState extends State<RoomCalendar> {
  final _hBody = ScrollController(), _hHead = ScrollController();
  final _vBody = ScrollController(), _vDates = ScrollController();
  late DateTime _month;
  List<CalProperty> _properties = [];
  bool _busy = true, _loaded = false, _syncing = false, _scrollToToday = true;
  String? _error, _property;
  int _generation = 0;
  double _lastDayW = calHourW * 24;

  String c(String key) => calText(context, key);

  @override
  void initState() {
    super.initState();
    final now = widget.initialMonth ?? DateTime.now();
    // Infinite scroll (2026-10-04, Tom): three months are loaded (the one
    // before, the one shown, the one after); scrolling near either end moves
    // the window by a month and keeps the same days on screen.
    _month = DateTime.utc(now.year, now.month - 1);
    _jumpTo = DateTime.utc(now.year, now.month);
    _link(_hBody, _hHead);
    _link(_hHead, _hBody);
    _link(_vBody, _vDates);
    _link(_vDates, _vBody);
    _hBody.addListener(_edge);
    _load();
  }

  /// A day to bring to the left edge once the grid is laid out.
  DateTime? _jumpTo;

  /// Month view (2026-10-04, Tom): Airbnb-like weeks of day boxes, all rooms.
  bool _monthMode = false;
  DateTime _monthFocus = DateTime.utc(2000);
  int _focusToken = 0;
  DateTime? _monthShown;

  /// Day view ↔ month view, keeping the month being looked at.
  void _setMode(bool month) {
    if (month == _monthMode) return;
    if (month) {
      final m = _shown;
      setState(() {
        _monthMode = true;
        _monthFocus = m;
        _monthShown = m;
        _focusToken++;
      });
      return;
    }
    final m = _monthShown ?? _monthFocus;
    final today = _today;
    final window = DateTime.utc(m.year, m.month - 1);
    setState(() {
      _monthMode = false;
      _scrollToToday =
          today != null && today.year == m.year && today.month == m.month;
      _jumpTo = m;
      if (window != _month) _month = window;
    });
    _load();
  }

  /// The month view reached its top or bottom: one more month that way.
  void _monthEdge(int direction) {
    if (_busy) return;
    setState(
      () => _month = DateTime.utc(_month.year, _month.month + direction),
    );
    _load();
  }

  /// The "now" line (2026-10-04, Tom): the property's clock at load time,
  /// moved on by the time passed since, redrawn every minute.
  DateTime? _loadedAt;
  Timer? _clock;
  DateTime? get _now {
    final p = _current, at = _loadedAt;
    if (p?.now == null || at == null) return null;
    return p!.now!.add(DateTime.now().difference(at));
  }

  bool _shifting = false;

  /// The month at the left of the screen (shown in the toolbar).
  DateTime get _shown {
    var idx = 0;
    if (_hBody.hasClients && _hBody.positions.length == 1) {
      idx = (_hBody.offset / _lastDayW + 0.5).floor().clamp(0, _days - 1);
    } else if (_jumpTo != null) {
      idx = _jumpTo!.difference(_month).inDays.clamp(0, _days - 1);
    } else {
      idx = DateTime.utc(
        _month.year,
        _month.month + 1,
      ).difference(_month).inDays;
    }
    final d = _month.add(Duration(days: idx));
    return DateTime.utc(d.year, d.month);
  }

  /// The month of the last day on screen (the label names both when the
  /// screen shows the end of one month and the start of the next).
  DateTime get _shownLast {
    if (!_hBody.hasClients || _hBody.positions.length != 1) return _shown;
    final idx = ((_hBody.offset + _lastViewW) / _lastDayW - 0.5).floor().clamp(
      0,
      _days - 1,
    );
    final d = _month.add(Duration(days: idx));
    return DateTime.utc(d.year, d.month);
  }

  double _lastViewW = 0;

  /// Near either end of the loaded months: move the window by one month.
  void _edge() {
    if (_shifting ||
        !_loaded ||
        !_hBody.hasClients ||
        _hBody.positions.length != 1) {
      return;
    }
    // Never while a drag or fling is still moving the dates or the rooms:
    // moving the window under a moving scroll threw the view to the wrong
    // month (live check 2026-10-04). It runs again when the scroll ends.
    bool moving(ScrollController c) =>
        c.hasClients &&
        c.positions.length == 1 &&
        c.position.isScrollingNotifier.value;
    if (moving(_hBody) || moving(_hHead)) return;
    final pos = _hBody.position, margin = 7 * _lastDayW;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels < margin) {
      _shift(-1);
    } else if (pos.pixels > pos.maxScrollExtent - margin) {
      _shift(1);
    }
  }

  void _shift(int months) {
    final old = _month, next = DateTime.utc(old.year, old.month + months);
    final days = next.difference(old).inDays;
    final target = _hBody.offset - days * _lastDayW;
    _shifting = true;
    setState(() => _month = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Both the rooms and the dates, so neither keeps an old position.
      for (final c in [_hBody, _hHead]) {
        if (mounted && c.hasClients && c.positions.length == 1) {
          c.jumpTo(target.clamp(0.0, c.position.maxScrollExtent));
        }
      }
      _shifting = false;
    });
    _load();
  }

  void _link(ScrollController from, ScrollController to) {
    from.addListener(() {
      if (_syncing || !from.hasClients || !to.hasClients) return;
      _syncing = true;
      final target = from.offset.clamp(0.0, to.position.maxScrollExtent);
      if (to.offset != target) to.jumpTo(target);
      _syncing = false;
    });
  }

  @override
  void didUpdateWidget(covariant RoomCalendar old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.service != widget.service) {
      _properties = [];
      _loaded = false;
      _load();
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    for (final s in [_hBody, _hHead, _vBody, _vDates]) {
      s.dispose();
    }
    // A page left open must not outlive the calendar that opened it (sign-out,
    // role or organization change): it would keep showing what this person
    // may no longer open. Removed after the frame, when the navigator is free.
    final open = List.of(_dialogs);
    _dialogs.clear();
    if (open.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final route in open) {
          if (route.isActive) route.navigator?.removeRoute(route);
        }
      });
    }
    super.dispose();
  }

  /// The loaded window: three months from [_month] (the first of a month).
  DateTime get _monthEnd => DateTime.utc(_month.year, _month.month + 3);
  int get _days => _monthEnd.difference(_month).inDays;

  /// "Today" in the properties' own zone (the first one when zones differ).
  DateTime? get _today {
    for (final p in _properties) {
      if (p.today != null) return p.today;
    }
    return null;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    // Speed (2026-10-06, device copy): the copy saved on this device shows
    // right away (the progress bar keeps running); the server's answer then
    // replaces it. If the server cannot be reached, the saved copy stays with
    // the error notice and its own "updated" time.
    try {
      await for (final r in widget.service.calendarViewLive({
        'organizationId': widget.organizationId,
        'from': calYmd(_month),
        'to': calYmd(_monthEnd),
      })) {
        if (!mounted || generation != _generation) return;
        setState(() {
          _properties = [
            for (final p in (r.data['properties'] as List? ?? const []))
              CalProperty.fromMap(Map<String, dynamic>.from(p as Map)),
          ];
          _loadedAt = r.at;
          _clock ??= Timer.periodic(const Duration(minutes: 1), (_) {
            if (mounted) setState(() {});
          });
          if (!_properties.any((p) => p.id == _property))
            _property = _properties.firstOrNull?.id;
          _busy = r.saved;
          _loaded = true;
        });
        _afterLayout();
      }
    } catch (e) {
      if (!mounted || generation != _generation) return;
      final denied =
          e is FirebaseFunctionsException && e.code == 'permission-denied';
      setState(() {
        _busy = false;
        _error = denied ? 'denied' : 'error';
        // No access any more: nothing saved may stay on screen.
        if (denied) _properties = [];
      });
    }
  }

  void _afterLayout() {
    if (!_scrollToToday && _jumpTo == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hBody.hasClients) return;
      final today = _today;
      double? target;
      if (_scrollToToday &&
          today != null &&
          !today.isBefore(_month) &&
          today.isBefore(_monthEnd)) {
        // The current time a quarter of the way in (2026-10-04: with
        // 432 px days, "one day before today" filled most of the screen).
        // (Today may be stamped at noon: compare the date only.)
        final now = _now;
        final start = today.subtract(
          Duration(hours: today.hour, minutes: today.minute),
        );
        final at =
            now != null &&
                now.year == today.year &&
                now.month == today.month &&
                now.day == today.day
            ? now
            : start.add(const Duration(hours: 9));
        target = _x(at, _lastDayW) - _lastViewW / 4;
      } else if (_jumpTo != null) {
        target = _jumpTo!.difference(_month).inDays * _lastDayW;
      }
      _scrollToToday = false;
      _jumpTo = null;
      if (target == null) return;
      _shifting = true;
      _hBody.jumpTo(target.clamp(0.0, _hBody.position.maxScrollExtent));
      _shifting = false;
      setState(() {});
    });
  }

  /// The month before or after the one shown: that month at the left edge.
  void _goMonth(int delta) {
    if (_monthMode) {
      final m = _monthShown ?? _monthFocus;
      final target = DateTime.utc(m.year, m.month + delta);
      setState(() {
        _month = DateTime.utc(target.year, target.month - 1);
        _monthFocus = target;
        _monthShown = target;
        _focusToken++;
      });
      _load();
      return;
    }
    final shown = _shown,
        target = DateTime.utc(shown.year, shown.month + delta);
    setState(() {
      _month = DateTime.utc(target.year, target.month - 1);
      _jumpTo = target;
      _scrollToToday = false;
    });
    _load();
  }

  void _goToday() {
    if (_monthMode) {
      final t = _today ?? DateTime.now().toUtc();
      final target = DateTime.utc(t.year, t.month);
      final window = DateTime.utc(t.year, t.month - 1);
      setState(() {
        _monthFocus = target;
        _monthShown = target;
        _focusToken++;
      });
      if (window != _month) {
        setState(() => _month = window);
        _load();
      }
      return;
    }
    final today = _today ?? DateTime.now().toUtc();
    final month = DateTime.utc(today.year, today.month - 1);
    _scrollToToday = true;
    _jumpTo = DateTime.utc(today.year, today.month);
    if (month == _month) {
      _afterLayout();
      setState(() {});
    } else {
      setState(() => _month = month);
      _load();
    }
  }

  double _rowH(BuildContext context) {
    // Thin bars like the month pills, rows just tall enough for them
    // (2026-10-05, Tom): a 24 px bar with 3 px above and below.
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    return 30.0 * scale;
  }

  // ---- Layout ----

  /// The building shown: the chosen one, else the first.
  CalProperty? get _current =>
      _properties.where((p) => p.id == _property).firstOrNull ??
      _properties.firstOrNull;

  /// The shown building's rooms (or one "no rooms" row).
  List<(CalProperty, CalRoom?)> _columns() {
    final p = _current;
    if (p == null) return const [];
    if (p.rooms.isEmpty) return [(p, null)];
    return [for (final r in p.rooms) (p, r)];
  }

  @override
  Widget build(BuildContext context) {
    // Short screens (phone landscape): the toolbar stays one scrolling line
    // so the days keep most of the height.
    return LayoutBuilder(
      builder: (context, box) => _layout(
        context,
        oneLine: box.maxHeight < 480,
        narrow: box.maxWidth < 600,
      ),
    );
  }

  Widget _layout(
    BuildContext context, {
    required bool oneLine,
    required bool narrow,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(context, oneLine: oneLine, narrow: narrow),
        SizedBox(
          height: 3,
          child: _busy ? const LinearProgressIndicator() : null,
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: WsNotice(
              c(_error!),
              action: TextButton(
                onPressed: _busy ? null : _load,
                child: Text(c('retry')),
              ),
            ),
          ),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _toolbar(
    BuildContext context, {
    bool oneLine = false,
    bool narrow = false,
  }) {
    final theme = Theme.of(context);
    final vi = AppTranslations.of(context).locale.languageCode == 'vi';
    const en = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    // Phones: the short form, so it stays readable at large text sizes.
    // The month at the left of the screen, updated while scrolling.
    String one(DateTime m) => narrow
        ? '${_two(m.month)}/${m.year}'
        : vi
        ? 'Tháng ${m.month}, ${m.year}'
        : '${en[m.month - 1]} ${m.year}';
    // Two months on screen: both, e.g. "Tháng 10 – 11, 2026".
    String label(DateTime a, DateTime b) {
      if (a == b) return one(a);
      if (a.year != b.year) return '${one(a)} – ${one(b)}';
      return narrow
          ? '${_two(a.month)}–${_two(b.month)}/${a.year}'
          : vi
          ? 'Tháng ${a.month} – ${b.month}, ${a.year}'
          : '${en[a.month - 1]} – ${en[b.month - 1]} ${a.year}';
    }

    final month = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120),
      child: ListenableBuilder(
        listenable: _hBody,
        builder: (context, _) => Text(
          _monthMode
              ? one(_monthShown ?? _monthFocus)
              : label(_shown, _shownLast),
          key: const ValueKey('calendar-month'),
          textAlign: TextAlign.center,
          maxLines: 1,
          style: theme.textTheme.titleMedium,
        ),
      ),
    );
    final nav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          key: const ValueKey('calendar-today'),
          onPressed: _busy && !_loaded ? null : _goToday,
          child: Text(c('today')),
        ),
        const SizedBox(width: 4),
        IconButton(
          key: const ValueKey('calendar-prev'),
          visualDensity: VisualDensity.compact,
          tooltip: c('prev'),
          onPressed: () => _goMonth(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        // In the one-line (scrolling) toolbar the width is unbounded: no Flexible.
        if (oneLine)
          month
        else
          Flexible(
            child: FittedBox(fit: BoxFit.scaleDown, child: month),
          ),
        IconButton(
          key: const ValueKey('calendar-next'),
          visualDensity: VisualDensity.compact,
          tooltip: c('next'),
          onPressed: () => _goMonth(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
    // Phones: legend and reload share one "…" menu to leave room for the month.
    final menu = PopupMenuButton<String>(
      key: const ValueKey('calendar-menu'),
      tooltip: vi ? 'Chú thích và tải lại' : 'Legend and refresh',
      icon: const Icon(Icons.tune),
      onSelected: (v) {
        if (v == 'legend') _showLegend(context);
        if (v == 'refresh' && !_busy) _load();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'legend',
          child: ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(c('legend')),
          ),
        ),
        PopupMenuItem(
          value: 'refresh',
          enabled: !_busy,
          child: ListTile(
            leading: const Icon(Icons.refresh),
            title: Text(c('refresh')),
          ),
        ),
      ],
    );
    // Day view (rooms × hours) or month view (Airbnb-like weeks).
    final modes = SegmentedButton<bool>(
      key: const ValueKey('calendar-mode'),
      segments: [
        ButtonSegment(value: false, label: Text(c('modeDay'), maxLines: 1)),
        ButtonSegment(value: true, label: Text(c('modeMonth'), maxLines: 1)),
      ],
      selected: {_monthMode},
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelectionChanged: _loaded ? (v) => _setMode(v.first) : null,
    );
    final tools = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        modes,
        const SizedBox(width: 4),
        IconButton(
          key: const ValueKey('calendar-legend'),
          tooltip: c('legend'),
          onPressed: () => _showLegend(context),
          icon: const Icon(Icons.info_outline),
        ),
        IconButton(
          key: const ValueKey('calendar-refresh'),
          tooltip: c('refresh'),
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
    // One building at a time: its name, or a picker when there are several,
    // then its settings gear (2026-10-04, Tom: moved here from the grid).
    final current = _current;
    double nameWidth(String name) {
      final painter = TextPainter(
        text: TextSpan(text: name, style: theme.textTheme.titleSmall),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
        maxLines: 1,
      )..layout();
      return painter.width.ceilToDouble() + 112;
    }

    final pickerWidth = current == null ? 240.0 : nameWidth(current.name);
    final Widget? buildingName = current == null
        ? null
        : _properties.length < 2
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.apartment_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  current.name,
                  key: const ValueKey('calendar-building-name'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          )
        : SizedBox(
            width: pickerWidth,
            child: DropdownButtonFormField<String>(
              key: ValueKey('calendar-building-${current.id}'),
              initialValue: current.id,
              isExpanded: true,
              isDense: false,
              itemHeight: null,
              selectedItemBuilder: (_) => [for (final _ in _properties) Text(current.name)],
              style: theme.textTheme.titleSmall,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: Icon(Icons.apartment_outlined, size: 18),
              ),
              items: [
                for (final p in _properties)
                  DropdownMenuItem<String>(
                    value: p.id,
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(p.name)),
                  ),
              ],
              onChanged: (v) {
                if (v != null && v != _property) {
                  setState(() {
                    _property = v;
                    _scrollToToday = true;
                  });
                  _afterLayout();
                }
              },
            ),
          );
    final Widget? building = current == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: buildingName!),
              if (current.needsTimeZone)
                Tooltip(
                  message: c('needsTimeZone'),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: wsToneColor(context, WsTone.warning),
                    ),
                  ),
                ),
              if (_buildingPages(current).isNotEmpty)
                IconButton(
                  key: ValueKey('calendar-building-pages-${current.id}'),
                  iconSize: 28,
                  tooltip: current.name,
                  onPressed: () => _openBuilding(current),
                  icon: Icon(
                    Icons.settings_outlined,
                    size: 28,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          );
    final canCreateBuilding =
        widget.access?.allBuildings == true &&
        widget.access!.allows(TeamPermission.manageProperty);
    final canCreateRoom =
        current != null &&
        !current.needsTimeZone &&
        widget.access?.allows(
              TeamPermission.manageProperty,
              buildingId: current.id,
            ) ==
            true;
    // Icon buttons, the name in the tooltip (2026-10-05, Tom). Order:
    // building, room, problems, cleaning, then the main one (book).
    final canClean =
        current != null &&
        (widget.access?.allows(
                  TeamPermission.manageProperty,
                  buildingId: current.id,
                ) ==
                true ||
            widget.access?.allows(
                  TeamPermission.readAssignedTasks,
                  buildingId: current.id,
                ) ==
                true);
    Widget tool(String key, IconData icon, String tip, VoidCallback onTap) =>
        IconButton.outlined(
          key: ValueKey(key),
          tooltip: tip,
          onPressed: onTap,
          icon: Icon(icon, size: 20),
        );
    final buttons = <Widget>[
      if (canCreateBuilding)
        tool(
          'calendar-new-building',
          Icons.add_business_outlined,
          c('newBuilding'),
          _newBuilding,
        ),
      if (canCreateRoom)
        tool(
          'calendar-new-room',
          Icons.meeting_room_outlined,
          c('newRoom'),
          () => _newRoom(current),
        ),
      // Every room's problems, and "Báo sự cố" there (2026-10-05, Tom).
      if (current != null && current.canReadProblems)
        tool(
          'calendar-problems',
          Icons.build_outlined,
          c('problems'),
          () => _buildingProblems(current),
        ),
      // Housekeeping tasks (the "Dọn phòng" (was "Buồng phòng") section is gone for people
      // who have the calendar, 2026-10-05, Tom).
      if (canClean)
        tool(
          'calendar-cleaning',
          Icons.cleaning_services_outlined,
          c('cleaning'),
          () => _cleaning(current),
        ),
      // 2026-10-04: bookings are made here (the Đặt phòng page is gone).
      if (current != null &&
          !current.needsTimeZone &&
          (current.canCreateBookings || current.canLease))
        IconButton.filled(
          key: const ValueKey('calendar-new-stay'),
          tooltip: c('newStay'),
          onPressed: () => _newStay(current),
          icon: const Icon(Icons.event_available_outlined, size: 20),
        ),
    ];
    final availableWidth = MediaQuery.sizeOf(context).width;
    final compactActions =
        availableWidth < pickerWidth + 64 + buttons.length * 48 + 32;
    final actionWidgets = compactActions && buttons.isNotEmpty
        ? <Widget>[
            PopupMenuButton<int>(
              key: const ValueKey('calendar-actions-menu'),
              tooltip: vi ? 'Thao tác' : 'Actions',
              icon: const Icon(Icons.more_vert),
              onSelected: (index) =>
                  (buttons[index] as IconButton).onPressed?.call(),
              itemBuilder: (_) => [
                for (var i = 0; i < buttons.length; i++)
                  PopupMenuItem(
                    key: buttons[i].key,
                    value: i,
                    child: Row(
                      children: [
                        (buttons[i] as IconButton).icon,
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text((buttons[i] as IconButton).tooltip!),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ]
        : buttons;
    final buildingWidth = _properties.length < 2 && current != null
        ? nameWidth(current.name) + 48
        : pickerWidth + 48;
    final propertyActions = Row(
      children: [
        Expanded(
          child: building ?? const SizedBox.shrink(),
        ),
        for (final button in actionWidgets)
          Padding(padding: const EdgeInsets.only(left: 8), child: button),
      ],
    );
    // Like the workspace bars: keeps its size; very large text is capped here.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Material(
        color: theme.colorScheme.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: oneLine
                ? SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (building != null) ...[
                          // Name (or picker) and the settings gear.
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: buildingWidth,
                            ),
                            child: building,
                          ),
                          const SizedBox(width: 12),
                        ],
                        for (final b in actionWidgets)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: b,
                          ),
                        nav,
                        const SizedBox(width: 12),
                        tools,
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Building, then its create buttons; buttons move to the
                      // next line when the name needs the room.
                      if (building != null || buttons.isNotEmpty || narrow)
                        propertyActions,
                      if (building != null || buttons.isNotEmpty || narrow)
                        const SizedBox(height: 6),
                      if (narrow)
                        LayoutBuilder(builder: (context, constraints) {
                          if (constraints.maxWidth >= 480) {
                            return Row(children: [Expanded(child: nav), modes, menu]);
                          }
                          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Align(alignment: AlignmentDirectional.centerStart, child: nav),
                            Transform.translate(offset: const Offset(0, 4),
                              child: Row(children: [modes, const Spacer(), menu])),
                          ]);
                        })
                      else Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: nav,
                            ),
                          ),
                          if (narrow) menu else tools,
                        ],
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_properties.isEmpty) {
      final canCreate =
          widget.access?.allBuildings == true &&
          widget.access!.allows(TeamPermission.manageProperty);
      return ListView(
        children: [
          WsEmpty(
            icon: Icons.calendar_month_outlined,
            message: c(canCreate ? 'firstBuilding' : 'noProperties'),
            action: canCreate
                ? FilledButton.icon(
                    key: const ValueKey('calendar-first-building'),
                    onPressed: _newBuilding,
                    icon: const Icon(Icons.add_business_outlined, size: 18),
                    label: Text(c('newBuilding')),
                  )
                : null,
          ),
        ],
      );
    }
    final current = _current;
    if (_monthMode && current != null) {
      return MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: CalMonthView(
          key: ValueKey('calendar-month-view-${current.id}'),
          property: current,
          months: [
            for (var i = 0; i < 3; i++)
              DateTime.utc(_month.year, _month.month + i),
          ],
          focus: _monthFocus,
          focusToken: _focusToken,
          onOpen: (room, bar) => _openBar(current, room, bar),
          onDay: (day) => _newStay(current, on: day),
          onEdge: _monthEdge,
          onShown: (m) {
            if (_monthShown != m && mounted) setState(() => _monthShown = m);
          },
        ),
      );
    }
    final columns = _columns();
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: LayoutBuilder(
        builder: (context, constraints) => _grid(context, columns, constraints),
      ),
    );
  }

  Widget _grid(
    BuildContext context,
    List<(CalProperty, CalRoom?)> rooms,
    BoxConstraints constraints,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final wide = constraints.maxWidth >= 700;
    final rowH = _rowH(context);
    // The room column is as wide as the longest room name needs
    // (2026-10-05, Tom: "too much waste space"), within limits; a long name
    // goes on two smaller lines.
    final roomW = _roomColumnWidth(context, rooms, wide);
    // 18 px an hour on every screen (2026-10-04, Tom: "at least it should be
    // able to show a bar for 1 hour"): a 1-hour stay is drawn at its real
    // length, as wide as the shortest bar (18 px). A day is 432 px: about
    // 1.6 days on an 800 px window, 3 on 1440 px, most of a day on a phone.
    // The loaded months scroll sideways.
    const dayW = calHourW * 24;
    _lastDayW = dayW; // for "Today" scrolling
    _lastViewW = constraints.maxWidth - roomW; // for the month label
    // The day header has the date and a small hour line (6 · 12 · 18).
    final headH = 43.0 * scale;
    final gridW = dayW * _days;
    final today = _today;
    final todayCol =
        today == null || today.isBefore(_month) || !today.isBefore(_monthEnd)
        ? null
        : today.difference(_month).inDays;
    // Days before today are grey, like the month view (2026-10-05, Tom).
    final pastDays = today == null
        ? 0
        : today.isBefore(_month)
        ? 0
        : !today.isBefore(_monthEnd)
        ? _days
        : today.difference(_month).inDays;

    // The current time: a red line across the dates and the rooms.
    final now = _now;
    final nowX = now == null || now.isBefore(_month) || !now.isBefore(_monthEnd)
        ? null
        : _x(now, dayW);
    final nowColor = wsToneColor(context, WsTone.bad);

    // Each room's stays, placed in lanes. Only stays that overlap each other
    // (should not happen) get a lane of their own; the row grows for them
    // so every bar keeps its full height (2026-10-05, Tom).
    final barH = rowH - 6;
    List<(CalBar, double, double, int)> place(CalProperty p, CalRoom room) {
      final placed = <(CalBar, double, double)>[];
      for (final b in p.bars.where((b) => b.roomId == room.id)) {
        var left = _x(b.start, dayW),
            right = b.end == null ? gridW : _x(b.end!, dayW);
        left = left.clamp(0.0, gridW);
        right = right.clamp(0.0, gridW);
        if (right <= 0 || left >= gridW) continue;
        if (right - left < 18) {
          right = math.min(gridW, left + 18);
          if (right - left < 18) left = math.max(0.0, right - 18);
        }
        placed.add((b, left, right));
      }
      placed.sort((a, b) => a.$2.compareTo(b.$2));
      final laneEnds = <double>[];
      final out = <(CalBar, double, double, int)>[];
      for (final (b, left, right) in placed) {
        var lane = laneEnds.indexWhere((e) => e <= left + 0.5);
        if (lane < 0) {
          lane = laneEnds.length;
          laneEnds.add(right);
        } else {
          laneEnds[lane] = right;
        }
        out.add((b, left, right, lane));
      }
      return out;
    }

    // Rows: one per room (or a "no rooms" row).
    final rows =
        <
          ({CalProperty p, CalRoom? room, bool band, double top, double height})
        >[];
    final placedIn = <String, List<(CalBar, double, double, int)>>{};
    var y = 0.0;
    // One building is shown and named in the toolbar (with its settings
    // gear), so there is no building row above the rooms (2026-10-04, Tom).
    for (final (p, room) in rooms) {
      var height = rowH;
      if (room != null) {
        final placed = placedIn[room.id] = place(p, room);
        final lanes = placed.fold<int>(0, (m, e) => math.max(m, e.$4 + 1));
        if (lanes > 1) height += (lanes - 1) * (barH + 2);
      }
      rows.add((p: p, room: room, band: false, top: y, height: height));
      y += height;
    }
    final gridH = y;

    final bars = <Widget>[];
    // Every bar's place, for the edge bubbles (2026-10-04, Tom).
    final spots =
        <
          ({
            CalProperty p,
            CalRoom room,
            CalBar bar,
            double left,
            double right,
            double top,
            double height,
          })
        >[];
    for (final row in rows) {
      final room = row.room;
      if (row.band || room == null) continue;
      final p = row.p;
      for (final (b, left, right, lane)
          in placedIn[room.id] ?? const <(CalBar, double, double, int)>[]) {
        final top = row.top + 3 + lane * (barH + 2);
        spots.add((
          p: p,
          room: room,
          bar: b,
          left: left + 1,
          right: right - 1,
          top: top,
          height: barH,
        ));
        bars.add(
          Positioned(
            left: left + 1,
            top: top,
            width: right - left - 2,
            height: barH,
            child: CalBarTile(
              key: ValueKey('calendar-bar-${b.id}'),
              bar: b,
              roomNumber: room.number,
              from: left,
              to: right,
              x: (t) => _x(t, dayW),
              onTap: () => _openBar(p, room, b),
              // The part of the month on screen: the bar's name, icons and
              // status follow it while scrolling sideways (2026-10-04, Tom).
              scroll: _hBody,
              viewWidth: constraints.maxWidth - roomW,
            ),
          ),
        );
      }
    }

    final body = SizedBox(
      width: gridW,
      height: gridH,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('calendar-grid'),
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                final day = (d.localPosition.dx / dayW).floor();
                if (day < 0 || day >= _days) return;
                for (final row in rows) {
                  if (d.localPosition.dy >= row.top &&
                      d.localPosition.dy < row.top + row.height) {
                    final room = row.room;
                    if (!row.band && room != null) {
                      _openCell(
                        row.p,
                        room,
                        DateTime.utc(_month.year, _month.month, 1 + day),
                      );
                    }
                    return;
                  }
                }
              },
              child: CustomPaint(
                painter: _GridPainter(
                  month: _month,
                  days: _days,
                  dayW: dayW,
                  todayCol: todayCol,
                  pastDays: pastDays,
                  pastFill: theme.brightness == Brightness.dark
                      ? scheme.surfaceContainerLowest
                      : const Color(0xFFDDE1DD),
                  rows: [
                    for (final r in rows)
                      (r.top, r.height, r.band, r.room?.blocked == true),
                  ],
                  line: scheme.outlineVariant,
                  strong: scheme.outline.withValues(alpha: 0.6),
                  band: scheme.primary.withValues(alpha: 0.06),
                  blockedFill: wsToneColor(
                    context,
                    WsTone.bad,
                  ).withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
          for (final row in rows)
            if (!row.band && row.room == null)
              Positioned(
                left: 12,
                top: row.top,
                height: row.height,
                child: Center(
                  child: Text(
                    c('noRooms'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          // The now line under the bars (2026-10-04, Tom: it ran through a
          // name): full red in empty cells, faint through a bar's colour,
          // never over a name or an end label (they sit on light boxes).
          if (nowX != null)
            Positioned(
              key: const ValueKey('calendar-now-line'),
              left: nowX - 1,
              width: 2,
              top: 0,
              bottom: 0,
              child: IgnorePointer(child: ColoredBox(color: nowColor)),
            ),
          ...bars,
          // A bar cut by the screen edge with only a sliver left shows a
          // bubble next to that sliver: name and status (2026-10-04, Tom).
          Positioned.fill(
            child: ListenableBuilder(
              listenable: _hBody,
              builder: (context, _) => _edgeBubbles(
                spots,
                constraints.maxWidth - roomW,
                gridW,
                gridH,
              ),
            ),
          ),
        ],
      ),
    );

    final vi = AppTranslations.of(context).locale.languageCode == 'vi';
    final weekdays = vi
        ? const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final header = SizedBox(
      width: gridW,
      height: headH,
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < _days; i++)
                _dayCell(
                  context,
                  DateTime.utc(_month.year, _month.month, 1 + i),
                  weekdays,
                  dayW,
                  headH,
                  i == todayCol,
                ),
            ],
          ),
          if (nowX != null)
            Positioned(
              key: const ValueKey('calendar-now-head'),
              left: nowX - 4,
              width: 8,
              top: headH - 15,
              bottom: 0,
              child: IgnorePointer(
                child: CustomPaint(painter: _NowMarkPainter(nowColor)),
              ),
            ),
        ],
      ),
    );
    final labels = SizedBox(
      width: roomW,
      height: gridH,
      child: Stack(
        children: [
          for (final row in rows)
            Positioned(
              left: 0,
              top: row.top,
              width: roomW,
              height: row.height,
              child: _roomLabel(context, row.p, row.room),
            ),
        ],
      ),
    );

    final drag = ScrollConfiguration.of(
      context,
    ).copyWith(dragDevices: PointerDeviceKind.values.toSet());
    return NotificationListener<ScrollEndNotification>(
      // A drag or fling that ended near either end of the loaded months.
      onNotification: (n) {
        if (n.metrics.axis == Axis.horizontal) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _edge();
          });
        }
        return false;
      },
      child: ScrollConfiguration(
        behavior: drag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: roomW,
                  height: headH,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(color: scheme.outlineVariant),
                      bottom: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                ),
                Expanded(
                  child: Scrollbar(
                    controller: _hHead,
                    child: SingleChildScrollView(
                      controller: _hHead,
                      scrollDirection: Axis.horizontal,
                      child: header,
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SingleChildScrollView(controller: _vDates, child: labels),
                  Expanded(
                    child: Scrollbar(
                      controller: _vBody,
                      child: SingleChildScrollView(
                        controller: _vBody,
                        child: SingleChildScrollView(
                          controller: _hBody,
                          scrollDirection: Axis.horizontal,
                          child: body,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Name bubbles: for a bar with less than 24 px on screen because the
  /// month is scrolled past it, and for a bar too short for its name.
  ///
  /// Every such bar gets its bubble (2026-10-04, Tom: "it needs a name too").
  /// The bubble tries the right of the bar, then its left, then above it,
  /// then below it, and takes the first place that is on screen and covers no
  /// other stay's text: its name and icon line, its end time and status
  /// circle, or another bubble. A plain stretch of another bar may be
  /// covered. With no such place for the whole name it shrinks beside the
  /// bar; failing that it takes the place that covers least.
  Widget _edgeBubbles(
    List<_Spot> spots,
    double viewW,
    double gridW,
    double gridH,
  ) {
    if (!_hBody.hasClients || _hBody.positions.length != 1) {
      return const SizedBox.shrink();
    }
    final from = _hBody.offset, to = from + viewW;
    // The whole name: the bubble may take most of the screen's width; only
    // a name longer than that is drawn smaller (never cut).
    final maxW = math.max(120.0, viewW - 40), gap = 3.0;
    final bodyH = CalEdgeBubble.heightFor(context);
    // Text a bubble must keep off, in grid pixels.
    final blocked = <Rect>[];
    final wanted =
        <
          ({
            _Spot s,
            bool sliver,
            bool cutLeft,
            double visLeft,
            double visRight,
            String? end,
          })
        >[];
    for (final s in spots) {
      final visLeft = math.max(s.left, from), visRight = math.min(s.right, to);
      final visible = visRight - visLeft;
      if (visible <= 0) continue;
      final tile = CalBarTile(
        bar: s.bar,
        roomNumber: s.room.number,
        from: s.left - 1,
        to: s.right + 1,
        x: (t) => _x(t, _lastDayW),
        onTap: () {},
      );
      final zones = tile.textZones(context, visible);
      final top = s.top, bottom = s.top + s.height;
      if (zones.label > 0) {
        blocked.add(
          Rect.fromLTRB(
            visLeft,
            top,
            math.min(visRight, visLeft + zones.label),
            bottom,
          ),
        );
      }
      blocked.add(
        Rect.fromLTRB(
          math.max(visLeft, visRight - zones.foot),
          top,
          visRight,
          bottom,
        ),
      );
      final cutLeft = s.left < from, cutRight = s.right > to;
      final sliver = visible < 24 && (cutLeft || cutRight);
      // A name that fits in the bar needs no bubble (never "…").
      if (!sliver && tile.nameFits(context, visible)) continue;
      // The end label the bar cannot show goes in the bubble after the name
      // (2026-10-04, Tom: "where is the end time"): a short stay's when its
      // end is on screen, a lease's always.
      final end = s.bar.type == 'lease' || !cutRight ? tile.endLabel : null;
      wanted.add((
        s: s,
        sliver: sliver,
        cutLeft: cutLeft,
        visLeft: visLeft,
        visRight: visRight,
        end: tile.showsEnd(context, visible) ? null : end,
      ));
    }
    // Slivers first: their bubble is the only way left to reach that bar.
    wanted.sort((x, y) {
      if (x.sliver != y.sliver) return x.sliver ? -1 : 1;
      return x.visLeft.compareTo(y.visLeft);
    });

    double cover(Rect r) {
      var sum = 0.0;
      for (final b in blocked) {
        final i = r.intersect(b);
        if (i.width > 0.5 && i.height > 0.5) sum += i.width * i.height;
      }
      return sum;
    }

    bool onScreen(Rect r) =>
        r.left >= from - 0.5 &&
        r.right <= to + 0.5 &&
        r.top >= -0.5 &&
        r.bottom <= gridH + 0.5;

    final bubbles = <Widget>[];
    for (final w in wanted) {
      final s = w.s;
      final need = math.min(
        maxW,
        CalEdgeBubble.widthFor(context, s.bar, end: w.end, status: w.sliver),
      );
      final cy = s.top + s.height / 2;
      final cx = (w.visLeft + w.visRight) / 2;
      Rect beside(AxisDirection d, double width) => d == AxisDirection.left
          ? Rect.fromLTWH(w.visRight + gap, cy - bodyH / 2, width, bodyH)
          : Rect.fromLTWH(
              w.visLeft - gap - width,
              cy - bodyH / 2,
              width,
              bodyH,
            );
      Rect upDown(AxisDirection d) {
        final h = bodyH + CalEdgeBubble.tip;
        final x = (cx - need / 2)
            .clamp(from + 2, math.max(from + 2, to - need - 2))
            .toDouble();
        return d == AxisDirection.down
            ? Rect.fromLTWH(x, s.top - gap - h, need, h)
            : Rect.fromLTWH(x, s.top + s.height + gap, need, h);
      }

      // Free width beside the bar, up to the first text in the way.
      double room(AxisDirection d) {
        final band = beside(d, 1);
        var edge = d == AxisDirection.left ? to : from;
        for (final b in blocked) {
          if (b.top >= band.bottom || b.bottom <= band.top) continue;
          if (d == AxisDirection.left) {
            if (b.right > w.visRight + 0.5 && b.left < edge) {
              edge = math.max(b.left, w.visRight);
            }
          } else if (b.left < w.visLeft - 0.5 && b.right > edge) {
            edge = math.min(b.right, w.visLeft);
          }
        }
        return d == AxisDirection.left
            ? edge - w.visRight - 2 * gap
            : w.visLeft - edge - 2 * gap;
      }

      // The tip points towards the bar: a bubble on the bar's right points
      // left, one above it points down.
      final sides = w.sliver
          ? [w.cutLeft ? AxisDirection.left : AxisDirection.right]
          : [AxisDirection.left, AxisDirection.right];
      final options = <(AxisDirection, Rect)>[
        for (final d in sides) (d, beside(d, need)),
        (AxisDirection.down, upDown(AxisDirection.down)),
        (AxisDirection.up, upDown(AxisDirection.up)),
      ];
      (AxisDirection, Rect)? pick;
      for (final o in options) {
        if (onScreen(o.$2) && cover(o.$2) == 0) {
          pick = o;
          break;
        }
      }
      if (pick == null) {
        // Shrunk beside the bar, in the wider free space.
        AxisDirection? best;
        var bestW = CalEdgeBubble.minWidth;
        for (final d in sides) {
          final r = room(d);
          if (r >= bestW) {
            best = d;
            bestW = r;
          }
        }
        if (best != null) pick = (best, beside(best, math.min(need, bestW)));
      }
      if (pick == null) {
        // Nowhere free: the place that covers least (a sliver keeps its side).
        final onIt = options.where((o) => onScreen(o.$2)).toList();
        final list = w.sliver || onIt.isEmpty ? [options.first] : onIt;
        pick = list.reduce((a, b) => cover(b.$2) < cover(a.$2) ? b : a);
      }
      final (dir, rect) = pick;
      blocked.add(rect);
      bubbles.add(
        Positioned.fromRect(
          rect: rect,
          child: Align(
            alignment: switch (dir) {
              AxisDirection.left => Alignment.centerLeft,
              AxisDirection.right => Alignment.centerRight,
              AxisDirection.down => Alignment.bottomLeft,
              AxisDirection.up => Alignment.topLeft,
            },
            child: CalEdgeBubble(
              key: ValueKey('calendar-bubble-${s.bar.id}'),
              bar: s.bar,
              pointer: dir,
              end: w.end,
              // The bar shows its own circle unless only a sliver is left.
              status: w.sliver,
              tipAt: (cx - rect.left)
                  .clamp(8.0, math.max(8.0, rect.width - 8))
                  .toDouble(),
              onTap: () => _openBar(s.p, s.room, s.bar),
            ),
          ),
        ),
      );
    }
    // Slivers' bubbles last, so they are on top.
    return Stack(clipBehavior: Clip.none, children: bubbles.reversed.toList());
  }

  double _x(DateTime t, double dayW) =>
      t.difference(_month).inMinutes / 1440 * dayW;

  Widget _dayCell(
    BuildContext context,
    DateTime day,
    List<String> weekdays,
    double dayW,
    double h,
    bool today,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final weekend = day.weekday >= DateTime.saturday;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: today
          ? scheme.onPrimary
          : (weekend ? scheme.primary : scheme.onSurfaceVariant),
      fontWeight: today ? FontWeight.w700 : FontWeight.w500,
      height: 1.1,
    );
    return Container(
      key: ValueKey(
        today ? 'calendar-today-column' : 'calendar-day-${calYmd(day)}',
      ),
      width: dayW,
      height: h,
      decoration: BoxDecoration(
        // No column is shaded (2026-10-04, Tom): not weekends, not today;
        // today is marked by its date pill and the red now line.
        border: Border(
          right: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: today
                    ? BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      )
                    : null,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    // The first of a month also names the month (several are loaded).
                    day.day == 1
                        ? '${weekdays[day.weekday - 1]}, 1/${day.month}'
                        : '${weekdays[day.weekday - 1]}, ${day.day}',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: style,
                  ),
                ),
              ),
            ),
          ),
          // The day's 24 hours (2026-10-04, Tom): a small ruler with a tick
          // for every hour, longer ticks and numbers at 6, 12 and 18 (the
          // light lines across the rows sit at those hours too).
          SizedBox(
            height: 15,
            width: dayW,
            child: CustomPaint(
              painter: _HourRulerPainter(
                scheme.onSurfaceVariant.withValues(alpha: 0.75),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final hour in calHourMarks(dayW))
                    Positioned(
                      left: dayW * hour / 24 - 10,
                      width: 20,
                      top: 0,
                      height: 9,
                      child: Center(
                        child: Text(
                          '$hour',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 8.5,
                            height: 1,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.75,
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
    );
  }

  /// The room column's width: the longest room name (one line up to 8
  /// characters, else two smaller lines), its problem icon and padding;
  /// 44–110 px (wide) or 44–80 px (phone).
  double _roomColumnWidth(
    BuildContext context,
    List<(CalProperty, CalRoom?)> rooms,
    bool wide,
  ) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final max = (wide ? 110.0 : 80.0) * math.min(scaler.scale(1), 1.3);
    var need = 0.0;
    for (final (_, room) in rooms) {
      if (room == null) continue;
      final long = room.number.length > 8;
      final style = long
          ? theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)
          : theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
      final tp = TextPainter(
        text: TextSpan(text: room.number, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      var w = tp.width + 16 + 1;
      tp.dispose();
      if (room.problems.isNotEmpty || room.blocked) w += 18;
      if (room.needsCleaning) w += 18;
      need = math.max(need, w);
    }
    return need.clamp(44.0, max).ceilToDouble();
  }

  Widget _roomLabel(BuildContext context, CalProperty p, CalRoom? room) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bad = wsToneColor(context, WsTone.bad);
    final hasProblem =
        room != null && (room.problems.isNotEmpty || room.blocked);
    final content = room == null
        ? const SizedBox.shrink()
        : Row(
            children: [
              Flexible(
                child: Text(
                  room.number,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // Long room names get two smaller lines.
                  style: room.number.length > 8
                      ? theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        )
                      : theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                ),
              ),
              if (hasProblem) ...[
                const SizedBox(width: 3),
                Icon(Icons.build_circle, size: 15, color: bad),
              ],
              // A guest left and the room is not cleaned yet (2026-10-05).
              if (room.needsCleaning) ...[
                const SizedBox(width: 3),
                Icon(
                  Icons.cleaning_services,
                  key: ValueKey('calendar-room-dirty-${room.id}'),
                  size: 15,
                  color: calKindColor(context, null, kind: 'cleaning'),
                ),
              ],
            ],
          );
    return Container(
      decoration: BoxDecoration(
        color: hasProblem ? bad.withValues(alpha: 0.06) : scheme.surface,
        border: Border(
          right: BorderSide(color: scheme.outlineVariant),
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: room == null
          ? null
          : Tooltip(
              message: [
                calText(context, 'room').replaceAll('{n}', room.number),
                if (room.problems.isNotEmpty)
                  calText(
                    context,
                    'openProblems',
                  ).replaceAll('{n}', '${room.problems.length}'),
                if (room.blocked) calText(context, 'roomBlocked'),
                if (room.needsCleaning) calText(context, 'needsCleaning'),
              ].join('\n'),
              child: InkWell(
                key: ValueKey('calendar-room-${room.id}'),
                onTap: () => _canManageRooms(p)
                    ? _openRoomPage(p, room)
                    : _openRoom(p, room),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: content,
                  ),
                ),
              ),
            ),
    );
  }

  // ---- Actions ----

  void _say(String key) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(c(key))));
  }

  Future<void> _page(
    String title,
    Widget Function(VoidCallback close) build, {
    List<Widget> Function(VoidCallback close)? actions,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (_) =>
          CalendarPageDialog(title: title, build: build, actions: actions),
    );
    _dialogs.add(route);
    await navigator.push(route);
    _dialogs.remove(route);
    if (mounted) _load();
  }

  /// Pages open over the calendar right now (closed when the calendar goes away).
  final Set<Route<void>> _dialogs = {};

  bool _canManageRooms(CalProperty p) =>
      widget.access?.allows(TeamPermission.manageProperty, buildingId: p.id) ==
      true;

  /// The building's pages this person may open (same rules as the old
  /// Settings and Rooms pages).
  List<(String, String, Widget Function(VoidCallback close))> _buildingPages(
    CalProperty p,
  ) {
    final a = widget.access;
    if (a == null) return const [];
    bool can(TeamPermission x) => a.allows(x, buildingId: p.id);
    final vi = AppTranslations.of(context).locale.languageCode == 'vi';
    final manage = can(TeamPermission.manageProperty);
    return [
      if (manage)
        (
          'property',
          // Short chip names (2026-10-05, Tom).
          vi ? 'Thông tin' : 'Details',
          (close) => PropertyDetailsScreen(
            organizationId: widget.organizationId,
            buildingId: p.id,
            service: widget.service,
            create: false,
            canDelete:
                a.allows(TeamPermission.deleteBuildings, buildingId: p.id),
            onBack: close,
          ),
        ),
      if (manage && can(TeamPermission.manageLease))
        (
          'contract',
          vi ? 'Hợp đồng thuê' : 'Lease',
          (close) => PropertyContractScreen(
            organizationId: widget.organizationId,
            buildingId: p.id,
            service: widget.service,
          ),
        ),
      if (manage)
        (
          'layout',
          vi ? 'Mặc định tòa nhà' : 'Building defaults',
          (close) => PropertyLayoutScreen(
            organizationId: widget.organizationId,
            buildingId: p.id,
            service: widget.service,
          ),
        ),
      if (manage &&
          (can(TeamPermission.manageLease) ||
              can(TeamPermission.readFinancialReports)))
        (
          'fees',
          vi ? 'Phí dịch vụ' : 'Service fees',
          (close) => ServiceFeesScreen(
            organizationId: widget.organizationId,
            buildingId: p.id,
            service: widget.service,
          ),
        ),
    ];
  }

  void _openBuilding(CalProperty p, {String? initial}) {
    final pages = _buildingPages(p);
    if (pages.isEmpty) return;
    _page(
      p.name,
      (close) =>
          CalendarBuildingPages(pages: pages, close: close, initial: initial),
    );
  }

  Future<void> _newBuilding() async {
    final id = const Uuid().v4();
    var created = false;
    await _page(
      c('newBuilding'),
      (close) => PropertyDetailsScreen(
        organizationId: widget.organizationId,
        buildingId: id,
        service: widget.service,
        create: true,
        onBack: close,
        // Created: close the dialog and show the new building.
        onCreated: () {
          created = true;
          close();
        },
      ),
    );
    if (mounted && created) setState(() => _property = id);
  }

  void _newRoom(CalProperty p) {
    _page(
      '${p.name} · ${c('newRoom')}',
      (close) => RoomDirectory(
        organizationId: widget.organizationId,
        buildingId: p.id,
        service: widget.service,
        startCreate: true,
        // Created: close the dialog; the calendar reloads with the new room.
        onCreated: close,
      ),
    );
  }

  void _openRoomPage(CalProperty p, CalRoom room) {
    // Read now: the dialog rebuilds on its own and must not reach back into
    // the calendar's context (it may be gone by then).
    final problemsLabel = c('problems');
    // The room's fees page links to the building's fees (2026-10-05, Tom).
    final buildingFees = _buildingPages(p).any((x) => x.$1 == 'fees');
    _page(
      '${p.name} · ${_roomTitle(room)}',
      (close) => RoomDirectory(
        organizationId: widget.organizationId,
        buildingId: p.id,
        service: widget.service,
        onlyRoomId: room.id,
        canDelete:
            widget.access?.allows(TeamPermission.deleteRooms, buildingId: p.id) == true,
        onBuildingFees: buildingFees
            ? () {
                close();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _openBuilding(p, initial: 'fees');
                });
              }
            : null,
      ),
      actions: p.canReadProblems
          ? (close) => [
              TextButton.icon(
                key: const ValueKey('calendar-room-dialog-problems'),
                onPressed: () {
                  close();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _problems(p, room);
                  });
                },
                icon: const Icon(Icons.build_outlined, size: 18),
                label: Text(problemsLabel),
              ),
            ]
          : null,
    );
  }

  String _roomTitle(CalRoom room, [String? more]) {
    final r = c('room').replaceAll('{n}', room.number);
    return more == null || more.isEmpty ? r : '$r · $more';
  }

  void _openBar(CalProperty p, CalRoom room, CalBar b) {
    if (!b.canOpen || b.recordId == null) {
      _say('cantOpen');
      return;
    }
    // A cleaning opens the building's cleaning list (start / done there).
    if (b.type == 'cleaning') {
      _cleaning(p);
      return;
    }
    if (b.type == 'booking') {
      _page(
        _roomTitle(room, b.name),
        (close) => BookingWorkspaceScreen(
          organizationId: widget.organizationId,
          buildingId: p.id,
          accountId: widget.accountId,
          service: widget.service,
          initialRecordId: b.recordId,
          onClose: close,
        ),
      );
    } else {
      _page(
        _roomTitle(room, b.name),
        (close) => TenantContactsScreen(
          organizationId: widget.organizationId,
          buildingId: p.id,
          service: widget.service,
          initialRecordId: b.recordId,
          onClose: close,
        ),
      );
    }
  }

  void _newShort(CalProperty p, CalRoom room, DateTime day) {
    final next = day.add(const Duration(days: 1));
    _page(
      _roomTitle(room, c('newShort')),
      (close) => BookingWorkspaceScreen(
        organizationId: widget.organizationId,
        buildingId: p.id,
        accountId: widget.accountId,
        service: widget.service,
        onClose: close,
        startNew: true,
        initialRoomId: room.id,
        initialStart: '${calYmd(day)} 14:00',
        initialEnd: '${calYmd(next)} 12:00',
      ),
    );
  }

  /// "Đặt phòng" (2026-10-04): short stay or lease, for any room of the building.
  Future<void> _newStay(CalProperty p, {DateTime? on}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                '${p.name} · ${c('newStay')}',
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            if (p.canCreateBookings)
              ListTile(
                key: const ValueKey('calendar-stay-short'),
                leading: const Icon(Icons.nights_stay_outlined),
                title: Text(c('newShort')),
                onTap: () => Navigator.pop(sheet, 'short'),
              ),
            if (p.canLease)
              ListTile(
                key: const ValueKey('calendar-stay-long'),
                leading: const Icon(Icons.home_work_outlined),
                title: Text(c('newLong')),
                onTap: () => Navigator.pop(sheet, 'long'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final today = on ?? p.today ?? DateTime.now();
    final day = DateTime.utc(today.year, today.month, today.day);
    final next = day.add(const Duration(days: 1));
    if (choice == 'short') {
      _page(
        '${p.name} · ${c('newShort')}',
        (close) => BookingWorkspaceScreen(
          organizationId: widget.organizationId,
          buildingId: p.id,
          accountId: widget.accountId,
          service: widget.service,
          onClose: close,
          startNew: true,
          // Any room: the form lists them all.
          initialStart: '${calYmd(day)} 14:00',
          initialEnd: '${calYmd(next)} 12:00',
        ),
      );
    } else {
      _page(
        '${p.name} · ${c('newLong')}',
        (close) => TenantLeaseScreen(
          organizationId: widget.organizationId,
          buildingId: p.id,
          service: widget.service,
          onBack: close,
          initialMoveIn: calYmd(day),
        ),
      );
    }
  }

  void _newLong(CalProperty p, CalRoom room, DateTime day) {
    _page(
      _roomTitle(room, c('newLong')),
      (close) => TenantLeaseScreen(
        organizationId: widget.organizationId,
        buildingId: p.id,
        service: widget.service,
        onBack: close,
        initialRoomId: room.id,
        initialMoveIn: calYmd(day),
      ),
    );
  }

  /// All rooms' problems of the building, with "Báo sự cố" there.
  void _buildingProblems(CalProperty p) {
    _page(
      '${p.name} · ${c('problems')}',
      (close) => TechnicalProblemsScreen(
        organizationId: widget.organizationId,
        buildingId: p.id,
        service: widget.service,
        onClose: close,
      ),
    );
  }

  /// Housekeeping tasks of the building (2026-10-05, Tom: "Dọn phòng").
  void _cleaning(CalProperty p, {String? roomId, String? start, String? end}) {
    _page(
      '${p.name} · ${c('cleaning')}',
      (close) => HousekeepingScreen(
        organizationId: widget.organizationId,
        buildingId: p.id,
        service: widget.service,
        initialRoomId: roomId,
        initialStart: start,
        initialEnd: end,
      ),
    );
  }

  void _problems(CalProperty p, CalRoom room, {bool report = false}) {
    _page(
      _roomTitle(room, c('problems')),
      (close) => TechnicalProblemsScreen(
        organizationId: widget.organizationId,
        buildingId: p.id,
        service: widget.service,
        reportRoomId: report ? room.id : null,
        onClose: close,
      ),
    );
  }

  Future<void> _openCell(CalProperty p, CalRoom room, DateTime day) async {
    if (p.needsTimeZone) {
      _say('needsTimeZone');
      return;
    }
    final canShort = room.shortStay && p.canCreateBookings;
    final canLong = room.monthly && p.canLease;
    if (!canShort && !canLong && !p.canReportProblems && !p.canAssignCleaning) {
      _say('noAction');
      return;
    }
    final vi = AppTranslations.of(context).locale.languageCode == 'vi';
    final weekdays = vi
        ? const [
            'Thứ 2',
            'Thứ 3',
            'Thứ 4',
            'Thứ 5',
            'Thứ 6',
            'Thứ 7',
            'Chủ nhật',
          ]
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final when =
        '${weekdays[day.weekday - 1]} ${_two(day.day)}/${_two(day.month)}';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                '${_roomTitle(room)} · $when',
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            if (room.blocked)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: WsNotice(c('roomBlocked'), tone: WsTone.warning),
              ),
            if (canShort)
              ListTile(
                key: const ValueKey('calendar-new-short'),
                enabled: !room.blocked,
                leading: const Icon(Icons.nights_stay_outlined),
                title: Text(c('newShort')),
                onTap: () => Navigator.pop(sheet, 'short'),
              ),
            if (canLong)
              ListTile(
                key: const ValueKey('calendar-new-long'),
                enabled: !room.blocked,
                leading: const Icon(Icons.home_work_outlined),
                title: Text(c('newLong')),
                onTap: () => Navigator.pop(sheet, 'long'),
              ),
            if (p.canReportProblems)
              ListTile(
                key: const ValueKey('calendar-report'),
                leading: const Icon(Icons.build_outlined),
                title: Text(c('report')),
                onTap: () => Navigator.pop(sheet, 'report'),
              ),
            // Assign a cleaning for that day, 12:00–14:00 (between check-out
            // and check-in) to start with (2026-10-05, Tom).
            if (p.canAssignCleaning)
              ListTile(
                key: const ValueKey('calendar-new-cleaning'),
                leading: const Icon(Icons.cleaning_services_outlined),
                title: Text(c('assignCleaning')),
                onTap: () => Navigator.pop(sheet, 'clean'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'short':
        _newShort(p, room, day);
      case 'long':
        _newLong(p, room, day);
      case 'report':
        _problems(p, room, report: true);
      case 'clean':
        _cleaning(
          p,
          roomId: room.id,
          start: '${calYmd(day)} 12:00',
          end: '${calYmd(day)} 14:00',
        );
    }
  }

  Future<void> _openRoom(CalProperty p, CalRoom room) async {
    if (!p.canReadProblems) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                '${_roomTitle(room)} · ${p.name}',
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            if (room.blocked)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: WsNotice(c('roomBlocked'), tone: WsTone.warning),
              ),
            for (final t in room.problems)
              ListTile(
                leading: Icon(
                  Icons.build_circle_outlined,
                  color: wsToneColor(sheet, WsTone.bad),
                ),
                title: Text(t),
                onTap: () => Navigator.pop(sheet, 'list'),
              ),
            ListTile(
              key: const ValueKey('calendar-room-problems'),
              leading: const Icon(Icons.list_alt_outlined),
              title: Text(c('seeProblems')),
              onTap: () => Navigator.pop(sheet, 'list'),
            ),
            if (p.canReportProblems)
              ListTile(
                leading: const Icon(Icons.build_outlined),
                title: Text(c('report')),
                onTap: () => Navigator.pop(sheet, 'report'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    _problems(p, room, report: choice == 'report');
  }

  void _showLegend(BuildContext context) {
    Widget swatch(Color color, String label, {bool solid = true}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 14,
            decoration: BoxDecoration(
              color: color.withValues(
                alpha: solid ? calPaidAlpha : calDueAlpha,
              ),
              border: Border.all(color: color),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
    Widget circle(String status, String label) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Center(
              child: Container(
                width: 11,
                height: 11,
                decoration: calStatusDecoration(status),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
    Widget icon(IconData i, String label, [Color? color]) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 26, child: Icon(i, size: 16, color: color)),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
    final head = Theme.of(context).textTheme.labelLarge;
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(c('legend')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c('colours'), style: head),
              swatch(calKindColor(d, null, kind: 'short'), c('shortStay')),
              swatch(calKindColor(d, null, kind: 'long'), c('longStay')),
              // 2026-10-05: cleaning; solid = the work done so far.
              swatch(calKindColor(d, null, kind: 'cleaning'), c('cleaning')),
              const SizedBox(height: 4),
              Text(c('paidPart'), style: Theme.of(d).textTheme.bodySmall),
              Text(c('periodLine'), style: Theme.of(d).textTheme.bodySmall),
              const SizedBox(height: 12),
              // 2026-10-04: the status is a circle at the end of the bar.
              Text(c('circles'), style: head),
              for (final status in ['deposited', 'upcoming', 'staying', 'out'])
                circle(status, c(status)),
              const SizedBox(height: 12),
              Text(c('cleanCircles'), style: head),
              for (final status in ['cleanTodo', 'cleanDoing', 'cleanDone'])
                circle(status, c(status)),
              const SizedBox(height: 12),
              Text(c('icons'), style: head),
              icon(
                Icons.build_circle,
                c('problem'),
                wsToneColor(d, WsTone.bad),
              ),
              icon(
                Icons.cleaning_services,
                c('needsCleaning'),
                calKindColor(d, null, kind: 'cleaning'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(c('close')),
          ),
        ],
      ),
    );
  }
}

/// A bar's place in the grid, for the name bubbles.
typedef _Spot = ({
  CalProperty p,
  CalRoom room,
  CalBar bar,
  double left,
  double right,
  double top,
  double height,
});

/// One stay, drawn down its room's column.
class CalBarTile extends StatelessWidget {
  final CalBar bar;
  final String roomNumber;

  /// Left and right edges of the bar in the grid (pixels).
  final double from, to;
  final double Function(DateTime) x;
  final VoidCallback onTap;

  /// The grid's sideways scroll and the width on screen; without them the
  /// whole bar is taken as visible.
  final ScrollController? scroll;
  final double? viewWidth;
  const CalBarTile({
    super.key,
    required this.bar,
    required this.roomNumber,
    required this.from,
    required this.to,
    required this.x,
    required this.onTap,
    this.scroll,
    this.viewWidth,
  });

  /// The visible part of the bar, in the bar's own pixels: (left, right).
  (double, double) _visible(double w) {
    final c = scroll, view = viewWidth;
    if (c == null || view == null || !c.hasClients || c.positions.length != 1) {
      return (0, w);
    }
    final left = (c.offset - from - 1).clamp(0.0, w);
    final right = (c.offset + view - from - 1).clamp(0.0, w);
    return right - left < 24 ? (0, w) : (left, right);
  }

  String _short(DateTime d) => '${_two(d.day)}/${_two(d.month)}';
  String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  /// Share of the bar (from its left end) that is paid.
  double _paidStop() {
    final width = to - from;
    if (width <= 0 || bar.anonymous) return 0;
    if ((bar.type == 'booking' || bar.type == 'cleaning') &&
        bar.pay == 'paid') {
      return 1;
    }
    final until = bar.paidUntil;
    if (until == null) return 0;
    return ((x(until) - from) / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = calKindColor(context, bar);
    final stop = _paidStop();
    final solid = color.withValues(alpha: calPaidAlpha),
        tint = color.withValues(alpha: calDueAlpha);
    final ink = theme.brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF16202C);
    final name = calBarName(context, bar);

    // Period starts inside a lease bar (paid ahead per period).
    final ticks = <double>[];
    if (bar.type == 'lease' && !bar.anonymous) {
      for (var k = 1; k < 400; k++) {
        // Same day of the month, or the month's last day (like the server).
        final month = bar.start.month + k * bar.periodMonths;
        final last = DateTime.utc(bar.start.year, month + 1, 0).day;
        final d = DateTime.utc(
          bar.start.year,
          month,
          math.min(bar.start.day, last),
          12,
        );
        final at = x(d) - from;
        if (at >= to - from) break;
        if (at > 2) ticks.add(at);
      }
    }

    final cleaning = bar.type == 'cleaning';
    final tooltip = cleaning
        ? calCleaningInfo(context, bar, roomNumber)
        : [
            calText(context, 'room').replaceAll('{n}', roomNumber),
            name,
            _range(context),
            calText(context, calStayStatus(bar)),
            if (!bar.anonymous && bar.pay != null) calText(context, bar.pay!),
            if (!bar.anonymous && bar.paidUntil != null && bar.pay != 'paid')
              calText(
                context,
                'paidUntil',
              ).replaceAll('{d}', _short(bar.paidUntil!)),
            if (!bar.anonymous && bar.paidUntil == null && bar.pay == 'due')
              calText(context, 'nothingPaid'),
            if (bar.roommates > 0)
              calText(
                context,
                'roommates',
              ).replaceAll('{n}', '${bar.roommates}'),
            if (bar.staffName != null)
              calText(context, 'staff').replaceAll('{n}', bar.staffName!),
            if (bar.problem) calText(context, 'problem'),
          ].join('\n');

    return Semantics(
      button: true,
      label: tooltip.replaceAll('\n', ', '),
      excludeSemantics: true,
      // The details appear next to the mouse (or the finger, on a long press),
      // not under the middle of a long bar (2026-10-04, Tom).
      child: CalHoverInfo(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          // Rounder, like the month view's pills (2026-10-05, Tom).
          borderRadius: BorderRadius.circular(calBarRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(calBarRadius),
                border: Border.all(
                  color: color.withValues(alpha: bar.anonymous ? 0.5 : 0.9),
                ),
                gradient: LinearGradient(
                  colors: [solid, solid, tint, tint],
                  stops: [0, stop, stop, 1],
                ),
              ),
              child: CustomPaint(
                painter: ticks.isEmpty ? null : _TickPainter(ticks, color),
                child: LayoutBuilder(
                  builder: (context, box) => scroll == null
                      ? _content(context, box, name, ink)
                      : ListenableBuilder(
                          listenable: scroll!,
                          builder: (context, _) =>
                              _content(context, box, name, ink),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The check-out time (a lease: its end date) shown at the bar's end.
  String _long(DateTime d) => '${_short(d)}/${d.year}';

  /// The stay's dates for the hover card; a lease's with the year, and its
  /// contract end with date and time (2026-10-04, Tom).
  String _range(BuildContext context) {
    final lease = bar.type == 'lease';
    String at(DateTime d) => '${lease ? _long(d) : _short(d)} ${_time(d)}';
    final end = bar.end, planned = bar.plannedEnd;
    final tail = end != null
        ? at(end)
        : planned != null
        ? calText(context, 'contractEnd').replaceAll('{d}', at(planned))
        : calText(context, 'openEnded');
    return '${at(bar.start)} – $tail';
  }

  /// What the bar's right end says: a short stay its check-out time; a lease
  /// its end date and time (2026-10-04, Tom), "HĐ" for the contract's planned
  /// end while the tenant is still there.
  String? get _foot {
    final end = bar.end;
    if ((bar.type == 'booking' || bar.type == 'cleaning') && end != null) {
      return _time(end);
    }
    if (bar.type == 'lease') {
      if (end != null) return '${_long(end)} ${_time(end)}';
      final planned = bar.plannedEnd;
      if (planned != null) return 'HĐ ${_long(planned)} ${_time(planned)}';
    }
    return null;
  }

  /// A short stay's end is labelled only where the bar really ends on screen.
  /// A lease runs for months, so its end date is shown at the right end of
  /// what is on screen (2026-10-04, Tom).
  bool get _endsHere {
    if (bar.type == 'lease') return true;
    final end = bar.end;
    return end == null
        ? (bar.plannedEnd != null && x(bar.plannedEnd!) <= to + 0.5)
        : x(end) <= to + 0.5;
  }

  /// Where the name starts inside the bar (clear of the round corner).
  static const _textLeft = 8.0;

  static const _footStyle = TextStyle(
    fontSize: 10,
    height: 1.15,
    fontWeight: FontWeight.w600,
  );

  /// The end label's width, measured.
  double _footTextWidth(BuildContext context, String foot) => (TextPainter(
    text: TextSpan(text: foot, style: _footStyle),
    maxLines: 1,
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
  )..layout()).width;

  /// Room for the end label and the status circle at the right end; 12 px
  /// (the circle) when the label is not shown.
  double _footWidth(BuildContext context, double w) {
    final foot = _foot;
    if (foot == null || !_endsHere) return 12.0;
    final need = _footTextWidth(context, foot) + 4 + 3 + 10 + 2;
    return w >= math.max(70.0, need + 24) ? need : 12.0;
  }

  /// Does the bar itself show its end label with [w] px on screen? Only next
  /// to the whole name; otherwise the name bubble carries it.
  bool showsEnd(BuildContext context, double w) {
    final foot = _foot;
    if (foot == null || !_endsHere) return false;
    final fw = _footWidth(context, w);
    return fw > 12 && _nameWidth(context) <= w - 14 - fw;
  }

  /// The end label when the end belongs on screen (see [_endsHere]).
  String? get endLabel => _endsHere ? _foot : null;

  static const _nameStyle = TextStyle(
    fontSize: 11.5,
    height: 1.15,
    fontWeight: FontWeight.w700,
  );

  String _name(BuildContext context) => calBarName(context, bar);

  double _nameWidth(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: _name(context), style: _nameStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width + (bar.type == 'lease' ? 4 : 0);
  }

  /// Does the whole name fit in [w] px of the bar, next to the status circle?
  /// When it does not, the calendar shows it in a bubble beside the bar
  /// instead of cutting it with "…" (2026-10-04, Tom). The end time gives way
  /// to the name first.
  bool nameFits(BuildContext context, double w) =>
      w >= 30 && _nameWidth(context) <= w - 26;

  /// Where the bar's own text sits when [w] px of it are on screen: the
  /// name and icon line from the visible left end ([label] px, 0 for none)
  /// and the end time and status circle at the visible right end ([foot]
  /// px). Name bubbles keep off both (2026-10-04, Tom). A little wide on
  /// purpose: covering a bar's plain stretch is fine, its text is not.
  ({double label, double foot}) textZones(BuildContext context, double w) {
    final scaler = MediaQuery.textScalerOf(context);
    double text(String t) => (TextPainter(
      text: TextSpan(
        text: t,
        style: const TextStyle(
          fontSize: 10,
          height: 1.15,
          fontWeight: FontWeight.w600,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout()).width;
    final name = nameFits(context, w) ? _nameWidth(context) : 0.0;
    // One line (2026-10-05, Tom): the name, then the problem icon and "+N".
    var icons = 0.0;
    if (bar.problem) icons += 16;
    if (bar.roommates > 0) icons += text('+${bar.roommates}') + 4;
    final label = name + icons;
    return (
      label: label == 0 ? 0.0 : math.min(w, label + _textLeft + 4),
      foot: math.min(w, _footWidth(context, w) + 8),
    );
  }

  Widget _content(
    BuildContext context,
    BoxConstraints box,
    String name,
    Color ink,
  ) {
    final full = box.maxWidth;
    // Text and the status sit in the part of the bar that is on screen.
    final (visLeft, visRight) = _visible(full);
    final w = visRight - visLeft, rightGap = full - visRight;
    // Full-strength ink: the icon line sits on the bar's strong colour.
    final small = TextStyle(
      fontSize: 10,
      height: 1.15,
      color: ink,
      fontWeight: FontWeight.w600,
    );
    final nameStyle = _nameStyle.copyWith(color: ink);
    // At the right end (2026-10-04, Tom): the check-out time (a lease: its end
    // date), then the status as a circle only.
    final foot = _foot;
    // The end label only when the name still fits beside it; otherwise the
    // name bubble carries both.
    final fullFoot = _footWidth(context, w);
    final showFoot =
        foot != null &&
        fullFoot > 12 &&
        (scroll == null || _nameWidth(context) <= w - 14 - fullFoot);
    final status = calStayStatus(bar);
    final circle = Container(
      key: const ValueKey('calendar-bar-status'),
      width: 10,
      height: 10,
      decoration: calStatusDecoration(status),
    );
    final footWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showFoot) ...[
          // No box behind it (2026-10-05, Tom): the paid part shows through.
          Text(
            foot,
            key: const ValueKey('calendar-bar-end'),
            maxLines: 1,
            style: small.copyWith(color: ink),
          ),
          const SizedBox(width: 3),
        ],
        circle,
      ],
    );
    final footWidth = showFoot ? fullFoot : 12.0;
    // No phone icon (2026-10-05, Tom: not needed on the calendar).
    final icons = <Widget>[
      if (bar.problem)
        Icon(
          Icons.build_circle,
          size: 12,
          color: wsToneColor(context, WsTone.bad),
        ),
      if (bar.roommates > 0) Text('+${bar.roommates}', style: small),
    ];
    // In the calendar a name that does not fit goes into a bubble beside the
    // bar (never "…"); the bar keeps its icons and status.
    final Widget title = w < 30 || (scroll != null && !nameFits(context, w))
        ? const SizedBox.shrink()
        // No box behind the name (2026-10-05, Tom): it hid the paid part.
        : Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: nameStyle,
          );
    // One line only, like the month view (2026-10-05, Tom): the name, then
    // the icons; what does not fit is cut, never wrapped.
    // A stack so a short bar clips its text instead of overflowing.
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned(
          left: visLeft + _textLeft,
          right: rightGap + footWidth + 6,
          top: 0,
          bottom: 0,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  key: const ValueKey('calendar-bar-line'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    title,
                    for (final i in icons)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: i,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (w >= 12)
          Positioned(
            right: w < 20 ? null : rightGap + 8,
            left: w < 20 ? visLeft + 1 : null,
            top: 0,
            bottom: 0,
            child: Center(child: footWidget),
          ),
      ],
    );
  }
}

/// A small card with a bar's details beside the mouse pointer: it follows
/// the pointer over the bar and moves to the other side near screen edges.
/// On touch screens a long press shows it until the finger lifts.
class CalHoverInfo extends StatefulWidget {
  final String message;
  final Widget child;
  const CalHoverInfo({super.key, required this.message, required this.child});
  @override
  State<CalHoverInfo> createState() => _CalHoverInfoState();
}

class _CalHoverInfoState extends State<CalHoverInfo> {
  OverlayEntry? _entry;
  Offset _at = Offset.zero;
  Timer? _wait;

  void _insert() {
    if (_entry != null || !mounted) return;
    // Not over a dialog opened since (2026-10-05: a click opened a stay and
    // the card, due 350 ms later, stayed on top of it).
    if (ModalRoute.of(context)?.isCurrent == false) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: _card);
    overlay.insert(_entry!);
  }

  void _hide() {
    _wait?.cancel();
    _wait = null;
    _entry?.remove();
    _entry = null;
  }

  void _move(Offset global) {
    _at = global;
    _entry?.markNeedsBuild();
  }

  @override
  void didUpdateWidget(covariant CalHoverInfo old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message) _entry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    final box =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()
            as RenderBox?;
    final at = box == null ? _at : box.globalToLocal(_at);
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomSingleChildLayout(
          delegate: _NearPointer(at),
          child: Material(
            key: const ValueKey('calendar-hover-info'),
            elevation: 4,
            color: theme.colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Text(
                  widget.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                    height: 1.35,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    // A click opens the stay: no card.
    onPointerDown: (e) {
      if (e.kind == PointerDeviceKind.mouse) _hide();
    },
    child: MouseRegion(
      onEnter: (e) {
        _at = e.position;
        _wait?.cancel();
        _wait = Timer(const Duration(milliseconds: 350), _insert);
      },
      onHover: (e) => _move(e.position),
      onExit: (_) => _hide(),
      child: GestureDetector(
        onLongPressStart: (d) {
          _at = d.globalPosition;
          _insert();
        },
        onLongPressMoveUpdate: (d) => _move(d.globalPosition),
        onLongPressEnd: (_) => _hide(),
        onLongPressCancel: _hide,
        child: widget.child,
      ),
    ),
  );
}

/// Below and to the right of the pointer; flipped near the screen's edges.
class _NearPointer extends SingleChildLayoutDelegate {
  final Offset at;
  _NearPointer(this.at);
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) => c.loosen();
  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = at.dx + 14, y = at.dy + 18;
    if (x + child.width > size.width - 8) x = at.dx - 14 - child.width;
    if (y + child.height > size.height - 8) y = at.dy - 12 - child.height;
    return Offset(
      x.clamp(8.0, math.max(8.0, size.width - child.width - 8)),
      y.clamp(8.0, math.max(8.0, size.height - child.height - 8)),
    );
  }

  @override
  bool shouldRelayout(_NearPointer old) => old.at != at;
}

/// The bubble next to a bar that is almost off screen: a small pointer to
/// the bar, the name and the status circle. Tapping it opens the bar.
class CalEdgeBubble extends StatelessWidget {
  final CalBar bar;

  /// Which way the small tip points: towards the bar. Left: the bubble is on
  /// the bar's right; down: the bubble is above the bar.
  final AxisDirection pointer;

  /// For a tip pointing up or down: its middle, from the bubble's left.
  final double tipAt;

  /// The end label the bar is too short to show ("12:00"), after the name.
  final String? end;

  /// The status circle, only when the bar cannot show its own (a sliver at
  /// the screen edge): never twice (2026-10-04, Tom).
  final bool status;
  final VoidCallback onTap;
  const CalEdgeBubble({
    super.key,
    required this.bar,
    required this.pointer,
    this.tipAt = 12,
    this.end,
    this.status = false,
    required this.onTap,
  });

  static const _endStyle = TextStyle(
    fontSize: 10,
    height: 1.15,
    fontWeight: FontWeight.w600,
  );

  /// The tip's length.
  static const tip = 6.0;

  /// The bubble's height without the tip.
  static double heightFor(BuildContext context) {
    final painter = TextPainter(
      text: const TextSpan(text: 'Ág', style: _style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.height + 6 + 2.4;
  }

  static const _style = TextStyle(
    fontSize: 11,
    height: 1.15,
    fontWeight: FontWeight.w700,
  );

  /// The narrowest bubble still worth showing: a few letters of the name
  /// (shrunk at most to about 70%) and the status circle.
  static const minWidth = 56.0;

  /// The width the bubble needs for the whole name: pointer, border,
  /// padding, the name, the gap and the status circle.
  static double widthFor(
    BuildContext context,
    CalBar bar, {
    String? end,
    bool status = false,
  }) {
    final name = calBarName(context, bar);
    double measure(String t, TextStyle style) => (TextPainter(
      text: TextSpan(text: t, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout()).width;
    return measure(name, _style) +
        (end == null ? 0 : 5 + measure(end, _endStyle)) +
        (status ? 4 + 9 : 0) +
        6 +
        2.4 +
        12 +
        2;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = calKindColor(context, bar);
    final ink = theme.brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF16202C);
    final name = calBarName(context, bar);
    final vertical =
        pointer == AxisDirection.up || pointer == AxisDirection.down;
    final tipWidget = CustomPaint(
      size: vertical ? const Size(10, tip) : const Size(tip, 10),
      painter: _PointerPainter(color, pointer),
    );
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 1.2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                name,
                maxLines: 1,
                softWrap: false,
                style: _style.copyWith(color: ink),
              ),
            ),
          ),
          if (end != null) ...[
            const SizedBox(width: 5),
            Text(
              end!,
              key: const ValueKey('calendar-bubble-end'),
              maxLines: 1,
              softWrap: false,
              style: _endStyle.copyWith(color: ink.withValues(alpha: 0.75)),
            ),
          ],
          if (status) ...[
            const SizedBox(width: 4),
            Container(
              key: const ValueKey('calendar-bubble-status'),
              width: 9,
              height: 9,
              decoration: calStatusDecoration(calStayStatus(bar)),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: vertical
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (pointer == AxisDirection.up)
                    Padding(
                      padding: EdgeInsets.only(left: math.max(0, tipAt - 5)),
                      child: tipWidget,
                    ),
                  body,
                  if (pointer == AxisDirection.down)
                    Padding(
                      padding: EdgeInsets.only(left: math.max(0, tipAt - 5)),
                      child: tipWidget,
                    ),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: pointer == AxisDirection.left
                    ? [tipWidget, Flexible(child: body)]
                    : [Flexible(child: body), tipWidget],
              ),
      ),
    );
  }
}

class _PointerPainter extends CustomPainter {
  final Color color;

  /// The way the tip points.
  final AxisDirection to;
  _PointerPainter(this.color, this.to);
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = switch (to) {
      AxisDirection.left =>
        Path()
          ..moveTo(w, 0)
          ..lineTo(0, h / 2)
          ..lineTo(w, h),
      AxisDirection.right =>
        Path()
          ..moveTo(0, 0)
          ..lineTo(w, h / 2)
          ..lineTo(0, h),
      AxisDirection.down =>
        Path()
          ..moveTo(0, 0)
          ..lineTo(w / 2, h)
          ..lineTo(w, 0),
      AxisDirection.up =>
        Path()
          ..moveTo(0, h)
          ..lineTo(w / 2, 0)
          ..lineTo(w, h),
    };
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PointerPainter old) => old.color != color || old.to != to;
}

/// The top of the "now" line in the date header: a small triangle and line.
class _NowMarkPainter extends CustomPainter {
  final Color color;
  _NowMarkPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final mid = size.width / 2;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(mid, 6)
        ..close(),
      paint,
    );
    canvas.drawRect(Rect.fromLTWH(mid - 1, 4, 2, size.height - 4), paint);
  }

  @override
  bool shouldRepaint(_NowMarkPainter old) => old.color != color;
}

/// Pixels for one hour on the timeline (2026-10-04, Tom): a 1-hour stay is
/// as wide as the shortest bar the calendar draws.
const calHourW = 18.0;

/// The hours named under a date (and drawn as light lines across the rooms):
/// every 2 hours on very wide days, every 3 on wide days, else 6 · 12 · 18.
List<int> calHourMarks(double dayW) {
  final step = dayW >= 200 ? 2 : (dayW >= 110 ? 3 : 6);
  return [for (var h = step; h < 24; h += step) h];
}

/// A tick for every hour of a day under its date; 6, 12 and 18 are longer.
class _HourRulerPainter extends CustomPainter {
  final Color color;
  _HourRulerPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.8;
    final named = calHourMarks(size.width);
    for (var h = 1; h < 24; h++) {
      final x = size.width * h / 24;
      final long = named.contains(h);
      canvas.drawLine(
        Offset(x, size.height - (long ? 5 : 2.5)),
        Offset(x, size.height),
        paint..color = color.withValues(alpha: long ? 1 : 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_HourRulerPainter old) => old.color != color;
}

class _TickPainter extends CustomPainter {
  final List<double> ticks;
  final Color color;
  _TickPainter(this.ticks, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    // A clear divider at the start of each payment period (2026-10-04): the
    // bar's own colour, full height, with a white edge so it never reads as
    // a grid line.
    final edge = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..strokeWidth = 4.5;
    final line = Paint()
      ..color = color
      ..strokeWidth = 2.5;
    for (final t in ticks) {
      canvas.drawLine(Offset(t, 0), Offset(t, size.height), edge);
      canvas.drawLine(Offset(t, 0), Offset(t, size.height), line);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.ticks.length != ticks.length || old.color != color;
}

class _GridPainter extends CustomPainter {
  final DateTime month;
  final int days;
  final int? todayCol;
  final int pastDays;
  final double dayW;

  /// (top, height, property band, closed by a problem) per row.
  final List<(double, double, bool, bool)> rows;
  final Color line, strong, band, blockedFill, pastFill;
  _GridPainter({
    required this.month,
    required this.days,
    required this.dayW,
    required this.todayCol,
    required this.pastDays,
    required this.pastFill,
    required this.rows,
    required this.line,
    required this.strong,
    required this.band,
    required this.blockedFill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    if (pastDays > 0)
      canvas.drawRect(
        Rect.fromLTWH(0, 0, pastDays * dayW, size.height),
        fill..color = pastFill,
      );
    final from = (todayCol ?? 0) * dayW;
    final thin = Paint()
      ..color = line
      ..strokeWidth = 1;
    final bold = Paint()
      ..color = strong
      ..strokeWidth = 1;
    for (final (top, height, isBand, blocked) in rows) {
      if (isBand)
        canvas.drawRect(
          Rect.fromLTWH(0, top, size.width, height),
          fill..color = band,
        );
      // A room closed by an open problem: tinted from today on.
      if (blocked)
        canvas.drawRect(
          Rect.fromLTWH(from, top, size.width - from, height),
          fill..color = blockedFill,
        );
      canvas.drawLine(
        Offset(0, top + height - 0.5),
        Offset(size.width, top + height - 0.5),
        isBand ? bold : thin,
      );
    }
    for (var i = 1; i <= days; i++) {
      final x = i * dayW - 0.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), thin);
    }
    // Faint hour lines at the hours named in the header.
    final hours = Paint()
      ..color = line.withValues(alpha: 0.35)
      ..strokeWidth = 0.6;
    for (var i = 0; i < days; i++) {
      for (final h in calHourMarks(dayW)) {
        final x = (i + h / 24) * dayW;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), hours);
      }
    }
    // A clear line where each month starts.
    final monthLine = Paint()
      ..color = strong
      ..strokeWidth = 2;
    for (var i = 1; i < days; i++) {
      if (DateTime.utc(month.year, month.month, 1 + i).day == 1) {
        canvas.drawLine(
          Offset(i * dayW, 0),
          Offset(i * dayW, size.height),
          monthLine,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.month != month ||
      old.days != days ||
      old.dayW != dayW ||
      old.todayCol != todayCol ||
      old.pastDays != pastDays ||
      old.pastFill != pastFill ||
      old.rows.length != rows.length ||
      old.rows.join(',') != rows.join(',') ||
      old.line != line;
}

/// An organization page (booking, tenant, problems…) opened over the calendar.
/// Phones get the whole screen; wider screens a large dialog. Back inside the
/// page goes one step back; the page's own "back to the list" closes it.
class CalendarPageDialog extends StatefulWidget {
  final String title;
  final Widget Function(VoidCallback close) build;

  /// Extra buttons next to the close button.
  final List<Widget> Function(VoidCallback close)? actions;
  const CalendarPageDialog({
    super.key,
    required this.title,
    required this.build,
    this.actions,
  });
  @override
  State<CalendarPageDialog> createState() => _CalendarPageDialogState();
}

class _CalendarPageDialogState extends State<CalendarPageDialog> {
  final _steps = BackSteps();
  bool _closed = false;

  @override
  void dispose() {
    _steps.dispose();
    super.dispose();
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    // Pages report "back to the list" during their own state changes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 640;
    final page = Material(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: theme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      key: const ValueKey('calendar-dialog-title'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  ...?widget.actions?.call(_close),
                  IconButton(
                    key: const ValueKey('calendar-dialog-close'),
                    tooltip: calText(context, 'close'),
                    onPressed: _close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: DialogPageScope(child: widget.build(_close))),
        ],
      ),
    );
    final scoped = BackStepsScope(
      steps: _steps,
      child: SafeArea(child: page),
    );
    if (!wide) return Dialog.fullscreen(child: scoped);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: math.min(800, size.width - 48),
        height: size.height * 0.9,
        child: scoped,
      ),
    );
  }
}

/// A building's pages (details, whole-building contract, layout and room
/// defaults, service fees) in one dialog, with a chip per page.
class CalendarBuildingPages extends StatefulWidget {
  final List<(String, String, Widget Function(VoidCallback close))> pages;
  final VoidCallback close;

  /// The page to open first (default: the first).
  final String? initial;
  const CalendarBuildingPages({
    super.key,
    required this.pages,
    required this.close,
    this.initial,
  });
  @override
  State<CalendarBuildingPages> createState() => _CalendarBuildingPagesState();
}

class _CalendarBuildingPagesState extends State<CalendarBuildingPages> {
  late String _page = widget.initial ?? widget.pages.first.$1;

  @override
  Widget build(BuildContext context) {
    final page =
        widget.pages.where((p) => p.$1 == _page).firstOrNull ??
        widget.pages.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.pages.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in widget.pages)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        key: ValueKey('building-page-${p.$1}'),
                        label: Text(p.$2),
                        selected: p.$1 == page.$1,
                        onSelected: (_) => setState(() => _page = p.$1),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(page.$1),
            child: page.$3(widget.close),
          ),
        ),
      ],
    );
  }
}
