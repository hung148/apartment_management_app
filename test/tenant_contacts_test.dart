import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_contacts_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'staff_editor_test.dart' show openSection;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;

Widget page(TeamService s, {String building = 'riverside'}) =>
    TenantContactsScreen(
      organizationId: 'preview',
      buildingId: building,
      service: s,
      onBack: () {},
    );
Future<void> open(WidgetTester tester, String id) async {
  final f = find.byKey(ValueKey('tenant-contact-$id'));
  await reveal(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'manager edits active and former tenant contact from workspace without changing lease data',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'manager';
      store.tenants.first.addAll({'monthlyRent': 200, 'deposit': 500});
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
      );
      await openSection(tester, 'tenants');
      await open(tester, 'tenant-anh');
      await enter(tester, 'tenant-contact-name', 'Updated name');
      await enter(tester, 'tenant-contact-phone', '+84 900 111');
      await press(tester, 'Save contact');
      // Saving reloads the page; no "Reload contact" next to it (2026-10-04).
      expect(find.text('Reload contact'), findsNothing);
      // The name is in the page header and in the edit box.
      expect(find.text('Updated name'), findsWidgets);
      expect(store.tenants.first['monthlyRent'], 200);
      expect(store.tenants.first['deposit'], 500);
      await press(tester, 'Tenants');
      await open(tester, 'tenant-linh');
      await enter(tester, 'tenant-contact-name', 'Former tenant');
      await press(tester, 'Save contact');
      expect(store.tenants.last['status'], 'moveOut');
      await tester.pumpWidget(const SizedBox.shrink());
      store.workspaceRole = 'receptionist';
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
      );
      expect(find.text('Tenants'), findsNothing);
    },
  );
  testWidgets(
    'empty invalid name sends nothing, lost reply retries exactly, stale and revoked writes cannot continue',
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
            calls.add(data);
            final r = await store.call(name, data);
            if (calls.length == 1) throw StateError('lost');
            return r;
          }
          return store.call(name, data);
        },
      );
      await mountReview(tester, page(service));
      await open(tester, 'tenant-anh');
      await enter(tester, 'tenant-contact-name', '');
      await press(tester, 'Save contact');
      expect(calls, isEmpty);
      await enter(tester, 'tenant-contact-name', 'Valid name');
      await press(tester, 'Save contact');
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('tenant-contact-name')),
            )
            .enabled,
        isFalse,
      );
      await press(tester, 'Retry the same contact change');
      expect(calls, hasLength(2));
      expect(calls[0], calls[1]);
      error = 'aborted';
      await press(tester, 'Save contact');
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save contact'),
            )
            .onPressed,
        isNull,
      );
      error = null;
      await press(tester, 'Reload contact');
      error = 'permission-denied';
      await press(tester, 'Save contact');
      expect(find.text('Valid name'), findsNothing);
      expect(find.byKey(const ValueKey('tenant-contact-name')), findsNothing);
    },
  );
  testWidgets(
    'pagination clears all rows on denial and refresh supports empty state',
    (tester) async {
      final store = TeamPreviewStore();
      store.tenants.clear();
      store.tenants.addAll(
        List.generate(
          27,
          (i) => {
            'id': 't${i.toString().padLeft(2, '0')}',
            'buildingId': 'riverside',
            'roomId': 'room',
            'fullName': 'Tenant $i',
            'phoneNumber': '',
            'status': 'active',
            'revision': '1:0',
          },
        ),
      );
      await mountReview(tester, page(store.service));
      await press(tester, 'Load more tenants');
      expect(find.text('Tenant 26'), findsOneWidget);
      expect(find.text('Load more tenants'), findsNothing);
      store.workspaceRole = 'housekeeper';
      await press(tester, 'Refresh tenants');
      expect(find.byType(Card), findsNothing);
      store.workspaceRole = 'owner';
      store.tenants.clear();
      await press(tester, 'Refresh tenants');
      expect(find.text('No tenants in this property.'), findsOneWidget);
    },
  );
  testWidgets('late reads cannot expose tenants from a previous property', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    final service = TeamService(
      transport: (name, data) async => data['buildingId'] == 'riverside'
          ? pending.future
          : {'records': [], 'nextCursor': null},
    );
    await mountReview(tester, page(service), settle: false);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await mountReview(tester, page(service, building: 'other'));
    pending.complete({
      'records': [
        {'id': 'old', 'fullName': 'Private old data'},
      ],
      'nextCursor': null,
    });
    await tester.pumpAndSettle();
    expect(find.text('Private old data'), findsNothing);
  });
  testWidgets(
    'populated directory and contact errors remain readable across locales screens text scales themes',
    (tester) async {
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
            for (final brightness in Brightness.values) {
              final store = TeamPreviewStore();
              store.tenants.first['fullName'] =
                  'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông, căn hộ hướng sông';
              final t = AppTranslations(Locale(lang));
              await mountReview(
                tester,
                page(store.service),
                language: lang,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await reveal(
                tester,
                find.byKey(const ValueKey('tenant-contact-tenant-anh')),
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('TENANT_CONTACT_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/tenant-list-$lang-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await open(tester, 'tenant-anh');
              await enter(tester, 'tenant-contact-phone', 'x' * 81);
              await press(tester, t['tenant_contacts_save']);
              await reveal(tester, find.text(t['tenant_contacts_long']));
              expect(
                find.text(t['tenant_contacts_long']).hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('TENANT_CONTACT_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/tenant-contact-$lang-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await enter(tester, 'tenant-contact-phone', '0901234567');
              await press(tester, t['tenant_contacts_save']);
              expect(store.tenants.first['phoneNumber'], '0901234567');
            }
          }
        }
      }
    },
  );
}
