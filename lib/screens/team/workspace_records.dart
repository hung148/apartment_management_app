import 'package:flutter/material.dart';
import '../../services/payment_command_service.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'back_steps.dart';
import 'operational_widgets.dart';
import 'payment_action_form.dart';
import 'team_display.dart';
import 'ws_ui.dart';

/// Read-only lists from `readWorkspace` (payments to collect/refund, financial
/// data, bookings) for one property. Moved out of the old workspace (U1).
class WorkspaceRecords extends StatefulWidget {
  final String organizationId;
  final String buildingId;
  final String accountId;

  /// 'paymentActions', 'financial' or 'bookings'.
  final String view;
  final TeamService service;

  /// Called when the server says this person may no longer see the list.
  final VoidCallback? onDenied;
  const WorkspaceRecords({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.accountId,
    required this.view,
    required this.service,
    this.onDenied,
  });
  @override
  State<WorkspaceRecords> createState() => _WorkspaceRecordsState();
}

class _WorkspaceRecordsState extends State<WorkspaceRecords> {
  List<Map<String, dynamic>> _records = [];
  String? _cursor;
  Map<String, dynamic>? _payment;
  bool _busy = true, _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(covariant WorkspaceRecords old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.view != widget.view ||
        old.service != widget.service) {
      _payment = null;
      _read();
    }
  }

  Future<void> _read({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      if (!more) {
        _records = [];
        _cursor = null;
      }
    });
    try {
      final page = await widget.service.workspace(
        widget.organizationId,
        widget.view,
        buildingId: widget.buildingId,
        cursor: more ? _cursor : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _records = [if (more) ..._records, ...page.records];
        _cursor = page.nextCursor;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _failed = true;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final payment = _payment;
    if (payment != null) {
      void back() {
        setState(() => _payment = null);
        _read();
      }

      return BackStep(
        onBack: back,
        child: PaymentActionForm(
          key: ValueKey('${widget.organizationId}-${payment['id']}'),
          organizationId: widget.organizationId,
          accountId: widget.accountId,
          invoice: payment,
          service: PaymentCommandService(
            transport: (_, data) => widget.service.mutatePayment(data),
          ),
          onBack: back,
          onDenied: () {
            setState(() => _payment = null);
            widget.onDenied?.call();
          },
        ),
      );
    }
    String statusLabel(Object? value) {
      final status = switch (value) {
        'checkedIn' => 'checked_in',
        'checkedOut' => 'checked_out',
        'noShow' => 'no_show',
        _ => value?.toString() ?? '',
      };
      final key =
          '${widget.view == 'bookings' ? 'booking' : 'payment'}_status_$status';
      return t.translationKeys.contains(key) ? t[key] : t['workspace_unknown'];
    }

    WsTone tone(Object? status) => switch (status) {
      'paid' || 'checkedIn' => WsTone.good,
      'pending' || 'partial' => WsTone.warning,
      'overdue' || 'cancelled' || 'noShow' => WsTone.bad,
      'confirmed' => WsTone.info,
      _ => WsTone.neutral,
    };
    return WsPage(
      children: [
        WsHeader(title: t['workspace_${widget.view}']),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(),
          ),
        if (_failed)
          WsNotice(
            t['workspace_denied'],
            action: TextButton(
              onPressed: _busy ? null : _read,
              child: Text(t['team_refresh']),
            ),
          ),
        if (!_busy && !_failed && _records.isEmpty)
          WsEmpty(icon: Icons.inbox_outlined, message: t['workspace_empty']),
        for (final r in _records)
          WsRecord(
            tone: tone(r['status']),
            leading: WsBadge(text: teamRoomLabel(r)),
            title: widget.view == 'bookings'
                ? (r['guestName'] as String? ?? '')
                : appMoney(
                    r['amount'] is num ? r['amount'] : 0,
                    '${r['currency'] ?? 'VND'}',
                  ),
            pill: WsPill(statusLabel(r['status']), tone: tone(r['status'])),
            details: [
              '${t['workspace_room']}: ${teamRoomLabel(r)}',
              if (widget.view == 'bookings')
                // Property time when the server sends it; device time for older servers.
                r['startLocal'] is String &&
                        (r['startLocal'] as String).isNotEmpty
                    ? '${r['startLocal']} – ${r['endLocal']} (${r['timeZone'] ?? ''})'
                    : '${teamDate(r['startTime'], t)} – ${teamDate(r['endTime'], t)}'
              else ...[
                if (r['direction'] != null)
                  opsText(context, r['direction'] as String),
                '${t['workspace_paid']}: ${appMoney(r['paidAmount'] is num ? r['paidAmount'] : 0, '${r['currency'] ?? 'VND'}')}',
              ],
              '${t['workspace_status']}: ${statusLabel(r['status'])}',
            ],
            actions: [
              if (widget.view == 'paymentActions' &&
                  (r['canCollect'] == true || r['canRefund'] == true))
                OutlinedButton(
                  onPressed: _busy ? null : () => setState(() => _payment = r),
                  child: Text(t['payment_action_title']),
                ),
            ],
          ),
        if (_cursor != null)
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => _read(more: true),
              child: Text(t['workspace_more']),
            ),
          ),
      ],
    );
  }
}
