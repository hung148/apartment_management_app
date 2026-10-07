import 'package:flutter/material.dart';
import 'workspace_page_scope.dart';
import 'package:uuid/uuid.dart';
import '../../services/team_service.dart';
import '../../utils/app_number.dart';
import '../../utils/localizations/app_localizations.dart';
import 'room_details_screen.dart';
import 'utility_readings_screen.dart';
import 'room_service_fees_screen.dart';
import 'room_rates_screen.dart';
import 'room_booking_settings_screen.dart';
import 'back_steps.dart';
import 'ws_ui.dart';

const _roomViews = ['utilities', 'fees', 'settings', 'rates'];

/// Address record for a room page other than its details. Too long for the
/// address (128 characters) → null, so the address shows the room list rather
/// than the wrong page.
String? roomLink(String view, String roomId) {
  final link = '$view--$roomId';
  return link.length <= 128 ? link : null;
}

/// The page named in a room link, or null for a bare room ID.
String? roomLinkView(String link) {
  for (final view in _roomViews) {
    if (link.startsWith('$view--') && link.length > view.length + 2)
      return view;
  }
  return null;
}

/// The room ID in a room link (a bare ID is returned unchanged).
String roomLinkRoom(String link) {
  final view = roomLinkView(link);
  return view == null ? link : link.substring(view.length + 2);
}

class RoomDirectory extends StatefulWidget {
  final String organizationId, buildingId;
  final TeamService service;

  /// Null inside the organization workspace sections (U1): no Back button.
  /// Open this record first (from a link), then report what is open.
  final String? initialRecordId;
  final ValueChanged<String?>? onRecordChanged;
  final VoidCallback? onBack;
  final bool canDelete;

  /// Opened from the calendar (C): only this room (its card and its pages).
  final String? onlyRoomId;

  /// The room dialog's fees page links to the building's fees (calendar).
  final VoidCallback? onBuildingFees;

  /// Opened from the calendar's "New room": starts on the new-room form, then
  /// shows only the new room.
  final bool startCreate;

  /// With [startCreate]: called once the room is created (closes the dialog).
  final VoidCallback? onCreated;
  const RoomDirectory({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.service,
    this.onBack,
    this.canDelete = false,
    this.initialRecordId,
    this.onRecordChanged,
    this.onlyRoomId,
    this.startCreate = false,
    this.onCreated,
    this.onBuildingFees,
  });
  @override
  State<RoomDirectory> createState() => _RoomDirectoryState();
}

class _RoomDirectoryState extends State<RoomDirectory> {
  List<Map<String, dynamic>> _rooms = [];
  String? _cursor, _selected;
  bool _busy = true, _failed = false;
  bool _creating = false;
  String? _ratesRoom, _utilityRoom, _feesRoom;
  String? _settingsRoom;

  /// Only this room is listed (calendar dialog), else every room.
  String? _only;

