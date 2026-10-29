import '../../utils/money_conversion.dart';
import '../../services/organization_money.dart';
import 'dart:convert' show base64Encode;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../services/read_cache.dart' show Saved;
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'property_contract_screen.dart' show contractDate;
import 'room_rates_screen.dart' show parseRoomRate;
import 'lease_surcharges.dart';
import 'room_picker.dart';
import 'problem_photos.dart'
    show PickedPhoto, photoType, pickProblemPhotos, maxPhotoBytes;
import 'utility_readings_screen.dart' show meterMilli;
import 'workspace_page_scope.dart';
import 'ws_ui.dart';

/// Lease-form wording added with B3. Older keys stay in AppTranslations.
String _leaseText(BuildContext context, String key) {
  final vi = AppTranslations.of(context).locale.languageCode == 'vi';
  const labels = <String, List<String>>{
    'secRoom': ['Room', 'Phòng'],
    'moveIn': ['Move-in', 'Ngày dọn vào'],
    'done': ['Done', 'Xong'],
    'secMain': [
      'Main tenant (on the contract)',
      'Người thuê chính (đứng tên hợp đồng)',
    ],
    'secCo': ['People living with them', 'Người ở cùng'],
    'secContract': ['Contract and payment', 'Hợp đồng và thanh toán'],
    'secDeposit': ['Deposit', 'Tiền cọc'],
    'paymentSection': ['Payment', 'Thanh toán'],
    'secStaff': ['Staff in charge', 'Nhân viên phụ trách'],
    'idNumber': ['ID card number (CCCD)', 'Số CCCD'],
    'residence': [
      'Temporary residence registered (tạm trú)',
      'Đã đăng ký tạm trú',
    ],
    'residenceDate': [
      'Registered on (YYYY-MM-DD, optional)',
      'Ngày đăng ký (YYYY-MM-DD, không bắt buộc)',
    ],
    'coTenant': ['Co-tenant', 'Người ở cùng'],
    'addCo': ['Add person', 'Thêm người ở cùng'],
    'noCo': [
      'Nobody else yet. You can also add people later.',
      'Chưa có ai. Có thể thêm sau.',
    ],
    'remove': ['Remove', 'Xóa'],
    'period': ['Pay every', 'Thu tiền mỗi'],
    'months': ['{n} months', '{n} tháng'],
    'oneMonth': ['1 month', '1 tháng'],
    // 2026-10-26 (Tom): no own due day and no "Thanh toán" section any more:
    // every kỳ starts at rent × months + recurring phụ thu, and is changed
    // later in the lease page's payment table (lease_schedule_section.dart).
    'deposit': ['Deposit amount (optional)', 'Tiền cọc (không bắt buộc)'],
    'cash': ['Cash', 'Tiền mặt'],
    'transfer': ['Bank transfer', 'Chuyển khoản'],
    'depositNote': ['Deposit note', 'Ghi chú cọc'],
    'depositNoTotal': [
      'Not part of the total. Given back to the tenant when the contract ends.',
      'Không tính vào tổng tiền. Hoàn lại cho khách khi hết hợp đồng.',
    ],
    'secPower': ['Electricity and water', 'Điện và nước'],
    'powerPrice': ['Price per kWh', 'Giá điện mỗi kWh'],
    'powerHelp': [
      'Optional. Each month: (new meter reading − previous) × price.',
      'Không bắt buộc. Mỗi tháng: (chỉ số mới − chỉ số trước) × giá.',
    ],
    // 2026-10-04 (Tom): the meter reading on the move-in day, with a photo.
    'powerStart': [
      'Meter reading at move-in (kWh)',
      'Chỉ số điện lúc dọn vào (kWh)',
    ],
    'powerStartHelp': [
      'Optional. Each month after: open this lease (tap its bar on the calendar) › Electricity › Record reading.',
      'Không bắt buộc. Các tháng sau: mở hợp đồng này (bấm vào thanh trên lịch) › Tiền điện › Ghi chỉ số.',
    ],
    'powerLater': [
      'Moving in later: on that day, open this lease on the calendar › Electricity › Record reading.',
      'Dọn vào sau hôm nay: đến ngày đó, mở hợp đồng trên lịch › Tiền điện › Ghi chỉ số.',
    ],
    'invalidReading': ['Enter a number (kWh).', 'Nhập một số (kWh).'],
    'photo': ['Meter photo', 'Ảnh đồng hồ'],
    'photoChange': ['Change photo', 'Đổi ảnh'],
    'photoTooBig': [
      'That photo is too large (max 2 MB).',
      'Ảnh quá lớn (tối đa 2 MB).',
    ],
    'readingFailed': [
      'The lease is saved, but the meter reading was not: {why} Add it in the lease (tap its bar on the calendar).',
      'Hợp đồng đã lưu, nhưng chưa lưu chỉ số điện: {why} Hãy ghi lại trong hợp đồng (bấm vào thanh trên lịch).',
    ],
    'whyPrice': [
      'the room has no electricity price yet.',
      'phòng chưa có giá điện.',
    ],
    'whyOrder': [
      'the meter already has a later reading.',
      'đồng hồ đã có chỉ số ngày sau đó.',
    ],
    'whyOther': ['it could not be saved.', 'không lưu được.'],
    'photoFailed': [
      'The lease and the meter reading are saved, but the photo was not. Add it in the lease.',
      'Hợp đồng và chỉ số điện đã lưu, nhưng ảnh chưa lưu. Hãy thêm ảnh trong hợp đồng.',
    ],
    'readingReason': ['Reading at move-in', 'Chỉ số lúc dọn vào'],
    'notSet': ['Not set', 'Chưa chọn'],
    'staffInvalid': [
      'That staff member is no longer active. Choose someone else.',
      'Nhân viên này không còn làm việc. Hãy chọn người khác.',
    ],
    'accountInvalid': [
      'That account was removed. Choose another one.',
      'Tài khoản này đã bị xóa. Hãy chọn tài khoản khác.',
    ],
  };
  final pair = labels[key];
  return pair == null ? AppTranslations.of(context)[key] : pair[vi ? 1 : 0];
}

