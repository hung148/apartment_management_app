import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/team_access.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'team_display.dart';
import 'ws_ui.dart';

typedef HousekeepingFirstPage = ({
  List<Map<String, dynamic>> tasks,
  String? cursor,
  List<Map<String, dynamic>> rooms,
  List<Map<String, dynamic>> people,
  bool manager,
});

/// The cleaning list's first page with the rooms and people a manager assigns
/// to, kept on this device for the next open. The calendar also calls this to
/// load it ahead (2026-10-11, Tom: forms ready before they are tapped).
Future<HousekeepingFirstPage> loadHousekeeping(
  TeamService service,
  String organizationId,
  String buildingId,
  TeamAccess access,
) async {
  final manager = access.allows(
    TeamPermission.manageProperty,
    buildingId: buildingId,
  );
  // 100 a page (the most the server gives): 100 staff is one or two reads.
  Future<List<Map<String, dynamic>>> all(String view) async {
    final rows = <Map<String, dynamic>>[];
    String? cursor;
    final seen = <String>{};
    do {
      final page = await service.workspace(
        organizationId,
        view,
        buildingId: buildingId,
        cursor: cursor,
        limit: 100,
      );
      rows.addAll(page.records);
      cursor = page.nextCursor;
      if (cursor != null && !seen.add(cursor)) {
        throw StateError('Repeated cursor');
      }
    } while (cursor != null);
    return rows;
  }

  // The tasks, rooms and people are read at the same time (2026-10-11).
  final none = Future.value(<Map<String, dynamic>>[]);
  final pageRead = service.workspace(
    organizationId,
    'tasks',
    buildingId: buildingId,
  );
  final roomsRead = manager ? all('taskRooms') : none;
  final peopleRead = manager ? all('taskAssignees') : none;
  // One failure is reported once; the others are not left unhandled.
  roomsRead.ignore();
  peopleRead.ignore();
  final page = await pageRead;
  final rooms = await roomsRead, people = await peopleRead;
  service.save('housekeeping:$buildingId', organizationId, {
    'tasks': page.records,
    'rooms': rooms,
    'people': people,
    'manager': manager,
  });
  return (
    tasks: page.records,
    cursor: page.nextCursor,
    rooms: rooms,
    people: people,
    manager: manager,
  );
}

class HousekeepingScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;

  /// Null inside the organization workspace sections (U1): no Back button.
  final VoidCallback? onBack;

  /// From a day on the calendar (2026-10-05): open the assign form for this
  /// room with this planned window ("YYYY-MM-DD HH:mm").
  final String? initialRoomId, initialStart, initialEnd;

  /// What this person may do, when the opener already knows it (the
  /// calendar): no extra "my access" read before the list (2026-10-11, Tom).
  /// The server still checks every read and change.
  final TeamAccess? access;
  const HousekeepingScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    this.onBack,
    this.initialRoomId,
    this.initialStart,
    this.initialEnd,
    this.access,
  });
  @override
  State<HousekeepingScreen> createState() => _HousekeepingScreenState();
}

class _HousekeepingScreenState extends State<HousekeepingScreen> {
  final _title = TextEditingController();

  /// The planned window shown on the calendar (optional, both or neither).
  final _start = TextEditingController(), _end = TextEditingController();
  bool _prefilled = false;
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
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  static final _stamp = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$');

  /// The planned window to send, null when left empty, or 'bad'.
  Object? _plan() {
    final a = _start.text.trim(), b = _end.text.trim();
    if (a.isEmpty && b.isEmpty) return null;
    if (!_stamp.hasMatch(a) ||
        !_stamp.hasMatch(b) ||
        b.compareTo(a) <= 0 ||
        DateTime.tryParse(a.replaceFirst(' ', 'T')) == null ||
        DateTime.tryParse(b.replaceFirst(' ', 'T')) == null) {
      return 'bad';
    }
    return {'plannedStart': a, 'plannedEnd': b};
  }

  /// Name of the person a task is for; the account ID only if no name is known.
  /// "… – HH:mm" for the same day, the full stamp for another day, "…" while
  /// the work is still going.
  String _endPart(String start, Object? end) {
    if (end is! String || end.isEmpty) return '…';
    return end.length >= 16 &&
            start.length >= 10 &&
            end.substring(0, 10) == start.substring(0, 10)
        ? end.substring(11)
        : end;
  }

