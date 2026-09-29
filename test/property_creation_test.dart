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
import 'room_booking_settings_test.dart' show enter;
import 'access_editor_test.dart' show choose;

Widget create(TeamService service, {String id = 'new-property'}) =>
    PropertyDetailsScreen(
      organizationId: 'preview',
      buildingId: id,
      service: service,
      create: true,
      onBack: () {},
    );
Future<void> fill(WidgetTester tester) async {
  await enter(tester, 'property-name', 'Riverside East');
  await enter(tester, 'property-address', '25 Nguyễn Văn Thoại, Đà Nẵng');
}

void main() {
  testWidgets('correcting the required timezone clears its validation error', (tester) async {
    final store = TeamPreviewStore();
    await mountReview(tester, create(store.service));
    await fill(tester);
    await enter(tester, 'property-timezone', '');
    await press(tester, 'Create property');
    await reveal(tester, find.text('Enter a value.'));
    expect(find.text('Enter a value.'), findsOneWidget);
    await enter(tester, 'property-timezone', 'UTC');
    await tester.pumpAndSettle();
    expect(find.text('Enter a value.'), findsNothing);
  });
  testWidgets(
    'empty workspace creates property, validates required fields and returns to editable details',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'manager';
      store.buildings.clear();
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
      );
      await press(tester, 'Create property');
      expect(find.text('Asia/Ho_Chi_Minh'), findsOneWidget);
      await press(tester, 'Create property');
      expect(store.buildings, isEmpty);
      await fill(tester);
      await enter(tester, 'property-timezone', '');
      await press(tester, 'Create property');
      expect(store.buildings, isEmpty);
      await enter(tester, 'property-timezone', 'America/New_York');
      await choose(tester, 'property-currency-VND', 'USD');
      await press(tester, 'Create property');
      expect(store.buildings.single['name'], 'Riverside East');
      expect(store.buildings.single['timeZone'], 'America/New_York');
      expect(store.buildings.single['currency'], 'USD');
      await enter(tester, 'property-name', 'Riverside renamed');
      await press(tester, 'Save property details');
      expect(store.buildings.single['name'], 'Riverside renamed');
      await press(
        tester,
        AppTranslations(const Locale('en'))['workspace_title'],
      );
      expect(find.text('Riverside renamed'), findsWidgets);
      expect(
        store.activity.where((a) => a['action'] == 'property_created').length,
        1,
      );
    },
  );

  testWidgets(
    'creation is hidden for scoped managers and non-managers, including direct entry',
    (tester) async {
      for (final role in [
        'manager',
        'owner',
        'administrator',
        'receptionist',
        'viewer',
      ]) {
        final store = TeamPreviewStore()..workspaceRole = role;
        store.assignedOnly = [
          'manager',
          'owner',
          'administrator',
        ].contains(role);
        await mountReview(
          tester,
          RoleWorkspace(
            key: UniqueKey(),
            organizationId: 'preview',
            service: store.service,
          ),
        );
        expect(find.text('Create property'), findsNothing);
        await mountReview(tester, create(store.service));
        expect(find.byKey(const ValueKey('property-name')), findsNothing);
      }
    },
  );

  testWidgets(
    'lost creation reply retries same intent; denial clears the form',
    (tester) async {
      final store = TeamPreviewStore();
      final calls = <Map<String, dynamic>>[];
      bool denied = false;
      final service = TeamService(
        transport: (name, data) async {
          if (denied) {
            throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'Revoked',
            );
          }
          if (data['action'] == 'create') {
            calls.add(Map.of(data));
            final result = await store.call(name, data);
            if (calls.length == 1) throw StateError('Lost reply');
            return result;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, create(service));
      await fill(tester);
      await press(tester, 'Create property');
      final t = AppTranslations(const Locale('en'));
      await press(tester, t['property_retry']);
      expect(calls.length, 2);
      expect(calls[0], calls[1]);
      expect(store.buildings.where((p) => p['id'] == 'new-property').length, 1);
      denied = true;
      await press(tester, t['property_save']);
      expect(find.byKey(const ValueKey('property-name')), findsNothing);
    },
  );

  testWidgets(
    'late creation result cannot replace a different property form and failed preparation reloads',
    (tester) async {
      final store = TeamPreviewStore();
      final pending = Completer<Map<String, dynamic>>();
      bool unavailable = false;
      final service = TeamService(
        transport: (name, data) async {
          if (unavailable) throw StateError('Offline');
          return data['action'] == 'create'
              ? pending.future
              : store.call(name, data);
        },
      );
      await mountReview(tester, create(service));
      await fill(tester);
      await reveal(tester, find.text('Create property').last);
      await tester.tap(find.widgetWithText(FilledButton, 'Create property'));
      await tester.pump();
      await mountReview(tester, create(service, id: 'different'));
      pending.complete({'buildingId': 'new-property'});
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, 'Create property'),
        findsOneWidget,
      );
      expect(find.text('Riverside East'), findsNothing);
      unavailable = true;
      await press(
        tester,
        AppTranslations(const Locale('en'))['property_reload'],
      );
      expect(find.byKey(const ValueKey('property-name')), findsNothing);
      unavailable = false;
      await press(
        tester,
        AppTranslations(const Locale('en'))['property_reload'],
      );
      expect(find.byKey(const ValueKey('property-name')), findsOneWidget);
    },
  );

  testWidgets(
    'populated creation form and validation fit languages screens scales and themes',
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
              store.buildings.first['name'] = 'Riverside — Khu căn hộ và khách sạn phía Đông thành phố Đà Nẵng';
              await mountReview(
                tester,
                RoleWorkspace(key: UniqueKey(), organizationId: 'preview', service: store.service),
                language: language,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await reveal(tester, find.widgetWithText(OutlinedButton, t['property_create']));
              expect(find.widgetWithText(OutlinedButton, t['property_create']).hitTestable(), findsOneWidget);
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('PROPERTY_CREATE_GOLDENS')) {
                await expectLater(find.byKey(const ValueKey('capture')), matchesGoldenFile('../.dart_tool/property-create-entry-$language-${size.width.toInt()}-$scale-${brightness.name}.png'));
              }
              await press(tester, t['property_create']);
              await enter(
                tester,
                'property-name',
                'Riverside — Khu căn hộ và khách sạn phía Đông thành phố Đà Nẵng',
              );
              await enter(
                tester,
                'property-address',
                'Tầng 12, số 123 đường Nguyễn Văn Thoại, phường Mỹ An, quận Ngũ Hành Sơn, thành phố Đà Nẵng',
              );
              await enter(tester, 'property-timezone', '');
              await press(tester, t['property_create']);
              await reveal(tester, find.text(t['property_required']));
              expect(
                find.text(t['property_required']).hitTestable(),
                findsOneWidget,
              );
              await enter(
                tester,
                'property-timezone',
                'America/Argentina/Buenos_Aires',
              );
              await reveal(
                tester,
                find.widgetWithText(FilledButton, t['property_create']),
              );
              expect(
                find
                    .widgetWithText(FilledButton, t['property_create'])
                    .hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('PROPERTY_CREATE_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/property-create-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
            }
          }
        }
      }
    },
  );
}
