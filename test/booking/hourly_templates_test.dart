import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/booking_workspace_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import '../lease/tenant_lease_test.dart' show store;
import '../team/team_review_test.dart' show mountReview;
import '../property/room_rates_test.dart' show reveal, press;
import 'room_booking_settings_test.dart' show enter;
import 'booking_payment_test.dart' show calculate, field;

Widget page(TeamService service) => BookingWorkspaceScreen(
  organizationId: 'preview',
  buildingId: 'riverside',
  accountId: 'owner',
  service: service,
  initialRoomId: 'room-102',
  startNew: true,
  initialStart: '2026-10-10 14:00',
  initialEnd: '2026-10-10 18:00',
  onClose: () {},
);
Future<void> tap(WidgetTester t, String key) async {
  await reveal(t, field(key));
  await t.tap(field(key));
  await calculate(t);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'create select delete template and save snapshot with repeating last hour',
    (t) async {
      final s = store();
      s.rooms.last.addAll({'hourlyPrice': 100000, 'currency': 'VND'});
      await mountReview(t, page(s.service));
      await calculate(t);
      await tap(t, 'booking-pricing-hourly');
      await tap(t, 'hour-custom');
      await enter(t, 'ops-hour-price-0', '300000');
      await tap(t, 'hour-add');
      await enter(t, 'ops-hour-price-1', '200000');
      await tap(t, 'hour-add');
      await enter(t, 'ops-hour-price-2', '100000');
      await enter(t, 'ops-templateName', 'Standard');
      await tap(t, 'hour-save-template');
      final saved = s.buildingHourTemplates['riverside']!.single;
      expect(saved['hourPricesMinor'], [300000, 200000, 100000]);
      // No "flat rate" any more (2026-10-26): picking a template replaces
      // the typed hours.
      expect(field('hour-flat'), findsNothing);
      await tap(t, 'hour-template-${saved['id']}');
      expect(
        t.widget<TextFormField>(field('ops-hour-price-1')).controller!.text,
        '200,000',
      );
      await reveal(t, field('hour-template-${saved['id']}'));
      t.widget<IconButton>(field('hour-delete-${saved['id']}')).onPressed!();
      await calculate(t);
      expect(s.buildingHourTemplates['riverside'], isEmpty);
      await enter(t, 'ops-guest', 'Hourly guest');
      await calculate(t);
      await press(t, 'Confirm and save');
      expect(s.operationalBookings.single['totalPrice'], 700000);
      expect(s.operationalBookings.single['hourPrices'], [
        300000,
        200000,
        100000,
      ]);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'populated hourly templates fit languages sizes and text scales',
    (t) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      for (final lang in ['en', 'vi'])
        for (final size in [
          const Size(320, 740),
          const Size(812, 375),
          const Size(1440, 900),
        ])
          for (final scale in [1.0, 1.3, 2.0]) {
            await t.pumpWidget(const SizedBox.shrink());
            final s = store();
            s.rooms.last.addAll({'hourlyPrice': 100000, 'currency': 'VND'});
            s.buildingHourTemplates['riverside'] = [
              {
                'id': 'long',
                'name': 'Mẫu cuối tuần dành cho khách gia đình Riverside',
                'currency': 'VND',
                'hourPricesMinor': [300000, 200000, 100000],
              },
            ];
            await mountReview(
              t,
              page(s.service),
              language: lang,
              size: size,
              scale: scale,
            );
            await calculate(t);
            await tap(t, 'booking-pricing-hourly');
            expect(
              field('hour-template-long'),
              findsOneWidget,
              reason: '$lang $size $scale',
            );
            await tap(t, 'hour-template-long');
            await reveal(t, field('ops-hour-price-2'));
            expect(t.takeException(), isNull, reason: '$lang $size $scale');
            await reveal(t, field('hour-save-template'));
            expect(t.takeException(), isNull);
            if ((size.width == 320 && scale == 2) ||
                (size.width == 1440 && scale == 1)) {
              await reveal(t, field('ops-hour-price-0'));
              await t.runAsync(() async {
                final image = await t
                    .renderObject<RenderRepaintBoundary>(field('capture'))
                    .toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                Directory('.dart_tool/hourly').createSync(recursive: true);
                File(
                  '.dart_tool/hourly/$lang-${size.width.toInt()}.png',
                ).writeAsBytesSync(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
          }
    },
  );
  testWidgets(
    'receptionist selects saved prices but cannot edit or delete templates',
    (t) async {
      final s = store()..workspaceRole = 'receptionist';
      s.rooms.last.addAll({'hourlyPrice': 100000, 'currency': 'VND'});
      s.buildingHourTemplates['riverside'] = [
        {
          'id': 't',
          'name': 'Standard',
          'currency': 'VND',
          'hourPricesMinor': [300000, 200000, 100000],
        },
      ];
      await mountReview(t, page(s.service));
      await calculate(t);
      await tap(t, 'booking-pricing-hourly');
      await tap(t, 'hour-template-t');
      expect(field('hour-delete-t'), findsNothing);
      expect(
        t
            .widget<TextField>(
              find.descendant(
                of: field('ops-hour-price-0'),
                matching: find.byType(TextField),
              ),
            )
            .readOnly,
        isTrue,
      );
      expect(field('hour-add'), findsNothing);
      expect(field('hour-save-template'), findsNothing);
      await enter(t, 'ops-guest', 'Desk guest');
      await calculate(t);
      await press(t, 'Confirm and save');
      expect(s.operationalBookings.single['totalPrice'], 700000);
    },
  );
  testWidgets('template picker actual-font light and dark renders', (t) async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final dark in [false, true])
      for (final size in [const Size(320, 740), const Size(1440, 900)]) {
        await t.pumpWidget(const SizedBox.shrink());
        final s = store();
        s.rooms.last.addAll({'hourlyPrice': 100000, 'currency': 'VND'});
        s.buildingHourTemplates['riverside'] = [
          {
            'id': 'long',
            'name': 'Mẫu cuối tuần dành cho khách gia đình Riverside',
            'currency': 'VND',
            'hourPricesMinor': [300000, 200000, 100000],
          },
        ];
        await mountReview(
          t,
          page(s.service),
          language: 'vi',
          size: size,
          scale: size.width == 320 ? 2 : 1,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        await calculate(t);
        await tap(t, 'booking-pricing-hourly');
        await tap(t, 'hour-template-long');
        if (size.width == 320) {
          final title = find.descendant(
            of: field('hour-template-long'),
            matching: find.text(
              'Mẫu cuối tuần dành cho khách gia đình Riverside',
            ),
          );
          expect(
            t.getSize(title).height,
            greaterThan(100),
            reason: 'Long template title must wrap instead of clipping',
          );
          expect(
            t.getSize(field('hour-delete-long')).width,
            greaterThanOrEqualTo(48),
          );
        }
        await t.ensureVisible(field('hour-template-long'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await t.runAsync(() async {
          final image = await t
              .renderObject<RenderRepaintBoundary>(field('capture'))
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory('.dart_tool/hourly').createSync(recursive: true);
          File(
            '.dart_tool/hourly/picker-${dark ? 'dark' : 'light'}-${size.width.toInt()}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
  });

  testWidgets(
    'lost template response retains draft and retry does not duplicate',
    (t) async {
      final s = store();
      s.rooms.last.addAll({'hourlyPrice': 100000, 'currency': 'VND'});
      var lose = true;
      final service = TeamService(
        transport: (name, data) async {
          final result = await s.call(name, data);
          if (data['action'] == 'hourTemplates' && lose) {
            lose = false;
            throw FirebaseFunctionsException(
              code: 'unavailable',
              message: 'Lost reply',
            );
          }
          return result;
        },
      );
      await mountReview(t, page(service));
      await calculate(t);
      await tap(t, 'booking-pricing-hourly');
      await tap(t, 'hour-custom');
      await enter(t, 'ops-hour-price-0', '300000');
      await enter(t, 'ops-templateName', 'Retry template');
      await tap(t, 'hour-save-template');
      expect(
        t.widget<TextFormField>(field('ops-templateName')).controller!.text,
        'Retry template',
      );
      await tap(t, 'hour-save-template');
      expect(s.buildingHourTemplates['riverside']!.length, 1);
      expect(
        field(
          'hour-template-${s.buildingHourTemplates['riverside']!.single['id']}',
        ),
        findsOneWidget,
      );
    },
  );
}
