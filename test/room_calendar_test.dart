import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/services/app_functions.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/models/team_access.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_details_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_layout_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_directory.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/calendar/month_calendar.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/calendar/room_calendar.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/booking_workspace_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/technical_problems_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_contacts_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_lease_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/ws_ui.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';

import 'team_review_test.dart' show mountReview;

/// October 2026 at two properties: a long room name, an open-ended lease with
/// a roommate, an Airbnb stay partly paid, a deposit-only stay, two stays that
/// overlap (lanes), a short hourly stay this person may not open, a room
/// closed by a problem, a property with no rooms and one without a time zone.
Map<String, dynamic> calendarFixture(
  String from, {
  String? to,
  bool canLease = true,
  bool sandwich = false,
}) {
  // The calendar loads three months at a time: October's stays are there
  // whenever the window covers October.
  final october =
      from.compareTo('2026-10-01') <= 0 &&
      (to ?? '2026-11-01').compareTo('2026-10-01') > 0;
  Map<String, dynamic> room(
    String id,
    String number, {
    bool short = true,
    bool monthly = true,
    bool blocked = false,
    List<String> problems = const [],
  }) => {
    'id': id,
    'roomNumber': number,
    'shortStay': short,
    'monthly': monthly,
    'blocked': blocked,
    'problems': [
      for (final p in problems)
        {'id': 'p-$id', 'title': p, 'blocksRoom': blocked},
    ],
  };
  return {
    'from': from,
    'properties': [
      {
        'id': 'riverside',
        'name': 'Riverside — Khu căn hộ phía Đông',
        'timeZone': 'Asia/Ho_Chi_Minh',
        'today': '2026-10-02',
        'now': '2026-10-02 09:00',
        'canCreateBookings': true,
        'canLease': canLease,
        'canReadProblems': true,
        'canReportProblems': true,
        'rooms': [
          room('room-101', '101 — Phòng gia đình Riverside'),
          room('r102', '102'),
          room('r103', '103', blocked: true, problems: ['Vòi nước hỏng']),
          room('r104', '104'),
        ],
        'bars': [
          {
            'id': 'lease:tenant-anh',
            'type': 'lease',
            'roomId': 'room-101',
            'kind': 'long',
            'start': '2026-09-01 12:00',
            'end': null,
            'plannedEnd': '2027-08-31',
            'status': 'staying',
            'canOpen': true,
            'recordId': 'tenant-anh',
            'name': 'Nguyễn Thị Minh Anh — gia đình Riverside',
            'phone': true,
            'roommates': 1,
            'periodMonths': 1,
            'pay': 'paid',
            'paidUntil': '2026-10-15 00:00',
          },
          if (october) ...[
            {
              'id': 'booking:b1',
              'type': 'booking',
              'roomId': 'r102',
              'kind': 'short',
              'start': '2026-10-03 14:00',
              'end': '2026-10-06 11:30',
              'status': 'upcoming',
              'canOpen': true,
              'recordId': 'b1',
              'name': 'Trần Văn Bình',
              'platform': 'airbnb',
              'phone': true,
              'pay': 'due',
              'paidFraction': 0.33,
              'paidUntil': '2026-10-04 06:00',
            },
            {
              'id': 'booking:b2',
              'type': 'booking',
              'roomId': 'r102',
              'kind': 'deposit',
              'start': '2026-10-06 14:00',
              'end': '2026-10-08 12:00',
              'status': 'upcoming',
              'canOpen': true,
              'recordId': 'b2',
              'name': 'Lê Thị Cúc',
              'pay': 'deposit',
              'paidFraction': 0,
            },
            {
              'id': 'booking:b3',
              'type': 'booking',
              'roomId': 'r102',
              'kind': 'short',
              'start': '2026-10-07 14:00',
              'end': '2026-10-09 12:00',
              'status': 'upcoming',
              'canOpen': true,
              'recordId': 'b3',
              'name': 'Overlap Guest',
              'pay': 'paid',
              'paidFraction': 1,
            },
            {
              'id': 'booking:hidden',
              'type': 'booking',
              'roomId': 'r104',
              'kind': 'short',
              'start': '2026-10-02 09:00',
              'end': '2026-10-02 12:00',
              'status': 'out',
              'canOpen': false,
              'anonymous': true,
              'name': '',
            },
            {
              'id': 'booking:b4',
              'type': 'booking',
              'roomId': 'r104',
              'kind': 'short',
              'start': '2026-10-10 13:00',
              'end': '2026-10-10 16:00',
              'status': 'upcoming',
              'canOpen': true,
              'recordId': 'b4',
              'name': 'Hourly',
              'pay': 'paid',
              'paidFraction': 1,
            },
            // The hourly stay (13:00–16:00) with a stay ending at 12:00 and
            // one starting at 17:00: an hour free on each side, 18 px.
            if (sandwich) ...[
              {
                'id': 'booking:b5',
                'type': 'booking',
                'roomId': 'r104',
                'kind': 'short',
                'start': '2026-10-08 14:00',
                'end': '2026-10-10 12:00',
                'status': 'upcoming',
                'canOpen': true,
                'recordId': 'b5',
                'name': 'Before Guest',
                'pay': 'paid',
                'paidFraction': 1,
              },
              {
                'id': 'booking:b6',
                'type': 'booking',
                'roomId': 'r104',
                'kind': 'short',
                'start': '2026-10-10 17:00',
                'end': '2026-10-13 12:00',
                'status': 'upcoming',
                'canOpen': true,
                'recordId': 'b6',
                'name': 'After Guest',
                'pay': 'paid',
                'paidFraction': 1,
              },
            ],
          ],
        ],
      },
      {
        'id': 'garden',
        'name': 'Garden Homestay',
        'timeZone': 'Asia/Ho_Chi_Minh',
        'today': '2026-10-02',
        'canCreateBookings': true,
        'canLease': true,
        'canReadProblems': true,
        'canReportProblems': true,
        'rooms': <Map<String, dynamic>>[],
        'bars': <Map<String, dynamic>>[],
      },
      {
        'id': 'nozone',
        'name': 'Toà C',
        'timeZone': null,
        'today': null,
        'needsTimeZone': true,
        'rooms': <Map<String, dynamic>>[],
        'bars': <Map<String, dynamic>>[],
      },
    ],
  };
}

class Calls {
  final calendar = <Map<String, dynamic>>[];
  final other = <String>[];
}

TeamService calendarService(
  Calls calls, {
  Object? fail,
  bool canLease = true,
  bool sandwich = false,
}) {
  final store = TeamPreviewStore();
  var failures = fail == null ? 0 : 1;
  return TeamService(
    transport: (name, data) async {
      if (name == 'calendarView') {
        calls.calendar.add(Map<String, dynamic>.from(data));
        if (failures > 0) {
          failures--;
          throw fail!;
        }
        return calendarFixture(
          data['from'] as String,
          to: data['to'] as String?,
          canLease: canLease,
          sandwich: sandwich,
        );
      }
      calls.other.add('$name/${data['action']}');
      if (name == 'bookingWorkspace' && data['action'] == 'rooms') {
        return {
          'records': [
            {
              'id': 'r102',
              'roomNumber': '102',
              'currency': 'VND',
              'nightlyPriceMinor': 500000,
            },
            {
              'id': 'r104',
              'roomNumber': '104',
              'currency': 'VND',
              'nightlyPriceMinor': 400000,
            },
          ],
          'staff': <Map<String, dynamic>>[],
          'accounts': <Map<String, dynamic>>[],
          'timeZone': 'Asia/Ho_Chi_Minh',
          'canPrice': true,
          'canReadGuestIds': true,
        };
      }
      if (name == 'tenantLeases' && data['action'] == 'prepare') {
        return {
          'record': {
            'roomNumber': '104',
            'roomRevision': '1:0',
            'currency': 'VND',
            'timeZone': 'Asia/Ho_Chi_Minh',
            'today': '2026-10-02',
            'canBackdate': true,
            'staff': <Map<String, dynamic>>[],
            'accounts': <Map<String, dynamic>>[],
            'monthlyRentMinor': 5000000,
          },
        };
      }
      if (name == 'technicalProblems' && data['action'] == 'list') {
        return {
          'records': <Map<String, dynamic>>[],
          'rooms': [
            {'id': 'r103', 'roomNumber': '103', 'blocked': true},
          ],
          'accounts': <Map<String, dynamic>>[],
          'currency': 'VND',
          'today': '2026-10-02',
          'canReport': true,
          'canManage': true,
          'canExpense': true,
          'uid': 'owner',
          'drive': {'state': 'none'},
        };
      }
      return store.call(name, data);
    },
  );
}

