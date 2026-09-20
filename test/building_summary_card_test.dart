import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/building_summary_card.dart';

final building = Building(
  id: 'a',
  organizationId: 'org',
  name: 'Tòa A',
  address: '123 đường ABC',
  createdAt: DateTime(2026, 7, 1),
);
final rental = Building(
  id: 'b',
  organizationId: 'org',
  name: 'Tòa B',
  address: '456 đường BCD',
  createdAt: DateTime(2026, 8, 1),
  managementType: BuildingManagementType.rented,
  rentAmount: 5000000,
  rentDueDay: 30,
  renterName: 'Nguyễn Văn Bình',
  renterPhone: '0901234567',
  rentContractStart: DateTime(2026, 8, 1),
  rentContractEnd: DateTime(2027, 8, 1),
);
final rooms = List.generate(
  45,
  (i) => Room(
    id: 'r$i',
    organizationId: 'org',
    buildingId: 'a',
    roomNumber: '${101 + i}',
    roomType: 'Studio',
    area: 30,
    createdAt: DateTime(2026),
  ),
);
Tenant tenant(
  String id,
  String name,
  String room, {
  TenantStatus status = TenantStatus.active,
}) => Tenant(
  id: id,
  organizationId: 'org',
  buildingId: 'a',
  roomId: room,
  fullName: name,
  phoneNumber: '0900000000',
  moveInDate: DateTime(2026),
  createdAt: DateTime(2026),
  status: status,
);
final tenants = [
  tenant('one', 'Nguyễn Thị Mai', 'r0'),
  tenant('two', 'Trần Minh Anh', 'r1'),
  tenant('roommate', 'Lê Hoàng Nam', 'r0'),
  tenant('former', 'Former tenant', 'r2', status: TenantStatus.moveOut),
  tenant('orphan', 'Missing room', 'missing'),
];

