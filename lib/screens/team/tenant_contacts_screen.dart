import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'workspace_page_scope.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'tenant_lease_screen.dart';
import 'lease_actions.dart';
import '../calendar/room_calendar.dart' show CalendarPageDialog;
import 'period_invoice_form.dart';
import 'move_out_settlement_form.dart';
import 'back_steps.dart';
import 'team_display.dart';
import 'ws_ui.dart';
import 'room_problems_section.dart';
import 'lease_surcharges.dart';
import 'lease_electricity.dart';

class TenantContactsScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;

  /// Null inside the organization workspace sections (U1): no Back button.
  /// Open this record first (from a link), then report what is open.
  final String? initialRecordId;
  final ValueChanged<String?>? onRecordChanged;
  final VoidCallback? onBack;

  /// Opened over the calendar (C): only [initialRecordId]'s page; "back to
  /// the list" calls this instead, and sub-pages return to that tenant.
  final VoidCallback? onClose;
  const TenantContactsScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    this.onBack,
    this.initialRecordId,
    this.onRecordChanged,
    this.onClose,
  });
  @override
  State<TenantContactsScreen> createState() => _TenantContactsScreenState();
}

class _TenantContactsScreenState extends State<TenantContactsScreen> {
  final _name = TextEditingController(), _phone = TextEditingController();
  final _form = GlobalKey<FormState>();
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic>? _pending;
  String? _selected, _revision, _cursor, _message;
  String _room = '', _status = '';
  Map<String, dynamic>? _detail;
  bool _busy = true, _saving = false;
  bool _creating = false;
  bool _showingSaved = false;
  // B6: the period invoice form for this tenant is open.
  String? _periodTenant;
  // B6b: the move-out settlement for this tenant is open.
  String? _settleTenant;
  int _generation = 0;
  Map<String, dynamic> get _identity => {
    'organizationId': widget.organizationId,
    'buildingId': widget.buildingId,
  };
  @override
  void initState() {
    super.initState();
    _openLink();
  }

  /// List first, then the linked tenant (if any).
  Future<void> _openLink() async {
    if (widget.onClose != null) {
      final link = widget.initialRecordId;
      if (link == null) {
        widget.onClose!();
      } else {
        await _read(link);
      }
      return;
    }
    await _list();
    final link = widget.initialRecordId;
    if (link != null && mounted && _selected == null) await _read(link);
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

  @override
  void didUpdateWidget(covariant TenantContactsScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _selected = null;
      _creating = false;
      _periodTenant = null;
      _settleTenant = null;
      _pending = null;
      _saving = false;
      _clear();
      _list();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _clear() {
    _name.clear();
    _phone.clear();
    _revision = null;
    _room = '';
    _status = '';
    _detail = null;
  }

  /// From a sub-page: the tenant's page over the calendar, else the list.
  void _back() {
    final home = widget.initialRecordId;
    if (widget.onClose != null && home != null) {
      _read(home);
    } else {
      _list();
    }
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
      _showingSaved = false;
      _message = null;
      _selected = null;
      _clear();
      if (!more) {
        _rows = [];
        _cursor = null;
      }
    });
    try {
      final existing = more
          ? List<Map<String, dynamic>>.of(_rows)
          : <Map<String, dynamic>>[];
      await for (final answer in widget.service.tenantListLive({
        'action': 'list',
        ..._identity,
        if (more) 'cursor': _cursor,
      })) {
        if (!mounted || generation != _generation) return;
        final result = answer.data;
        setState(() {
          final known = existing.map((v) => v['id']).toSet();
          _rows = [
            ...existing,
            ...(result['records'] as List)
                .map((v) => Map<String, dynamic>.from(v as Map))
                .where((v) => known.add(v['id'])),
          ];
          _cursor = result['nextCursor'] as String?;
          _showingSaved = answer.saved;
          // Show the copy immediately, but do not unlock actions until the
          // current server response has checked access.
          _busy = answer.saved;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _rows = [];
          _cursor = null;
          _showingSaved = false;
          _busy = false;
          _message = 'tenant_contacts_unavailable';
        });
      }
    }
  }