Future<void> mountCalendar(
  WidgetTester tester,
  TeamService service, {
  String language = 'en',
  Size size = const Size(1440, 1000),
  double scale = 1,
  TeamAccess? access,
}) => mountReview(
  tester,
  RoomCalendar(
    key: UniqueKey(),
    organizationId: 'preview',
    accountId: 'preview-owner',
    service: service,
    access: access,
    initialMonth: DateTime(2026, 10),
  ),
  language: language,
  size: size,
  scale: scale,
);

Finder bar(String id) => find.byKey(ValueKey('calendar-bar-$id'));

/// The dates' sideways scroll view (the body, not the day header).
final _gridFinder = find
    .byWidgetPredicate(
      (w) =>
          w is SingleChildScrollView &&
          w.scrollDirection == Axis.horizontal &&
          w.controller != null,
    )
    .first;

/// Scrolls the dates so [x] (a screen position) is in the middle of the view.
Future<void> showX(WidgetTester tester, double x) async {
  final view = tester.getRect(_gridFinder);
  if (x > view.left + 8 && x < view.right - 8) return;
  final grid = tester.widget<SingleChildScrollView>(_gridFinder).controller!;
  grid.jumpTo(
    (grid.offset + x - view.center.dx).clamp(
      0.0,
      grid.position.maxScrollExtent,
    ),
  );
  await tester.pumpAndSettle();
}

/// Taps the empty part of a day (1..31) in a room's row. Days are wide
/// (2026-10-04: 432 px, 18 px an hour), so the day is scrolled into view first.
Future<void> tapDay(WidgetTester tester, String roomId, int day) async {
  final column = find.byKey(
    ValueKey('calendar-day-2026-10-${day.toString().padLeft(2, '0')}'),
  );
  await showX(tester, tester.getCenter(column).dx);
  final row = find.byKey(ValueKey('calendar-room-$roomId'));
  await tester.tapAt(
    Offset(tester.getCenter(column).dx, tester.getCenter(row).dy + 8),
  );
  await tester.pumpAndSettle();
}

