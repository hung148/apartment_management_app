import '../../utils/money_conversion.dart';
import '../../services/organization_money.dart';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import 'back_steps.dart';
import 'operational_widgets.dart';
import 'room_problems_section.dart';
import 'tenant_lease_screen.dart';
import 'workspace_page_scope.dart';
import 'ws_ui.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';

/// Booking wording (B1/B2). Falls back to the shared operational wording.
String bookingText(BuildContext context, String key) {
  final vi = AppTranslations.of(context).locale.languageCode == 'vi';
  const labels = <String, List<String>>{
    'newBooking': ['New booking', 'Đặt phòng mới'],
    'chooseKind': ['What kind of booking?', 'Loại đặt phòng'],
    'shortStay': ['Short stay', 'Ngắn hạn'],
    'shortStayHelp': ['By the hour or by the night', 'Theo giờ hoặc theo đêm'],
    'longStay': ['Long stay', 'Dài hạn'],
    'longStayHelp': [
      'Monthly lease with a contract',
      'Thuê theo tháng, có hợp đồng',
    ],
    'stayHelp': [
      'Times are in the property\'s time zone. The server calculates the price.',
      'Giờ theo múi giờ của tòa nhà. Máy chủ tính giá.',
    ],
    'secStay': ['Room and dates', 'Phòng và thời gian'],
    'secGuests': ['Guests', 'Khách'],
    'secPrice': ['Price', 'Giá'],
    'secSurcharges': ['Surcharges', 'Phụ phí'],
    'secDeposit': ['Deposit', 'Tiền cọc'],
    'secSource': ['Staff and source', 'Phụ trách và nguồn khách'],
    'secMoney': ['Payments', 'Thanh toán'],
    'checkIn': ['Check-in (YYYY-MM-DD HH:mm)', 'Nhận phòng (YYYY-MM-DD HH:mm)'],
    'checkOut': [
      'Check-out (YYYY-MM-DD HH:mm)',
      'Trả phòng (YYYY-MM-DD HH:mm)',
    ],
    'pickDate': ['Pick date and time', 'Chọn ngày giờ'],
    'nightsCount': ['{n} nights', '{n} đêm'],
    'oneNight': ['1 night', '1 đêm'],
    'repeatedHour': ['Repeated hour (clock change)', 'Giờ bị lặp (đổi giờ)'],
    'mainGuest': ['Main guest', 'Khách chính'],
    'idNumber': ['ID card number (CCCD)', 'Số CCCD'],
    'idHidden': [
      'Hidden ({mask}). Leave empty to keep it.',
      'Đã ẩn ({mask}). Để trống để giữ nguyên.',
    ],
    'guestCount': ['Total guests', 'Tổng số khách'],
    'coGuest': ['Co-guest', 'Khách đi cùng'],
    'addGuest': ['Add co-guest', 'Thêm khách đi cùng'],
    'remove': ['Remove', 'Xóa'],
    'nightly': ['Per night', 'Theo đêm'],
    'defaultNight': [
      'Room price: {price} per night',
      'Giá phòng: {price} / đêm',
    ],
    'customNights': ['Different price each night', 'Giá khác nhau mỗi đêm'],
    'nightsField': ['Nights', 'Số đêm'],
    'hoursField': ['Hours', 'Số giờ'],
    'hoursCount': ['{n} hours', '{n} giờ'],
    // Deposit taken with the booking (2026-10-04): part of the total.
    'depositLine': ['Deposit', 'Tiền cọc'],
    'depositHelp': ['Taken off the total.', 'Được trừ vào tổng tiền.'],
    'depositHow': ['Paid by', 'Trả bằng'],
    'payCash': ['Cash', 'Tiền mặt'],
    'payTransfer': ['Bank transfer', 'Chuyển khoản'],
    'payCard': ['Card', 'Thẻ'],
    'depositDate': ['Payment date (YYYY-MM-DD)', 'Ngày trả cọc (YYYY-MM-DD)'],
    'transferDate': [
      'Transfer date (YYYY-MM-DD)',
      'Ngày chuyển khoản (YYYY-MM-DD)',
    ],
    'depositRecorded': ['Deposit received: {info}', 'Đã nhận cọc: {info}'],
    'depositNeedsCollect': [
      'Taking a deposit needs "Collect payments".',
      'Cần quyền "Thu tiền" để nhận cọc.',
    ],
    'depositTooLarge': [
      'The deposit is more than the total.',
      'Tiền cọc lớn hơn tổng tiền.',
    ],
    'depositBadDate': [
      'Enter a day up to today (YYYY-MM-DD).',
      'Nhập ngày đến hôm nay (YYYY-MM-DD).',
    ],
    'alreadyPaid': ['Already paid', 'Đã thanh toán'],
    'pricePerNight': ['Price per night', 'Giá mỗi đêm'],
    'pricePerHour': ['Price per hour', 'Giá mỗi giờ'],
    'unitLocked': [
      'Room price. Changing it needs "Change prices".',
      'Giá phòng. Cần quyền "Đổi giá" để sửa.',
    ],
    'nightsHelp': [
      'Changes the check-out date.',
      'Đổi số đêm sẽ đổi ngày trả phòng.',
    ],
    'estimate': ['Estimate', 'Tạm tính'],
    'oldPricing': [
      'This booking was priced by day or overnight; choose per night or per hour.',
      'Đặt phòng này trước đây tính theo ngày hoặc qua đêm; hãy chọn theo đêm hoặc theo giờ.',
    ],
    'night': ['Night {n}', 'Đêm {n}'],
    'nightPricesKept': [
      'Saved prices per night are kept while the number of nights stays the same.',
      'Giá từng đêm đã lưu được giữ nếu số đêm không đổi.',
    ],
    'addSurcharge': ['Add surcharge', 'Thêm phụ phí'],
    'perRoom': ['Per room', 'Theo phòng'],
    'perPerson': ['Per person', 'Theo người'],
    'perPersonLine': ['{p} × {n} guests = {t}', '{p} × {n} khách = {t}'],
    'surchargeLabel': ['Description', 'Nội dung'],
    'noSurcharges': ['No surcharges.', 'Không có phụ phí.'],
    'depositNote': [
      'Deposit note (date, transfer…)',
      'Ghi chú cọc (ngày, chuyển khoản…)',
    ],
    'depositNoteShort': ['Deposit note', 'Ghi chú cọc'],
    'staffInCharge': ['Staff in charge', 'Nhân viên phụ trách'],
    'notSet': ['Not set', 'Chưa chọn'],
    'platform': ['Booking platform', 'Nền tảng đặt phòng'],
    'contactChannel': ['Contact channel', 'Kênh liên lạc'],
    'direct': ['Direct', 'Trực tiếp'],
    'airbnb': ['Airbnb', 'Airbnb'],
    'booking': ['Booking.com', 'Booking.com'],
    'agoda': ['Agoda', 'Agoda'],
    'traveloka': ['Traveloka', 'Traveloka'],
    'zalo': ['Zalo', 'Zalo'],
    'whatsapp': ['WhatsApp', 'WhatsApp'],
    'messenger': ['Messenger', 'Messenger'],
    'roomPrice': ['Room price', 'Tiền phòng'],
    'remaining': ['Still owed', 'Còn phải trả'],
    'close': ['Close', 'Đóng'],
    'moreActions': ['More actions', 'Thao tác khác'],
    'checkoutShort': ['Check out', 'Trả phòng'],
    // Short labels for buttons inside sections (2026-10-04, Tom).
    'editShort': ['Edit', 'Sửa'],
    'collectShort': ['Collect', 'Thu tiền'],
    'depositShort': ['Deposit', 'Thu cọc'],
    'backToBookings': ['Bookings', 'Đặt phòng'],
    'depositPaid': ['Deposit paid', 'Đã cọc'],
    'receivedInto': ['Received into', 'Nhận vào'],
    'otherTransfer': ['Bank transfer', 'Chuyển khoản'],
    // The three stay statuses (2026-10-04): deposit paid, staying, checked out.
    'statusDeposited': [
      'Deposit paid – not checked in',
      'Đã đặt cọc – chưa check in',
    ],
    'staying': ['Staying', 'Đang ở'],
    'notCheckedIn': ['Not checked in', 'Chưa check in'],
    'checkedOutWord': ['Checked out', 'Đã check out'],
    'changedAgain': [
      'This booking or room changed meanwhile. Check the details and the price again.',
      'Đặt phòng hoặc phòng vừa được thay đổi. Hãy kiểm tra lại thông tin và giá.',
    ],
    'conflict': [
      'The room is already booked or rented for part of that time.',
      'Phòng đã có người đặt hoặc thuê trong một phần thời gian này.',
    ],
    'roomProblem': [
      'This room has an open technical problem and takes no new bookings until it is fixed.',
      'Phòng đang có sự cố kỹ thuật chưa sửa, chưa nhận đặt phòng mới.',
    ],
    'staffInvalid': [
      'That staff member is no longer active. Choose someone else.',
      'Nhân viên này không còn làm việc. Hãy chọn người khác.',
    ],
    'accountInvalid': [
      'That account was removed. Choose another one.',
      'Tài khoản này đã bị xóa. Hãy chọn tài khoản khác.',
    ],
    'overpay': [
      'The amount is more than what can be collected or refunded.',
      'Số tiền vượt quá số có thể thu hoặc hoàn.',
    ],
    'outsideHours': [
      'The room is not open at that time.',
      'Phòng không mở cửa vào thời gian này.',
    ],
    'priceRows': [
      'Fill in every price line, or remove the empty ones.',
      'Hãy điền đủ từng dòng giá, hoặc xóa dòng trống.',
    ],
    'guestCountInvalid': ['Enter 1 to 100.', 'Nhập từ 1 đến 100.'],
  };
  return labels[key]?[vi ? 1 : 0] ?? opsText(context, key);
}

class _GuestRow {
  final String id;
  final TextEditingController name, idNumber;

