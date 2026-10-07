import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_directory.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_details_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_booking_settings_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/utility_readings_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_service_fees_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'support/calendar_nav.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;

Widget editor(TeamService service, {String room = 'room-101'}) =>
    RoomDetailsScreen(
      organizationId: 'preview',
      buildingId: 'riverside',
      roomId: room,
      service: service,
      onBack: () {},
    );
Widget directory(TeamService service) => RoomDirectory(
  organizationId: 'preview',
  buildingId: 'riverside',
  service: service,
  onBack: () {},
);
Future<void> enter(WidgetTester tester, String field, String value) async {
  final finder = find.byKey(ValueKey('room-edit-$field'));
  await reveal(tester, finder);
  await tester.enterText(finder, value);
}

void main() {
  testWidgets(
    'correcting area clears the validation error before submitting again',
    (tester) async {
      final store = TeamPreviewStore();
      await mountReview(tester, editor(store.service));
      await enter(tester, 'area', '0');
      await press(tester, 'Save room details');
      expect(
        find.text('Enter an area above 0 and up to 100,000 m².'),
        findsOneWidget,
      );
      await enter(tester, 'area', '45.5');
      await tester.pumpAndSettle();
      expect(
        find.text('Enter an area above 0 and up to 100,000 m².'),
        findsNothing,
      );
    },
  );
  testWidgets(
    'manager edits room from workspace, validates input and sees saved directory; worker has no management',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'manager';
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
      );
      await openRoomDialog(tester, 'room-101');
      // The room's pages are chips in its dialog (2026-10-05, Tom); the
      // details page shows first, with the booking settings under it (no
      // separate "Cài đặt" chip).
      expect(find.byKey(const ValueKey('room-edit-number')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == 'RoomBookingSettingsScreen',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-room-room-101')),
        findsNothing,
      );
      await reveal(tester, find.byKey(const ValueKey('edit-room-room-101')));
      await tester.tap(find.byKey(const ValueKey('edit-room-room-101')));
      await tester.pumpAndSettle();
      await enter(tester, 'number', '');
      await enter(tester, 'area', '0');
      await press(tester, 'Save room details');
      expect(find.text('Enter a value.'), findsOneWidget);
      expect(store.rooms.first['area'], 45.5);
      await enter(tester, 'number', '102');
      // A comma is only a thousands mark (2026-10-05): "52,75" is refused,
      // not read as 52.75.
      await enter(tester, 'area', '52,75');
      await press(tester, 'Save room details');
      expect(
        find.text('Enter an area above 0 and up to 100,000 m².'),
        findsOneWidget,
      );
      await enter(tester, 'area', '52.75');
      await press(tester, 'Save room details');
      expect(find.textContaining('already uses'), findsOneWidget);
      await enter(tester, 'number', 'Family 201');
      await enter(tester, 'type', 'Family suite');
      await press(tester, 'Save room details');
      expect(store.rooms.first['area'], 52.75);
      expect(find.text('Room details saved.'), findsOneWidget);
      // The details are a page of the room dialog (2026-10-05): no "Back".
      expect(find.text('Family 201'), findsWidgets);
      expect(find.text('Family suite'), findsOneWidget);
      store.workspaceRole = 'housekeeper';
      await mountReview(
        tester,
        RoleWorkspace(
          key: UniqueKey(),
          organizationId: 'preview',
          service: store.service,
        ),
      );
      expect(find.text('Manage rooms'), findsNothing);
    },
  );
  testWidgets(
    'uncertain updates reuse intent, conflicts require reload and denied access clears room data',
    (tester) async {
      final store = TeamPreviewStore();
      final calls = <Map<String, dynamic>>[];
      String? error;
      final service = TeamService(
        transport: (name, data) async {
          if (error != null) {
            throw FirebaseFunctionsException(code: error, message: 'test');
          }
          if (data['action'] == 'update') {
            calls.add(Map.of(data));
            final result = await store.call(name, data);
            if (calls.length == 1) throw StateError('lost response');
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, editor(service));
      await press(tester, 'Save room details');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('room-edit-number')),
            )
            .enabled,
        isFalse,
      );
      await press(tester, 'Retry the same room change');
      expect(calls[0], calls[1]);
      error = 'aborted';
      await press(tester, 'Save room details');
      expect(find.textContaining('Copy any edits'), findsOneWidget);
      expect(find.text('Save room details'), findsNothing);
      error = null;
      await press(tester, 'Reload room details');
      error = 'permission-denied';
      await press(tester, 'Save room details');
      expect(find.byKey(const ValueKey('room-edit-number')), findsNothing);
    },
  );
  testWidgets(
    'changing rooms during pending save ignores late results and enables the next room',
    (tester) async {
      final store = TeamPreviewStore(),
          pending = Completer<Map<String, dynamic>>();
      final service = TeamService(
        transport: (name, data) async => data['action'] == 'update'
            ? pending.future
            : store.call(name, data),
      );
      await mountReview(tester, editor(service));
      await reveal(tester, find.text('Save room details'));
      await tester.tap(find.text('Save room details'));
      await tester.pump();
      await mountReview(tester, editor(service, room: 'room-102'));
      expect(find.text('102'), findsOneWidget);
      pending.complete({});
      await tester.pumpAndSettle();
      expect(find.text('102'), findsOneWidget);
      expect(find.text('Room details saved.'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save room details'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
  testWidgets(
    'directory paginates, clears inaccessible rows and recovers to empty state',
    (tester) async {
      final store = TeamPreviewStore();
      bool denied = false, empty = false;
      final service = TeamService(
        transport: (name, data) async {
          if (denied) throw StateError('denied');
          if (data['view'] == 'rooms') {
            return {
              'records': empty
                  ? []
                  : [store.rooms[data['cursor'] == null ? 0 : 1]],
              'nextCursor': !empty && data['cursor'] == null ? 'next' : null,
            };
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, directory(service));
      expect(find.text('102'), findsNothing);
      await press(
        tester,
        AppTranslations(const Locale('en'))['workspace_more'],
      );
      expect(find.text('102'), findsOneWidget);
      denied = true;
      await press(tester, 'Refresh');
      expect(find.text('102'), findsNothing);
      expect(find.textContaining('Check your access'), findsOneWidget);
      denied = false;
      empty = true;
      await press(tester, 'Refresh');
      expect(find.text('No rooms found in this property.'), findsOneWidget);
    },
  );
  testWidgets(
    'populated directory and editor fit languages orientations text scales and themes',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final language in ['en', 'vi']) {
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 1000),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final brightness in Brightness.values) {
              final store = TeamPreviewStore();
              final t = AppTranslations(Locale(language));
              store.rooms.first['roomNumber'] =
                  'Phòng gia đình Riverside — tầng mười hai, hướng sông Hàn';
              store.rooms.first['roomType'] =
                  'Căn hộ gia đình hai phòng ngủ với ban công rộng hướng sông và khu sinh hoạt chung';
              await mountReview(
                tester,
                directory(store.service),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              final edit = find.byKey(const ValueKey('edit-room-room-101'));
              await reveal(tester, edit);
              expect(edit.hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('ROOM_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/room-list-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await tester.tap(edit);
              await tester.pumpAndSettle();
              await enter(tester, 'area', '0');
              await press(tester, t['room_edit_save']);
              await reveal(tester, find.text(t['room_edit_area_invalid']));
              expect(
                find.text(t['room_edit_area_invalid']).hitTestable(),
                findsOneWidget,
              );
              await enter(tester, 'area', '45.5');
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              await reveal(tester, find.text(t['room_edit_save']));
              expect(
                find.text(t['room_edit_save']).hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('ROOM_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/room-edit-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
            }
          }
        }
      }
    },
  );
  test('room links name the open page and keep older bare room IDs', () {
    expect(roomLink('utilities', 'room-101'), 'utilities--room-101');
    expect(roomLinkView('utilities--room-101'), 'utilities');
    expect(roomLinkRoom('utilities--room-101'), 'room-101');
    expect(roomLinkView('settings--a_b-c'), 'settings');
    expect(roomLinkView('fees--room-101'), 'fees');
    expect(roomLinkRoom('rates--x'), 'x');
    // Older links and odd values open the room details.
    expect(roomLinkView('room-101'), isNull);
    expect(roomLinkRoom('room-101'), 'room-101');
    expect(roomLinkView('utilities--'), isNull);
    expect(roomLink('utilities', 'r' * 120), isNull);
  });
  for (final (link, screen) in [
    ('utilities--room-101', UtilityReadingsScreen),
    ('fees--room-101', RoomServiceFeesScreen),
    ('settings--room-101', RoomBookingSettingsScreen),
    ('room-101', RoomDetailsScreen),
  ]) {
    testWidgets(
      'a room link $link reopens the same page and keeps its address',
      (tester) async {
        final store = TeamPreviewStore();
        final reported = <String?>[];
        await mountReview(
          tester,
          RoomDirectory(
            organizationId: 'preview',
            buildingId: 'riverside',
            service: store.service,
            initialRecordId: link,
            onRecordChanged: reported.add,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget);
        if (screen != RoomDetailsScreen) {
          expect(find.byType(RoomDetailsScreen), findsNothing);
        }
        expect(reported.last, link);
      },
    );
  }
  // The Rooms section and its addresses were removed (rooms open from the
  // calendar, 2026-10-03); room pages are covered by the link tests above.
}
