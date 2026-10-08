import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'property_initial_rooms.dart';
import 'ws_ui.dart';
import 'room_batch_generator.dart';

class BulkRoomsScreen extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;
  final VoidCallback onBack, onCreated;
  final bool openGenerator;
  const BulkRoomsScreen({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.onBack,
    required this.onCreated,
    this.openGenerator = false,
  });
  @override
  State<BulkRoomsScreen> createState() => _BulkRoomsScreenState();
}

class _BulkRoomsScreenState extends State<BulkRoomsScreen> {
  final _form = GlobalKey<FormState>();
  final _rooms = <InitialRoomDraft>[];
  bool _loading = true, _saving = false, _ready = false, _prices = false;
  bool _openingGenerator = false;
  String _currency = 'VND';
  String? _message;
  Map<String, dynamic>? _pending;
  int _generation = 0;
  void _clear() {
    for (final r in _rooms) {
      r.dispose();
    }
    _rooms.clear();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BulkRoomsScreen old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _pending = null;
      _saving = false;
      _load();
    }
  }

  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _clear();
      _ready = false;
      _loading = true;
      _message = null;
    });
    try {
      final response = await widget.service.roomDetails({
        'action': 'prepareBulk',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
      });
      if (!mounted || generation != _generation) return;
      final r = response['record'] as Map;
      setState(() {
        _currency = r['currency'] as String;
        _prices = r['canSetRoomPrices'] == true;
        _ready = !widget.openGenerator;
      });
      if (widget.openGenerator) {
        setState(() {
          _loading = false;
          _openingGenerator = true;
        });
        final rows = await generateRoomBatch(
          context,
          currency: _currency,
          canSetPrices: _prices,
          existing: _rooms,
        );
        if (!mounted || generation != _generation) {
          if (rows != null) {
            for (final row in rows) {
              row.dispose();
            }
          }
          return;
        }
        if (rows == null) {
          widget.onBack();
          return;
        }
        setState(() {
          _openingGenerator = false;
          _rooms.addAll(rows);
          _ready = true;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _message = 'room_edit_unavailable');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_ready || _rooms.isEmpty) return;
    if (_pending == null && !_form.currentState!.validate()) return;
    _pending ??= {
      'action': 'createBulk',
      'organizationId': widget.organizationId,
      'buildingId': widget.buildingId,
      'operationId': const Uuid().v4(),
      'rooms': _rooms.map((r) => r.toMap(_currency)).toList(),
    };
    final generation = _generation;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await widget.service.roomDetails(Map.of(_pending!));
      if (!mounted || generation != _generation) return;
      _pending = null;
      widget.onCreated();
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _message = 'room_edit_uncertain';
        if (error is FirebaseFunctionsException) {
          if ([
            'permission-denied',
            'unauthenticated',
            'not-found',
          ].contains(error.code)) {
            _clear();
            _ready = false;
            _pending = null;
            _message = 'room_edit_unavailable';
          } else if ([
            'already-exists',
            'invalid-argument',
            'failed-precondition',
            'aborted',
          ].contains(error.code)) {
            _pending = null;
            _message = error.code == 'already-exists'
                ? 'room_edit_duplicate'
                : 'room_edit_rejected';
          }
        }
      });
    } finally {
      if (mounted && generation == _generation) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_openingGenerator) return const SizedBox.shrink();
    final t = AppTranslations.of(context),
        locked = _loading || _saving || _pending != null;
    return WsPage(
      children: [
        WsActions(
          children: [
            TextButton(
              onPressed: locked ? null : widget.onBack,
              child: Text(t['back']),
            ),
          ],
        ),
        if (_loading || _saving) const LinearProgressIndicator(),
        if (_message != null) ...[
          Semantics(liveRegion: true, child: Text(t[_message!])),
          const SizedBox(height: 16),
        ],
        if (_ready)
          Form(
            key: _form,
            child: PropertyInitialRooms(
              title: t['rooms_generate'],
              rooms: _rooms,
              currency: _currency,
              locked: locked,
              canSetPrices: _prices,
              onAdd: () => setState(() => _rooms.add(InitialRoomDraft())),
              onGenerate: (rows) => setState(() => _rooms.addAll(rows)),
              onRemove: (room) => setState(() {
                _rooms.remove(room);
                room.dispose();
              }),
            ),
          ),
        if (_ready)
          WsActions(
            children: [
              FilledButton(
                onPressed: _saving || _rooms.isEmpty ? null : _save,
                child: Text(
                  t[_pending == null ? 'rooms_save_batch' : 'room_edit_retry'],
                ),
              ),
            ],
          ),
        if (!_ready && !_loading)
          WsActions(
            children: [
              OutlinedButton(
                onPressed: _load,
                child: Text(t['room_edit_reload']),
              ),
            ],
          ),
      ],
    );
  }
}
