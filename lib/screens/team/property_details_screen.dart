import 'workspace_page_scope.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'ws_ui.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import '../../utils/app_number.dart';
import '../../utils/money_conversion.dart';
import '../../services/organization_money.dart';
import 'property_initial_rooms.dart';
import 'building_room_setup.dart';
import 'building_existing_rooms.dart';
import 'building_prices_section.dart';
import '../../widgets/time_zone_picker.dart';

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
  final _roomPlan = BuildingRoomPlan();

  /// Building prices (PRICE_DEFAULTS.md): typed here for a new building;
  /// for an existing one [BuildingPricesEditor] reports the saved ones.
  final _prices = BuildingPriceDraft();
  Map<String, String> _savedDefaults = const {};

  /// Said after creating when some hourly templates could not be saved.
  String? _note;
  bool _canSetRoomPrices = false;

  /// What new room rows start with (only when rooms use the building's
  /// currency).
  Map<String, String> get _roomDefaults =>
      !_canSetRoomPrices || _roomCurrency != _currency
      ? const {}
      : _creating
      ? _prices.roomDefaults
      : _savedDefaults;
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
  MoneyForm _money = MoneyForm(null);
  String get _inputCurrency => _money.currency(_currency);
  String _currency = 'VND', _roomCurrency = 'VND';
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
    _roomPlan.dispose();
    _name.dispose();
    _address.dispose();
    _zone.dispose();
    _cost.dispose();
    _prices.dispose();
    _clearRooms();
    super.dispose();
  }

  Future<void> _load({bool saved = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _revision = null;
      _message = null;
      _note = null;
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
        _roomCurrency = row['roomCurrency'] as String? ?? _currency;
        _canSetRoomPrices = row['canSetRoomPrices'] == true;
        _roomPlan.load(row['layout'] as Map?);
        _money = MoneyForm(
          OrganizationMoney.shared.forOrganization(widget.organizationId),
        );
        _money.set(
          _cost,
          (row['exploitationCostMinor'] as num?)?.toInt(),
          _currency,
        );
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
    if (_pending == null) {
      for (final r in _rooms) {
        r.showRequired = true;
      }
      if (!(_form.currentState?.validate() ?? false)) return;
    }
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
          : _money.parse(_cost, _currency),
      'rooms': _rooms.map((r) => r.toMap(_roomCurrency)).toList(),
      if (_rooms.isNotEmpty) 'roomCurrency': _roomCurrency,
      'layout': _roomPlan.toMap(),
      if (_creating && _canSetRoomPrices) ...{
        'defaultPrices': _prices.defaults(_currency),
        'electricityPriceMinor': _prices.electricityMinor(_currency),
      },
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
      // Hourly templates typed for the new building are saved right after it.
      var failed = 0;
      if (creating) {
        for (final tpl in List.of(_prices.templates)) {
          try {
            await widget.service.bookingWorkspace({
              'action': 'hourTemplates',
              'organizationId': widget.organizationId,
              'buildingId': widget.buildingId,
              ...tpl.toMap(),
            });
            _prices.templates.remove(tpl);
          } catch (_) {
            failed++;
          }
        }
        if (!mounted || generation != _generation) return;
      }
      if (failed > 0) {
        // The building exists: show it as an existing one, where the
        // templates can be added again.
        final vi = AppTranslations.of(context).locale.languageCode == 'vi';
        setState(() {
          _saving = false;
          _pending = null;
          _created = true;
          _prices.templates.clear();
        });
        await _load(saved: true);
        if (mounted) {
          setState(
            () => _note = vi
                ? 'Đã tạo cơ sở, nhưng $failed mẫu giá theo giờ chưa lưu được. Thêm lại ở mục Giá của cơ sở.'
                : 'The building was created, but $failed hourly template(s) were not saved. Add them again under Building prices.',
          );
        }
        return;
      }
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
                : error.code == 'already-exists'
                ? 'property_room_duplicate'
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // In a dialog its title bar names the page and closes it.
                if (!inDialog) ...[
                  TextButton(
                    onPressed: _saving || _pending != null
                        ? null
                        : widget.onBack,
                    child: Text(t['workspace_title']),
                  ),
                  Text(
                    t[_creating ? 'property_create' : 'property_details'],
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                ],
                if (_loading || _saving) const LinearProgressIndicator(),
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
                          // Optional (2026-10-14, Tom).
                          decoration: InputDecoration(
                            labelText: t['property_address'],
                          ),
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
                                  suffixIcon: IconButton(
                                    key: const ValueKey(
                                      'property-timezone-choose',
                                    ),
                                    tooltip: t['timezone_choose'],
                                    icon: const Icon(Icons.arrow_drop_down),
                                    onPressed: locked
                                        ? null
                                        : () async {
                                            final generation = _generation;
                                            final zone = await chooseTimeZone(
                                              context,
                                              _zone.text.trim(),
                                            );
                                            if (mounted &&
                                                generation == _generation &&
                                                zone != null) {
                                              setState(() => _zone.text = zone);
                                            }
                                          },
                                  ),
                                ),
                              ),
                              // No long explanation under it (2026-10-14, Tom).
                              const SizedBox(height: 16),
                            ],
                          ),
                        if (_creating && _revision != null) ...[
                          Text('${t['organization_currency']}: $_currency'),
                          const SizedBox(height: 8),
                          Text(t['organization_currency_inherited']),
                          const SizedBox(height: 16),
                        ],
                        Semantics(
                          label:
                              '${t['property_exploitation_cost']} ($_inputCurrency)',
                          child: TextFormField(
                            key: const ValueKey('property-exploitation-cost'),
                            controller: _cost,
                            enabled: !locked,
                            readOnly: _revision == null,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: appMoneyInput(_inputCurrency),
                            decoration: InputDecoration(
                              labelText:
                                  '${t['property_exploitation_cost']} ($_inputCurrency)',
                              errorMaxLines: 4,
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? null
                                : _money.parse(_cost, _currency) == null
                                ? t['property_invalid_amount']
                                : null,
                          ),
                        ),
                        const SizedBox(height: 24),
                        if (_creating &&
                            _revision != null &&
                            _canSetRoomPrices) ...[
                          BuildingPriceFields(
                            draft: _prices,
                            currency: _currency,
                            locked: locked,
                            onRoomDefaultChanged: (field, old, next) =>
                                setState(() {
                                  if (_roomCurrency != _currency) return;
                                  for (final r in _rooms) {
                                    final c = r.prices[field]!;
                                    if (c.text == old) c.text = next;
                                  }
                                }),
                            onChanged: () => setState(() {}),
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (!_creating && _revision != null) ...[
                          BuildingPricesEditor(
                            key: ValueKey(
                              'prices-${widget.buildingId}-$_generation',
                            ),
                            organizationId: widget.organizationId,
                            buildingId: widget.buildingId,
                            service: widget.service,
                            onDefaults: (d) {
                              if (mounted) setState(() => _savedDefaults = d);
                            },
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (!_creating && _revision != null)
                          BuildingExistingRooms(
                            key: ValueKey(
                              'existing-${widget.buildingId}-$_generation',
                            ),
                            organizationId: widget.organizationId,
                            buildingId: widget.buildingId,
                            service: widget.service,
                          ),
                        // Rooms: type how many, then fill in each one
                        // (2026-10-23, Tom). The saved floor layout
                        // (_roomPlan) is kept as it was, just not shown.
                        PropertyInitialRooms(
                          title: t['building_rooms_to_add'],
                          hint: t['building_rooms_to_add_hint'],
                          rooms: _rooms,
                          currency: _roomCurrency,
                          locked: locked || _revision == null,
                          canSetPrices: _canSetRoomPrices,
                          defaults: _roomDefaults,
                          onAdd: () => setState(
                            () => _rooms.add(
                              InitialRoomDraft(defaults: _roomDefaults),
                            ),
                          ),
                          onGenerate: (rows) =>
                              setState(() => _rooms.addAll(rows)),
                          onRemove: (room) => setState(() {
                            _rooms.remove(room);
                            room.dispose();
                          }),
                        ),
                        // Delete and Save side by side, Delete first
                        // (2026-10-14, Tom); confirming a delete replaces them.
                        if (_revision != null && !_confirmDelete && !_deleting)
                          WsActions(
                            children: [
                              if (widget.canDelete && !_creating && !_deleted)
                                OutlinedButton(
                                  key: const ValueKey('property-delete'),
                                  onPressed: locked
                                      ? null
                                      : () => setState(
                                          () => _confirmDelete = true,
                                        ),
                                  child: Text(t['property_delete']),
                                ),
                              FilledButton(
                                key: const ValueKey('property-save'),
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
                if (_note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: WsNotice(
                      _note!,
                      key: const ValueKey('property-template-note'),
                      tone: WsTone.warning,
                    ),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(t[_message!]),
                    ),
                  ),
                if (widget.canDelete &&
                    !_creating &&
                    !_deleted &&
                    _revision != null &&
                    (_confirmDelete || _deleting)) ...[
                  const SizedBox(height: 16),
                  Text(_savedName),
                  Text(t['property_delete_hint']),
                  const SizedBox(height: 12),
                  WsActions(
                    children: [
                      if (!_deleting)
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() => _confirmDelete = false),
                          child: Text(t['property_delete_cancel']),
                        ),
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
                ],
                const SizedBox(height: 16),
                // In a dialog: only when the details could not be loaded.
                if (!_deleted &&
                    (!inDialog || (_revision == null && !_loading)))
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
      ),
    );
  }
}
