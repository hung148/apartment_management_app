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
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/models/membership_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/organization_screen.dart'
    show OrganizationScreen;
import 'package:phan_mem_quan_ly_can_ho/services/auth_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/organization_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_notifier.dart';

final building = Building(
  id: 'b',
  organizationId: 'o',
  name: 'Apartment building',
  address: '',
  createdAt: DateTime(2026),
);

class RoomsFake implements RoomService {
  @override
  Future<List<Room>> getOrganizationRooms(String org) => getBuildingRooms(org, 'b');

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
  List<Tenant> entries = [];
  @override
  Future<List<Tenant>> getOrganizationTenants(String org) async => entries;

  @override
  Future<List<Tenant>> getBuildingTenants(
    String org,
    String building, {
    bool requireServer = false,
  }) async => entries;
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

class ThemeAuthFake implements AuthService {
  @override
  User? get currentUser => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ThemeOrganizationsFake implements OrganizationService {
  @override
  Future<List<Membership>> getOrganizationMembers(String org) async => [
    Membership(id: 'admin', organizationId: org, ownerId: 'admin',
      role: 'admin', status: 'active', joinedAt: DateTime(2026), displayName: 'Alex Nguyen'),
    Membership(id: 'member', organizationId: org, ownerId: 'member',
      role: 'member', status: 'active', joinedAt: DateTime(2026), displayName: 'Sam Tran'),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ThemePaymentsFake implements PaymentService {
  @override
  Future<List<Payment>> getOrganizationPayments(String org) async => [
    Payment(id:'p1', organizationId:org, buildingId:'b',roomId:'r',
      tenantName:'Alex Nguyen', type:PaymentType.rent,status:PaymentStatus.paid,
      amount:2500000,paidAmount:2500000,currency:'VND',
      dueDate:DateTime(2026,9,1),createdAt:DateTime(2026,9,1)),
    Payment(id:'p2', organizationId:org, buildingId:'b',roomId:'r',
      tenantName:'Sam Tran', type:PaymentType.rent,status:PaymentStatus.partial,
      amount:100,paidAmount:25,currency:'USD',
      dueDate:DateTime(2026,9,15),createdAt:DateTime(2026,9,2)),
  ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Organization header and calendar follow live theme changes', (
    tester,
  ) async {
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
    SharedPreferences.setMockInitialValues({
      'reference_exchange_rates_v2': '[{"base":"USD","quote":"VND","rate":25000,"date":"2026-09-08"}]',
    });
    await getIt.reset();
    getIt.registerSingleton<RoomService>(RoomsFake());
    getIt.registerSingleton<BuildingService>(BuildingsFake());
    getIt.registerSingleton<TenantService>(TenantsFake());
    getIt.registerSingleton<BookingService>(BookingsFake());
    getIt.registerSingleton<AuthService>(ThemeAuthFake());
    getIt.registerSingleton<OrganizationService>(ThemeOrganizationsFake());
    final payments = ThemePaymentsFake();
    getIt.registerSingleton<PaymentService>(payments);
    final paymentsNotifier = PaymentsNotifier(payments);
    getIt.registerSingleton<PaymentsNotifier>(paymentsNotifier);
    final theme = AppThemeNotifier();
    addTearDown(() async {
      theme.dispose();
      paymentsNotifier.dispose();
      AppThemePalette.setPrimary(AppThemeColors.teal);
      await getIt.reset();
    });
    tester.view.physicalSize = const Size(1440, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        child: OrganizationScreen(
          organization: Organization(
            id: 'o', name: 'Theme test', createdBy: 'u',
            createdAt: DateTime(2026), inviteCode: '12345678',
          ),
        ),
        builder: (context, child) => MaterialApp(
          theme: buildAppTheme(theme.primary),
          locale: const Locale('en', 'US'),
          supportedLocales: const [Locale('en', 'US'), Locale('vi', 'VN')],
          localizationsDelegates: const [
            AppTranslationsDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final calendarState = tester.state(find.byType(AvailabilityCalendarScreen));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Week'));
    await tester.pumpAndSettle();

    for (final primary in AppThemeColors.presets) {
      await theme.setPrimary(primary);
      await tester.pumpAndSettle();
      // The existing route must repaint without losing its selected view.
      expect(tester.state(find.byType(AvailabilityCalendarScreen)), same(calendarState));
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.toolbarHeight, 56);
      expect(appBar.bottom, isNull);
      final tabs = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabs.labelColor, appBar.backgroundColor);
      expect((tabs.indicator! as BoxDecoration).color, Colors.white);
      for (final mode in ['Day', 'Week', 'Month', 'Agenda']) {
        final finder = find.widgetWithText(ChoiceChip, mode);
        final chip = tester.widget<ChoiceChip>(finder);
        expect(chip.selected, mode == 'Week');
        final ink = tester.widget<Ink>(find.descendant(
          of: finder, matching: find.byType(Ink),
        ).first);
        final label = find.descendant(of: finder, matching: find.text(mode));
        final textColor = DefaultTextStyle.of(tester.element(label)).style.color!;
        final background = (ink.decoration! as ShapeDecoration).color!;
        expect(background.a, 1);
        final luminances = [textColor.computeLuminance(), background.computeLuminance()]..sort();
        expect((luminances.last + 0.05) / (luminances.first + 0.05), greaterThanOrEqualTo(4.5));
      }
      expect(tester.takeException(), isNull);
    }
    // Exercise the other kept-alive tabs while the theme changes in place.
    for (final tab in ['Buildings', 'Tenants', 'Payments', 'Statistics', 'Members']) {
      await tester.tap(find.descendant(of: find.byType(TabBar), matching: find.text(tab)));
      await tester.pumpAndSettle();
      if (tab == 'Buildings') {
        expect(find.widgetWithText(OutlinedButton, 'Calendar'), findsNothing);
        expect(find.text(AppTranslations(const Locale('en', 'US'))['hourly_calendar']), findsNothing);
      }
      for (final primary in [AppThemeColors.teal, AppThemeColors.purple]) {
        await theme.setPrimary(primary);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$tab with $primary');
      }
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await expectLater(find.byType(OrganizationScreen),
            matchesGoldenFile('../.dart_tool/theme-$tab.png'));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final language in ['en', 'vi']) {
    for (final embedded in [false, true]) {
    testWidgets('Calendar day and month fit a phone in $language (embedded: $embedded)', (
      tester,
    ) async {
      if (const bool.fromEnvironment('CAPTURE_UI') || const bool.fromEnvironment('CAPTURE_ROOM_UI')) {
        await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
        await (FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      }
      await getIt.reset();
      getIt.registerSingleton<RoomService>(RoomsFake());
      getIt.registerSingleton<BuildingService>(BuildingsFake());
      final tenants = TenantsFake();
      getIt.registerSingleton<TenantService>(tenants);
      final bookings = BookingsFake();
      getIt.registerSingleton<BookingService>(bookings);
      addTearDown(getIt.reset);
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
            embedded: embedded,
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
      if (embedded) {
        for (final size in [const Size(1440, 900), const Size(740, 360), const Size(360, 740)]) {
          tester.view.physicalSize = size;
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byKey(const ValueKey('calendar-workspace-toolbar'))).height,
            lessThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('CAPTURE_UI')) {
            await expectLater(find.byType(AvailabilityCalendarScreen),
              matchesGoldenFile('../.dart_tool/calendar-$language-${size.width.toInt()}.png'));
          }
        }
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.pumpAndSettle();
      }
      Future<void> selectView(String mode) async {
        await tester.tap(find.byKey(const ValueKey('calendar-view-menu')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('calendar-view-$mode')));
        await tester.pumpAndSettle();
      }
      await selectView('month');
      await tester.pumpAndSettle();
      expect(find.byType(GridView), findsOneWidget);
      expect(find.text(language == 'en' ? 'Sun' : 'CN'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final mode in ['week', 'agenda', 'day']) {
        await selectView(mode);
        if (mode != 'agenda') expect(find.text('101'), findsWidgets);
        expect(tester.takeException(), isNull);
      }
      expect(tester.getSize(find.byKey(const ValueKey('calendar-slot-r'))).height, 48);
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
        find.byKey(const ValueKey('calendar-range-instructions')),
        findsNothing,
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
      // Exercise the actual two-line occupied label, not just empty rooms.
      tenants.entries = [Tenant(
        id: 'tenant', organizationId: 'o', buildingId: 'b', roomId: 'r',
        fullName: 'Long-term resident', phoneNumber: '',
        status: TenantStatus.active, moveInDate: DateTime(2020),
        createdAt: DateTime(2020),
      )];
      await tester.tap(find.byTooltip(AppTranslations(locale)['refresh']));
      await tester.pumpAndSettle();
      expect(find.text(AppTranslations(locale)['calendar_long_term_guest']), findsOneWidget);
      for (final width in [360.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 900);
        for (final scale in [1.0, 1.3, 2.0]) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
            reason: 'Occupied label: $language, width $width, scale $scale');
          if (scale == 1) {
            expect(tester.getSize(find.byKey(const ValueKey('calendar-room-label-r'))).height,
              lessThanOrEqualTo(56), reason: 'Occupied rooms should stay compact');
          }
          if (const bool.fromEnvironment('CAPTURE_ROOM_UI') && width == 360 && scale != 1.3) {
            await expectLater(find.byType(AvailabilityCalendarScreen),
              matchesGoldenFile('../.dart_tool/occupied-$language-$scale.png'));
          }
        }
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  }
}
