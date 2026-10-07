import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';

class TenantRentHistory extends StatefulWidget {
  final String organizationId, buildingId, tenantId;
  final String backLabelKey;
  final TeamService service;
  final VoidCallback onBack;
  const TenantRentHistory({
    super.key,
    this.backLabelKey = 'rent_history_back',
    required this.organizationId,
    required this.buildingId,
    required this.tenantId,
    required this.service,
    required this.onBack,
  });
  @override
  State<TenantRentHistory> createState() => _TenantRentHistoryState();
}

class _TenantRentHistoryState extends State<TenantRentHistory> {
  List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  bool _busy = true, _failed = false, _denied = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TenantRentHistory old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.tenantId != widget.tenantId ||
        old.service != widget.service) {
      _load();
    }
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      _denied = false;
      if (!more) {
        _rows = [];
        _cursor = null;
      }
    });
    try {
      final r = await widget.service.tenantRent({
        'action': 'history',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'tenantId': widget.tenantId,
        if (more) 'cursor': _cursor,
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        final seen = _rows.map((v) => v['id']).toSet();
        _rows.addAll(
          (r['records'] as List)
              .map((v) => Map<String, dynamic>.from(v as Map))
              .where((v) => seen.add(v['id'])),
        );
        _cursor = r['nextCursor'] as String?;
        _busy = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _failed = true;
        if (e is FirebaseFunctionsException &&
            [
              'permission-denied',
              'unauthenticated',
              'not-found',
            ].contains(e.code)) {
          _rows = [];
          _cursor = null;
          _denied = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    String money(Map? value, String currency) {
      if (value == null) return t['rent_history_none'];
      return appMoneyMinor(value['amountMinor'] as int, currency);
    }

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: WorkspacePageScope.constraints(context, 720),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextButton(
                  onPressed: widget.onBack,
                  child: Text(t[widget.backLabelKey]),
                ),
                Text(
                  t['rent_history_title'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(t['rent_history_help']),
                const SizedBox(height: 12),
                WsActions(
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => _load(),
                      child: Text(t['contract_history_refresh']),
                    ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_failed)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      t[_denied
                          ? 'rent_plan_unavailable'
                          : 'contract_history_error'],
                    ),
                  ),
                if (!_busy && !_failed && _rows.isEmpty)
                  Text(t['rent_history_empty']),
                for (final row in _rows)
                  Card(
                    key: ValueKey('rent-history-${row['id']}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            t[row['after'] == null
                                ? 'rent_history_cancelled'
                                : row['before'] == null
                                ? 'rent_history_added'
                                : 'rent_history_replaced'],
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${t['contract_history_saved']}: ${row['createdAt']}',
                          ),
                          Text(
                            '${t['contract_history_actor']}: ${row['actorId']}',
                          ),
                          Text(
                            '${t['rent_plan_date']}: ${row['effectiveDate']}',
                          ),
                          Text(
                            '${t['lease_form_timezone']}: ${row['timeZone']}',
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${t['rent_history_before']}: ${money(row['before'] as Map?, row['currency'] as String)}',
                          ),
                          Text(
                            '${t['rent_history_after']}: ${money(row['after'] as Map?, row['currency'] as String)}',
                          ),
                          const SizedBox(height: 8),
                          Text('${t['rent_plan_reason']}: ${row['reason']}'),
                        ],
                      ),
                    ),
                  ),
                if (_cursor != null)
                  WsActions(
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : () => _load(more: true),
                        child: Text(
                          t[_failed
                              ? 'contract_history_retry'
                              : 'contract_history_more'],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
