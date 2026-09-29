import 'package:flutter/material.dart';
import '../../utils/localizations/app_localizations.dart';

int? scheduleMinute(String text, {bool closing = false}) {
  if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(text.trim())) return null;
  final parts = text.trim().split(':').map(int.parse).toList();
  if (parts[1] >= 60 ||
      parts[0] > 24 ||
      parts[0] == 24 && (!closing || parts[1] != 0)) {
    return null;
  }
  return parts[0] * 60 + parts[1];
}

String scheduleTime(int value) =>
    '${(value ~/ 60).toString().padLeft(2, '0')}:${(value % 60).toString().padLeft(2, '0')}';

class ScheduleWindow {
  final key = UniqueKey();
  String start, end;
  ScheduleWindow(this.start, this.end);
  Map<String, int>? toMap() {
    final a = scheduleMinute(start), b = scheduleMinute(end, closing: true);
    return a == null || b == null || a == b ? null : {'start': a, 'end': b};
  }
}

class ScheduleException {
  final key = UniqueKey();
  String date;
  final List<ScheduleWindow> windows;
  ScheduleException(this.date, this.windows);
}

class ScheduleDraft {
  final List<List<ScheduleWindow>> week;
  final List<ScheduleException> exceptions;
  ScheduleDraft(this.week, this.exceptions);
  factory ScheduleDraft.daily(int? start, int? end) => ScheduleDraft(
    List.generate(
      7,
      (_) => [
        ScheduleWindow(scheduleTime(start ?? 0), scheduleTime(end ?? 1440)),
      ],
    ),
    [],
  );
  factory ScheduleDraft.fromMap(Map raw) {
    List<ScheduleWindow> rows(List values) => values
        .map(
          (w) => ScheduleWindow(
            scheduleTime(w['start'] as int),
            scheduleTime(w['end'] as int),
          ),
        )
        .toList();
    return ScheduleDraft(
      List.generate(7, (i) => rows(raw['week']['$i'] as List)),
      (raw['exceptions'] as Map).entries
          .map((e) => ScheduleException(e.key as String, rows(e.value as List)))
          .toList(),
    );
  }
  Map<String, dynamic>? toMap() {
    if (week.length != 7 || exceptions.length > 60) return null;
    List<Map<String, int>>? encode(List<ScheduleWindow> rows) {
      if (rows.length > 6 || rows.any((r) => r.toMap() == null)) return null;
      return rows.map((r) => r.toMap()!).toList();
    }

    final weeks = week.map(encode).toList();
    if (weeks.any((v) => v == null)) return null;
    final dates = <String, List<Map<String, int>>>{};
    for (final e in exceptions) {
      final day = DateTime.tryParse('${e.date}T00:00:00Z');
      final rows = encode(e.windows);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(e.date) ||
          day == null ||
          day.year < 2000 ||
          day.year > 2199 ||
          day.toIso8601String().substring(0, 10) != e.date ||
          dates.containsKey(e.date) ||
          rows == null) {
        return null;
      }
      dates[e.date] = rows;
    }
    bool clear(List<Map<String, int>> own, List<Map<String, int>> previous) {
      final ranges = [
        for (final w in own)
          [w['start']!, w['end']! < w['start']! ? 1440 : w['end']!],
        for (final w in previous)
          if (w['end']! < w['start']! && w['end']! > 0) [0, w['end']!],
      ];
      ranges.sort((a, b) => a[0].compareTo(b[0]));
      for (var i = 1; i < ranges.length; i++) {
        if (ranges[i][0] < ranges[i - 1][1]) return false;
      }
      return true;
    }

    for (var i = 0; i < 7; i++) {
      if (!clear(weeks[i]!, weeks[(i + 6) % 7]!)) return null;
    }
    String key(DateTime d) => d.toIso8601String().substring(0, 10);
    List<Map<String, int>> on(DateTime d) =>
        dates[key(d)] ?? weeks[d.weekday - 1]!;
    for (final date in dates.keys) {
      final d = DateTime.parse('${date}T00:00:00Z');
      for (final day in [d, d.add(const Duration(days: 1))]) {
        if (!clear(
          on(day),
          dates.containsKey(key(day))
              ? []
              : on(day.subtract(const Duration(days: 1))),
        )) {
          return null;
        }
      }
    }
    return {
      'week': {for (var i = 0; i < 7; i++) '$i': weeks[i]},
      'exceptions': dates,
    };
  }
}

class OperatingScheduleEditor extends StatefulWidget {
  final ScheduleDraft draft;
  final bool enabled;
  const OperatingScheduleEditor({
    super.key,
    required this.draft,
    required this.enabled,
  });
  @override
  State<OperatingScheduleEditor> createState() =>
      _OperatingScheduleEditorState();
}

