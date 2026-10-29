// Preview (widget tests): a small copy of functions/lease_schedule.js for the
// lease page's payment table (PAYMENT_SCHEDULE.md, 2026-10-26). Same answers
// and refusal keys for the usual cases; whole months only for the default
// amount (the server prorates exactly).
import 'package:cloud_functions/cloud_functions.dart';

String _addDays(String date, int n) => DateTime.parse(
  '${date}T00:00:00Z',
).add(Duration(days: n)).toIso8601String().substring(0, 10);

int _daysBetween(String a, String b) => DateTime.parse(
  '${b}T00:00:00Z',
).difference(DateTime.parse('${a}T00:00:00Z')).inDays;

String _addMonths(String date, int months) {
  final p = date.split('-').map(int.parse).toList();
  final first = DateTime.utc(p[0], p[1] - 1 + months + 1, 1);
  final last = DateTime.utc(first.year, first.month + 1, 0).day;
  final day = p[2] < last ? p[2] : last;
  return DateTime.utc(
    first.year,
    first.month,
    day,
  ).toIso8601String().substring(0, 10);
}

Never _no(String key) =>
    throw FirebaseFunctionsException(code: 'failed-precondition', message: key);

/// [lease]: the preview tenant row (its `paymentSchedule` and
/// `scheduleRevision` are kept on it). [invoices]: kỳ id → invoice id.
Map<String, dynamic> previewSchedule(
  Map<String, dynamic> lease,
  Map<String, dynamic> d, {
  required bool canPrice,
  required bool canEdit,
  Map<String, String> invoices = const {},
}) {
  final start = lease['moveInLocalDate'] as String?;
  final contractEnd = lease['contractEndLocalDate'] as String?;
  final months = (lease['paymentPeriodMonths'] as int?) ?? 1;
  final rent = (lease['monthlyRentMinor'] as int?) ?? 0;
  final recurring = [
    for (final s in (lease['surcharges'] as List? ?? const []))
      if ((s as Map)['frequency'] == 'period') s['amountMinor'] as int,
  ].fold(0, (a, b) => a + b);
  final revision = '${lease['scheduleRevision'] ?? 0}:0';

  List<Map<String, dynamic>> build(List stored) {
    // The contract end date is the day the tenant leaves (2026-10-26).
    final end = contractEnd!;
    final rows = <Map<String, dynamic>>[];
    var cursor = start!;
    for (final raw in stored) {
      final s = Map<String, dynamic>.from(raw as Map);
      if (invoices.containsKey(s['id'])) {
        rows.add({...s, 'locked': true});
        cursor = s['end'] as String;
        continue;
      }
      if (cursor.compareTo(end) >= 0) continue;
      final from = rows.isEmpty && s['startEdited'] == true
          ? s['start'] as String
          : cursor;
      var to = s['datesEdited'] == true
          ? _addDays(from, s['days'] as int)
          : _addMonths(from, months);
      final overflow = to.compareTo(end) > 0;
      if (overflow) to = end;
      rows.add({
        ...s,
        'start': from,
        'end': to,
        'locked': false,
        'overflow': overflow && s['datesEdited'] == true,
      });
      cursor = to;
    }
    while (cursor.compareTo(end) < 0 && rows.length < 240) {
      final next = _addMonths(cursor, months);
      final to = next.compareTo(end) < 0 ? next : end;
      final id = 'k${cursor.replaceAll('-', '')}';
      rows.add({
        'id': id,
        'start': cursor,
        'end': to,
        'locked': invoices.containsKey(id),
      });
      cursor = to;
    }
    for (final r in rows) {
      int? whole;
      for (var k = 1; k <= 24; k++) {
        final e = _addMonths(r['start'] as String, k);
        if (e == r['end']) whole = k;
        if (e.compareTo(r['end'] as String) >= 0) break;
      }
      final days = _daysBetween(r['start'] as String, r['end'] as String);
      final def =
          (whole != null ? rent * whole : (rent * days / 30).round()) +
          recurring;
      r['wholeMonths'] = whole;
      r['days'] = days;
      r['defaultMinor'] = def;
      if (r['amountEdited'] != true) r['amountMinor'] = def;
      r['due'] = r['dueEdited'] == true
          ? _addDays(r['start'] as String, r['dueOffset'] as int)
          : r['start'];
      r['paidMinor'] = 0;
      r['leftMinor'] = r['amountMinor'];
      r['invoiceId'] = invoices[r['id']];
      r['datesEdited'] = r['datesEdited'] == true;
      r['dueEdited'] = r['dueEdited'] == true;
      r['amountEdited'] = r['amountEdited'] == true;
    }
    return rows;
  }

  Map<String, dynamic> read() {
    if (start == null || contractEnd == null) {
      return {
        'record': {
          'revision': revision,
          'currency': lease['currency'] ?? 'VND',
          'needsEnd': true,
          'canEdit': canEdit,
          'canPrice': canPrice,
          'canBill': true,
          'rows': const [],
        },
      };
    }
    return {
      'record': {
        'revision': revision,
        'currency': lease['currency'] ?? 'VND',
        'needsEnd': false,
        'canEdit': canEdit,
        'canPrice': canPrice,
        'canBill': true,
        'rows': build(lease['paymentSchedule'] as List? ?? const []),
      },
    };
  }

  if (d['op'] == 'read') return read();
  if (d['revision'] != revision) _no('schedule_changed');
  if (start == null || contractEnd == null) _no('schedule_needs_end');
  final rows = build(lease['paymentSchedule'] as List? ?? const []);
  final i = rows.indexWhere((r) => r['id'] == d['rowId']);
  if (i < 0) _no('schedule_row_not_found');
  final r = rows[i];
  if (r['locked'] == true) _no('schedule_row_locked');
  final copy = [for (final x in rows) Map<String, dynamic>.from(x)];
  final row = copy[i];
  switch (d['op']) {
    case 'edit':
      if (d['start'] != null) {
        final s = d['start'] as String;
        if (s.compareTo(r['end'] as String) >= 0) _no('schedule_invalid_dates');
        if (i == 0) {
          if (s.compareTo(start) < 0) _no('schedule_before_move_in');
          row['start'] = s;
          row['startEdited'] = s != start;
        } else {
          final prev = copy[i - 1];
          if (prev['locked'] == true) _no('schedule_row_locked');
          prev['datesEdited'] = true;
          prev['days'] = _daysBetween(prev['start'] as String, s);
        }
      }
      if (d['end'] != null) {
        final from = (d['start'] ?? r['start']) as String;
        if ((d['end'] as String).compareTo(from) <= 0) {
          _no('schedule_invalid_dates');
        }
        row['datesEdited'] = true;
        row['days'] = _daysBetween(from, d['end'] as String);
      }
      if (d['due'] != null) {
        final from = (d['start'] ?? r['start']) as String;
        final to = (d['end'] ?? r['end']) as String;
        final due = d['due'] as String;
        if (due.compareTo(from) < 0 || due.compareTo(to) >= 0) {
          _no('schedule_due_outside');
        }
        row['dueEdited'] = due != from;
        row['dueOffset'] = _daysBetween(from, due);
      }
      if (d['amountMinor'] != null) {
        final amount = d['amountMinor'] as int;
        if (amount == r['defaultMinor']) {
          row['amountEdited'] = false;
          row.remove('reason');
        } else {
          if (!canPrice) {
            throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'lease_price_authority',
            );
          }
          if (((d['reason'] as String?) ?? '').trim().isEmpty) {
            _no('schedule_reason_required');
          }
          row['amountEdited'] = true;
          row['amountMinor'] = amount;
          row['reason'] = (d['reason'] as String).trim();
        }
      }
    case 'split':
      final date = d['date'] as String;
      if (date.compareTo(r['start'] as String) <= 0 ||
          date.compareTo(r['end'] as String) >= 0) {
        _no('schedule_split_outside');
      }
      row['datesEdited'] = true;
      row['days'] = _daysBetween(r['start'] as String, date);
      copy.insert(i + 1, {
        'id': 'k${date.replaceAll('-', '')}',
        'start': date,
        'end': r['end'],
        'datesEdited': true,
        'days': _daysBetween(date, r['end'] as String),
      });
    case 'merge':
      if (copy.length < 2) _no('schedule_merge_only_one');
      final j = i == 0 ? 1 : i - 1;
      if (copy[j]['locked'] == true) _no('schedule_row_locked');
      final a = copy[i < j ? i : j], b = copy[i < j ? j : i];
      a['datesEdited'] = true;
      a['days'] = _daysBetween(a['start'] as String, b['end'] as String);
      copy.remove(b);
    default:
      _no('schedule_invalid_change');
  }
  final next = build(copy);
  if (next.any((x) => x['overflow'] == true)) _no('schedule_past_contract_end');
  lease['paymentSchedule'] = [
    for (final x in next)
      {
        'id': x['id'],
        'start': x['start'],
        'end': x['end'],
        if (x['startEdited'] == true) 'startEdited': true,
        if (x['datesEdited'] == true) ...{'datesEdited': true, 'days': x['days']},
        if (x['dueEdited'] == true) ...{
          'dueEdited': true,
          'dueOffset': x['dueOffset'],
        },
        if (x['amountEdited'] == true) ...{
          'amountEdited': true,
          'amountMinor': x['amountMinor'],
          'reason': x['reason'],
        },
      },
  ];
  lease['scheduleRevision'] = ((lease['scheduleRevision'] as int?) ?? 0) + 1;
  return {'ok': true};
}
