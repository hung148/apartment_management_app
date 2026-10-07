import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/team_access.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/org_location.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/org_shell.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/role_workspace.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/ws_ui.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'staff_editor_test.dart' show press, reveal, openSection;

Finder section(String id) => find.byKey(ValueKey('workspace-section-$id'));

void main() {
  testWidgets(
    'organization content pages adapt to locales sizes and large text',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      // Explicit compact button styles have no font family. Replace the test
      // engine's Ahem fallback with the app font for representative rendering.
      await (FontLoader(
        'Ahem',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final language in ['en', 'vi'])
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 1000),
        ])
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final entry in [
              ('staff', 'team'),
              ('staff', 'activity'),
              ('calendar', 'board'),
            ]) {
              final store = TeamPreviewStore()..addOperationalSamples();
              await mountReview(
                tester,
                RoleWorkspace(
                  key: UniqueKey(),
                  organizationId: 'preview',
                  service: store.service,
                  initial: OrgLocation(
                    'preview',
                    section: entry.$1,
                    page: entry.$2,
                    propertyId: 'riverside',
                  ),
                ),
                language: language,
                size: size,
                scale: scale,
              );
              final screen = {
                'team': 'TeamScreen',
                'activity': 'ActivityHistory',
                'tasks': 'HousekeepingScreen',
                'board': 'RoomCalendar',
              }[entry.$2];
              expect(
                find.byWidgetPredicate(
                  (widget) => widget.runtimeType.toString() == screen,
                ),
                findsOneWidget,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '$language $size $scale $entry',
              );
              if ((language == 'en' && size.width == 1440 && scale == 1) ||
                  (language == 'vi' && size.width == 320 && scale == 2)) {
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
                    '.dart_tool/organization-layout',
                  ).create(recursive: true);
                  await File(
                    '.dart_tool/organization-layout/$language-${size.width.toInt()}-$scale-${entry.$1}-${entry.$2}.png',
                  ).writeAsBytes(bytes!.buffer.asUint8List());
                  image.dispose();
                });
              }
            }
          }
    },
  );
  testWidgets(
    'organization pages fill desktop width and share one refresh control',
    (tester) async {
      final store = TeamPreviewStore()..addOperationalSamples();
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
        size: const Size(1440, 1000),
      );
      for (final entry in [
        ('staff', 'team'),
        ('staff', 'activity'),
        ('calendar', 'board'),
      ]) {
        await openSection(tester, entry.$1, page: entry.$2);
        final scroll = find
            .byType(Scrollable)
            .evaluate()
            .where(
              (e) =>
                  (e.widget as Scrollable).axisDirection == AxisDirection.down,
            );
        expect(scroll, isNotEmpty);
        expect(
          scroll
              .map((e) => (e.renderObject as RenderBox).size.width)
              .reduce((a, b) => a > b ? a : b),
          greaterThan(1300),
          reason: '${entry.$1}/${entry.$2}',
        );
        expect(
          find.byIcon(Icons.refresh),
          findsOneWidget,
          reason: '${entry.$1}/${entry.$2}',
        );
        expect(tester.takeException(), isNull);
      }
    },
  );
  test('organization addresses parse and print back the same', () {
    final full = OrgLocation.parse('/org/abc_1/rooms/layout?p=riverside');
    expect(
      full,
      const OrgLocation(
        'abc_1',
        section: 'rooms',
        page: 'layout',
        propertyId: 'riverside',
      ),
    );
    expect(full!.address, '/org/abc_1/rooms/layout?p=riverside');
    expect(OrgLocation.parse('/org/abc')!.address, '/org/abc');
    for (final bad in [
      '/dashboard',
      '/org',
      '/org/../x',
      '/org/a/b/c/d/e',
      '/org/a/r00m!',
      null,
    ]) {
      expect(OrgLocation.parse(bad), isNull, reason: '$bad');
    }
    // A malformed property is dropped, the rest of the address still works.
    expect(OrgLocation.parse('/org/a/rooms?p=../x')!.propertyId, isNull);
    // U1 step 2: one record (booking, room, tenant) after the page.
    final record = OrgLocation.parse('/org/a/rooms/list/room-101?p=riverside')!;
    expect(record.record, 'room-101');
    expect(record.address, '/org/a/rooms/list/room-101?p=riverside');
    expect(OrgLocation.parse('/org/a/rooms/list/bad!id'), isNull);
  });

  testWidgets(
    'a link to one room opens it; going back to the list updates the address',
    (tester) async {
      final store = TeamPreviewStore();
      final addresses = <String>[];
      await mountReview(
        tester,
        OrgShell(
          organizationId: 'preview',
          name: 'Riverside',
          service: store.service,
          initial: const OrgLocation(
            'preview',
            section: 'tenants',
            page: 'list',
            propertyId: 'riverside',
            record: 'tenant-anh',
          ),
        ),
        size: const Size(1440, 1000),
      );
      expect(find.byType(WsBack), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WsBack), findsNothing);
      expect(
        find.byKey(const ValueKey('tenant-contact-tenant-anh')),
        findsWidgets,
      );
      // Opening it again from the list keeps the record in the address.
      final workspace = RoleWorkspace(
        organizationId: 'preview',
        service: store.service,
        initial: const OrgLocation('preview', section: 'tenants', page: 'list'),
        onLocationChanged: (l) => addresses.add(l.address),
      );
      await mountReview(tester, workspace, size: const Size(1440, 1000));
      await tester.tap(find.byKey(const ValueKey('tenant-contact-tenant-anh')));
      await tester.pumpAndSettle();
      expect(
        addresses.last,
        '/org/preview/tenants/list/tenant-anh?p=riverside',
      );
    },
  );

  testWidgets(
    'receptionist records standalone payment through the Money section then sees refreshed balance',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = TeamPreviewStore()..workspaceRole = 'receptionist';
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
        size: const Size(1440, 1000),
      );
      await openSection(tester, 'money', page: 'payments');
      await press(tester, 'Record a payment or refund');
      expect(find.text('Refund payment'), findsNothing);
      await reveal(tester, find.byKey(const ValueKey('payment-amount')));
      await tester.enterText(
        find.byKey(const ValueKey('payment-amount')),
        '250000',
      );
      await press(tester, 'Confirm recording');
      expect(store.payment['paidAmount'], 750000);
      await press(tester, 'Back to payments');
      expect(find.textContaining('750,000'), findsOneWidget);
      expect(store.activity.last['action'], 'paymentCollect');
    },
  );

  testWidgets(
    'staff can open their own activity and profile without team administration',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'receptionist';
      store.addOperationalSamples();
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
        size: const Size(1440, 1000),
      );
      await openSection(tester, 'staff', page: 'activity');
      expect(find.textContaining('preview-receptionist'), findsWidgets);
      expect(find.textContaining('preview-manager'), findsNothing);
      await openSection(tester, 'staff', page: 'team');
      expect(
        find.text(AppTranslations(const Locale('en'))['team_profile']),
        findsWidgets,
      );
      expect(find.text('Account access review'), findsNothing);
      expect(find.text('an@example.com'), findsNothing);
    },
  );

  testWidgets('every role sees only the sections it may use', (tester) async {
    for (final role in TeamPolicy.templateIds) {
      final store = TeamPreviewStore()..workspaceRole = role;
      final access = TeamAccess.fromMap(TeamPreviewStore.grant(role));
      await mountReview(
        tester,
        RoleWorkspace(
          key: UniqueKey(),
          organizationId: 'preview',
          service: store.service,
        ),
        // Wide enough for all nine section tabs in the test font (Ahem is
        // wider than Roboto; real 1440 screens fit them).
        size: const Size(1920, 1000),
      );
      bool any(List<TeamPermission> p) => p.any(access.allows);
      final expected = {
        // 2026-10-05: cleaners too (cleaning only).
        'calendar': any([
          TeamPermission.readBookings,
          TeamPermission.createBookings,
          TeamPermission.manageLease,
          TeamPermission.manageProperty,
          TeamPermission.readAssignedTasks,
        ]),
        // 2026-10-04: bookings live on the calendar.
        'bookings': false,
        // Rooms open from the calendar now (2026-10-03); no section for anyone.
        'rooms': false,
        'tenants': any([TeamPermission.manageLease]),
        'money': any([
          TeamPermission.readFinancialReports,
          TeamPermission.collectPayments,
          TeamPermission.refundPayments,
        ]),
        // 2026-10-05: cleaning and problems are on the calendar for everyone.
        'cleaning': false,
        'problems': false,
        'staff':
            (access.allBuildings && access.allows(TeamPermission.manageTeam)) ||
            access.allows(TeamPermission.readOwnActivity),
      };
      for (final entry in expected.entries) {
        expect(
          section(entry.key),
          entry.value ? findsOneWidget : findsNothing,
          reason: '$role ${entry.key}',
        );
      }
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'switching property reloads the page for that property; lost access clears the workspace',
    (tester) async {
      var denied = false;
      final store = TeamPreviewStore();
      final reads = <String?>[];
      final service = TeamService(
        transport: (name, data) async {
          if (denied) throw StateError('revoked');
          if (name == 'readWorkspace' && data['view'] == 'financial') {
            reads.add(data['buildingId'] as String?);
          }
          return store.call(name, data);
        },
      );
      final addresses = <String>[];
      await mountReview(
        tester,
        RoleWorkspace(
          organizationId: 'preview',
          service: service,
          initial: const OrgLocation(
            'preview',
            section: 'money',
            page: 'financial',
          ),
          onLocationChanged: (l) => addresses.add(l.address),
        ),
        size: const Size(1440, 1000),
      );
      expect(reads, ['riverside']);
      expect(addresses.last, '/org/preview/money/financial?p=riverside');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Garden Homestay').last);
      await tester.pumpAndSettle();
      expect(reads, ['riverside', 'garden']);
      expect(addresses.last, '/org/preview/money/financial?p=garden');
      denied = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(section('money'), findsNothing);
      expect(
        find.text(AppTranslations(const Locale('en'))['workspace_denied']),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'an address for a page this role cannot use falls back to the first allowed one',
    (tester) async {
      final store = TeamPreviewStore()..workspaceRole = 'housekeeper';
      final addresses = <String>[];
      await mountReview(
        tester,
        RoleWorkspace(
          organizationId: 'preview',
          service: store.service,
          initial: const OrgLocation(
            'preview',
            section: 'money',
            page: 'financial',
            propertyId: 'nope',
          ),
          onLocationChanged: (l) => addresses.add(l.address),
        ),
        size: const Size(1440, 1000),
      );
      expect(addresses.last, isNot(contains('money')));
      expect(addresses.last, isNot(contains('nope')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'phone: up to five sections in the bottom bar, the rest under More',
    (tester) async {
      final store = TeamPreviewStore();
      await mountReview(
        tester,
        RoleWorkspace(organizationId: 'preview', service: store.service),
        size: const Size(360, 740),
      );
      // Settings actions now belong to Account; four main sections remain.
      for (final id in ['calendar', 'tenants', 'money', 'staff']) {
        expect(section(id), findsOneWidget, reason: id);
      }
      expect(section('more'), findsNothing);
      expect(section('settings'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Back inside a section goes one step back before leaving the organization',
    (tester) async {
      final store = TeamPreviewStore();
      await mountReview(
        tester,
        OrgShell(
          organizationId: 'preview',
          name: 'Riverside',
          service: store.service,
          initial: const OrgLocation(
            'preview',
            section: 'tenants',
            page: 'list',
          ),
        ),
        size: const Size(1440, 1000),
      );
      final row = find.byKey(const ValueKey('tenant-contact-tenant-anh'));
      await reveal(tester, row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(WsBack), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(WsBack), findsNothing);
      expect(
        find.byKey(const ValueKey('tenant-contact-tenant-anh')),
        findsWidgets,
      );
    },
  );

  testWidgets('populated workspace fits locales screens text scales and themes', (
    tester,
  ) async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final language in ['en', 'vi']) {
      final t = AppTranslations(Locale(language));
      for (final size in [
        const Size(320, 740),
        const Size(812, 375),
        const Size(1440, 1000),
      ]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          for (final brightness in Brightness.values) {
            final store = TeamPreviewStore()
              ..workspaceRole = 'manager'
              ..assignedOnly = true;
            store.buildings.first['name'] =
                'Riverside — Khu căn hộ và khách sạn phía Đông thành phố Đà Nẵng';
            await mountReview(
              tester,
              RoleWorkspace(
                key: UniqueKey(),
                organizationId: 'preview',
                service: store.service,
              ),
              language: language,
              size: size,
              scale: scale,
              brightness: brightness,
            );
            await openSection(tester, 'money', page: 'financial');
            await reveal(tester, find.textContaining(t['workspace_status']));
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('WORKSPACE_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('capture')),
                matchesGoldenFile(
                  '../.dart_tool/workspace-$language-${size.width.toInt()}-$scale-${brightness.name}-financial.png',
                ),
              );
            }
          }
        }
      }
    }
  });
}
