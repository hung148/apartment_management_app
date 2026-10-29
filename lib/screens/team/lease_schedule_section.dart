// Bảng thanh toán theo kỳ (PAYMENT_SCHEDULE.md, Tom 2026-10-26): the lease's
// payment periods. Wide screens: a table; phones / large text: one card per
// kỳ. Tap Khoảng thuê, Hạn thu or Tổng tiền to change it; "…" splits a kỳ
// (Tách kỳ) or joins it into the one before (Gộp). An invoiced kỳ is locked.
// The server checks everything again (tenantLeases action "schedule").
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'service_fee_text.dart' show addDays;
import 'ws_ui.dart';

class LeaseScheduleSection extends StatefulWidget {
  final TeamService service;
  final String organizationId, buildingId, tenantId;

  /// The kỳ's invoice (Chi tiết → when it has one).
  final ValueChanged<String> onOpenInvoice;

  /// "Lập hóa đơn kỳ" for this kỳ: start, end (exclusive) and Hạn thu.
  final void Function(String start, String end, String due) onNewInvoice;

  /// Over the calendar (Tom, 2026-10-26): only the count and "Xem bảng", so a
  /// long table does not push the other sections down; the whole table opens
  /// in its own dialog.
  final bool summary;

  /// Inside that dialog: no card around the table (the dialog has the title).
  final bool bare;
  const LeaseScheduleSection({
    super.key,
    required this.service,
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.onOpenInvoice,
    required this.onNewInvoice,
    this.summary = false,
    this.bare = false,
  });
  @override
  State<LeaseScheduleSection> createState() => _LeaseScheduleSectionState();
}

class _LeaseScheduleSectionState extends State<LeaseScheduleSection> {
  Map<String, dynamic>? _data;
  bool _busy = false, _saving = false;
  String? _error, _notice;
  int _generation = 0;

  static const _known = [
    'schedule_changed',
    'schedule_row_locked',
    'schedule_moves_locked',
    'schedule_past_contract_end',
    'schedule_before_move_in',
    'schedule_invalid_dates',
    'schedule_due_outside',
    'schedule_reason_required',
    'schedule_amount_below_surcharges',
    'schedule_split_outside',
    'schedule_merge_only_one',
    'schedule_needs_end',
    'schedule_lease_closed',
    'schedule_row_not_found',
    'lease_price_authority',
    'lease_backdate_owner_admin_required',
  ];