  /// The stored number as the server showed it (masked without "Xem số CCCD").
  final String shown;
  _GuestRow(this.id, {String name = '', String idNumber = '', this.shown = ''})
    : name = TextEditingController(text: name),
      idNumber = TextEditingController(text: idNumber);
  void dispose() {
    name.dispose();
    idNumber.dispose();
  }
}

class _ChargeRow {
  final TextEditingController label, amount;

  /// 'room': the amount once; 'person': the amount × the number of guests (2026-10-04).
  String basis;
  _ChargeRow({String label = '', String amount = '', this.basis = 'room'})
    : label = TextEditingController(text: label),
      amount = TextEditingController(text: amount);
  void dispose() {
    label.dispose();
    amount.dispose();
  }
}

// Zones without daylight-saving time never repeat an hour.
const _noClockChange = {
  'Asia/Ho_Chi_Minh',
  'Asia/Saigon',
  'Asia/Bangkok',
  'Asia/Singapore',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Asia/Shanghai',
  'Asia/Jakarta',
  'Asia/Manila',
  'Asia/Kuala_Lumpur',
  'Asia/Phnom_Penh',
  'Asia/Vientiane',
  'Asia/Hong_Kong',
  'Asia/Taipei',
  'Asia/Kolkata',
  'UTC',
};
const _platforms = [
  'direct',
  'airbnb',
  'booking',
  'agoda',
  'traveloka',
  'other',
];
const _channels = ['phone', 'zalo', 'whatsapp', 'messenger', 'other'];

class BookingWorkspaceScreen extends StatefulWidget {
  final String organizationId, buildingId, accountId;
  final TeamService service;

  /// Null inside the organization workspace sections (U1): no Back button
  /// on the list; Back still returns from a booking/invoice to the list.
  /// Open this record first (from a link), then report what is open.
  final String? initialRecordId;
  final ValueChanged<String?>? onRecordChanged;
  final VoidCallback? onBack;

  /// B1: "New booking" also offers a long stay (lease form) when true.
  final bool offerLease;

  /// Opened over the calendar (C): shows only [initialRecordId], or the
  /// new-booking form when [startNew]; "back to the list" calls this instead.
  final VoidCallback? onClose;
  final bool startNew;

  /// New booking from the calendar: room and "YYYY-MM-DD HH:MM" times.
  final String? initialRoomId, initialStart, initialEnd;
  const BookingWorkspaceScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.accountId,
    required this.service,
    this.onBack,
    this.initialRecordId,
    this.onRecordChanged,
    this.offerLease = false,
    this.onClose,
    this.startNew = false,
    this.initialRoomId,
    this.initialStart,
    this.initialEnd,
  });
  @override
  State<BookingWorkspaceScreen> createState() => _BookingWorkspaceScreenState();
}

