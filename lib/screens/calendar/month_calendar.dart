// The month view of the calendar (2026-10-04, Tom): like Airbnb's month
// calendar — weeks of day boxes, months one under the other, and each stay a
// pill across its days. All rooms of the building at once; each pill names
// its room ("101 · Khách"). Pills run from the check-in time to the check-out
// time, so a 14:00 → 12:00 stay starts and ends in the middle of a day.
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../utils/localizations/app_localizations.dart';
import 'room_calendar.dart';

class CalMonthView extends StatefulWidget {
  final CalProperty property;

  /// First day of each month shown, in order (the loaded window).
  final List<DateTime> months;

  /// Scroll to this month when [focusToken] changes.
  final DateTime focus;
  final int focusToken;
  final void Function(CalRoom room, CalBar bar) onOpen;
  final void Function(DateTime day) onDay;

  /// Scrolled near the top (-1) or the bottom (1): load another month.
  final void Function(int direction) onEdge;

  /// The month at the top of the screen changed (for the toolbar).
  final void Function(DateTime month) onShown;
  const CalMonthView({
    super.key,
    required this.property,
    required this.months,
    required this.focus,
    required this.focusToken,
    required this.onOpen,
    required this.onDay,
    required this.onEdge,
    required this.onShown,
  });
  @override
  State<CalMonthView> createState() => _CalMonthViewState();
}

/// One stay's piece inside one week.
class _Piece {
  final CalBar bar;
  final CalRoom room;
  final double from, to; // days from the week's Monday (fractional)
  final bool startsHere, endsHere;
  int lane = 0;
  // A pill too narrow for its name: the name goes in a tag beside it
  // (pixels from the week's left edge). Lanes keep room for the tag.
  double? tagLeft, tagW;
  _Piece(
    this.bar,
    this.room,
    this.from,
    this.to,
    this.startsHere,
    this.endsHere,
  );
}

class _Week {
  final DateTime monday;
  final List<_Piece> pieces;
  final int lanes;
  _Week(this.monday, this.pieces, this.lanes);
}

class _CalMonthViewState extends State<CalMonthView> {
  final _scroll = ScrollController();
  int _token = -1;
  // What is at the top of the screen, kept across reloads and month shifts.
  DateTime? _anchor;
  double _anchorDelta = 0;
  DateTime? _reported;
  List<double> _tops = const [];
  bool _jumping = false;

  static const _headH = 52.0, _numberH = 30.0, _laneH = 24.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // Every week's piece of a stay shows "room · name" and its status
  // (2026-10-05, Tom: no more moving the name while scrolling).

  void _onScroll() {
    if (_jumping || _tops.isEmpty) return;
    final y = _scroll.offset;
    var i = 0;
    while (i + 1 < _tops.length && _tops[i + 1] <= y + 1) {
      i++;
    }
    _anchor = widget.months[i];
    _anchorDelta = y - _tops[i];
    // The toolbar names the month that fills most of the screen: the one
    // 40 % of the way down, not a sliver at the top (2026-10-04, Tom).
    final probe = y + _scroll.position.viewportDimension * 0.4;
    var shown = 0;
    while (shown + 1 < _tops.length && _tops[shown + 1] <= probe) {
      shown++;
    }
    final month = widget.months[shown];
    if (_reported != month) {
      _reported = month;
      widget.onShown(month);
    }
  }

  DateTime _addDays(DateTime d, int n) =>
      DateTime.utc(d.year, d.month, d.day + n);

  static const _labelStyle = TextStyle(
    fontSize: 11,
    height: 1.1,
    fontWeight: FontWeight.w700,
  );

  String _name(BuildContext context, CalBar b) => calBarName(context, b);

  String _label(BuildContext context, _Piece p) =>
      '${p.room.number} · ${_name(context, p.bar)}';

