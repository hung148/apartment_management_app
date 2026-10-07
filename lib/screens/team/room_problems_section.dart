import 'package:flutter/material.dart';
import '../../services/team_service.dart';
import '../calendar/room_calendar.dart' show CalendarPageDialog;
import 'service_fee_text.dart' show FeeText;
import 'technical_problems_screen.dart';
import 'ws_ui.dart';

/// A room's technical problems inside a short-stay booking or a long-stay lease
/// (2026-10-04). The room's open problems, and a button that opens that room's
/// problems (report, fix, photos) in a dialog. Hidden for people who may not
/// see problems.
class RoomProblemsSection extends StatefulWidget {
  final String organizationId, buildingId, roomId;

  /// Shown in the dialog's title, e.g. "Phòng 101".
  final String roomLabel;
  final TeamService service;
  const RoomProblemsSection({
    super.key,
    required this.organizationId,
    required this.buildingId,
    required this.roomId,
    required this.roomLabel,
    required this.service,
  });
  @override
  State<RoomProblemsSection> createState() => _RoomProblemsSectionState();
}

class _RoomProblemsSectionState extends State<RoomProblemsSection> {
  List<Map> _open = const [];
  bool _busy = true, _hidden = false, _canReport = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RoomProblemsSection old) {
    super.didUpdateWidget(old);
    if (old.organizationId != widget.organizationId ||
        old.buildingId != widget.buildingId ||
        old.roomId != widget.roomId ||
        old.service != widget.service) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final data = await widget.service.technicalProblems({
        'action': 'list',
        'organizationId': widget.organizationId,
        'buildingId': widget.buildingId,
        'status': 'open',
      });
      if (!mounted || generation != _generation) return;
      setState(() {
        _open = ((data['records'] as List?) ?? const [])
            .cast<Map>()
            .where((r) => r['roomId'] == widget.roomId && r['status'] == 'open')
            .toList();
        _canReport = data['canReport'] == true;
        _busy = false;
        _hidden = false;
      });
    } catch (_) {
      // No access to problems (or offline): the section stays out of the way.
      if (!mounted || generation != _generation) return;
      setState(() {
        _busy = false;
        _hidden = true;
      });
    }
  }

  Future<void> _openRoom(FeeText x) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CalendarPageDialog(
        title:
            '${widget.roomLabel} · ${x.tr('Technical problems', 'Sự cố kỹ thuật')}',
        build: (close) => TechnicalProblemsScreen(
          organizationId: widget.organizationId,
          buildingId: widget.buildingId,
          service: widget.service,
          onlyRoomId: widget.roomId,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final x = FeeText(context);
    final theme = Theme.of(context);
    return WsSection(
      key: const ValueKey('room-problems'),
      title: x.tr('Technical problems', 'Sự cố kỹ thuật'),
      icon: Icons.build_outlined,
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (!_busy && _open.isEmpty)
          Text(
            x.tr(
              'No open problems in this room.',
              'Phòng không có sự cố đang mở.',
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        for (final p in _open)
          Padding(
            padding: const EdgeInsets.only(bottom: WsSpace.xs),
            child: Wrap(
              spacing: WsSpace.sm,
              runSpacing: WsSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  Icons.build_circle,
                  size: 16,
                  color: wsToneColor(context, WsTone.bad),
                ),
                Text('${p['title']}', style: theme.textTheme.bodyMedium),
                if (p['blocksRoom'] == true)
                  WsPill(
                    x.tr(
                      'Room not rented until fixed',
                      'Phòng tạm ngừng cho thuê',
                    ),
                    tone: WsTone.bad,
                  ),
              ],
            ),
          ),
        const SizedBox(height: WsSpace.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('room-problems-open'),
            onPressed: _busy ? null : () => _openRoom(x),
            icon: const Icon(Icons.build_outlined, size: 18),
            label: Text(
              _canReport
                  ? x.tr('Report or view', 'Báo / xem sự cố')
                  : x.tr('View', 'Xem sự cố'),
            ),
          ),
        ),
      ],
    );
  }
}
