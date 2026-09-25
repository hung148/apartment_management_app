import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/main.dart';
import 'package:phan_mem_quan_ly_can_ho/models/booking_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/buildings_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/organization_model.dart';
import 'package:phan_mem_quan_ly_can_ho/models/rooms_model.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/booking/booking_form_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/booking_service.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';

class _BookingsFake implements BookingService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final size in [
    const Size(375, 812),
    const Size(812, 375),
    const Size(1440, 900),
  ]) {
    for (final language in ['en', 'vi']) {
      testWidgets('Booking header fills both corners $size $language', (
        tester,
      ) async {
        await getIt.reset();
        getIt.registerSingleton<BookingService>(_BookingsFake());
        addTearDown(getIt.reset);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await (FontLoader(
          'Roboto',
        )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
        final start = DateTime(2026, 9, 19, 10);
        final boundaryKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(AppThemeColors.purple),
            locale: Locale(language, language == 'vi' ? 'VN' : 'US'),
            supportedLocales: const [Locale('en', 'US'), Locale('vi', 'VN')],
            localizationsDelegates: const [
              AppTranslationsDelegate(),
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: RepaintBoundary(
              key: boundaryKey,
              child: Scaffold(
                body: BookingFormDialog(
                  organization: Organization(
                    id: 'o',
                    name: 'Apartment',
                    createdBy: 'u',
                    createdAt: start,
                    inviteCode: '12345678',
                  ),
                  building: Building(
                    id: 'b',
                    organizationId: 'o',
                    name: 'Building A',
                    address: '',
                    createdAt: start,
                  ),
                  room: Room(
                    id: 'r',
                    organizationId: 'o',
                    buildingId: 'b',
                    roomNumber: '101',
                    roomType: 'Standard',
                    area: 20,
                    createdAt: start,
                  ),
                  booking: RoomBooking(
                    id: 'booking',
                    organizationId: 'o',
                    buildingId: 'b',
                    roomId: 'r',
                    guestName: 'Nguyễn Minh Anh',
                    guestPhone: '0901234567',
                    startTime: start,
                    endTime: start.add(const Duration(hours: 3)),
                    totalPrice: 450000,
                    createdAt: start,
                  ),
                  initialStart: start,
                  initialEnd: start.add(const Duration(hours: 3)),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final translations = AppTranslations(Locale(language, language == 'vi' ? 'VN' : 'US'));
        for (final count in [1, 2, 3]) {
          expect(find.text(translations.textWithParams('booking_form_duration_hours', {'count': count})), findsNothing);
        }
        expect(find.text(translations['booking_form_custom_range_hint']), findsNothing);
        expect(find.byIcon(Icons.hourglass_bottom_rounded), findsNothing);
        expect(find.text(translations['booking_check_in']), findsOneWidget);
        expect(find.text(translations['booking_check_out']), findsOneWidget);
        final header = find
            .byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration! as BoxDecoration).gradient != null,
            )
            .first;
        final rect = tester.getRect(header);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = (await tester.runAsync(() => boundary.toImage()))!;
        final pixels = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        for (final x in [rect.left + 4, rect.right - 5]) {
          final offset = ((rect.top.toInt() + 5) * image.width + x.toInt()) * 4;
          final rgb = List.generate(
            3,
            (channel) => pixels.getUint8(offset + channel),
          );
          expect(
            rgb.every((channel) => channel > 240),
            isFalse,
            reason:
                'The white dialog surface must not show through the header corner at $x.',
          );
        }
        image.dispose();
        if (const bool.fromEnvironment('CAPTURE_UI')) {
          await expectLater(
            find.byKey(boundaryKey),
            matchesGoldenFile(
              '../.dart_tool/dialog-corners-${size.width.toInt()}-$language.png',
            ),
          );
        }
      });
    }
  }
}
