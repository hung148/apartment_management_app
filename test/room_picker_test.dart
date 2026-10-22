import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/calendar/room_calendar.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_picker.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/workspace_page_scope.dart';
import 'team_review_test.dart' show mountReview;

// The room box and list used by the booking, lease and room-move forms
// (2026-10-22, Tom).
void main() {
  test('rooms sort by number, not by text', () {
    final labels = ['QA103', 'qa101', 'QA102', '10', '9', 'B2', 'A10', 'A9']
      ..sort(compareRoomLabels);
    expect(labels, ['9', '10', 'A9', 'A10', 'B2', 'qa101', 'QA102', 'QA103']);
  });

  testWidgets('the box shows one room; the list is sorted, marks it and picks', (
    tester,
  ) async {
    String? picked;
    await mountReview(
      tester,
      Builder(
        builder: (context) => Center(
          child: RoomPickerField(
            fieldKey: 'room',
            value: 'QA102',
            onPick: () async {
              picked = await showRoomPicker(
                context,
                keyPrefix: 'room',
                selectedId: 'b',
                rooms: const [
                  RoomChoice('c', 'QA103'),
                  RoomChoice('a', 'QA101'),
                  RoomChoice('b', 'QA102'),
                  RoomChoice('d', 'QA104', enabled: false, note: 'Busy'),
                ],
              );
            },
          ),
        ),
      ),
    );
    // Only the chosen room is in the form; the box fits it.
    expect(find.text('QA101'), findsNothing);
    expect(tester.getSize(find.byKey(const ValueKey('room'))).width, lessThan(240));
    await tester.tap(find.byKey(const ValueKey('room')));
    await tester.pumpAndSettle();
    final ys = [
      for (final id in ['a', 'b', 'c', 'd'])
        tester.getTopLeft(find.byKey(ValueKey('room-$id'))).dy,
    ];
    expect(ys, [...ys]..sort());
    expect(find.text('Busy'), findsOneWidget);
    // A room that cannot be chosen does nothing.
    await tester.tap(find.byKey(const ValueKey('room-d')));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    await tester.tap(find.byKey(const ValueKey('room-a')));
    await tester.pumpAndSettle();
    expect(picked, 'a');
    expect(find.byKey(const ValueKey('room:dialog')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a calendar page titled by room follows the room picked in it', (
    tester,
  ) async {
    await mountReview(
      tester,
      CalendarPageDialog(
        title: 'Room QA102 · Short stay',
        roomTitle: (n) => 'Room $n · Short stay',
        build: (_) => Builder(
          builder: (context) => TextButton(
            onPressed: () => RoomTitleScope.report(context, 'QA101'),
            child: const Text('pick'),
          ),
        ),
      ),
    );
    expect(find.text('Room QA102 · Short stay'), findsOneWidget);
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    expect(find.text('Room QA101 · Short stay'), findsOneWidget);
    expect(find.text('Room QA102 · Short stay'), findsNothing);
  });

  testWidgets('crossing the phone / desktop width keeps what was typed', (
    tester,
  ) async {
    late StateSetter rebuild;
    var page = 0;
    await mountReview(
      tester,
      CalendarPageDialog(
        title: 'Room QA102 · Short stay',
        // A page that keeps its own state, like the booking form.
        build: (_) => StatefulBuilder(
          builder: (context, set) {
            rebuild = set;
            return Column(
              children: [
                TextField(key: const ValueKey('guest')),
                Text('page $page'),
              ],
            );
          },
        ),
      ),
      size: const Size(1200, 900),
    );
    await tester.enterText(find.byKey(const ValueKey('guest')), 'Nguyễn Văn An');
    rebuild(() => page = 1);
    await tester.pump();
    for (final size in [const Size(390, 844), const Size(1200, 900)]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(find.text('Nguyễn Văn An'), findsOneWidget);
      expect(find.text('page 1'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