Future<void> pumpCard(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  String language = 'vi',
  double scale = 1,
  Brightness brightness = Brightness.light,
  Building? value,
  bool admin = true,
  bool loading = false,
  bool error = false,
  List<Room>? roomData,
  List<Tenant>? tenantData,
  VoidCallback? onEdit,
  VoidCallback? onManage,
  VoidCallback? onDelete,
  VoidCallback? onRetry,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(language),
      supportedLocales: const [Locale('en'), Locale('vi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(brightness: brightness, fontFamily: 'Roboto'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(
          key: const ValueKey('appCapture'),
          child: child!,
        ),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RepaintBoundary(
              key: const ValueKey('capture'),
              child: BuildingSummaryCard(
                building: value ?? building,
                translations: AppTranslations(Locale(language)),
                color: Colors.blue,
                rooms: roomData ?? rooms,
                tenants: tenantData ?? tenants,
                loading: loading,
                hasError: error,
                onRetry: onRetry,
                onManage: (value?.isRented == true && !admin)
                    ? null
                    : onManage ?? () {},
                onEdit: admin ? onEdit ?? () {} : null,
                onDelete: admin ? onDelete ?? () {} : null,
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
  test(
    'room summaries group roommates and exclude former or unrelated tenants',
    () {
      final summary = BuildingRoomSummary(building, rooms, tenants);
      expect(summary.matching(BuildingRoomFilter.all), hasLength(45));
      expect(summary.matching(BuildingRoomFilter.occupied), hasLength(2));
      expect(summary.matching(BuildingRoomFilter.vacant), hasLength(43));
      expect(summary.occupants['r0']!.map((t) => t.fullName), [
        'Nguyễn Thị Mai',
        'Lê Hoàng Nam',
      ]);
    },
  );

  testWidgets(
    'stats open matching room lists and menus retain permitted actions',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var edits = 0, manages = 0, deletes = 0;
      await pumpCard(
        tester,
        onEdit: () => edits++,
        onManage: () => manages++,
        onDelete: () => deletes++,
      );
      final cardRect = tester.getRect(find.byType(BuildingSummaryCard));
      expect(cardRect.height, lessThan(115));
      final identityRight = tester.getRect(find.text(building.address)).right;
      final statsLeft = tester
          .getRect(find.byKey(const ValueKey(BuildingRoomFilter.all)))
          .left;
      expect(
        statsLeft - identityRight,
        lessThanOrEqualTo(20),
        reason:
            'Short building identities must not reserve an empty name column.',
      );
      expect(
        tester.getRect(find.byKey(const ValueKey(BuildingRoomFilter.all))).left,
        lessThan(cardRect.left + 300),
      );
      for (final filter in BuildingRoomFilter.values) {
        await tester.tap(find.byKey(ValueKey(filter)));
        await tester.pumpAndSettle();
        if (filter == BuildingRoomFilter.occupied) {
          expect(find.text('Phòng 101'), findsOneWidget);
          expect(find.text('Phòng 102'), findsOneWidget);
          expect(find.text('Nguyễn Thị Mai'), findsOneWidget);
          expect(find.text('Lê Hoàng Nam'), findsOneWidget);
          expect(find.text('Trần Minh Anh'), findsOneWidget);
          expect(find.text('Former tenant'), findsNothing);
          expect(find.text('Phòng 103'), findsNothing);
        } else if (filter == BuildingRoomFilter.vacant) {
          expect(find.text('Phòng 103'), findsOneWidget);
          expect(find.text('Nguyễn Thị Mai'), findsNothing);
        }
        await tester.tap(find.text('Đóng'));
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byType(BuildingSummaryCard)), cardRect);
      }
      for (final label in ['Chỉnh sửa', 'Quản lý phòng', 'Xoá']) {
        await tester.tap(find.byTooltip('Thao tác tòa nhà'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect([edits, manages, deletes], [1, 1, 1]);
      await pumpCard(tester, admin: false);
      await tester.tap(find.byTooltip('Thao tác tòa nhà'));
      await tester.pumpAndSettle();
      expect(find.text('Chỉnh sửa'), findsNothing);
      expect(find.text('Xoá'), findsNothing);
      expect(find.text('Quản lý phòng'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading, retry, empty and whole-building rental details', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpCard(tester, loading: true);
    expect(find.text('Đang tải...'), findsOneWidget);
    expect(
      find.byKey(const ValueKey(BuildingRoomFilter.occupied)),
      findsNothing,
    );
    var retries = 0;
    await pumpCard(tester, error: true, onRetry: () => retries++);
    await tester.tap(find.text('Thử lại'));
    expect(retries, 1);
    expect(
      find.byKey(const ValueKey(BuildingRoomFilter.occupied)),
      findsNothing,
    );
    await pumpCard(tester, roomData: [], tenantData: []);
    await tester.tap(find.byKey(const ValueKey(BuildingRoomFilter.occupied)));
    await tester.pumpAndSettle();
    expect(find.text('Không có phòng phù hợp.'), findsOneWidget);
    await tester.tap(find.text('Đóng'));
    await tester.pumpAndSettle();
    await pumpCard(tester, value: rental);
    for (final label in ['Tiền thuê / kỳ', 'Ngày đến hạn']) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('Nguyễn Văn Bình'), findsOneWidget);
      expect(find.text('0901234567'), findsOneWidget);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('long names stay readable and rental viewers cannot edit', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final longBuilding = building.copyWith(
      name: 'Tòa nhà Nguyễn Thị Minh Khai – Riverside Apartments',
      address:
          '123 Nguyễn Thị Minh Khai, Phường Bến Nghé, Thành phố Hồ Chí Minh',
    );
    final longRoom = Room(
      id: 'long',
      organizationId: 'org',
      buildingId: 'a',
      roomNumber: 'Penthouse tầng 12 – Căn hộ gia đình hướng sông',
      roomType: 'Two-bedroom apartment',
      area: 80,
      createdAt: DateTime(2026),
    );
    final longTenant = tenant(
      'long',
      'Nguyễn Hoàng Anh Thư – Alexandria Montgomery',
      'long',
    );
    for (final language in ['en', 'vi']) {
      for (final brightness in Brightness.values) {
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 900),
        ]) {
          await pumpCard(
            tester,
            size: size,
            language: language,
            brightness: brightness,
            scale: 2,
            value: longBuilding,
            roomData: [longRoom],
            tenantData: [longTenant],
          );
          expect(tester.takeException(), isNull);
          final stat = find.byKey(const ValueKey(BuildingRoomFilter.occupied));
          await tester.ensureVisible(stat);
          await tester.tap(stat);
          await tester.pumpAndSettle();
          expect(find.text(longTenant.fullName), findsOneWidget);
          await tester.ensureVisible(find.text(longTenant.fullName));
          await tester.pumpAndSettle();
          expect(
            tester.getRect(find.text(longTenant.fullName)).bottom,
            lessThan(size.height),
          );
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('BUILDING_GOLDENS') &&
              language == 'vi' &&
              brightness == Brightness.light) {
            await expectLater(
              find.byKey(const ValueKey('appCapture')),
              matchesGoldenFile(
                '../.dart_tool/building-details-${size.width.toInt()}.png',
              ),
            );
          }
          await tester.tap(
            find.text(AppTranslations(Locale(language))['close']),
          );
          await tester.pumpAndSettle();
        }
      }
    }
    await pumpCard(tester, value: rental, admin: false);
    expect(find.byTooltip('Thao tác tòa nhà'), findsNothing);
    await tester.tap(find.text('Ngày đến hạn'));
    await tester.pumpAndSettle();
    expect(find.text('Nguyễn Văn Bình'), findsOneWidget);
  });

  testWidgets(
    'populated compact cards and details adapt to locale, theme and text size',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Bold.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final size in [
        const Size(320, 740),
        const Size(375, 812),
        const Size(812, 375),
        const Size(1440, 900),
      ]) {
        for (final language in ['en', 'vi']) {
          for (final brightness in Brightness.values) {
            for (final scale in [1.0, 1.3, 2.0]) {
              for (final value in [building, rental]) {
                await pumpCard(
                  tester,
                  size: size,
                  language: language,
                  brightness: brightness,
                  scale: scale,
                  value: value,
                );
                expect(tester.takeException(), isNull);
                if (const bool.fromEnvironment('BUILDING_GOLDENS') &&
                    (scale == 1 || (size.width == 320 && scale == 2))) {
                  await expectLater(
                    find.byKey(const ValueKey('capture')),
                    matchesGoldenFile(
                      '../.dart_tool/building-${value.id}-$language-${brightness.name}-${size.width.toInt()}-$scale.png',
                    ),
                  );
                }
                final t = AppTranslations(Locale(language));
                await tester.tap(
                  value.isRented
                      ? find.text(t['building_rent_due_day_label'])
                      : find.byKey(const ValueKey(BuildingRoomFilter.occupied)),
                );
                await tester.pumpAndSettle();
                expect(
                  find.text(
                    value.isRented ? 'Nguyễn Văn Bình' : 'Nguyễn Thị Mai',
                  ),
                  findsOneWidget,
                );
                expect(tester.takeException(), isNull);
                await tester.tap(find.text(t['close']));
                await tester.pumpAndSettle();
                await tester.tap(find.byTooltip(t['building_actions']));
                await tester.pumpAndSettle();
                expect(find.text(t['edit']), findsOneWidget);
                expect(tester.takeException(), isNull);
                await tester.tap(find.text(t['edit']));
                await tester.pumpAndSettle();
              }
            }
          }
        }
      }
    },
  );
}
