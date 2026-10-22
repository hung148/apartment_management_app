import 'package:flutter/material.dart';

import '../../utils/localizations/app_localizations.dart';
import 'ws_ui.dart';

/// Room picker for the booking and lease forms (2026-10-22, Tom): the form
/// shows only the chosen room; tapping it opens a list of the rooms to pick
/// another one, instead of laying every room of the property out in the form.

String _pickerText(BuildContext context, String key) {
  final vi = AppTranslations.of(context).locale.languageCode == 'vi';
  const labels = <String, List<String>>{
    'room': ['Room', 'Phòng'],
    'choose': ['Choose a room', 'Chọn phòng'],
    'search': ['Find a room', 'Tìm phòng'],
    'noMatch': ['No room matches.', 'Không có phòng phù hợp.'],
    'empty': ['No rooms yet.', 'Chưa có phòng nào.'],
    'more': ['Show more', 'Xem thêm'],
    'retry': ['Try again', 'Thử lại'],
    'failed': [
      'Could not load the rooms.',
      'Không tải được danh sách phòng.',
    ],
    'close': ['Close', 'Đóng'],
  };
  final pair = labels[key]!;
  return vi ? pair[1] : pair[0];
}

/// One room in the list. A room that cannot be chosen stays in the list,
/// greyed out, with [note] saying why.
class RoomChoice {
  final String id, label;
  final bool enabled;
  final String? note;
  const RoomChoice(this.id, this.label, {this.enabled = true, this.note});
}

/// A page of rooms read from the server ([hasMore]: another page exists).
class RoomChoicePage {
  final List<RoomChoice> rooms;
  final bool hasMore;
  const RoomChoicePage(this.rooms, {this.hasMore = false});
}

/// The box in the form: "Phòng" with the chosen room, and an arrow.
/// [onPick] null = cannot be changed (saved booking, form busy).
/// Key [fieldKey] is on the tappable box; tests and links use it.
class RoomPickerField extends StatefulWidget {
  final String fieldKey;
  final String? value;
  final Future<void> Function()? onPick;
  final String? label;

  /// Shown under the box in red (e.g. "required" from a FormField).
  final String? errorText;

  /// False where the section title already says "Phòng".
  final bool showLabel;
  const RoomPickerField({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.onPick,
    this.label,
    this.errorText,
    this.showLabel = true,
  });
  @override
  State<RoomPickerField> createState() => _RoomPickerFieldState();
}

class _RoomPickerFieldState extends State<RoomPickerField> {
  // A double tap opens the list once.
  bool _open = false;