/// Taps the part of a bar that is on screen (a long bar's middle may not be).
Future<void> tapBar(WidgetTester tester, String id) async {
  var rect = tester.getRect(bar(id));
  var view = tester.getRect(_gridFinder);
  if (rect.right < view.left + 12 || rect.left > view.right - 12) {
    await showX(tester, rect.left + 12);
    rect = tester.getRect(bar(id));
    view = tester.getRect(_gridFinder);
  }
  final left = rect.left < view.left ? view.left : rect.left;
  final right = rect.right > view.right ? view.right : rect.right;
  await tester.tapAt(Offset((left + right) / 2, rect.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'Ahem',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('narrow property selector stays entirely inside the viewport', (
    tester,
  ) async {
    await mountCalendar(
      tester,
      calendarService(Calls()),
      size: const Size(320, 740),
      access: TeamAccess.fromMap(TeamPreviewStore.grant('owner')),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(
      find.byKey(const ValueKey('calendar-building-riverside')),
    );
    expect(rect.right, lessThanOrEqualTo(320));
    expect(
      find
          .byKey(const ValueKey('calendar-building-pages-riverside'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  // Fix 2 (2026-10-09, Tom): one building shows its name in the same outlined
  // box as the several-buildings picker, not as a small plain label.
  testWidgets('one building: name box is as tall as the picker', (
    tester,
  ) async {
    await mountCalendar(
      tester,
      calendarService(Calls()),
      access: TeamAccess.fromMap(TeamPreviewStore.grant('owner')),
    );
    await tester.pumpAndSettle();
    final picker = tester.getSize(
      find.byKey(const ValueKey('calendar-building-riverside')),
    );
    final one = TeamService(
      transport: (name, data) async {
        final m = calendarFixture(
          data['from'] as String,
          to: data['to'] as String?,
        );
        return {
          ...m,
          'properties': [(m['properties'] as List).first],
        };
      },
    );
    await mountCalendar(
      tester,
      one,
      access: TeamAccess.fromMap(TeamPreviewStore.grant('owner')),
    );
    await tester.pumpAndSettle();
    final box = tester.getSize(
      find.byKey(const ValueKey('calendar-building-box')),
    );
    expect(box.height, closeTo(picker.height, 1));
    expect(find.text('Riverside — Khu căn hộ phía Đông'), findsOneWidget);
    expect(
      find
          .byKey(const ValueKey('calendar-building-pages-riverside'))
          .hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('small toolbar exposes authorized actions through three dots', (
    tester,
  ) async {
    await mountCalendar(
      tester,
      calendarService(Calls()),
      size: const Size(390, 844),
      access: TeamAccess.fromMap(TeamPreviewStore.grant('owner')),
    );
    await tester.pumpAndSettle();
    final menu = find.byKey(const ValueKey('calendar-actions-menu'));
    expect(menu.hitTestable(), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-new-stay')), findsNothing);
    await tester.tap(menu);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<int>), findsNWidgets(5));
    expect(tester.takeException(), isNull);
  });
  testWidgets('property picker preserves the complete one-line name', (
    tester,
  ) async {
    await mountCalendar(tester, calendarService(Calls()));
    await tester.pumpAndSettle();
    final label = find.text('Riverside — Khu căn hộ phía Đông').first;
    expect(tester.widget<Text>(label).overflow, isNot(TextOverflow.ellipsis));
    await tester.tap(find.byKey(const ValueKey('calendar-building-riverside')));
    await tester.pumpAndSettle();
    for (final text in tester.widgetList<Text>(
      find.text('Riverside — Khu căn hộ phía Đông'),
    )) {
      expect(text.overflow, isNot(TextOverflow.ellipsis));
    }
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'populated calendar fits languages, screens, landscape and large text',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'Ahem',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final language in ['en', 'vi']) {
        // 812×255: phone landscape inside the workspace (top bar + bottom bar take the rest).
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(812, 255),
          const Size(1440, 1000),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            // As the owner, so the toolbar also has "New building" and "New room".
            await mountCalendar(
              tester,
              calendarService(Calls()),
              language: language,
              size: size,
              scale: scale,
              access: TeamAccess.fromMap(TeamPreviewStore.grant('owner')),
            );
            final reason = '$language $size $scale';
            expect(tester.takeException(), isNull, reason: reason);
            expect(
              find.byKey(const ValueKey('calendar-month')),
              findsOneWidget,
              reason: reason,
            );
            expect(
              find.byKey(const ValueKey('calendar-today')),
              findsOneWidget,
              reason: reason,
            );
            // The grid has room to show at least a few days on every screen.
            final grid = tester.getRect(
              find.byKey(const ValueKey('calendar-grid')),
            );
            expect(grid.width, greaterThan(0), reason: reason);
            final shot =
                (language == 'en' && size.width == 1440 && scale == 1) ||
                (language == 'vi' && size.width == 320 && scale == 2) ||
                (language == 'vi' && size.width == 812 && scale == 1) ||
                (language == 'vi' && size.width == 1440 && scale == 1);
            if (shot) {
              await tester.runAsync(() async {
                final boundary =
                    tester
                            .element(find.byKey(const ValueKey('capture')))
                            .renderObject!
                        as RenderRepaintBoundary;
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory(
                  '.dart_tool/calendar-layout',
                ).create(recursive: true);
                await File(
                  '.dart_tool/calendar-layout/$language-${size.width.toInt()}x${size.height.toInt()}-$scale.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
        }
      }
    },
  );

  testWidgets(
    'one building at a time: its rooms are rows, the picker switches building',
    (tester) async {
      await mountCalendar(tester, calendarService(Calls()));
      for (final id in ['room-101', 'r102', 'r103', 'r104']) {
        expect(
          find.byKey(ValueKey('calendar-room-$id')),
          findsOneWidget,
          reason: id,
        );
      }
      expect(
        find.text('Garden Homestay'),
        findsNothing,
        reason: 'only the chosen building',
      );
      expect(find.text('No rooms yet'), findsNothing);
      // No filters and no "smaller rows" button any more (Tom, 2026-10-03).
      expect(find.byKey(const ValueKey('calendar-filter-all')), findsNothing);
      expect(find.byKey(const ValueKey('calendar-density')), findsNothing);
      // Days read "Sat, 3" on one line; the first of a month names it
      // ("Thu, 1/10"), since several months are loaded side by side.
      expect(find.text('Sat, 3'), findsOneWidget);
      expect(find.text('Thu, 1/10'), findsOneWidget);
      // Rooms are rows, in number order top to bottom.
      final x = [
        for (final id in ['room-101', 'r102', 'r103', 'r104'])
          tester.getCenter(find.byKey(ValueKey('calendar-room-$id'))).dy,
      ];
      expect(x, [...x]..sort());
      // Every stay of the month is drawn; overlapping stays sit side by side.
      for (final id in [
        'lease:tenant-anh',
        'booking:b1',
        'booking:b2',
        'booking:b3',
        'booking:hidden',
        'booking:b4',
      ]) {
        expect(bar(id), findsOneWidget, reason: id);
      }
      // Stays that overlap keep the full bar height; the row grows for the
      // second lane (2026-10-05, Tom: thin bars, rows fit the bars).
      expect(
        tester.getSize(bar('booking:b2')).height,
        moreOrLessEquals(tester.getSize(bar('booking:b1')).height),
      );
      expect(tester.getSize(bar('booking:b1')).height, 24);
      expect(
        tester.getSize(find.byKey(const ValueKey('calendar-room-r102'))).height,
        greaterThan(
          tester
              .getSize(find.byKey(const ValueKey('calendar-room-r104')))
              .height,
        ),
      );
      expect(
        tester.getTopLeft(bar('booking:b2')).dy,
        isNot(tester.getTopLeft(bar('booking:b3')).dy),
      );
      // A short hourly stay is still big enough to tap.
      expect(tester.getSize(bar('booking:b4')).width, greaterThanOrEqualTo(16));
      // Days go right: the stay starting on the 3rd is left of the one on the 6th.
      expect(
        tester.getTopLeft(bar('booking:b1')).dx,
        lessThan(tester.getTopLeft(bar('booking:b2')).dx),
      );
      // Both 102 stays sit in room 102's row.
      final row102 = tester.getRect(
        find.byKey(const ValueKey('calendar-room-r102')),
      );
      expect(
        tester.getCenter(bar('booking:b1')).dy,
        inInclusiveRange(row102.top, row102.bottom),
      );

      // Switch to the other building.
      await tester.tap(
        find.byKey(const ValueKey('calendar-building-riverside')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garden Homestay').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-room-r102')), findsNothing);
      expect(find.text('No rooms yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'owner: create building and room next to the picker; building and room pages open as dialogs',
    (tester) async {
      final owner = TeamAccess.fromMap(TeamPreviewStore.grant('owner'));
      await mountCalendar(tester, calendarService(Calls()), access: owner);
      expect(
        find.byKey(const ValueKey('calendar-new-building')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('calendar-new-room')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('calendar-new-building')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PropertyDetailsScreen>(find.byType(PropertyDetailsScreen))
            .create,
        isTrue,
      );
      // Created: the dialog closes itself.
      expect(
        tester
            .widget<PropertyDetailsScreen>(find.byType(PropertyDetailsScreen))
            .onCreated,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendar-new-room')));
      await tester.pumpAndSettle();
      final newRoom = tester.widget<RoomDirectory>(find.byType(RoomDirectory));
      expect([newRoom.startCreate, newRoom.buildingId], [true, 'riverside']);
      expect(newRoom.onCreated, isNotNull);
      await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
      await tester.pumpAndSettle();

      // Tapping a room: only that room, with its pages.
      await tester.tap(find.byKey(const ValueKey('calendar-room-r102')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RoomDirectory>(find.byType(RoomDirectory)).onlyRoomId,
        'r102',
      );
      expect(
        find.byKey(const ValueKey('calendar-room-dialog-problems')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
      await tester.pumpAndSettle();

      // Tapping the building: its pages behind chips.
      await tester.tap(
        find.byKey(const ValueKey('calendar-building-pages-riverside')),
      );
      await tester.pumpAndSettle();
      for (final page in ['property', 'contract', 'layout', 'fees']) {
        expect(
          find.byKey(ValueKey('building-page-$page')),
          findsOneWidget,
          reason: page,
        );
      }
      expect(find.byType(PropertyDetailsScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('building-page-layout')));
      await tester.pumpAndSettle();
      expect(find.byType(PropertyLayoutScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'without building rights there are no create buttons and a room opens its problems',
    (tester) async {
      final receptionist = TeamAccess.fromMap(
        TeamPreviewStore.grant('receptionist'),
      );
      await mountCalendar(
        tester,
        calendarService(Calls()),
        access: receptionist,
      );
      expect(find.byKey(const ValueKey('calendar-new-building')), findsNothing);
      expect(find.byKey(const ValueKey('calendar-new-room')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('calendar-room-r102')));
      await tester.pumpAndSettle();
      expect(find.byType(RoomDirectory), findsNothing);
      expect(
        find.byKey(const ValueKey('calendar-room-problems')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'month buttons move by a month (three loaded); Today comes back',
    (tester) async {
      final calls = Calls();
      await mountCalendar(tester, calendarService(calls));
      // The month before, the month shown and the month after.
      expect(calls.calendar.last, {
        'organizationId': 'preview',
        'from': '2026-09-01',
        'to': '2026-12-01',
      });
      expect(find.text('October 2026'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-next')));
      await tester.pumpAndSettle();
      expect(calls.calendar.last['from'], '2026-10-01');
      expect(calls.calendar.last['to'], '2027-01-01');
      expect(find.text('November 2026'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const ValueKey('calendar-prev')));
        await tester.pumpAndSettle();
      }
      expect(find.text('August 2026'), findsOneWidget);
      expect(calls.calendar.last['from'], '2026-07-01');
      expect(calls.calendar.last['to'], '2026-10-01');
      await tester.tap(find.byKey(const ValueKey('calendar-today')));
      await tester.pumpAndSettle();
      expect(calls.calendar.last['from'], '2026-09-01');
      expect(find.text('October 2026'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-today-column')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  // 2026-10-04 (Tom): no cut at the end of a month; scrolling near either end
  // loads the next (or previous) month and the same days stay on screen.
  testWidgets('scrolling past the loaded months loads more; no month cut', (
    tester,
  ) async {
    final calls = Calls();
    await mountCalendar(
      tester,
      calendarService(calls),
      size: const Size(390, 844),
    );
    final grid = tester
        .widget<SingleChildScrollView>(
          find
              .byWidgetPredicate(
                (w) =>
                    w is SingleChildScrollView &&
                    w.scrollDirection == Axis.horizontal &&
                    w.controller != null,
              )
              .first,
        )
        .controller!;
    // 1 October and 31 October sit side by side with November in one grid.
    expect(
      find.byKey(const ValueKey('calendar-day-2026-11-01')),
      findsOneWidget,
    );
    grid.jumpTo(grid.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(calls.calendar.last['from'], '2026-10-01');
    expect(calls.calendar.last['to'], '2027-01-01');
    // Still at the end of November/start of December, not thrown back.
    expect(find.textContaining('2026'), findsWidgets);
    expect(grid.offset, lessThan(grid.position.maxScrollExtent));
    grid.jumpTo(0);
    await tester.pumpAndSettle();
    expect(calls.calendar.last['from'], '2026-09-01');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a lease opens the tenant page in a dialog; closing it reloads only after a change',
    (tester) async {
      final calls = Calls();
      await mountCalendar(tester, calendarService(calls));
      final before = calls.calendar.length;
      await tapBar(tester, 'lease:tenant-anh');
      expect(find.byType(CalendarPageDialog), findsOneWidget);
      expect(find.textContaining('Room 101'), findsWidgets);
      final page = tester.widget<TenantContactsScreen>(
        find.byType(TenantContactsScreen),
      );
      expect(page.initialRecordId, 'tenant-anh');
      expect(page.buildingId, 'riverside');
      expect(calls.other, contains('tenantContacts/read'));
      expect(
        calls.other,
        isNot(contains('tenantContacts/list')),
        reason: 'no list behind a dialog',
      );
      // 2026-10-04: the dialog's title bar names the tenant; no back link or second title.
      expect(
        find.descendant(
          of: find.byType(TenantContactsScreen),
          matching: find.byType(WsBack),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarPageDialog), findsNothing);
      // 2026-10-09 (Tom): only read, nothing changed: no reload.
      expect(calls.calendar.length, before);
      // Something saved on the page: the calendar loads again.
      await tapBar(tester, 'lease:tenant-anh');
      ServerWrites.note('tenantContacts', {'action': 'update'});
      await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
      await tester.pumpAndSettle();
      expect(calls.calendar.length, before + 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a booking opens in a dialog; the close button closes it', (
    tester,
  ) async {
    final calls = Calls();
    await mountCalendar(tester, calendarService(calls));
    await tapBar(tester, 'booking:b1');
    final page = tester.widget<BookingWorkspaceScreen>(
      find.byType(BookingWorkspaceScreen),
    );
    expect(page.initialRecordId, 'b1');
    expect(page.onClose, isNotNull);
    expect(calls.other, contains('bookingWorkspace/read'));
    expect(calls.other, isNot(contains('bookingWorkspace/list')));
    await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarPageDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stay the person may not open says so instead', (tester) async {
    await mountCalendar(tester, calendarService(Calls()));
    await tapBar(tester, 'booking:hidden');
    expect(find.text("You don't have access to this stay."), findsOneWidget);
    expect(find.byType(CalendarPageDialog), findsNothing);
  });

  testWidgets(
    'an empty day offers a short stay or a lease for that room and date',
    (tester) async {
      final calls = Calls();
      await mountCalendar(tester, calendarService(calls));
      await tapDay(tester, 'r102', 12); // room 102, 12 October
      expect(find.byKey(const ValueKey('calendar-new-short')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-new-long')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-report')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-new-short')));
      await tester.pumpAndSettle();
      expect(find.byType(CalendarPageDialog), findsOneWidget);
      final start = tester.widget<TextFormField>(
        find.byKey(const ValueKey('ops-startLocal')),
      );
      final end = tester.widget<TextFormField>(
        find.byKey(const ValueKey('ops-endLocal')),
      );
      expect(start.controller!.text, '2026-10-12 14:00');
      expect(end.controller!.text, '2026-10-13 12:00');
      expect(
        tester
            .widget<BookingWorkspaceScreen>(find.byType(BookingWorkspaceScreen))
            .initialRoomId,
        'r102',
      );
      await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
      await tester.pumpAndSettle();

      await tapDay(tester, 'r104', 12); // room 104
      await tester.tap(find.byKey(const ValueKey('calendar-new-long')));
      await tester.pumpAndSettle();
      final lease = tester.widget<TenantLeaseScreen>(
        find.byType(TenantLeaseScreen),
      );
      expect(lease.initialRoomId, 'r104');
      expect(lease.initialMoveIn, '2026-10-12');
      expect(calls.other, contains('tenantLeases/prepare'));
      expect(calls.other, isNot(contains('tenantLeases/rooms')));
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('lease-start')))
            .controller!
            .text,
        '2026-10-12',
      );
      await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a room closed by a problem cannot take a new stay; problems open from its header',
    (tester) async {
      await mountCalendar(tester, calendarService(Calls()));
      await tapDay(tester, 'r103', 12); // room 103
      expect(
        find.text('This room is closed while a problem is open.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('calendar-new-short')))
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('calendar-new-long')))
            .enabled,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('calendar-report')));
      await tester.pumpAndSettle();
      final problems = tester.widget<TechnicalProblemsScreen>(
        find.byType(TechnicalProblemsScreen),
      );
      expect(problems.reportRoomId, 'r103');
      await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-room-r103')));
      await tester.pumpAndSettle();
      expect(find.text('Vòi nước hỏng'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('calendar-room-problems')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TechnicalProblemsScreen>(
              find.byType(TechnicalProblemsScreen),
            )
            .reportRoomId,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'without lease access the day offers only what the person may do',
    (tester) async {
      await mountCalendar(tester, calendarService(Calls(), canLease: false));
      await tapDay(tester, 'r102', 12);
      expect(find.byKey(const ValueKey('calendar-new-short')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-new-long')), findsNothing);
    },
  );

  testWidgets('load error shows a retry; empty and denied states say why', (
    tester,
  ) async {
    final calls = Calls();
    await mountCalendar(
      tester,
      calendarService(
        calls,
        fail: FirebaseFunctionsException(code: 'unavailable', message: 'x'),
      ),
    );
    expect(
      find.text(
        'Could not load the calendar. Check the connection and try again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(bar('booking:b1'), findsOneWidget);
    expect(
      find.text(
        'Could not load the calendar. Check the connection and try again.',
      ),
      findsNothing,
    );

    await mountCalendar(
      tester,
      calendarService(
        Calls(),
        fail: FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'x',
        ),
      ),
    );
    expect(
      find.text('You no longer have access to this calendar.'),
      findsOneWidget,
    );

    await mountCalendar(
      tester,
      TeamService(
        transport: (name, data) async => {
          'properties': <Map<String, dynamic>>[],
        },
      ),
    );
    expect(
      find.text('There is no property you can see on the calendar.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('calendar stamps are wall-clock times that ignore the device zone', () {
    expect(calStamp('2026-10-03 14:30'), DateTime.utc(2026, 10, 3, 14, 30));
    expect(calStamp('2026-10-03'), DateTime.utc(2026, 10, 3, 12));
    expect(calStamp('bad'), isNull);
    expect(calYmd(DateTime.utc(2026, 1, 5)), '2026-01-05');
  });

  // 2026-10-04: check-out time at the end of the bar, then the status as a circle.
  testWidgets('bar end: check-out time then a status circle; two colours only', (
    tester,
  ) async {
    Future<(String?, BoxDecoration)> end(
      Map<String, dynamic> m, {
      double width = 220,
    }) async {
      await mountReview(
        tester,
        Center(
          child: SizedBox(
            width: width,
            height: 40,
            child: CalBarTile(
              bar: CalBar.fromMap({
                'id': 'booking:x',
                'type': 'booking',
                'roomId': 'r',
                'start': '2026-10-03 14:00',
                'end': '2026-10-06 12:00',
                'name': 'Khách',
                'canOpen': true,
                ...m,
              }),
              roomNumber: '101',
              from: 0,
              to: width,
              x: (_) => 0,
              onTap: () {},
            ),
          ),
        ),
        language: 'vi',
      );
      final time = find.byKey(const ValueKey('calendar-bar-end'));
      final circle = tester.widget<Container>(
        find.byKey(const ValueKey('calendar-bar-status')),
      );
      return (
        time.evaluate().isEmpty ? null : tester.widget<Text>(time).data,
        circle.decoration! as BoxDecoration,
      );
    }

    final deposited = await end({'status': 'upcoming', 'deposit': true});
    expect(deposited.$1, '12:00');
    expect(deposited.$2.color, calStatusColor('deposited'));
    expect(
      (await end({'status': 'staying'})).$2.color,
      calStatusColor('staying'),
    );
    expect((await end({'status': 'out'})).$2.color, calStatusColor('out'));
    // Nothing paid, not checked in: a hollow circle.
    expect((await end({'status': 'upcoming'})).$2.color, Colors.white);
    // Too narrow for the time: the circle only.
    final narrow = await end({'status': 'staying'}, width: 50);
    expect(narrow.$1, isNull);
    // A lease shows its end date and time (2026-10-04, Tom): the contract's
    // planned end while the tenant stays, the real end after moving out.
    final lease = await end({
      'type': 'lease',
      'status': 'staying',
      'end': null,
      'plannedEnd': '2027-06-30',
    }, width: 420);
    expect(lease.$1, 'HĐ 30/06/2027 12:00');
    final moved = await end({
      'type': 'lease',
      'status': 'out',
      'end': '2027-03-15 12:00',
    }, width: 420);
    expect(moved.$1, '15/03/2027 12:00');
    expect(find.byKey(const ValueKey('calendar-bar-status')), findsOneWidget);
    // An older "deposit" kind is still a deposit, drawn in the short-stay colour.
    final old = CalBar.fromMap({
      'id': 'b',
      'type': 'booking',
      'roomId': 'r',
      'kind': 'deposit',
      'status': 'upcoming',
    });
    expect(calStayStatus(old), 'deposited');
    final ctx = tester.element(find.byType(CalBarTile));
    expect(calKindColor(ctx, old), calKindColor(ctx, null, kind: 'short'));
    final hidden = CalBar.fromMap({
      'id': 'l',
      'type': 'lease',
      'roomId': 'r',
      'kind': 'long',
      'anonymous': true,
    });
    expect(calKindColor(ctx, hidden), calKindColor(ctx, null, kind: 'long'));
    expect(tester.takeException(), isNull);
  });

  // 2026-10-04: the name and the status follow the screen while the month
  // scrolls sideways, so a long bar always shows who it is.
  testWidgets(
    'a long bar keeps its name and status on screen while scrolling',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await mountReview(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 40,
            child: SingleChildScrollView(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 1200,
                height: 40,
                child: CalBarTile(
                  bar: CalBar.fromMap({
                    'id': 'lease:x',
                    'type': 'lease',
                    'roomId': 'r',
                    'start': '2026-10-05 12:00',
                    'name': 'Khach Dai Han',
                    'status': 'staying',
                    'canOpen': true,
                  }),
                  roomNumber: '101',
                  from: 0,
                  to: 1200,
                  x: (_) => 0,
                  onTap: () {},
                  scroll: scroll,
                  viewWidth: 300,
                ),
              ),
            ),
          ),
        ),
        language: 'vi',
      );
      // Positions inside the 300 px window.
      double left() =>
          tester.getTopLeft(find.byType(SingleChildScrollView).first).dx;
      double nameX() =>
          tester.getTopLeft(find.text('Khach Dai Han')).dx - left();
      double circleX() =>
          tester
              .getTopLeft(find.byKey(const ValueKey('calendar-bar-status')))
              .dx -
          left();
      expect(nameX(), lessThan(20));
      expect(circleX(), inInclusiveRange(250, 300));
      scroll.jumpTo(600);
      await tester.pump();
      // Still at the left and right of what is on screen.
      expect(nameX(), inInclusiveRange(0, 20));
      expect(circleX(), inInclusiveRange(250, 300));
      expect(tester.takeException(), isNull);
    },
  );

  // 2026-10-04: a bar scrolled almost off screen shows a bubble next to the
  // sliver that is left, with its name and status; the bubble opens the bar.
  testWidgets('a bar almost off screen shows a bubble with its name', (
    tester,
  ) async {
    await mountCalendar(
      tester,
      calendarService(Calls()),
      size: const Size(390, 844),
    );
    // (No "before" check: in the test font a 3-night bar is already too
    // short for "Trần Văn Bình", so it has a bubble from the start.)
    final grid = tester.widget<SingleChildScrollView>(
      find
          .byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal &&
                w.controller != null,
          )
          .first,
    );
    // The grid starts on 1 September; days are 432 px (18 px an hour).
    // Trần Văn Bình's stay ends on 6/10 at 11:30: scroll so 12 px of it is
    // left at the left edge.
    final dayW = tester
        .getSize(find.byKey(const ValueKey('calendar-today-column')))
        .width;
    grid.controller!.jumpTo(35 * dayW + dayW * 11.5 / 24 - 12);
    await tester.pumpAndSettle();
    final bubble = find.byKey(const ValueKey('calendar-bubble-booking:b1'));
    expect(bubble, findsOneWidget);
    expect(
      find.descendant(of: bubble, matching: find.text('Trần Văn Bình')),
      findsOneWidget,
    );
    // Only a sliver is left of the bar, so the bubble carries its status and
    // its check-out time.
    expect(
      find.descendant(
        of: bubble,
        matching: find.byKey(const ValueKey('calendar-bubble-status')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bubble, matching: find.text('11:30')),
      findsOneWidget,
    );
    // On top of any neighbour's bubble: tapping it opens this stay.
    await tester.tap(bubble);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BookingWorkspaceScreen>(find.byType(BookingWorkspaceScreen))
          .initialRecordId,
      'b1',
    );
    await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
    await tester.pumpAndSettle();
    // A bar too short for its name (3 hours, 10/10) shows the name in a
    // bubble beside it right away, never "…".
    // (Days are 432 px, more than a phone's width: 10/10 from 08:00, so the
    // evening after the stay is free for its bubble.)
    grid.controller!.jumpTo(39 * dayW + dayW / 3);
    await tester.pumpAndSettle();
    final short = find.byKey(const ValueKey('calendar-bubble-booking:b4'));
    expect(short, findsOneWidget);
    expect(
      find.descendant(of: short, matching: find.text('Hourly')),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(short).dx,
      greaterThan(tester.getTopRight(bar('booking:b4')).dx),
      reason: 'beside the bar, on its right',
    );
    expect(tester.takeException(), isNull);
  });

  // 2026-10-04 (Tom, live): a 3-hour stay's name bubble covered the next
  // guest's name. A bubble goes right, left, above or below its bar, to the
  // first place that covers no other stay's text; every short stay keeps
  // its name.
  testWidgets('a name bubble never covers the stay next to it', (tester) async {
    await mountCalendar(tester, calendarService(Calls(), sandwich: true));
    final grid = tester.widget<SingleChildScrollView>(
      find
          .byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal &&
                w.controller != null,
          )
          .first,
    );
    final dayW = tester
        .getSize(find.byKey(const ValueKey('calendar-today-column')))
        .width;
    // 10 October at the left edge: the end of the stay before, the hourly
    // stay and the stay after are all on screen.
    grid.controller!.jumpTo(39 * dayW);
    await tester.pumpAndSettle();
    const ids = ['booking:b4', 'booking:b5', 'booking:b6'];
    for (final id in ids) {
      expect(bar(id), findsOneWidget, reason: id);
    }
    // One lane: the three stays share the row's full height.
    for (final id in ids) {
      expect(
        tester.getRect(bar(id)).height,
        moreOrLessEquals(tester.getRect(bar('booking:b4')).height),
        reason: id,
      );
      expect(
        tester.getRect(bar(id)).top,
        moreOrLessEquals(tester.getRect(bar('booking:b4')).top),
        reason: id,
      );
    }
    // The hourly stay has no room on its right or left (its neighbours' end
    // time, status and name are there), so its bubble goes above it.
    final hourly = find.byKey(const ValueKey('calendar-bubble-booking:b4'));
    expect(hourly, findsOneWidget, reason: 'every short stay shows its name');
    expect(
      find.descendant(of: hourly, matching: find.text('Hourly')),
      findsOneWidget,
    );
    // Tom: the status shows once (on the bar), the end time the bar has no
    // room for goes in the bubble.
    expect(
      find.descendant(of: hourly, matching: find.text('16:00')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: hourly,
        matching: find.byKey(const ValueKey('calendar-bubble-status')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: bar('booking:b4'),
        matching: find.byKey(const ValueKey('calendar-bar-status')),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(hourly).bottom,
      lessThanOrEqualTo(tester.getRect(bar('booking:b4')).top + 0.5),
      reason: 'above the bar',
    );
    // No bubble covers any text of the stays around it: names, icon lines,
    // end times or status circles.
    final texts = <Rect>[
      for (final id in ['booking:b5', 'booking:b6'])
        for (final e
            in find
                .descendant(
                  of: bar(id),
                  matching: find.byWidgetPredicate(
                    (w) =>
                        w is Text ||
                        w is Icon ||
                        w.key == const ValueKey('calendar-bar-status'),
                  ),
                )
                .evaluate())
          tester.getRect(find.byWidget(e.widget)),
    ];
    expect(texts, isNotEmpty);
    expect(find.text('After Guest'), findsOneWidget);
    for (final e in find.byType(CalEdgeBubble).evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      for (final t in texts) {
        expect(
          r.overlaps(t.deflate(0.5)),
          isFalse,
          reason: 'bubble $r over text $t',
        );
      }
    }
    // The bubble opens its own stay.
    await tester.tap(hourly);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BookingWorkspaceScreen>(find.byType(BookingWorkspaceScreen))
          .initialRecordId,
      'b4',
    );
    expect(tester.takeException(), isNull);
  });

  // 2026-10-04 (Tom): a bar's details appear next to the mouse, not under the
  // middle of a long bar; every day shows its hours (6 · 12 · 18).
  testWidgets(
    'hovering a bar shows its details by the mouse; days show hours',
    (tester) async {
      await mountCalendar(tester, calendarService(Calls()));
      expect(
        find.text('12'),
        findsWidgets,
        reason: 'hour marks under the dates',
      );
      final target = bar('lease:tenant-anh');
      final rect = tester.getRect(target);
      // The lease began in September, so its left end is off screen: hover it
      // over today's column, which is on screen.
      final today = tester.getRect(
        find.byKey(const ValueKey('calendar-today-column')),
      );
      final point = Offset(today.center.dx, rect.center.dy);
      final mouse = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(point);
      await tester.pump(const Duration(milliseconds: 500));
      final card = find.byKey(const ValueKey('calendar-hover-info'));
      expect(card, findsOneWidget);
      // Just below and to the right of the pointer, far from the bar's middle.
      final at = tester.getTopLeft(card);
      expect((at.dx - point.dx).abs(), lessThan(40));
      expect((at.dy - point.dy).abs(), lessThan(40));
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Nguyễn Thị Minh Anh'),
        ),
        findsOneWidget,
      );
      // A lease's dates with the year and time.
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining(
            '01/09/2026 12:00 – Contract ends 31/08/2027 12:00',
          ),
        ),
        findsOneWidget,
      );
      // It follows the pointer and goes away when the mouse leaves.
      await mouse.moveTo(point + const Offset(200, 0));
      await tester.pump();
      expect(tester.getTopLeft(card).dx, greaterThan(at.dx + 150));
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      expect(card, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  // 2026-10-04 (Tom): a red line at the property's current time, and the
  // toolbar names both months when the screen shows the end of one and the
  // start of the next.
  testWidgets('a red now line; the label names both months on screen', (
    tester,
  ) async {
    await mountCalendar(tester, calendarService(Calls()));
    final line = find.byKey(const ValueKey('calendar-now-line'));
    expect(line, findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-now-head')), findsOneWidget);
    // 09:00 on 2 October: 37.5 % into today's column.
    final today = tester.getRect(
      find.byKey(const ValueKey('calendar-today-column')),
    );
    final x = tester.getRect(line).center.dx;
    expect(x, closeTo(today.left + today.width * 9 / 24, 2));
    // Drawn under the bars, so it never runs through a name (Tom).
    final layer = tester.widget<Stack>(
      find.ancestor(of: line, matching: find.byType(Stack)).first,
    );
    int at(bool Function(Widget) test) => layer.children.indexWhere(test);
    final lineAt = at((w) => w.key == const ValueKey('calendar-now-line'));
    final barAt = at((w) => w is Positioned && w.child is CalBarTile);
    expect(barAt, greaterThan(lineAt));
    // Opened at today: the now line a quarter of the way into the dates.
    final view = tester.getRect(_gridFinder);
    expect(x, closeTo(view.left + view.width / 4, 3));
    expect(find.text('October 2026'), findsOneWidget);
    final grid = tester
        .widget<SingleChildScrollView>(
          find
              .byWidgetPredicate(
                (w) =>
                    w is SingleChildScrollView &&
                    w.scrollDirection == Axis.horizontal &&
                    w.controller != null,
              )
              .first,
        )
        .controller!;
    // About 3 days on screen: from late 29 October it reaches into November.
    grid.jumpTo(grid.offset + 28 * today.width);
    await tester.pumpAndSettle();
    expect(find.text('October – November 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // Live check 2026-10-04: dragging the dates forward past the loaded months
  // must never throw the view back to an earlier month.
  testWidgets('flinging the dates forward keeps going forward', (tester) async {
    await mountCalendar(
      tester,
      calendarService(Calls()),
      language: 'vi',
      size: const Size(800, 826),
    );
    final rooms = find.byKey(const ValueKey('calendar-room-r102'));
    var last = 10;
    // Days are wide (about 5 on screen), so it takes a few flings.
    for (var i = 0; i < 14 && last <= 10; i++) {
      // Fling the rooms' row to the left (later days), well right of the labels.
      final row = tester.getRect(rooms);
      await tester.flingFrom(
        Offset(row.right + 400, row.center.dy),
        const Offset(-500, 0),
        2000,
      );
      await tester.pumpAndSettle();
      final label = tester
          .widget<Text>(find.byKey(const ValueKey('calendar-month')))
          .data!;
      // "Tháng 10, 2026", "Tháng 10 – 11, 2026" or "Tháng 12, 2026 – Tháng 1, 2027".
      final first = int.parse(
        RegExp(r'Tháng (\d{1,2})').firstMatch(label)![1]!,
      );
      final month = first < 9 ? first + 12 : first;
      expect(month, greaterThanOrEqualTo(last), reason: label);
      last = month;
    }
    expect(last, greaterThan(10), reason: 'it did move forward');
    expect(tester.takeException(), isNull);
  });

  // 2026-10-05 (Tom): cleaning on the calendar — a purple bar from the
  // planned start to the planned end, solid for the work done so far, and a
  // broom on rooms a guest left that are not cleaned yet.
  testWidgets('cleaning bars and rooms that need cleaning', (tester) async {
    final service = TeamService(
      transport: (name, data) async {
        if (name != 'calendarView') return <String, dynamic>{};
        final m = calendarFixture(
          data['from'] as String,
          to: data['to'] as String?,
        );
        final p = Map<String, dynamic>.from(
          (m['properties'] as List).first as Map,
        );
        p['canAssignCleaning'] = true;
        p['rooms'] = [
          for (final r in p['rooms'] as List)
            {
              ...Map<String, dynamic>.from(r as Map),
              'needsCleaning': (r)['id'] == 'r104',
            },
        ];
        p['bars'] = [
          ...(p['bars'] as List),
          {
            'id': 'cleaning:t1',
            'type': 'cleaning',
            'kind': 'cleaning',
            'roomId': 'r104',
            'start': '2026-10-02 13:00',
            'end': '2026-10-02 15:00',
            'status': 'inProgress',
            'taskStatus': 'inProgress',
            'recordId': 't1',
            'canOpen': true,
            'name': 'Chi Lan',
            'title': 'Don phong',
            'plannedStart': '2026-10-02 13:00',
            'plannedEnd': '2026-10-02 15:00',
            'actualStart': '2026-10-02 13:10',
            'pay': 'due',
            'paidUntil': '2026-10-02 14:00',
          },
        ];
        return {
          ...m,
          'properties': [p, ...(m['properties'] as List).skip(1)],
        };
      },
    );
    await mountCalendar(tester, service);
    final clean = bar('cleaning:t1');
    expect(clean, findsOneWidget);
    // Two hours at 18 px an hour.
    expect(tester.getSize(clean).width, closeTo(36, 3));
    expect(
      find.byKey(const ValueKey('calendar-room-dirty-r104')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('calendar-room-dirty-r102')),
      findsNothing,
    );
    // The details say what, who, the plan and the real time.
    final info = tester
        .widget<CalHoverInfo>(
          find.descendant(of: clean, matching: find.byType(CalHoverInfo)),
        )
        .message;
    expect(info, contains('Cleaning · Chi Lan'));
    expect(info, contains('Planned: 02/10 13:00 – 15:00'));
    expect(info, contains('Worked: 02/10 13:10 – …'));
    // A cleaning's own states, not a stay's (2026-10-05, Tom).
    expect(info, contains('In progress'));
    expect(info, isNot(contains('Staying')));
    final states = ['cleanTodo', 'cleanDoing', 'cleanDone'];
    final stays = ['deposited', 'upcoming', 'staying', 'out'];
    for (final s in states) {
      expect(stays.map(calStatusColor), isNot(contains(calStatusColor(s))));
    }
    expect(calStatusDecoration('cleanTodo').color, Colors.white);
    expect(tester.takeException(), isNull);
  });

  // 2026-10-09 (Tom): a cleaning's bubble goes below its bar, also below the
  // last row, where it is not cut off; a name it covers moves right, the bar
  // stays where it is.
  TeamService cleaningService({required String room, bool guest = false}) =>
      TeamService(
        transport: (name, data) async {
          if (name != 'calendarView') return <String, dynamic>{};
          final m = calendarFixture(
            data['from'] as String,
            to: data['to'] as String?,
          );
          final p = Map<String, dynamic>.from(
            (m['properties'] as List).first as Map,
          );
          p['rooms'] = [
            for (final r in p['rooms'] as List)
              {
                ...Map<String, dynamic>.from(r as Map),
                'blocked': false,
                'problems': const [],
              },
          ];
          p['bars'] = [
            for (final b in p['bars'] as List)
              if ((b as Map)['roomId'] != 'r104' && b['roomId'] != room) b,
            {
              'id': 'cleaning:t1',
              'type': 'cleaning',
              'kind': 'cleaning',
              'roomId': room,
              'start': '2026-10-02 13:00',
              'end': '2026-10-02 15:00',
              'status': 'inProgress',
              'taskStatus': 'inProgress',
              'recordId': 't1',
              'canOpen': true,
              'name': 'Chi Lan',
              'title': 'Don phong',
              'plannedStart': '2026-10-02 13:00',
              'plannedEnd': '2026-10-02 15:00',
              'pay': 'due',
            },
            if (guest)
              {
                'id': 'booking:guest',
                'type': 'booking',
                'roomId': 'r104',
                'kind': 'short',
                'start': '2026-10-02 12:00',
                'end': '2026-10-05 11:00',
                'status': 'upcoming',
                'canOpen': true,
                'recordId': 'guest',
                'name': 'Long Name Guest',
                'pay': 'paid',
                'paidFraction': 1,
              },
          ];
          return {
            ...m,
            'properties': [p, ...(m['properties'] as List).skip(1)],
          };
        },
      );

  testWidgets('a cleaning bubble sits below its bar, even on the last row', (
    tester,
  ) async {
    await mountCalendar(tester, cleaningService(room: 'r104'));
    final clean = bar('cleaning:t1');
    await showX(tester, tester.getCenter(clean).dx);
    final bubble = find.byKey(const ValueKey('calendar-bubble-cleaning:t1'));
    expect(bubble, findsOneWidget);
    final b = tester.getRect(bubble), c = tester.getRect(clean);
    expect(b.top, greaterThanOrEqualTo(c.bottom), reason: 'below the bar');
    // Not cut off: the whole bubble is inside the calendar's scroll view and
    // a tap on it reaches it.
    final view = tester.getRect(find.byType(RoomCalendar));
    expect(b.bottom, lessThanOrEqualTo(view.bottom + 0.5));
    final hits = tester
        .hitTestOnBinding(b.center)
        .path
        .map((e) => e.target)
        .toList();
    expect(hits, contains(tester.renderObject(bubble)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a cleaning bubble moves only the name it covers, not the bar', (
    tester,
  ) async {
    await mountCalendar(tester, cleaningService(room: 'r103', guest: true));
    final clean = bar('cleaning:t1'), guest = bar('booking:guest');
    await showX(tester, tester.getCenter(clean).dx);
    final bubble = find.byKey(const ValueKey('calendar-bubble-cleaning:t1'));
    expect(bubble, findsOneWidget);
    final b = tester.getRect(bubble);
    expect(b.top, greaterThanOrEqualTo(tester.getRect(clean).bottom));
    final g = tester.getRect(guest);
    // The bubble reaches into the guest's bar, over where its name begins.
    expect(b.overlaps(g), isTrue);
    expect(b.left, lessThan(g.left + 60));
    // The bar keeps its place: it starts at 12:00, an hour (18 px) before
    // the cleaning.
    expect(
      g.left,
      moreOrLessEquals(tester.getRect(clean).left - 18, epsilon: 2),
    );
    final name = find.descendant(
      of: guest,
      matching: find.text('Long Name Guest'),
    );
    expect(name, findsOneWidget);
    final n = tester.getRect(name);
    expect(n.left, greaterThanOrEqualTo(b.right), reason: 'name moved past it');
    expect(n.right, lessThanOrEqualTo(g.right));
    expect(tester.takeException(), isNull);
  });

  // 2026-10-04: "Đặt phòng" next to "Tạo phòng": short stay or lease for any room.
  testWidgets('Đặt phòng: short stay or lease, any room of the building', (
    tester,
  ) async {
    final owner = TeamAccess.fromMap(TeamPreviewStore.grant('owner'));
    await mountCalendar(tester, calendarService(Calls()), access: owner);
    await tester.tap(find.byKey(const ValueKey('calendar-new-stay')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-stay-short')), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-stay-long')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-stay-short')));
    await tester.pumpAndSettle();
    final booking = tester.widget<BookingWorkspaceScreen>(
      find.byType(BookingWorkspaceScreen),
    );
    expect(
      [booking.startNew, booking.initialRoomId, booking.buildingId],
      [true, null, 'riverside'],
    );
    expect(booking.initialStart, '2026-10-02 14:00');
    await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-new-stay')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-stay-long')));
    await tester.pumpAndSettle();
    final lease = tester.widget<TenantLeaseScreen>(
      find.byType(TenantLeaseScreen),
    );
    expect([lease.initialRoomId, lease.initialMoveIn], [null, '2026-10-02']);
    // The dialog's title bar names the page: no back link inside it.
    expect(
      find.descendant(
        of: find.byType(TenantLeaseScreen),
        matching: find.byType(WsBack),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
    await tester.pumpAndSettle();
    // "Sự cố" next to it (2026-10-05, Tom): every room's problems, where
    // one can be reported too. Toolbar buttons are icons with a tooltip.
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('calendar-problems')))
          .tooltip,
      'Problems',
    );
    await tester.tap(find.byKey(const ValueKey('calendar-problems')));
    await tester.pumpAndSettle();
    final problems = tester.widget<TechnicalProblemsScreen>(
      find.byType(TechnicalProblemsScreen),
    );
    expect(
      [problems.startReport, problems.reportRoomId, problems.buildingId],
      [false, null, 'riverside'],
    );
    await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
    await tester.pumpAndSettle();
    // "Dọn phòng": the building's housekeeping tasks.
    await tester.tap(find.byKey(const ValueKey('calendar-cleaning')));
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == 'HousekeepingScreen',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  // 2026-10-04 (Tom): 18 px an hour, so a 1-hour stay is a real bar (it was
  // about 5 days on a screen), and a second view shows whole months like
  // Airbnb, every room.
  testWidgets('days are 18 px an hour; the hour marks are every 2 hours', (
    tester,
  ) async {
    await mountCalendar(tester, calendarService(Calls()));
    final grid = tester.getRect(_gridFinder);
    final day = tester.getSize(
      find.byKey(const ValueKey('calendar-today-column')),
    );
    // 18 px an hour (Tom: a 1-hour stay shows as a real bar).
    expect(day.width, 432);
    expect(grid.width / day.width, inInclusiveRange(3, 3.3));
    // The 3-hour stay (13:00–16:00) is drawn at its real length.
    expect(tester.getSize(bar('booking:b4')).width, closeTo(54, 3));
    // No column is shaded, not a weekend and not today (Tom).
    BoxDecoration? fill(String key) =>
        tester.widget<Container>(find.byKey(ValueKey(key))).decoration
            as BoxDecoration?;
    expect(fill('calendar-day-2026-10-03')?.color, isNull);
    expect(fill('calendar-day-2026-10-05')?.color, isNull);
    expect(fill('calendar-today-column')?.color, isNull);
    // Today is still marked by its date pill and the now line.
    expect(find.byKey(const ValueKey('calendar-now-line')), findsOneWidget);
    expect(calHourMarks(day.width), isNot(contains(1)));
    expect(calHourMarks(270), [2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22]);
    expect(calHourMarks(120), [3, 6, 9, 12, 15, 18, 21]);
    expect(calHourMarks(48), [6, 12, 18]);
    // One line like the month pills, no phone icon, rounder (2026-10-05, Tom):
    // the "+1" (one person living with them) sits on the bar's middle line.
    expect(find.byIcon(Icons.phone_outlined), findsNothing);
    final lease = bar('lease:tenant-anh');
    final plus = find.descendant(of: lease, matching: find.text('+1'));
    expect(plus, findsOneWidget);
    expect(tester.getCenter(plus).dy, closeTo(tester.getCenter(lease).dy, 2));
    expect(calBarRadius, 12);

    await mountCalendar(
      tester,
      calendarService(Calls()),
      size: const Size(390, 844),
    );
    final phone = tester.getRect(_gridFinder);
    final phoneDay = tester.getSize(
      find.byKey(const ValueKey('calendar-today-column')),
    );
    expect(phoneDay.width, 432);
    expect(phone.width, lessThan(phoneDay.width));
    expect(tester.takeException(), isNull);
  });

  // 2026-10-09 (Tom): Tháng → Ngày was slow; the same months are not asked
  // for again, only another month is.
  testWidgets('back to the day view does not load the same months again', (
    tester,
  ) async {
    final calls = Calls();
    await mountCalendar(tester, calendarService(calls));
    final modes = find.byKey(const ValueKey('calendar-mode'));
    final before = calls.calendar.length;
    await tester.tap(find.descendant(of: modes, matching: find.text('Month')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: modes, matching: find.text('Day')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('calendar-grid')), findsOneWidget);
    expect(calls.calendar.length, before, reason: 'no new server call');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('calendar-month'))).data,
      'October 2026',
    );
    expect(tester.takeException(), isNull);
  });

  // 2026-10-10 (Tom): a 30-minute cleaning had only its name tag in the
  // month view; its bar (about 2 px) was dropped. It now has a small bar.
  testWidgets('a short cleaning still has a bar in the month view', (
    tester,
  ) async {
    final service = TeamService(
      transport: (name, data) async {
        if (name != 'calendarView') return <String, dynamic>{};
        final m = calendarFixture(
          data['from'] as String,
          to: data['to'] as String?,
        );
        final p = Map<String, dynamic>.from(
          (m['properties'] as List).first as Map,
        );
        p['bars'] = [
          ...(p['bars'] as List),
          {
            'id': 'cleaning:t9',
            'type': 'cleaning',
            'kind': 'cleaning',
            'roomId': 'r102',
            'start': '2026-10-07 09:00',
            'end': '2026-10-07 09:30',
            'status': 'planned',
            'taskStatus': 'planned',
            'recordId': 't9',
            'canOpen': true,
            'name': 'tom',
            'title': 'Don phong',
            'plannedStart': '2026-10-07 09:00',
            'plannedEnd': '2026-10-07 09:30',
          },
        ];
        return {
          ...m,
          'properties': [p, ...(m['properties'] as List).skip(1)],
        };
      },
    );
    await mountCalendar(tester, service);
    final modes = find.byKey(const ValueKey('calendar-mode'));
    await tester.tap(find.descendant(of: modes, matching: find.text('Month')));
    await tester.pumpAndSettle();
    final tag = find.byKey(
      const ValueKey('calendar-month-tag-cleaning:t9-2026-10-05'),
    );
    await tester.ensureVisible(tag);
    await tester.pumpAndSettle();
    final bar = find.byKey(
      const ValueKey('calendar-month-bar-cleaning:t9-2026-10-05'),
    );
    expect(bar, findsOneWidget);
    final pill = tester.getRect(bar), label = tester.getRect(tag);
    expect(pill.width, greaterThanOrEqualTo(9.5));
    // The bar starts at 09:00 of Wednesday (day 2 of the week, 0.375 in).
    final day = tester.getRect(
      find.byKey(const ValueKey('calendar-month-day-2026-10-07')),
    );
    expect(pill.left, inInclusiveRange(day.left, day.left + day.width * 0.5));
    // The name is in its tag right after the bar, on the same line.
    expect(label.left, greaterThanOrEqualTo(pill.right));
    expect(label.left - pill.right, lessThan(8));
    expect(label.center.dy, closeTo(pill.center.dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets("month view: every room's stays in a month grid", (tester) async {
    await mountCalendar(tester, calendarService(Calls()));
    // The toolbar's label (the month view also has a heading per month).
    String label() =>
        tester.widget<Text>(find.byKey(const ValueKey('calendar-month'))).data!;
    final modes = find.byKey(const ValueKey('calendar-mode'));
    expect(modes, findsOneWidget);
    await tester.tap(find.descendant(of: modes, matching: find.text('Month')));
    await tester.pumpAndSettle();
    expect(find.byType(CalMonthView), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-grid')), findsNothing);
    expect(label(), 'October 2026');
    // Past days are a clearly darker grey; days to come are white and
    // raised (2026-10-04, Tom). Today is 2 October in the fixture.
    Material cell(String ymd) => tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(ValueKey('calendar-month-day-$ymd')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(cell('2026-10-01').color, const Color(0xFFDDE1DD));
    expect(cell('2026-10-03').color, Colors.white);
    expect(cell('2026-10-03').elevation, greaterThan(0));
    expect(
      find.byKey(const ValueKey('calendar-month-head-2026-10-01')),
      findsOneWidget,
    );
    // Today's date is marked; stays are labelled with their room.
    expect(
      find.byKey(const ValueKey('calendar-month-day-2026-10-02')),
      findsOneWidget,
    );
    // Every week's piece says room · name and its status (2026-10-05, Tom:
    // no more moving the name while scrolling). b1 starts on 3/10 and goes
    // on into the next week: two pieces, two labels.
    expect(find.text('102 · Trần Văn Bình'), findsNWidgets(2));
    // The stay's status sits right after the room and name.
    final status = find.byKey(
      const ValueKey('calendar-month-status-booking:b1-2026-09-28'),
    );
    expect(status, findsOneWidget);
    expect(
      tester.getTopLeft(status).dx -
          tester.getTopRight(find.text('102 · Trần Văn Bình').first).dx,
      inInclusiveRange(0, 8),
    );
    expect(
      find.byKey(const ValueKey('calendar-month-status-booking:b1-2026-10-05')),
      findsOneWidget,
    );
    // The lease (from September, no end) is named on every week.
    expect(
      find.textContaining('Nguyễn Thị Minh Anh').evaluate().length,
      greaterThanOrEqualTo(5),
    );
    final monthScroll = find.byKey(const ValueKey('calendar-month-scroll'));
    final months = tester
        .widget<SingleChildScrollView>(monthScroll)
        .controller!;
    final at = months.offset;
    // The toolbar names the month filling most of the screen: with only a
    // strip of September left at the top, it says October.
    months.jumpTo(at - 60);
    await tester.pumpAndSettle();
    expect(label(), 'October 2026');
    months.jumpTo(at);
    await tester.pumpAndSettle();
    // A stay over a weekend goes on in the next week's row.
    final b1 = find.byKey(
      const ValueKey('calendar-month-bar-booking:b1-2026-10-05'),
    );
    expect(b1, findsOneWidget);
    expect(
      find.byKey(const ValueKey('calendar-month-bar-booking:b1-2026-09-28')),
      findsOneWidget,
    );
    // The paid part is solid, like the day view (2026-10-05, Tom): b1 is paid
    // to 4/10 06:00, part way into its first week and none of the next.
    double paidStop(String key) =>
        ((tester
                            .widget<Ink>(
                              find.byKey(ValueKey('calendar-month-fill-$key')),
                            )
                            .decoration
                        as BoxDecoration)
                    .gradient
                as LinearGradient)
            .stops![1];
    expect(paidStop('booking:b1-2026-09-28'), closeTo(0.47, 0.01));
    expect(paidStop('booking:b1-2026-10-05'), 0);
    expect(paidStop('booking:b3-2026-10-05'), 1);
    // The lease is paid to 15/10: three of the seven days of that week.
    expect(paidStop('lease:tenant-anh-2026-10-12'), closeTo(3 / 7, 0.01));
    // Tapping a stay opens it, like on the timeline.
    await tester.ensureVisible(b1);
    await tester.pumpAndSettle();
    await tester.tap(b1);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BookingWorkspaceScreen>(find.byType(BookingWorkspaceScreen))
          .initialRecordId,
      'b1',
    );
    await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
    await tester.pumpAndSettle();
    // A 3-hour stay is too narrow for its name: the name is in a tag right
    // after it, whole, and the tag opens the stay too.
    final hourly = find.byKey(
      const ValueKey('calendar-month-tag-booking:b4-2026-10-05'),
    );
    await tester.ensureVisible(hourly);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: hourly, matching: find.text('104 · Hourly')),
      findsOneWidget,
    );
    final pill = tester.getRect(
      find.byKey(const ValueKey('calendar-month-bar-booking:b4-2026-10-05')),
    );
    final tag = tester.getRect(hourly);
    expect(tag.left, greaterThanOrEqualTo(pill.right));
    expect(tag.left - pill.right, lessThan(8));
    expect(tag.center.dy, closeTo(pill.center.dy, 1));
    await tester.tap(hourly);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BookingWorkspaceScreen>(find.byType(BookingWorkspaceScreen))
          .initialRecordId,
      'b4',
    );
    await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
    await tester.pumpAndSettle();
    // Tapping a day (above its stays) offers a new stay from that date.
    final day = find.byKey(const ValueKey('calendar-month-day-2026-10-12'));
    await tester.ensureVisible(day);
    await tester.pumpAndSettle();
    final box = tester.getRect(day);
    await tester.tapAt(Offset(box.right - 12, box.top + 12));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('calendar-stay-short')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BookingWorkspaceScreen>(find.byType(BookingWorkspaceScreen))
          .initialStart,
      '2026-10-12 14:00',
    );
    await tester.tap(find.byKey(const ValueKey('calendar-dialog-close')));
    await tester.pumpAndSettle();
    // The month buttons and Today work in this view too. (The day tapped
    // above sits at the top of the screen, so November already fills most
    // of it: start again from today's month.)
    await tester.tap(find.byKey(const ValueKey('calendar-today')));
    await tester.pumpAndSettle();
    expect(label(), 'October 2026');
    await tester.tap(find.byKey(const ValueKey('calendar-next')));
    await tester.pumpAndSettle();
    expect(label(), 'November 2026');
    await tester.tap(find.byKey(const ValueKey('calendar-today')));
    await tester.pumpAndSettle();
    expect(label(), 'October 2026');
    // Back to days: today is on screen again.
    await tester.tap(find.descendant(of: modes, matching: find.text('Day')));
    await tester.pumpAndSettle();
    expect(find.byType(CalMonthView), findsNothing);
    expect(find.byKey(const ValueKey('calendar-today-column')), findsOneWidget);
    expect(label(), 'October 2026');
    expect(tester.takeException(), isNull);
  });

  testWidgets('month view fits a phone, in Vietnamese, with large text', (
    tester,
  ) async {
    for (final size in [const Size(320, 740), const Size(812, 375)]) {
      await mountCalendar(
        tester,
        calendarService(Calls()),
        language: 'vi',
        size: size,
        scale: 1.3,
      );
      final modes = find.byKey(const ValueKey('calendar-mode'));
      // Landscape: the one-line toolbar scrolls; the switch is at its end.
      await tester.ensureVisible(modes);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: modes, matching: find.text('Tháng')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CalMonthView), findsOneWidget, reason: '$size');
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });
}
