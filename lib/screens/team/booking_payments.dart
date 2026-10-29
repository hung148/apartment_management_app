import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import '../../utils/money_conversion.dart';
import 'ws_ui.dart';

/// Short-stay payments (2026-10-24, Tom). The Thanh toán section shows the
/// payments made so far ("lần thanh toán") and "Thêm lần thanh toán". Each one
/// has a day, a type (tiền cọc, tiền phòng, phụ thu, khác, hoàn tiền), the
/// amount, how it was paid (the organization's list; a new way typed once is
/// kept for everyone) and who received it: the staff member for cash, the
/// receiving account otherwise. More than is still owed: only what is owed is
/// recorded and the change (tiền thối) is shown and kept.
///
/// A saved booking: each payment is saved at once (functions/
/// booking_receipts.js). A new booking: payments are kept in the form
/// ([drafts]) and saved with the booking.
/// Adding needs "Thu tiền", refunds "Hoàn tiền", changing a recorded payment
/// "Sửa lần thanh toán"; the server checks them again.

const paymentKinds = ['deposit', 'room', 'surcharge', 'other', 'refund'];

/// What the form already knows (from the booking options).
class BookingPaymentOptions {
  final List<Map<String, dynamic>> staff, accounts, methods;
  final String? myStaffId;
  final String today;
  final bool canCollect, canRefund, canEdit;
  const BookingPaymentOptions({
    this.staff = const [],
    this.accounts = const [],
    this.methods = const [],
    this.myStaffId,
    this.today = '',
    this.canCollect = false,
    this.canRefund = false,
    this.canEdit = false,
  });
}

String _w(BuildContext context, String en, String vi) =>
    AppTranslations.of(context).locale.languageCode == 'vi' ? vi : en;

/// A refund names what it gives back (2026-10-24, Tom): "Hoàn tiền cọc" or
/// "Hoàn tiền phòng". [kind] may also be the dialog's "refund:deposit".
String paymentKindLabel(
  BuildContext context,
  String? kind, [
  String? refundFrom,
]) => switch (kind) {
  'deposit' => _w(context, 'Deposit', 'Tiền cọc'),
  'room' => _w(context, 'Room charge', 'Tiền phòng'),
  'surcharge' => _w(context, 'Surcharge', 'Phụ thu'),
  'refund:deposit' => _w(context, 'Deposit refund', 'Hoàn tiền cọc'),
  'refund:room' => _w(context, 'Room refund', 'Hoàn tiền phòng'),
  'refund' => paymentKindLabel(context, 'refund:${refundFrom ?? 'room'}'),
  _ => _w(context, 'Other', 'Khác'),
};

/// What a row did to the amount paid: + a payment, − a refund (minor units).
int paidEffect(Map<String, dynamic> row, {bool draft = false}) {
  if (row['paidEffectMinor'] is int) return row['paidEffectMinor'] as int;
  final amount = ((draft ? row['recordedMinor'] : row['amountMinor']) as num)
      .toInt();
  return row['kind'] == 'refund' ? -amount : amount;
}

/// "Còn lại" after each row, in order (2026-10-24, Tom).
List<int> runningOwed(
  List<Map<String, dynamic>> rows,
  int total, {
  bool draft = false,
}) {
  var owed = total;
  return [for (final r in rows) owed = owed - paidEffect(r, draft: draft)];
}

String _methodLabel(
  BuildContext context,
  String? id,
  String? label,
  List<Map<String, dynamic>> methods,
) {
  if (id == 'cash') return _w(context, 'Cash', 'Tiền mặt');
  if (id == 'bankTransfer') return _w(context, 'Bank transfer', 'Chuyển khoản');
  final found = methods.where((m) => m['id'] == id).firstOrNull;
  return '${found?['label'] ?? label ?? _w(context, 'Other', 'Khác')}';
}