  Future<void> _tap() async {
    if (_open) return;
    _open = true;
    try {
      await widget.onPick!();
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPick != null;
    final value = widget.value;
    final theme = Theme.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        // 2026-10-22 (Tom): as wide as the room name. Min: room for the
        // label; max: long names wrap instead of stretching across a desktop.
        constraints: BoxConstraints(
          minWidth: widget.showLabel ? 120 : 0,
          maxWidth: 420,
        ),
        child: IntrinsicWidth(
          child: Semantics(
            button: true,
            enabled: enabled,
            child: InkWell(
              key: ValueKey(widget.fieldKey),
              borderRadius: BorderRadius.circular(10),
              onTap: enabled ? _tap : null,
              child: InputDecorator(
                decoration: InputDecoration(
                  enabled: enabled,
                  labelText: widget.showLabel
                      ? widget.label ?? _pickerText(context, 'room')
                      : null,
                  errorText: widget.errorText,
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                ),
                // The full room name, wrapped when long (never cut with "…").
                // "Chọn phòng" is text in hint grey (not hintText) so the box
                // also fits it when nothing is chosen yet.
                child: Text(
                  value ?? _pickerText(context, 'choose'),
                  style: value == null
                      ? theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.5,
                          ),
                        )
                      : theme.textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the list of rooms; returns the chosen room's id, or null when
/// closed without a choice. Rows are keyed '[keyPrefix]-<room id>'.
///
/// [rooms] is what the form already has. With [load], the list reads the
/// rooms itself: at once when [rooms] is empty, and "Xem thêm" while
/// [hasMore] (load(true) = the next page).
Future<String?> showRoomPicker(
  BuildContext context, {
  required String keyPrefix,
  required List<RoomChoice> rooms,
  String? selectedId,
  bool hasMore = false,
  Future<RoomChoicePage> Function(bool more)? load,
}) => showDialog<String>(
  context: context,
  builder: (_) => _RoomPickerDialog(
    keyPrefix: keyPrefix,
    rooms: rooms,
    selectedId: selectedId,
    hasMore: hasMore,
    load: load,
  ),
);

class _RoomPickerDialog extends StatefulWidget {
  final String keyPrefix;
  final List<RoomChoice> rooms;
  final String? selectedId;
  final bool hasMore;
  final Future<RoomChoicePage> Function(bool more)? load;
  const _RoomPickerDialog({
    required this.keyPrefix,
    required this.rooms,
    required this.selectedId,
    required this.hasMore,
    required this.load,
  });
  @override
  State<_RoomPickerDialog> createState() => _RoomPickerDialogState();
}

/// Room number order: "QA101 < QA102 < QA103", "9 < 10" (2026-10-22, Tom).
int compareRoomLabels(String a, String b) {
  final parts = RegExp(r'\d+|\D+');
  final x = parts.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final y = parts.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final m = int.tryParse(x[i]), n = int.tryParse(y[i]);
    final c = m != null && n != null ? m.compareTo(n) : x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

List<RoomChoice> _sorted(List<RoomChoice> rooms) =>
    List.of(rooms)..sort((a, b) => compareRoomLabels(a.label, b.label));

class _RoomPickerDialogState extends State<_RoomPickerDialog> {
  late List<RoomChoice> _rooms = _sorted(widget.rooms);
  late bool _hasMore = widget.hasMore && widget.load != null;
  final _search = TextEditingController();
  bool _loading = false, _failed = false, _lastMore = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    if (_rooms.isEmpty && widget.load != null) _fetch(false);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _fetch(bool more) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
      _lastMore = more;
    });
    try {
      final page = await widget.load!(more);
      if (!mounted || generation != _generation) return;
      setState(() {
        final known = more ? _rooms.map((r) => r.id).toSet() : <String>{};
        _rooms = _sorted([
          if (more) ..._rooms,
          ...page.rooms.where((r) => known.add(r.id)),
        ]);
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String p(String key) => _pickerText(context, key);
    final query = _search.text.trim().toLowerCase();
    final shown = query.isEmpty
        ? _rooms
        : _rooms.where((r) => r.label.toLowerCase().contains(query)).toList();
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final k = widget.keyPrefix;
    return Dialog(
      key: ValueKey('$k:dialog'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            WsSpace.lg,
            WsSpace.sm,
            WsSpace.sm,
            WsSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(p('choose'), style: theme.textTheme.titleLarge),
                  ),
                  IconButton(
                    key: ValueKey('$k:close'),
                    tooltip: p('close'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              // Search only when the list is long enough to need it.
              if (_rooms.length > 8 || _hasMore)
                Padding(
                  padding: const EdgeInsets.only(
                    top: WsSpace.sm,
                    right: WsSpace.sm,
                  ),
                  child: TextField(
                    key: ValueKey('$k:search'),
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: p('search'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
              const SizedBox(height: WsSpace.sm),
              if (_loading) const LinearProgressIndicator(),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(right: WsSpace.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final room in shown)
                        ListTile(
                          key: ValueKey('$k-${room.id}'),
                          enabled: room.enabled,
                          selected: room.id == widget.selectedId,
                          selectedTileColor: theme.colorScheme.primary
                              .withValues(alpha: 0.08),
                          leading: const Icon(Icons.meeting_room_outlined),
                          title: Text(room.label),
                          subtitle: room.note == null ? null : Text(room.note!),
                          trailing: room.id == widget.selectedId
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () => Navigator.pop(context, room.id),
                        ),
                      if (!_loading && !_failed && shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(WsSpace.md),
                          child: Text(
                            p(_rooms.isEmpty ? 'empty' : 'noMatch'),
                            style: muted,
                          ),
                        ),
                      if (_failed)
                        Padding(
                          padding: const EdgeInsets.only(top: WsSpace.sm),
                          child: WsNotice(
                            p('failed'),
                            tone: WsTone.warning,
                            action: TextButton(
                              key: ValueKey('$k:retry'),
                              onPressed: () => _fetch(_lastMore),
                              child: Text(p('retry')),
                            ),
                          ),
                        ),
                      if (_hasMore && !_loading && !_failed)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: ValueKey('$k:more'),
                            onPressed: () => _fetch(true),
                            child: Text(p('more')),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
