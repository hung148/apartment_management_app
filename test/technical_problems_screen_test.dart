import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/technical_problems_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'account_entry_test.dart' as fixtures;

Map<String, dynamic> _problem({
  String id = 'p1',
  String status = 'open',
  bool blocks = false,
  String title = 'Máy lạnh chảy nước',
}) => {
  'id': id,
  'revision': '1:0',
  'roomId': 'r1',
  'roomNumber': '101',
  'title': title,
  'description': 'Nước nhỏ xuống giường',
  'status': status,
  'blocksRoom': blocks,
  'reportedByName': 'Chị Lan (dọn phòng)',
  'reportedLocalDate': '2026-11-18',
  'occupant': {'kind': 'lease', 'id': 't', 'name': 'Le Van Chinh'},
  'fixedByName': status == 'fixed' ? 'Thợ Hùng' : null,
  'fixedLocalDate': status == 'fixed' ? '2026-11-19' : null,
  'costMinor': status == 'fixed' ? 500000 : null,
  'currency': 'VND',
  'expenseId': status == 'fixed' ? 'e1' : null,
  'note': '',
  'photos': [],
};

Map<String, dynamic> _list({bool manager = true, List<Map<String, dynamic>>? records, String room = '101'}) => {
  'records': records ?? [_problem(), _problem(id: 'p2', status: 'fixed', title: 'Vòi nước rỉ')],
  'rooms': [
    {'id': 'r1', 'roomNumber': room, 'blocked': false},
    {'id': 'r2', 'roomNumber': '102', 'blocked': true},
  ],
  'accounts': manager ? [{'id': 'vcb', 'label': 'Vietcombank 0123'}] : [],
  'currency': 'VND',
  'today': '2026-11-20',
  'canReport': true,
  'canManage': manager,
  'canExpense': manager,
};

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> _enter(WidgetTester t, Finder f, String text) async {
  await t.ensureVisible(f);
  await t.enterText(f, text);
  await t.pump();
}

Widget _screen(TeamService s) => Scaffold(
  body: TechnicalProblemsScreen(organizationId: 'o', buildingId: 'b', service: s),
);