/// The server's reason for a refused payment, in words.
String paymentError(BuildContext context, Object e) {
  final key = e is FirebaseFunctionsException ? '${e.message}' : '';
  final code = e is FirebaseFunctionsException ? e.code : '';
  return switch (key) {
    'booking_nothing_owed' => _w(
      context,
      'Nothing is owed on this booking.',
      'Đặt phòng này không còn tiền phải trả.',
    ),
    'booking_payment_date' => _w(
      context,
      'Choose a day up to today.',
      'Chọn ngày không sau hôm nay.',
    ),
    'booking_refund_exceeds_deposit' => _w(
      context,
      'The refund is more than the deposit received.',
      'Số tiền hoàn lớn hơn tiền cọc đã nhận.',
    ),
    'booking_refund_exceeds_payment' => _w(
      context,
      'The refund is more than the room money received.',
      'Số tiền hoàn lớn hơn tiền phòng đã nhận.',
    ),
    'booking_payment_balance' => _w(
      context,
      'This change does not fit the payments recorded after it. Check the amounts.',
      'Thay đổi này không khớp với các lần thanh toán khác. Kiểm tra lại số tiền.',
    ),
    'booking_staff_invalid' => _w(
      context,
      'That staff member can no longer receive money. Choose another.',
      'Nhân viên này không còn nhận tiền được. Chọn người khác.',
    ),
    'booking_account_invalid' => _w(
      context,
      'That account was removed. Choose another.',
      'Tài khoản này đã bị xóa. Chọn tài khoản khác.',
    ),
    'booking_method_invalid' => _w(
      context,
      'That way of paying was removed. Choose another.',
      'Cách thanh toán này đã bị xóa. Chọn cách khác.',
    ),
    'booking_methods_full' => _w(
      context,
      'The list of ways to pay is full.',
      'Danh sách cách thanh toán đã đầy.',
    ),
    'booking_deposit_refund_cancelled_only' => _w(
      context,
      'The deposit is part of the payment; it is given back only when the booking is cancelled.',
      'Tiền cọc là một phần tiền phòng; chỉ hoàn cọc khi đặt phòng đã hủy.',
    ),
    'booking_invalid_transition' => _w(
      context,
      'A cancelled booking only takes refunds.',
      'Đặt phòng đã hủy chỉ có thể hoàn tiền.',
    ),
    'booking_changed' => _w(
      context,
      'Someone changed this payment. Close and open it again.',
      'Lần thanh toán này vừa được người khác sửa. Đóng và mở lại.',
    ),
    'booking_currency_changed' || 'booking_invalid_conversion' => _w(
      context,
      'The currency or exchange rate changed. Reload and try again.',
      'Tiền tệ hoặc tỷ giá đã thay đổi. Tải lại rồi thử lại.',
    ),
    _ when code == 'permission-denied' => _w(
      context,
      'You don\'t have permission for this.',
      'Bạn không có quyền làm việc này.',
    ),
    _ => _w(
      context,
      'Couldn\'t save. Check your connection and try again.',
      'Không lưu được. Kiểm tra kết nối rồi thử lại.',
    ),
  };
}

/// The payments kept in the form for a new booking, worked out against the
/// total like the server does: each one records at most what is still owed.
List<Map<String, dynamic>> settleDrafts(
  List<Map<String, dynamic>> drafts,
  int? totalMinor,
) {
  var owed = totalMinor ?? 0;
  return [
    for (final d in drafts)
      () {
        final amount = d['amountMinor'] as int;
        final recorded = totalMinor == null
            ? amount
            : amount.clamp(0, owed < 0 ? 0 : owed);
        owed -= recorded;
        return {...d, 'recordedMinor': recorded, 'changeMinor': amount - recorded};
      }(),
  ];
}

/// What the server takes for one draft.
Map<String, dynamic> draftPayload(Map<String, dynamic> d) => {
  for (final k in [
    'kind',
    'paidOn',
    'amountMinor',
    'methodId',
    'accountId',
    'receivedById',
    'note',
    'inputCurrency',
    'inputAmountMinor',
    'ratesId',
  ])
    if (d[k] != null && !(k == 'note' && d[k] == '')) k: d[k],
  // A name typed once goes with its payment; a listed way is known by its id.
  if (d['methodId'] == 'other') 'methodLabel': d['methodLabel'],
};

class BookingPayments extends StatefulWidget {
  final TeamService service;
  final String organizationId, buildingId, currency;
  final String? bookingId;
  final MoneyForm conversion;
  final BookingPaymentOptions options;

  /// The booking's total (the price calculation), for a new booking.
  final int? totalMinor;
  final List<Map<String, dynamic>> drafts;
  final ValueChanged<List<Map<String, dynamic>>> onDraftsChanged;

  /// A saved booking's payments changed: the form re-reads the booking.
  final Future<void> Function() onSaved;

  /// A new way of paying was added.
  final ValueChanged<List<Map<String, dynamic>>> onMethodsChanged;

  /// Changes when the booking was read again, so the list reloads.
  final Object? reloadToken;
  final bool enabled;

  /// The payments shown, for the totals card (each one listed there).
  final ValueChanged<List<Map<String, dynamic>>>? onRows;

  /// The booking's status: a deposit is given back only when the booking is
  /// cancelled (2026-10-24, Tom: the deposit is part of the payment).
  final String? bookingStatus;
  const BookingPayments({
    super.key,
    required this.service,
    required this.organizationId,
    required this.buildingId,
    required this.currency,
    required this.conversion,
    required this.options,
    required this.onDraftsChanged,
    required this.onSaved,
    required this.onMethodsChanged,
    this.bookingId,
    this.totalMinor,
    this.drafts = const [],
    this.reloadToken,
    this.enabled = true,
    this.bookingStatus,
    this.onRows,
  });
  @override
  State<BookingPayments> createState() => _BookingPaymentsState();
}

