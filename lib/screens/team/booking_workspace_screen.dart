import '../../utils/money_conversion.dart';
import '../../services/organization_money.dart';
import 'dart:convert';
import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../services/read_cache.dart';
import '../../services/team_service.dart';
import 'back_steps.dart';
import 'booking_payments.dart';
import 'operational_widgets.dart';
import 'room_problems_section.dart';
import 'room_picker.dart';
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
      'Giờ theo múi giờ của cơ sở. Máy chủ tính giá.',
    ],
    'secStay': ['Room and dates', 'Phòng và thời gian'],
    'secGuests': ['Guests', 'Khách'],
    'secPrice': ['Price', 'Giá'],
    'secSurcharges': ['Surcharges', 'Phụ phí'],
    'secDeposit': ['Deposit', 'Tiền cọc'],
    'paymentSection': ['Payment', 'Thanh toán'],
    'retryCalculation': ['Retry calculation', 'Thử tính lại'],
    'calculationWaiting': [
      'Enter the stay dates and prices to see the total.',
      'Nhập ngày ở và giá để xem tổng tiền.',
    ],
    'calculationUpdating': ['Updating total…', 'Đang tính tổng tiền…'],
    // The dates are there, a price is not (2026-10-14: a room without its
    // own nightly price opens with an empty "Đêm 1").
    'pricesWaiting': [
      'Enter the price to see the total.',
      'Nhập giá để xem tổng tiền.',
    ],
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
    // Saved prices of the room (2026-10-09, Tom): tap one instead of typing.
    'savedPrices': ['Saved prices', 'Giá đã lưu'],
    // An agreed room price (Fix 5, 2026-10-09, Tom): needs "Đổi giá" and a
    // reason; the booking keeps the calculated price and who changed it.
    'agreedSwitch': ['Agreed price', 'Giá thỏa thuận'],
    // 2026-10-14 (Tom): the agreed price is the whole total (room price and
    // surcharges), not the price per night.
    'agreedHelp': [
      'A different total than calculated, with the reason.',
      'Tổng tiền khác với giá tính ra, kèm lý do.',
    ],
    'agreedPrice': ['Agreed total', 'Tổng tiền thỏa thuận'],
    'nightNeedsDay': [
      'Per night: check out on a later day than check-in.',
      'Theo đêm: ngày trả phòng phải sau ngày nhận phòng.',
    ],
    'agreedNeeded': [
      'Enter the agreed total and the reason.',
      'Nhập tổng tiền thỏa thuận và lý do.',
    ],
    'agreedReason': ['Reason for the change', 'Lý do đổi giá'],
    'agreedKept': [
      'Agreed price {price} ({reason}) is kept. Changing it needs "Change prices".',
      'Giữ giá thỏa thuận {price} ({reason}). Cần quyền "Đổi giá" để sửa.',
    ],
    'calculatedPrice': ['Calculated price', 'Giá tính ra'],
    'agreedBy': ['Changed by', 'Người đổi giá'],
    'savePrice': ['Save price', 'Lưu giá'],
    'saveThisPrice': ['Save this price', 'Lưu giá này'],
    'pickPrice': ['Saved prices', 'Chọn giá đã lưu'],
    'removePrice': ['Remove this price', 'Xóa giá này'],
    'savedPricesFull': [
      'This building already has 12 saved prices. Remove one first.',
      'Cơ sở này đã có 12 giá đã lưu. Hãy xóa bớt một giá.',
    ],
    'savePriceFailed': [
      'The price was not saved. Try again.',
      'Chưa lưu được giá. Hãy thử lại.',
    ],
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
    // The Thanh toán section (2026-10-14, Tom).
    'paymentTooLarge': [
      'The payments are more than the total. Change or remove a payment.',
      'Các lần thanh toán lớn hơn tổng tiền. Sửa hoặc xóa một lần thanh toán.',
    ],
    'paymentProblem': [
      'A payment in the list can\'t be saved (staff, account or way of paying changed). Edit it and try again.',
      'Một lần thanh toán không lưu được (nhân viên, tài khoản hoặc cách thanh toán đã thay đổi). Sửa lại rồi thử lại.',
    ],
    'refundTooLarge': [
      'The refund is more than the amount paid.',
      'Tiền hoàn lớn hơn số tiền đã thanh toán.',
    ],
    'depositNeeded': [
      'Enter the deposit amount, or untick "Deposit paid".',
      'Nhập số tiền cọc, hoặc bỏ chọn "Đã đặt cọc".',
    ],
    'depositDay': ['Deposit date', 'Ngày cọc'],
    'depositAmountShort': ['Deposit', 'Tiền cọc'],
    'depositPaidBox': ['Deposit paid', 'Đã đặt cọc'],
    'payDay': ['Payment date', 'Ngày thanh toán'],
    'payAmount': ['Amount paid', 'Số tiền'],
    'noteShort': ['Note', 'Ghi chú'],
    'paymentsHeading': ['Payments', 'Thanh toán'],
    'paidLine': ['Paid {amount} · {day}', 'Đã trả {amount} · {day}'],
    'stayHeading': ['Status', 'Trạng thái'],
    'stayNotIn': ['Not checked in', 'Chưa check in'],
    'stayIn': ['Staying', 'Đang ở'],
    'stayOut': ['Checked out', 'Đã check out'],
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
    // 2026-10-26: no flat price per hour; hourly bookings pick a template.
    'hourTemplateNeeded': [
      'Pick an hourly price template.',
      'Hãy chọn một mẫu giá theo giờ.',
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

  /// What the calendar already knows about [initialRecordId] (guest, dates,
  /// status), shown at once while the booking itself loads (2026-10-09).
  final List<String>? preview;
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
    this.preview,
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
          'depositNote',
          // A payment with the booking (2026-10-14, Tom): day, amount, note.
          'payDate',
          'payAmount',
          'payNote',
          'amount',
          'reason',
          'checkoutReason',
          'cancelReason',
          'refundReason',
          'refundAmount',
          'templateName',
          'unitPrice',
          'nightsField',
          'agreedPrice',
          'agreedReason',
        ])
          k: TextEditingController(),
      },
      _form = GlobalKey<FormState>();
  final _guests = <_GuestRow>[];
  final _charges = <_ChargeRow>[];
  final _hourPrices = <TextEditingController>[];
  List<Map<String, dynamic>> _hourTemplates = [];
  String? _templateCurrency;
  final _templateRequestIds = <String, String>{};
  final _nightPrices = <TextEditingController>[];
  // Rows removed from the form while their fields may still be on screen
  // for one more frame; disposed with the page.
  final _retired = <Object>[];
  List<Map<String, dynamic>> _rows = [],
      _rooms = [],
      _staff = [],
      _accounts = [],
      // Short-stay payments (2026-10-24, Tom): the organization's own ways
      // of paying, and the payments added to a new booking before its first
      // save (saved with it).
      _payMethods = [],
      _drafts = [],
      // A saved booking's payments as listed, for the totals card.
      _paymentRows = [];
  String? _myStaffId;
  bool _canRefundOpt = false, _canEditPayments = false;
  int _paymentsToken = 0;
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
          // The stay status staff choose (2026-10-14, Tom): notCheckedIn,
          // checkedIn (Đang ở) or checkedOut; never changed by the clock.
          _stay =
          'notCheckedIn',
      _today = '',
      _zone = '',
      _currency = 'VND';
  bool _busy = true,
      _canManage = false,
      _canCreate = false,
      _canPrice = false,
      _canSavePrices = false,
      _savingPrice = false,
      _canCollect = false,
      _canReadIds = false,
      _customNights = true,
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
  String _refundAccount = 'cash';
  final Map<String, String> _actionErrors = {};
  bool get _canEditRecord =>
      _record == null ||
      (_record!['canManage'] == true &&
          !['cancelled', 'noShow'].contains(_record!['status']));
  bool get _formEnabled => !_locked && (_command != null || _canEditRecord);
  Timer? _quoteTimer;
  String? _quoteInputKey;
  int _quoteVersion = 0;
  bool _quoting = false;
  String? _calculationMessage;
  bool _quoteFailed = false;
  int get _scale => _currency == 'USD' ? 100 : 1;

  /// An agreed total is typed (2026-10-14, Tom: no switch; empty = none).
  /// 2026-10-24 (Tom): "Tổng tiền thỏa thuận" was removed from the form. An
  /// agreed total already on a booking is kept (left out of every save).
  bool get _agreed => false;

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
      _leasing = false;
      _init();
    }
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final g in _guests) {
      g.dispose();
    }
    for (final c in _charges) {
      c.dispose();
    }
    for (final c in _hourPrices) {
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

  /// The building's saved nightly prices (2026-10-09, Tom: one list for all
  /// its rooms). Only when the booking is in the room's own currency and shown
  /// in it: a saved price is never converted.
  bool get _savedPricesApply {
    final room = _rooms.where((v) => v['id'] == _room).firstOrNull;
    if (room == null) return false;
    final source = room['currency'] as String? ?? 'VND';
    return source == _currency && _inputCurrency == _currency;
  }

  List<int> get _savedNights {
    if (!_savedPricesApply) return const [];
    final room = _rooms.where((v) => v['id'] == _room).firstOrNull;
    final list = room?['savedNightPricesMinor'];
    return list is List ? list.whereType<int>().toList() : const [];
  }

  /// What can be picked: the saved prices and the room's own price (always
  /// there, never removed: it comes from the room's settings). Sorted.
  List<int> get _priceOptions {
    final saved = _savedNights;
    if (!_savedPricesApply) return const [];
    final own = _roomNightMinor;
    return {...saved, ?own}.toList()..sort();
  }

  /// Fills the price box with a saved price.
  void _pickSaved(int minor) => setState(() {
    _conversion.set(_fields['unitPrice']!, minor, _currency);
    _pricingChosen = true;
    _message = null;
  });

  /// Adds prices to the building's saved prices, or removes one. Every room
  /// of the building shares the list (2026-10-09, Tom).
  Future<void> _savePrice(int minor, {bool remove = false}) =>
      _savePrices([minor], remove: remove);

  Future<void> _savePrices(List<int> minors, {bool remove = false}) async {
    if (minors.isEmpty || _savingPrice) return;
    setState(() {
      _savingPrice = true;
      _message = null;
    });
    try {
      final r = await widget.service.bookingWorkspace({
        ..._identity,
        'action': 'prices',
        if (minors.length == 1) 'priceMinor': minors.single,
        if (minors.length > 1) 'pricesMinor': minors,
        if (remove) 'remove': true,
      });
      if (!mounted) return;
      setState(() {
        final list = List<int>.from(
          (r['savedNightPricesMinor'] as List? ?? const []).whereType<int>(),
        );
        final currency = r['currency'] as String?;
        widget.service.keepBookingPrices(
          widget.organizationId,
          widget.buildingId,
          currency,
          list,
        );
        for (final room in _rooms) {
          final c = room['currency'] as String? ?? 'VND';
          if (currency == null || c == currency) {
            room['savedNightPricesMinor'] = List<int>.of(list);
          }
        }
        _savingPrice = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingPrice = false;
        _message =
            e is FirebaseFunctionsException &&
                serverReason(e, const ['booking_saved_prices_full']) ==
                    'booking_saved_prices_full'
            ? 'savedPricesFull'
            : 'savePriceFailed';
      });
    }
  }

  /// "Giá khác nhau mỗi đêm": a saved price for every night at once.
  void _pickSavedForAll(int minor) => setState(() {
    _conversion.set(_fields['unitPrice']!, minor, _currency);
    for (final c in _nightPrices) {
      _conversion.set(c, minor, _currency);
    }
    _message = null;
  });

  /// The nights' prices that are not saved yet (valid ones only).
  List<int> get _newNightPrices {
    final options = _priceOptions.toSet();
    return {
      for (final c in _nightPrices)
        if (_conversion.parse(c, _currency) case final v?)
          if (v > 0 && v <= 1000000000000 && !options.contains(v)) v,
    }.toList();
  }

  String _ht(String en, String vi) =>
      AppTranslations.of(context).locale.languageCode == 'vi' ? vi : en;
  List<int>? get _hourValues {
    final values = _hourPrices
        .map((c) => _conversion.parse(c, _currency))
        .toList();
    if (values.isEmpty ||
        values.any((v) => v == null || v <= 0 || v > 1000000000000))
      return null;
    return values.cast<int>();
  }

  void _setHourPrices(List<int> values) {
    _retired.addAll(_hourPrices);
    _hourPrices.clear();
    for (final value in values) {
      final c = TextEditingController();
      _conversion.set(c, value, _currency);
      _hourPrices.add(c);
    }
  }

  Future<void> _changeHourTemplate(Map<String, dynamic> change) async {
    if (_savingPrice) return;
    final generation = _generation;
    setState(() {
      _savingPrice = true;
      _message = null;
    });
    try {
      final result = await widget.service.bookingWorkspace({
        ..._identity,
        'action': 'hourTemplates',
        ...change,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _hourTemplates = (result['hourTemplates'] as List)
            .map((v) => Map<String, dynamic>.from(v as Map))
            .toList();
        _savingPrice = false;
        _fields['templateName']!.clear();
      });
      widget.service.keepBookingHourTemplates(
        widget.organizationId,
        widget.buildingId,
        _hourTemplates,
      );
    } catch (_) {
      if (mounted && generation == _generation)
        setState(() {
          _savingPrice = false;
          _message = 'savePriceFailed';
        });
    }
  }

  Widget _hourPricingEditor() {
    final enabled = _formEnabled && !_savingPrice;
    final templates = _hourTemplates.where((v) => v['currency'] == _currency);
    final custom = _hourPrices.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: WsSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _ht('Hourly templates', 'Mẫu giá theo giờ'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (templates.isEmpty)
            Text(
              _ht(
                'No templates yet. Add them under the building\'s prices.',
                'Chưa có mẫu giá. Thêm mẫu ở mục Giá của cơ sở.',
              ),
              key: const ValueKey('hour-templates-none'),
            ),
          for (final template in templates)
            ListTile(
              key: ValueKey('hour-template-${template['id']}'),
              contentPadding: EdgeInsets.zero,
              title: Text('${template['name']}'),
              selected:
                  jsonEncode(_hourValues) ==
                  jsonEncode(template['hourPricesMinor']),
              leading: Icon(
                jsonEncode(_hourValues) ==
                        jsonEncode(template['hourPricesMinor'])
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
              ),
              onTap: enabled
                  ? () => setState(() {
                      _setHourPrices(
                        (template['hourPricesMinor'] as List).cast<int>(),
                      );
                      _pricingChosen = true;
                    })
                  : null,
              trailing: _canSavePrices
                  ? IconButton(
                      key: ValueKey('hour-delete-${template['id']}'),
                      tooltip: _ht('Delete template', 'Xóa mẫu'),
                      icon: const Icon(Icons.close),
                      onPressed: enabled
                          ? () => _changeHourTemplate({
                              'templateId': template['id'],
                              'remove': true,
                            })
                          : null,
                    )
                  : null,
            ),
          Wrap(
            spacing: WsSpace.sm,
            runSpacing: WsSpace.sm,
            children: [
              if (!custom && _canPrice)
                TextButton(
                  key: const ValueKey('hour-custom'),
                  onPressed: enabled
                      ? () => setState(() {
                          _setHourPrices([]);
                          _hourPrices.add(TextEditingController());
                          _pricingChosen = true;
                        })
                      : null,
                  child: Text(_ht('Custom hours', 'Giá từng giờ')),
                ),
              // No "flat rate" any more (2026-10-26, Tom).
            ],
          ),
          if (custom) ...[
            Text(
              _ht(
                'The last price repeats for extra hours. Partial hours are prorated.',
                'Giờ tiếp theo dùng giá giờ cuối. Giờ lẻ tính theo thời gian thực tế.',
              ),
            ),
            for (final (i, c) in _hourPrices.indexed)
              Padding(
                padding: const EdgeInsets.only(top: WsSpace.sm),
                child: _input(
                  'hour-price-$i',
                  _ht('Hour ${i + 1}', 'Giờ ${i + 1}'),
                  controller: c,
                  enabled: enabled,
                  keyboard: TextInputType.numberWithOptions(
                    decimal: _inputCurrency == 'USD',
                  ),
                  formatters: appMoneyInput(_inputCurrency),
                  readOnly: !_canPrice,
                  onChanged: (_) => setState(() {}),
                  check: (v) => (_conversion.parse(c, _currency) ?? 0) <= 0
                      ? opsText(context, 'required')
                      : null,
                ),
              ),
            if (_canPrice)
              Wrap(
                spacing: WsSpace.sm,
                children: [
                  TextButton(
                    key: const ValueKey('hour-add'),
                    onPressed: enabled && _hourPrices.length < 168
                        ? () => setState(() {
                            final c = TextEditingController();
                            _conversion.set(
                              c,
                              _hourValues?.last ?? 0,
                              _currency,
                            );
                            _hourPrices.add(c);
                          })
                        : null,
                    child: Text(_ht('Add hour', 'Thêm giờ')),
                  ),
                  if (_hourPrices.length > 1)
                    TextButton(
                      key: const ValueKey('hour-remove'),
                      onPressed: enabled
                          ? () => setState(
                              () => _retired.add(_hourPrices.removeLast()),
                            )
                          : null,
                      child: Text(_ht('Remove last hour', 'Xóa giờ cuối')),
                    ),
                ],
              ),
            if (_canSavePrices &&
                _templateCurrency == _currency &&
                _inputCurrency == _currency) ...[
              _input(
                'templateName',
                _ht('Template name', 'Tên mẫu'),
                formatters: [LengthLimitingTextInputFormatter(80)],
                enabled: enabled,
                onChanged: (_) => setState(() {}),
              ),
              TextButton(
                key: const ValueKey('hour-save-template'),
                onPressed:
                    enabled &&
                        _hourValues != null &&
                        _fields['templateName']!.text.trim().isNotEmpty &&
                        _fields['templateName']!.text.trim().length <= 80
                    ? () => _changeHourTemplate({
                        'templateId': _templateRequestIds.putIfAbsent(
                          jsonEncode([
                            _fields['templateName']!.text.trim(),
                            _hourValues,
                            _currency,
                          ]),
                          () => const Uuid().v4(),
                        ),
                        'name': _fields['templateName']!.text.trim(),
                        'hourPricesMinor': _hourValues,
                      })
                    : null,
                child: Text(_ht('Save template', 'Lưu mẫu')),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// An older booking with one price per hour (before 2026-10-26) keeps it
  /// until a template or own hour prices are picked.
  bool get _oldFlatHourly =>
      _record?['pricingType'] == 'hourly' &&
      _record?['hourlyPrice'] != null &&
      _hourPrices.isEmpty;

  /// The room's price for the chosen way of pricing. Per hour there is none
  /// (2026-10-26): hourly bookings pick one of the building's templates.
  int? get _roomUnitMinor => _pricing == 'hourly' ? null : _roomNightMinor;

  /// The way of pricing a new booking starts with (2026-10-05, Tom): the
  /// room's only price when it has one kind; otherwise by the dates — a stay
  /// that crosses a night (14:00 → next day 12:00) is per night, a same-day
  /// stay per hour. Per night when the dates are not filled in yet.
  String _autoPricing() {
    // Per night: the room's price or the building's saved night prices
    // (every room may use those); per hour: the building's templates.
    final night = _roomNightMinor != null || _savedNights.isNotEmpty,
        hour = _hourTemplates.any((v) => v['currency'] == _currency);
    if (night != hour) return night ? 'nightly' : 'hourly';
    if (_nightCount != null) return 'nightly';
    if (_hours != null) return 'hourly';
    return 'nightly';
  }

  /// Follows [_autoPricing] on a new booking until staff choose themselves.
  void _autoPick() {
    if (_record != null || _pricingChosen) return;
    final p = _autoPricing();
    if (p == _pricing) return;
    _pricing = p;
    _resetUnit();
    _syncNights();
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
      if (_hourPrices.isNotEmpty) {
        final total = _estimateMinor();
        return total == null || h == null
            ? null
            : '${bt('hoursCount').replaceAll('{n}', appQuantity(h, decimals: 2))} = ${_money(total / _scale)}';
      }
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
      final original = _pricing == 'nightly'
          ? _conversion.parse(_fields['unitPrice']!, _currency) ??
                _roomNightMinor
          : _roomNightMinor;
      final controller = TextEditingController();
      if (original != null) {
        _conversion.set(controller, original, _currency);
      } else {
        controller.text = '';
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
        (row['depositReceivedAmount'] as num? ?? 0) > 0 ||
        row['depositReceivedAmount'] == null && row['depositPayment'] is Map;
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
    _savingPrice = false;
    _fields['templateName']!.clear();
    _retired
      ..addAll(_guests)
      ..addAll(_charges)
      ..addAll(_nightPrices)
      ..addAll(_hourPrices);
    _guests.clear();
    _charges.clear();
    _nightPrices.clear();
    _hourPrices.clear();
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
      if (_record?['id'] != id) {
        for (final field in [
          'checkoutReason',
          'cancelReason',
          'refundReason',
          'refundAmount',
        ]) {
          _fields[field]!.clear();
        }
        _actionErrors.clear();
        _refundAccount = 'cash';
      }
      _busy = true;
      _record = null;
      _rows = [];
      _quote = null;
      _command = null;
      _status = null;
    });
    try {
      // 2026-10-11 (Tom: open at once): the device copy first, locked
      // (busy) until the server's answer replaces it.
      await for (final answer in widget.service.readLive('bookingWorkspace', {
        ..._identity,
        'action': 'read',
        'bookingId': id,
      })) {
        if (!mounted || generation != _generation) return;
        final first = _record == null || _record!['id'] != id;
        setState(() {
          _record = Map<String, dynamic>.from(answer.data['record'] as Map);
          _currency = _record!['currency'] as String;
          _zone = _record!['timeZone'] as String;
          _mode = 'opening';
          _busy = answer.saved;
          if (first || !answer.saved) {
            _fields['reason']!.clear();
            _fields['amount']!.clear();
          }
        });
      }
      if (mounted && generation == _generation && !_busy) await _edit();
    } catch (_) {
      if (mounted && generation == _generation) _deny();
    }
  }

  Future<void> _refreshPaymentRecord() async {
    final id = _record?['id'];
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final result = await widget.service.bookingWorkspace({
        ..._identity,
        'action': 'read',
        'bookingId': id,
      });
      if (!mounted || _record?['id'] != id) return;
      setState(() {
        _record = Map<String, dynamic>.from(result['record'] as Map);
        _quoteInputKey = null;
      });
    } catch (_) {
      if (mounted) _deny();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Rooms that take short stays, staff, receiving accounts and what the
  /// person may do with prices and ID numbers.
  Future<void> _loadOptions() async {
    final org = widget.organizationId, building = widget.buildingId;
    // Speed (2026-10-09): the options shown last time open the form at once;
    // the server's answer replaces them a moment later. An access refusal
    // then closes the form like before.
    final saved = widget.service.savedBookingOptions(org, building);
    if (saved != null) {
      _applyOptions(saved);
      final generation = _generation;
      widget.service
          .bookingOptions(org, building)
          .then(
            (fresh) {
              if (mounted) setState(() => _applyOptions(fresh));
            },
            onError: (Object e) {
              // Also when the refusal arrives before the form has finished
              // opening: the newer generation stops that opening.
              if (mounted &&
                  generation == _generation &&
                  ReadCache.isAccessError(e)) {
                _generation++;
                _deny();
              }
            },
          );
      return;
    }
    _applyOptions(await widget.service.bookingOptions(org, building));
  }

  void _applyOptions(Map<String, dynamic> r) {
    List<Map<String, dynamic>> list(Object? v) => v is List
        ? v.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    // A newer answer must not drop what the form already shows as chosen
    // (a staff member who left, a receiving account removed meanwhile).
    List<Map<String, dynamic>> keeping(
      List<Map<String, dynamic>> fresh,
      List<Map<String, dynamic>> old,
      String? chosen,
    ) => chosen == null || fresh.any((v) => v['id'] == chosen)
        ? fresh
        : [...fresh, ...old.where((v) => v['id'] == chosen)];
    _hourTemplates = list(r['hourTemplates']);
    _templateCurrency = r['priceListCurrency'] as String? ?? 'VND';
    _rooms = list(r['records']);
    _staff = keeping(list(r['staff']), _staff, _staffId);
    _accounts = keeping(list(r['accounts']), _accounts, _account);
    _zone = r['timeZone'] as String? ?? _zone;
    _canPrice = r['canPrice'] == true;
    _canSavePrices = r['canSavePrices'] == true;
    _canCollect = r['canCollect'] == true;
    _today = r['today'] as String? ?? _today;
    _canReadIds = r['canReadGuestIds'] == true;
    _payMethods = list(r['paymentMethods']);
    _myStaffId = r['myStaffId'] as String?;
    _canRefundOpt = r['canRefund'] == true;
    _canEditPayments = r['canEditPayments'] == true;
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
          // A two-hour slot on the calendar in a room priced only per night
          // (2026-10-14, Tom: the form opened with a price error): one night,
          // checking out the next day at 12:00.
          final start = _parseLocal(_fields['startLocal']!.text);
          if (_pricing == 'nightly' && _nightCount == null && start != null) {
            _fields['endLocal']!.text = _formatLocal(
              DateTime.utc(start.year, start.month, start.day + 1, 12),
            );
          }
        }
        // Payments (2026-10-24, Tom): a new booking's list starts empty; a
        // saved booking's list is read again.
        _drafts = [];
        _paymentRows = [];
        _paymentsToken++;
        _stay = switch (r?['status']) {
          'checkedIn' => 'checkedIn',
          'checkedOut' => 'checkedOut',
          _ => 'notCheckedIn',
        };
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
        _setHourPrices(
          (r?['hourPrices'] as List? ?? [])
              .map((v) => ((v as num) * _scale).round())
              .toList(),
        );
        final nights = (r?['nightPrices'] as List?)?.cast<num>();
        // Without "Đổi giá" too, when every night is a price that can be
        // picked (2026-10-09, Tom).
        _customNights = true;
        if (nights != null && nights.isNotEmpty) {
          _nightPrices.addAll(
            nights.map((v) {
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
        _syncNights();
        // An agreed price stays on the booking until changed (Fix 5).
        final agreed = _agreedOn(r);
        if (agreed != null) {
          _conversion.set(
            _fields['agreedPrice']!,
            ((agreed['total'] as num) * _scale).round(),
            _currency,
          );
          _fields['agreedReason']!.text = '${agreed['reason'] ?? ''}';
        } else {
          _fields['agreedPrice']!.clear();
          _fields['agreedReason']!.clear();
        }
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
      final stored = (_record?['nightPrices'] as List?)
          ?.map((v) => ((v as num) * _scale).round())
          .toList();
      final keepsStored =
          stored != null && jsonEncode(stored) == jsonEncode(list);
      final usesRoom =
          _record == null && list.every((v) => v == _roomNightMinor);
      // Omitting unchanged prices preserves historical rates and lets the
      // server apply converted room rates without granting override rights.
      if (_canPrice || !keepsStored && !usesRoom)
        out['nightPricesMinor'] = list;
    } else if (_pricing == 'nightly') {
      // Same price every night: people with "Đổi giá" send it; others get the
      // room's price (or keep the booking's) on the server.
      // A saved price of the room may be picked without "Đổi giá"
      // (2026-10-09, Tom).
      final n = _nightCount;
      final saved =
          unit != null &&
          unit != _roomNightMinor &&
          _priceOptions.contains(unit);
      if ((_canPrice || saved) && n != null) {
        if (unit == null || unit <= 0) return null;
        out['nightPricesMinor'] = List<int>.filled(n, unit);
      }
    } else if (_pricing == 'hourly') {
      if (_hourPrices.isNotEmpty) {
        final prices = _hourValues;
        if (prices == null) return null;
        out['hourPricesMinor'] = prices;
      } else if (_oldFlatHourly) {
        // An older booking keeps its own price per hour (changing it needs
        // "Đổi giá"; the box is locked without it).
        if (unit == null || unit <= 0) return null;
        out['hourlyPriceMinor'] = unit;
      } else {
        return null; // pick a template first ('hourTemplateNeeded')
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
    // An agreed room price (Fix 5, 2026-10-09, Tom). Unchanged, it is left
    // out and the server keeps it with who agreed it; switched off, null goes
    // back to the calculated price.
    final had = _agreedOn(_record);
    // The same as the calculated total is no change of price (2026-10-14,
    // Tom): no agreed price, no reason needed.
    if (_canPrice && _agreed && _agreedIsCalculated) {
      if (had != null) out['overrideMinor'] = null;
    } else if (_canPrice && _agreed) {
      final value = _conversion.parse(_fields['agreedPrice']!, _currency);
      final why = _fields['agreedReason']!.text.trim();
      if (value == null || value <= 0 || why.isEmpty) return null;
      final same =
          had != null &&
          ((had['total'] as num) * _scale).round() == value &&
          '${had['reason'] ?? ''}' == why;
      if (!same) {
        out['overrideMinor'] = value;
        out['overrideReason'] = why;
      }
    }
    return out;
  }

  /// Why there is no total yet. Red only for something typed that cannot be
  /// used; empty or not yet filled prices just wait (2026-10-14, Tom: a new
  /// booking opened with "fill in every price line" in red).
  String _missingReason() {
    if (_room == null || _nightCount == null && _hours == null) {
      return 'calculationWaiting';
    }
    if (_pricing == 'nightly' && _nightCount == null) return 'nightNeedsDay';
    if (_pricing == 'hourly' && _hourPrices.isEmpty && !_oldFlatHourly) {
      return 'hourTemplateNeeded';
    }
    bool bad(TextEditingController c) =>
        c.text.trim().isNotEmpty && (_conversion.parse(c, _currency) ?? 0) <= 0;
    for (final row in _charges) {
      final label = row.label.text.trim(), amount = row.amount.text.trim();
      if (label.isEmpty && amount.isEmpty) continue;
      if (label.isEmpty || amount.isEmpty || bad(row.amount)) {
        return 'priceRows';
      }
    }
    if (_pricing == 'nightly' && _customNights) {
      if (_nightPrices.any(bad)) return 'priceRows';
    } else if (bad(_fields['unitPrice']!)) {
      return 'priceRows';
    }
    if (_canPrice && _agreed) {
      final price = _fields['agreedPrice']!;
      if (bad(price)) return 'priceRows';
      if (price.text.trim().isEmpty ||
          !_agreedIsCalculated &&
              _fields['agreedReason']!.text.trim().isEmpty) {
        return 'agreedNeeded';
      }
    }
    return 'pricesWaiting';
  }

  /// The agreed box holds exactly the calculated total: not a price change.
  bool get _agreedIsCalculated {
    final value = _conversion.parse(_fields['agreedPrice']!, _currency);
    if (value == null) return false;
    final q = _quote;
    final calculated =
        _localTotalMinor() ??
        ((q?['calculatedMinor'] ?? q?['totalMinor']) as num?)?.round();
    return calculated != null && value == calculated;
  }

  /// Room price and surcharges worked out from the form itself.
  int? _localTotalMinor() {
    final room = _estimateMinor();
    if (room == null) return null;
    var extra = 0;
    for (final row in _charges) {
      final minor = _conversion.parse(row.amount, _currency);
      if (minor == null || minor <= 0) continue;
      extra += row.basis == 'person' ? minor * _guestCount : minor;
    }
    return room + extra;
  }

  /// The booking's agreed price, when it has one.
  static Map<String, dynamic>? _agreedOn(Map<String, dynamic>? r) {
    final o = r?['priceOverride'];
    return o is Map && o['total'] is num ? Map<String, dynamic>.from(o) : null;
  }

  /// The room price the form works out (nights × price, or hours × price).
  int? _estimateMinor() {
    final unit = _conversion.parse(_fields['unitPrice']!, _currency);
    if (_pricing == 'hourly') {
      final h = _hours;
      if (_hourPrices.isNotEmpty) {
        final prices = _hourValues;
        if (h == null || prices == null) return null;
        var left = h, total = 0.0;
        for (final price in prices) {
          final portion = left.clamp(0.0, 1.0);
          total += portion * price;
          left -= portion;
        }
        return (total + left * prices.last).round();
      }
      return h == null || unit == null || unit <= 0 ? null : (unit * h).round();
    }
    final n = _nightCount;
    if (n == null) return null;
    if (_customNights) {
      final list = [
        for (final c in _nightPrices) _conversion.parse(c, _currency),
      ];
      if (list.length != n || list.any((v) => v == null || v <= 0)) return null;
      return list.fold<int>(0, (a, b) => a + b!);
    }
    return unit == null || unit <= 0 ? null : unit * n;
  }

  Map<String, dynamic>? _quoteInput() {
    if (_room == null ||
        _hours == null ||
        _pricing == 'nightly' && _nightCount == null)
      return null;
    final price = _pricePayload();
    if (price == null) return null;
    return {
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
    };
  }

  // A quote belongs to exactly one set of inputs. Editing invalidates it
  // immediately; an older network response must never re-enable Save.
  void _scheduleQuote() {
    if (_mode != 'edit' || _locked || !_canEditRecord || _command != null)
      return;
    final input = _quoteInput();
    final key = jsonEncode([
      _generation,
      input,
      [for (final d in _drafts) draftPayload(d)],
      // Without a request, what is missing can still change (e.g. switching
      // to per hour: "pick a template"), so the message must follow it.
      if (input == null) _missingReason(),
    ]);
    if (key == _quoteInputKey) return;
    _quoteInputKey = key;
    final version = ++_quoteVersion;
    _quoteTimer?.cancel();
    _quote = null;
    _quoting = input != null;
    _quoteFailed = false;
    _calculationMessage = input == null ? _missingReason() : null;
    if (input != null) {
      final generation = _generation;
      _quoteTimer = Timer(
        const Duration(milliseconds: 350),
        () => _review(input, version, generation),
      );
    }
  }

  Future<void> _review(
    Map<String, dynamic> input,
    int version,
    int generation,
  ) async {
    bool current() =>
        mounted &&
        generation == _generation &&
        version == _quoteVersion &&
        _mode == 'edit' &&
        _pending == null;
    if (!current()) return;
    try {
      final r = await widget.service.bookingWorkspace(input);
      if (!current()) return;
      final quote = Map<String, dynamic>.from(r['record'] as Map);
      final paid = (((_record?['paidAmount'] as num?) ?? 0) * _scale).round();
      final total = ((quote['totalMinor'] as num?) ?? 0).round();
      // Paid already (or payments added to this new booking) more than the
      // new total: the price must stay at least that (2026-10-24).
      if (paid > total ||
          settleDrafts(
            _drafts,
            total,
          ).any((d) => (d['recordedMinor'] as int) <= 0)) {
        setState(() {
          _quoting = false;
          _calculationMessage = 'paymentTooLarge';
        });
        return;
      }
      setState(() {
        _quote = quote;
        _currency = _quote!['currency'] as String;
        _quoting = false;
      });
    } catch (e) {
      if (current()) {
        setState(() {
          _quoting = false;
          _quote = null;
          _calculationMessage = _quoteProblem(e);
          _quoteFailed = true;
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
      'booking_hour_template_required',
    ])) {
      'booking_hour_template_required' => 'hourTemplateNeeded',
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
    'booking_hour_template_required': 'hourTemplateNeeded',
    'booking_invalid_dates': 'badDates',
    'booking_deposit_too_large': 'depositTooLarge',
    'booking_deposit_date': 'depositBadDate',
    'booking_payment_date': 'depositBadDate',
    'booking_payment_too_large': 'paymentTooLarge',
    'booking_nothing_owed': 'paymentTooLarge',
    'booking_payment_balance': 'paymentTooLarge',
    'booking_method_invalid': 'paymentProblem',
    'booking_deposit_recorded': 'changedAgain',
  };

  Future<void> _save() async {
    if (_pending == null) {
      if (_mode == 'edit' && _command == null) {
        _scheduleQuote();
        if (_quote == null || _quoting) return;
      }
      if (!_form.currentState!.validate()) return;
      if (_mode == 'edit' && _command == null) {
        final price = _pricePayload();
        if (price == null) {
          setState(() => _message = 'priceRows');
          return;
        }
        // The deposit asked for (older bookings) is kept as it is; payments
        // are the payment list's (2026-10-24, Tom).
        final asked =
            (((_record?['depositAmount'] as num?) ?? 0) * _scale).round();
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
          'stayStatus': _stay,
          if (_record == null && _drafts.isNotEmpty)
            'receipts': [for (final d in _drafts) draftPayload(d)],
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
      final wasCommand = _pending?['action'] == 'command';
      _pending = null;
      if (wasCommand) {
        await _refreshPaymentRecord();
        if (mounted)
          setState(() {
            _command = null;
            _status = null;
            _stay = switch (_record?['status']) {
              'checkedIn' => 'checkedIn',
              'checkedOut' => 'checkedOut',
              _ => 'notCheckedIn',
            };
          });
      } else {
        await _read(r['id'] as String);
      }
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
    bool readOnly = false,
    bool labelAbove = false,
    ValueChanged<String>? onChanged,
  }) => Semantics(
    label: label,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (labelAbove) _label(context, label),
        TextFormField(
          key: ValueKey('ops-$key'),
          controller: controller ?? _fields[key],
          enabled: _formEnabled && enabled,
          readOnly: readOnly,
          onChanged: onChanged,
          keyboardType: keyboard,
          inputFormatters: formatters,
          maxLines: maxLines,
          decoration: InputDecoration(
            labelText: labelAbove ? null : label,
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
      ],
    ),
  );

  /// The chosen room's number; a saved booking whose room is no longer in
  /// the list still shows its own.
  String? get _chosenRoomNumber {
    final number =
        _rooms.where((v) => v['id'] == _room).firstOrNull?['roomNumber'] ??
        _record?['roomNumber'];
    return number == null ? null : '$number';
  }

  Future<void> _pickRoom() async {
    final id = await showRoomPicker(
      context,
      keyPrefix: 'booking-room',
      selectedId: _room,
      rooms: [
        for (final room in _rooms)
          RoomChoice(room['id'] as String, '${room['roomNumber']}'),
      ],
    );
    // The form may have been locked or reloaded while the list was open.
    final room = _rooms.where((v) => v['id'] == id).firstOrNull;
    if (!mounted || room == null || id == _room || !_formEnabled) return;
    if (_record != null) return;
    setState(() {
      _room = id;
      _currency = _conversion.currency(room['currency'] as String? ?? 'VND');
      _setHourPrices([]);
      _resetUnit();
      _autoPick();
      _retired.addAll(_nightPrices);
      _nightPrices.clear();
      _syncNights();
    });
    // A calendar dialog titled "Phòng …" follows the new room.
    RoomTitleScope.report(context, '${room['roomNumber']}');
  }

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
    _scheduleQuote();
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
            // 2026-10-22 (Tom): only the chosen room; tapping it lists the
            // other rooms. A saved booking keeps its room (as before).
            RoomPickerField(
              fieldKey: 'booking-room',
              value: _chosenRoomNumber,
              onPick: !_formEnabled || editing ? null : _pickRoom,
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
          // The stay status, chosen by staff and changed later by them, never
          // by the clock (2026-10-14, Tom). "Đã đặt cọc" is the deposit tick.
          const SizedBox(height: WsSpace.md),
          _label(context, bt('stayHeading')),
          if (['cancelled', 'noShow'].contains(_record?['status']))
            _statusPill(context, _record!)
          else
            Wrap(
              spacing: WsSpace.sm,
              runSpacing: WsSpace.sm,
              children: [
                for (final (value, label) in [
                  ('notCheckedIn', bt('stayNotIn')),
                  ('checkedIn', bt('stayIn')),
                  ('checkedOut', bt('stayOut')),
                ])
                  _choice(
                    label,
                    value,
                    _stay,
                    _formEnabled ? (v) => setState(() => _stay = v) : null,
                    key: ValueKey('booking-stay-$value'),
                  ),
              ],
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
                          _setHourPrices([]);
                          _resetUnit();
                          _syncNights();
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
              if (!(_pricing == 'nightly' && _customNights) &&
                  !(_pricing == 'hourly' && !_oldFlatHourly))
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
          if (_pricing == 'hourly') _hourPricingEditor(),
          if (_pricing == 'nightly' &&
              !_customNights &&
              (_priceOptions.isNotEmpty || _canSavePrices && _savedPricesApply))
            _savedPriceChips(context),
          if (_pricing == 'nightly') ...[
            if (_customNights &&
                (_priceOptions.isNotEmpty ||
                    _canSavePrices && _savedPricesApply))
              _savedPriceChips(context, allNights: true),
            if (_customNights && _nightPrices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: WsSpace.md),
                child: Wrap(
                  spacing: WsSpace.sm,
                  runSpacing: WsSpace.md,
                  children: [
                    for (final (i, c) in _nightPrices.indexed)
                      SizedBox(
                        width: 170,
                        child: _input(
                          'night-$i',
                          bt('night').replaceAll('{n}', '${i + 1}'),
                          controller: c,
                          keyboard: money,
                          formatters: appMoneyInput(_inputCurrency),
                          required: true,
                          check: moneyCheck,
                          // Without "Đổi giá": picked from the list, not typed.
                          readOnly: !_canPrice,
                          suffix: _nightMenu(i, c),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                  ],
                ),
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
      WsSection(
        key: const ValueKey('booking-payment'),
        title: bt('paymentSection'),
        icon: Icons.payments_outlined,
        children: [
          // 2026-10-24 (Tom): the payments made so far and "Thêm lần thanh
          // toán" (booking_payments.dart), then the total.
          BookingPayments(
            key: ValueKey('booking-payments-${_record?['id'] ?? 'new'}'),
            service: widget.service,
            organizationId: widget.organizationId,
            buildingId: widget.buildingId,
            bookingId: _record?['id'] as String?,
            currency: _currency,
            conversion: _conversion,
            options: BookingPaymentOptions(
              staff: _staff,
              accounts: _accounts,
              methods: _payMethods,
              myStaffId: _myStaffId,
              today: _today,
              canCollect: _canCollect,
              canRefund: _canRefundOpt,
              canEdit: _canEditPayments,
            ),
            totalMinor: (_quote?['totalMinor'] as num?)?.round(),
            drafts: _drafts,
            onDraftsChanged: (list) => setState(() {
              _drafts = list;
              _message = null;
            }),
            onSaved: _refreshPaymentRecord,
            onMethodsChanged: (list) => setState(() => _payMethods = list),
            reloadToken: _paymentsToken,
            onRows: (rows) => setState(() => _paymentRows = rows),
            enabled: !_locked,
            bookingStatus: _record?['status'] as String?,
          ),
          if (_agreedOn(_record) != null)
            WsInfo(bt('agreedBy'), '${_agreedOn(_record)!['byName'] ?? ''}'),
          const SizedBox(height: WsSpace.md),
          if (_quoting) ...[
            Text(bt('calculationUpdating')),
            const LinearProgressIndicator(),
          ],
          if (_quote != null) _quoteCard(context),
          if (!_canEditRecord && _record != null) ...[
            WsInfo(
              opsText(context, 'total'),
              _money(_record!['totalPrice'] as num?),
            ),
            WsInfo(
              opsText(context, 'paid'),
              _money(_record!['paidAmount'] as num?),
            ),
          ],
          if (_calculationMessage != null)
            Text(
              bt(_calculationMessage!),
              key: const ValueKey('booking-calculation-message'),
              style:
                  const {
                    'calculationWaiting',
                    'pricesWaiting',
                    'agreedNeeded',
                    'nightNeedsDay',
                  }.contains(_calculationMessage)
                  ? muted
                  : error,
            ),
          if (_quoteFailed && !_quoting && _quote == null)
            TextButton.icon(
              onPressed: _locked
                  ? null
                  : () => setState(() => _quoteInputKey = null),
              icon: const Icon(Icons.refresh),
              label: Text(bt('retryCalculation')),
            ),
        ],
      ),
      if (_record?['roomId'] is String)
        RoomProblemsSection(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          roomId: _record!['roomId'] as String,
          roomLabel: _roomTitleFor(_record!),
          service: widget.service,
        ),
      if (_record != null) ..._savedActions(context, _record!),
      // Shown next to the buttons: a message at the top is off screen on phones.
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: WsSpace.md),
          child: Text(
            bt(_message!),
            key: const ValueKey('booking-form-message'),
            style: _message == 'saved'
                ? TextStyle(color: wsToneColor(context, WsTone.good))
                : error,
          ),
        ),
      WsActions(
        children: [
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _record == null
                      ? _list()
                      : _read(_record!['id'] as String),
            child: Text(bt('cancel')),
          ),
          FilledButton(
            onPressed: !_formEnabled || _quote == null || _quoting
                ? null
                : _save,
            child: Text(opsText(context, 'confirm')),
          ),
        ],
      ),
    ];
  }

  /// A label and its amount. [struck]: the calculated total crossed out
  /// before an agreed one (2026-10-14, Tom).
  Widget _paymentLine(
    String label,
    String value, {
    bool emphasis = false,
    String? struck,
  }) => Padding(
    padding: const EdgeInsets.only(top: WsSpace.xs),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final style = emphasis
            ? theme.textTheme.titleMedium
            : theme.textTheme.bodyMedium;
        final labelText = Text(label, style: style);
        final Widget valueText = struck == null
            ? Text(value, style: style)
            : Wrap(
                spacing: WsSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    struck,
                    key: const ValueKey('booking-quote-calculated'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  Text(value, style: style),
                ],
              );
        if (constraints.maxWidth <
            420 * MediaQuery.textScalerOf(context).scale(14) / 14) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelText,
              const SizedBox(height: WsSpace.xs),
              valueText,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: labelText),
            const SizedBox(width: WsSpace.md),
            Flexible(child: valueText),
          ],
        );
      },
    ),
  );

  Widget _label(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: WsSpace.sm),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );

  /// The building's saved nightly prices as chips (2026-10-09, Tom), with
  /// the room's own price. A tap fills the price box, or with "Giá khác nhau
  /// mỗi đêm" every night. With "Lưu giá phòng" the price in the box (or
  /// every night's new price) can be saved and a saved one removed (its ×).
  Widget _savedPriceChips(BuildContext context, {bool allNights = false}) {
    final saved = _savedNights.toSet();
    final options = _priceOptions;
    final enabled = _formEnabled && !_savingPrice;
    final unit = _conversion.parse(_fields['unitPrice']!, _currency);
    final nights = [
      for (final c in _nightPrices) _conversion.parse(c, _currency),
    ];
    bool chosen(int v) => allNights
        ? nights.isNotEmpty && nights.every((n) => n == v)
        : unit == v;
    final toSave = allNights
        ? _newNightPrices
        : [
            if (unit != null &&
                unit > 0 &&
                unit <= 1000000000000 &&
                !options.contains(unit))
              unit,
          ];
    return Padding(
      padding: const EdgeInsets.only(top: WsSpace.md),
      child: Wrap(
        key: ValueKey(
          allNights ? 'booking-saved-prices-nights' : 'booking-saved-prices',
        ),
        spacing: WsSpace.sm,
        runSpacing: WsSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (options.isNotEmpty)
            Text(
              '${bt('savedPrices')}:',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          for (final v in options)
            InputChip(
              key: ValueKey(
                '${allNights ? 'booking-all-nights-price' : 'booking-saved-price'}-$v',
              ),
              label: Text(appMoneyMinor(v, _currency), maxLines: 1),
              selected: chosen(v),
              showCheckmark: false,
              onPressed: enabled
                  ? () => allNights ? _pickSavedForAll(v) : _pickSaved(v)
                  : null,
              // The room's own price is not in the list: nothing to remove.
              onDeleted: _canSavePrices && enabled && saved.contains(v)
                  ? () => _savePrice(v, remove: true)
                  : null,
              deleteButtonTooltipMessage: bt('removePrice'),
            ),
          if (_canSavePrices && _savedPricesApply)
            ActionChip(
              key: ValueKey(
                allNights ? 'booking-save-night-prices' : 'booking-save-price',
              ),
              avatar: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: Text(bt('savePrice'), maxLines: 1),
              onPressed: enabled && toSave.isNotEmpty
                  ? () => _savePrices(toSave)
                  : null,
            ),
        ],
      ),
    );
  }

  /// A night's ▾: the saved prices for that night, and "Lưu giá này" for a
  /// typed price that is not saved yet (2026-10-09, Tom).
  Widget? _nightMenu(int i, TextEditingController c) {
    final options = _priceOptions;
    final value = _conversion.parse(c, _currency);
    final canSave =
        _canSavePrices &&
        _savedPricesApply &&
        value != null &&
        value > 0 &&
        value <= 1000000000000 &&
        !options.contains(value);
    if (options.isEmpty && !canSave) return null;
    return PopupMenuButton<int>(
      key: ValueKey('booking-night-menu-$i'),
      tooltip: bt('pickPrice'),
      enabled: _formEnabled && !_savingPrice,
      icon: const Icon(Icons.arrow_drop_down),
      onSelected: (v) {
        if (v < 0) {
          if (value != null) _savePrice(value);
          return;
        }
        setState(() {
          _conversion.set(c, v, _currency);
          _message = null;
        });
      },
      itemBuilder: (_) => [
        for (final v in options)
          PopupMenuItem<int>(
            key: ValueKey('booking-night-$i-price-$v'),
            value: v,
            child: Text(appMoneyMinor(v, _currency)),
          ),
        if (canSave)
          PopupMenuItem<int>(
            key: ValueKey('booking-night-$i-save'),
            value: -1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bookmark_add_outlined, size: 18),
                const SizedBox(width: WsSpace.sm),
                Text(bt('saveThisPrice')),
              ],
            ),
          ),
      ],
    );
  }

  /// The room price line (2026-10-14, Tom: × instead of ·):
  /// "300,000 VND × 1 đêm", "300,000 VND × 2 đêm = 600,000 VND",
  /// "650,000 VND (2 đêm)" when the nights have different prices.
  String _roomLine(Map q) {
    num units(Object? minor) => (minor as num? ?? 0) / _scale;
    final base = q['baseMinor'] ?? q['totalMinor'];
    final nights = q['nights'] as int?;
    if (q['pricingType'] == 'nightly' && nights != null && nights > 0) {
      final list = (q['nightPricesMinor'] as List?)?.cast<num>();
      final same =
          list != null &&
          list.length == nights &&
          list.every((v) => v == list.first);
      if (!same) return '${_money(units(base))} (${_nightsLabel(nights)})';
      final each = '${_money(units(list!.first))} × ${_nightsLabel(nights)}';
      return nights == 1 ? each : '$each = ${_money(units(base))}';
    }
    final h = _hours;
    if (q['pricingType'] == 'hourly' &&
        q['hourlyPriceMinor'] is num &&
        h != null) {
      final hours = bt(
        'hoursCount',
      ).replaceAll('{n}', appQuantity(h, decimals: 2));
      return '${_money(units(q['hourlyPriceMinor']))} × $hours = ${_money(units(base))}';
    }
    return _money(units(base));
  }

  Widget _quoteCard(BuildContext context) {
    final q = _quote!;
    final theme = Theme.of(context);
    num units(Object? minor) => (minor as num? ?? 0) / _scale;
    // An agreed price is the whole total (2026-10-14, Tom): the room price
    // and surcharges as calculated, then the total with the calculated one
    // crossed out and the reason next to it: "~~300,000~~ 250,000 (lý do)".
    final agreed = q['agreedMinor'] as num?;
    final reason = '${q['agreedReason'] ?? ''}'.trim();
    final calculated = (q['calculatedMinor'] as num?) ?? agreed;
    final total = (q['totalMinor'] as num?) ?? 0,
        paid = (((_record?['paidAmount'] as num?) ?? 0) * _scale).round(),
        // Payments added to a new booking before saving (2026-10-24).
        drafts = _record != null
            ? 0
            : settleDrafts(
                _drafts,
                (q['totalMinor'] as num?)?.round(),
              ).fold<int>(0, (a, d) => a + (d['recordedMinor'] as int));
    final rows = _record != null
        ? _paymentRows
        : settleDrafts(_drafts, (q['totalMinor'] as num?)?.round());
    // Listed one by one only when the list adds up to what was paid.
    final itemized =
        rows.isNotEmpty &&
        rows.fold<int>(
              0,
              (a, r) => a + paidEffect(r, draft: _record == null),
            ) ==
            (_record != null ? paid : drafts);
    return Card(
      key: const ValueKey('booking-quote'),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(WsSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _paymentLine(bt('roomPrice'), _roomLine(q)),
            for (final l
                in (q['surchargeLines'] as List? ?? const []).cast<Map>())
              _paymentLine(
                '+ ${l['label']}',
                l['basis'] == 'person'
                    ? bt('perPersonLine')
                          .replaceAll('{p}', _money(units(l['unitMinor'])))
                          .replaceAll('{n}', '${l['count']}')
                          .replaceAll('{t}', _money(units(l['totalMinor'])))
                    : _money(units(l['totalMinor'])),
              ),
            const Divider(height: WsSpace.lg),
            _paymentLine(
              opsText(context, 'total'),
              '${_money(units(q['totalMinor']))}'
              '${agreed != null && reason.isNotEmpty ? ' ($reason)' : ''}',
              emphasis: true,
              struck: agreed != null && calculated != agreed
                  ? _money(units(calculated))
                  : null,
            ),
            // The deposit (and anything paid before) is taken off the total.
            // Taken off, lined up under the total.
            // Each payment listed (2026-10-24, Tom): "1 · Tiền cọc − 200,000",
            // "2 · Hoàn tiền cọc + 50,000". Older amounts the list does not
            // explain stay as one "Đã thanh toán" line.
            if (itemized)
              for (final (i, r) in rows.indexed)
                _paymentLine(
                  '${i + 1} · ${paymentKindLabel(context, r['kind'] as String?, r['refundFrom'] as String?)}',
                  '${paidEffect(r, draft: _record == null) < 0 ? '+' : '−'} '
                  '${_money(units(paidEffect(r, draft: _record == null).abs()))}',
                )
            else ...[
              if (paid > 0)
                _paymentLine(bt('alreadyPaid'), '− ${_money(units(paid))}'),
              if (drafts > 0)
                _paymentLine(bt('alreadyPaid'), '− ${_money(units(drafts))}'),
            ],
            if (paid > 0 || drafts > 0)
              KeyedSubtree(
                key: const ValueKey('booking-quote-remaining'),
                child: _paymentLine(
                  bt('remaining'),
                  _money(units(total - paid - drafts)),
                  emphasis: true,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _savedActions(BuildContext context, Map<String, dynamic> r) {
    final active = ['pending', 'confirmed', 'checkedIn'].contains(r['status']);
    final manage = r['canManage'] == true;
    return [
      const SizedBox(height: WsSpace.md),
      _inlineAction(
        'checkout',
        bt('checkoutShort'),
        'checkoutReason',
        manage && r['status'] == 'checkedIn',
      ),
      const SizedBox(height: WsSpace.sm),
      _inlineAction(
        'cancel',
        opsText(context, 'cancelled'),
        'cancelReason',
        manage && active,
      ),
      // Refunds are a payment type now (2026-10-24, Tom): "Thêm lần thanh
      // toán" → Hoàn tiền.
    ];
  }

  Widget _inlineAction(
    String action,
    String title,
    String reasonField,
    bool allowed,
  ) {
    final enabled = allowed && !_locked;
    final refund = action == 'refund-rent';
    return WsSection(
      key: ValueKey('booking-$action-section'),
      title: title,
      icon: refund ? Icons.receipt_long_outlined : Icons.event_outlined,
      children: [
        Text(
          opsText(context, 'reviewWarning'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: WsSpace.md),
        TextFormField(
          key: ValueKey('booking-$action-reason'),
          controller: _fields[reasonField],
          enabled: enabled,
          maxLength: 1000,
          decoration: InputDecoration(labelText: opsText(context, 'reason')),
        ),
        if (refund) ...[
          const SizedBox(height: WsSpace.md),
          TextFormField(
            key: const ValueKey('booking-refund-rent-amount'),
            controller: _fields['refundAmount'],
            enabled: enabled,
            keyboardType: TextInputType.numberWithOptions(
              decimal: _currency == 'USD',
            ),
            inputFormatters: appMoneyInput(_currency),
            decoration: InputDecoration(
              labelText: opsText(context, 'amount'),
              suffixText: _currency,
            ),
          ),
          const SizedBox(height: WsSpace.md),
          Wrap(
            spacing: WsSpace.sm,
            runSpacing: WsSpace.sm,
            children: [
              for (final choice in <(String, String)>[
                ('cash', opsText(context, 'cash')),
                for (final a in _accounts) ('${a['id']}', '${a['label']}'),
                if (_accounts.isEmpty) ('transfer', bt('otherTransfer')),
              ])
                ChoiceChip(
                  key: ValueKey('booking-refund-account-${choice.$1}'),
                  label: Text(choice.$2),
                  selected: _refundAccount == choice.$1,
                  onSelected: enabled
                      ? (_) => setState(() => _refundAccount = choice.$1)
                      : null,
                ),
            ],
          ),
        ],
        if (_actionErrors[action] != null)
          Text(
            bt(_actionErrors[action]!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        WsActions(
          children: [
            OutlinedButton(
              key: ValueKey('booking-$action'),
              onPressed: enabled
                  ? () => _submitInlineAction(action, reasonField)
                  : null,
              child: Text(title),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _submitInlineAction(String action, String reasonField) async {
    if (_locked || _record == null) return;
    final reason = _fields[reasonField]!.text.trim();
    final refund = action == 'refund-rent';
    final amount = refund
        ? appParseMoney(_fields['refundAmount']!.text, _currency)
        : null;
    if (reason.isEmpty ||
        reason.length > 1000 ||
        (refund && (amount == null || amount <= 0))) {
      setState(() => _actionErrors[action] = 'required');
      return;
    }
    if (refund &&
        amount! > ((_record!['paidAmount'] as num? ?? 0) * _scale).round()) {
      setState(() => _actionErrors[action] = 'refundTooLarge');
      return;
    }
    setState(() {
      _actionErrors.remove(action);
      _message = null;
      _pending = {
        ..._identity,
        'action': 'command',
        'bookingId': _record!['id'],
        'revision': _record!['revision'],
        'operationId': const Uuid().v4(),
        'command': refund ? 'refundRent' : 'status',
        if (!refund)
          'status': action == 'checkout' ? 'checkedOut' : 'cancelled',
        'reason': reason,
        if (refund) ...{
          'amountMinor': amount,
          'paymentMethod': _refundAccount == 'cash' ? 'cash' : 'bankTransfer',
          if (_refundAccount != 'transfer') 'accountId': _refundAccount,
        },
      };
    });
    // Reuse the journal/revision/retry path without validating unrelated drafts.
    await _save();
    if (mounted && _message == 'saved') {
      _fields[reasonField]!.clear();
      if (refund) _fields['refundAmount']!.clear();
    }
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
    _reportRecord(r?['id'] as String?);
    return BackStep(
      enabled: _mode != 'list',
      onBack: () {
        if (!_locked) _list();
      },
      child: opsPage(context, [
        Form(
          key: _form,
          onChanged: () {
            if (mounted) setState(() {});
          },
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
              if (_message != null &&
                  (_mode != 'edit' || _pending != null) &&
                  _command == null)
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
              if (_mode == 'edit' && _pending == null)
                if (_command == null)
                  ..._editForm(context)
                else
                  _commandCard(context),
              // Opened from the calendar: what it already shows, until the
              // booking itself is here (2026-10-09, speed).
              if (r == null &&
                  _busy &&
                  _pending == null &&
                  widget.initialRecordId != null &&
                  (widget.preview?.isNotEmpty ?? false))
                WsSection(
                  key: const ValueKey('booking-preview'),
                  title: widget.preview!.first,
                  icon: Icons.nights_stay_outlined,
                  children: [
                    for (final line in widget.preview!.skip(1))
                      Text(line, style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
            ],
          ),
        ),
      ]),
    );
  }
}
