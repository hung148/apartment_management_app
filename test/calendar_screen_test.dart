import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/booking/booking_form_dialog.dart';
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
  Future<List<Room>> getBuildingRooms(
    String org,
    String buildingId, {
    bool requireServer = false,
  }) async => [
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
  Future<List<Building>> getOrganizationBuildings(
    String org, {
    bool requireServer = false,
  }) async => [building];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TenantsFake implements TenantService {
  @override
  Future<List<Tenant>> getBuildingTenants(
    String org,
    String building, {
    bool requireServer = false,
  }) async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class BookingsFake implements BookingService {
  bool fail = false;
  List<RoomBooking> entries = [];
  @override
  Future<Map<String, List<RoomBooking>>> getBuildingBookingsForDay(
    String org,
    String building,
    DateTime date,
  ) async {
    if (fail) throw StateError("offline");
    return {'r':entries};
  }

  @override
  Future<List<RoomBooking>> getBuildingBookingsForMonth(
    String org,
    String building,
    DateTime date,
  ) async {
    if (fail) throw StateError("offline");
    return entries;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final language in ['en', 'vi']) {
    testWidgets('Calendar day and month fit a phone in $language', (
      tester,
    ) async {
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
        await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      }
      await getIt.reset();
      getIt.registerSingleton<RoomService>(RoomsFake());
      getIt.registerSingleton<BuildingService>(BuildingsFake());
      getIt.registerSingleton<TenantService>(TenantsFake());
      final bookings = BookingsFake();
      getIt.registerSingleton<BookingService>(bookings);
      addTearDown(getIt.reset);
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final locale = Locale(language, language == 'vi' ? 'VN' : 'US');
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme().copyWith(textTheme:buildAppTheme().textTheme.apply(fontFamily: 'Roboto')),
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
      for (final mode in ['week', 'agenda', 'day']) {
        await tester.tap(
          find.text(AppTranslations(locale)['calendar_view_$mode']),
        );
        await tester.pumpAndSettle();
        expect(find.text('101'), findsWidgets);
        expect(tester.takeException(), isNull);
      }
      DateTime? selectedStart;
      // Both mouse clicks and phone taps preserve the existing booking form.
      for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        final slot = find.byKey(const ValueKey('calendar-slot-r'));
        final y = tester.getTopLeft(slot).dy + 30;
        await tester.tapAt(Offset(180, y), kind: kind);
        await tester.pumpAndSettle();
        expect(find.byType(BookingFormDialog), findsNothing);
        expect(find.text(AppTranslations(locale)['cancel']), findsOneWidget);
        await tester.tapAt(Offset(260, y), kind: kind);
        await tester.pumpAndSettle();
        expect(find.byType(BookingFormDialog), findsOneWidget);
        if (const bool.fromEnvironment('CAPTURE_UI') && kind == PointerDeviceKind.mouse) {
          await expectLater(find.byType(BookingFormDialog),matchesGoldenFile('../.dart_tool/booking-dialog-$language.png'));
        }
        final form = tester.widget<BookingFormDialog>(
          find.byType(BookingFormDialog),
        );
        selectedStart ??= form.initialStart;
        expect(
          form.initialEnd.difference(form.initialStart),
          const Duration(hours: 1),
        );
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(BookingFormDialog))).pop();
        await tester.pumpAndSettle();
      }
      final y =
          tester.getTopLeft(find.byKey(const ValueKey('calendar-slot-r'))).dy +
          30;
      await tester.tapAt(Offset(180, y));
      await tester.pumpAndSettle();
      // An earlier end does not open a booking or discard the selected start.
      await tester.tapAt(Offset(140, y));
      await tester.pumpAndSettle();
      expect(find.byType(BookingFormDialog), findsNothing);
      expect(
        find.text(AppTranslations(locale)['calendar_range_invalid']),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.text(AppTranslations(locale)['calendar_range_hint']),
        findsOneWidget,
      );
      bookings.entries=[RoomBooking(id:'occupied',organizationId:'o',buildingId:'b',roomId:'r',guestName:'Existing guest',guestPhone:'',startTime:selectedStart!.add(const Duration(minutes:30)),endTime:selectedStart.add(const Duration(minutes:45)),totalPrice:20,createdAt:DateTime(2026),status:BookingStatus.confirmed)];
      await tester.tap(find.byTooltip(AppTranslations(locale)['refresh']));
      await tester.pumpAndSettle();
      ScaffoldMessenger.of(tester.element(find.byType(AvailabilityCalendarScreen))).clearSnackBars();
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(180,y));
      await tester.pumpAndSettle();
      await tester.tapAt(Offset(300,y));
      await tester.pumpAndSettle();
      expect(find.byType(BookingFormDialog),findsNothing);
      expect(find.text(AppTranslations(locale)['booking_conflict']),findsOneWidget);
      bookings.entries=[];
      bookings.fail = true;
      await tester.tap(find.byTooltip(AppTranslations(locale)['refresh']));
      await tester.pumpAndSettle();
      expect(
        find.text(AppTranslations(locale)['calendar_load_failed']),
        findsOneWidget,
      );
      expect(find.text('101'), findsNothing);
      bookings.fail = false;
      await tester.tap(find.text(AppTranslations(locale)['retry']));
      await tester.pumpAndSettle();
      expect(find.text('101'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