class _BookingPaymentsState extends State<BookingPayments> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _summary;
  bool _loading = false;
  String? _error;
  int _load = 0;

  bool get _saved => widget.bookingId != null;
  bool get _cancelled =>
      ['cancelled', 'noShow'].contains(widget.bookingStatus);

  @override
  void initState() {
    super.initState();
    if (_saved) _reload();
  }

  @override
  void didUpdateWidget(covariant BookingPayments old) {
    super.didUpdateWidget(old);
    if (_saved &&
        (old.bookingId != widget.bookingId ||
            old.reloadToken != widget.reloadToken)) {
      _reload();
    }
  }

  Future<void> _reload() async {
    final id = widget.bookingId, load = ++_load;
    if (id == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.service.bookingWorkspace({
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'action': 'receipts',
        'bookingId': id,
      });
      if (!mounted || load != _load) return;
      setState(() {
        _summary = r;
        _rows = [
          for (final x in (r['records'] as List? ?? const []))
            Map<String, dynamic>.from(x as Map),
        ];
      });
      widget.onRows?.call(_rows);
    } catch (_) {
      if (mounted && load == _load) {
        setState(
          () => _error = _w(
            context,
            'Couldn\'t load the payments.',
            'Không tải được các lần thanh toán.',
          ),
        );
      }
    } finally {
      if (mounted && load == _load) setState(() => _loading = false);
    }
  }

  String _money(num minor) => appMoneyMinor(minor, widget.currency);

  bool get _canCollect =>
      _summary?['canCollect'] as bool? ?? widget.options.canCollect;
  bool get _canRefund =>
      _summary?['canRefund'] as bool? ?? widget.options.canRefund;
  bool get _canEdit => _summary?['canEdit'] as bool? ?? widget.options.canEdit;

  /// Still owed, deposit received and room money received (minor units).
  ({int owed, int deposit, int room}) get _balances {
    if (_saved) {
      final s = _summary ?? const {};
      final paid = s['paidMinor'] as int? ?? 0,
          deposit = s['depositMinor'] as int? ?? 0,
          held = s['heldDepositMinor'] as int? ?? 0;
      return (
        owed: s['remainingMinor'] as int? ?? 0,
        deposit: deposit + held,
        room: paid - deposit,
      );
    }
    final settled = settleDrafts(widget.drafts, widget.totalMinor);
    final paid = settled.fold<int>(0, (a, d) => a + (d['recordedMinor'] as int));
    return (
      owed: (widget.totalMinor ?? 0) - paid,
      deposit: 0,
      room: 0,
    );
  }

  Future<void> _open({Map<String, dynamic>? row, int? draftIndex}) async {
    final b = _balances;
    // Editing: what it would be without this payment.
    var owed = b.owed, deposit = b.deposit, room = b.room;
    if (row != null) {
      final amount = (row['amountMinor'] as num).toInt();
      if (row['kind'] == 'refund') {
        owed -= amount;
        if (row['refundFrom'] == 'deposit') {
          deposit += amount;
        } else {
          room += amount;
        }
      } else if (draftIndex != null) {
        owed += (row['recordedMinor'] as int? ?? amount);
      } else {
        owed += amount;
        if (row['kind'] == 'deposit') {
          deposit -= amount;
        } else {
          room -= amount;
        }
      }
    }
    final result = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BookingPaymentDialog(
        service: widget.service,
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        bookingId: widget.bookingId,
        currency: widget.currency,
        conversion: widget.conversion,
        options: widget.options,
        number: draftIndex != null
            ? draftIndex + 1
            : row != null
            ? _rows.indexOf(row) + 1
            : (_saved ? _rows.length : widget.drafts.length) + 1,
        row: row,
        owedMinor: owed < 0 ? 0 : owed,
        totalMinor: _saved
            ? (_summary?['totalMinor'] as int? ?? 0)
            : (widget.totalMinor ?? 0),
        depositRefundAllowed: _cancelled || row?['refundFrom'] == 'deposit',
        cancelled: _cancelled,
        depositMinor: deposit,
        roomMinor: room,
        canRefund: _saved && _canRefund,
        canDelete:
            _saved &&
            row != null &&
            _canEdit &&
            (row['kind'] != 'refund' || _canRefund),
        onMethodsChanged: widget.onMethodsChanged,
      ),
    );
    if (!mounted || result == null) return;
    if (result is Map<String, dynamic>) {
      final next = [...widget.drafts];
      if (draftIndex != null) {
        next[draftIndex] = result;
      } else {
        next.add(result);
      }
      widget.onDraftsChanged(next);
    } else if (result == true) {
      await _reload();
      await widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final rows = _saved
        ? _rows
        : settleDrafts(widget.drafts, widget.totalMinor);
    final total = _saved
        ? (_summary?['totalMinor'] as int?)
        : widget.totalMinor;
    final owedAfter = total == null
        ? null
        : runningOwed(rows, total, draft: !_saved);
    // A cancelled booking only gives money back (needs "Hoàn tiền").
    final canAdd =
        widget.enabled &&
        !_loading &&
        (_cancelled ? _canRefund : _canCollect);
    return Column(
      key: const ValueKey('booking-payments'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              TextButton(
                onPressed: _reload,
                child: Text(_w(context, 'Retry', 'Thử lại')),
              ),
            ],
          ),
        if (!_loading && _error == null && rows.isEmpty)
          Text(
            _w(context, 'No payments yet.', 'Chưa có lần thanh toán nào.'),
            style: muted,
          ),
        for (var i = 0; i < rows.length; i++)
          _PaymentRow(
            key: ValueKey('booking-payment-row-$i'),
            index: i,
            row: rows[i],
            owedAfter: owedAfter?[i],
            money: _money,
            methods: widget.options.methods,
            draft: !_saved,
            canEdit:
                widget.enabled &&
                (!_saved ||
                    _canEdit &&
                        (rows[i]['kind'] != 'refund' || _canRefund)),
            onEdit: () => _open(
              row: rows[i],
              draftIndex: _saved ? null : i,
            ),
            onRemove: _saved || !widget.enabled
                ? null
                : () => widget.onDraftsChanged([...widget.drafts]..removeAt(i)),
          ),
        if (!_canCollect)
          Padding(
            padding: const EdgeInsets.only(top: WsSpace.sm),
            child: Text(
              _w(
                context,
                'Taking payments needs "Collect payments".',
                'Thu tiền cần quyền "Thu tiền".',
              ),
              style: muted,
            ),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsets.only(top: WsSpace.sm),
            child: OutlinedButton.icon(
              key: const ValueKey('booking-add-payment'),
              onPressed: canAdd ? () => _open() : null,
              icon: const Icon(Icons.add),
              label: Text(
                _w(context, 'Add payment', 'Thêm lần thanh toán'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final int index;
  final Map<String, dynamic> row;

  /// Still owed once this payment is counted.
  final int? owedAfter;
  final String Function(num) money;
  final List<Map<String, dynamic>> methods;
  final bool draft, canEdit;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;
  const _PaymentRow({
    super.key,
    required this.index,
    required this.row,
    this.owedAfter,
    required this.money,
    required this.methods,
    required this.draft,
    required this.canEdit,
    required this.onEdit,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final refund = row['kind'] == 'refund';
    final amount = (draft ? row['recordedMinor'] : row['amountMinor']) as num;
    final change = (row['changeMinor'] as num?) ?? 0;
    final who = row['methodId'] == 'cash' || row['paymentMethod'] == 'cash'
        ? row['receivedByName']
        : row['accountLabel'];
    final details = [
      _methodLabel(context, row['methodId'] as String?, row['methodLabel'] as String?, methods),
      if ('${who ?? ''}'.isNotEmpty) '$who',
      if (change > 0)
        _w(context, 'Change: {c}', 'Tiền thối: {c}').replaceAll('{c}', money(change)),
      if ('${row['note'] ?? ''}'.isNotEmpty) '${row['note']}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: WsSpace.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${index + 1}', style: muted),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: WsSpace.sm,
                  runSpacing: WsSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${row['paidOn'] ?? ''}'),
                    WsPill(
                      paymentKindLabel(
                        context,
                        row['kind'] as String?,
                        row['refundFrom'] as String?,
                      ),
                      tone: refund ? WsTone.warning : WsTone.info,
                    ),
                    Text(
                      '${refund ? '− ' : ''}${money(amount)}',
                      style: theme.textTheme.titleSmall,
                    ),
                  ],
                ),
                if (details.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: WsSpace.xs),
                    child: Text(details, style: muted),
                  ),
                if (owedAfter != null)
                  Padding(
                    key: ValueKey('booking-payment-left-$index'),
                    padding: const EdgeInsets.only(top: WsSpace.xs),
                    child: Text(
                      _w(context, 'Still owed: {m}', 'Còn lại: {m}')
                          .replaceAll(
                            '{m}',
                            money(owedAfter! < 0 ? 0 : owedAfter!),
                          ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (canEdit)
            TextButton(
              key: ValueKey('booking-payment-edit-$index'),
              onPressed: onEdit,
              child: Text(_w(context, 'Edit', 'Sửa')),
            ),
          if (onRemove != null)
            IconButton(
              key: ValueKey('booking-payment-remove-$index'),
              tooltip: _w(context, 'Remove', 'Xóa'),
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

/// "Lần thanh toán N": add a payment, or change one already recorded.
/// Pops with true (saved), or the draft map for a new booking, or null.
class BookingPaymentDialog extends StatefulWidget {
  final TeamService service;
  final String organizationId, buildingId, currency;
  final String? bookingId;
  final MoneyForm conversion;
  final BookingPaymentOptions options;
  final int number, owedMinor, depositMinor, roomMinor, totalMinor;

  /// "Từ tiền cọc" only for a cancelled booking (or a deposit refund already
  /// recorded that is being changed).
  final bool depositRefundAllowed;

  /// A cancelled booking takes only refunds.
  final bool cancelled;
  final Map<String, dynamic>? row;
  final bool canRefund;

  /// "Xóa" on a recorded payment (needs "Sửa lần thanh toán").
  final bool canDelete;
  final ValueChanged<List<Map<String, dynamic>>> onMethodsChanged;
  const BookingPaymentDialog({
    super.key,
    required this.service,
    required this.organizationId,
    required this.buildingId,
    required this.currency,
    required this.conversion,
    required this.options,
    required this.number,
    required this.owedMinor,
    required this.totalMinor,
    required this.depositRefundAllowed,
    this.cancelled = false,
    required this.depositMinor,
    required this.roomMinor,
    required this.canRefund,
    this.canDelete = false,
    required this.onMethodsChanged,
    this.bookingId,
    this.row,
  });
  @override
  State<BookingPaymentDialog> createState() => _BookingPaymentDialogState();
}

class _BookingPaymentDialogState extends State<BookingPaymentDialog> {
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController(),
      _amount = TextEditingController(),
      _note = TextEditingController(),
      _method = TextEditingController();
  late String _kind;
  String _refundFrom = 'deposit';
  String? _receivedById, _accountId, _error;
  late List<Map<String, dynamic>> _methods = [...widget.options.methods];
  bool _busy = false;
  Map<String, dynamic>? _pending;

  String get _inputCurrency => widget.conversion.currency(widget.currency);
  bool get _refund => _kind == 'refund';

  /// Thanh toán bằng (2026-10-24, Tom): typed, or picked from the list while
  /// typing. A name in the list is that way of paying; anything else is new.
  List<(String, String)> get _methodChoices => [
    ('cash', _w(context, 'Cash', 'Tiền mặt')),
    ('bankTransfer', _w(context, 'Bank transfer', 'Chuyển khoản')),
    for (final m in _methods) ('${m['id']}', '${m['label']}'),
  ];
  static String _plain(String v) =>
      v.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  /// The way of paying for the typed name, or null when it is not in the list.
  String? get _methodId {
    final typed = _plain(_method.text);
    if (typed.isEmpty) return null;
    for (final (id, label) in _methodChoices) {
      if (_plain(label) == typed) return id;
    }
    // Both languages' names of the two built-in ways.
    if (['tiền mặt', 'cash'].contains(typed)) return 'cash';
    if (['chuyển khoản', 'bank transfer'].contains(typed)) {
      return 'bankTransfer';
    }
    // A payment kept with a name typed once.
    if (widget.row?['methodId'] == 'other' &&
        _plain('${widget.row?['methodLabel'] ?? ''}') == typed) {
      return 'other';
    }
    return null;
  }

  bool get _cash => _methodId == 'cash';

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _kind = r?['kind'] as String? ?? (widget.owedMinor > 0 ? 'room' : 'refund');
    _refundFrom =
        r?['refundFrom'] as String? ??
        (_depositLeft > 0 ? 'deposit' : 'room');
    if (!_kinds.contains(_kindValue)) _setKind(_kinds.first);
    final methodId = r?['methodId'] as String? ?? 'cash';
    _date.text = r?['paidOn'] as String? ?? widget.options.today;
    if (r != null) {
      final typed = (r['tenderedMinor'] ?? r['amountMinor']) as num;
      widget.conversion.set(_amount, typed.toInt(), widget.currency);
      _note.text = '${r['note'] ?? ''}';
    }
    _receivedById = r == null
        ? widget.options.myStaffId
        : r['receivedById'] as String?;
    _accountId =
        r?['accountId'] as String? ??
        (widget.options.accounts.length == 1
            ? '${widget.options.accounts.single['id']}'
            : null);
    // A saved way of paying removed since stays shown on its old payment.
    if (!['cash', 'bankTransfer', 'other'].contains(methodId) &&
        !_methods.any((m) => m['id'] == methodId)) {
      _methods.add({'id': methodId, 'label': r?['methodLabel'] ?? methodId});
    }
    _method.text = switch (methodId) {
      'cash' => '',
      'other' => '${r?['methodLabel'] ?? ''}',
      _ => '',
    };
  }

  bool _methodSet = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The label needs the language, so it is filled here once.
    if (_methodSet) return;
    _methodSet = true;
    final id = widget.row?['methodId'] as String? ?? 'cash';
    if (id == 'other') return;
    _method.text =
        _methodChoices.where((c) => c.$1 == id).firstOrNull?.$2 ??
        '${widget.row?['methodLabel'] ?? ''}';
  }

  @override
  void dispose() {
    for (final c in [_date, _amount, _note, _method]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The type as the list shows it: a refund is "refund:deposit" (Hoàn tiền
  /// cọc) or "refund:room" (Hoàn tiền phòng), 2026-10-24 (Tom).
  String get _kindValue => _refund ? 'refund:$_refundFrom' : _kind;
  void _setKind(String v) {
    if (v.startsWith('refund:')) {
      _kind = 'refund';
      _refundFrom = v.substring(7);
    } else {
      _kind = v;
    }
  }

  List<String> get _kinds {
    final r = widget.row;
    if (r != null) {
      // A payment stays a payment and a refund stays the same refund.
      return r['kind'] == 'refund'
          ? ['refund:${r['refundFrom'] ?? 'room'}']
          : paymentKinds.where((k) => k != 'refund').toList();
    }
    final refunds = [
      if (widget.canRefund && _depositLeft > 0) 'refund:deposit',
      if (widget.canRefund && widget.roomMinor > 0) 'refund:room',
    ];
    if (widget.cancelled) return refunds.isEmpty ? ['refund:room'] : refunds;
    return [
      if (widget.owedMinor > 0) ...paymentKinds.where((k) => k != 'refund'),
      ...refunds,
      if (widget.owedMinor <= 0 && refunds.isEmpty) 'room',
    ];
  }

  /// The deposit that may be given back here.
  int get _depositLeft =>
      widget.depositRefundAllowed ? widget.depositMinor : 0;

  int? get _typedMinor =>
      widget.conversion.parseText(_amount.text, widget.currency);

  String _money(num minor) => appMoneyMinor(minor, widget.currency);

  String? _dateProblem(String v) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(v);
    final d = m == null
        ? null
        : DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    String two(int x) => x.toString().padLeft(2, '0');
    final real =
        d != null &&
        '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}' ==
            v;
    final today = widget.options.today;
    return real && (today.isEmpty || v.compareTo(today) <= 0)
        ? null
        : _w(context, 'Choose a day up to today.', 'Chọn ngày không sau hôm nay.');
  }

  Future<void> _pickDay() async {
    final today = DateTime.tryParse(widget.options.today) ?? DateTime.now();
    final current = DateTime.tryParse(_date.text.trim());
    final date = await showDatePicker(
      context: context,
      initialDate: current != null && !current.isAfter(today) ? current : today,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
    );
    if (date == null || !mounted) return;
    String two(int v) => v.toString().padLeft(2, '0');
    setState(
      () => _date.text = '${date.year}-${two(date.month)}-${two(date.day)}',
    );
  }

  /// A name not in the list: keep it for everyone ("Lưu vào danh sách"), use
  /// it only for this payment ("Chỉ lần này"), or go back (null).
  Future<String?> _askToSave(String label) => showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      key: const ValueKey('payment-method-ask'),
      title: Text(_w(context, 'New way to pay?', 'Cách thanh toán mới?')),
      content: Text(
        _w(
          context,
          '"{m}" is not in the list. Save it so it can be picked next time?',
          '"{m}" chưa có trong danh sách. Lưu lại để lần sau chọn?',
        ).replaceAll('{m}', label),
      ),
      actions: [
        TextButton(
          key: const ValueKey('payment-method-once'),
          onPressed: () => Navigator.pop(context, 'once'),
          child: Text(_w(context, 'Just this once', 'Chỉ lần này')),
        ),
        FilledButton(
          key: const ValueKey('payment-method-keep'),
          onPressed: () => Navigator.pop(context, 'keep'),
          child: Text(_w(context, 'Save to list', 'Lưu vào danh sách')),
        ),
      ],
    ),
  );

  /// Saves a new way of paying for the organization; its id, or null.
  Future<String?> _keepMethod(String label) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.service.bookingWorkspace({
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'action': 'paymentMethod',
        'operationId': const Uuid().v4(),
        'label': label,
      });
      if (!mounted) return null;
      final list = [
        for (final m in (r['methods'] as List? ?? const []))
          Map<String, dynamic>.from(m as Map),
      ];
      widget.onMethodsChanged(list);
      setState(() => _methods = list);
      return '${r['methodId']}';
    } catch (e) {
      if (mounted) setState(() => _error = paymentError(context, e));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic>? _build(String methodId) {
    final amount = _typedMinor;
    if (amount == null || amount <= 0) return null;
    final cash = methodId == 'cash';
    return {
      'kind': _kind,
      if (_refund) 'refundFrom': _refundFrom,
      'paidOn': _date.text.trim(),
      'amountMinor': amount,
      'methodId': methodId,
      if (methodId == 'other')
        'methodLabel': _method.text.trim().replaceAll(RegExp(r'\s+'), ' '),
      if (cash && _receivedById != null) 'receivedById': _receivedById,
      if (!cash && _accountId != null) 'accountId': _accountId,
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      if (_inputCurrency != widget.currency) ...{
        'inputCurrency': _inputCurrency,
        'inputAmountMinor': appParseMoney(_amount.text, _inputCurrency),
        if (widget.conversion.conversion?.snapshotId != null)
          'ratesId': widget.conversion.conversion!.snapshotId,
      },
    };
  }

  Future<void> _save() async {
    if (_pending == null) {
      if (!_form.currentState!.validate()) return;
      if (!_refund && widget.owedMinor <= 0) {
        setState(
          () => _error = _w(
            context,
            'Nothing is owed on this booking.',
            'Đặt phòng này không còn tiền phải trả.',
          ),
        );
        return;
      }
      var methodId = _methodId;
      if (methodId == null) {
        final label = _method.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        final choice = await _askToSave(label);
        if (!mounted || choice == null) return;
        methodId = choice == 'keep' ? await _keepMethod(label) : 'other';
        if (!mounted || methodId == null) return;
        // The saved name shows as picked from now on.
        if (methodId != 'other') {
          _method.text =
              _methodChoices.where((c) => c.$1 == methodId).firstOrNull?.$2 ??
              label;
        }
      }
      final x = _build(methodId);
      if (x == null) return;
      if (widget.bookingId == null) {
        // A new booking: kept in the form, saved with the booking.
        final cash = methodId == 'cash';
        final person = widget.options.staff
            .where((s) => s['id'] == _receivedById)
            .firstOrNull;
        final account = widget.options.accounts
            .where((a) => a['id'] == _accountId)
            .firstOrNull;
        Navigator.pop(context, <String, dynamic>{
          ...x,
          'receivedByName': cash ? (person?['displayName']) : null,
          'accountLabel': cash ? null : account?['label'],
          'methodLabel': _method.text.trim(),
        });
        return;
      }
      final r = widget.row;
      _pending = {
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'action': 'receipt',
        'bookingId': widget.bookingId,
        'operationId': const Uuid().v4(),
        if (r != null) ...{
          'paymentId': r['paymentId'],
          'receiptRevision': r['revision'],
        },
        ...x,
      };
    }
    await _send();
  }

  /// "Xóa" (2026-10-24, Tom): after asking, the payment is taken off; the
  /// server keeps it as cancelled in history.
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('payment-delete-ask'),
        title: Text(
          _w(context, 'Delete payment {n}?', 'Xóa lần thanh toán {n}?')
              .replaceAll('{n}', '${widget.number}'),
        ),
        content: Text(
          _w(
            context,
            'Its amount comes off what was paid. Activity history keeps a record.',
            'Số tiền sẽ được trừ khỏi số đã thanh toán. Lịch sử hoạt động vẫn ghi lại.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_w(context, 'Close', 'Đóng')),
          ),
          FilledButton(
            key: const ValueKey('payment-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_w(context, 'Delete', 'Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _pending = {
      'organizationId': widget.organizationId,
      'buildingId': widget.buildingId,
      'action': 'removeReceipt',
      'bookingId': widget.bookingId,
      'operationId': const Uuid().v4(),
      'paymentId': widget.row!['paymentId'],
      'receiptRevision': widget.row!['revision'],
    };
    await _send();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.bookingWorkspace(_pending!);
      if (!mounted) return;
      _pending = null;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      // A lost answer keeps the same request, so trying again cannot record
      // the payment twice. A refusal lets the person change what they typed.
      final uncertain =
          e is! FirebaseFunctionsException ||
          ['unavailable', 'internal', 'deadline-exceeded', 'unknown']
              .contains(e.code);
      if (!uncertain) _pending = null;
      setState(
        () => _error = uncertain
            ? _w(
                context,
                'Not sure it was saved. Press Save again; it won\'t be recorded twice.',
                'Chưa chắc đã lưu. Bấm Lưu lần nữa; sẽ không bị ghi hai lần.',
              )
            : paymentError(context, e),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _dropdown<T>({
    required Key key,
    required String label,
    required T? value,
    required List<(T?, String)> items,
    required ValueChanged<T?>? onChanged,
  }) => DropdownButtonFormField<T?>(
    key: key,
    initialValue: value,
    isExpanded: true,
    style: Theme.of(context).textTheme.bodyLarge,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final (v, text) in items)
        DropdownMenuItem<T?>(
          value: v,
          child: Text(text, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged,
  );

  /// Thanh toán bằng: type, or pick from the list that narrows while typing.
  Widget _methodField(bool locked) => RawAutocomplete<String>(
    textEditingController: _method,
    focusNode: _methodFocus,
    optionsBuilder: (value) {
      final typed = _plain(value.text);
      final labels = [for (final c in _methodChoices) c.$2];
      // The whole list when the box is empty or holds a name from it.
      if (typed.isEmpty || labels.any((l) => _plain(l) == typed)) {
        return labels;
      }
      return labels.where((l) => _plain(l).contains(typed));
    },
    onSelected: (_) => setState(() => _error = null),
    fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
        TextFormField(
          key: const ValueKey('payment-method'),
          controller: controller,
          focusNode: focusNode,
          readOnly: locked,
          maxLength: 40,
          onChanged: (_) => setState(() => _error = null),
          decoration: InputDecoration(
            labelText: _w(context, 'Paid by', 'Thanh toán bằng'),
            counterText: '',
            suffixIcon: const Icon(Icons.arrow_drop_down),
          ),
          validator: (v) => (v ?? '').trim().isEmpty
              ? _w(context, 'Choose or type a way to pay.', 'Chọn hoặc nhập cách thanh toán.')
              : null,
        ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: AlignmentDirectional.topStart,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240, maxWidth: 280),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final o in options)
                ListTile(
                  key: ValueKey('payment-method-option-$o'),
                  dense: true,
                  title: Text(o),
                  onTap: () => onSelected(o),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  final _methodFocus = FocusNode();

  /// A row of the running sum.
  Widget _sumLine(String label, String value, {bool strong = false, Key? key}) {
    final style = strong
        ? Theme.of(context).textTheme.titleSmall
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: WsSpace.sm),
          Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locked = _busy || _pending != null;
    final typed = _typedMinor ?? 0;
    final owed = widget.owedMinor;
    final change = !_refund && typed > owed ? typed - owed : 0;
    // What is still owed once this payment (or refund) is counted, worked
    // out while typing (2026-10-24, Tom).
    final after = _refund ? owed + typed : (owed - typed < 0 ? 0 : owed - typed);
    final staff = [
      ...widget.options.staff,
      if (_receivedById != null &&
          !widget.options.staff.any((s) => s['id'] == _receivedById))
        {
          'id': _receivedById,
          'displayName': widget.row?['receivedByName'] ?? _receivedById,
        },
    ];
    final accounts = [
      ...widget.options.accounts,
      if (_accountId != null &&
          !widget.options.accounts.any((a) => a['id'] == _accountId))
        {'id': _accountId, 'label': widget.row?['accountLabel'] ?? _accountId},
    ];
    final canDelete = widget.row != null && widget.canDelete;
    return PopScope(
      canPop: !locked,
      child: AlertDialog(
        key: const ValueKey('booking-payment-dialog'),
        title: Text(
          widget.row == null
              ? _w(context, 'Payment {n}', 'Lần thanh toán {n}')
                    .replaceAll('{n}', '${widget.number}')
              : _w(context, 'Edit payment {n}', 'Sửa lần thanh toán {n}')
                    .replaceAll('{n}', '${widget.number}'),
        ),
        content: SizedBox(
          width: 520,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_busy) const LinearProgressIndicator(),
                  const SizedBox(height: WsSpace.sm),
                  WsFieldRow(
                    children: [
                      TextFormField(
                        key: const ValueKey('payment-date'),
                        controller: _date,
                        readOnly: locked,
                        decoration: InputDecoration(
                          labelText: _w(context, 'Date', 'Ngày'),
                          hintText: widget.options.today,
                          suffixIcon: IconButton(
                            tooltip: _w(context, 'Pick a date', 'Chọn ngày'),
                            icon: const Icon(Icons.event_outlined),
                            onPressed: locked ? null : _pickDay,
                          ),
                        ),
                        validator: (v) => _dateProblem((v ?? '').trim()),
                      ),
                      _dropdown<String>(
                        key: const ValueKey('payment-kind'),
                        label: _w(context, 'Type', 'Loại'),
                        value: _kindValue,
                        items: [
                          for (final k in _kinds)
                            (k, paymentKindLabel(context, k)),
                        ],
                        onChanged: locked || _kinds.length < 2
                            ? null
                            : (v) => setState(() {
                                if (v != null) _setKind(v);
                                _error = null;
                              }),
                      ),
                    ],
                  ),
                  const SizedBox(height: WsSpace.md),
                  WsFieldRow(
                    children: [
                      TextFormField(
                        key: const ValueKey('payment-amount'),
                        controller: _amount,
                        readOnly: locked,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: _inputCurrency == 'USD',
                        ),
                        inputFormatters: appMoneyInput(_inputCurrency),
                        onChanged: (_) => setState(() => _error = null),
                        decoration: InputDecoration(
                          labelText: _refund
                              ? _w(context, 'Amount refunded', 'Số tiền hoàn')
                              : _w(context, 'Amount', 'Số tiền'),
                          suffixText: _inputCurrency,
                        ),
                        validator: (v) {
                          final value = _typedMinor;
                          if (value == null || value <= 0) {
                            return _w(
                              context,
                              'Enter an amount.',
                              'Nhập số tiền.',
                            );
                          }
                          final limit = _refundFrom == 'deposit'
                              ? widget.depositMinor
                              : widget.roomMinor;
                          if (_refund && value > limit) {
                            return _w(
                              context,
                              'More than was received ({m}).',
                              'Lớn hơn số đã nhận ({m}).',
                            ).replaceAll('{m}', _money(limit));
                          }
                          return null;
                        },
                      ),
                      _methodField(locked),
                    ],
                  ),
                  const SizedBox(height: WsSpace.md),
                  // "Còn lại", worked out while the amount is typed
                  // (2026-10-24, Tom): what is still owed once this payment
                  // (or refund) counts, and the change to give back.
                  Padding(
                    padding: const EdgeInsets.only(top: WsSpace.sm),
                    child: Text(
                      [
                        _w(context, 'Still owed: {m}', 'Còn lại: {m}')
                            .replaceAll('{m}', _money(after)),
                        if (change > 0)
                          _w(context, 'Change: {m}', 'Tiền thối: {m}')
                              .replaceAll('{m}', _money(change)),
                      ].join(' · '),
                      key: const ValueKey('payment-left'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: WsSpace.md),
                  if (_cash)
                    _dropdown<String>(
                      key: const ValueKey('payment-received-by'),
                      // A refund is money paid out (2026-10-24, Tom).
                      label: _refund
                          ? _w(context, 'Paid out by', 'Người chi tiền')
                          : _w(context, 'Received by', 'Người nhận tiền'),
                      value: _receivedById,
                      items: [
                        (null, _w(context, 'Not set', 'Chưa chọn')),
                        for (final s in staff)
                          ('${s['id']}', '${s['displayName']}'),
                      ],
                      onChanged: locked
                          ? null
                          : (v) => setState(() => _receivedById = v),
                    )
                  else
                    _dropdown<String>(
                      key: const ValueKey('payment-account'),
                      label: _refund
                          ? _w(context, 'Paid from account', 'Tài khoản chi')
                          : _w(context, 'Receiving account', 'Tài khoản nhận'),
                      value: _accountId,
                      items: [
                        (null, _w(context, 'Not set', 'Chưa chọn')),
                        for (final a in accounts)
                          ('${a['id']}', '${a['label']}'),
                      ],
                      onChanged: locked
                          ? null
                          : (v) => setState(() => _accountId = v),
                    ),
                  const SizedBox(height: WsSpace.md),
                  TextFormField(
                    key: const ValueKey('payment-note'),
                    controller: _note,
                    readOnly: locked,
                    maxLines: null,
                    maxLength: 500,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: InputDecoration(
                      labelText: _w(context, 'Note', 'Ghi chú'),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: WsSpace.sm),
                      child: Text(
                        _error!,
                        key: const ValueKey('payment-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          if (canDelete)
            TextButton(
              key: const ValueKey('payment-delete'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: locked ? null : _delete,
              child: Text(_w(context, 'Delete', 'Xóa')),
            ),
          TextButton(
            onPressed: locked ? null : () => Navigator.pop(context),
            child: Text(_w(context, 'Close', 'Đóng')),
          ),
          FilledButton(
            key: const ValueKey('payment-save'),
            onPressed: _busy ? null : _save,
            child: Text(_w(context, 'Save', 'Lưu')),
          ),
        ],
      ),
    );
  }
}
