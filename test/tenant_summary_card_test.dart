import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/tenant_summary_card.dart';

Tenant sample({
  TenantStatus status = TenantStatus.active,
  bool long = false,
  bool populated = true,
}) => Tenant(
  id: 't',
  organizationId: 'o',
  buildingId: 'b',
  roomId: 'r',
  fullName: long
      ? 'Nguyễn Hoàng Anh Thư – Alexandria Montgomery'
      : 'Nguyễn Thị Mai',
  phoneNumber: '0901234567',
  status: status,
  moveInDate: DateTime(2026),
  createdAt: DateTime(2026),
  isMainTenant: populated,
  monthlyRent: populated ? 5000000 : null,
  occupation: long ? 'Senior software engineer and property consultant' : null,
  vehicles: populated
      ? [VehicleInfo(type: VehicleType.car, licensePlate: '51A-12345')]
      : null,
  previousRentals: populated
      ? [
          PreviousRentalHistory(
            buildingName: 'Tòa C',
            roomNumber: '201',
            moveInDate: DateTime(2025),
            moveOutDate: DateTime(2026),
          ),
        ]
      : null,
);

Future<void> fonts() async {
  await (FontLoader(
    'Roboto',
  )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> pump(
  WidgetTester tester, {
  Tenant? tenant,
  Size size = const Size(1440, 900),
  String language = 'vi',
  double scale = 1,
  Brightness brightness = Brightness.light,
  bool admin = true,
  bool long = false,
  bool missingRoom = false,
  VoidCallback? details,
  VoidCallback? room,
  VoidCallback? options,
  VoidCallback? history,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final value = tenant ?? sample(long: long);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness, fontFamily: 'Roboto'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: const ValueKey('capture'),
              child: TenantSummaryCard(
                tenant: value,
                translations: AppTranslations(Locale(language)),
                accentColor: Colors.blue,
                buildingName: long
                    ? 'Tòa nhà Nguyễn Thị Minh Khai – Riverside Apartments'
                    : 'Tòa A',
                roomNumber: long ? 'Penthouse tầng 12 hướng sông' : '101',
                onDetails: details ?? () {},
                onRoom: value.status == TenantStatus.moveOut || missingRoom
                    ? null
                    : room ?? () {},
                onOptions: admin ? options ?? () {} : null,
                onHistory: history ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('short identity hugs facts and tenant actions stay reachable', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await fonts();
    var details = 0, room = 0, options = 0, history = 0;
    final tenant = sample();
    await pump(
      tester,
      tenant: tenant,
      details: () => details++,
      room: () => room++,
      options: () => options++,
      history: () => history++,
    );
    final identityRight = math.max(
      tester.getRect(find.text(tenant.fullName)).right,
      tester.getRect(find.text(tenant.phoneNumber)).right,
    );
    final location = find.byKey(const ValueKey('tenant-location'));
    expect(tester.getRect(location).left - identityRight, closeTo(16, 1));
    expect(
      tester.getSize(find.byType(TenantSummaryCard)).height,
      lessThan(120),
    );
    final rect = tester.getRect(location);
    await tester.tap(location);
    await tester.tap(find.text(tenant.fullName));
    await tester.tap(find.byKey(const ValueKey('tenant-rent')));
    final t = AppTranslations(const Locale('vi'));
    await tester.tap(find.byTooltip(t['tenant_options_tooltip']));
    await tester.tap(find.byTooltip(t['tenant_menu_rental_history']));
    await tester.tap(find.byTooltip(t['tenant_menu_vehicles']));
    await tester.pumpAndSettle();
    expect([details, room, options, history], [2, 2, 1, 1]);
    expect(tester.getRect(location), rect);
    expect(tester.takeException(), isNull);
    await pump(
      tester,
      admin: false,
      missingRoom: true,
      tenant: sample(populated: false),
      details: () => details++,
    );
    expect(find.byTooltip(t['tenant_options_tooltip']), findsNothing);
    expect(find.byKey(const ValueKey('tenant-rent')), findsNothing);
    await tester.tap(location);
    expect(details, 3);
    await pump(
      tester,
      tenant: sample(status: TenantStatus.moveOut),
      details: () => details++,
    );
    expect(find.text(t['tenant_previous_location_label']), findsOneWidget);
    await tester.tap(location);
    expect(details, 4);
  });

  testWidgets(
    'tenant states fit both languages, themes, orientations and large text',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await fonts();
      for (final size in [
        const Size(320, 740),
        const Size(812, 375),
        const Size(1440, 900),
      ]) {
        for (final language in ['en', 'vi']) {
          for (final brightness in Brightness.values) {
            for (final scale in [1.0, 1.3, 2.0]) {
              for (final status in TenantStatus.values) {
                final long = scale == 2;
                await pump(
                  tester,
                  size: size,
                  language: language,
                  brightness: brightness,
                  scale: scale,
                  long: long,
                  tenant: sample(status: status, long: long),
                );
                expect(tester.takeException(), isNull);
                final fact = find.byKey(const ValueKey('tenant-rent'));
                await tester.ensureVisible(fact);
                await tester.tap(fact);
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                if (const bool.fromEnvironment('TENANT_GOLDENS') &&
                    status == TenantStatus.active &&
                    (scale == 1 || (size.width == 320 && scale == 2))) {
                  await expectLater(
                    find.byKey(const ValueKey('capture')),
                    matchesGoldenFile(
                      '../.dart_tool/tenant-$language-${brightness.name}-${size.width.toInt()}-$scale.png',
                    ),
                  );
                }
              }
            }
          }
        }
      }
    },
  );
}
