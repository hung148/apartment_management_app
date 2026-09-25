import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/membership_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/organizations/tenants/tenant_tab.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/suggested_text_field.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/searchable_select_field.dart';
import 'calendar_screen_test.dart'
    show RoomsFake, BuildingsFake, TenantsFake, ThemeOrganizationsFake;
import 'ai_import_test.dart' show AuthFake;

class EditableTenantFake extends TenantsFake {
  Map<String, dynamic>? update;
  String? reason;
  List<String>? moved;
  EditableTenantFake() {
    entries = [
      Tenant(
        id: 'tenant',
        organizationId: 'o',
        buildingId: 'b',
        roomId: 'r',
        status: TenantStatus.active,
        fullName: 'Nguyễn Thị Mai',
        phoneNumber: '0901234567',
        apartmentType: 'Family Studio',
        moveInDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026),
        monthlyRent: 5000000,
      ),
    ];
  }
  @override
  Future<bool> updateTenant(String id, Map<String, dynamic> data) async {
    update = data;
    return true;
  }

  @override
  Future<bool> markTenantAsMovedOut(
    String id, {
    DateTime? moveOutDate,
    String? moveOutReason,
    String? newBuildingName,
    String? newBuildingAddress,
    String? newRoomNumber,
  }) async {
    reason = moveOutReason;
    return true;
  }

  @override
  Future<bool> moveTenantToRoom(
    String id,
    String building,
    String room, {
    String? moveOutReason,
  }) async {
    moved = [building, room];
    return true;
  }
}

class EditableOrgFake extends ThemeOrganizationsFake {
  @override
  Future<Membership?> getUserMembership(String user, String org) async =>
      Membership(
        id: 'admin',
        organizationId: org,
        ownerId: user,
        role: 'admin',
        status: 'active',
        joinedAt: DateTime(2026),
      );
}

Future<void> pumpTenants(
  WidgetTester tester,
  EditableTenantFake service, {
  Size size = const Size(1440, 1100),
  String language = 'en',
  double scale = 1,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('vi')],
      theme: ThemeData(fontFamily: 'Roboto'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(
          key: const ValueKey('tenant-capture'),
          child: child!,
        ),
      ),
      localizationsDelegates: const [
        AppTranslationsDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      home: Scaffold(
        body: TenantsTab(
          organization: Organization(
            id: 'o',
            name: 'Apartments',
            createdBy: 'user',
            createdAt: DateTime(2026),
            inviteCode: '123',
          ),
          tenantService: service,
          buildingService: BuildingsFake(),
          roomService: RoomsFake(),
          organizationService: EditableOrgFake(),
          authService: AuthFake(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> openOption(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('Options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Populated tenant edit form fits languages orientations and enlarged text',
    (tester) async {
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
            await pumpTenants(
              tester,
              EditableTenantFake(),
              size: size,
              language: language,
              scale: scale,
            );
            await tester.tap(find.byTooltip(t['tenant_options_tooltip']));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.text(t['tenant_menu_edit']));
            await tester.tap(find.text(t['tenant_menu_edit']));
            await tester.pumpAndSettle();
            final type = find.descendant(
              of: find.byType(SuggestedTextField),
              matching: find.byType(TextField),
            );
            await tester.ensureVisible(type);
            await tester.enterText(type, 'Phòng Gia Đình Có Ban Công');
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$language $size $scale',
            );
            expect(type.hitTestable(), findsOneWidget);
            if (const bool.fromEnvironment('EDITABLE_GOLDENS')) {
              await expectLater(
                find.byKey(const ValueKey('tenant-capture')),
                matchesGoldenFile(
                  '../.dart_tool/tenant-edit-$language-${size.width.toInt()}-$scale.png',
                ),
              );
            }
          }
        }
      }
    },
  );
  testWidgets(
    'Edit tenant saves custom apartment type and blocks invalid date',
    (tester) async {
      final service = EditableTenantFake();
      await pumpTenants(tester, service);
      await openOption(tester, 'Edit information');
      final type = find.descendant(
        of: find.byType(SuggestedTextField),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(type);
      await tester.enterText(type, '  Phòng Gia Đình  ');
      final date = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Move-in date *',
      );
      await tester.ensureVisible(date);
      await tester.enterText(date, '02/31/2026');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(service.update, isNull);
      await tester.enterText(date, '09/25/2026');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(service.update?['apartmentType'], 'Phòng Gia Đình');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Move-out saves a typed reason through the actual service call', (
    tester,
  ) async {
    final service = EditableTenantFake();
    await pumpTenants(tester, service);
    await openOption(tester, 'Mark as moved out');
    final reason = find.descendant(
      of: find.byType(SuggestedTextField),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(reason);
    await tester.enterText(reason, '  Chuyển công tác đến Đà Nẵng  ');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(service.reason, 'Chuyển công tác đến Đà Nẵng');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Move-room form exposes searchable existing building and room selectors',
    (tester) async {
      await pumpTenants(tester, EditableTenantFake());
      await openOption(tester, 'Move room');
      expect(find.byType(SearchableSelectField<String>), findsNWidgets(2));
      await tester.tap(find.byType(SearchableSelectField<String>).first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('record-search')),
        'apartment',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