  List<_Week> _weeks(
    DateTime month,
    double cellW,
    double Function(_Piece) measure,
  ) {
    final first = month, next = DateTime.utc(month.year, month.month + 1);
    var monday = _addDays(first, -(first.weekday - 1));
    final rooms = {for (final r in widget.property.rooms) r.id: r};
    final weeks = <_Week>[];
    while (monday.isBefore(next)) {
      final sunday = _addDays(monday, 7);
      // Only this month's days: a stay going on continues in the next month.
      final from = monday.isBefore(first) ? first : monday;
      final to = sunday.isAfter(next) ? next : sunday;
      final pieces = <_Piece>[];
      for (final b in widget.property.bars) {
        final room = rooms[b.roomId];
        if (room == null) continue;
        final end = b.end ?? DateTime.utc(9999);
        if (!b.start.isBefore(to) || !end.isAfter(from)) continue;
        final s = b.start.isBefore(from) ? from : b.start;
        final e = end.isAfter(to) ? to : end;
        double day(DateTime t) => t.difference(monday).inMinutes / 1440;
        pieces.add(
          _Piece(
            b,
            room,
            day(s),
            day(e),
            !b.start.isBefore(from),
            !end.isAfter(to),
          ),
        );
      }
      pieces.sort(
        (a, b) => a.from.compareTo(b.from) != 0
            ? a.from.compareTo(b.from)
            : a.room.number.compareTo(b.room.number),
      );
      // Names first (2026-10-04, Tom): a pill too narrow for "101 · Name"
      // gets a tag with the name right after it (or before it at the end of
      // the week). Never cut: inside the pill the name may shrink a little.
      final weekW = 7 * cellW;
      for (final p in pieces) {
        final left = p.from * cellW, right = p.to * cellW, w = right - left;
        final textW = measure(p);
        // Inside the pill when it fits, shrunk to 3/4 at most; else a tag.
        // Room · name, then the status circle (8 px and a 4 px gap).
        if (w >= textW * 0.75 + 12 + 12) continue;
        final tagW = math.min(textW + 14 + 12, weekW);
        p.tagW = tagW;
        if (right + 3 + tagW <= weekW) {
          p.tagLeft = right + 3;
        } else if (left - 3 - tagW >= 0) {
          p.tagLeft = left - 3 - tagW;
        } else {
          p.tagLeft = weekW - tagW;
        }
      }
      double lo(_Piece p) =>
          p.tagLeft == null ? p.from : math.min(p.from, p.tagLeft! / cellW);
      double hi(_Piece p) => p.tagLeft == null
          ? p.to
          : math.max(p.to, (p.tagLeft! + p.tagW!) / cellW);
      pieces.sort(
        (a, b) => lo(a).compareTo(lo(b)) != 0
            ? lo(a).compareTo(lo(b))
            : a.room.number.compareTo(b.room.number),
      );
      final ends = <double>[];
      final gap = 3 / cellW;
      for (final p in pieces) {
        var lane = ends.indexWhere((e) => e <= lo(p) + 0.01);
        if (lane < 0) {
          lane = ends.length;
          ends.add(hi(p) + gap);
        } else {
          ends[lane] = hi(p) + gap;
        }
        p.lane = lane;
      }
      weeks.add(_Week(monday, pieces, ends.length));
      monday = sunday;
    }
    return weeks;
  }

  double _weekH(_Week w, bool wide) =>
      math.max(wide ? 104.0 : 76.0, _numberH + w.lanes * _laneH + 12);

