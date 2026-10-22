import 'package:flutter/material.dart';
import '../../services/team_service.dart';
import '../../utils/localizations/app_localizations.dart';
import 'ws_ui.dart';

/// Existing inventory is separate from the unsaved rooms to create.
class BuildingExistingRooms extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;
  const BuildingExistingRooms({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
  });
  @override
  State<BuildingExistingRooms> createState() => _BuildingExistingRoomsState();
}

class _BuildingExistingRoomsState extends State<BuildingExistingRooms> {
  final _rooms = <Map<String, dynamic>>[];
  String? _cursor;
  bool _busy = false, _failed = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BuildingExistingRooms old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.service != widget.service) {
      _generation++;
      _rooms.clear();
      _cursor = null;
      _busy = false;
      _load();
    }
  }

  Future<void> _load() async {
    if (_busy) return;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final page = await widget.service.workspace(
        widget.organizationId,
        'rooms',
        buildingId: widget.buildingId,
        cursor: _cursor,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _rooms.map((r) => r['id']).toSet();
        _rooms.addAll(page.records.where((r) => !ids.contains(r['id'])));
        _cursor = page.nextCursor;
        _busy = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      // Clear stale inventory if access has changed, including pagination.
      setState(() {
        _rooms.clear();
        _cursor = null;
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    final vi = t.locale.languageCode == 'vi';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          vi ? 'Phòng hiện có' : 'Existing rooms',
          key: const ValueKey('building-existing-rooms'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_busy) const LinearProgressIndicator(),
        if (_failed) ...[
          Text(t['room_edit_unavailable']),
          WsActions(
            children: [
              OutlinedButton(
                onPressed: _load,
                child: Text(t['room_edit_reload']),
              ),
            ],
          ),
        ],
        if (!_busy && !_failed && _rooms.isEmpty)
          Text(t['room_directory_empty']),
        for (final room in _rooms)
          Card(
            key: ValueKey('existing-room-${room['id']}'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${room['roomNumber'] ?? ''}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if ('${room['roomType'] ?? ''}'.trim().isNotEmpty)
                    Text('${room['roomType']}'),
                  if (room['area'] is num && (room['area'] as num) > 0)
                    Text('${room['area']} m²'),
                ],
              ),
            ),
          ),
        if (_cursor != null && !_busy)
          WsActions(
            children: [
              OutlinedButton(
                key: const ValueKey('existing-rooms-more'),
                onPressed: _load,
                child: Text(t['workspace_more']),
              ),
            ],
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}
