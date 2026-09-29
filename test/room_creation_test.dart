import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_details_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal;
import 'room_directory_test.dart' show directory, enter;

Widget create(
  TeamService service, {
  String building = 'riverside',
  String id = 'new',
}) => RoomDetailsScreen(
  organizationId: 'preview',
  buildingId: building,
  roomId: id,
  create: true,
  service: service,
  onBack: () {},
);
Future<void> fill(WidgetTester tester, {String number = '201'}) async {
  await enter(tester, 'number', number);
  await enter(tester, 'type', 'Family suite');
  await enter(tester, 'area', '52,75');
}

void main() {
  testWidgets(
    'create from empty directory validates, inherits currency and returns a room that can be edited',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'manager';
      store.rooms.clear();
      store.buildings.first['currency'] = 'USD';
      await mountReview(tester, directory(store.service));
      await press(tester, 'Add room');
      expect(find.textContaining('USD'), findsOneWidget);
      await press(tester, 'Create room');
      expect(store.rooms, isEmpty);
      await fill(tester);
      await press(tester, 'Create room');
      expect(store.rooms.length, 1);
      expect(store.rooms.single['area'], 52.75);
      expect(store.rooms.single['currency'], 'USD');
      expect(store.rooms.single['rentalMode'], 'monthly');
      expect(find.text('Create room'), findsNothing);
      expect(find.text('Room details saved.'), findsOneWidget);
      await enter(tester, 'number', '202');
      await press(tester, 'Save room details');
      expect(store.rooms.single['roomNumber'], '202');
      await press(tester, 'Manage rooms');
      expect(find.text('202'), findsOneWidget);
      expect(
        store.activity.where((a) => a['action'] == 'room_created').length,
        1,
      );
    },
  );
  testWidgets(
    'duplicate create is recoverable and lost reply reuses the room ID and operation',
    (tester) async {
      final store = TeamPreviewStore();
      final calls = <Map<String, dynamic>>[];
      bool lose = true;
      final service = TeamService(
        transport: (name, data) async {
          if (data['action'] == 'create') {
            calls.add(Map.of(data));
            final result = await store.call(name, data);
            if (lose) {
              lose = false;
              throw StateError('lost response');
            }
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, create(service));
      await fill(tester, number: '102');
      await press(tester, 'Create room');
      expect(find.textContaining('already uses'), findsOneWidget);
      expect(store.rooms.length, 2);
      await enter(tester, 'number', '201');
      await press(tester, 'Create room');
      expect(store.rooms.length, 3);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('room-edit-number')),
            )
            .enabled,
        isFalse,
      );
      await press(tester, 'Retry the same room change');
      expect(calls[1], calls[2]);
      expect(store.rooms.length, 3);
      expect(
        store.activity.where((a) => a['action'] == 'room_created').length,
        1,
      );
    },
  );
  testWidgets(
    'creation access loss clears fields; switching properties ignores late creation results',
    (tester) async {
      final store = TeamPreviewStore();
      bool denied = false;
      final pending = Completer<Map<String, dynamic>>();
      final service = TeamService(
        transport: (name, data) async {
          if (denied) {
            throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'revoked',
            );
          }
          if (data['action'] == 'create') return pending.future;
          return store.call(name, data);
        },
      );
      await mountReview(tester, create(service));
      await fill(tester);
      await reveal(tester, find.text('Create room'));
      await tester.tap(find.text('Create room'));
      await tester.pump();
      await mountReview(
        tester,
        create(service, building: 'garden', id: 'garden-new'),
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('room-edit-number')),
            )
            .controller!
            .text,
        isEmpty,
      );
      pending.complete({});
      await tester.pumpAndSettle();
      expect(find.text('Room details saved.'), findsNothing);
      await fill(tester);
      denied = true;
      await press(tester, 'Create room');
      expect(find.byKey(const ValueKey('room-edit-number')), findsNothing);
      expect(find.textContaining('Check your access'), findsOneWidget);
      denied = false;
      await press(tester, 'Reload room details');
      expect(find.byKey(const ValueKey('room-edit-number')), findsOneWidget);
    },
  );
  testWidgets('create form and defaults fit locales sizes text scales and themes', (
    tester,
  ) async {
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
            await mountReview(
              tester,
              create(store.service),
              language: language,
              size: size,
              scale: scale,
              brightness: brightness,
            );
            await reveal(tester, find.textContaining(t['room_create_info']));
            expect(
              find.textContaining(t['room_create_info']).hitTestable(),
              findsOneWidget,
            );
            if (const bool.fromEnvironment('CREATE_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  '../.dart_tool/create-info-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                ),
              );
            }
            await fill(
              tester,
              number: 'Phòng gia đình Riverside — tầng mười hai hướng sông Hàn',
            );
            await enter(
              tester,
              'type',
              'Căn hộ gia đình hai phòng ngủ với ban công rộng hướng sông và khu sinh hoạt chung',
            );
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.pumpAndSettle();
            await reveal(tester, find.text(t['room_create_save']));
            expect(
              find.text(t['room_create_save']).hitTestable(),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('CREATE_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  '../.dart_tool/create-form-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                ),
              );
            }
          }
        }
      }
    }
  });
}