class _BookingWorkspaceScreenState extends State<BookingWorkspaceScreen> {
  late final MoneyForm _conversion = MoneyForm(
    OrganizationMoney.shared.forOrganization(widget.organizationId),
  );
  String get _inputCurrency => _conversion.currency(_currency);
  final _fields = {
        for (final k in [
          'guest',
          'phone',
          'idNumber',
          'guestCount',
          'notes',
          'startLocal',
          'endLocal',
          'depositAmount',
          'depositDate',
          'amount',
          'reason',
          'unitPrice',
          'nightsField',
        ])
          k: TextEditingController(),
      },
      _form = GlobalKey<FormState>();
  final _guests = <_GuestRow>[];
  final _charges = <_ChargeRow>[];
  final _nightPrices = <TextEditingController>[];
  // Rows removed from the form while their fields may still be on screen
  // for one more frame; disposed with the page.
  final _retired = <Object>[];
  List<Map<String, dynamic>> _rows = [],
      _rooms = [],
      _staff = [],
      _accounts = [];
  Map<String, dynamic>? _record, _quote, _pending;
  String? _cursor,
      _room,
      _message,
      _command,
      _status,
      _staffId,
      _platform,
      _channel,
      _mainShown;
  String _mode = 'list',
      _pricing = 'hourly',
      _occurrence = 'first',
      _method = 'cash',
      _account = 'cash',
      _depositMethod = 'cash',
      _today = '',
      _zone = '',
      _currency = 'VND';
  bool _busy = true,
      _canManage = false,
      _canCreate = false,
      _canPrice = false,
      _canCollect = false,
      _canReadIds = false,
      _optionsLoaded = false,
      _customNights = false,
      _syncingNights = false,
          // Per night / per hour picked by hand (or a price typed): the dates
          // no longer change it (2026-10-05).
          _pricingChosen =
          false,
      _leasing = false;
  int _generation = 0;
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
  };
  String get _journal =>
      'booking-pending:${jsonEncode([widget.accountId, widget.organizationId, widget.buildingId])}';
  bool get _locked => _busy || _pending != null;
  bool get _formEnabled => !_locked && _quote == null;
  int get _scale => _currency == 'USD' ? 100 : 1;

  @override
  void initState() {
    super.initState();
    _fields['startLocal']!.addListener(_datesChanged);
    _fields['endLocal']!.addListener(_datesChanged);
    _init();
  }

  @override
  void didUpdateWidget(covariant BookingWorkspaceScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.accountId != widget.accountId ||
        old.service != widget.service) {
      _generation++;
      _pending = null;
      _optionsLoaded = false;
      _leasing = false;
      _init();
    }
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final g in _guests) {
      g.dispose();
    }
    for (final c in _charges) {
      c.dispose();
    }
    for (final c in _nightPrices) {
      c.dispose();
    }
    for (final r in _retired) {
      if (r is TextEditingController) r.dispose();
      if (r is _GuestRow) r.dispose();
      if (r is _ChargeRow) r.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _rows = [];
      _record = null;
      _quote = null;
    });
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_journal);
      if (!mounted || generation != _generation) return;
      if (raw != null) {
        setState(() {
          _pending = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          _busy = false;
          _message = 'uncertain';
        });
        return;
      }
      // Opened over the calendar: that booking only, or the new-booking form.
      if (widget.onClose != null) {
        if (widget.initialRecordId != null) {
          await _read(widget.initialRecordId!);
        } else if (widget.startNew) {
          await _edit(create: true);
        } else {
          widget.onClose!();
        }
        return;
      }
      await _list();
      // A link to one booking: open it once the list is there.
      final link = widget.initialRecordId;
      if (link != null &&
          mounted &&
          generation == _generation &&
          _pending == null) {
        await _read(link);
      }
    } catch (_) {
      if (mounted && generation == _generation) _deny();
    }
  }

  // U1 step 2: tell the workspace which record is open (for the address).
  String? _reported;
  void _reportRecord(String? id) {
    if (id == _reported) return;
    _reported = id;
    final report = widget.onRecordChanged;
    if (report != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) report(id);
      });
    }
  }

  String bt(String key) => bookingText(context, key);

  String _roomTitleFor(Map<String, dynamic> r) =>
      AppTranslations.of(context).locale.languageCode == 'vi'
      ? 'Phòng ${_roomLabel(r)}'
      : 'Room ${_roomLabel(r)}';

  /// Room number when the server sent one; the internal ID only as a fallback.
  String _roomLabel(Map<String, dynamic> row) {
    final number = row['roomNumber'];
    return number is String && number.isNotEmpty
        ? number
        : '${row['roomId'] ?? ''}';
  }

  String _money(Object? value, [String? currency]) {
    // 5,000,000 VND · 2,000.50 USD in every language (2026-10-05, Tom).
    return appMoney(value is num ? value : 0, currency ?? _currency);
  }

  String _nightsLabel(int n) =>
      n == 1 ? bt('oneNight') : bt('nightsCount').replaceAll('{n}', '$n');

  /// Property-local nights between the check-in and check-out dates.
  int? _nightsBetween(String start, String end) {
    DateTime? day(String s) {
      final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s.trim());
      if (m == null) return null;
      return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }

    final a = day(start), b = day(end);
    if (a == null || b == null) return null;
    final n = b.difference(a).inDays;
    return n > 0 && n <= 366 ? n : null;
  }

  int? get _nightCount =>
      _nightsBetween(_fields['startLocal']!.text, _fields['endLocal']!.text);

  int? _roomRate(String field) {
    final room = _rooms.where((v) => v['id'] == _room).firstOrNull;
    final value = room?[field] as int?;
    if (value == null) return null;
    final source = room?['currency'] as String? ?? 'VND';
    if (source == _currency) return value;
    return _conversion.conversion?.convertMinor(value, source, _currency);
  }

  int? get _roomNightMinor => _roomRate('nightlyPriceMinor');
  int? get _roomHourMinor => _roomRate('hourlyPriceMinor');

  /// The room's price for the chosen way of pricing (per night / per hour).
  int? get _roomUnitMinor =>
      _pricing == 'hourly' ? _roomHourMinor : _roomNightMinor;

  /// The way of pricing a new booking starts with (2026-10-05, Tom): the
  /// room's only price when it has one kind; otherwise by the dates — a stay
  /// that crosses a night (14:00 → next day 12:00) is per night, a same-day
  /// stay per hour. Per night when the dates are not filled in yet.
  String _autoPricing() {
    final night = _roomNightMinor != null, hour = _roomHourMinor != null;
    if (night != hour) return night ? 'nightly' : 'hourly';
    if (_nightCount != null) return 'nightly';
    if (_hours != null) return 'hourly';
    return 'nightly';
  }

  /// Follows [_autoPricing] on a new booking until staff choose themselves.
  void _autoPick() {
    if (_record != null || _pricingChosen || _customNights) return;
    final p = _autoPricing();
    if (p == _pricing) return;
    _pricing = p;
    _syncNights();
    _resetUnit();
  }

  /// Fills the price box with the room's price (new room or way of pricing).
  void _resetUnit() {
    final m = _roomUnitMinor;
    _conversion.set(_fields['unitPrice']!, m, _currency);
  }

  static DateTime? _parseLocal(String s) {
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})$',
    ).firstMatch(s.trim());
    if (m == null) return null;
    return DateTime.utc(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      int.parse(m[4]!),
      int.parse(m[5]!),
    );
  }

  static String _formatLocal(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Hours between check-in and check-out (wall-clock, property time).
  double? get _hours {
    final a = _parseLocal(_fields['startLocal']!.text),
        b = _parseLocal(_fields['endLocal']!.text);
    if (a == null || b == null || !b.isAfter(a)) return null;
    return b.difference(a).inMinutes / 60;
  }

  void _datesChanged() {
    if (!mounted || _mode != 'edit') return;
    setState(() {
      _autoPick();
      _syncNights();
      // The nights box follows the dates, unless it is the one changing them.
      if (!_syncingNights) {
        final n = _nightCount;
        final text = n == null ? '' : '$n';
        if (_fields['nightsField']!.text != text)
          _fields['nightsField']!.text = text;
      }
    });
  }

  /// Typing the number of nights moves the check-out date (same check-out time).
  void _nightsTyped(String value) {
    final n = int.tryParse(value.trim());
    final start = _parseLocal(_fields['startLocal']!.text);
    if (n == null || n < 1 || n > 366 || start == null) return;
    final end = _parseLocal(_fields['endLocal']!.text);
    final out = DateTime.utc(
      start.year,
      start.month,
      start.day + n,
      end?.hour ?? 12,
      end?.minute ?? 0,
    );
    _syncingNights = true;
    _fields['endLocal']!.text = _formatLocal(out);
    _syncingNights = false;
  }

  /// "2 nights × 500,000 = 1,000,000" (the server's quote is final).
  String? _estimate() {
    final unit = _conversion.parse(_fields['unitPrice']!, _currency);
    if (_pricing == 'hourly') {
      final h = _hours;
      if (h == null || unit == null || unit <= 0) return null;
      final hours = appQuantity(h, decimals: 2);
      return '${bt('hoursCount').replaceAll('{n}', hours)} × ${_money(unit / _scale)} = ${_money((unit * h).round() / _scale)}';
    }
    final n = _nightCount;
    if (n == null) return null;
    if (_customNights) {
      final list = [
        for (final c in _nightPrices) _conversion.parse(c, _currency),
      ];
      if (list.length != n || list.any((v) => v == null || v <= 0)) return null;
      return '${_nightsLabel(n)} = ${_money(list.fold<int>(0, (a, b) => a + b!) / _scale)}';
    }
    if (unit == null || unit <= 0) return null;
    return '${_nightsLabel(n)} × ${_money(unit / _scale)} = ${_money(unit * n / _scale)}';
  }

  /// Keeps one price field per night; typed prices stay for the nights left.
  void _syncNights() {
    if (!_customNights) return;
    final n = _nightCount;
    if (n == null) return;
    while (_nightPrices.length < n) {
      final previous = _nightPrices.lastOrNull;
      final original = previous == null
          ? _roomNightMinor
          : _conversion.parse(previous, _currency);
      final controller = TextEditingController();
      if (original != null) {
        _conversion.set(controller, original, _currency);
      } else {
        controller.text = previous?.text ?? '';
      }
      _nightPrices.add(controller);
    }
    while (_nightPrices.length > n) {
      _retired.add(_nightPrices.removeLast());
    }
  }

  /// Booking status in anh Hưng's words: a paid deposit before check-in reads
  /// "Đã cọc – chưa nhận phòng", a checked-in booking "Đang ở".
  Widget _statusPill(BuildContext context, Map<String, dynamic> row) {
    final tr = AppTranslations.of(context);
    final status = row['status'];
    final deposited =
        (row['depositPaidAmount'] as num? ?? 0) > 0 ||
        row['depositPayment'] is Map;
    if (['pending', 'confirmed'].contains(status) && deposited) {
      return WsPill(bt('statusDeposited'), tone: WsTone.info);
    }
    if (status == 'checkedIn') return WsPill(bt('staying'), tone: WsTone.good);
    // The four stay statuses (2026-10-04, Tom): Đã đặt cọc – chưa check in,
    // Chưa check in, Đang ở, Đã check out.
    if (['pending', 'confirmed'].contains(status)) {
      return WsPill(bt('notCheckedIn'), tone: WsTone.warning);
    }
    if (status == 'checkedOut')
      return WsPill(bt('checkedOutWord'), tone: WsTone.neutral);
    final key = switch (status) {
      'checkedOut' => 'checked_out',
      'noShow' => 'no_show',
      _ => '$status',
    };
    final label = tr.translationKeys.contains('booking_status_$key')
        ? tr['booking_status_$key']
        : '$status';
    final tone = switch (status) {
      'pending' => WsTone.warning,
      'confirmed' => WsTone.info,
      'cancelled' || 'noShow' => WsTone.bad,
      _ => WsTone.neutral,
    };
    return WsPill(label, tone: tone);
  }

  void _deny() {
    setState(() {
      _busy = false;
      _rows = [];
      _rooms = [];
      _record = null;
      _quote = null;
      _mode = 'list';
      _command = null;
      _canManage = false;
      _canCreate = false;
      _message = 'unavailable';
      for (final c in _fields.values) {
        c.clear();
      }
      _clearRows();
    });
  }

  void _clearRows() {
    _retired
      ..addAll(_guests)
      ..addAll(_charges)
      ..addAll(_nightPrices);
    _guests.clear();
    _charges.clear();
    _nightPrices.clear();
  }

  Future<void> _list({bool more = false}) async {
    // Over the calendar there is no list: going back to it closes the page.
    if (widget.onClose != null && !more) {
      widget.onClose!();
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _mode = 'list';
      _message = null;
      _record = null;
      _quote = null;
      _command = null;
      if (!more) {
        _rows = [];
        _cursor = null;
      }
    });
    try {
      final r = await widget.service.bookingWorkspace({
        ..._identity,
        'action': 'list',
        if (more) 'cursor': _cursor,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _rows.map((v) => v['id']).toSet();
        _rows.addAll(
          (r['records'] as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .where((v) => ids.add(v['id'])),
        );
        _cursor = r['nextCursor'] as String?;
        _canManage = r['canManage'] == true;
        // Older servers had no separate "add bookings" permission.
        _canCreate = r['canCreate'] is bool
            ? r['canCreate'] == true
            : _canManage;
        _zone = r['timeZone'] as String;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) _deny();
    }
  }

  Future<void> _read(String id) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _record = null;
      _rows = [];
      _quote = null;
      _command = null;
      _status = null;
    });
    try {
      final r = await widget.service.bookingWorkspace({
        ..._identity,
        'action': 'read',
        'bookingId': id,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _record = Map<String, dynamic>.from(r['record'] as Map);
        _currency = _record!['currency'] as String;
        _zone = _record!['timeZone'] as String;
        _mode = 'detail';
        _busy = false;
        _fields['reason']!.clear();
        _fields['amount']!.clear();
      });
    } catch (_) {
      if (mounted && generation == _generation) _deny();
    }
  }

  /// Rooms that take short stays, staff, receiving accounts and what the
  /// person may do with prices and ID numbers.
  Future<void> _loadOptions() async {
    final r = await widget.service.bookingWorkspace({
      ..._identity,
      'action': 'rooms',
    });
    List<Map<String, dynamic>> list(Object? v) => v is List
        ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    _rooms = list(r['records']);
    _staff = list(r['staff']);
    _accounts = list(r['accounts']);
    _zone = r['timeZone'] as String? ?? _zone;
    _canPrice = r['canPrice'] == true;
    _canCollect = r['canCollect'] == true;
    _today = r['today'] as String? ?? _today;
    _canReadIds = r['canReadGuestIds'] == true;
    _optionsLoaded = true;
  }

  Future<void> _newBooking() async {
    if (!widget.offerLease) return _edit(create: true);
    if (!_canCreate) {
      setState(() => _leasing = true);
      return;
    }
    final kind = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(bt('chooseKind')),
        contentPadding: const EdgeInsets.symmetric(vertical: WsSpace.md),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const ValueKey('booking-kind-short'),
              leading: const Icon(Icons.nights_stay_outlined),
              title: Text(bt('shortStay')),
              subtitle: Text(bt('shortStayHelp')),
              onTap: () => Navigator.pop(c, 'short'),
            ),
            ListTile(
              key: const ValueKey('booking-kind-long'),
              leading: const Icon(Icons.home_work_outlined),
              title: Text(bt('longStay')),
              subtitle: Text(bt('longStayHelp')),
              onTap: () => Navigator.pop(c, 'long'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(bt('cancel')),
          ),
        ],
      ),
    );
    if (!mounted || kind == null) return;
    if (kind == 'long') {
      setState(() => _leasing = true);
    } else {
      await _edit(create: true);
    }
  }

  Future<void> _edit({bool create = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _quote = null;
      _message = null;
      if (create) _record = null;
    });
    try {
      await _loadOptions();
      if (!mounted || generation != _generation) return;
      setState(() {
        final r = _record;
        _room =
            r?['roomId'] as String? ??
            (_rooms.any((v) => v['id'] == widget.initialRoomId)
                ? widget.initialRoomId
                : null) ??
            // Opened without a room (calendar "Đặt phòng"): start on the
            // first room that has a short-stay price; any room can be chosen.
            (_rooms
                        .where(
                          (v) =>
                              v['nightlyPriceMinor'] != null ||
                              v['hourlyPriceMinor'] != null,
                        )
                        .firstOrNull ??
                    _rooms.firstOrNull)?['id']
                as String?;
        _currency =
            r?['currency'] as String? ??
            _rooms.where((v) => v['id'] == _room).firstOrNull?['currency']
                as String? ??
            'VND';
        if (r == null) _currency = _conversion.currency(_currency);
        // New bookings start per night when the room has a nightly price.
        _pricing =
            r?['pricingType'] as String? ??
            (_roomNightMinor != null ? 'nightly' : 'hourly');
        // Only per night and per hour are offered (2026-10-03); a booking
        // priced by day or overnight is priced again when it is edited.
        if (!const ['nightly', 'hourly'].contains(_pricing)) {
          _pricing = _roomNightMinor != null ? 'nightly' : 'hourly';
        }
        String text(String key) => '${r?[key] ?? ''}';
        _fields['guest']!.text = text('guestName');
        _fields['phone']!.text = text('guestPhone');
        _fields['notes']!.text = text('notes');
        _fields['startLocal']!.text = text('startLocal');
        _fields['endLocal']!.text = text('endLocal');
        // New booking from a day on the calendar.
        if (r == null && widget.initialStart != null) {
          _fields['startLocal']!.text = widget.initialStart!;
          _fields['endLocal']!.text = widget.initialEnd ?? '';
        }
        if (r == null) {
          _pricingChosen = false;
          _pricing = _autoPricing();
        }
        // A deposit taken now (2026-10-04); one already recorded is only shown.
        _fields['depositAmount']!.clear();
        _fields['depositDate']!.text = _today;
        _depositMethod = 'cash';
        _fields['guestCount']!.text = text('numberOfGuests');
        final shownId = text('guestIdNumber');
        _fields['idNumber']!.text = _canReadIds ? shownId : '';
        _mainShown = shownId;
        _clearRows();
        for (final g in (r?['guests'] as List? ?? const [])) {
          final m = Map<String, dynamic>.from(g as Map);
          _guests.add(
            _GuestRow(
              '${m['id']}',
              name: '${m['name'] ?? ''}',
              idNumber: _canReadIds ? '${m['idNumber'] ?? ''}' : '',
              shown: '${m['idNumber'] ?? ''}',
            ),
          );
        }
        for (final s in (r?['surcharges'] as List? ?? const [])) {
          final m = Map<String, dynamic>.from(s as Map);
          final person = m['basis'] == 'person';
          final row = _ChargeRow(
            label: '${m['label'] ?? ''}',
            basis: person ? 'person' : 'room',
          );
          _conversion.set(
            row.amount,
            (((person ? m['unitAmount'] : m['amount']) as num? ?? 0) * _scale)
                .round(),
            _currency,
          );
          _charges.add(row);
        }
        final nights = (r?['nightPrices'] as List?)?.cast<num>();
        _customNights =
            _canPrice &&
            nights != null &&
            nights.isNotEmpty &&
            nights.toSet().length > 1;
        if (_customNights) {
          _nightPrices.addAll(
            nights!.map((v) {
              final c = TextEditingController();
              _conversion.set(c, (v * _scale).round(), _currency);
              return c;
            }),
          );
        }
        // The price box: the booking's own price when it has one, else the room's.
        final ownNight =
            r?['pricingType'] == 'nightly' &&
                nights != null &&
                nights.toSet().length == 1
            ? nights.first
            : null;
        final ownHour = r?['pricingType'] == 'hourly'
            ? (r?['hourlyPrice'] as num?)
            : null;
        final own = _pricing == 'nightly' ? ownNight : ownHour;
        if (own != null) {
          _conversion.set(
            _fields['unitPrice']!,
            (own * _scale).round(),
            _currency,
          );
        } else {
          _resetUnit();
        }
        _fields['nightsField']!.text = _nightCount?.toString() ?? '';
        final staffId = r?['staffInChargeId'] as String?;
        if (staffId != null && !_staff.any((s) => s['id'] == staffId)) {
          // Someone who left stays shown on their old bookings.
          final name = '${r?['staffName'] ?? ''}';
          _staff.add({
            'id': staffId,
            'displayName': name.isEmpty ? staffId : name,
          });
        }
        _staffId = staffId;
        _platform = r?['platform'] as String?;
        _channel = r?['contactChannel'] as String?;
        _mode = 'edit';
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) _deny();
    }
  }

  /// Price inputs shared by the quote and the save. Null: a line is incomplete.
  Map<String, dynamic>? _pricePayload() {
    final out = <String, dynamic>{};
    final unit = _conversion.parse(_fields['unitPrice']!, _currency);
    if (_pricing == 'nightly' && _customNights) {
      final list = [
        for (final c in _nightPrices) _conversion.parse(c, _currency),
      ];
      if (list.length != _nightCount || list.any((v) => v == null || v <= 0)) {
        return null;
      }
      out['nightPricesMinor'] = list;
    } else if (_pricing == 'nightly') {
      // Same price every night: people with "Đổi giá" send it; others get the
      // room's price (or keep the booking's) on the server.
      final n = _nightCount;
      if (_canPrice && n != null) {
        if (unit == null || unit <= 0) return null;
        out['nightPricesMinor'] = List<int>.filled(n, unit);
      }
    } else if (_pricing == 'hourly') {
      if (_canPrice) {
        if (unit == null || unit <= 0) return null;
        out['hourlyPriceMinor'] = unit;
      } else if (!(_record?['pricingType'] == 'hourly' &&
              _record?['hourlyPrice'] != null) &&
          _roomHourMinor != null) {
        // Hours × the room's price (not the older switch to a day price).
        out['hourlyPriceMinor'] = _roomHourMinor;
      }
    }
    final charges = <Map<String, dynamic>>[];
    for (final row in _charges) {
      final label = row.label.text.trim(), amount = row.amount.text.trim();
      if (label.isEmpty && amount.isEmpty) continue;
      final minor = _conversion.parse(row.amount, _currency);
      if (label.isEmpty || minor == null || minor <= 0) return null;
      charges.add({
        'label': label,
        'amountMinor': minor,
        if (row.basis == 'person') 'basis': 'person',
      });
    }
    out['surcharges'] = charges;
    return out;
  }

  Future<void> _review() async {
    if (!_form.currentState!.validate()) return;
    if (_room == null) {
      setState(
        () => _message = _rooms.isEmpty ? 'noShortStayRooms' : 'roomRequired',
      );
      return;
    }
    final price = _pricePayload();
    if (price == null) {
      setState(() => _message = 'priceRows');
      return;
    }
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final r = await widget.service.bookingWorkspace({
        ..._identity,
        'action': 'quote',
        if (_record != null) 'bookingId': _record!['id'],
        'inputCurrency': _currency,
        if (_conversion.conversion?.snapshotId != null)
          'ratesId': _conversion.conversion!.snapshotId,
        'roomId': _room,
        'startLocal': _fields['startLocal']!.text.trim(),
        'endLocal': _fields['endLocal']!.text.trim(),
        'occurrence': _occurrence,
        'pricingType': _pricing,
        'numberOfGuests': _guestCount,
        ...price,
      });
      if (!mounted || generation != _generation) return;
      final quote = Map<String, dynamic>.from(r['record'] as Map);
      final paid = (((_record?['paidAmount'] as num?) ?? 0) * _scale).round();
      if ((_newDepositMinor ?? 0) + paid >
          ((quote['totalMinor'] as num?) ?? 0)) {
        setState(() {
          _busy = false;
          _message = 'depositTooLarge';
        });
        return;
      }
      setState(() {
        _quote = quote;
        _currency = _quote!['currency'] as String;
        _busy = false;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _quote = null;
          _message = _quoteProblem(e);
        });
      }
    }
  }

  /// A plain reason for a refused price check, instead of a generic error.
  static String _quoteProblem(Object e) {
    if (e is! FirebaseFunctionsException) return 'unavailable';
    return switch (serverReason(e, const [
      'booking_currency_changed',
      'booking_invalid_dates',
      'booking_invalid-argument',
      'booking_rate_required',
      'booking_room_required',
      'booking_invalid_amount',
      'booking_permission-denied',
      'booking_not-found',
      'lease_property_timezone_required',
      'booking_night_prices_invalid',
      'booking_invalid_surcharge',
    ])) {
      'booking_currency_changed' => 'changedAgain',
      'booking_invalid_dates' || 'booking_invalid-argument' => 'badDates',
      'booking_night_prices_invalid' ||
      'booking_invalid_surcharge' => 'priceRows',
      'booking_rate_required' => 'rateMissing',
      'booking_room_required' => 'roomRequired',
      'booking_invalid_amount' => 'badAmount',
      'booking_permission-denied' => 'noCreatePermission',
      'booking_not-found' => 'roomUnavailable',
      'lease_property_timezone_required' => 'timezoneMissing',
      _ =>
        const {
              'unavailable',
              'internal',
              'deadline-exceeded',
              'unknown',
            }.contains(e.code)
            ? 'uncertain'
            : 'unavailable',
    };
  }

  /// Refusals the person can fix in the form (what was typed stays).
  static const _fixable = {
    'booking_currency_changed': 'changedAgain',
    'booking_conflict': 'conflict',
    'room_has_open_problem': 'roomProblem',
    'booking_staff_invalid': 'staffInvalid',
    'booking_account_invalid': 'accountInvalid',
    'booking_overpayment': 'overpay',
    'booking_refund_exceeds_deposit': 'overpay',
    'booking_refund_exceeds_payment': 'overpay',
    'booking_changed': 'changedAgain',
    'booking_room_changed': 'changedAgain',
    'booking_property_changed': 'changedAgain',
    'booking_invalid_transition': 'changedAgain',
    'booking_outside_operating_hours': 'outsideHours',
    'booking_night_prices_invalid': 'priceRows',
    'booking_invalid_surcharge': 'priceRows',
    'booking_invalid_dates': 'badDates',
    'booking_deposit_too_large': 'depositTooLarge',
    'booking_deposit_date': 'depositBadDate',
    'booking_deposit_recorded': 'changedAgain',
  };

  Future<void> _startCommand(String action, {String? status}) async {
    if (!_optionsLoaded) {
      setState(() => _busy = true);
      try {
        await _loadOptions();
      } catch (_) {
        // Without the account list, cash and plain transfer still work.
      }
      if (!mounted) return;
    }
    setState(() {
      _busy = false;
      _message = null;
      _command = action;
      _status = status;
      _method = 'cash';
      _account = 'cash';
      _fields['reason']!.clear();
      // Start from the amount still open; it can be changed.
      final r = _record ?? const <String, dynamic>{};
      num n(String k) => r[k] as num? ?? 0;
      final open = switch (action) {
        'payment' => n('totalPrice') - n('paidAmount'),
        'deposit' => n('depositAmount') - n('depositPaidAmount'),
        'refund' => n('depositPaidAmount') - n('depositRefundedAmount'),
        'refundRent' => n('paidAmount'),
        _ => 0,
      };
      _conversion.set(
        _fields['amount']!,
        open > 0 ? (open * _scale).round() : null,
        _currency,
      );
    });
  }

  Future<void> _save() async {
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      if (_mode == 'edit') {
        final price = _pricePayload();
        if (price == null) {
          setState(() => _message = 'priceRows');
          return;
        }
        final deposit = _newDepositMinor;
        // Older bookings' "deposit asked for" stays as it was.
        final asked = (((_record?['depositAmount'] as num?) ?? 0) * _scale)
            .round();
        final idText = _fields['idNumber']!.text.trim();
        final count = _fields['guestCount']!.text.trim();
        _pending = {
          ..._identity,
          'action': 'save',
          'inputCurrency': _currency,
          if (_conversion.conversion?.snapshotId != null)
            'ratesId': _conversion.conversion!.snapshotId,
          'bookingId': _record?['id'] ?? const Uuid().v4(),
          'operationId': const Uuid().v4(),
          'revision': _record?['revision'],
          'roomId': _room,
          'roomRevision': _quote!['roomRevision'],
          'startLocal': _fields['startLocal']!.text.trim(),
          'endLocal': _fields['endLocal']!.text.trim(),
          'occurrence': _occurrence,
          'pricingType': _pricing,
          ...price,
          'guestName': _fields['guest']!.text.trim(),
          'guestPhone': _fields['phone']!.text.trim(),
          // Without "Xem số CCCD" an empty box keeps the stored number.
          if (_canReadIds || idText.isNotEmpty) 'guestIdNumber': idText,
          'guests': [
            for (final g in _guests)
              {
                'id': g.id,
                'name': g.name.text.trim(),
                if (_canReadIds || g.idNumber.text.trim().isNotEmpty)
                  'idNumber': g.idNumber.text.trim(),
              },
          ],
          'numberOfGuests': count.isEmpty
              ? 1 + _guests.length
              : int.parse(count),
          'staffInChargeId': _staffId,
          'platform': _platform,
          'contactChannel': _channel,
          'notes': _fields['notes']!.text.trim(),
          'depositMinor': asked,
          if (deposit != null)
            'deposit': {
              'amountMinor': deposit,
              'inputCurrency': _inputCurrency,
              'inputAmountMinor': appParseMoney(_fields['depositAmount']!.text, _inputCurrency),
              if (_conversion.conversion?.snapshotId != null) 'ratesId': _conversion.conversion!.snapshotId,
              'method': _depositMethod,
              'paidOn': _fields['depositDate']!.text.trim(),
            },
        };
      } else {
        final amount = _conversion.parse(_fields['amount']!, _currency);
        final money = [
          'payment',
          'deposit',
          'refund',
          'refundRent',
          'checkout',
        ].contains(_command);
        if (money &&
            _command != 'checkout' &&
            (amount == null || amount <= 0)) {
          setState(() => _message = 'required');
          return;
        }
        _pending = {
          ..._identity,
          'action': 'command',
          'bookingId': _record!['id'],
          'operationId': const Uuid().v4(),
          'revision': _record!['revision'],
          'command': _command,
          'status': _status,
          'reason': _fields['reason']!.text.trim(),
          'paymentMethod': _method,
          'amountMinor': amount,
          if (money && _command != 'checkout') ...{
            'inputCurrency': _inputCurrency,
            'inputAmountMinor': appParseMoney(
              _fields['amount']!.text,
              _inputCurrency,
            ),
            if (_conversion.conversion?.snapshotId != null)
              'ratesId': _conversion.conversion!.snapshotId,
          },
          if (money && _account != 'transfer') 'accountId': _account,
        };
      }
    }
    final generation = ++_generation, journal = _journal;
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(journal, jsonEncode(_pending))) {
        throw StateError('Storage');
      }
      if (!mounted || generation != _generation) return;
      final r = await widget.service.bookingWorkspace(_pending!);
      if (!await prefs.remove(journal)) throw StateError('Storage');
      if (!mounted || generation != _generation) return;
      _pending = null;
      await _read(r['id'] as String);
      if (mounted) setState(() => _message = 'saved');
    } catch (e) {
      if (!mounted || generation != _generation) return;
      if (e is FirebaseFunctionsException &&
          ![
            'unavailable',
            'internal',
            'deadline-exceeded',
            'unknown',
          ].contains(e.code)) {
        try {
          await (await SharedPreferences.getInstance()).remove(journal);
        } catch (_) {}
        if (!mounted || generation != _generation) return;
        _pending = null;
        final fix = _fixable[serverReason(e, _fixable.keys)];
        if (fix != null) {
          // Keep what was typed; a changed booking needs a fresh price check.
          setState(() {
            _busy = false;
            _message = fix;
            if (fix == 'changedAgain' || fix == 'conflict') _quote = null;
          });
        } else {
          _deny();
        }
      } else {
        setState(() {
          _busy = false;
          _message = 'uncertain';
        });
      }
    }
  }

  /// Guests for per-person surcharges: the "Tổng số khách" box, else main guest + co-guests.
  int get _guestCount {
    final n = int.tryParse(_fields['guestCount']!.text.trim());
    return n != null && n >= 1 && n <= 100 ? n : 1 + _guests.length;
  }

  /// The deposit typed in the form (minor units), when one can be taken now.
  int? get _newDepositMinor {
    if (!_canCollect || _record?['depositPayment'] is Map) return null;
    final text = _fields['depositAmount']!.text.trim();
    if (text.isEmpty) return null;
    final v = _conversion.parse(_fields['depositAmount']!, _currency);
    return v == null || v <= 0 ? null : v;
  }

  String _payLabel(Object? method) => switch (method) {
    'bankTransfer' => bt('payTransfer'),
    'creditCard' => bt('payCard'),
    _ => bt('payCash'),
  };

  /// "300,000 VND · Bank transfer · 2026-10-03".
  String _depositInfo(Map<String, dynamic> d) =>
      '${_money(d['amount'])} · ${_payLabel(d['paymentMethod'])}'
      '${'${d['paidOn'] ?? ''}'.isEmpty ? '' : ' · ${d['paidOn']}'}';

  /// A day up to today (property time), as YYYY-MM-DD.
  String? _depositDateProblem(String v) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
    final d = m == null
        ? null
        : DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    String two(int x) => x.toString().padLeft(2, '0');
    final real =
        d != null &&
        '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}' ==
            v;
    return real && (_today.isEmpty || v.compareTo(_today) <= 0)
        ? null
        : bt('depositBadDate');
  }

  Future<void> _pickDay(TextEditingController controller) async {
    final today = DateTime.tryParse(_today) ?? DateTime.now();
    final current = DateTime.tryParse(controller.text.trim());
    final date = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isAfter(today) ? current : today,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
    );
    if (date == null || !mounted) return;
    String two(int v) => v.toString().padLeft(2, '0');
    setState(
      () =>
          controller.text = '${date.year}-${two(date.month)}-${two(date.day)}',
    );
  }

  Future<void> _pickDateTime(TextEditingController controller) async {
    final current = DateTime.tryParse(
      controller.text.trim().replaceAll(' ', 'T'),
    );
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: current != null
          ? TimeOfDay.fromDateTime(current)
          : const TimeOfDay(hour: 14, minute: 0),
    );
    if (time == null) return;
    String two(int v) => v.toString().padLeft(2, '0');
    controller.text =
        '${date.year}-${two(date.month)}-${two(date.day)} ${two(time.hour)}:${two(time.minute)}';
  }

  Widget _input(
    String key,
    String label, {
    bool required = false,
    String? helper,
    String? hint,
    Widget? suffix,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    int? maxLines = 1,
    String? Function(String)? check,
    TextEditingController? controller,
    bool enabled = true,
    ValueChanged<String>? onChanged,
  }) => Semantics(
    label: label,
    child: TextFormField(
      key: ValueKey('ops-$key'),
      controller: controller ?? _fields[key],
      enabled: _formEnabled && enabled,
      onChanged: onChanged,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        hintText: hint,
        suffixIcon: suffix,
      ),
      validator: (v) {
        final text = (v ?? '').trim();
        if (required && text.isEmpty) return opsText(context, 'required');
        return check?.call(text);
      },
    ),
  );

  Widget _choice(
    String label,
    String value,
    String? group,
    ValueChanged<String>? onSelect, {
    Key? key,
  }) => ChoiceChip(
    key: key,
    label: Text(label),
    selected: value == group,
    onSelected: onSelect == null ? null : (_) => onSelect(value),
  );

  Widget _dropdown(
    String key,
    String label,
    String? value,
    List<(String, String)> items,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String?>(
    key: ValueKey('booking-$key'),
    initialValue: value,
    isExpanded: true,
    // Regular weight: the chosen value is data, not a heading.
    style: Theme.of(context).textTheme.bodyLarge,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem<String?>(value: null, child: Text(bt('notSet'))),
      for (final (id, text) in items)
        DropdownMenuItem<String?>(
          value: id,
          child: Text(text, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: _formEnabled ? onChanged : null,
  );

  Widget _removeButton(VoidCallback onPressed) => IconButton(
    tooltip: bt('remove'),
    icon: const Icon(Icons.close),
    onPressed: _formEnabled ? onPressed : null,
  );

  List<Widget> _editForm(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final error = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.error,
    );
    final nights = _nightCount;
    final editing = _record != null;
    final money = TextInputType.numberWithOptions(
      decimal: _inputCurrency == 'USD',
    );
    String? moneyCheck(String v) =>
        v.isNotEmpty && operationalMoney(v, _inputCurrency) == null
        ? opsText(context, 'required')
        : null;
    Widget pickButton(String key) => IconButton(
      tooltip: bt('pickDate'),
      icon: const Icon(Icons.event_outlined),
      onPressed: _formEnabled ? () => _pickDateTime(_fields[key]!) : null,
    );
    return [
      WsSection(
        title: bt('secStay'),
        icon: Icons.meeting_room_outlined,
        children: [
          if (_rooms.isEmpty)
            Text(
              opsText(context, 'noShortStayRooms'),
              key: const ValueKey('booking-no-rooms'),
              style: error,
            )
          else
            Wrap(
              spacing: WsSpace.sm,
              runSpacing: WsSpace.sm,
              children: [
                for (final room in _rooms)
                  _choice(
                    '${room['roomNumber']}',
                    room['id'] as String,
                    _room,
                    !_formEnabled || editing
                        ? null
                        : (v) => setState(() {
                            _room = v;
                            _currency = _conversion.currency(
                              room['currency'] as String? ?? 'VND',
                            );
                            _resetUnit();
                            _autoPick();
                          }),
                    key: ValueKey('booking-room-${room['id']}'),
                  ),
              ],
            ),
          const SizedBox(height: WsSpace.md),
          WsFieldRow(
            children: [
              _input(
                'startLocal',
                bt('checkIn'),
                required: true,
                hint: '2026-10-10 14:00',
                suffix: pickButton('startLocal'),
              ),
              _input(
                'endLocal',
                bt('checkOut'),
                required: true,
                hint: '2026-10-11 12:00',
                suffix: pickButton('endLocal'),
              ),
            ],
          ),
          if (nights != null)
            Padding(
              padding: const EdgeInsets.only(top: WsSpace.sm),
              child: Text(
                _nightsLabel(nights),
                key: const ValueKey('booking-nights'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          if (_zone.isNotEmpty && !_noClockChange.contains(_zone)) ...[
            const SizedBox(height: WsSpace.md),
            Text(bt('repeatedHour'), style: muted),
            const SizedBox(height: WsSpace.xs),
            Wrap(
              spacing: WsSpace.sm,
              children: [
                for (final value in ['first', 'second'])
                  _choice(
                    opsText(context, value),
                    value,
                    _occurrence,
                    _formEnabled
                        ? (v) => setState(() => _occurrence = v)
                        : null,
                  ),
              ],
            ),
          ],
        ],
      ),
      WsSection(
        title: bt('secGuests'),
        icon: Icons.people_alt_outlined,
        children: [
          WsFieldRow(
            children: [
              _input('guest', bt('mainGuest'), required: true),
              _input(
                'phone',
                opsText(context, 'phone'),
                keyboard: TextInputType.phone,
              ),
            ],
          ),
          const SizedBox(height: WsSpace.md),
          WsFieldRow(
            children: [
              _input(
                'idNumber',
                bt('idNumber'),
                helper: !_canReadIds && (_mainShown ?? '').isNotEmpty
                    ? bt('idHidden').replaceAll('{mask}', _mainShown!)
                    : null,
              ),
              _input(
                'guestCount',
                bt('guestCount'),
                keyboard: TextInputType.number,
                hint: '${1 + _guests.length}',
                // Per-person surcharges follow the number of guests.
                onChanged: (_) => setState(() {}),
                check: (v) {
                  if (v.isEmpty) return null;
                  final n = int.tryParse(v);
                  return n == null || n < 1 || n > 100
                      ? bt('guestCountInvalid')
                      : null;
                },
              ),
            ],
          ),
          for (final (i, g) in _guests.indexed) ...[
            const SizedBox(height: WsSpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: WsFieldRow(
                    children: [
                      _input(
                        'coGuest-$i',
                        '${bt('coGuest')} ${i + 1}',
                        controller: g.name,
                        required: true,
                      ),
                      _input(
                        'coGuestId-$i',
                        bt('idNumber'),
                        controller: g.idNumber,
                        helper: !_canReadIds && g.shown.isNotEmpty
                            ? bt('idHidden').replaceAll('{mask}', g.shown)
                            : null,
                      ),
                    ],
                  ),
                ),
                _removeButton(
                  () => setState(() => _retired.add(_guests.removeAt(i))),
                ),
              ],
            ),
          ],
          if (_guests.length < 20)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('booking-add-guest'),
                onPressed: _formEnabled
                    ? () => setState(
                        () => _guests.add(
                          _GuestRow(
                            const Uuid()
                                .v4()
                                .replaceAll('-', '')
                                .substring(0, 20),
                          ),
                        ),
                      )
                    : null,
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: Text(bt('addGuest')),
              ),
            ),
        ],
      ),
      WsSection(
        title: bt('secPrice'),
        icon: Icons.sell_outlined,
        children: [
          Wrap(
            spacing: WsSpace.sm,
            runSpacing: WsSpace.sm,
            children: [
              // Per night or per hour only (Tom, 2026-10-03).
              for (final type in ['nightly', 'hourly'])
                _choice(
                  bt(type),
                  type,
                  _pricing,
                  _formEnabled
                      ? (v) => setState(() {
                          _pricingChosen = true;
                          if (_pricing == v) return;
                          _pricing = v;
                          _syncNights();
                          _resetUnit();
                        })
                      : null,
                  key: ValueKey('booking-pricing-$type'),
                ),
            ],
          ),
          if (editing &&
              !const ['nightly', 'hourly'].contains(_record?['pricingType']))
            Padding(
              padding: const EdgeInsets.only(top: WsSpace.sm),
              child: Text(bt('oldPricing'), style: muted),
            ),
          const SizedBox(height: WsSpace.md),
          WsFieldRow(
            children: [
              if (_pricing == 'nightly')
                _input(
                  'nightsField',
                  bt('nightsField'),
                  keyboard: TextInputType.number,
                  helper: bt('nightsHelp'),
                  onChanged: (v) => setState(() => _nightsTyped(v)),
                  check: (v) {
                    final n = int.tryParse(v);
                    return v.isNotEmpty && (n == null || n < 1 || n > 366)
                        ? opsText(context, 'required')
                        : null;
                  },
                )
              else
                InputDecorator(
                  key: const ValueKey('booking-hours'),
                  decoration: InputDecoration(
                    labelText: bt('hoursField'),
                    enabled: false,
                  ),
                  child: Text(
                    _hours == null ? '—' : appQuantity(_hours!, decimals: 2),
                  ),
                ),
              if (!(_pricing == 'nightly' && _customNights))
                _input(
                  'unitPrice',
                  bt(_pricing == 'hourly' ? 'pricePerHour' : 'pricePerNight'),
                  keyboard: money,
                  formatters: appMoneyInput(_inputCurrency),
                  enabled: _canPrice,
                  helper: _canPrice ? null : bt('unitLocked'),
                  onChanged: (_) => setState(() => _pricingChosen = true),
                  check: moneyCheck,
                ),
            ],
          ),
          if (_pricing == 'nightly') ...[
            if (_canPrice)
              SwitchListTile(
                key: const ValueKey('booking-custom-nights'),
                contentPadding: EdgeInsets.zero,
                title: Text(bt('customNights')),
                value: _customNights,
                onChanged: _formEnabled
                    ? (v) => setState(() {
                        _customNights = v;
                        if (v) {
                          // Every night starts at the price in the box.
                          if (_fields['unitPrice']!.text.trim().isNotEmpty) {
                            _retired.addAll(_nightPrices);
                            _nightPrices.clear();
                            final n = _nightCount ?? 0;
                            for (var i = 0; i < n; i++) {
                              final controller = TextEditingController();
                              final original = _conversion.parse(
                                _fields['unitPrice']!,
                                _currency,
                              );
                              if (original != null) {
                                _conversion.set(
                                  controller,
                                  original,
                                  _currency,
                                );
                              } else {
                                controller.text = _fields['unitPrice']!.text
                                    .trim();
                              }
                              _nightPrices.add(controller);
                            }
                          }
                          _syncNights();
                        } else {
                          _retired.addAll(_nightPrices);
                          _nightPrices.clear();
                        }
                      })
                    : null,
              )
            else if (editing && _record?['nightPrices'] != null)
              Padding(
                padding: const EdgeInsets.only(top: WsSpace.sm),
                child: Text(bt('nightPricesKept'), style: muted),
              ),
            if (_customNights && _nightPrices.isNotEmpty)
              Wrap(
                spacing: WsSpace.sm,
                runSpacing: WsSpace.md,
                children: [
                  for (final (i, c) in _nightPrices.indexed)
                    SizedBox(
                      width: 150,
                      child: _input(
                        'night-$i',
                        bt('night').replaceAll('{n}', '${i + 1}'),
                        controller: c,
                        keyboard: money,
                        formatters: appMoneyInput(_inputCurrency),
                        required: true,
                        check: moneyCheck,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                ],
              ),
          ],
          if (_estimate() case final estimate?)
            Padding(
              padding: const EdgeInsets.only(top: WsSpace.md),
              child: Text(
                '${bt('estimate')}: $estimate',
                key: const ValueKey('booking-estimate'),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      WsSection(
        title: bt('secSurcharges'),
        icon: Icons.add_card_outlined,
        children: [
          if (_charges.isEmpty) Text(bt('noSurcharges'), style: muted),
          for (final (i, c) in _charges.indexed)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : WsSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: WsFieldRow(
                          children: [
                            _input(
                              'surcharge-$i',
                              bt('surchargeLabel'),
                              controller: c.label,
                            ),
                            _input(
                              'surchargeAmount-$i',
                              opsText(context, 'amount'),
                              controller: c.amount,
                              keyboard: money,
                              formatters: appMoneyInput(_inputCurrency),
                              check: moneyCheck,
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                      _removeButton(
                        () =>
                            setState(() => _retired.add(_charges.removeAt(i))),
                      ),
                    ],
                  ),
                  const SizedBox(height: WsSpace.xs),
                  // Per room: the amount once. Per person: × the number of guests, once.
                  Wrap(
                    spacing: WsSpace.sm,
                    runSpacing: WsSpace.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (basis, label) in [
                        ('room', bt('perRoom')),
                        ('person', bt('perPerson')),
                      ])
                        _choice(
                          label,
                          basis,
                          c.basis,
                          _formEnabled
                              ? (v) => setState(() => c.basis = v)
                              : null,
                          key: ValueKey('booking-surcharge-$i-$basis'),
                        ),
                      if (c.basis == 'person')
                        if (_conversion.parse(c.amount, _currency)
                            case final unit? when unit > 0)
                          Text(
                            bt('perPersonLine')
                                .replaceAll('{p}', _money(unit / _scale))
                                .replaceAll('{n}', '$_guestCount')
                                .replaceAll(
                                  '{t}',
                                  _money(unit * _guestCount / _scale),
                                ),
                            key: ValueKey('booking-surcharge-$i-total'),
                            style: muted,
                          ),
                    ],
                  ),
                ],
              ),
            ),
          if (_charges.length < 20)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('booking-add-surcharge'),
                onPressed: _formEnabled
                    ? () => setState(() => _charges.add(_ChargeRow()))
                    : null,
                icon: const Icon(Icons.add, size: 18),
                label: Text(bt('addSurcharge')),
              ),
            ),
        ],
      ),
      WsSection(
        title: bt('secDeposit'),
        icon: Icons.savings_outlined,
        children: [
          if (_record?['depositPayment'] is Map)
            Text(
              bt('depositRecorded').replaceAll(
                '{info}',
                _depositInfo(
                  Map<String, dynamic>.from(_record!['depositPayment'] as Map),
                ),
              ),
              key: const ValueKey('booking-deposit-recorded'),
            )
          else if (!_canCollect)
            Text(bt('depositNeedsCollect'), style: muted)
          else ...[
            _input(
              'depositAmount',
              bt('depositLine'),
              keyboard: money,
              formatters: appMoneyInput(_inputCurrency),
              check: moneyCheck,
              helper: bt('depositHelp'),
              onChanged: (_) => setState(() {}),
            ),
            // How and when: only once there is a deposit.
            if (_newDepositMinor != null) ...[
              const SizedBox(height: WsSpace.md),
              Text(bt('depositHow'), style: theme.textTheme.labelLarge),
              const SizedBox(height: WsSpace.xs),
              Wrap(
                spacing: WsSpace.sm,
                runSpacing: WsSpace.sm,
                children: [
                  for (final (method, label) in [
                    ('cash', bt('payCash')),
                    ('bankTransfer', bt('payTransfer')),
                    ('creditCard', bt('payCard')),
                  ])
                    _choice(
                      label,
                      method,
                      _depositMethod,
                      _formEnabled
                          ? (v) => setState(() => _depositMethod = v)
                          : null,
                      key: ValueKey('booking-deposit-$method'),
                    ),
                ],
              ),
              const SizedBox(height: WsSpace.md),
              _input(
                'depositDate',
                bt(
                  _depositMethod == 'bankTransfer'
                      ? 'transferDate'
                      : 'depositDate',
                ),
                required: true,
                hint: _today.isEmpty ? '2026-10-04' : _today,
                check: _depositDateProblem,
                suffix: IconButton(
                  tooltip: bt('pickDate'),
                  icon: const Icon(Icons.event_outlined),
                  onPressed: _formEnabled
                      ? () => _pickDay(_fields['depositDate']!)
                      : null,
                ),
              ),
            ],
          ],
        ],
      ),
      WsSection(
        title: bt('secSource'),
        icon: Icons.badge_outlined,
        children: [
          _dropdown('staff', bt('staffInCharge'), _staffId, [
            for (final s in _staff) ('${s['id']}', '${s['displayName']}'),
          ], (v) => setState(() => _staffId = v)),
          const SizedBox(height: WsSpace.md),
          WsFieldRow(
            children: [
              _dropdown(
                'platform',
                bt('platform'),
                _platform,
                [for (final p in _platforms) (p, bt(p))],
                (v) => setState(() => _platform = v),
              ),
              _dropdown(
                'channel',
                bt('contactChannel'),
                _channel,
                [for (final p in _channels) (p, bt(p))],
                (v) => setState(() => _channel = v),
              ),
            ],
          ),
          const SizedBox(height: WsSpace.md),
          _input('notes', opsText(context, 'notes'), maxLines: null),
        ],
      ),
      if (_quote != null) _quoteCard(context),
      // Shown next to the buttons: a message at the top is off screen on phones.
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: WsSpace.md),
          child: Text(
            bt(_message!),
            key: const ValueKey('booking-form-message'),
            style: error,
          ),
        ),
      WsActions(
        children: _quote == null
            ? [
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _record == null
                            ? _list()
                            : _read(_record!['id'] as String),
                  child: Text(bt('cancel')),
                ),
                FilledButton(
                  onPressed: _busy ? null : _review,
                  child: Text(opsText(context, 'review')),
                ),
              ]
            : [
                OutlinedButton(
                  onPressed: _busy ? null : () => setState(() => _quote = null),
                  child: Text(opsText(context, 'edit')),
                ),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(opsText(context, 'confirm')),
                ),
              ],
      ),
    ];
  }

  Widget _minusLine(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: WsSpace.xs),
    child: Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    ),
  );

  Widget _quoteCard(BuildContext context) {
    final q = _quote!;
    final theme = Theme.of(context);
    num units(Object? minor) => (minor as num? ?? 0) / _scale;
    final nights = q['nights'] as int?;
    final total = (q['totalMinor'] as num?) ?? 0,
        paid = (((_record?['paidAmount'] as num?) ?? 0) * _scale).round(),
        deposit = _newDepositMinor ?? 0;
    return Card(
      key: const ValueKey('booking-quote'),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(WsSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WsInfo(
              bt('roomPrice'),
              '${_money(units(q['baseMinor'] ?? q['totalMinor']))}'
              '${nights != null ? ' · ${_nightsLabel(nights)}' : ''}',
            ),
            for (final l
                in (q['surchargeLines'] as List? ?? const []).cast<Map>())
              WsInfo(
                '+ ${l['label']}',
                l['basis'] == 'person'
                    ? bt('perPersonLine')
                          .replaceAll('{p}', _money(units(l['unitMinor'])))
                          .replaceAll('{n}', '${l['count']}')
                          .replaceAll('{t}', _money(units(l['totalMinor'])))
                    : _money(units(l['totalMinor'])),
              ),
            const Divider(height: WsSpace.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    opsText(context, 'total'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  _money(units(q['totalMinor'])),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            // The deposit (and anything paid before) is taken off the total.
            // Taken off, lined up under the total.
            if (paid > 0)
              _minusLine(theme, bt('alreadyPaid'), '− ${_money(units(paid))}'),
            if (deposit > 0)
              _minusLine(
                theme,
                bt('depositLine'),
                '− ${_money(units(deposit))}',
              ),
            if (paid > 0 || deposit > 0)
              Row(
                key: const ValueKey('booking-quote-remaining'),
                children: [
                  Expanded(
                    child: Text(
                      bt('remaining'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    _money(units(total - paid - deposit)),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _detail(BuildContext context, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final total = r['totalPrice'] as num? ?? 0,
        paid = r['paidAmount'] as num? ?? 0;
    final depositRequired = r['depositAmount'] as num? ?? 0,
        depositPaid = r['depositPaidAmount'] as num? ?? 0,
        depositRefunded = r['depositRefundedAmount'] as num? ?? 0;
    final nights = _nightsBetween(
      '${r['startLocal'] ?? ''}',
      '${r['endLocal'] ?? ''}',
    );
    List<Map<String, dynamic>> maps(Object? v) => (v as List? ?? const [])
        .map((g) => Map<String, dynamic>.from(g as Map))
        .toList();
    final guests = maps(r['guests']), charges = maps(r['surcharges']);
    final active = ['pending', 'confirmed', 'checkedIn'].contains(r['status']);
    final statuses = switch (r['status']) {
      'pending' => ['confirmed', 'checkedIn', 'cancelled', 'noShow'],
      'confirmed' => ['checkedIn', 'cancelled', 'noShow'],
      'checkedIn' => ['cancelled'],
      _ => <String>[],
    };
    String named(Object? v) => v == null ? '' : bt('$v');
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(WsSpace.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              WsBadge(text: _roomLabel(r)),
              const SizedBox(width: WsSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r['guestName']}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: WsSpace.xs),
                    Text(
                      '${r['startLocal']} – ${r['endLocal']}'
                      '${nights != null && r['pricingType'] == 'nightly' ? ' · ${_nightsLabel(nights)}' : ''}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: WsSpace.sm),
                    _statusPill(context, r),
                  ],
                ),
              ),
              // Changing the booking sits with what it changes (2026-10-04, Tom).
              if (_command == null && r['canManage'] == true && active)
                TextButton.icon(
                  key: const ValueKey('booking-edit'),
                  onPressed: _locked ? null : () => _edit(),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(bt('editShort'), maxLines: 1),
                ),
            ],
          ),
        ),
      ),
      WsSection(
        title: bt('secMoney'),
        icon: Icons.payments_outlined,
        // Taking money is done from the money section (2026-10-04, Tom).
        trailing: _command == null && r['canCollect'] == true && active
            ? Wrap(
                spacing: WsSpace.xs,
                children: [
                  if (depositPaid < depositRequired)
                    TextButton(
                      key: const ValueKey('booking-collect-deposit'),
                      onPressed: _locked
                          ? null
                          : () => _startCommand('deposit'),
                      child: Text(bt('depositShort'), maxLines: 1),
                    ),
                  if (paid < total)
                    TextButton(
                      key: const ValueKey('booking-collect'),
                      onPressed: _locked
                          ? null
                          : () => _startCommand('payment'),
                      child: Text(bt('collectShort'), maxLines: 1),
                    ),
                ],
              )
            : null,
        children: [
          WsInfo(opsText(context, 'total'), _money(total)),
          for (final c in charges)
            WsInfo(
              '+ ${c['label']}',
              c['basis'] == 'person'
                  ? bt('perPersonLine')
                        .replaceAll('{p}', _money(c['unitAmount']))
                        .replaceAll('{n}', '${c['count']}')
                        .replaceAll('{t}', _money(c['amount']))
                  : _money(c['amount']),
            ),
          WsInfo(opsText(context, 'paid'), _money(paid)),
          // Nothing is owed on a cancelled or no-show booking.
          if (!['cancelled', 'noShow'].contains(r['status']))
            WsInfo(bt('remaining'), _money(total - paid)),
          if (r['depositPayment'] is Map)
            WsInfo(
              bt('depositLine'),
              _depositInfo(
                Map<String, dynamic>.from(r['depositPayment'] as Map),
              ),
            )
          // Older bookings: a deposit asked for and collected separately.
          else if (depositRequired > 0 || depositPaid > 0)
            WsInfo(
              bt('depositPaid'),
              '${_money(r['depositPaidAmount'])} / ${_money(r['depositAmount'])}',
            ),
          if ('${r['depositNote'] ?? ''}'.isNotEmpty)
            WsInfo(bt('depositNoteShort'), '${r['depositNote']}'),
        ],
      ),
      WsSection(
        title: bt('secGuests'),
        icon: Icons.people_alt_outlined,
        children: [
          WsInfo(opsText(context, 'phone'), '${r['guestPhone'] ?? ''}'),
          WsInfo(bt('idNumber'), '${r['guestIdNumber'] ?? ''}'),
          WsInfo(bt('guestCount'), '${r['numberOfGuests'] ?? ''}'),
          for (final g in guests)
            WsInfo(
              bt('coGuest'),
              [
                g['name'],
                g['idNumber'],
              ].where((v) => '${v ?? ''}'.isNotEmpty).join(' · '),
            ),
          WsInfo(bt('staffInCharge'), '${r['staffName'] ?? ''}'),
          WsInfo(bt('platform'), named(r['platform'])),
          WsInfo(bt('contactChannel'), named(r['contactChannel'])),
          WsInfo(opsText(context, 'notes'), '${r['notes'] ?? ''}'),
        ],
      ),
      // The room's technical problems (2026-10-04).
      if (r['roomId'] is String)
        RoomProblemsSection(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          roomId: r['roomId'] as String,
          roomLabel: _roomTitleFor(r),
          service: widget.service,
        ),
      if (_command == null)
        Builder(
          builder: (context) {
            final manage = r['canManage'] == true;
            // The usual next step is the one filled button: check in, then
            // check out. Rare or undoing actions sit in the "…" menu.
            final next = !manage
                ? null
                : statuses.contains('checkedIn')
                ? 'checkedIn'
                : r['status'] == 'checkedIn' && r['canCollect'] == true
                ? 'checkout'
                : null;
            void run(String a) =>
                [
                  'payment',
                  'deposit',
                  'checkout',
                  'refund',
                  'refundRent',
                ].contains(a)
                ? _startCommand(a)
                : _startCommand('status', status: a);
            final more = [
              // Confirming is rare (most bookings go straight to check-in).
              if (manage && statuses.contains('confirmed')) 'confirmed',
              if (manage)
                ...statuses.where((s) => ['cancelled', 'noShow'].contains(s)),
              // Refunds only when there is money to give back.
              if (r['canRefund'] == true && depositPaid - depositRefunded > 0)
                'refund',
              if (r['canRefund'] == true && paid > 0) 'refundRent',
            ];
            return WsActions(
              children: [
                if (more.isNotEmpty)
                  PopupMenuButton<String>(
                    key: const ValueKey('booking-more'),
                    tooltip: bt('moreActions'),
                    enabled: !_locked,
                    onSelected: run,
                    itemBuilder: (_) => [
                      for (final a in more)
                        PopupMenuItem(
                          value: a,
                          child: Text(opsText(context, a)),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.all(WsSpace.sm),
                      child: Icon(Icons.more_horiz),
                    ),
                  ),
                // Only the usual next step here; editing and money are in
                // their sections above (2026-10-04, Tom).
                if (next != null)
                  FilledButton(
                    onPressed: _locked ? null : () => run(next),
                    child: Text(
                      next == 'checkout'
                          ? bt('checkoutShort')
                          : opsText(context, next),
                    ),
                  ),
              ],
            );
          },
        )
      else
        _commandCard(context),
    ];
  }

  Widget _commandCard(BuildContext context) {
    final theme = Theme.of(context);
    final money = [
      'payment',
      'deposit',
      'refund',
      'refundRent',
      'checkout',
    ].contains(_command);
    final choices = <(String, String)>[
      ('cash', opsText(context, 'cash')),
      for (final a in _accounts) ('${a['id']}', '${a['label']}'),
      if (_accounts.isEmpty) ('transfer', bt('otherTransfer')),
    ];
    return WsSection(
      title: opsText(context, _status ?? _command!),
      icon: Icons.receipt_long_outlined,
      children: [
        Text(
          opsText(context, 'reviewWarning'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: WsSpace.md),
        Semantics(
          label: opsText(context, 'reason'),
          child: TextFormField(
            key: const ValueKey('ops-reason'),
            controller: _fields['reason'],
            enabled: !_locked,
            decoration: InputDecoration(labelText: opsText(context, 'reason')),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? opsText(context, 'required') : null,
          ),
        ),
        if (money && _command != 'checkout') ...[
          const SizedBox(height: WsSpace.md),
          Semantics(
            label: opsText(context, 'amount'),
            child: TextFormField(
              key: const ValueKey('ops-amount'),
              controller: _fields['amount'],
              enabled: !_locked,
              keyboardType: TextInputType.numberWithOptions(
                decimal: _inputCurrency == 'USD',
              ),
              inputFormatters: appMoneyInput(_inputCurrency),
              decoration: InputDecoration(
                labelText: opsText(context, 'amount'),
                suffixText: _inputCurrency,
              ),
            ),
          ),
        ],
        if (money) ...[
          const SizedBox(height: WsSpace.md),
          Text(bt('receivedInto'), style: theme.textTheme.labelLarge),
          const SizedBox(height: WsSpace.xs),
          Wrap(
            spacing: WsSpace.sm,
            runSpacing: WsSpace.sm,
            children: [
              for (final (id, label) in choices)
                _choice(
                  label,
                  id,
                  _account,
                  _locked
                      ? null
                      : (v) => setState(() {
                          _account = v;
                          _method = v == 'cash' ? 'cash' : 'bankTransfer';
                        }),
                  key: ValueKey('booking-account-$id'),
                ),
            ],
          ),
        ],
        if (_message != null && _message != 'saved')
          Padding(
            padding: const EdgeInsets.only(top: WsSpace.md),
            child: Text(
              bt(_message!),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        WsActions(
          children: [
            OutlinedButton(
              onPressed: _locked
                  ? null
                  : () => setState(() {
                      _command = null;
                      _status = null;
                      _message = null;
                    }),
              // "Đóng", not "Hủy": next to "Hủy đặt phòng" a "Hủy" button is ambiguous.
              child: Text(bt('close')),
            ),
            FilledButton(
              onPressed: _locked ? null : _save,
              child: Text(opsText(context, 'confirm')),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    String t(String k) => opsText(context, k);
    if (_leasing) {
      void close() {
        setState(() => _leasing = false);
        _list();
      }

      return BackStep(
        onBack: close,
        child: TenantLeaseScreen(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          service: widget.service,
          onBack: close,
          backLabel: bt('backToBookings'),
        ),
      );
    }
    final r = _record;
    // Over the calendar the dialog's title bar names the page and closes it.
    final inDialog = DialogPageScope.contains(context);
    _reportRecord(_mode == 'detail' ? (r?['id'] as String?) : null);
    return BackStep(
      enabled: _mode != 'list',
      onBack: () {
        if (!_locked) _list();
      },
      child: opsPage(context, [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              WsHeader(
                back: !inDialog && (_mode != 'list' || widget.onBack != null)
                    ? WsBack(
                        label: t('back'),
                        onPressed: _locked
                            ? null
                            : (_mode == 'list' ? widget.onBack : () => _list()),
                      )
                    : null,
                title: inDialog
                    ? ''
                    : _mode == 'edit'
                    ? (r == null ? bt('newBooking') : t('edit'))
                    : t('bookings'),
                help: _mode == 'edit'
                    ? '${bt('stayHelp')}${_zone.isEmpty ? '' : ' ($_zone)'}'
                    : null,
                actions: [
                  if (_mode == 'list' &&
                      _pending == null &&
                      (_canCreate || widget.offerLease))
                    FilledButton.icon(
                      key: const ValueKey('booking-new'),
                      onPressed: _busy ? null : _newBooking,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(bt('newBooking')),
                    ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(bottom: WsSpace.sm),
                  child: LinearProgressIndicator(),
                ),
              if (_message != null && _mode != 'edit' && _command == null)
                WsNotice(
                  bt(_message!),
                  tone: _message == 'saved' ? WsTone.good : WsTone.warning,
                ),
              if (_pending != null)
                WsActions(
                  children: [
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(t('retry')),
                    ),
                  ],
                ),
              if (_mode == 'list' && _pending == null) ...[
                for (final row in _rows)
                  WsRecord(
                    leading: WsBadge(text: _roomLabel(row)),
                    title: '${row['guestName']}',
                    pill: _statusPill(context, row),
                    details: [
                      '${row['startLocal'] ?? ''} – ${row['endLocal'] ?? ''}',
                      if (row['totalPrice'] is num)
                        _money(row['totalPrice'], row['currency'] as String?),
                    ],
                    onTap: _busy ? null : () => _read(row['id'] as String),
                  ),
                if (_rows.isEmpty && !_busy)
                  WsEmpty(
                    icon: Icons.event_available_outlined,
                    message: t('empty'),
                  ),
                if (_cursor != null)
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : () => _list(more: true),
                      child: Text(t('more')),
                    ),
                  ),
              ],
              if (_mode == 'edit' && _pending == null) ..._editForm(context),
              if (_mode == 'detail' && r != null && _pending == null)
                ..._detail(context, r),
            ],
          ),
        ),
      ]),
    );
  }
}
