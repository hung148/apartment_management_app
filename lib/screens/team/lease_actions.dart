import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../services/organization_money.dart';
import '../../utils/money_conversion.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'property_contract_screen.dart' show contractDate;
import 'ws_ui.dart';

/// Lease page actions (2026-10-04, Tom): the short forms that used to be
/// separate pages behind a row of buttons now open as small dialogs from the
/// section they belong to — the end date and the rent in "Hợp đồng", room
/// moves in its "…" menu, and a roommate's move-out on their page.
String leaseActionText(BuildContext context, String key) {
  final vi = AppTranslations.of(context).locale.languageCode == 'vi';
  const labels = <String, List<String>>{
    'edit': ['Edit', 'Sửa'],
    'change': ['Change', 'Đổi'],
    'save': ['Save', 'Lưu'],
    'cancel': ['Cancel', 'Hủy'],
    'close': ['Close', 'Đóng'],
    'retry': ['Try again', 'Thử lại'],
    'reason': ['Reason', 'Lý do'],
    'required': ['Required', 'Bắt buộc'],
    'badDate': ['Enter a date as YYYY-MM-DD.', 'Nhập ngày dạng YYYY-MM-DD.'],
    'endTitle': ['Contract end date', 'Ngày hết hạn hợp đồng'],
    'endDate': ['Ends on (YYYY-MM-DD)', 'Hết hạn ngày (YYYY-MM-DD)'],
    'endAfterStart': [
      'The end date must be after the move-in day.',
      'Ngày hết hạn phải sau ngày dọn vào.',
    ],
    'rent': ['Monthly rent', 'Tiền thuê hằng tháng'],
    'rentTitle': ['Change rent', 'Đổi tiền thuê'],
    'rentFrom': [
      'From (YYYY-MM-DD, after today)',
      'Áp dụng từ (YYYY-MM-DD, sau hôm nay)',
    ],
    'rentNew': ['New monthly rent', 'Tiền thuê mới mỗi tháng'],
    'rentHelp': [
      'Invoices already made do not change.',
      'Hóa đơn đã lập không thay đổi.',
    ],
    'rentBadDate': [
      'Choose a day after today (and after the move-in day).',
      'Chọn ngày sau hôm nay (và sau ngày dọn vào).',
    ],
    'rentBad': ['Enter an amount above 0.', 'Nhập số tiền lớn hơn 0.'],
    'fromDay': ['From {date}', 'Từ {date}'],
    'perPeriod': ['Amount per period', 'Số tiền mỗi kỳ'],
    'perPeriodShort': ['{amount} per period', '{amount} mỗi kỳ'],
    // Fix 5 (2026-10-09, Tom): an amount agreed with the lease.
    'periodAgreed': [
      'Calculated {amount} · {reason} · changed by {name}',
      'Tính ra {amount} · {reason} · {name} đổi',
    ],
    'until': ['until {date}', 'đến {date}'],
    'planned': ['planned', 'đã lên lịch'],
    'applied': ['in effect', 'đang áp dụng'],
    'past': ['earlier', 'trước đây'],
    'cancelChange': ['Cancel this change', 'Hủy thay đổi này'],
    'cancelTitle': ['Cancel planned rent', 'Hủy tiền thuê đã lên lịch'],
    'cancelDo': ['Remove change', 'Bỏ thay đổi'],
    'moveTitle': ['Move to another room', 'Chuyển sang phòng khác'],
    'moveRoom': ['Move room', 'Chuyển phòng'],
    'room': ['New room', 'Phòng mới'],
    'roomNumber': ['Room {n}', 'Phòng {n}'],
    'liveWith': ['Lives with', 'Ở cùng'],
    'moveDate': ['Moved on (YYYY-MM-DD)', 'Ngày chuyển (YYYY-MM-DD)'],
    'noRooms': [
      'There is no other room to move to.',
      'Không có phòng khác để chuyển.',
    ],
    'noMain': [
      'Nobody lives in that room to stay with. Choose another room.',
      'Phòng đó chưa có người thuê chính để ở cùng. Chọn phòng khác.',
    ],
    'actualDate': [
      'Use the day it happened: today or earlier, after the move-in day.',
      'Nhập ngày đã diễn ra: hôm nay hoặc trước đó, sau ngày dọn vào.',
    ],
    'outTitle': ['Move out', 'Trả phòng'],
    'outDate': ['Moved out on (YYYY-MM-DD)', 'Ngày trả phòng (YYYY-MM-DD)'],
    'loadFailed': [
      'Could not load. Close and try again.',
      'Không tải được. Đóng rồi thử lại.',
    ],
    'failed': [
      'Could not save. Check the connection and try again.',
      'Không lưu được. Kiểm tra kết nối rồi thử lại.',
    ],
    'changed': [
      'Someone else changed this lease. Close and open it again.',
      'Hợp đồng vừa được người khác thay đổi. Đóng rồi mở lại.',
    ],
    'denied': [
      'You may not make this change (a past date needs the "enter past dates" right).',
      'Bạn không có quyền thay đổi này (ngày trong quá khứ cần quyền nhập ngày đã qua).',
    ],
    'roommatesFirst': [
      'The people living with this tenant must move out or move first.',
      'Người ở cùng cần trả phòng hoặc chuyển phòng trước.',
    ],
    'occupied': [
      'That room is taken on that day (a lease or a booking).',
      'Phòng đó đang có người thuê hoặc đặt phòng vào ngày này.',
    ],
    'problem': [
      'That room is closed by an open technical problem.',
      'Phòng đó đang tạm đóng vì có sự cố kỹ thuật.',
    ],
  };
  final pair = labels[key];
  return pair == null ? key : pair[vi ? 1 : 0];
}