  Future<void> _read(String id, {bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _selected = id;
      _busy = true;
      _rows = [];
      _cursor = null;
      _message = null;
      _clear();
    });
    try {
      final result = await widget.service.tenantContacts({
        'action': 'read',
        ..._identity,
        'tenantId': id,
      });
      if (!mounted || generation != _generation) return;
      final row = result['record'] as Map;
      setState(() {
        _name.text = row['fullName'] as String;
        _phone.text = row['phoneNumber'] as String;
        _room = (row['roomNumber'] as String?)?.isNotEmpty == true
            ? row['roomNumber'] as String
            : row['roomId'] as String;
        _status = row['status'] as String;
        _detail = Map<String, dynamic>.from(row);
        _revision = row['revision'] as String;
        _busy = false;
        _message = saved ? 'tenant_contacts_saved' : null;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _clear();
          _busy = false;
          _message = 'tenant_contacts_unavailable';
        });
      }
    }
  }

  /// After a change made in a dialog on this page: reads the tenant again
  /// without emptying the page, so it stays where it was scrolled
  /// (2026-10-04, Tom). Falls back to a full read if that fails.
  Future<void> _refresh(String id) async {
    if (_selected != id || _detail == null) return _read(id);
    final generation = ++_generation;
    try {
      final result = await widget.service.tenantContacts({
        'action': 'read',
        ..._identity,
        'tenantId': id,
      });
      if (!mounted || generation != _generation) return;
      final row = Map<String, dynamic>.from(result['record'] as Map);
      setState(() {
        // Keep what is being typed in the contact box.
        if (_name.text == _detail!['fullName']) {
          _name.text = row['fullName'] as String;
        }
        if (_phone.text == _detail!['phoneNumber']) {
          _phone.text = row['phoneNumber'] as String;
        }
        _room = (row['roomNumber'] as String?)?.isNotEmpty == true
            ? row['roomNumber'] as String
            : row['roomId'] as String;
        _status = row['status'] as String;
        _detail = row;
        _revision = row['revision'] as String;
      });
    } catch (_) {
      if (mounted && generation == _generation) await _read(id);
    }
  }

  Future<void> _save() async {
    if (_busy || _saving || _revision == null) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    _pending ??= Map.unmodifiable({
      'action': 'update',
      ..._identity,
      'tenantId': _selected,
      'revision': _revision,
      'operationId': const Uuid().v4(),
      'fullName': _name.text.trim(),
      'phoneNumber': _phone.text.trim(),
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.service.tenantContacts(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      _pending = null;
      _saving = false;
      await _read(_selected!, saved: true);
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _message = 'tenant_contacts_uncertain';
        if (e is FirebaseFunctionsException) {
          if ([
            'permission-denied',
            'unauthenticated',
            'not-found',
          ].contains(e.code)) {
            _pending = null;
            _clear();
            _message = 'tenant_contacts_unavailable';
          } else if (e.code == 'aborted') {
            _pending = null;
            _revision = null;
            _message = 'tenant_contacts_conflict';
          } else if ([
            'invalid-argument',
            'failed-precondition',
            'already-exists',
          ].contains(e.code)) {
            _pending = null;
            _message = 'tenant_contacts_rejected';
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    _reportRecord(_selected);
    if (_settleTenant != null) {
      // Back and Done both return to this tenant's page (now moved out).
      final tenant = _settleTenant!;
      void close() {
        setState(() => _settleTenant = null);
        _read(tenant);
      }

      return BackStep(
        onBack: close,
        child: MoveOutSettlementForm(
          service: widget.service,
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          tenantId: tenant,
          backLabel: AppTranslations.of(context)['tenant_contacts_title'],
          onCancel: close,
          onDone: close,
        ),
      );
    }
    if (_periodTenant != null) {
      // Back and Done both return to this tenant's page.
      final tenant = _periodTenant!;
      void close() {
        setState(() => _periodTenant = null);
        _read(tenant);
      }

      return BackStep(
        onBack: close,
        child: PeriodInvoiceForm(
          service: widget.service,
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          tenantId: tenant,
          backLabel: AppTranslations.of(context)['tenant_contacts_title'],
          onCancel: close,
          onDone: close,
        ),
      );
    }
    if (_creating) {
      return BackStep(
        onBack: () {
          setState(() => _creating = false);
          _back();
        },
        child: TenantLeaseScreen(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          service: widget.service,
          onBack: () {
            setState(() => _creating = false);
            _back();
          },
        ),
      );
    }
    final t = AppTranslations.of(context),
        locked = _busy || _saving || _pending != null,
        editable = !locked && _revision != null;
    final vi = t.locale.languageCode == 'vi';
    String w(String en, String viText) => vi ? viText : en;
    String status(String value) =>
        ['active', 'inactive', 'suspended', 'moveOut'].contains(value)
        ? t['tenant_contacts_$value']
        : t['team_unspecified'];
    // 2026-10-04: the same four words as short stays.
    WsPill statusPill(Map<String, dynamic> row, {Key? key}) {
      final stay = row['stayStatus'] as String?;
      final value = row['status'] as String? ?? '';
      return switch (stay) {
        'deposited' => WsPill(
          w('Deposit paid – not checked in', 'Đã đặt cọc – chưa check in'),
          tone: WsTone.info,
          key: key,
        ),
        'notCheckedIn' => WsPill(
          w('Not checked in', 'Chưa check in'),
          tone: WsTone.warning,
          key: key,
        ),
        'staying' when value != 'suspended' => WsPill(
          w('Staying', 'Đang ở'),
          tone: WsTone.good,
          key: key,
        ),
        'checkedOut' => WsPill(
          w('Checked out', 'Đã check out'),
          tone: WsTone.neutral,
          key: key,
        ),
        _ => WsPill(
          status(value),
          tone: value == 'active'
              ? WsTone.good
              : value == 'suspended'
              ? WsTone.warning
              : WsTone.neutral,
          key: key,
        ),
      };
    }

    String money(Object? minor, Object? currency) {
      if (minor is! num) return '';
      return appMoneyMinor(minor, currency as String? ?? 'VND');
    }

    Widget field(
      String key,
      String label,
      TextEditingController controller,
      int max, {
      bool required = false,
    }) => Semantics(
      label: label,
      child: TextFormField(
        key: ValueKey(key),
        controller: controller,
        enabled: !locked,
        readOnly: !editable,
        maxLines: null,
        decoration: InputDecoration(labelText: label, errorMaxLines: 8),
        validator: (v) => required && (v ?? '').trim().isEmpty
            ? t['tenant_contacts_required']
            : (v ?? '').trim().length > max
            ? t['tenant_contacts_long']
            : null,
      ),
    );
    final d = _detail;
    String roomLine(Map<String, dynamic> row) {
      final room = teamRoomLabel(row);
      return room.isEmpty ? '' : '${w('Room', 'Phòng')} $room';
    }

    // The page for one tenant: contact, lease details and the lease actions.
    List<Widget> detail(Map<String, dynamic> r) {
      final id = _selected!;
      final months = r['paymentPeriodMonths'] as int?;
      final due = r['paymentDueDay'] as int?;
      final period = months == null
          ? ''
          : [
              months == 1
                  ? w('Every month', 'Hằng tháng')
                  : w('Every $months months', 'Mỗi $months tháng'),
              if (due != null) w('on day $due', 'vào ngày $due'),
            ].join(' ');
      final depositWay = switch (r['depositMethod']) {
        'cash' => w('cash', 'tiền mặt'),
        'bankTransfer' =>
          (r['depositAccountLabel'] as String? ?? '').isNotEmpty
              ? r['depositAccountLabel'] as String
              : w('bank transfer', 'chuyển khoản'),
        _ => '',
      };
      final residence = r['residenceRegistered'] == true
          ? [
              w('Registered', 'Đã đăng ký'),
              if ((r['residenceRegisteredLocalDate'] as String? ?? '')
                  .isNotEmpty)
                r['residenceRegisteredLocalDate'] as String,
            ].join(' · ')
          : w('Not registered', 'Chưa đăng ký');
      final hasLease = r['isMainTenant'] == true;
      // Still living here (not moved out): the lease can still change.
      final open =
          ['active', 'suspended'].contains(_status) &&
          (r['moveOutLocalDate'] as String? ?? '').isEmpty;
      Future<void> change(LeaseChange what) async {
        final saved = await showLeaseChange(
          context,
          change: what,
          service: widget.service,
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          tenantId: id,
        );
        if (saved && mounted) _refresh(id);
      }

      Future<void> addRoommate() async {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => CalendarPageDialog(
            title: t['roommate_form_title'],
            build: (close) => TenantLeaseScreen(
              organizationId: widget.organizationId,
              buildingId: widget.buildingId,
              service: widget.service,
              mainTenantId: id,
              onBack: close,
            ),
          ),
        );
        if (mounted) _refresh(id);
      }

      final roommates = ((r['roommates'] as List?) ?? const []).cast<Map>();
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(WsSpace.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WsBadge(text: _room),
                const SizedBox(width: WsSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r['fullName'] as String? ?? '',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if ((r['mainTenantName'] as String? ?? '').isNotEmpty)
                        Text(
                          w(
                            'Lives with ${r['mainTenantName']}',
                            'Ở cùng ${r['mainTenantName']}',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: WsSpace.sm),
                      statusPill({
                        ...r,
                        'status': _status,
                      }, key: const ValueKey('tenant-stay-status')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // The contract is over: the deposit goes back at the move-out settlement.
        if (hasLease &&
            r['contractEnded'] == true &&
            r['stayStatus'] != 'checkedOut')
          WsNotice(
            w(
              'The contract has ended. Settle the move-out to give the deposit back.',
              'Hợp đồng đã hết hạn. Quyết toán trả phòng để hoàn tiền cọc cho khách.',
            ),
            key: const ValueKey('lease-contract-ended'),
          ),
        WsSection(
          title: w('Papers', 'Giấy tờ'),
          icon: Icons.badge_outlined,
          children: [
            WsInfo(
              w('ID card (CCCD)', 'Số CCCD'),
              r['nationalId'] as String? ?? '',
            ),
            WsInfo(w('Temporary residence', 'Tạm trú'), residence),
          ],
        ),
        if (hasLease)
          WsSection(
            title: w('Lease', 'Hợp đồng'),
            icon: Icons.description_outlined,
            // Rare: moving the lease to another room (2026-10-04, Tom).
            trailing: open
                ? PopupMenuButton<String>(
                    key: ValueKey('lease-more-$id'),
                    tooltip: w('More', 'Thêm'),
                    icon: const Icon(Icons.more_horiz),
                    enabled: !locked,
                    onSelected: (_) => change(LeaseChange.move),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        key: const ValueKey('lease-move-room'),
                        value: 'move',
                        child: Text(leaseActionText(context, 'moveRoom')),
                      ),
                    ],
                  )
                : null,
            children: [
              WsInfo(
                w('Moved in', 'Ngày vào ở'),
                r['moveInLocalDate'] as String? ?? '',
              ),
              LeaseInfoAction(
                w('Contract ends', 'Hết hạn hợp đồng'),
                (r['contractEndLocalDate'] as String? ?? '').isEmpty
                    ? w('Open-ended', 'Không thời hạn')
                    : r['contractEndLocalDate'] as String,
                action: leaseActionText(context, 'edit'),
                buttonKey: ValueKey('lease-end-edit-$id'),
                onPressed: open && !locked
                    ? () => change(LeaseChange.endDate)
                    : null,
              ),
              // Today's rent, "Đổi", and planned / earlier changes.
              LeaseRentRows(
                key: ValueKey('lease-rent-$id-$_revision'),
                organizationId: widget.organizationId,
                buildingId: widget.buildingId,
                tenantId: id,
                currency: r['currency'] as String? ?? 'VND',
                monthlyRentMinor: r['monthlyRentMinor'],
                periodRentMinor: r['periodRentMinor'],
                periodRentOverride: r['periodRentOverride'] as Map?,
                periodMonths: (r['paymentPeriodMonths'] as int?) ?? 1,
                canPrice: r['canReadRentHistory'] == true,
                canEdit: r['canEditRent'] == true && !locked,
                service: widget.service,
              ),
              WsInfo(w('Payment', 'Thu tiền'), period),
              WsInfo(
                w('Deposit', 'Tiền cọc'),
                [
                  money(r['depositMinor'], r['currency']),
                  depositWay,
                ].where((v) => v.isNotEmpty).join(' · '),
              ),
              if (r['depositMinor'] is num && (r['depositMinor'] as num) > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: WsSpace.xs),
                  child: Text(
                    w(
                      'Not part of the total. Given back when the contract ends.',
                      'Không tính vào tổng tiền. Hoàn lại cho khách khi hết hợp đồng.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              WsInfo(
                w('Deposit note', 'Ghi chú cọc'),
                r['depositNote'] as String? ?? '',
              ),
              WsInfo(
                w('Staff in charge', 'Nhân viên phụ trách'),
                r['staffName'] as String? ?? '',
              ),
            ],
          ),
        // The people living with the main tenant; "Thêm" adds one (2026-10-04).
        if (hasLease)
          WsSection(
            key: ValueKey('lease-roommates-$id'),
            title: w('Living with them', 'Người ở cùng'),
            icon: Icons.people_alt_outlined,
            trailing: r['canAddRoommate'] == true
                ? TextButton(
                    key: ValueKey('add-roommate-$id'),
                    onPressed: locked ? null : addRoommate,
                    child: Text(w('Add', 'Thêm'), maxLines: 1),
                  )
                : null,
            children: [
              if (roommates.isEmpty)
                Text(
                  w('Nobody else.', 'Không có ai.'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              for (final m in roommates)
                ListTile(
                  key: ValueKey('lease-roommate-${m['id']}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${m['fullName']}'),
                  subtitle: '${m['moveInLocalDate'] ?? ''}'.isEmpty
                      ? null
                      : Text(
                          w(
                            'Moved in ${m['moveInLocalDate']}',
                            'Vào ở ${m['moveInLocalDate']}',
                          ),
                        ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: locked ? null : () => _read(m['id'] as String),
                ),
            ],
          ),
        // 2026-10-04: surcharges and electricity of the lease.
        if (hasLease)
          LeaseSurchargesSection(
            organizationId: widget.organizationId,
            buildingId: widget.buildingId,
            tenantId: id,
            currency: r['currency'] as String? ?? 'VND',
            surcharges: ((r['surcharges'] as List?) ?? const []).cast<Map>(),
            canEdit: r['stayStatus'] != 'checkedOut' && !locked,
            service: widget.service,
            onSaved: () => _refresh(id),
          ),
        if (hasLease &&
            r['stayStatus'] != 'checkedOut' &&
            r['roomId'] is String &&
            (r['roomId'] as String).isNotEmpty)
          LeaseElectricitySection(
            organizationId: widget.organizationId,
            buildingId: widget.buildingId,
            roomId: r['roomId'] as String,
            roomLabel: '${w('Room', 'Phòng')} $_room',
            service: widget.service,
          ),
        // Water per person per month (2026-10-04, Tom).
        if (hasLease)
          LeaseWaterSection(
            organizationId: widget.organizationId,
            buildingId: widget.buildingId,
            tenantId: id,
            currency: r['currency'] as String? ?? 'VND',
            surcharges: ((r['surcharges'] as List?) ?? const []).cast<Map>(),
            canEdit: r['stayStatus'] != 'checkedOut' && !locked,
            service: widget.service,
            onSaved: () => _refresh(id),
          ),
        // The room's technical problems (2026-10-04).
        if (hasLease &&
            r['roomId'] is String &&
            (r['roomId'] as String).isNotEmpty)
          RoomProblemsSection(
            organizationId: widget.organizationId,
            buildingId: widget.buildingId,
            roomId: r['roomId'] as String,
            roomLabel: '${w('Room', 'Phòng')} $_room',
            service: widget.service,
          ),
        WsSection(
          title: w('Contact', 'Liên hệ'),
          icon: Icons.contact_phone_outlined,
          children: [
            if (_revision != null || _message == 'tenant_contacts_conflict')
              Form(
                key: _form,
                child: WsFieldRow(
                  children: [
                    field(
                      'tenant-contact-name',
                      t['tenant_contacts_name'],
                      _name,
                      160,
                      required: true,
                    ),
                    field(
                      'tenant-contact-phone',
                      t['tenant_contacts_phone'],
                      _phone,
                      80,
                    ),
                  ],
                ),
              ),
            WsActions(
              children: [
                // Only after "changed by someone else" (2026-10-04, Tom).
                if (_revision == null)
                  TextButton(
                    onPressed: locked ? null : () => _read(_selected!),
                    child: Text(t['tenant_contacts_reload']),
                  ),
                if (_pending != null)
                  OutlinedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(t['tenant_contacts_retry']),
                  ),
                FilledButton(
                  onPressed: editable ? _save : null,
                  child: Text(t['tenant_contacts_save']),
                ),
              ],
            ),
          ],
        ),
        // Two steps only (2026-10-04, Tom): the period invoice and moving
        // out. Short changes live in their sections above.
        WsActions(
          children: [
            if (r['canBill'] == true && hasLease)
              FilledButton.icon(
                key: ValueKey('period-invoice-$id'),
                onPressed: locked
                    ? null
                    : () => setState(() => _periodTenant = id),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: Text(w('Period invoice', 'Lập hóa đơn kỳ')),
              ),
            if (r['canSettle'] == true)
              OutlinedButton(
                key: ValueKey('settle-$id'),
                onPressed: locked
                    ? null
                    : () => setState(() => _settleTenant = id),
                child: Text(
                  _status == 'moveOut'
                      ? w('Settle', 'Quyết toán')
                      : w('Move out', 'Trả phòng'),
                  maxLines: 1,
                ),
              ),
            // Someone living with a main tenant: move out or change room here.
            if (!hasLease && open) ...[
              OutlinedButton(
                key: ValueKey('roommate-move-$id'),
                onPressed: locked ? null : () => change(LeaseChange.move),
                child: Text(leaseActionText(context, 'moveRoom'), maxLines: 1),
              ),
              OutlinedButton(
                key: ValueKey('roommate-out-$id'),
                onPressed: locked ? null : () => change(LeaseChange.moveOut),
                child: Text(w('Move out', 'Trả phòng'), maxLines: 1),
              ),
            ],
          ],
        ),
      ];
    }

    return BackStep(
      enabled: _selected != null,
      onBack: () {
        if (!locked) _list();
      },
      child: WsPage(
        maxWidth: 760,
        children: [
          WsHeader(
            // Over the calendar the dialog's title bar names the tenant and
            // closes the page: no back link and no second title.
            back:
                !DialogPageScope.contains(context) &&
                    (_selected != null || widget.onBack != null)
                ? WsBack(
                    label:
                        t[_selected == null
                            ? 'workspace_title'
                            : 'tenant_contacts_title'],
                    onPressed: locked
                        ? null
                        : (_selected == null ? widget.onBack : () => _list()),
                  )
                : null,
            title: _selected == null
                ? t['tenant_contacts_title']
                : DialogPageScope.contains(context)
                ? ''
                : w('Tenant', 'Người thuê'),
            actions: [
              if (_selected == null)
                FilledButton.icon(
                  onPressed: locked
                      ? null
                      : () => setState(() => _creating = true),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: Text(w('Add tenant', 'Thêm người thuê')),
                ),
              if (_selected == null && !WorkspacePageScope.contains(context))
                TextButton(
                  onPressed: locked ? null : () => _list(),
                  child: Text(t['tenant_contacts_refresh']),
                ),
            ],
          ),
          if (_busy || _saving)
            const Padding(
              padding: EdgeInsets.only(bottom: WsSpace.sm),
              child: LinearProgressIndicator(),
            ),
          if (_showingSaved && _selected == null)
            WsNotice(
              w(
                'Showing saved data while refreshing.',
                'Đang hiển thị dữ liệu đã lưu trong khi cập nhật.',
              ),
              tone: WsTone.info,
            ),
          if (_message != null)
            Semantics(
              liveRegion: true,
              child: WsNotice(
                t[_message!],
                tone: _message == 'tenant_contacts_saved'
                    ? WsTone.good
                    : WsTone.warning,
              ),
            ),
          if (_selected == null) ...[
            if (!_busy && _message == null && _rows.isEmpty)
              WsEmpty(
                icon: Icons.people_outline,
                message: t['tenant_contacts_empty'],
              ),
            for (final row in _rows)
              WsRecord(
                tapKey: ValueKey('tenant-contact-${row['id']}'),
                onTap: locked ? null : () => _read(row['id'] as String),
                leading: WsBadge(text: teamRoomLabel(row)),
                title: row['fullName'] as String? ?? '',
                pill: statusPill(row),
                details: [
                  [
                    roomLine(row),
                    row['phoneNumber'] as String? ?? '',
                  ].where((v) => v.isNotEmpty).join(' · '),
                  if ((row['mainTenantName'] as String? ?? '').isNotEmpty)
                    w(
                      'Lives with ${row['mainTenantName']}',
                      'Ở cùng ${row['mainTenantName']}',
                    ),
                ],
              ),
            if (_cursor != null)
              Center(
                child: TextButton(
                  onPressed: locked ? null : () => _list(more: true),
                  child: Text(t['tenant_contacts_more']),
                ),
              ),
          ] else if (d != null)
            ...detail(d),
        ],
      ),
    );
  }
}