class _Person {
  final name = TextEditingController(),
      phone = TextEditingController(),
      idNumber = TextEditingController(),
      residenceDate = TextEditingController();
  bool residence = false;
  void dispose() {
    for (final c in [name, phone, idNumber, residenceDate]) {
      c.dispose();
    }
  }
}

class TenantLeaseScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final String? mainTenantId;
  final TeamService service;
  final VoidCallback onBack;

  /// Back-link label; defaults to "Tenants" (opened from Bookings: "Bookings").
  final String? backLabel;

  /// From a day on the calendar (C): this room is chosen and the move-in
  /// date ("YYYY-MM-DD") filled in; "Change room" still lists every room.
  final String? initialRoomId, initialMoveIn;

  /// Picks the meter photo (tests pass their own).
  final Future<List<PickedPhoto>> Function(int max) pick;
  const TenantLeaseScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.onBack,
    this.mainTenantId,
    this.backLabel,
    this.initialRoomId,
    this.initialMoveIn,
    this.pick = pickProblemPhotos,
  });
  @override
  State<TenantLeaseScreen> createState() => _TenantLeaseScreenState();
}

class _TenantLeaseScreenState extends State<TenantLeaseScreen> {
  late final MoneyForm _conversion = MoneyForm(
    OrganizationMoney.shared.forOrganization(widget.organizationId),
  );
  String get _inputCurrency => _conversion.currency(_currency);
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final k in [
      'name',
      'phone',
      'start',
      'end',
      'rent',
      'reason',
      'idNumber',
      'residenceDate',
      'deposit',
      'depositNote',
      'electricity',
      'powerStart',
      'water',
    ])
      k: TextEditingController(),
  };
  final _coTenants = <_Person>[];
  final _retired = <_Person>[];
  // 2026-10-04: surcharges (phụ thu) typed with the lease.
  final _surcharges = <LeaseSurchargeDraft>[];
  final _retiredCharges = <LeaseSurchargeDraft>[];
  List<Map<String, dynamic>> _rooms = [];
  Map<String, dynamic>? _record, _pending;
  String? _roomId, _cursor, _message, _staffId;
  // The rent the form filled in from the room's price (cleared on a room
  // change unless it was edited, so the new room's price is used).
  String? _suggestedRent;
  // After the lease: the move-in meter reading and photo (2026-10-04).
  PickedPhoto? _startPhoto;
  String _waterBasis = 'person';
  String? _warning;
  String _depositMethod = 'cash';
  String? _depositAccount;
  int _periodMonths = 1;
  bool _busy = false, _saving = false, _done = false, _residence = false;
  int _generation = 0;
  bool get _roommate => widget.mainTenantId != null;
  Future<Map<String, dynamic>> _request(Map<String, dynamic> data) => _roommate
      ? widget.service.tenantRoommates(data)
      : widget.service.tenantLeases(data);
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    if (_roommate) 'mainTenantId': widget.mainTenantId,
  };
  bool get _locked => _busy || _saving || _pending != null;

  /// Opened by itself in a calendar dialog: the dialog's title bar names the
  /// page and closes it, so no back link, no second title, and the dialog
  /// closes once the lease is created.
  bool get _dialogRoot =>
      DialogPageScope.contains(context) && widget.backLabel == null;
  String lt(String key) => _leaseText(context, key);

  @override
  void initState() {
    super.initState();
    _fields['rent']!.addListener(_refresh);
    final room = widget.initialRoomId;
    if (_roommate) {
      _prepare('');
    } else if (room != null) {
      _fields['start']!.text = widget.initialMoveIn ?? '';
      _prepare(room);
    } else {
      _load();
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant TenantLeaseScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service ||
        old.mainTenantId != widget.mainTenantId) {
      _pending = null;
      _saving = false;
      _done = false;
      _roomId = null;
      _record = null;
      for (final c in _fields.values) {
        c.clear();
      }
      _clearPeople();
      _roommate ? _prepare('') : _load();
    }
  }

  void _clearPeople() {
    _retired.addAll(_coTenants);
    _coTenants.clear();
    _retiredCharges.addAll(_surcharges);
    _surcharges.clear();
    _residence = false;
    _staffId = null;
    _periodMonths = 1;
    _startPhoto = null;
    _suggestedRent = null;
    _warning = null;
    _waterBasis = 'person';
    _depositMethod = 'cash';
    _depositAccount = null;
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    for (final p in [..._coTenants, ..._retired]) {
      p.dispose();
    }
    for (final c in [..._surcharges, ..._retiredCharges]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _message = null;
      if (!more) {
        _rooms = [];
        _cursor = null;
      }
    });
    try {
      // 2026-10-11 (Tom: open at once): the first page of rooms from this
      // device first, then the server's (still locked until it answers).
      final payload = {
        'action': 'rooms',
        ..._identity,
        if (more) 'cursor': _cursor,
      };
      final answers = _roommate || more
          ? Stream.fromFuture(
              _request(
                payload,
              ).then((v) => Saved(v, saved: false, at: DateTime.now())),
            )
          : widget.service.readLive('tenantLeases', payload);
      final before = List<Map<String, dynamic>>.of(_rooms);
      await for (final answer in answers) {
        if (!mounted || generation != _generation) return;
        final r = answer.data;
        setState(() {
          _rooms = List.of(before);
          final known = _rooms.map((v) => v['id']).toSet();
          _rooms.addAll(
            (r['records'] as List)
                .map((v) => Map<String, dynamic>.from(v as Map))
                .where((v) => known.add(v['id'])),
          );
          _cursor = r['nextCursor'] as String?;
          _busy = answer.saved;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _rooms = [];
          _cursor = null;
          _busy = false;
          _message = 'lease_form_unavailable';
        });
      }
    }
  }

  RoomChoice _roomChoice(AppTranslations t, Map<String, dynamic> room) {
    final blocked = room['blocked'] == true, monthly = room['monthly'] == true;
    return RoomChoice(
      room['id'] as String,
      '${room['roomNumber']}',
      enabled: monthly && !blocked,
      note: blocked
          ? t['lease_room_problem']
          : monthly
          ? null
          : t['lease_form_hourly'],
    );
  }

  /// The room list. Before a room is chosen it starts from the rooms this
  /// page already read; with a room chosen it reads them when opened.
  Future<void> _pickRoom() async {
    final chosen = _roomId, t = AppTranslations.of(context);
    String? cursor = chosen == null ? _cursor : null;
    // Room numbers of everything listed, for the dialog title afterwards.
    final numbers = <String, String>{};
    RoomChoice choice(Map<String, dynamic> room) {
      final c = _roomChoice(t, room);
      numbers[c.id] = c.label;
      return c;
    }

    final id = await showRoomPicker(
      context,
      keyPrefix: 'lease-room',
      selectedId: chosen,
      rooms: chosen == null ? [for (final r in _rooms) choice(r)] : [],
      hasMore: chosen == null && _cursor != null,
      load: (more) async {
        final r = await _request({
          'action': 'rooms',
          ..._identity,
          if (more && cursor != null) 'cursor': cursor,
        });
        cursor = r['nextCursor'] as String?;
        return RoomChoicePage([
          for (final v in r['records'] as List)
            choice(Map<String, dynamic>.from(v as Map)),
        ], hasMore: cursor != null);
      },
    );
    // Nothing changes if the page moved on while the list was open.
    if (!mounted || id == null || id == chosen || _roomId != chosen) return;
    if (_locked || _done) return;
    // The new room's price replaces the old room's, unless it was typed.
    if (_fields['rent']!.text == _suggestedRent) _fields['rent']!.clear();
    _suggestedRent = null;
    // The move-in meter reading and its photo belong to the old room's meter
    // (2026-10-22, Tom: clear them on a room change).
    _fields['powerStart']!.clear();
    _startPhoto = null;
    _warning = null;
    _prepare(id);
    // A calendar dialog titled "Phòng …" follows the new room.
    final number = numbers[id];
    if (number != null) RoomTitleScope.report(context, number);
  }

  Future<void> _prepare(String id) async {
    final generation = ++_generation;
    setState(() {
      _roomId = id;
      _record = null;
      _rooms = [];
      _cursor = null;
      _busy = true;
      _message = null;
    });
    try {
      // 2026-10-11 (Tom: open at once): the room's form from this device
      // first (shown, locked); the server's answer then fills the dates and
      // amounts, so an old "today" is never put in the form.
      final payload = {
        'action': 'prepare',
        ..._identity,
        if (!_roommate) 'roomId': id,
      };
      final answers = _roommate
          ? Stream.fromFuture(
              _request(
                payload,
              ).then((v) => Saved(v, saved: false, at: DateTime.now())),
            )
          : widget.service.readLive('tenantLeases', payload);
      await for (final answer in answers) {
        final r = answer.data;
        if (!mounted || generation != _generation) return;
        setState(() {
          _record = Map<String, dynamic>.from(r['record'] as Map);
          _busy = answer.saved;
          if (answer.saved) return;
          if (_fields['start']!.text.isEmpty) {
            _fields['start']!.text = _record!['today'] as String;
            if (_roommate &&
                (_record!['earliestDate'] as String).compareTo(
                      _fields['start']!.text,
                    ) >
                    0) {
              _fields['start']!.text = _record!['earliestDate'] as String;
            }
          }
          // The room's monthly price as a starting point for the rent.
          int? roomRent = _record!['monthlyRentMinor'] as int?;
          final source = _record!['roomRent'];
          if (roomRent == null &&
              source is Map &&
              source['amountMinor'] is int &&
              source['currency'] is String) {
            final sourceCurrency = source['currency'] as String;
            if (sourceCurrency == _currency) {
              roomRent = source['amountMinor'] as int;
            } else {
              try {
                roomRent = _conversion.conversion?.convertMinor(
                  source['amountMinor'] as int,
                  sourceCurrency,
                  _currency,
                );
              } on StateError {
                // Without rates, leave the suggested rent empty. Never relabel
                // a source price; the user can enter the new lease's currency.
              }
            }
          }
          if (_fields['rent']!.text.isEmpty && roomRent is int) {
            _conversion.set(_fields['rent']!, roomRent, _currency);
            _suggestedRent = _fields['rent']!.text;
          }
          // The building's water price (PRICE_DEFAULTS.md, 2026-10-26).
          final water = _record!['waterDefault'];
          if (_fields['water']!.text.isEmpty &&
              water is Map &&
              water['amountMinor'] is int) {
            _conversion.set(
              _fields['water']!,
              water['amountMinor'] as int,
              _currency,
            );
            _waterBasis = water['basis'] == 'room' ? 'room' : 'person';
          }
          if (_staffId != null && !_staff.any((s) => s['id'] == _staffId)) {
            _staffId = null;
          }
          if (_depositAccount != null &&
              !_accounts.any((a) => a['id'] == _depositAccount)) {
            _depositAccount = null;
          }
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _message =
              e is FirebaseFunctionsException &&
                  e.message == 'lease_property_timezone_required'
              ? 'lease_form_timezone_required'
              : 'lease_form_unavailable';
        });
      }
    }
  }

  List<Map<String, dynamic>> _list(String key) =>
      (_record?[key] as List? ?? const [])
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  List<Map<String, dynamic>> get _staff => _list('staff');
  List<Map<String, dynamic>> get _accounts => _list('accounts');
  String get _currency => _record?['currency'] as String? ?? 'VND';

  Map<String, dynamic> _paper(String idNumber, bool registered, String date) =>
      {
        if (idNumber.trim().isNotEmpty) 'nationalId': idNumber.trim(),
        'residenceRegistered': registered,
        if (registered && date.trim().isNotEmpty) 'residenceDate': date.trim(),
      };

  Map<String, dynamic> _details() {
    final deposit = _conversion.parse(_fields['deposit']!, _currency);
    final power = _conversion.parse(_fields['electricity']!, _currency);
    final water = _conversion.parse(_fields['water']!, _currency);
    final charges = [
      for (final c in _surcharges) c.toJson(_currency),
      if (water != null && water > 0)
        leaseWaterJson(context, water, basis: _waterBasis),
    ].whereType<Map<String, dynamic>>().toList();
    return {
      if (charges.isNotEmpty) 'surcharges': charges,
      if (power != null && power > 0 && _record?['canPrice'] == true)
        'electricityPriceMinor': power,
      ..._paper(
        _fields['idNumber']!.text,
        _residence,
        _fields['residenceDate']!.text,
      ),
      if (_coTenants.isNotEmpty)
        'coTenants': [
          for (final p in _coTenants)
            {
              'fullName': p.name.text.trim(),
              'phoneNumber': p.phone.text.trim(),
              ..._paper(p.idNumber.text, p.residence, p.residenceDate.text),
            },
        ],
      if (_staffId != null) 'staffInChargeId': _staffId,
      'periodMonths': _periodMonths,
      if (deposit != null && deposit > 0) ...{
        'depositMinor': deposit,
        'depositMethod': _depositMethod,
        if (_depositMethod == 'bankTransfer' && _depositAccount != null)
          'depositAccountId': _depositAccount,
        if (_fields['depositNote']!.text.trim().isNotEmpty)
          'depositNote': _fields['depositNote']!.text.trim(),
      },
    };
  }

  Future<void> _save() async {
    if (_busy || _saving || _record == null || _done) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    _pending ??= Map.unmodifiable({
      'action': 'create',
      ..._identity,
      if (!_roommate) 'roomId': _roomId,
      'operationId': const Uuid().v4(),
      'roomRevision': _record!['roomRevision'],
      'timeZone': _record!['timeZone'],
      if (!_roommate) 'currency': _record!['currency'],
      if (_roommate) 'mainRevision': _record!['mainRevision'],
      'fullName': _fields['name']!.text.trim(),
      'phoneNumber': _fields['phone']!.text.trim(),
      'moveInDate': _fields['start']!.text.trim(),
      // Required since 2026-10-04 (Tom).
      if (!_roommate) 'contractEndDate': _fields['end']!.text.trim(),
      if (!_roommate)
        'rentMinor': _conversion.parse(
          _fields['rent']!,
          _record!['currency'] as String,
        ),
      'backdateReason': _fields['reason']!.text.trim(),
      if (!_roommate) ..._details(),
      if (_roommate)
        ..._paper(
          _fields['idNumber']!.text,
          _residence,
          _fields['residenceDate']!.text,
        ),
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await _request(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      // The move-in meter reading (and photo) after the lease is saved.
      final warning = _roommate ? null : await _saveStartReading();
      if (!mounted || generation != _generation) return;
      _warning = warning;
      // In a calendar dialog the new lease shows on the calendar: close
      // (unless the reading needs saying).
      if (_dialogRoot && warning == null) {
        _pending = null;
        _saving = false;
        _done = true;
        widget.onBack();
        return;
      }
      setState(() {
        _pending = null;
        _saving = false;
        _done = true;
        _message = _roommate ? 'roommate_form_saved' : 'lease_form_saved';
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _message = 'lease_form_uncertain';
        if (e is FirebaseFunctionsException) {
          final reason = serverReason(e, const [
            'booking_staff_invalid',
            'booking_account_invalid',
          ]);
          if (reason.isNotEmpty) {
            // Fixable in the form: keep everything that was typed.
            _pending = null;
            _message = reason == 'booking_staff_invalid'
                ? 'staffInvalid'
                : 'accountInvalid';
          } else if ([
            'permission-denied',
            'unauthenticated',
            'not-found',
          ].contains(e.code)) {
            _pending = null;
            _record = null;
            for (final c in _fields.values) {
              c.clear();
            }
            _clearPeople();
            _message = 'lease_form_unavailable';
          } else if (e.code == 'already-exists') {
            // Room busy: keep the form so another room or date can be chosen.
            _pending = null;
            _message = 'lease_form_occupied';
          } else if ([
            'aborted',
            'failed-precondition',
            'invalid-argument',
          ].contains(e.code)) {
            _pending = null;
            _record = null;
            _message = e.code == 'already-exists'
                ? 'lease_form_occupied'
                : 'lease_form_changed';
          }
        }
      });
    }
  }

  /// Whether a move-in reading can be typed: moving in today or earlier.
  bool get _startAllowed {
    final start = _fields['start']!.text.trim(), today = _record?['today'];
    return today is String &&
        contractDate(start) &&
        start.compareTo(today) <= 0;
  }

  Future<void> _pickStartPhoto() async {
    final picked = await widget.pick(1);
    if (!mounted || picked.isEmpty) return;
    setState(() {
      if (picked.first.bytes.length > maxPhotoBytes) {
        _warning = lt('photoTooBig');
      } else {
        _startPhoto = picked.first;
        _warning = null;
      }
    });
  }

  /// Saves the move-in meter reading (and its photo) once the lease exists.
  /// Returns what to tell the person when part of it failed, else null.
  Future<String?> _saveStartReading() async {
    final milli = meterMilli(_fields['powerStart']!.text);
    if (milli == null || !_startAllowed || _roomId == null) return null;
    final scope = {
      'organizationId': widget.organizationId,
      'buildingId': widget.buildingId,
      'roomId': _roomId,
      'kind': 'electricity',
    };
    String failed(String why) =>
        lt('readingFailed').replaceAll('{why}', lt(why));
    String? readingId;
    try {
      final meter = await widget.service.utilityReadings({
        'action': 'read',
        ...scope,
      });
      final r = await widget.service.utilityReadings({
        'action': 'record',
        ...scope,
        'operationId': const Uuid().v4(),
        'revision': (meter['record'] as Map)['revision'],
        'date': _fields['start']!.text.trim(),
        'readingMilli': milli,
        'reason': lt('readingReason'),
        'oldFinalMilli': null,
        'newStartMilli': null,
      });
      readingId = '${r['readingId']}';
    } on FirebaseFunctionsException catch (e) {
      return failed(switch (e.message) {
        'utility_tariff_required' => 'whyPrice',
        'utility_reading_order' => 'whyOrder',
        _ => 'whyOther',
      });
    } catch (_) {
      return failed('whyOther');
    }
    final photo = _startPhoto,
        type = photo == null ? null : photoType(photo.bytes);
    if (photo == null || type == null) return null;
    try {
      await widget.service.utilityReadings({
        'action': 'addPhoto',
        ...scope,
        'readingId': readingId,
        'operationId': const Uuid().v4(),
        'mimeType': type,
        'dataBase64': base64Encode(photo.bytes),
      });
      return null;
    } catch (_) {
      return lt('photoFailed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context), r = _record;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final past =
        r != null &&
        contractDate(_fields['start']!.text.trim()) &&
        _fields['start']!.text.trim().compareTo(r['today'] as String) < 0;
    String? dateCheck(String v) =>
        v.isNotEmpty && !contractDate(v) ? t['lease_form_invalid_date'] : null;
    Widget input(
      String key, {
      String? label,
      int max = 160,
      TextEditingController? controller,
      String? hint,
      String? helper,
      TextInputType? keyboard,
      bool required = false,
      bool readOnly = false,
      bool labelAbove = false,
      String? Function(String)? check,
      ValueChanged<String>? onChanged,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (labelAbove) ...[
          Text(label ?? t['lease_form_$key']),
          const SizedBox(height: WsSpace.sm),
        ],
        Semantics(
          label: label ?? t['lease_form_$key'],
          child: TextFormField(
            key: ValueKey('lease-$key'),
            controller: controller ?? _fields[key],
            enabled: !_locked,
            readOnly: readOnly,
            keyboardType: keyboard,
            // Money boxes group the digits as you type (2026-10-05, Tom).
            inputFormatters:
                const {
                  'rent',
                  'deposit',
                  'electricity',
                  'water',
                }.contains(key)
                ? appMoneyInput(_inputCurrency)
                : null,
            maxLines: null,
            onChanged: onChanged,
            decoration: InputDecoration(
              labelText: labelAbove ? null : label ?? t['lease_form_$key'],
              hintText: hint,
              helperText: helper,
              helperMaxLines: 5,
            ),
            validator: (value) {
              final v = (value ?? '').trim();
              if (v.length > max) return t['tenant_contacts_long'];
              if (required && v.isEmpty) return t['tenant_contacts_required'];
              return check?.call(v);
            },
          ),
        ),
      ],
    );
    Widget residence(
      String key,
      bool value,
      ValueChanged<bool> onChanged,
      TextEditingController date,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: ValueKey('lease-$key'),
          contentPadding: EdgeInsets.zero,
          title: Text(lt('residence')),
          value: value,
          onChanged: _locked ? null : onChanged,
        ),
        if (value)
          input(
            '$key-date',
            label: lt('residenceDate'),
            controller: date,
            max: 10,
            check: dateCheck,
          ),
      ],
    );

    List<Widget> mainForm(Map<String, dynamic> r) => [
      if (!_roommate)
        WsSection(
          title: lt('secRoom'),
          icon: Icons.meeting_room_outlined,
          children: [
            // 2026-10-22 (Tom): the chosen room; tapping it lists the others
            // (replaces "Đổi phòng" and the list of every room).
            RoomPickerField(
              fieldKey: 'lease-room',
              value: '${r['roomNumber']}',
              onPick: _locked ? null : _pickRoom,
              // The section is titled "Phòng" already (no repeat).
              showLabel: false,
            ),
            const SizedBox(height: WsSpace.xs),
            Text(
              '${t['lease_form_timezone']}: ${r['timeZone']} · ${t['lease_form_today']}: ${r['today']}',
              style: muted,
            ),
          ],
        )
      else
        WsSection(
          title: '${r['roomNumber']}',
          icon: Icons.meeting_room_outlined,
          children: [
            Text('${t['roommate_form_main']}: ${r['mainName']}'),
            Text(
              '${t['roommate_form_earliest']}: ${r['earliestDate']}',
              style: muted,
            ),
          ],
        ),
      WsSection(
        title: _roommate ? lt('coTenant') : lt('secMain'),
        icon: Icons.person_outline,
        children: [
          WsFieldRow(
            children: [
              input('name', required: true),
              input('phone', max: 80, keyboard: TextInputType.phone),
            ],
          ),
          // CCCD and tạm trú for a roommate too (2026-10-04, Tom).
          ...[
            const SizedBox(height: WsSpace.md),
            input('idNumber', label: lt('idNumber'), max: 30),
            residence(
              'residence',
              _residence,
              (v) => setState(() => _residence = v),
              _fields['residenceDate']!,
            ),
          ],
        ],
      ),
      if (!_roommate)
        WsSection(
          title: lt('secCo'),
          icon: Icons.people_alt_outlined,
          children: [
            if (_coTenants.isEmpty) Text(lt('noCo'), style: muted),
            for (final (i, p) in _coTenants.indexed)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : WsSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${lt('coTenant')} ${i + 1}',
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: lt('remove'),
                          icon: const Icon(Icons.close),
                          onPressed: _locked
                              ? null
                              : () => setState(
                                  () => _retired.add(_coTenants.removeAt(i)),
                                ),
                        ),
                      ],
                    ),
                    WsFieldRow(
                      children: [
                        input(
                          'co-$i-name',
                          label: t['lease_form_name'],
                          controller: p.name,
                          required: true,
                        ),
                        input(
                          'co-$i-phone',
                          label: t['lease_form_phone'],
                          controller: p.phone,
                          max: 80,
                          keyboard: TextInputType.phone,
                        ),
                      ],
                    ),
                    const SizedBox(height: WsSpace.md),
                    input(
                      'co-$i-id',
                      label: lt('idNumber'),
                      controller: p.idNumber,
                      max: 30,
                    ),
                    residence(
                      'co-$i-residence',
                      p.residence,
                      (v) => setState(() => p.residence = v),
                      p.residenceDate,
                    ),
                  ],
                ),
              ),
            if (_coTenants.length < 10)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('lease-add-co'),
                  onPressed: _locked
                      ? null
                      : () => setState(() => _coTenants.add(_Person())),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: Text(lt('addCo')),
                ),
              ),
          ],
        ),
      WsSection(
        title: _roommate ? lt('moveIn') : lt('secContract'),
        icon: Icons.description_outlined,
        children: [
          WsFieldRow(
            children: [
              input(
                'start',
                max: 10,
                onChanged: (_) => setState(() {}),
                check: (v) {
                  if (!contractDate(v)) return t['lease_form_invalid_date'];
                  if (_roommate &&
                      v.compareTo(r['earliestDate'] as String) < 0) {
                    return t['roommate_form_before_main'];
                  }
                  if (v.compareTo(r['today'] as String) < 0 &&
                      r['canBackdate'] != true) {
                    return t['lease_form_no_backdate'];
                  }
                  return null;
                },
              ),
              if (!_roommate)
                input(
                  'end',
                  max: 10,
                  required: true,
                  check: (v) =>
                      !contractDate(v) ||
                          v.compareTo(_fields['start']!.text.trim()) <= 0
                      ? t['lease_form_invalid_end']
                      : null,
                ),
            ],
          ),
          if (!_roommate) ...[
            const SizedBox(height: WsSpace.md),
            // 2026-10-26 (Tom): rent and "Thu tiền mỗi" side by side, the
            // period as a dropdown (was a row of chips) to save space.
            WsFieldRow(
              children: [
                input(
                  'rent',
                  label: '${t['lease_form_rent']} ($_inputCurrency)',
                  max: 24,
                  keyboard: TextInputType.numberWithOptions(
                    decimal: _inputCurrency == 'USD',
                  ),
                  check: (v) => parseRoomRate(v, _inputCurrency) == null
                      ? t['lease_form_invalid_rent']
                      : null,
                ),
                // Keyed on the value so a form reset (_clearPeople) shows
                // 1 month again; the dropdown keeps its own value otherwise.
                KeyedSubtree(
                  key: ValueKey('lease-period-at-$_periodMonths'),
                  child: DropdownButtonFormField<int>(
                    key: const ValueKey('lease-period'),
                    initialValue: _periodMonths,
                    isExpanded: true,
                    // Regular weight like the other dropdowns (design rule).
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(labelText: lt('period')),
                    items: [
                      for (final n in [1, 2, 3, 6, 12])
                        DropdownMenuItem(
                          value: n,
                          child: Text(
                            n == 1
                                ? lt('oneMonth')
                                : lt('months').replaceAll('{n}', '$n'),
                          ),
                        ),
                    ],
                    onChanged: _locked
                        ? null
                        : (n) => setState(() => _periodMonths = n ?? 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: WsSpace.sm),
          ],
          if (past && r['canBackdate'] == true) ...[
            const SizedBox(height: WsSpace.md),
            input(
              'reason',
              max: 1000,
              check: (v) => v.isEmpty ? t['lease_form_reason_required'] : null,
            ),
          ],
        ],
      ),
      if (!_roommate)
        WsSection(
          title: lt('secDeposit'),
          icon: Icons.savings_outlined,
          children: [
            WsFieldRow(
              children: [
                input(
                  'deposit',
                  label: lt('deposit'),
                  max: 24,
                  keyboard: TextInputType.numberWithOptions(
                    decimal: _inputCurrency == 'USD',
                  ),
                  check: (v) =>
                      v.isNotEmpty && parseRoomRate(v, _inputCurrency) == null
                      ? t['lease_form_invalid_rent']
                      : null,
                ),
                input('depositNote', label: lt('depositNote'), max: 500),
              ],
            ),
            const SizedBox(height: WsSpace.xs),
            Text(lt('depositNoTotal'), style: muted),
            const SizedBox(height: WsSpace.md),
            Wrap(
              spacing: WsSpace.sm,
              runSpacing: WsSpace.sm,
              children: [
                ChoiceChip(
                  key: const ValueKey('lease-deposit-cash'),
                  label: Text(lt('cash')),
                  selected: _depositMethod == 'cash',
                  onSelected: _locked
                      ? null
                      : (_) => setState(() {
                          _depositMethod = 'cash';
                          _depositAccount = null;
                        }),
                ),
                if (_accounts.isEmpty)
                  ChoiceChip(
                    key: const ValueKey('lease-deposit-transfer'),
                    label: Text(lt('transfer')),
                    selected: _depositMethod == 'bankTransfer',
                    onSelected: _locked
                        ? null
                        : (_) =>
                              setState(() => _depositMethod = 'bankTransfer'),
                  ),
                for (final a in _accounts)
                  ChoiceChip(
                    key: ValueKey('lease-deposit-${a['id']}'),
                    label: Text('${a['label']}'),
                    selected: _depositAccount == a['id'],
                    onSelected: _locked
                        ? null
                        : (_) => setState(() {
                            _depositMethod = 'bankTransfer';
                            _depositAccount = a['id'] as String;
                          }),
                  ),
              ],
            ),
          ],
        ),
      if (!_roommate)
        WsSection(
          title: leaseSurchargeText(context, 'title'),
          icon: Icons.add_card_outlined,
          children: [
            LeaseSurchargeEditor(
              conversion: _conversion.conversion,
              drafts: _surcharges,
              currency: _currency,
              enabled: !_locked,
              onChanged: () => setState(() {}),
              onRemoved: _retiredCharges.add,
            ),
          ],
        ),
      if (!_roommate)
        WsSection(
          title: lt('secPower'),
          icon: Icons.bolt_outlined,
          children: [
            if (r['canPrice'] == true) ...[
              input(
                'electricity',
                label: '${lt('powerPrice')} ($_inputCurrency)',
                max: 24,
                helper: lt('powerHelp'),
                keyboard: TextInputType.numberWithOptions(
                  decimal: _inputCurrency == 'USD',
                ),
                check: (v) =>
                    v.isNotEmpty && (parseRoomRate(v, _inputCurrency) ?? 0) <= 0
                    ? t['lease_form_invalid_rent']
                    : null,
              ),
              const SizedBox(height: WsSpace.md),
            ],
            if (_startAllowed) ...[
              input(
                'powerStart',
                label: lt('powerStart'),
                max: 16,
                helper: lt('powerStartHelp'),
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                // A photo needs the reading it shows.
                check: (v) =>
                    (v.isNotEmpty && meterMilli(v) == null) ||
                        (v.isEmpty && _startPhoto != null)
                    ? lt('invalidReading')
                    : null,
              ),
              const SizedBox(height: WsSpace.sm),
              Wrap(
                spacing: WsSpace.sm,
                runSpacing: WsSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('lease-power-photo'),
                    onPressed: _locked ? null : _pickStartPhoto,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(
                      lt(_startPhoto == null ? 'photo' : 'photoChange'),
                      maxLines: 1,
                    ),
                  ),
                  if (_startPhoto != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(
                        _startPhoto!.bytes,
                        key: const ValueKey('lease-power-photo-preview'),
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const SizedBox(width: 56, height: 56),
                      ),
                    ),
                ],
              ),
            ] else
              Text(lt('powerLater'), style: muted),
            const SizedBox(height: WsSpace.lg),
            input(
              'water',
              label:
                  '${leaseSurchargeText(context, 'waterPrice')} ($_inputCurrency)',
              max: 24,
              keyboard: TextInputType.numberWithOptions(
                decimal: _inputCurrency == 'USD',
              ),
              check: (v) =>
                  v.isNotEmpty && (parseRoomRate(v, _inputCurrency) ?? 0) <= 0
                  ? t['lease_form_invalid_rent']
                  : null,
            ),
            const SizedBox(height: WsSpace.sm),
            LeaseWaterBasis(
              basis: _waterBasis,
              enabled: !_locked,
              onChanged: (v) => setState(() => _waterBasis = v),
            ),
          ],
        ),
      if (!_roommate)
        WsSection(
          title: lt('secStaff'),
          icon: Icons.badge_outlined,
          children: [
            DropdownButtonFormField<String?>(
              key: const ValueKey('lease-staff'),
              initialValue: _staffId,
              isExpanded: true,
              style: theme.textTheme.bodyLarge,
              // The section title already says what this is.
              decoration: const InputDecoration(),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(lt('notSet')),
                ),
                for (final s in _staff)
                  DropdownMenuItem<String?>(
                    value: s['id'] as String,
                    child: Text(
                      '${s['displayName']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _locked ? null : (v) => setState(() => _staffId = v),
            ),
          ],
        ),
      // No "reload" next to save (2026-10-04, Tom): reloading is offered only
      // when loading failed or the server said something changed.
      WsActions(
        children: [
          FilledButton(
            onPressed: _locked ? null : _save,
            child: Text(
              t[_roommate ? 'roommate_form_save' : 'lease_form_save'],
            ),
          ),
        ],
      ),
    ];

    return WsPage(
      maxWidth: 760,
      children: [
        WsHeader(
          back: _dialogRoot
              ? null
              : WsBack(
                  label: widget.backLabel ?? t['tenant_contacts_title'],
                  onPressed: _locked ? null : widget.onBack,
                ),
          title: _dialogRoot
              ? ''
              : t[_roommate ? 'roommate_form_title' : 'lease_form_title'],
          help: _dialogRoot
              ? null
              : t[_roommate ? 'roommate_form_help' : 'lease_form_help'],
        ),
        if (_busy || _saving)
          const Padding(
            padding: EdgeInsets.only(bottom: WsSpace.sm),
            child: LinearProgressIndicator(),
          ),
        if (_message != null)
          Semantics(
            liveRegion: true,
            child: WsNotice(
              lt(_message!),
              tone:
                  const {
                    'lease_form_saved',
                    'roommate_form_saved',
                  }.contains(_message)
                  ? WsTone.good
                  : WsTone.warning,
            ),
          ),
        if (_warning != null)
          Semantics(
            liveRegion: true,
            child: WsNotice(
              _warning!,
              key: const ValueKey('lease-reading-warning'),
              tone: WsTone.warning,
            ),
          ),
        if (_done)
          WsActions(
            children: [
              FilledButton(
                key: const ValueKey('lease-done'),
                onPressed: widget.onBack,
                child: Text(lt('done')),
              ),
            ],
          ),
        if (!_done && _roomId == null) ...[
          WsSection(
            title: lt('secRoom'),
            icon: Icons.meeting_room_outlined,
            trailing: TextButton(
              onPressed: _locked ? null : () => _load(),
              child: Text(t['lease_form_reload_rooms']),
            ),
            children: [
              if (!_busy && _message == null && _rooms.isEmpty)
                Text(t['lease_form_empty'], style: muted)
              else
                // 2026-10-22 (Tom): one box; tapping it lists the rooms.
                // Hourly-only rooms and rooms with an open "room unavailable"
                // problem (B7) are greyed out in the list with the reason.
                RoomPickerField(
                  fieldKey: 'lease-room',
                  showLabel: false,
                  value: null,
                  onPick: _locked || _rooms.isEmpty ? null : _pickRoom,
                ),
            ],
          ),
        ],
        if (!_done && _roomId != null) ...[
          if (r != null)
            Form(
              key: _form,
              onChanged: () {
                if (mounted) setState(() {});
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: mainForm(r),
              ),
            ),
          if (_pending != null)
            WsActions(
              children: [
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(
                    t[_roommate ? 'roommate_form_retry' : 'lease_form_retry'],
                  ),
                ),
              ],
            ),
          if (r == null && !_busy)
            WsActions(
              children: [
                if (!_roommate)
                  TextButton(
                    onPressed: _locked
                        ? null
                        : () {
                            setState(() {
                              _roomId = null;
                              _record = null;
                            });
                            _load();
                          },
                    child: Text(t['lease_form_change_room']),
                  ),
                OutlinedButton(
                  onPressed: _locked ? null : () => _prepare(_roomId!),
                  child: Text(
                    t[_roommate ? 'roommate_form_reload' : 'lease_form_reload'],
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }
}