  void _after(List<double> tops) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      double? target;
      if (_token != widget.focusToken) {
        _token = widget.focusToken;
        final i = widget.months.indexWhere(
          (m) => m.year == widget.focus.year && m.month == widget.focus.month,
        );
        if (i >= 0) target = tops[i];
      } else if (_anchor != null) {
        // Keep the same place on screen after new data or a moved window.
        final i = widget.months.indexOf(_anchor!);
        if (i >= 0) target = tops[i] + _anchorDelta;
      }
      if (target != null) {
        final t = target.clamp(0.0, _scroll.position.maxScrollExtent);
        if ((t - _scroll.offset).abs() > 0.5) {
          _jumping = true;
          _scroll.jumpTo(t);
          _jumping = false;
        }
      }
      _onScroll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final vi = AppTranslations.of(context).locale.languageCode == 'vi';
    final weekdays = vi
        ? const ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
        : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const en = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 700;
        final pad = wide ? 16.0 : 6.0;
        final cellW = (box.maxWidth - 2 * pad) / 7;
        final scaler = MediaQuery.textScalerOf(context);
        double measure(_Piece p) {
          final tp = TextPainter(
            text: TextSpan(text: _label(context, p), style: _labelStyle),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w;
        }

        // Headings (widgets) and weeks (built once the labels are known).
        final parts = <Object>[];
        final tops = <double>[];
        var y = 0.0;
        for (final m in widget.months) {
          tops.add(y);
          final weeks = _weeks(m, cellW, measure);
          parts.add(
            SizedBox(
              height: _headH,
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    vi
                        ? 'Tháng ${m.month}, ${m.year}'
                        : '${en[m.month - 1]} ${m.year}',
                    key: ValueKey('calendar-month-head-${calYmd(m)}'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          );
          y += _headH;
          for (final w in weeks) {
            final h = _weekH(w, wide);
            parts.add((m, w, h));
            y += h;
          }
        }
        final sections = [
          for (final x in parts)
            if (x is Widget)
              x
            else if (x case (DateTime m, _Week w, double h))
              _week(context, m, w, cellW, h),
        ];
        _tops = tops;
        _after(tops);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The weekdays stay at the top while the months scroll.
            Container(
              padding: EdgeInsets.symmetric(horizontal: pad),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: scheme.outlineVariant),
                ),
              ),
              height: 28,
              child: Row(
                children: [
                  for (final d in weekdays)
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: NotificationListener<ScrollEndNotification>(
                onNotification: (n) {
                  final p = _scroll.position;
                  if (p.pixels < 120) {
                    widget.onEdge(-1);
                  } else if (p.pixels > p.maxScrollExtent - 120) {
                    widget.onEdge(1);
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  key: const ValueKey('calendar-month-scroll'),
                  controller: _scroll,
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [...sections, const SizedBox(height: 24)],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _week(
    BuildContext context,
    DateTime month,
    _Week w,
    double cellW,
    double h,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = widget.property.today;
    final next = DateTime.utc(month.year, month.month + 1);
    final cells = <Widget>[];
    // Days to come: white on the light grey page (dark mode: a lifted
    // surface). Past days: a clearly darker grey (2026-10-04, Tom: "keep the
    // grey but make it stronger").
    final dark = theme.brightness == Brightness.dark;
    final cellColor = dark ? scheme.surfaceContainerHigh : scheme.surface;
    final pastColor = dark
        ? scheme.surfaceContainerLowest
        : const Color(0xFFDDE1DD);
    for (var i = 0; i < 7; i++) {
      final day = _addDays(w.monday, i);
      final inMonth = !day.isBefore(month) && day.isBefore(next);
      final isToday =
          today != null &&
          day.year == today.year &&
          day.month == today.month &&
          day.day == today.day;
      final past =
          today != null &&
          day.isBefore(DateTime.utc(today.year, today.month, today.day));
      cells.add(
        Positioned(
          left: i * cellW,
          width: cellW,
          top: 0,
          height: h,
          child: !inMonth
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.all(2.5),
                  // Clearly apart from the background: an outline, and a
                  // soft shadow on the days to come.
                  child: Material(
                    color: past ? pastColor : cellColor,
                    elevation: past ? 0 : 1,
                    shadowColor: const Color(0x33000000),
                    surfaceTintColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: InkWell(
                      key: ValueKey('calendar-month-day-${calYmd(day)}'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => widget.onDay(day),
                      child: Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 5, 4, 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: isToday
                                ? BoxDecoration(
                                    color: scheme.error,
                                    borderRadius: BorderRadius.circular(10),
                                  )
                                : null,
                            child: Text(
                              '${day.day}',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: isToday
                                    ? scheme.onError
                                    : (past
                                          ? scheme.onSurfaceVariant
                                          : scheme.onSurface),
                                fontWeight: isToday
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      );
    }
    for (final p in w.pieces) {
      final left = p.from * cellW + (p.startsHere ? 0 : 2.5);
      final right = p.to * cellW - (p.endsHere ? 0 : 2.5);
      if (right - left < 4) continue;
      cells.add(
        Positioned(
          left: left,
          width: right - left,
          top: _numberH + p.lane * _laneH,
          height: _laneH - 3,
          child: _pill(context, p, w.monday),
        ),
      );
    }
    for (final p in w.pieces) {
      if (p.tagLeft == null) continue;
      cells.add(
        Positioned(
          left: p.tagLeft,
          width: p.tagW,
          top: _numberH + p.lane * _laneH,
          height: _laneH - 3,
          child: _pill(context, p, w.monday, tag: true),
        ),
      );
    }
    return SizedBox(
      height: h,
      child: Stack(clipBehavior: Clip.none, children: cells),
    );
  }

  Widget _pill(
    BuildContext context,
    _Piece p,
    DateTime monday, {
    bool tag = false,
  }) {
    final theme = Theme.of(context);
    final b = p.bar;
    final color = calKindColor(context, b);
    final ink = theme.brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF16202C);
    final name = _name(context, b);
    String two(int v) => v.toString().padLeft(2, '0');
    String stamp(DateTime d) =>
        '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
    final info = b.type == 'cleaning'
        ? calCleaningInfo(context, b, p.room.number)
        : [
            calText(context, 'room').replaceAll('{n}', p.room.number),
            name,
            '${stamp(b.start)} – ${b.end == null ? calText(context, 'openEnded') : stamp(b.end!)}',
            calText(context, calStayStatus(b)),
          ].join('\n');
    // The paid part like the day view (2026-10-05, Tom): solid from the
    // pill's left end up to where the stay is paid, lighter after that.
    double paidStop() {
      final w = p.to - p.from;
      if (w <= 0 || b.anonymous) return 0;
      if ((b.type == 'booking' || b.type == 'cleaning') && b.pay == 'paid') {
        return 1;
      }
      final until = b.paidUntil;
      if (until == null) return 0;
      final at = until.difference(monday).inMinutes / 1440;
      return ((at - p.from) / w).clamp(0.0, 1.0).toDouble();
    }

    final stop = tag ? 0.0 : paidStop();
    final surface = theme.colorScheme.surface;
    final solid = Color.alphaBlend(
          color.withValues(alpha: calPaidAlpha),
          surface,
        ),
        tint = Color.alphaBlend(color.withValues(alpha: calDueAlpha), surface);
    final radius = tag
        ? BorderRadius.circular(11)
        : BorderRadius.horizontal(
            left: Radius.circular(p.startsHere ? 11 : 0),
            right: Radius.circular(p.endsHere ? 11 : 0),
          );
    return Semantics(
      button: true,
      label: info.replaceAll('\n', ', '),
      excludeSemantics: true,
      child: CalHoverInfo(
        message: info,
        child: Material(
          key: ValueKey(
            'calendar-month-${tag ? 'tag' : 'bar'}-${b.id}-${calYmd(monday)}',
          ),
          color: surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: color.withValues(alpha: 0.9)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            key: tag
                ? null
                : ValueKey('calendar-month-fill-${b.id}-${calYmd(monday)}'),
            decoration: tag
                ? null
                : BoxDecoration(
                    gradient: LinearGradient(
                      colors: [solid, solid, tint, tint],
                      stops: [0, stop, stop, 1],
                    ),
                  ),
            child: InkWell(
              // A stay this person may not open says so (same as the timeline).
              onTap: () => widget.onOpen(p.room, b),
              child: LayoutBuilder(
                builder: (context, box) {
                  // The tag: the whole name, made smaller if needed, never cut.
                  // Room · name and the stay's status right next to it
                  // (2026-10-04, Tom): the name made smaller if needed, never cut.
                  // No box behind the text (2026-10-05, Tom): the paid part
                  // shows right through.
                  Widget label() => Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              '${p.room.number} · $name',
                              maxLines: 1,
                              softWrap: false,
                              style: _labelStyle.copyWith(color: ink),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          key: ValueKey(
                            'calendar-month-status-${b.id}-${calYmd(monday)}',
                          ),
                          width: 8,
                          height: 8,
                          decoration: calStatusDecoration(calStayStatus(b)),
                        ),
                      ],
                    ),
                  );
                  if (tag) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: label(),
                    );
                  }
                  // The name is in a tag beside a pill too narrow for it.
                  if (p.tagLeft != null || box.maxWidth < 34) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: label(),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