  /// The room dialog's open page (2026-10-05, Tom: the pages right in the
  /// dialog under chips, instead of a card with five buttons).
  String _tab = 'details';
  bool _roomDeleted = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _only = widget.onlyRoomId;
    if (widget.startCreate) {
      _creating = true;
      _selected = const Uuid().v4();
      _only = _selected;
    }
    // A link opens the same room page that was open when it was made
    // ("utilities--<room>", "settings--<room>", "rates--<room>"); a bare room
    // ID (older links) opens the room's details.
    final link = widget.initialRecordId;
    if (link != null) {
      final view = roomLinkView(link);
      final room = roomLinkRoom(link);
      if (view == 'utilities') {
        _utilityRoom = room;
      } else if (view == 'fees') {
        _feesRoom = room;
      } else if (view == 'settings') {
        _settingsRoom = room;
      } else if (view == 'rates') {
        _ratesRoom = room;
      } else {
        _selected = room;
      }
    }
    _load();
  }

  /// The record for the address: which room page is open, if any.
  String? _openRecord() {
    if (_creating) return null;
    if (_utilityRoom != null) return roomLink('utilities', _utilityRoom!);
    if (_feesRoom != null) return roomLink('fees', _feesRoom!);
    if (_settingsRoom != null) return roomLink('settings', _settingsRoom!);
    if (_ratesRoom != null) return roomLink('rates', _ratesRoom!);
    return _selected;
  }

  // U1 step 2: tell the workspace which record is open (for the address).
  String? _reported;
  void _reportRecord(String? id) {
    if (id == _reported) return;
    _reported = id;
    final report = widget.onRecordChanged;
    if (report != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) report(id);
      });
    }
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
      _utilityRoom = null;
      _feesRoom = null;
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
      var page = await widget.service.workspace(
        widget.organizationId,
        'rooms',
        buildingId: widget.buildingId,
        cursor: more ? _cursor : null,
      );
      final found = [...page.records];
      // One room only: keep reading pages until it is found.
      while (_only != null &&
          page.nextCursor != null &&
          !found.any((r) => r['id'] == _only)) {
        page = await widget.service.workspace(
          widget.organizationId,
          'rooms',
          buildingId: widget.buildingId,
          cursor: page.nextCursor,
        );
        found.addAll(page.records);
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _rooms = [if (more) ..._rooms, ...found];
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

  /// One room in the calendar's dialog: a chip per page and the page below
  /// it, no back links (2026-10-05, Tom).
  Widget _roomTabs(BuildContext context, AppTranslations t) {
    if (_roomDeleted) {
      return WsPage(
        children: [
          WsNotice(
            t.locale.languageCode == 'vi' ? 'Đã xóa phòng.' : 'Room deleted.',
            key: const ValueKey('room-deleted'),
            tone: WsTone.good,
          ),
        ],
      );
    }
    final room = _rooms.where((r) => r['id'] == _only).firstOrNull;
    if (room == null) {
      return WsPage(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_failed) WsNotice(t['room_edit_unavailable']),
          if (!_busy && !_failed)
            WsEmpty(
              icon: Icons.meeting_room_outlined,
              message: t['room_directory_empty'],
            ),
        ],
      );
    }
    final id = room['id'] as String;
    final vi = t.locale.languageCode == 'vi';
    final utilities = room['canReadUtilities'] == true;
    void none() {}
    final pages = <(String, String, Widget Function())>[
      // Room details, then its booking settings (2026-10-05, Tom: one page).
      (
        'details',
        vi ? 'Thông tin' : 'Details',
        () => SingleChildScrollView(
          child: StackedPageScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RoomDetailsScreen(
                  organizationId: widget.organizationId,
                  buildingId: widget.buildingId,
                  roomId: id,
                  canDelete: widget.canDelete,
                  service: widget.service,
                  onBack: none,
                  onDeleted: () => setState(() => _roomDeleted = true),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                RoomBookingSettingsScreen(
                  organizationId: widget.organizationId,
                  buildingId: widget.buildingId,
                  roomId: id,
                  service: widget.service,
                  onBack: none,
                ),
              ],
            ),
          ),
        ),
      ),
      if (utilities)
        (
          'utilities',
          vi ? 'Điện nước' : 'Utilities',
          () => UtilityReadingsScreen(
            organizationId: widget.organizationId,
            buildingId: widget.buildingId,
            roomId: id,
            service: widget.service,
            onBack: none,
          ),
        ),
      if (utilities)
        (
          'fees',
          vi ? 'Phí dịch vụ' : 'Service fees',
          () => RoomServiceFeesScreen(
            organizationId: widget.organizationId,
            buildingId: widget.buildingId,
            roomId: id,
            service: widget.service,
            onBack: none,
            onBuildingFees: widget.onBuildingFees,
          ),
        ),
      if (room['canEditRates'] == true)
        (
          'rates',
          vi ? 'Giá thuê' : 'Rates',
          () => RoomRatesScreen(
            organizationId: widget.organizationId,
            buildingId: widget.buildingId,
            roomId: id,
            service: widget.service,
            onBack: none,
          ),
        ),
    ];
    final page = pages.where((p) => p.$1 == _tab).firstOrNull ?? pages.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in pages)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      // The same keys as the room card's old buttons.
                      key: ValueKey(
                        p.$1 == 'details'
                            ? 'edit-room-$id'
                            : '${p.$1}-room-$id',
                      ),
                      label: Text(p.$2),
                      selected: p.$1 == page.$1,
                      onSelected: (_) => setState(() => _tab = p.$1),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: PageTabScope(
            child: KeyedSubtree(key: ValueKey(page.$1), child: page.$3()),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context);
    _reportRecord(_openRecord());
    if (_only != null &&
        !widget.startCreate &&
        !_creating &&
        DialogPageScope.contains(context)) {
      return _roomTabs(context, t);
    }
    if (_utilityRoom != null) {
      return BackStep(
        onBack: () => setState(() => _utilityRoom = null),
        child: UtilityReadingsScreen(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          roomId: _utilityRoom!,
          service: widget.service,
          onBack: () => setState(() => _utilityRoom = null),
        ),
      );
    }
    if (_feesRoom != null) {
      return BackStep(
        onBack: () => setState(() => _feesRoom = null),
        child: RoomServiceFeesScreen(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          roomId: _feesRoom!,
          service: widget.service,
          onBack: () => setState(() => _feesRoom = null),
        ),
      );
    }
    if (_settingsRoom != null) {
      return BackStep(
        onBack: () {
          setState(() => _settingsRoom = null);
          _load();
        },
        child: RoomBookingSettingsScreen(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          roomId: _settingsRoom!,
          service: widget.service,
          onBack: () {
            setState(() => _settingsRoom = null);
            _load();
          },
        ),
      );
    }
    if (_ratesRoom != null) {
      return BackStep(
        onBack: () {
          setState(() => _ratesRoom = null);
          _load();
        },
        child: RoomRatesScreen(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          roomId: _ratesRoom!,
          service: widget.service,
          onBack: () {
            setState(() => _ratesRoom = null);
            _load();
          },
        ),
      );
    }
    if (_selected != null) {
      return BackStep(
        onBack: () {
          setState(() {
            _selected = null;
            _creating = false;
          });
          _load();
        },
        child: RoomDetailsScreen(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          roomId: _selected!,
          create: _creating,
          canDelete: widget.canDelete,
          service: widget.service,
          onCreated: widget.startCreate ? widget.onCreated : null,
          onBack: () {
            setState(() {
              _selected = null;
              _creating = false;
            });
            _load();
          },
        ),
      );
    }
    final rooms = _only == null
        ? _rooms
        : _rooms.where((r) => r['id'] == _only).toList();
    final single = _only != null;
    // One room in a dialog: the dialog's title names it; no list to reload.
    final bare = single && DialogPageScope.contains(context);
    return WsPage(
      children: [
        if (!bare)
          WsHeader(
            back: widget.onBack == null
                ? null
                : WsBack(label: t['workspace_title'], onPressed: widget.onBack),
            title: single
                ? (rooms.firstOrNull?['roomNumber'] as String? ??
                      t['room_directory'])
                : t['room_directory'],
            actions: [
              if (!_failed && !single)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _creating = true;
                          _selected = const Uuid().v4();
                        }),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(t['room_create']),
                ),
              if (!WorkspacePageScope.contains(context))
                OutlinedButton(
                  onPressed: _busy ? null : () => _load(),
                  child: Text(t['team_refresh']),
                ),
            ],
          ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(),
          ),
        if (_failed) WsNotice(t['room_edit_unavailable']),
        if (!_busy && !_failed && rooms.isEmpty)
          WsEmpty(
            icon: Icons.meeting_room_outlined,
            message: t['room_directory_empty'],
          ),
        for (final room in rooms)
          WsRecord(
            leading: const WsBadge(icon: Icons.meeting_room_outlined),
            title: room['roomNumber'] as String? ?? room['id'] as String,
            // No rental-mode pill: every room takes both (2026-10-04).
            details: [
              room['roomType'] as String? ?? t['team_unspecified'],
              // The display label, not the form's "(m², required)" one.
              room['area'] is num
                  ? '${t['room_info_area']}: ${appQuantity(room['area'] as num, decimals: 2)} m²'
                  : '${t['room_info_area']}: ${t['team_unspecified']}',
            ],
            actions: [
              OutlinedButton(
                key: ValueKey('edit-room-${room['id']}'),
                onPressed: _busy
                    ? null
                    : () => setState(() => _selected = room['id'] as String),
                child: Text(t['room_edit_details']),
              ),
              OutlinedButton(
                key: ValueKey('settings-room-${room['id']}'),
                onPressed: _busy
                    ? null
                    : () =>
                          setState(() => _settingsRoom = room['id'] as String),
                child: Text(t['settings_title']),
              ),
              if (room['canReadUtilities'] == true)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () =>
                            setState(() => _utilityRoom = room['id'] as String),
                  child: Text(
                    t.locale.languageCode == 'vi' ? 'Điện nước' : 'Utilities',
                  ),
                ),
              if (room['canReadUtilities'] == true)
                OutlinedButton(
                  key: ValueKey('fees-room-${room['id']}'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _feesRoom = room['id'] as String),
                  child: Text(
                    t.locale.languageCode == 'vi'
                        ? 'Phí dịch vụ'
                        : 'Service fees',
                  ),
                ),
              if (room['canEditRates'] == true)
                OutlinedButton(
                  key: ValueKey('rates-room-${room['id']}'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _ratesRoom = room['id'] as String),
                  child: Text(t['rates_title']),
                ),
            ],
          ),
        if (_cursor != null && !single)
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => _load(more: true),
              child: Text(t['workspace_more']),
            ),
          ),
      ],
    );
  }
}