void main() {
  testWidgets('report a problem that stops renting the room; existing bookings are listed', (t) async {
    final sent = <Map<String, dynamic>>[];
    final service = TeamService(
      transport: (name, d) async {
        expect(name, 'technicalProblems');
        if (d['action'] == 'list') return _list();
        sent.add(Map<String, dynamic>.from(d));
        return {
          'problemId': 'p3',
          'warnings': [
            {'kind': 'booking', 'id': 'k', 'name': 'Nguyen Van An', 'status': 'confirmed', 'start': '2026-12-01', 'end': '2026-12-03'},
          ],
        };
      },
    );
    await fixtures.mount(t, _screen(service));
    await t.pumpAndSettle();
    // Open problems first; the fixed one is behind its filter.
    expect(find.text('101 · Máy lạnh chảy nước'), findsOneWidget);
    expect(find.text('101 · Vòi nước rỉ'), findsNothing);
    await _tap(t, find.byKey(const ValueKey('problem-filter-all')));
    expect(find.text('101 · Vòi nước rỉ'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('problems-report')));
    expect(find.textContaining('Not rented now (open problem): 102'), findsOneWidget);
    // Nothing chosen yet: refused before anything is sent.
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(find.text('Choose the room.'), findsOneWidget);
    expect(sent, isEmpty);
    await _tap(t, find.byKey(const ValueKey('problem-room-r1')));
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(find.text('Enter what is broken.'), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('problem-title')), 'Mất điện ổ cắm');
    await _enter(t, find.byKey(const ValueKey('problem-description')), 'Ổ cắm cạnh giường');
    await _tap(t, find.byKey(const ValueKey('problem-block')));
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(sent.single['action'], 'report');
    expect(sent.single['roomId'], 'r1');
    expect(sent.single['title'], 'Mất điện ổ cắm');
    expect(sent.single['description'], 'Ổ cắm cạnh giường');
    expect(sent.single['blocksRoom'], true);
    expect(find.byKey(const ValueKey('problem-done')), findsOneWidget);
    expect(find.textContaining('Booking Nguyen Van An: 2026-12-01 – 2026-12-03'), findsOneWidget);
  });

  testWidgets('mark fixed with a paid expense by bank; refusals are explained; exact retry', (t) async {
    final sent = <Map<String, dynamic>>[];
    var step = 0;
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'list') return _list();
        sent.add(Map<String, dynamic>.from(d));
        step++;
        if (step == 1) throw FirebaseFunctionsException(code: 'invalid-argument', message: 'problem_fixed_before_report');
        if (step == 2) throw FirebaseFunctionsException(code: 'unavailable', message: 'offline');
        return {'problemId': 'p1', 'expenseId': 'e9', 'warnings': []};
      },
    );
    await fixtures.mount(t, _screen(service));
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('problem-p1')));
    expect(find.text('Le Van Chinh'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('problem-fix')));
    expect(find.widgetWithText(TextFormField, '2026-11-20'), findsOneWidget, reason: 'today is filled in');
    await _enter(t, find.byKey(const ValueKey('problem-fixed-by')), 'Thợ Hùng');
    await _enter(t, find.byKey(const ValueKey('problem-cost')), '500.000');
    await _tap(t, find.byKey(const ValueKey('problem-expense')));
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(find.text('Choose how the cost was paid.'), findsOneWidget);
    expect(sent, isEmpty);
    await _tap(t, find.byKey(const ValueKey('problem-method-bank')));
    await _tap(t, find.byKey(const ValueKey('problem-account-vcb')));
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(find.text('The fix date cannot be before the day it was reported.'), findsOneWidget);
    expect(sent.last['costMinor'], 500000);
    expect(sent.last['recordExpense'], true);
    expect(sent.last['paymentMethod'], 'bankTransfer');
    expect(sent.last['accountId'], 'vcb');
    expect(sent.last['revision'], '1:0');
    // A lost reply keeps the request; the retry repeats it exactly.
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(find.textContaining('Save was not confirmed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(sent[2], sent[1]);
    expect(find.text('Saved. The cost is recorded in Thu chi.'), findsOneWidget);
  });

  testWidgets('staff who are not managers can report but not block, edit or fix', (t) async {
    final service = TeamService(transport: (name, d) async => _list(manager: false));
    await fixtures.mount(t, _screen(service), locale: 'vi');
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('problem-p1')));
    expect(find.byKey(const ValueKey('problem-fix')), findsNothing);
    expect(find.byKey(const ValueKey('problem-edit')), findsNothing);
    await _tap(t, find.text('Sự cố kỹ thuật').first);
    await _tap(t, find.byKey(const ValueKey('problems-report')));
    expect(find.byKey(const ValueKey('problem-block')), findsNothing);
  });

  testWidgets('a fixed problem can be reopened with a reason', (t) async {
    final sent = <Map<String, dynamic>>[];
    final service = TeamService(
      transport: (name, d) async {
        if (d['action'] == 'list') return _list(records: [_problem(status: 'fixed', blocks: true)]);
        sent.add(Map<String, dynamic>.from(d));
        return {'problemId': 'p1', 'warnings': []};
      },
    );
    await fixtures.mount(t, _screen(service));
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('problem-filter-fixed')));
    await _tap(t, find.byKey(const ValueKey('problem-p1')));
    expect(find.text('Recorded as a paid expense'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('problem-reopen')));
    expect(find.textContaining('stops taking new bookings'), findsOneWidget);
    expect(find.textContaining('stays in Thu chi'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(find.text('Write why it is reopened.'), findsOneWidget);
    await _enter(t, find.byKey(const ValueKey('problem-note')), 'Lại chảy nước');
    await _tap(t, find.byKey(const ValueKey('problem-save')));
    expect(sent.single['action'], 'reopen');
    expect(sent.single['note'], 'Lại chảy nước');
  });

  for (final locale in ['en', 'vi']) {
    for (final size in [const Size(360, 800), const Size(800, 360), const Size(1440, 900)]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('problem layouts $locale ${size.width} $scale', (t) async {
          final long = 'Máy lạnh phòng ngủ chảy nước xuống giường, cần thợ điện lạnh đến kiểm tra gấp';
          final service = TeamService(
            transport: (name, d) async => _list(
              records: [_problem(title: long, blocks: true)],
              room: 'Căn hộ 1201 hướng biển',
            ),
          );
          await fixtures.mount(t, _screen(service), locale: locale, size: size, scale: scale);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'list');
          await _tap(t, find.byKey(const ValueKey('problem-p1')));
          final fix = find.byKey(const ValueKey('problem-fix'));
          await t.ensureVisible(fix);
          await t.pumpAndSettle();
          expect(fix.hitTestable(), findsOneWidget);
          await _tap(t, fix);
          await _tap(t, find.byKey(const ValueKey('problem-expense')));
          await _tap(t, find.byKey(const ValueKey('problem-method-bank')));
          final save = find.byKey(const ValueKey('problem-save'));
          await t.ensureVisible(save);
          await t.pumpAndSettle();
          expect(save.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull, reason: 'fix form');
        });
      }
    }
  }
}
