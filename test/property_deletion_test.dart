import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/property_details_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;

Widget page(
  TeamService service, {
  String id = 'garden',
  bool canDelete = true,
}) => PropertyDetailsScreen(
  organizationId: 'preview',
  buildingId: id,
  service: service,
  canDelete: canDelete,
  onBack: () {},
);
void main() {
  testWidgets(
    'confirmation can cancel; deletion succeeds once and leaves an audit event',
    (tester) async {
      final store = TeamPreviewStore();
      await mountReview(tester, page(store.service));
      await press(tester, 'Delete empty property');
      await press(tester, 'Keep property');
      expect(store.buildings.any((p) => p['id'] == 'garden'), isTrue);
      await press(tester, 'Delete empty property');
      await press(tester, 'Confirm deletion');
      expect(store.buildings.any((p) => p['id'] == 'garden'), isFalse);
      expect(find.byKey(const ValueKey('property-name')), findsNothing);
      expect(
        store.activity.where((a) => a['action'] == 'property_deleted').length,
        1,
      );
    },
  );
  testWidgets('nonempty properties remain; manager has no deletion action', (
    tester,
  ) async {
    final store = TeamPreviewStore();
    await mountReview(tester, page(store.service, id: 'riverside'));
    await press(tester, 'Delete empty property');
    await press(tester, 'Confirm deletion');
    await reveal(tester, find.textContaining('historical records'));
    expect(find.textContaining('historical records'), findsOneWidget);
    expect(store.buildings.length, 2);
    store.workspaceRole = 'manager';
    await mountReview(
      tester,
      RoleWorkspace(organizationId: 'preview', service: store.service),
    );
    await press(tester, 'Property details');
    expect(find.text('Delete empty property'), findsNothing);
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
      await press(tester, 'Delete empty property');
      await press(tester, 'Confirm deletion');
      await press(tester, 'Retry the same deletion');
      expect(sent.length, 2);
      expect(sent[0], sent[1]);
      expect(
        store.activity.where((a) => a['action'] == 'property_deleted').length,
        1,
      );
      await mountReview(tester, page(service, id: 'riverside'));
      await press(tester, 'Delete empty property');
      denied = true;
      await press(tester, 'Confirm deletion');
      expect(find.byKey(const ValueKey('property-name')), findsNothing);
    },
  );
  testWidgets(
    'stale deletion requires reload and late result cannot clear another property',
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
      await press(tester, 'Delete empty property');
      await press(tester, 'Confirm deletion');
      expect(find.text('Delete empty property'), findsNothing);
      await press(tester, 'Reload property details');
      stale = false;
      await press(tester, 'Delete empty property');
      await reveal(tester, find.text('Confirm deletion'));
      await tester.tap(find.text('Confirm deletion'));
      await tester.pump();
      await mountReview(tester, page(service, id: 'riverside'));
      pending.complete({'deleted': true});
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('property-name')), findsOneWidget);
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
            store.buildings.last['name'] =
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
            await press(tester, t['property_delete']);
            await reveal(tester, find.text(t['property_delete_hint']));
            expect(tester.takeException(), isNull);
            await reveal(tester, find.text(t['property_delete_confirm']));
            expect(
              find.text(t['property_delete_confirm']).hitTestable(),
              findsOneWidget,
            );
            await reveal(tester, find.text(t['property_delete_cancel']));
            expect(
              find.text(t['property_delete_cancel']).hitTestable(),
              findsOneWidget,
            );
            if (const bool.fromEnvironment('DELETE_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  '../.dart_tool/property-delete-$lang-${size.width.toInt()}-$scale-${theme.name}.png',
                ),
              );
            }
            await press(tester, t['property_delete_cancel']);
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
  });
}