String _money(BuildContext context, Object? minor, String currency) {
  if (minor is! num) return '';
  return appMoneyMinor(minor, currency);
}

/// The message for a refused save, or null when retrying may help.
String? _refusal(FirebaseFunctionsException e) {
  if ([
    'unavailable',
    'internal',
    'deadline-exceeded',
    'unknown',
  ].contains(e.code)) {
    return null;
  }
  return switch (e.message) {
    'lease_handle_roommates_first' => 'roommatesFirst',
    'room_has_open_problem' => 'problem',
    'lease_actual_date_required' => 'actualDate',
    _ => switch (e.code) {
      'aborted' => 'changed',
      'already-exists' => 'occupied',
      'permission-denied' => 'denied',
      _ => 'failed',
    },
  };
}

/// A label and a value with a small button at the end ("Sửa", "Đổi").
class LeaseInfoAction extends StatelessWidget {
  final String label, value, action;
  final VoidCallback? onPressed;
  final Key? buttonKey;
  const LeaseInfoAction(
    this.label,
    this.value, {
    super.key,
    required this.action,
    this.onPressed,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: WsSpace.sm),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
          if (onPressed != null)
            TextButton(
              key: buttonKey,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: onPressed,
              child: Text(action, maxLines: 1),
            ),
        ],
      ),
    );
  }
}

/// The frame of every dialog here: title, a spinner while busy, a message,
/// the fields, then Cancel / the action.
class _ActionDialog extends StatelessWidget {
  final String title, action;
  final bool busy;
  final String? error;
  final List<Widget> children;
  final VoidCallback? onSave;
  final Key? saveKey;
  const _ActionDialog({
    required this.title,
    required this.action,
    required this.busy,
    required this.children,
    this.error,
    this.onSave,
    this.saveKey,
  });

