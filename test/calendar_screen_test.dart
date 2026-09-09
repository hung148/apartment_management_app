import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/tenants_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/room_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/building_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/tenants_service.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/availability_calendar_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';

final building = Building(
  id: 'b',
  organizationId: 'o',
  name: 'Apartment building',
  address: '',
  createdAt: DateTime(2026),
);

class RoomsFake implements RoomService {
  @override
  Future<List<Room>> getBuildingRooms(String org, String buildingId) async => [
    Room(
      id: 'r',
      organizationId: org,
      buildingId: buildingId,
      roomNumber: '101',
      roomType: 'Standard',
      area: 20,
      createdAt: DateTime(2026),
      rentalMode: RoomRentalMode.hourly,
    ),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BuildingsFake implements BuildingService {
  @override
  Future<List<Building>> getOrganizationBuildings(String org) async => [
    building,
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TenantsFake implements TenantService {
  @override
  Future<List<Tenant>> getBuildingTenants(String org, String building) async =>
      [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BookingsFake implements BookingService {
  @override
  Future<Map<String, List<RoomBooking>>> getBuildingBookingsForDay(
    String org,
    String building,
    DateTime date,
  ) async => {};
  @override
  Future<List<RoomBooking>> getBuildingBookingsForMonth(
    String org,
    String building,
    DateTime date,
  ) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final language in ['en', 'vi']) {
    testWidgets('Calendar day and month fit a phone in $language', (
      tester,
    ) async {
      await getIt.reset();
      getIt.registerSingleton<RoomService>(RoomsFake());
      getIt.registerSingleton<BuildingService>(BuildingsFake());
      getIt.registerSingleton<TenantService>(TenantsFake());
      getIt.registerSingleton<BookingService>(BookingsFake());
      addTearDown(getIt.reset);
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final locale = Locale(language, language == 'vi' ? 'VN' : 'US');
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          supportedLocales: const [Locale('en', 'US'), Locale('vi', 'VN')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AvailabilityCalendarScreen(
            organization: Organization(
              id: 'o',
              name: 'Test',
              createdBy: 'u',
              createdAt: DateTime(2026),
              inviteCode: '12345678',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.text(AppTranslations(locale)['calendar_view_month']),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text(language == 'en' ? 'Sun' : 'CN'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
