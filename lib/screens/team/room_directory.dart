import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'room_details_screen.dart';
import 'room_rates_screen.dart';
import 'room_booking_settings_screen.dart';

class RoomDirectory extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;
  final VoidCallback onBack;
  final bool canDelete;
  const RoomDirectory({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    required this.onBack,
    this.canDelete = false,
  });
  @override
  State<RoomDirectory> createState() => _RoomDirectoryState();
}

class _RoomDirectoryState extends State<RoomDirectory> {
  List<Map<String, dynamic>> _rooms = [];
  String? _cursor, _selected;
  bool _busy = true, _failed = false;
  bool _creating = false;
  String? _ratesRoom;
  String? _settingsRoom;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RoomDirectory old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.canDelete != widget.canDelete ||
        old.service != widget.service) {
      _selected = null;
      _creating = false;
      _ratesRoom = null;
      _settingsRoom = null;
      _load();
    }
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
      if (!more) {
        _rooms = [];
        _cursor = null;
      }
    });
    try {
      final page = await widget.service.workspace(
        widget.organizationId,
        'rooms',
        buildingId: widget.buildingId,
        cursor: more ? _cursor : null,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _rooms = [if (more) ..._rooms, ...page.records];
        _cursor = page.nextCursor;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _rooms = [];
        _cursor = null;
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context),
        number = NumberFormat.decimalPattern(t.locale.languageCode);
    if (_settingsRoom != null) {
      return RoomBookingSettingsScreen(
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        roomId: _settingsRoom!,
        service: widget.service,
        onBack: () {
          setState(() => _settingsRoom = null);
          _load();
        },
      );
    }
    if (_ratesRoom != null) {
      return RoomRatesScreen(
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        roomId: _ratesRoom!,
        service: widget.service,
        onBack: () {
          setState(() => _ratesRoom = null);
          _load();
        },
      );
    }
    if (_selected != null) {
      return RoomDetailsScreen(
        organizationId: widget.organizationId,
        buildingId: widget.buildingId,
        roomId: _selected!,
        create: _creating,
        canDelete: widget.canDelete,
        service: widget.service,
        onBack: () {
          setState(() {
            _selected = null;
            _creating = false;
          });
          _load();
        },
      );
    }
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextButton(
                onPressed: widget.onBack,
                child: Text(t['workspace_title']),
              ),
              Text(
                t['room_directory'],
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              if (_busy) const LinearProgressIndicator(),
              if (_failed) Text(t['room_edit_unavailable']),
              if (!_busy && !_failed && _rooms.isEmpty)
                Text(t['room_directory_empty']),
              OutlinedButton(
                onPressed: _busy ? null : () => _load(),
                child: Text(t['team_refresh']),
              ),
              if (!_failed)
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _creating = true;
                          _selected = const Uuid().v4();
                        }),
                  child: Text(t['room_create']),
                ),
              for (final room in _rooms)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room['roomNumber'] as String? ?? room['id'] as String,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          room['roomType'] as String? ?? t['team_unspecified'],
                        ),
                        Text(
                          '${t['room_edit_area']}: ${room['area'] is num ? number.format(room['area']) : t['team_unspecified']}',
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          key: ValueKey('edit-room-${room['id']}'),
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _selected = room['id'] as String,
                                ),
                          child: Text(t['room_edit_details']),
                        ),
                        OutlinedButton(
                          key: ValueKey('settings-room-${room['id']}'),
                          onPressed: _busy
                              ? null
                              : () => setState(
                                  () => _settingsRoom = room['id'] as String,
                                ),
                          child: Text(t['settings_title']),
                        ),
                        if (room['canEditRates'] == true)
                          OutlinedButton(
                            key: ValueKey('rates-room-${room['id']}'),
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _ratesRoom = room['id'] as String,
                                  ),
                            child: Text(t['rates_title']),
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