  @override
  Widget build(BuildContext context) {
    String lt(String k) => leaseActionText(context, k);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(WsSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: WsSpace.md),
              if (busy) const LinearProgressIndicator(),
              if (error != null) WsNotice(error!),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
              const SizedBox(height: WsSpace.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: WsSpace.sm,
                runSpacing: WsSpace.sm,
                children: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => Navigator.pop(context, false),
                    child: Text(lt('cancel'), maxLines: 1),
                  ),
                  if (onSave != null)
                    FilledButton(
                      key: saveKey,
                      onPressed: busy ? null : onSave,
                      child: Text(action, maxLines: 1),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _field(
  BuildContext context,
  String key,
  TextEditingController controller,
  String label, {
  required bool enabled,
  String? Function(String)? check,
  TextInputType? keyboard,
  List<TextInputFormatter>? formatters,
  String? helper,
}) => Padding(
  padding: const EdgeInsets.only(bottom: WsSpace.sm),
  child: TextFormField(
    key: ValueKey(key),
    controller: controller,
    enabled: enabled,
    keyboardType: keyboard,
    inputFormatters: formatters,
    decoration: InputDecoration(labelText: label, helperText: helper),
    validator: (v) => check?.call((v ?? '').trim()),
  ),
);

String? _reasonCheck(BuildContext context, String v) => v.isEmpty
    ? leaseActionText(context, 'required')
    : v.length > 1000
    ? AppTranslations.of(context)['tenant_contacts_long']
    : null;

// ---- End date, room move and move-out (leaseLifecycle) ----

/// Which lease change a [_LifecycleDialog] makes.
enum LeaseChange { endDate, move, moveOut }

/// Opens the dialog for [change]; true when it was saved.
Future<bool> showLeaseChange(
  BuildContext context, {
  required LeaseChange change,
  required TeamService service,
  required String organizationId,
  required String buildingId,
  required String tenantId,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LifecycleDialog(
        change: change,
        service: service,
        identity: {
          'organizationId': organizationId,
          'buildingId': buildingId,
          'tenantId': tenantId,
        },
      ),
    ) ==
    true;

class _LifecycleDialog extends StatefulWidget {
  final LeaseChange change;
  final TeamService service;
  final Map<String, dynamic> identity;
  const _LifecycleDialog({
    required this.change,
    required this.service,
    required this.identity,
  });
  @override
  State<_LifecycleDialog> createState() => _LifecycleDialogState();
}

class _LifecycleDialogState extends State<_LifecycleDialog> {
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController(), _reason = TextEditingController();
  Map<String, dynamic>? _record, _pending;
  List<Map<String, dynamic>> _rooms = [];
  String? _room, _main, _error;
  bool _busy = true;
  String lt(String k) => leaseActionText(context, k);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _date.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await widget.service.leaseLifecycle({
        ...widget.identity,
        'action': 'read',
      });
      final rooms = widget.change == LeaseChange.move
          ? await widget.service.leaseLifecycle({
              ...widget.identity,
              'action': 'destinations',
            })
          : null;
      if (!mounted) return;
      setState(() {
        _record = Map<String, dynamic>.from(r['record'] as Map);
        _rooms = [
          for (final v in (rooms?['records'] as List? ?? const []))
            Map<String, dynamic>.from(v as Map),
        ];
        _date.text = widget.change == LeaseChange.endDate
            ? '${_record!['contractEndDate'] ?? ''}'
            : '${_record!['today'] ?? ''}';
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = lt('loadFailed');
        });
      }
    }
  }

  bool get _roommate => _record?['isMainTenant'] == false;
  List<Map> get _mains =>
      ((_rooms.where((v) => v['id'] == _room).firstOrNull?['mainTenants']
                  as List?) ??
              const [])
          .cast<Map>();

  Future<void> _save() async {
    final r = _record;
    if (_busy || r == null) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    _pending ??= {
      ...widget.identity,
      'action': switch (widget.change) {
        LeaseChange.endDate => 'terms',
        LeaseChange.move => 'move',
        LeaseChange.moveOut => 'moveOut',
      },
      'operationId': const Uuid().v4(),
      'revision': r['revision'],
      'timeZone': r['timeZone'],
      'reason': _reason.text.trim(),
      if (widget.change == LeaseChange.endDate)
        'contractEndDate': _date.text.trim(),
      if (widget.change != LeaseChange.endDate)
        'effectiveDate': _date.text.trim(),
      if (widget.change == LeaseChange.move) 'destinationRoomId': _room,
      if (widget.change == LeaseChange.move)
        'destinationMainTenantId': _roommate ? _main : null,
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.leaseLifecycle(Map.of(_pending!));
      if (mounted) Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final why = _refusal(e);
      setState(() {
        _busy = false;
        // A refusal will not change on retry: let them fix the form.
        if (why != null) _pending = null;
        _error = lt(why ?? 'failed');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = lt('failed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _record;
    final locked = _busy || _pending != null;
    final title = lt(switch (widget.change) {
      LeaseChange.endDate => 'endTitle',
      LeaseChange.move => 'moveTitle',
      LeaseChange.moveOut => 'outTitle',
    });
    String? dateCheck(String v) {
      if (!contractDate(v)) return lt('badDate');
      final start = '${r?['startDate'] ?? ''}', today = '${r?['today'] ?? ''}';
      if (widget.change == LeaseChange.endDate) {
        return v.compareTo(start) <= 0 ? lt('endAfterStart') : null;
      }
      // A move or a move-out is something that already happened.
      return v.compareTo(today) > 0 || v.compareTo(start) <= 0
          ? lt('actualDate')
          : null;
    }

    return _ActionDialog(
      title: title,
      action: _pending != null ? lt('retry') : lt('save'),
      busy: _busy,
      error: _error,
      saveKey: const ValueKey('lease-change-save'),
      onSave: r == null || (widget.change == LeaseChange.move && _rooms.isEmpty)
          ? null
          : _save,
      children: [
        if (r != null)
          Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.change == LeaseChange.move) ...[
                  if (_rooms.isEmpty)
                    Text(lt('noRooms'))
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: WsSpace.sm),
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('lease-change-room'),
                        initialValue: _room,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: lt('room')),
                        items: [
                          for (final v in _rooms)
                            DropdownMenuItem(
                              value: v['id'] as String,
                              child: Text(
                                lt(
                                  'roomNumber',
                                ).replaceAll('{n}', '${v['roomNumber']}'),
                              ),
                            ),
                        ],
                        onChanged: locked
                            ? null
                            : (v) => setState(() {
                                _room = v;
                                _main = null;
                              }),
                        validator: (v) => v == null ? lt('required') : null,
                      ),
                    ),
                  // Someone who lives with a main tenant moves in with another.
                  if (_roommate && _room != null)
                    _mains.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: WsSpace.sm),
                            child: WsNotice(lt('noMain'), tone: WsTone.warning),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(bottom: WsSpace.sm),
                            child: DropdownButtonFormField<String>(
                              key: const ValueKey('lease-change-main'),
                              initialValue: _main,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: lt('liveWith'),
                              ),
                              items: [
                                for (final m in _mains)
                                  DropdownMenuItem(
                                    value: m['id'] as String,
                                    child: Text('${m['fullName']}'),
                                  ),
                              ],
                              onChanged: locked
                                  ? null
                                  : (v) => setState(() => _main = v),
                              validator: (v) =>
                                  v == null ? lt('required') : null,
                            ),
                          ),
                ],
                _field(
                  context,
                  'lease-change-date',
                  _date,
                  lt(switch (widget.change) {
                    LeaseChange.endDate => 'endDate',
                    LeaseChange.move => 'moveDate',
                    LeaseChange.moveOut => 'outDate',
                  }),
                  enabled: !locked,
                  check: dateCheck,
                ),
                _field(
                  context,
                  'lease-change-reason',
                  _reason,
                  lt('reason'),
                  enabled: !locked,
                  check: (v) => _reasonCheck(context, v),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---- Rent: today's rent, planned and earlier changes (tenantRent) ----

/// "Tiền thuê hằng tháng" in the lease section, with "Đổi" and the list of
/// rent changes (planned ones can be cancelled). Without the right to change
/// prices it shows just the rent.
class LeaseRentRows extends StatefulWidget {
  final String organizationId, buildingId, tenantId, currency;
  final Object? monthlyRentMinor, periodRentMinor;

  /// The amount per period agreed with the lease: the calculated amount,
  /// the reason and who changed it (Fix 5).
  final Map? periodRentOverride;

  /// Months per payment period (1 = monthly).
  final int periodMonths;

  /// May read and change the rent plan (the "Đổi giá" right).
  final bool canPrice, canEdit;
  final TeamService service;
  const LeaseRentRows({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.currency,
    required this.monthlyRentMinor,
    this.periodRentMinor,
    this.periodRentOverride,
    this.periodMonths = 1,
    required this.canPrice,
    required this.canEdit,
    required this.service,
  });
  @override
  State<LeaseRentRows> createState() => _LeaseRentRowsState();
}

class _LeaseRentRowsState extends State<LeaseRentRows> {
  Map<String, dynamic>? _record;
  int _generation = 0;
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'tenantId': widget.tenantId,
  };

  @override
  void initState() {
    super.initState();
    if (widget.canPrice) _load();
  }

  @override
  void didUpdateWidget(covariant LeaseRentRows old) {
    super.didUpdateWidget(old);
    if (old.tenantId != widget.tenantId || old.service != widget.service) {
      _record = null;
      if (widget.canPrice) _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final r = await widget.service.tenantRent({
        'action': 'read',
        ..._identity,
      });
      if (mounted && generation == _generation) {
        setState(() => _record = Map<String, dynamic>.from(r['record'] as Map));
      }
    } catch (_) {
      // The plain rent stays on screen.
    }
  }

  Future<void> _open({String? cancel}) async {
    final r = _record;
    if (r == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RentDialog(
        service: widget.service,
        identity: _identity,
        record: r,
        cancelDate: cancel,
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    String lt(String k) => leaseActionText(context, k);
    final theme = Theme.of(context);
    final r = _record;
    final currency = '${r?['currency'] ?? widget.currency}';
    final today = '${r?['today'] ?? ''}';
    final changes =
        [
          for (final c in (r?['changes'] as List? ?? const []))
            Map<String, dynamic>.from(c as Map),
        ]..sort(
          (a, b) => '${b['effectiveDate']}'.compareTo('${a['effectiveDate']}'),
        );
    // The change in effect today: the latest one on or before today.
    final current = changes
        .where((c) => '${c['effectiveDate']}'.compareTo(today) <= 0)
        .firstOrNull;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // Amount per period (2026-10-04, Tom: it must follow rent changes). A
    // special amount typed with the lease counts until the first rent change
    // (like the period invoice); after that it is rent × months.
    final months = widget.periodMonths < 1 ? 1 : widget.periodMonths;
    final base = r?['baseMinor'] ?? widget.monthlyRentMinor;
    final rentNow = r?['currentMinor'] ?? widget.monthlyRentMinor;
    final planned = changes.reversed
        .where((c) => '${c['effectiveDate']}'.compareTo(today) > 0)
        .firstOrNull;
    final special =
        widget.periodRentMinor is int &&
        base is int &&
        widget.periodRentMinor != base * months &&
        current == null;
    final perPeriod = special
        ? widget.periodRentMinor
        : rentNow is int
        ? rentNow * months
        : null;
    // The amount agreed with the lease, while it counts (Fix 5).
    final agreedPeriod = special ? widget.periodRentOverride : null;
    return Column(
      key: const ValueKey('lease-rent-rows'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LeaseInfoAction(
          lt('rent'),
          _money(
            context,
            r?['currentMinor'] ?? widget.monthlyRentMinor,
            currency,
          ),
          action: lt('change'),
          buttonKey: const ValueKey('lease-rent-change'),
          onPressed: r != null && widget.canEdit ? () => _open() : null,
        ),
        for (final c in changes)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 136, bottom: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      lt(
                        'fromDay',
                      ).replaceAll('{date}', '${c['effectiveDate']}'),
                      _money(context, c['amountMinor'], currency),
                      if (months > 1 && c['amountMinor'] is int)
                        lt('perPeriodShort').replaceAll(
                          '{amount}',
                          _money(
                            context,
                            (c['amountMinor'] as int) * months,
                            currency,
                          ),
                        ),
                      lt(
                        '${c['effectiveDate']}'.compareTo(today) > 0
                            ? 'planned'
                            : identical(c, current)
                            ? 'applied'
                            : 'past',
                      ),
                    ].join(' · '),
                    key: ValueKey('lease-rent-change-${c['effectiveDate']}'),
                    style: muted,
                  ),
                ),
                if ('${c['effectiveDate']}'.compareTo(today) > 0 &&
                    widget.canEdit)
                  IconButton(
                    key: ValueKey('lease-rent-cancel-${c['effectiveDate']}'),
                    tooltip: lt('cancelChange'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _open(cancel: '${c['effectiveDate']}'),
                  ),
              ],
            ),
          ),
        if (perPeriod != null && (months > 1 || special))
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: WsInfo(
              lt('perPeriod'),
              [
                _money(context, perPeriod, currency),
                if (special && planned != null)
                  lt(
                    'until',
                  ).replaceAll('{date}', '${planned['effectiveDate']}'),
              ].join(' · '),
              key: const ValueKey('lease-per-period'),
            ),
          ),
        if (agreedPeriod case final o?)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 136, bottom: 2),
            child: Text(
              lt('periodAgreed')
                  .replaceAll(
                    '{amount}',
                    _money(context, o['calculatedTotalMinor'], currency),
                  )
                  .replaceAll('{reason}', '${o['reason'] ?? ''}')
                  .replaceAll('{name}', '${o['byName'] ?? ''}'),
              key: const ValueKey('lease-period-agreed'),
              style: muted,
            ),
          ),
      ],
    );
  }
}

