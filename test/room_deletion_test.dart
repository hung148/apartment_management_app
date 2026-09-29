import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/room_details_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;

Widget page(
  TeamService service, {
  String id = 'room-102',
  bool canDelete = true,
}) => RoomDetailsScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  roomId: id,
  service: service,
  canDelete: canDelete,
  onBack: () {},
);
void main() {
  testWidgets(
    'confirmation can cancel; deletion succeeds once and leaves an audit event',
    (tester) async {
      final store = TeamPreviewStore();
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
      );
      await press(tester, 'Manage rooms');
      final edit = find.byKey(const ValueKey('edit-room-room-102'));
      await reveal(tester, edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await press(tester, 'Delete empty room');
      await press(tester, 'Keep room');
      expect(store.rooms.any((p) => p['id'] == 'room-102'), isTrue);
      await press(tester, 'Delete empty room');
      await press(tester, 'Confirm room deletion');
      expect(store.rooms.any((p) => p['id'] == 'room-102'), isFalse);
      expect(find.byKey(const ValueKey('room-edit-number')), findsNothing);
      expect(
        store.activity.where((a) => a['action'] == 'room_deleted').length,
        1,
      );
      await press(tester, 'Manage rooms');
      expect(find.byKey(const ValueKey('edit-room-room-102')), findsNothing);
    },
  );
  testWidgets('nonempty rooms remain; manager has no deletion action', (
    tester,
  ) async {
    final store = TeamPreviewStore();
    await mountReview(tester, page(store.service, id: 'room-101'));
    await press(tester, 'Delete empty room');
    await press(tester, 'Confirm room deletion');
    await reveal(tester, find.textContaining('linked records'));
    expect(find.textContaining('linked records'), findsOneWidget);
    expect(store.rooms.length, 2);
    store.workspaceRole = 'manager';
    await mountReview(
      tester,
      RoleWorkspace(organizationId: 'preview', service: store.service),
    );
    await press(tester, 'Manage rooms');
    final edit = find.byKey(const ValueKey('edit-room-room-102'));
    await reveal(tester, edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Delete empty room'), findsNothing);
  });
  testWidgets(
    'lost deletion reply retries identically and revocation clears the form',
    (tester) async {
      final store = TeamPreviewStore();
      final sent = <Map<String, dynamic>>[];
      bool denied = false;
      final service = TeamService(
        transport: (name, data) async {
          if (denied) {
            throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'Revoked',
            );
          }
          if (data['action'] == 'delete') {
            sent.add(Map.of(data));
            final result = await store.call(name, data);
            if (sent.length == 1) {
              throw StateError('Lost');
            }
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await press(tester, 'Delete empty room');
      await press(tester, 'Confirm room deletion');
      await press(tester, 'Retry the same room deletion');
      expect(sent.length, 2);
      expect(sent[0], sent[1]);
      expect(
        store.activity.where((a) => a['action'] == 'room_deleted').length,
        1,
      );
      await mountReview(tester, page(service, id: 'room-101'));
      await press(tester, 'Delete empty room');
      denied = true;
      await press(tester, 'Confirm room deletion');
      expect(find.byKey(const ValueKey('room-edit-number')), findsNothing);
    },
  );
  testWidgets(
    'stale deletion requires reload and late result cannot clear another room',
    (tester) async {
      final store = TeamPreviewStore();
      final pending = Completer<Map<String, dynamic>>();
      bool stale = true;
      final service = TeamService(
        transport: (name, data) async {
          if (data['action'] == 'delete') {
            if (stale) {
              throw FirebaseFunctionsException(
                code: 'aborted',
                message: 'Changed',
              );
            }
            return pending.future;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await press(tester, 'Delete empty room');
      await press(tester, 'Confirm room deletion');
      expect(find.text('Delete empty room'), findsNothing);
      await press(tester, 'Reload room details');
      stale = false;
      await press(tester, 'Delete empty room');
      await reveal(tester, find.text('Confirm room deletion'));
      await tester.tap(find.text('Confirm room deletion'));
      await tester.pump();
      await mountReview(tester, page(service, id: 'room-101'));
      pending.complete({'deleted': true});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('room-edit-number')), findsOneWidget);
    },
  );
  testWidgets('deletion confirmation fits populated locales sizes scales themes', (
    tester,
  ) async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final lang in ['en', 'vi']) {
      for (final size in [
        const Size(320, 740),
        const Size(812, 375),
        const Size(1440, 1000),
      ]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          for (final theme in Brightness.values) {
            final store = TeamPreviewStore();
            store.rooms.last['roomNumber'] =
                'Riverside — Khu căn hộ và khách sạn phía Đông thành phố Đà Nẵng';
            final t = AppTranslations(Locale(lang));
            await mountReview(
              tester,
              page(store.service),
              language: lang,
              size: size,
              scale: scale,
              brightness: theme,
            );
            await press(tester, t['room_empty_delete']);
            await reveal(tester, find.text(t['room_delete_hint']));
            expect(tester.takeException(), isNull);
            await reveal(tester, find.text(t['room_empty_delete_confirm']));
            expect(
              find.text(t['room_empty_delete_confirm']).hitTestable(),
              findsOneWidget,
            );
            await reveal(tester, find.text(t['room_delete_cancel']));
            expect(
              find.text(t['room_delete_cancel']).hitTestable(),
              findsOneWidget,
            );
            if (const bool.fromEnvironment('ROOM_DELETE_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  '../.dart_tool/room-delete-$lang-${size.width.toInt()}-$scale-${theme.name}.png',
                ),
              );
            }
            await press(tester, t['room_delete_cancel']);
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });
}
