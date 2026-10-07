import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';

class PropertyContractHistory extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;
  final VoidCallback onBack;
  const PropertyContractHistory({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.onBack,
  });
  @override
  State<PropertyContractHistory> createState() =>
      _PropertyContractHistoryState();
}

class _PropertyContractHistoryState extends State<PropertyContractHistory> {
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
  void didUpdateWidget(covariant PropertyContractHistory old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
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
      final result = await widget.service.propertyContract({
        'action': 'history',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        if (more) 'cursor': _cursor,
      });
      if (!mounted || generation != _generation) return;
      final rows = (result['records'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();
      setState(() {
        final seen = _rows.map((r) => r['id']).toSet();
        _rows.addAll(rows.where((r) => seen.add(r['id'])));
        _cursor = result['nextCursor'] as String?;
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
    Widget snapshot(Map? value, String currency) {
      if (value == null) return Text(t['contract_history_no_previous']);
      String text(String key) =>
          value[key]?.toString() ?? t['team_unspecified'];
      final amount = value['amountMinor'];
      final money = amount is int
          ? (currency == 'USD'
                ? '${amount ~/ 100}.${(amount % 100).toString().padLeft(2, '0')}'
                : '$amount')
          : t['team_unspecified'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${t['contract_direction']}: ${t['contract_${value['direction']}']}',
          ),
          Text('${t['contract_status']}: ${t['contract_${value['status']}']}'),
          Text('${t['contract_party']}: ${text('partyName')}'),
          Text('${t['contract_phone']}: ${text('partyPhone')}'),
          Text('${t['contract_amount']}: $money $currency'),
          Text('${t['contract_due']}: ${text('dueDay')}'),
          Text('${t['contract_start']}: ${text('startDate')}'),
          Text('${t['contract_end']}: ${text('endDate')}'),
          Text('${t['contract_notes']}: ${text('notes')}'),
        ],
      );
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
                  child: Text(t['contract_history_back']),
                ),
                Text(
                  t['contract_history'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(t['contract_history_help']),
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
                          ? 'contract_unavailable'
                          : 'contract_history_error'],
                    ),
                  ),
                if (!_busy && !_failed && _rows.isEmpty)
                  Text(t['contract_history_empty']),
                for (final row in _rows)
                  Card(
                    key: ValueKey('contract-history-${row['id']}'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${t['contract_history_saved']}: ${row['createdAt']}',
                          ),
                          Text(
                            '${t['contract_history_actor']}: ${row['actorId']}',
                          ),
                          const SizedBox(height: 12),
                          Text(
                            t['contract_history_after'],
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          snapshot(
                            row['after'] as Map?,
                            row['currency'] as String,
                          ),
                          const SizedBox(height: 8),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(t['contract_history_before']),
                            children: [
                              snapshot(
                                row['before'] as Map?,
                                row['currency'] as String,
                              ),
                            ],
                          ),
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