class _RentDialog extends StatefulWidget {
  final TeamService service;
  final Map<String, dynamic> identity, record;

  /// The planned change being cancelled, or null for a new change.
  final String? cancelDate;
  const _RentDialog({
    required this.service,
    required this.identity,
    required this.record,
    this.cancelDate,
  });
  @override
  State<_RentDialog> createState() => _RentDialogState();
}

class _RentDialogState extends State<_RentDialog> {
  late final _conversion = MoneyForm(
    OrganizationMoney.shared.forOrganization(
      widget.identity['organizationId'] as String,
    ),
  );
  final _form = GlobalKey<FormState>();
  final _date = TextEditingController(),
      _amount = TextEditingController(),
      _reason = TextEditingController();
  Map<String, dynamic>? _pending;
  bool _busy = false;
  String? _error;
  String lt(String k) => leaseActionText(context, k);

  @override
  void dispose() {
    _date.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    final r = widget.record, cancel = widget.cancelDate;
    _pending ??= {
      'action': cancel != null ? 'cancel' : 'schedule',
      ...widget.identity,
      'operationId': const Uuid().v4(),
      'revision': r['revision'],
      'currency': r['currency'],
      'timeZone': r['timeZone'],
      'effectiveDate': cancel ?? _date.text.trim(),
      'reason': _reason.text.trim(),
      if (cancel == null)
        'amountMinor': _conversion.parse(_amount, '${r['currency']}'),
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.tenantRent(Map.of(_pending!));
      if (mounted) Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final why = _refusal(e);
      setState(() {
        _busy = false;
        if (why != null) _pending = null;
        _error = lt(why ?? 'failed');
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = lt('failed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record, cancel = widget.cancelDate;
    final currency = '${r['currency']}';
    final locked = _busy || _pending != null;
    final planned = cancel == null
        ? null
        : (r['changes'] as List? ?? const [])
              .cast<Map>()
              .where((c) => c['effectiveDate'] == cancel)
              .firstOrNull;
    return _ActionDialog(
      title: lt(cancel != null ? 'cancelTitle' : 'rentTitle'),
      action: _pending != null
          ? lt('retry')
          : lt(cancel != null ? 'cancelDo' : 'save'),
      busy: _busy,
      error: _error,
      saveKey: const ValueKey('lease-rent-save'),
      onSave: _save,
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (cancel != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: WsSpace.md),
                  child: Text(
                    '${lt('fromDay').replaceAll('{date}', cancel)} · ${_money(context, planned?['amountMinor'], currency)}',
                  ),
                )
              else ...[
                _field(
                  context,
                  'lease-rent-date',
                  _date,
                  lt('rentFrom'),
                  enabled: !locked,
                  check: (v) =>
                      !contractDate(v) ||
                          v.compareTo('${r['today']}') <= 0 ||
                          v.compareTo('${r['startDate']}') < 0
                      ? lt('rentBadDate')
                      : null,
                ),
                _field(
                  context,
                  'lease-rent-amount',
                  _amount,
                  '${lt('rentNew')} (${_conversion.currency(currency)})',
                  enabled: !locked,
                  keyboard: TextInputType.numberWithOptions(
                    decimal: _conversion.currency(currency) == 'USD',
                  ),
                  formatters: appMoneyInput(_conversion.currency(currency)),
                  helper: lt('rentHelp'),
                  check: (v) => (_conversion.parse(_amount, currency) ?? 0) <= 0
                      ? lt('rentBad')
                      : null,
                ),
              ],
              _field(
                context,
                'lease-rent-reason',
                _reason,
                lt('reason'),
                enabled: !locked,
                check: (v) => _reasonCheck(context, v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