  String _personLabel(Map<String, dynamic> task) {
    final name = task['assigneeName'];
    if (name is String && name.isNotEmpty) return name;
    for (final p in _people) {
      final n = p['displayName'];
      if (p['ownerId'] == task['assigneeId'] &&
          n is String &&
          n.trim().isNotEmpty)
        return n.trim();
    }
    return '${task['assigneeId'] ?? ''}';
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
    // 2026-10-11 (Tom: open at once): the list as it was last time, from this
    // device, while the server is asked (still locked until it answers).
    final savedKey = 'housekeeping:${widget.buildingId}';
    if (!more) {
      widget.service.saved(savedKey, widget.organizationId).then((saved) {
        if (saved == null ||
            !mounted ||
            generation != _generation ||
            !_busy ||
            _tasks.isNotEmpty) {
          return;
        }
        List<Map<String, dynamic>> rows(String k) => [
          for (final v in (saved[k] as List? ?? const []))
            Map<String, dynamic>.from(v as Map),
        ];
        setState(() {
          _tasks = rows('tasks');
          _rooms = rows('rooms');
          _people = rows('people');
          _manager = saved['manager'] == true;
        });
      }, onError: (Object _) {});
    }
    try {
      final access =
          widget.access ??
          TeamAccess.fromMap(
            await widget.service.myAccess(widget.organizationId) ?? {},
          );
      final manager = access.allows(
        TeamPermission.manageProperty,
        buildingId: widget.buildingId,
      );
      final HousekeepingFirstPage first;
      if (more) {
        final page = await widget.service.workspace(
          widget.organizationId,
          'tasks',
          buildingId: widget.buildingId,
          cursor: _cursor,
        );
        first = (
          tasks: [..._tasks, ...page.records],
          cursor: page.nextCursor,
          rooms: _rooms,
          people: _people,
          manager: manager,
        );
      } else {
        first = await loadHousekeeping(
          widget.service,
          widget.organizationId,
          widget.buildingId,
          access,
        );
      }
      final rooms = first.rooms, people = first.people;
      if (!mounted || generation != _generation) return;
      setState(() {
        _manager = manager;
        _tasks = first.tasks;
        _cursor = first.cursor;
        _rooms = rooms;
        _people = people;
        _busy = false;
        // Opened from a day on the calendar: the form, already filled in.
        if (!_prefilled && manager && widget.initialRoomId != null) {
          _prefilled = true;
          _creating = true;
          if (rooms.any((r) => r['id'] == widget.initialRoomId)) {
            _room = widget.initialRoomId;
          }
          _start.text = widget.initialStart ?? '';
          _end.text = widget.initialEnd ?? '';
        }
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
        _start.clear();
        _end.clear();
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
          constraints: WorkspacePageScope.constraints(context, 960),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              WsHeader(
                back: widget.onBack == null
                    ? null
                    : WsBack(
                        label: t['workspace_title'],
                        onPressed: _saving ? null : widget.onBack,
                      ),
                title: t['tasks_title'],
                actions: [
                  if (_manager)
                    FilledButton.icon(
                      onPressed: locked
                          ? null
                          : () => setState(() => _creating = !_creating),
                      icon: Icon(_creating ? Icons.close : Icons.add, size: 18),
                      label: Text(t['tasks_assign']),
                    ),
                  if (!WorkspacePageScope.contains(context))
                    OutlinedButton(
                      onPressed: locked ? null : () => _load(),
                      child: Text(t['team_refresh']),
                    ),
                ],
              ),
              if (_busy || _saving)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null) WsNotice(t[_error!]),
              if (_pending != null && !_saving)
                WsActions(
                  children: [
                    FilledButton(
                      onPressed: () => _send({}),
                      child: Text(t['tasks_retry']),
                    ),
                  ],
                ),
              if (_manager) ...[
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
                  // Space between fields (2026-10-05, Tom: they touched).
                  const SizedBox(height: WsSpace.md),
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
                            (p['displayName'] as String?)?.trim().isNotEmpty ==
                                    true
                                ? (p['displayName'] as String).trim()
                                : '${p['ownerId']}',
                          ),
                        ),
                    ],
                    onChanged: locked
                        ? null
                        : (v) => setState(() => _person = v),
                  ),
                  const SizedBox(height: WsSpace.md),
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
                  const SizedBox(height: WsSpace.sm),
                  // When to clean (optional): shown as a bar on the calendar.
                  WsFieldRow(
                    children: [
                      TextField(
                        key: const ValueKey('task-start'),
                        controller: _start,
                        readOnly: locked,
                        decoration: InputDecoration(
                          labelText: t['tasks_planned_start'],
                          hintText: 'YYYY-MM-DD HH:mm',
                        ),
                      ),
                      TextField(
                        key: const ValueKey('task-end'),
                        controller: _end,
                        readOnly: locked,
                        decoration: InputDecoration(
                          labelText: t['tasks_planned_end'],
                          hintText: 'YYYY-MM-DD HH:mm',
                        ),
                      ),
                    ],
                  ),
                  WsActions(
                    children: [
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
                                final plan = _plan();
                                if (plan == 'bad') {
                                  setState(() => _error = 'tasks_time_invalid');
                                  return;
                                }
                                _send({
                                  'action': 'assign',
                                  'taskId': const Uuid().v4(),
                                  'buildingId': widget.buildingId,
                                  'roomId': _room,
                                  'assigneeId': _person,
                                  'title': _title.text.trim(),
                                  if (plan is Map) ...plan,
                                });
                              },
                        child: Text(t['tasks_save']),
                      ),
                    ],
                  ),
                ],
              ],
              if (!_busy && _error == null && _tasks.isEmpty)
                WsEmpty(
                  icon: Icons.cleaning_services_outlined,
                  message: t['tasks_empty'],
                ),
              for (final task in _tasks)
                WsRecord(
                  leading: WsBadge(text: teamRoomLabel(task)),
                  title: task['title'] as String? ?? '',
                  pill: WsPill(
                    t['tasks_status_${task['status']}'],
                    tone: task['status'] == 'completed'
                        ? WsTone.good
                        : task['status'] == 'inProgress'
                        ? WsTone.info
                        : WsTone.warning,
                  ),
                  details: [
                    '${t['workspace_room']}: ${teamRoomLabel(task)}   ${t['tasks_assignee']}: ${_personLabel(task)}',
                    if (task['plannedStart'] is String &&
                        task['plannedEnd'] is String)
                      '${t['tasks_planned']}: ${task['plannedStart']} – ${(task['plannedEnd'] as String).length >= 16 ? (task['plannedEnd'] as String).substring(11) : task['plannedEnd']}',
                    if (task['startedLocal'] is String &&
                        (task['startedLocal'] as String).isNotEmpty)
                      '${t['tasks_actual']}: ${task['startedLocal']} – ${_endPart(task['startedLocal'] as String, task['completedLocal'])}',
                  ],
                  actions: [
                    if (task['status'] != 'completed') ...[
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
                  ],
                ),
              if (_cursor != null)
                Center(
                  child: TextButton(
                    onPressed: locked ? null : () => _load(more: true),
                    child: Text(t['team_more']),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
