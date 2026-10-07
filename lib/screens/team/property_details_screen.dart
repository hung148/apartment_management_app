import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import '../../utils/app_number.dart';
import 'property_initial_rooms.dart';

class PropertyDetailsScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;
  final VoidCallback onBack;
  final bool create, canDelete;

  /// Called once a new property is created (the calendar closes its dialog).
  /// Without it the page shows the new property's details.
  final VoidCallback? onCreated;
  const PropertyDetailsScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.onBack,
    this.create = false,
    this.canDelete = false,
    this.onCreated,
  });
  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  final _name = TextEditingController(), _address = TextEditingController();
  final _zone = TextEditingController();
  final _cost = TextEditingController();
  final _rooms = <InitialRoomDraft>[];
  bool _canSetRoomPrices = false;
  void _clearRooms() {
    for (final room in _rooms) {
      room.dispose();
    }
    _rooms.clear();
  }

  final _form = GlobalKey<FormState>();
  String? _revision, _message;
  bool _loading = true, _saving = false;
  int _generation = 0;
  Map<String, dynamic>? _pending;
  bool _created = false, _confirmDelete = false, _deleted = false;
  String _savedName = '';
  bool get _deleting => _pending?['action'] == 'delete';
  String _currency = 'VND';
  bool get _creating => widget.create && !_created;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PropertyDetailsScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.create != widget.create ||
        old.canDelete != widget.canDelete ||
        old.service != widget.service) {
      _saving = false;
      _pending = null;
      _created = false;
      _deleted = false;
      _confirmDelete = false;
      _load();
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _zone.dispose();
    _cost.dispose();
    _clearRooms();
    super.dispose();
  }

  Future<void> _load({bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _revision = null;
      _message = null;
      _confirmDelete = false;
      _name.clear();
      _address.clear();
      _zone.clear();
      _cost.clear();
      _clearRooms();
    });
    try {
      final result = await widget.service.propertyDetails({
        'action': _creating ? 'prepareCreate' : 'read',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
      });
      if (!mounted || generation != _generation) return;
      final row = Map<String, dynamic>.from(result['record'] as Map);
      setState(() {
        _revision = row['revision'] as String;
        _name.text = row['name'] as String;
        _savedName = _name.text;
        _address.text = row['address'] as String;
        _zone.text = row['timeZone'] as String? ?? '';
        _currency = row['currency'] as String? ?? 'VND';
        _canSetRoomPrices = row['canSetRoomPrices'] == true;
        _cost.text = row['exploitationCostMinor'] == null
            ? ''
            : appMoneyInputText(row['exploitationCostMinor'] as num, _currency);
        _loading = false;
        _message = saved ? 'property_saved' : null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _message = 'property_unavailable';
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
      'operationId': const Uuid().v4(),
      if (!_creating) 'revision': _revision,
      if (_creating) 'currency': _currency,
      'name': _name.text.trim(),
      'address': _address.text.trim(),
      'timeZone': _zone.text.trim().isEmpty ? null : _zone.text.trim(),
      'exploitationCostMinor': _cost.text.trim().isEmpty
          ? null
          : appParseMoney(_cost.text, _currency),
      if (_creating) 'rooms': _rooms.map((r) => r.toMap(_currency)).toList(),
    });
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final deleting = _deleting, creating = _creating;
      await widget.service.propertyDetails(Map.of(_pending!));
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
          _name.clear();
          _address.clear();
          _zone.clear();
          _cost.clear();
          _clearRooms();
          _message = 'property_deleted';
        });
      } else {
        await _load(saved: true);
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _saving = false;
        _message = 'property_uncertain';
        if (error is FirebaseFunctionsException) {
          if ([
            'unauthenticated',
            'permission-denied',
            'not-found',
          ].contains(error.code)) {
            _pending = null;
            _revision = null;
            _confirmDelete = false;
            _name.clear();
            _address.clear();
            _zone.clear();
            _cost.clear();
            _clearRooms();
            _message = 'property_unavailable';
          } else if (error.code == 'aborted') {
            _pending = null;
            _revision = null;
            _confirmDelete = false;
            _message = 'property_conflict';
          } else if ([
            'invalid-argument',
            'failed-precondition',
            'already-exists',
          ].contains(error.code)) {
            _pending = null;
            _message =
                [
                  'property_not_empty',
                  'property_has_assignments',
                ].contains(error.message)
                ? error.message
                : error.message == 'property_timezone_in_use'
                ? 'property_timezone_in_use'
                : 'property_rejected';
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context),
        locked = _loading || _saving || _pending != null || _confirmDelete,
        inDialog = DialogPageScope.contains(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: WorkspacePageScope.constraints(context, 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // In a dialog its title bar names the page and closes it.
              if (!inDialog) ...[
                TextButton(
                  onPressed: _saving || _pending != null ? null : widget.onBack,
                  child: Text(t['workspace_title']),
                ),
                Text(
                  t[_creating ? 'property_create' : 'property_details'],
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
              ],
              if (_loading || _saving) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(t[_message!])),
              const SizedBox(height: 16),
              if (_revision != null || _message == 'property_conflict')
                Form(
                  key: _form,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    children: [
                      TextFormField(
                        key: const ValueKey('property-name'),
                        controller: _name,
                        enabled: !locked,
                        readOnly: _revision == null,
                        maxLength: 160,
                        minLines: 1,
                        maxLines: null,
                        decoration: InputDecoration(
                          labelText: t['property_name'],
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? t['property_required']
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('property-address'),
                        controller: _address,
                        enabled: !locked,
                        readOnly: _revision == null,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: null,
                        decoration: InputDecoration(
                          labelText: t['property_address'],
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? t['property_required']
                            : null,
                      ),
                      const SizedBox(height: 16),
                      if (_revision != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              key: const ValueKey('property-timezone'),
                              controller: _zone,
                              validator: (v) =>
                                  _creating && (v == null || v.trim().isEmpty)
                                  ? t['property_required']
                                  : null,
                              enabled: !locked,
                              maxLength: 100,
                              minLines: 1,
                              maxLines: null,
                              decoration: InputDecoration(
                                labelText: t['property_timezone'],
                              ),
                            ),
                            Text(
                              t[_creating
                                  ? 'property_create_timezone_hint'
                                  : 'property_timezone_hint'],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      if (_creating && _revision != null) ...[
                        DropdownButtonFormField<String>(
                          key: ValueKey('property-currency-$_currency'),
                          initialValue: _currency,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t['property_currency'],
                          ),
                          items: ['VND', 'USD']
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: locked
                              ? null
                              : (value) => setState(() => _currency = value!),
                        ),
                        const SizedBox(height: 8),
                        Text(t['property_create_currency_hint']),
                        const SizedBox(height: 16),
                      ],
                      Text('${t['property_exploitation_cost']} ($_currency)'),
                      const SizedBox(height: 8),
                      Semantics(
                        label:
                            '${t['property_exploitation_cost']} ($_currency)',
                        child: TextFormField(
                          key: const ValueKey('property-exploitation-cost'),
                          controller: _cost,
                          enabled: !locked,
                          readOnly: _revision == null,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: appMoneyInput(_currency),
                          decoration: InputDecoration(errorMaxLines: 4),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? null
                              : appParseMoney(v, _currency) == null
                              ? t['property_invalid_amount']
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        t['property_cost_hint'],
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 24),
                      if (_creating)
                        PropertyInitialRooms(
                          rooms: _rooms,
                          currency: _currency,
                          locked: locked,
                          canSetPrices: _canSetRoomPrices,
                          onAdd: () =>
                              setState(() => _rooms.add(InitialRoomDraft())),
                          onRemove: (room) => setState(() {
                            _rooms.remove(room);
                            room.dispose();
                          }),
                        ),
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
                                          ? 'property_create'
                                          : 'property_save')
                                    : 'property_retry'],
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
                  Text(_savedName),
                  Text(t['property_delete_hint']),
                  const SizedBox(height: 12),
                  WsActions(
                    children: [
                      FilledButton(
                        onPressed: _saving ? null : _delete,
                        child: Text(
                          t[_deleting
                              ? 'property_delete_retry'
                              : 'property_delete_confirm'],
                        ),
                      ),
                    ],
                  ),
                  if (!_deleting)
                    WsActions(
                      children: [
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _confirmDelete = false),
                          child: Text(t['property_delete_cancel']),
                        ),
                      ],
                    ),
                ] else
                  WsActions(
                    children: [
                      OutlinedButton(
                        onPressed: locked
                            ? null
                            : () => setState(() => _confirmDelete = true),
                        child: Text(t['property_delete']),
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: 16),
              // In a dialog: only when the details could not be loaded.
              if (!_deleted && (!inDialog || (_revision == null && !_loading)))
                WsActions(
                  children: [
                    OutlinedButton(
                      onPressed: locked ? null : () => _load(),
                      child: Text(t['property_reload']),
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