class _OperatingScheduleEditorState extends State<OperatingScheduleEditor> {
  int _day = 0;
  ScheduleException? _exception;
  final _heading = GlobalKey();
  void _showEditor() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _heading.currentContext != null) {
        Scrollable.ensureVisible(
          _heading.currentContext!,
          duration: const Duration(milliseconds: 150),
        );
      }
    });
  }

  @override
  void didUpdateWidget(covariant OperatingScheduleEditor old) {
    super.didUpdateWidget(old);
    if (old.draft != widget.draft) {
      _day = 0;
      _exception = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTranslations.of(context), draft = widget.draft;
    final rows = _exception?.windows ?? draft.week[_day];
    final selected = _exception == null
        ? t['schedule_day_$_day']
        : '${t['schedule_exception']}: ${_exception!.date}';
    void change(VoidCallback action) => setState(action);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t['schedule_help']),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          key: ValueKey('schedule-weekday-$_day'),
          initialValue: _day,
          isExpanded: true,
          decoration: InputDecoration(labelText: t['schedule_weekday']),
          items: List.generate(
            7,
            (i) =>
                DropdownMenuItem(value: i, child: Text(t['schedule_day_$i'])),
          ),
          onChanged: widget.enabled
              ? (v) => change(() {
                  _day = v!;
                  _exception = null;
                })
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          selected,
          key: _heading,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (_exception != null) ...[
          OutlinedButton(
            onPressed: widget.enabled
                ? () => change(() => _exception = null)
                : null,
            child: Text(t['schedule_back_week']),
          ),
          TextFormField(
            key: ValueKey('schedule-date-${_exception!.key}'),
            initialValue: _exception!.date,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: t['schedule_date'],
              helperText: 'YYYY-MM-DD',
              errorMaxLines: 4,
            ),
            onChanged: (v) => change(() => _exception!.date = v.trim()),
          ),
          const SizedBox(height: 8),
        ],
        if (rows.isEmpty)
          Text(
            t[_exception == null ? 'schedule_no_starts' : 'schedule_closed'],
          ),
        for (var i = 0; i < rows.length; i++)
          Padding(
            key: rows[i].key,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${t['schedule_window']} ${i + 1}'),
                TextFormField(
                  key: ValueKey('schedule-open-$i'),
                  initialValue: rows[i].start,
                  enabled: widget.enabled,
                  decoration: InputDecoration(
                    labelText: t['settings_open'],
                    errorMaxLines: 4,
                  ),
                  onChanged: (v) => change(() => rows[i].start = v),
                  validator: (v) => scheduleMinute(v ?? '') == null
                      ? t['settings_time_invalid']
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: ValueKey('schedule-close-$i'),
                  initialValue: rows[i].end,
                  enabled: widget.enabled,
                  decoration: InputDecoration(
                    labelText: t['settings_close'],
                    errorMaxLines: 4,
                  ),
                  onChanged: (v) => change(() => rows[i].end = v),
                  validator: (v) =>
                      scheduleMinute(v ?? '', closing: true) == null ||
                          scheduleMinute(v ?? '', closing: true) ==
                              scheduleMinute(rows[i].start)
                      ? t['settings_time_invalid']
                      : null,
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: widget.enabled
                        ? () => change(() => rows.removeAt(i))
                        : null,
                    child: Text('${t['schedule_remove_window']} ${i + 1}'),
                  ),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const ValueKey('schedule-add-window'),
              onPressed: widget.enabled && rows.length < 6
                  ? () =>
                        change(() => rows.add(ScheduleWindow('09:00', '17:00')))
                  : null,
              child: Text(t['schedule_add_window']),
            ),
            OutlinedButton(
              onPressed: widget.enabled ? () => change(rows.clear) : null,
              child: Text(
                t[_exception == null
                    ? 'schedule_clear_windows'
                    : 'schedule_close_day'],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          t['schedule_exceptions'],
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(t['schedule_exception_help']),
        if (draft.exceptions.isEmpty) Text(t['schedule_no_exceptions']),
        for (final e in draft.exceptions)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(e.date.isEmpty ? t['schedule_date'] : e.date),
                  Text(
                    e.windows.isEmpty
                        ? t['schedule_closed']
                        : e.windows
                              .map((w) => '${w.start}–${w.end}')
                              .join(', '),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: widget.enabled
                            ? () {
                                change(() => _exception = e);
                                _showEditor();
                              }
                            : null,
                        child: Text(t['schedule_edit_exception']),
                      ),
                      TextButton(
                        onPressed: widget.enabled
                            ? () => change(() {
                                draft.exceptions.remove(e);
                                if (_exception == e) _exception = null;
                              })
                            : null,
                        child: Text(t['schedule_remove_exception']),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton(
          key: const ValueKey('schedule-add-exception'),
          onPressed: widget.enabled && draft.exceptions.length < 60
              ? () {
                  change(() {
                    final e = ScheduleException('', []);
                    draft.exceptions.add(e);
                    _exception = e;
                  });
                  _showEditor();
                }
              : null,
          child: Text(t['schedule_add_exception']),
        ),
      ],
    );
  }
}
