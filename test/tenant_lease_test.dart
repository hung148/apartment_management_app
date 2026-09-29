import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_lease_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/tenant_contacts_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'room_booking_settings_test.dart' show enter;

TeamPreviewStore store() =>
    TeamPreviewStore()..buildings.first['timeZone'] = 'Asia/Ho_Chi_Minh';
Widget page(TeamService s, {String building = 'riverside'}) =>
    TenantLeaseScreen(
      organizationId: 'preview',
      buildingId: building,
      service: s,
      onBack: () {},
    );
Future<void> room(WidgetTester tester, String id) async {
  final f = find.byKey(ValueKey('lease-room-$id'));
  await reveal(tester, f);
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, {String date = '2026-09-27'}) async {
  await enter(
    tester,
    'lease-name',
    'Nguyễn Thị Minh Anh — gia đình Riverside phía Đông',
  );
  await enter(tester, 'lease-phone', '0901234567');
  await enter(tester, 'lease-start', date);
  await enter(tester, 'lease-rent', '1500000');
}

void main() {
  testWidgets(
    'directory starts lease, validates past reason and returns new contact without collecting money',
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
      await press(tester, 'Add tenant / Start lease');
      await room(tester, 'room-102');
      await fill(tester, date: '2026-09-26');
      await press(tester, 'Create tenant and lease');
      expect(s.tenants.length, 2);
      expect(find.text('Enter a name.'), findsNothing);
      await enter(tester, 'lease-reason', 'Existing lease import');
      await press(tester, 'Create tenant and lease');
      expect(s.tenants.length, 3);
      expect(s.tenants.last['monthlyRentMinor'], 1500000);
      expect(s.tenants.last['isMainTenant'], true);
      expect(s.tenants.last.containsKey('deposit'), false);
      await press(tester, 'Tenants');
      expect(find.text(s.tenants.last['fullName'] as String), findsOneWidget);
    },
  );
  testWidgets(
    'manager cannot backdate, conflicts recover and uncertain reply freezes exact retry',
    (tester) async {
      final s = store()..workspaceRole = 'manager';
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (name, d) async {
          if (name == 'tenantLeases' && d['action'] == 'create') {
            calls.add(Map.of(d));
            final r = await s.call(name, d);
            if (calls.length == 2) throw StateError('lost reply');
            return r;
          }
          return s.call(name, d);
        },
      );
      await mountReview(tester, page(service));
      await room(tester, 'room-101');
      await fill(tester, date: '2026-09-26');
      await press(tester, 'Create tenant and lease');
      expect(calls, isEmpty);
      await enter(tester, 'lease-start', '2026-09-27');
      await press(tester, 'Create tenant and lease');
      expect(calls.length, 1);
      expect(
        find.text(AppTranslations(const Locale('en'))['lease_form_occupied']),
        findsOneWidget,
      );
      await press(tester, 'Choose another room');
      await room(tester, 'room-102');
      await press(tester, 'Create tenant and lease');
      expect(s.tenants.length, 3);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('lease-name')))
            .enabled,
        false,
      );
      await press(tester, 'Retry the same lease creation');
      expect(calls.length, 3);
      expect(calls[1], calls[2]);
      expect(s.tenants.length, 3);
    },
  );
  testWidgets(
    'empty rooms, timezone error, denied reads and late property response',
    (tester) async {
      final s = TeamPreviewStore();
      await mountReview(tester, page(s.service));
      await room(tester, 'room-102');
      expect(
        find.text(
          AppTranslations(const Locale('en'))['lease_form_timezone_required'],
        ),
        findsOneWidget,
      );
      s.buildings.first['timeZone'] = 'UTC';
      await press(tester, 'Reload room settings');
      expect(find.byKey(const ValueKey('lease-name')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      final pending = Completer<Map<String, dynamic>>();
      final service = TeamService(
        transport: (name, d) async {
          if (d['buildingId'] == 'riverside') return pending.future;
          return {'records': [], 'nextCursor': null};
        },
      );
      await mountReview(tester, page(service), settle: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await mountReview(tester, page(service, building: 'garden'));
      pending.complete({
        'records': [
          {'id': 'late', 'roomNumber': 'Late room', 'monthly': true},
        ],
        'nextCursor': null,
      });
      await tester.pumpAndSettle();
      expect(find.textContaining('Late room'), findsNothing);
      expect(
        find.text(AppTranslations(const Locale('en'))['lease_form_empty']),
        findsOneWidget,
      );
      await mountReview(
        tester,
        page(
          TeamService(
            transport: (_, _) async => throw FirebaseFunctionsException(
              code: 'permission-denied',
              message: 'Denied',
            ),
          ),
        ),
      );
      expect(
        find.text(
          AppTranslations(const Locale('en'))['lease_form_unavailable'],
        ),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'room pagination and stale settings require reload; revoked save clears private form data',
    (tester) async {
      final s = store();
      s.rooms.clear();
      for (var i = 0; i < 27; i++) {
        s.rooms.add({
          'id': 'r${i.toString().padLeft(2, '0')}',
          'buildingId': 'riverside',
          'roomNumber': 'Room $i',
          'revision': '1:0',
        });
      }
      String? error;
      final service = TeamService(
        transport: (name, d) async {
          if (d['action'] == 'create' && error != null) {
            throw FirebaseFunctionsException(code: error, message: 'Changed');
          }
          return s.call(name, d);
        },
      );
      await mountReview(tester, page(service));
      await press(
        tester,
        AppTranslations(const Locale('en'))['tenant_contacts_more'],
      );
      await room(tester, 'r26');
      await fill(tester);
      error = 'aborted';
      await press(tester, 'Create tenant and lease');
      expect(find.byKey(const ValueKey('lease-name')), findsNothing);
      await press(tester, 'Reload room settings');
      expect(
        find.text('Nguyễn Thị Minh Anh — gia đình Riverside phía Đông'),
        findsOneWidget,
      );
      error = 'permission-denied';
      await press(tester, 'Create tenant and lease');
      expect(
        find.text('Nguyễn Thị Minh Anh — gia đình Riverside phía Đông'),
        findsNothing,
      );
      expect(s.tenants.length, 2);
    },
  );
  testWidgets(
    'populated lease forms support locales sizes themes enlarged text and reachable errors',
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
              s.rooms.last['roomNumber'] =
                  '102 — Phòng gia đình hướng sông Riverside phía Đông';
              final t = AppTranslations(Locale(lang));
              await mountReview(
                tester,
                page(s.service),
                language: lang,
                size: size,
                scale: scale,
                brightness: brightness,
              );
              await room(tester, 'room-102');
              await fill(tester, date: '2026-09-26');
              await enter(
                tester,
                'lease-reason',
                'Nhập hợp đồng hiện có — gia đình đã vào ở từ ngày hôm trước.',
              );
              if (const bool.fromEnvironment('TENANT_LEASE_GOLDENS')) {
                await reveal(tester, find.byKey(const ValueKey('lease-name')));
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/tenant-lease-name-$lang-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await enter(tester, 'lease-rent', '12.345');
              await press(tester, t['lease_form_save']);
              await reveal(tester, find.text(t['lease_form_invalid_rent']));
              expect(
                find.text(t['lease_form_invalid_rent']).hitTestable(),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
              if (const bool.fromEnvironment('TENANT_LEASE_GOLDENS')) {
                await expectLater(
                  find.byKey(const ValueKey('capture')),
                  matchesGoldenFile(
                    '../.dart_tool/tenant-lease-$lang-${size.width.toInt()}-$scale-${brightness.name}.png',
                  ),
                );
              }
              await enter(tester, 'lease-rent', '1500000');
              await press(tester, t['lease_form_save']);
              expect(s.tenants.length, 3);
              expect(tester.takeException(), isNull);
            }
          }
        }
      }
    },
  );
}
