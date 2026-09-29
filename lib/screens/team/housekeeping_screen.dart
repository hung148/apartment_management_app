import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';

class HousekeepingScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;
  final VoidCallback onBack;
  const HousekeepingScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.onBack,
  });
  @override
  State<HousekeepingScreen> createState() => _HousekeepingScreenState();
}

class _HousekeepingScreenState extends State<HousekeepingScreen> {
  final _title = TextEditingController();
  List<Map<String, dynamic>> _tasks = [], _rooms = [], _people = [];
  String? _room, _person, _cursor, _error;
  bool _busy = true, _saving = false, _manager = false, _creating = false;
  int _generation = 0;
  Map<String, dynamic>? _pending;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HousekeepingScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _pending = null;
      _saving = false;
      _title.clear();
      _creating = false;
      _load();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _all(String view) async {
    final rows = <Map<String, dynamic>>[];
    String? cursor;
    final seen = <String>{};
    do {
      final page = await widget.service.workspace(
        widget.organizationId,
        view,
        buildingId: widget.buildingId,
        cursor: cursor,
      );
      rows.addAll(page.records);
      cursor = page.nextCursor;
      if (cursor != null && !seen.add(cursor)) {
        throw StateError('Repeated cursor');
      }
    } while (cursor != null);
    return rows;
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
      if (!more) {
        _tasks = [];
        _rooms = [];
        _people = [];
        _room = null;
        _person = null;
        _cursor = null;
        _manager = false;
      }
    });
    try {
      final access = TeamAccess.fromMap(
        await widget.service.myAccess(widget.organizationId) ?? {},
      );
      final manager = access.allows(
        TeamPermission.manageProperty,
        buildingId: widget.buildingId,
      );
      final page = await widget.service.workspace(
        widget.organizationId,
        'tasks',
        buildingId: widget.buildingId,
        cursor: more ? _cursor : null,
      );
      final rooms = manager
          ? await _all('taskRooms')
          : <Map<String, dynamic>>[];
      final people = manager
          ? await _all('taskAssignees')
          : <Map<String, dynamic>>[];
      if (!mounted || generation != _generation) return;
      setState(() {
        _manager = manager;
        _tasks = [if (more) ..._tasks, ...page.records];
        _cursor = page.nextCursor;
        _rooms = rooms;
        _people = people;
        _busy = false;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _tasks = [];
          _rooms = [];
          _people = [];
          _manager = false;
          _creating = false;
          _title.clear();
          _busy = false;
          _error = 'tasks_unavailable';
        });
      }
    }
  }

  Future<void> _send(Map<String, dynamic> fields) async {
    if (_saving || _busy) return;
    _pending ??= Map.unmodifiable({
      'organizationId': widget.organizationId,
      'operationId': const Uuid().v4(),
      ...fields,
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.mutateTask(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      setState(() {
        _pending = null;
        _saving = false;
        _creating = false;
        _title.clear();
      });
      await _load();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      if (error is FirebaseFunctionsException &&
          ['unauthenticated', 'permission-denied'].contains(error.code)) {
        setState(() {
          _saving = false;
          _pending = null;
          _creating = false;
          _title.clear();
          _tasks = [];
          _rooms = [];
          _people = [];
          _manager = false;
          _error = 'tasks_unavailable';
        });
        return;
      }
      setState(() {
        _saving = false;
        _error = 'tasks_uncertain';
        if (error is FirebaseFunctionsException &&
            [
              'invalid-argument',
              'failed-precondition',
              'not-found',
              'already-exists',
            ].contains(error.code)) {
          _pending = null;
          _error = 'tasks_rejected';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context),
        locked = _busy || _saving || _pending != null;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextButton(
                onPressed: _saving ? null : widget.onBack,
                child: Text(t['workspace_title']),
              ),
              Text(
                t['tasks_title'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (_busy || _saving) const LinearProgressIndicator(),
              if (_error != null) Text(t[_error!]),
              if (_pending != null && !_saving)
                FilledButton(
                  onPressed: () => _send({}),
                  child: Text(t['tasks_retry']),
                ),
              OutlinedButton(
                onPressed: locked ? null : () => _load(),
                child: Text(t['team_refresh']),
              ),
              if (_manager) ...[
                OutlinedButton(
                  onPressed: locked
                      ? null
                      : () => setState(() => _creating = !_creating),
                  child: Text(t['tasks_assign']),
                ),
                if (_creating) ...[
                  if (_rooms.isEmpty || _people.isEmpty)
                    Text(t['tasks_no_choices']),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('task-room'),
                    initialValue: _room,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: InputDecoration(labelText: t['workspace_room']),
                    items: [
                      for (final r in _rooms)
                        DropdownMenuItem(
                          value: r['id'] as String,
                          child: Text('${r['roomNumber'] ?? r['id']}'),
                        ),
                    ],
                    onChanged: locked ? null : (v) => setState(() => _room = v),
                  ),
                  DropdownButtonFormField<String>(
                    key: const ValueKey('task-person'),
                    initialValue: _person,
                    isExpanded: true,
                    itemHeight: null,
                    decoration: InputDecoration(labelText: t['tasks_assignee']),
                    items: [
                      for (final p in _people)
                        DropdownMenuItem(
                          value: p['ownerId'] as String,
                          child: Text(
                            '${p['displayName'] ?? p['ownerId']} (${p['ownerId']})',
                          ),
                        ),
                    ],
                    onChanged: locked
                        ? null
                        : (v) => setState(() => _person = v),
                  ),
                  TextField(
                    key: const ValueKey('task-title'),
                    controller: _title,
                    readOnly: locked,
                    maxLength: 200,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: t['tasks_description'],
                    ),
                  ),
                  FilledButton(
                    onPressed: locked
                        ? null
                        : () {
                            if (_room == null ||
                                _person == null ||
                                _title.text.trim().isEmpty) {
                              setState(() => _error = 'tasks_required');
                              return;
                            }
                            _send({
                              'action': 'assign',
                              'taskId': const Uuid().v4(),
                              'buildingId': widget.buildingId,
                              'roomId': _room,
                              'assigneeId': _person,
                              'title': _title.text.trim(),
                            });
                          },
                    child: Text(t['tasks_save']),
                  ),
                ],
              ],
              if (!_busy && _error == null && _tasks.isEmpty)
                Text(t['tasks_empty']),
              for (final task in _tasks)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task['title'] as String? ?? ''),
                        Text('${t['workspace_room']}: ${task['roomId']}'),
                        Text('${t['tasks_assignee']}: ${task['assigneeId']}'),
                        Text(t['tasks_status_${task['status']}']),
                        if (task['status'] != 'completed')
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (task['status'] == 'assigned')
                                OutlinedButton(
                                  onPressed: locked
                                      ? null
                                      : () => _send({
                                          'action': 'status',
                                          'taskId': task['id'],
                                          'status': 'inProgress',
                                        }),
                                  child: Text(t['tasks_start']),
                                ),
                              FilledButton(
                                onPressed: locked
                                    ? null
                                    : () => _send({
                                        'action': 'status',
                                        'taskId': task['id'],
                                        'status': 'completed',
                                      }),
                                child: Text(t['tasks_complete']),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              if (_cursor != null)
                OutlinedButton(
                  onPressed: locked ? null : () => _load(more: true),
                  child: Text(t['team_more']),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
