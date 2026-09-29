import 'package:flutter/material.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'team_display.dart';

class ActivityHistory extends StatefulWidget {
  final String organizationId;
  final TeamService service;
  final VoidCallback onBack;
  const ActivityHistory({
    super.key,
    required this.organizationId,
    required this.service,
    required this.onBack,
  });
  @override
  State<ActivityHistory> createState() => _ActivityHistoryState();
}

class _ActivityHistoryState extends State<ActivityHistory> {
  final _actor = TextEditingController();
  List<Map<String, dynamic>> _records = [];
  String? _cursor, _filter;
  bool _busy = true, _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _actor.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ActivityHistory old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.service != widget.service) {
      _actor.clear();
      _filter = null;
      _load();
    }
  }

  Future<void> _load({bool more = false}) async {
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
      final page = await widget.service.page(
        widget.organizationId,
        TeamView.activity,
        cursor: more ? _cursor : null,
        actorId: _filter,
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
          _records = [];
          _cursor = null;
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  String _details(Object? value, AppTranslations t) {
    if (value is! Map || value.isEmpty) return t['activity_not_recorded'];
    return value.entries
        .map((e) {
          final key = 'activity_field_${e.key}';
          final label = t.translationKeys.contains(key)
              ? t[key]
              : e.key.toString();
          var v = e.value;
          if ([
                'startTime',
                'endTime',
                'moveInDate',
                'moveOutDate',
              ].contains(e.key) &&
              v != null) {
            v = teamDate(v, t);
          }
          if (e.key == 'changedFields' && v is List) {
            v = v
                .map(
                  (f) => t.translationKeys.contains('activity_field_$f')
                      ? t['activity_field_$f']
                      : f,
                )
                .toList();
          }
          if (e.key == 'role' && t.translationKeys.contains('team_role_$v')) {
            v = t['team_role_$v'];
          }
          if ((e.key == 'status' || e.key == 'requestStatus') &&
              t.translationKeys.contains('team_status_$v')) {
            v = t['team_status_$v'];
          }
          if (e.key == 'buildingScope') {
            v = t[v == 'all' ? 'activity_all' : 'activity_selected'];
          }
          return '$label: ${v is Map
              ? v.entries.map((e) => '${e.key}: ${e.value}').join(', ')
              : v is List
              ? v.join(', ')
              : v ?? t['activity_not_recorded']}';
        })
        .join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextButton(onPressed: widget.onBack, child: Text(t['team_back'])),
              Text(
                t['activity_title'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(t['activity_help']),
              const SizedBox(height: 16),
              TextField(
                controller: _actor,
                readOnly: _busy,
                decoration: InputDecoration(
                  labelText: t['activity_actor_filter'],
                ),
                onChanged: (_) => setState(() {
                  _records = [];
                  _cursor = null;
                }),
              ),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () {
                        _filter = _actor.text.trim().isEmpty
                            ? null
                            : _actor.text.trim();
                        _load();
                      },
                child: Text(t['team_refresh']),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_failed) Text(t['activity_failed']),
              if (!_busy && !_failed && _records.isEmpty)
                Text(t['activity_empty']),
              for (final record in _records)
                Card(
                  key: ValueKey('activity-${record['id']}'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.translationKeys.contains(
                                'activity_action_${record['action']}',
                              )
                              ? t['activity_action_${record['action']}']
                              : t['activity_unknown'],
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(teamDate(record['createdAt'], t)),
                        SelectableText(
                          '${t['activity_actor']}: ${record['actorId'] ?? ''}',
                        ),
                        SelectableText(
                          '${t['activity_target']}: ${record['targetId'] ?? ''}',
                        ),
                        if (record['reason'] is String &&
                            (record['reason'] as String).isNotEmpty)
                          Text('${t['activity_reason']}: ${record['reason']}'),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text(t['activity_changes']),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '${t['activity_before']}\n${_details(record['before'], t)}\n\n${t['activity_after']}\n${_details(record['after'], t)}',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (_cursor != null)
                OutlinedButton(
                  onPressed: _busy ? null : () => _load(more: true),
                  child: Text(t['workspace_more']),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
