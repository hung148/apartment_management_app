import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import 'bulk_rooms_screen.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';

class RoomDetailsScreen extends StatefulWidget {
  final String organizationId, buildingId, roomId;
  final TeamService service;
  final VoidCallback onBack;
  final bool create, canDelete;

  /// Called once a new room is created (the calendar closes its dialog).
  final VoidCallback? onCreated;

  /// Called once the room is deleted (the room dialog then says so).
  final VoidCallback? onDeleted;
  const RoomDetailsScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.service,
    required this.onBack,
    this.create = false,
    this.canDelete = false,
    this.onCreated,
    this.onDeleted,
  });
  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  final _number = TextEditingController(), _type = TextEditingController();
  final _area = TextEditingController();
  // Dot for decimals, comma only as thousands (2026-10-05).
  double? _parseArea(String value) => appParseQuantity(value, decimals: 2);
  final _form = GlobalKey<FormState>();
  String? _revision, _message;
  bool _loading = true, _saving = false;
  int _generation = 0;
  Map<String, dynamic>? _pending;
  bool _bulk = false;
  bool _created = false, _confirmDelete = false, _deleted = false;
  String _savedNumber = '';
  bool get _deleting => _pending?['action'] == 'delete';
  String? _currency;
  bool get _creating => widget.create && !_created;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RoomDetailsScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.roomId != widget.roomId ||
        old.create != widget.create ||
        old.canDelete != widget.canDelete ||
        old.service != widget.service) {
      _saving = false;
      _pending = null;
      _bulk = false;
      _created = false;
      _confirmDelete = false;
      _deleted = false;
      _load();
    }
  }

  @override
  void dispose() {
    _number.dispose();
    _type.dispose();
    _area.dispose();
    super.dispose();
  }

  Future<void> _load({bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _revision = null;
      _message = null;
      _confirmDelete = false;
      _number.clear();
      _type.clear();
      _area.clear();
      _currency = null;
    });
    try {
      final result = await widget.service.roomDetails({
        'action': _creating ? 'prepareCreate' : 'read',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'roomId': widget.roomId,
      });
      if (!mounted || generation != _generation) return;
      final row = Map<String, dynamic>.from(result['record'] as Map);
      setState(() {
        _revision = row['revision'] as String;
        _number.text = row['roomNumber'] as String;
        _savedNumber = _number.text;
        _type.text = row['roomType'] as String;
        _area.text = _creating ? '' : appQuantity(row['area'] as num);
        _currency = row['currency'] as String?;
        _loading = false;
        _message = saved ? 'room_edit_saved' : null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _message = 'room_edit_unavailable';
      });
    }
  }

  Future<void> _delete() async {
    if (!widget.canDelete ||
        _saving ||
        _loading ||
        _revision == null ||
        _deleted) {
      return;
    }
    _pending ??= Map.unmodifiable({
      'action': 'delete',
      'organizationId': widget.organizationId,
      'buildingId': widget.buildingId,
      'roomId': widget.roomId,
      'operationId': const Uuid().v4(),
      'revision': _revision,
    });
    await _save();
  }

  Future<void> _save() async {
    if (_saving || _loading || _revision == null) return;
    if (_pending == null && !(_form.currentState?.validate() ?? false)) return;
    _pending ??= Map.unmodifiable({
      'action': _creating ? 'create' : 'update',
      'organizationId': widget.organizationId,
      'buildingId': widget.buildingId,
      'roomId': widget.roomId,
      'operationId': const Uuid().v4(),
      if (!_creating) 'revision': _revision,
      'roomNumber': _number.text.trim(),
      'roomType': _type.text.trim(),
      'area': _parseArea(_area.text),
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final deleting = _deleting, creating = _creating;
      await widget.service.roomDetails(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      if (creating && widget.onCreated != null) {
        _pending = null;
        widget.onCreated!();
        return;
      }
      setState(() {
        _saving = false;
        _pending = null;
        _created = true;
      });
      if (deleting) {
        setState(() {
          _deleted = true;
          _revision = null;
          _confirmDelete = false;
          _number.clear();
          _type.clear();
          _area.clear();
          _message = 'room_deleted';
        });
        widget.onDeleted?.call();
      } else {
        await _load(saved: true);
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _message = 'room_edit_uncertain';
        if (error is FirebaseFunctionsException) {
          if ([
            'unauthenticated',
            'permission-denied',
            'not-found',
          ].contains(error.code)) {
            _pending = null;
            _revision = null;
            _confirmDelete = false;
            _number.clear();
            _type.clear();
            _area.clear();
            _message = 'room_edit_unavailable';
          } else if (error.code == 'aborted') {
            _pending = null;
            _revision = null;
            _confirmDelete = false;
            _message = 'room_edit_conflict';
          } else if (error.code == 'already-exists') {
            _pending = null;
            _message = 'room_edit_duplicate';
          } else if ([
            'invalid-argument',
            'failed-precondition',
            'already-exists',
          ].contains(error.code)) {
            _pending = null;
            _message = error.message == 'room_not_empty'
                ? 'room_not_empty'
                : 'room_edit_rejected';
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bulk) {
      return BulkRoomsScreen(
        openGenerator: true,
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        service: widget.service,
        onBack: () => setState(() => _bulk = false),
        onCreated: widget.onCreated ?? widget.onBack,
      );
    }
    final t = AppTranslations.of(context),
        locked = _loading || _saving || _pending != null || _confirmDelete,
        inDialog = DialogPageScope.contains(context),
            // New room from the calendar: the dialog's title says it all.
            // Or a chip page of the room dialog: the chip names it.
            bare =
            inDialog &&
            (widget.onCreated != null || PageTabScope.contains(context));
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: WorkspacePageScope.constraints(context, 720),
          child: ListView(
            shrinkWrap: StackedPageScope.contains(context),
            physics: StackedPageScope.contains(context)
                ? const NeverScrollableScrollPhysics()
                : null,
            padding: const EdgeInsets.all(16),
            children: [
              if (!bare) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: _saving || _pending != null
                        ? null
                        : widget.onBack,
                    child: Text(
                      inDialog
                          ? DialogPageScope.back(context)
                          : t['room_directory'],
                    ),
                  ),
                ),
                Text(
                  t[_creating ? 'room_create' : 'room_edit_details'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
              ],
              if (_creating && _revision != null) ...[
                WsActions(
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('room-bulk-mode'),
                      onPressed: locked
                          ? null
                          : () => setState(() => _bulk = true),
                      icon: const Icon(Icons.playlist_add),
                      label: Text(t['rooms_generate']),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (_creating && _currency != null)
                Text('${t['room_create_info']} $_currency'),
              if (_loading || _saving) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(t[_message!])),
              const SizedBox(height: 16),
              if (_revision != null || _message == 'room_edit_conflict')
                Form(
                  key: _form,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    children: [
                      TextFormField(
                        key: const ValueKey('room-edit-number'),
                        controller: _number,
                        enabled: !locked,
                        readOnly: _revision == null,
                        maxLength: 80,
                        minLines: 1,
                        maxLines: null,
                        decoration: InputDecoration(
                          labelText: t['room_edit_number'],
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? t['room_edit_required']
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('room-edit-type'),
                        controller: _type,
                        enabled: !locked,
                        readOnly: _revision == null,
                        maxLength: 160,
                        minLines: 2,
                        maxLines: null,
                        // Optional (2026-10-04).
                        decoration: InputDecoration(
                          labelText: t['room_edit_type_optional'],
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('room-edit-area'),
                        controller: _area,
                        enabled: !locked,
                        readOnly: _revision == null,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        maxLength: 20,
                        decoration: InputDecoration(
                          labelText: t['room_edit_area'],
                          errorMaxLines: 8,
                        ),
                        validator: (v) {
                          final area = _parseArea(v ?? '');
                          return area == null ||
                                  !area.isFinite ||
                                  area <= 0 ||
                                  area > 100000
                              ? t['room_edit_area_invalid']
                              : null;
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_revision != null)
                        WsActions(
                          children: [
                            FilledButton(
                              onPressed:
                                  _loading ||
                                      _saving ||
                                      _deleting ||
                                      _confirmDelete
                                  ? null
                                  : _save,
                              child: Text(
                                t[_pending == null
                                    ? (_creating
                                          ? 'room_create_save'
                                          : 'room_edit_save')
                                    : 'room_edit_retry'],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              if (widget.canDelete &&
                  !_creating &&
                  !_deleted &&
                  _revision != null) ...[
                const SizedBox(height: 24),
                if (_confirmDelete || _deleting) ...[
                  Text(_savedNumber),
                  Text(t['room_delete_hint']),
                  const SizedBox(height: 12),
                  WsActions(
                    children: [
                      FilledButton(
                        onPressed: _saving ? null : _delete,
                        child: Text(
                          t[_deleting
                              ? 'room_delete_retry'
                              : 'room_empty_delete_confirm'],
                        ),
                      ),
                    ],
                  ),
                  if (!_deleting) ...[
                    const SizedBox(height: 8),
                    WsActions(
                      children: [
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _confirmDelete = false),
                          child: Text(t['room_delete_cancel']),
                        ),
                      ],
                    ),
                  ],
                ] else
                  WsActions(
                    children: [
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => setState(() => _confirmDelete = true),
                        child: Text(t['room_empty_delete']),
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: 16),
              if (!_deleted && (!inDialog || (_revision == null && !_loading)))
                WsActions(
                  children: [
                    OutlinedButton(
                      onPressed: locked ? null : () => _load(),
                      child: Text(t['room_edit_reload']),
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