  Map<String, dynamic> get _scope => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
    'action': 'schedule',
    'tenantId': widget.tenantId,
  };

  bool get _vi => AppTranslations.of(context).locale.languageCode == 'vi';
  String w(String en, String vi) => _vi ? vi : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LeaseScheduleSection old) {
    super.didUpdateWidget(old);
    if (old.tenantId != widget.tenantId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _load();
    }
  }

  Future<void> _load({String? notice}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      _notice = notice;
    });
    try {
      final r = await widget.service.tenantLeases({..._scope, 'op': 'read'});
      if (!mounted || generation != _generation) return;
      setState(() => _data = Map<String, dynamic>.from(r['record'] as Map));
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'load');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  /// One change; on success the table is read again (the server rebuilt it).
  /// Returns null when saved, or the message to show next to the inputs.
  Future<String?> _send(Map<String, dynamic> change) async {
    if (_saving) return null;
    setState(() => _saving = true);
    try {
      await widget.service.tenantLeases({
        ..._scope,
        'revision': _data!['revision'],
        ...change,
      });
      if (!mounted) return null;
      await _load();
      return null;
    } catch (e) {
      final key = serverReason(e, _known);
      if (key == 'schedule_changed') {
        // Someone else changed it: show the latest; the dialog closes.
        if (mounted) await _load(notice: _message('schedule_changed'));
        return null;
      }
      return _message(key);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _message(String key) => switch (key) {
    'schedule_changed' => w(
      'Someone else changed this table. It was reloaded.',
      'Đã có người khác sửa bảng này. Bảng đã được tải lại.',
    ),
    'schedule_row_locked' => w(
      'This period has an invoice. Cancel the invoice to change it.',
      'Kỳ này đã có hóa đơn. Hủy hóa đơn để sửa.',
    ),
    'schedule_moves_locked' => w(
      'This would move a period that has an invoice.',
      'Thay đổi này sẽ làm dời một kỳ đã có hóa đơn.',
    ),
    'schedule_past_contract_end' => w(
      'This would push a period past the contract end date.',
      'Thay đổi này đẩy một kỳ qua ngày hết hạn hợp đồng.',
    ),
    'schedule_before_move_in' => w(
      'Period 1 cannot start before the move-in date.',
      'Kỳ 1 không thể bắt đầu trước ngày vào ở.',
    ),
    'schedule_invalid_dates' => w(
      'The start must be before the end.',
      'Ngày bắt đầu phải trước ngày kết thúc.',
    ),
    'schedule_due_outside' => w(
      'The due date must be inside the period.',
      'Hạn thu phải nằm trong kỳ.',
    ),
    'schedule_reason_required' => w(
      'Enter why the amount differs.',
      'Nhập lý do số tiền khác.',
    ),
    'schedule_amount_below_surcharges' => w(
      'The amount must be more than the surcharges of this period.',
      'Số tiền phải lớn hơn phụ thu của kỳ này.',
    ),
    'schedule_split_outside' => w(
      'Pick a day inside the period (not its first day).',
      'Chọn một ngày trong kỳ (không phải ngày đầu kỳ).',
    ),
    'schedule_merge_only_one' => w(
      'There is only one period.',
      'Chỉ còn một kỳ.',
    ),
    'schedule_lease_closed' => w(
      'This lease has ended; its periods cannot change.',
      'Hợp đồng đã kết thúc; không sửa kỳ được nữa.',
    ),
    'lease_price_authority' => w(
      'Changing the amount needs the "Change prices" permission.',
      'Đổi số tiền cần quyền "Đổi giá".',
    ),
    'lease_backdate_owner_admin_required' => w(
      'Dates before today need the "Enter past dates" permission.',
      'Ngày trước hôm nay cần quyền "Nhập ngày trong quá khứ".',
    ),
    _ => w(
      'Could not save. Check the connection and try again.',
      'Không lưu được. Kiểm tra kết nối rồi thử lại.',
    ),
  };

  String get _currency => _data?['currency'] as String? ?? 'VND';
  String _money(int? minor) =>
      minor == null ? '—' : appMoneyMinor(minor, _currency);
  static String _dm(String date) =>
      '${date.substring(8)}/${date.substring(5, 7)}';
  static String _dmy(String date) =>
      '${date.substring(8)}/${date.substring(5, 7)}/${date.substring(0, 4)}';
  // The table shows the last day included (end is exclusive on the server).
  static String _last(String end) => addDays(end, -1);

  String _length(Map r) {
    final months = r['wholeMonths'] as int?;
    if (months != null) {
      return w('$months month${months == 1 ? '' : 's'}', '$months tháng');
    }
    final days = r['days'] as int;
    return w('$days day${days == 1 ? '' : 's'}', '$days ngày');
  }

  bool _editable(Map r) =>
      _data!['canEdit'] == true && r['locked'] != true && !_saving && !_busy;

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final rows = [
      for (final r in (data?['rows'] as List? ?? const []))
        Map<String, dynamic>.from(r as Map),
    ];
    final invoiced = rows.where((r) => r['locked'] == true).length;
    final children = <Widget>[
        if (_busy || _saving) const LinearProgressIndicator(),
        if (_notice != null)
          WsNotice(_notice!, key: const ValueKey('schedule-notice')),
        if (_error == 'load')
          WsNotice(
            w(
              'Could not load the payment table.',
              'Không tải được bảng thanh toán.',
            ),
            key: const ValueKey('schedule-load-error'),
            tone: WsTone.warning,
            action: TextButton(
              onPressed: _busy ? null : _load,
              child: Text(w('Try again', 'Thử lại')),
            ),
          )
        else if (data != null && data['needsEnd'] == true)
          WsNotice(
            w(
              'Set the contract end date first (Edit in the contract section). The periods are made from it.',
              'Hãy đặt ngày hết hạn hợp đồng trước (Sửa ở mục Hợp đồng). Các kỳ được tạo theo ngày này.',
            ),
            key: const ValueKey('schedule-needs-end'),
          )
        else if (data != null && rows.isEmpty)
          WsEmpty(
            icon: Icons.event_busy_outlined,
            message: w('No periods.', 'Không có kỳ nào.'),
          )
        else if (data != null && widget.summary)
          Row(
            children: [
              Expanded(child: _count(rows.length, invoiced)),
              const SizedBox(width: WsSpace.sm),
              OutlinedButton.icon(
                key: const ValueKey('schedule-open'),
                onPressed: _busy || _saving ? null : _openDialog,
                icon: const Icon(Icons.table_rows_outlined, size: 18),
                label: Text(w('Open table', 'Xem bảng'), maxLines: 1),
              ),
            ],
          )
        else if (data != null) ...[
          _count(rows.length, invoiced),
          const SizedBox(height: WsSpace.sm),
          LayoutBuilder(
            builder: (context, c) {
              final wide =
                  c.maxWidth >= 640 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 14 * 1.3;
              return wide ? _table(rows) : _cards(rows);
            },
          ),
        ],
    ];
    if (widget.bare) {
      return Column(
        key: const ValueKey('lease-schedule'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return WsSection(
      key: const ValueKey('lease-schedule'),
      title: _title,
      icon: Icons.event_note_outlined,
      children: children,
    );
  }

  String get _title => w('Payment by period', 'Bảng thanh toán theo kỳ');

  Widget _count(int count, int invoiced) => Text(
    w(
      '$count period${count == 1 ? '' : 's'} · $invoiced invoiced',
      '$count kỳ · $invoiced đã lập hóa đơn',
    ),
    key: const ValueKey('schedule-count'),
    style: Theme.of(context).textTheme.bodySmall,
  );

  /// The whole table in its own dialog (full screen on phones). Chi tiết
  /// closes it first, then opens the invoice / the period invoice form on
  /// the page; closing it reloads the count here.
  Future<void> _openDialog() async {
    String? invoice;
    List<String>? period;
    final theme = Theme.of(context);
    await showDialog<void>(
      context: context,
      builder: (c) {
        final size = MediaQuery.sizeOf(c);
        final body = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                WsSpace.lg,
                WsSpace.sm,
                WsSpace.sm,
                WsSpace.sm,
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_note_outlined, size: 20),
                  const SizedBox(width: WsSpace.sm),
                  Expanded(
                    child: Text(_title, style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    key: const ValueKey('schedule-dialog-close'),
                    tooltip: w('Close', 'Đóng'),
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                // Small margins so the table (≥ 640 px) fits sooner
                // (live check 2026-10-26: cards in a narrow window).
                padding: const EdgeInsets.symmetric(
                  horizontal: WsSpace.md,
                  vertical: WsSpace.lg,
                ),
                child: LeaseScheduleSection(
                  service: widget.service,
                  organizationId: widget.organizationId,
                  buildingId: widget.buildingId,
                  tenantId: widget.tenantId,
                  bare: true,
                  onOpenInvoice: (id) {
                    invoice = id;
                    Navigator.pop(c);
                  },
                  onNewInvoice: (a, b, d) {
                    period = [a, b, d];
                    Navigator.pop(c);
                  },
                ),
              ),
            ),
          ],
        );
        return Theme(
          data: theme,
          child: size.width < 640
              ? Dialog.fullscreen(
                  key: const ValueKey('schedule-dialog'),
                  child: SafeArea(child: body),
                )
              : Dialog(
                  key: const ValueKey('schedule-dialog'),
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: WsSpace.lg,
                    vertical: WsSpace.xl,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 1000,
                      maxHeight: size.height * 0.9,
                    ),
                    child: body,
                  ),
                ),
        );
      },
    );
    if (!mounted) return;
    if (invoice != null) {
      widget.onOpenInvoice(invoice!);
    } else if (period != null) {
      widget.onNewInvoice(period![0], period![1], period![2]);
    } else {
      _load();
    }
  }

  // ── Wide: one row per kỳ ───────────────────────────────────────────
  Widget _table(List<Map<String, dynamic>> rows) {
    final theme = Theme.of(context);
    final head = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // Money columns get the same room; a gap keeps texts from touching
    // (live check 2026-10-26: "5,000,000 VND" wrapped at an 800 px window).
    const flex = [22, 14, 19, 19, 19, 12];
    Widget cell(int i, Widget child) => Expanded(
      flex: flex[i],
      child: Padding(
        padding: const EdgeInsets.only(right: WsSpace.sm),
        child: child,
      ),
    );
    return Column(
      key: const ValueKey('schedule-table'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: WsSpace.sm),
          child: Row(
            children: [
              cell(
                0,
                Text(w('Period / Dates', 'Kỳ thu / Khoảng thuê'), style: head),
              ),
              cell(1, Text(w('Due', 'Hạn thu'), style: head)),
              cell(2, Text(w('Total', 'Tổng tiền'), style: head)),
              cell(3, Text(w('Paid', 'Đã thu'), style: head)),
              cell(4, Text(w('Left to pay', 'Còn phải thu'), style: head)),
              cell(5, const SizedBox()),
              const SizedBox(width: 40),
            ],
          ),
        ),
        for (final (i, r) in rows.indexed) ...[
          const Divider(height: 1),
          Padding(
            key: ValueKey('schedule-row-${r['id']}'),
            padding: const EdgeInsets.symmetric(vertical: WsSpace.sm),
            child: Row(
              children: [
                cell(0, _periodCell(i, r)),
                cell(1, _dueCell(r)),
                cell(2, _amountCell(r)),
                cell(3, _oneLine(_money(r['paidMinor'] as int?))),
                cell(4, _oneLine(_money(r['leftMinor'] as int?))),
                cell(
                  5,
                  Align(alignment: Alignment.centerLeft, child: _details(r)),
                ),
                SizedBox(width: 40, child: _menu(i, rows)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ── Phones / large text: one card per kỳ ───────────────────────────
  Widget _cards(List<Map<String, dynamic>> rows) => Column(
    key: const ValueKey('schedule-cards'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, r) in rows.indexed)
        Card(
          key: ValueKey('schedule-row-${r['id']}'),
          margin: const EdgeInsets.only(bottom: WsSpace.sm),
          child: Padding(
            padding: const EdgeInsets.all(WsSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _periodCell(i, r)),
                    _menu(i, rows),
                  ],
                ),
                const SizedBox(height: WsSpace.sm),
                _labelled(w('Due', 'Hạn thu'), _dueCell(r)),
                _labelled(w('Total', 'Tổng tiền'), _amountCell(r)),
                _labelled(
                  w('Paid', 'Đã thu'),
                  Text(_money(r['paidMinor'] as int?)),
                ),
                _labelled(
                  w('Left to pay', 'Còn phải thu'),
                  Text(_money(r['leftMinor'] as int?)),
                ),
                Align(alignment: Alignment.centerRight, child: _details(r)),
              ],
            ),
          ),
        ),
    ],
  );

  /// Money on one line: shrinks a little instead of wrapping "VND".
  Widget _oneLine(String text) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: Text(text, maxLines: 1, softWrap: false),
  );

  Widget _labelled(String label, Widget value) => Padding(
    padding: const EdgeInsets.only(bottom: WsSpace.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: value),
      ],
    ),
  );

  /// A value the user can tap to change (only when allowed).
  Widget _tap(String key, bool enabled, VoidCallback onTap, Widget child) =>
      enabled
      ? InkWell(
          key: ValueKey(key),
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: child,
          ),
        )
      : KeyedSubtree(key: ValueKey(key), child: child);

  Widget _periodCell(int i, Map<String, dynamic> r) {
    final theme = Theme.of(context);
    return _tap(
      'schedule-dates-${r['id']}',
      _editable(r),
      () => _editDates(i, r),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                w('Period ${i + 1}', 'Kỳ ${i + 1}'),
                style: theme.textTheme.titleSmall,
              ),
              if (r['locked'] == true) ...[
                const SizedBox(width: WsSpace.xs),
                Tooltip(
                  message: w('Has an invoice', 'Đã có hóa đơn'),
                  child: Icon(
                    Icons.lock_outline,
                    key: ValueKey('schedule-locked-${r['id']}'),
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
          Text(
            '${_dm(r['start'] as String)} – ${_dm(_last(r['end'] as String))}',
            style: theme.textTheme.bodySmall,
          ),
          Text(_length(r), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _dueCell(Map<String, dynamic> r) => _tap(
    'schedule-due-${r['id']}',
    _editable(r),
    () => _editDue(r),
    Text(_dmy(r['due'] as String)),
  );

  Widget _amountCell(Map<String, dynamic> r) {
    final theme = Theme.of(context);
    final reason = r['reason'] as String?;
    return _tap(
      'schedule-amount-${r['id']}',
      _editable(r) && _data!['canPrice'] == true,
      () => _editAmount(r),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _oneLine(_money(r['amountMinor'] as int)),
          if (r['amountEdited'] == true && reason != null && reason.isNotEmpty)
            Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _details(Map<String, dynamic> r) {
    final invoice = r['invoiceId'] as String?;
    final canBill = _data!['canBill'] == true;
    return TextButton(
      key: ValueKey('schedule-details-${r['id']}'),
      onPressed: _busy || _saving || (invoice == null && !canBill)
          ? null
          : () => invoice != null
                ? widget.onOpenInvoice(invoice)
                : widget.onNewInvoice(
                    r['start'] as String,
                    r['end'] as String,
                    r['due'] as String,
                  ),
      // "→" is not in Roboto (it showed nothing): "›".
      child: Text(w('Details ›', 'Chi tiết ›'), maxLines: 1, softWrap: false),
    );
  }

  Widget _menu(int i, List<Map<String, dynamic>> rows) {
    final r = rows[i];
    final neighbour = i == 0
        ? (rows.length > 1 ? rows[1] : null)
        : rows[i - 1];
    final canMerge = neighbour != null && neighbour['locked'] != true;
    if (!_editable(r)) return const SizedBox(width: 40);
    return PopupMenuButton<String>(
      key: ValueKey('schedule-menu-${r['id']}'),
      tooltip: w('More', 'Thêm'),
      icon: const Icon(Icons.more_horiz),
      onSelected: (v) => v == 'split' ? _split(r) : _merge(i, r),
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const ValueKey('schedule-split'),
          value: 'split',
          enabled: (r['days'] as int) > 1,
          child: Text(w('Split period', 'Tách kỳ')),
        ),
        PopupMenuItem(
          key: const ValueKey('schedule-merge'),
          value: 'merge',
          enabled: canMerge,
          child: Text(
            i == 0
                ? w('Join into period 2', 'Gộp vào kỳ 2')
                : w('Join into period $i', 'Gộp vào kỳ $i'),
          ),
        ),
      ],
    );
  }

  // ── Dialogs ────────────────────────────────────────────────────────
  static final _dateShape = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static bool _validDate(String v) {
    if (!_dateShape.hasMatch(v)) return false;
    final d = DateTime.tryParse('${v}T00:00:00Z');
    return d != null && d.toIso8601String().startsWith(v);
  }

  String? _dateCheck(String v) => _validDate(v.trim())
      ? null
      : w('Use the form YYYY-MM-DD.', 'Nhập theo dạng YYYY-MM-DD.');

  Future<void> _editDates(int i, Map<String, dynamic> r) async {
    final start = TextEditingController(text: r['start'] as String);
    final end = TextEditingController(text: _last(r['end'] as String));
    await _dialog(
      title: w('Period ${i + 1} dates', 'Ngày của kỳ ${i + 1}'),
      help: i == 0
          ? w(
              'Later periods move with it. Period 1 may start after move-in; those days are not billed.',
              'Các kỳ sau dời theo. Kỳ 1 có thể bắt đầu sau ngày vào ở; những ngày đó không tính tiền.',
            )
          : w(
              'The start moves the end of period $i too. Later periods move with it.',
              'Đổi ngày bắt đầu cũng đổi ngày kết thúc của kỳ $i. Các kỳ sau dời theo.',
            ),
      fields: [
        _field(
          'schedule-start',
          w('From (YYYY-MM-DD)', 'Từ ngày (YYYY-MM-DD)'),
          start,
          _dateCheck,
        ),
        _field(
          'schedule-end',
          w(
            'To, last day included (YYYY-MM-DD)',
            'Đến ngày, ngày cuối tính tiền (YYYY-MM-DD)',
          ),
          end,
          _dateCheck,
        ),
      ],
      submit: () => {
        'op': 'edit',
        'rowId': r['id'],
        if (start.text.trim() != r['start']) 'start': start.text.trim(),
        if (addDays(end.text.trim(), 1) != r['end'])
          'end': addDays(end.text.trim(), 1),
      },
    );
  }

  Future<void> _editDue(Map<String, dynamic> r) async {
    final due = TextEditingController(text: r['due'] as String);
    await _dialog(
      title: w('Due date', 'Hạn thu'),
      fields: [
        _field(
          'schedule-due',
          w('Due (YYYY-MM-DD)', 'Hạn thu (YYYY-MM-DD)'),
          due,
          _dateCheck,
        ),
      ],
      submit: () => {
        'op': 'edit',
        'rowId': r['id'],
        if (due.text.trim() != r['due']) 'due': due.text.trim(),
      },
    );
  }

  Future<void> _editAmount(Map<String, dynamic> r) async {
    final amount = TextEditingController(
      text: appMoneyInputText(r['amountMinor'] as int, _currency),
    );
    final reason = TextEditingController(text: r['reason'] as String? ?? '');
    final calculated = r['defaultMinor'] as int;
    await _dialog(
      title: w('Total', 'Tổng tiền'),
      help: w(
        'Calculated: ${_money(calculated)} (rent + surcharges). Another amount needs a reason.',
        'Tính ra: ${_money(calculated)} (tiền thuê + phụ thu). Số tiền khác cần lý do.',
      ),
      fields: [
        _field(
          'schedule-amount',
          '${w('Total', 'Tổng tiền')} ($_currency)',
          amount,
          (v) {
            final minor = appParseMoney(v, _currency);
            return minor == null || minor <= 0
                ? w('Enter an amount.', 'Nhập số tiền.')
                : null;
          },
          max: 24,
          formatters: appMoneyInput(_currency),
          keyboard: TextInputType.numberWithOptions(
            decimal: _currency == 'USD',
          ),
        ),
        _field(
          'schedule-reason',
          w('Reason for the change', 'Lý do đổi giá'),
          reason,
          (v) {
            final minor = appParseMoney(amount.text, _currency);
            return minor != null && minor != calculated && v.trim().isEmpty
                ? w('Enter why the amount differs.', 'Nhập lý do số tiền khác.')
                : null;
          },
          max: 1000,
        ),
      ],
      submit: () {
        final minor = appParseMoney(amount.text, _currency);
        return {
          'op': 'edit',
          'rowId': r['id'],
          if (minor != r['amountMinor'] ||
              reason.text.trim() != (r['reason'] ?? ''))
            'amountMinor': minor,
          if (reason.text.trim().isNotEmpty && minor != calculated)
            'reason': reason.text.trim(),
        };
      },
    );
  }

  Future<void> _split(Map<String, dynamic> r) async {
    final date = TextEditingController();
    final first = _dm(addDays(r['start'] as String, 1)),
        last = _dm(_last(r['end'] as String));
    await _dialog(
      title: w('Split period', 'Tách kỳ'),
      help: w(
        'Pick the day the second period starts ($first – $last).',
        'Chọn ngày kỳ thứ hai bắt đầu ($first – $last).',
      ),
      fields: [
        _field(
          'schedule-split-date',
          w('Second period starts (YYYY-MM-DD)', 'Kỳ sau bắt đầu (YYYY-MM-DD)'),
          date,
          _dateCheck,
        ),
      ],
      submit: () => {'op': 'split', 'rowId': r['id'], 'date': date.text.trim()},
    );
  }

  Future<void> _merge(int i, Map<String, dynamic> r) async {
    final into = i == 0 ? 2 : i;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(w('Join this period?', 'Gộp kỳ này?')),
        content: Text(
          w(
            'Period ${i + 1} becomes part of period $into. Are you sure?',
            'Kỳ ${i + 1} sẽ gộp vào kỳ $into. Bạn có chắc?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(w('Cancel', 'Hủy')),
          ),
          FilledButton(
            key: const ValueKey('schedule-merge-confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(w('Join', 'Gộp')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final error = await _send({'op': 'merge', 'rowId': r['id']});
    if (error != null && mounted) setState(() => _notice = error);
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller,
    String? Function(String) check, {
    int max = 10,
    List<TextInputFormatter>? formatters,
    TextInputType? keyboard,
  }) => Padding(
    padding: const EdgeInsets.only(top: WsSpace.md),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      maxLength: max,
      inputFormatters: formatters,
      keyboardType: keyboard,
      decoration: InputDecoration(labelText: label, counterText: ''),
      validator: (v) => check(v ?? ''),
    ),
  );

  /// A small form dialog. The server's refusal shows next to the buttons and
  /// what was typed stays. Nothing changed: it just closes.
  /// The callers' text controllers are not disposed after it returns: the
  /// dialog's closing animation still uses them (a crash caught by
  /// lease_schedule_section_test); they are freed with the dialog.
  Future<void> _dialog({
    required String title,
    String? help,
    required List<Widget> fields,
    required Map<String, dynamic> Function() submit,
  }) async {
    final form = GlobalKey<FormState>();
    String? error;
    var sending = false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => PopScope(
          canPop: !sending,
          child: AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 420,
              child: Form(
                key: form,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (help != null)
                        Text(help, style: Theme.of(c).textTheme.bodySmall),
                      ...fields,
                      if (error != null) ...[
                        const SizedBox(height: WsSpace.md),
                        Text(
                          error!,
                          key: const ValueKey('schedule-dialog-error'),
                          style: TextStyle(
                            color: Theme.of(c).colorScheme.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(c),
                child: Text(w('Cancel', 'Hủy')),
              ),
              FilledButton(
                key: const ValueKey('schedule-save'),
                onPressed: sending
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        final change = submit();
                        if (change['op'] == 'edit' && change.length <= 2) {
                          Navigator.pop(c); // nothing changed
                          return;
                        }
                        set(() {
                          sending = true;
                          error = null;
                        });
                        final message = await _send(change);
                        if (!c.mounted) return;
                        if (message == null) {
                          Navigator.pop(c);
                        } else {
                          set(() {
                            sending = false;
                            error = message;
                          });
                        }
                      },
                child: Text(w('Save', 'Lưu')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
