import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_contacts_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_lease_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'tenant_lease_test.dart' show store;
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;

Widget page(TeamService s) => TenantLeaseScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  mainTenantId: 'tenant-anh',
  service: s,
  onBack: () {},
);
void main() {
  testWidgets(
    'directory adds linked roommate with no rent fields, validates parent date and backdate reason',
    (tester) async {
      final s = store();
      await mountReview(
        tester,
        TenantContactsScreen(
          organizationId: 'preview',
          buildingId: 'riverside',
          service: s.service,
          onBack: () {},
        ),
      );
      await press(tester, 'Add roommate');
      expect(find.byKey(const ValueKey('lease-rent')), findsNothing);
      expect(find.byKey(const ValueKey('lease-end')), findsNothing);
      await enter(tester, 'lease-name', 'New roommate');
      await enter(tester, 'lease-start', '2026-08-31');
      await enter(tester, 'lease-reason', 'Import');
      await press(tester, 'Create roommate');
      expect(s.tenants.length, 2);
      await enter(tester, 'lease-start', '2026-09-26');
      await enter(tester, 'lease-reason', '');
      await press(tester, 'Create roommate');
      expect(
        find.text('Enter a reason for the past move-in date.'),
        findsOneWidget,
      );
      expect(s.tenants.length, 2);
      await enter(tester, 'lease-reason', 'Existing occupant');
      await press(tester, 'Create roommate');
      expect(s.tenants.length, 3);
      expect(s.tenants.last['mainTenantId'], 'tenant-anh');
      expect(s.tenants.last['isMainTenant'], false);
      expect(s.tenants.last.containsKey('monthlyRent'), false);
      await press(tester, 'Tenants');
      expect(find.text('New roommate'), findsOneWidget);
      expect(
        find.byKey(ValueKey('add-roommate-${s.tenants.last['id']}')),
        findsNothing,
      );
    },
  );
  testWidgets(
    'manager backdate denied; exact lost reply retry and stale or revoked parent recover safely',
    (tester) async {
      final s = store()..workspaceRole = 'manager';
      final calls = <Map<String, dynamic>>[];
      String? error;
      final service = TeamService(
        transport: (name, d) async {
          if (d['action'] == 'create') {
            calls.add(Map.of(d));
            if (error != null) {
              throw FirebaseFunctionsException(code: error, message: 'Changed');
            }
            final r = await s.call(name, d);
            if (calls.length == 1) throw StateError('Lost reply');
            return r;
          }
          return s.call(name, d);
        },
      );
      await mountReview(tester, page(service));
      await enter(tester, 'lease-name', 'Roommate');
      await enter(tester, 'lease-start', '2026-09-26');
      await press(tester, 'Create roommate');
      expect(calls, isEmpty);
      await enter(tester, 'lease-start', '2026-09-27');
      await press(tester, 'Create roommate');
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('lease-name')))
            .enabled,
        false,
      );
      await press(tester, 'Retry the same roommate creation');
      expect(calls[0], calls[1]);
      expect(s.tenants.length, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      await mountReview(tester, page(service));
      await enter(tester, 'lease-name', 'Draft');
      error = 'aborted';
      await press(tester, 'Create roommate');
      expect(find.byKey(const ValueKey('lease-name')), findsNothing);
      await press(tester, 'Reload main tenancy');
      expect(find.text('Draft'), findsOneWidget);
      error = 'permission-denied';
      await press(tester, 'Create roommate');
      expect(find.text('Draft'), findsNothing);
    },
  );
  testWidgets(
    'populated roommate form and errors fit both languages themes sizes and text scales',
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
              final s = store();
              s.tenants.first['fullName'] =
                  'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông, căn hộ hướng sông';
              final t = AppTranslations(Locale(lang));
              await mountReview(
                tester,
                page(s.service),
                language: lang,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await enter(
                tester,
                'lease-name',
                'Trần Nguyễn Minh Khánh — người ở cùng gia đình Riverside',
              );
              await enter(tester, 'lease-phone', '0901234567');
              await enter(tester, 'lease-start', '2026-09-26');
              await press(tester, t['roommate_form_save']);
              await reveal(tester, find.text(t['lease_form_reason_required']));
              expect(tester.takeException(), isNull);
              expect(
                find.text(t['lease_form_reason_required']).hitTestable(),
                findsOneWidget,
              );
              if (const bool.fromEnvironment('ROOMMATE_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/roommate-$lang-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await enter(tester, 'lease-reason', 'Nhập người ở cùng hiện có');
              await press(tester, t['roommate_form_save']);
              expect(s.tenants.length, 3);
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );
}
