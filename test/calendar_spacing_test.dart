import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/calendar/room_calendar.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/workspace_page_scope.dart';

import 'room_calendar_test.dart' show calendarService, Calls, tapDay;
import 'team_review_test.dart' show mountReview;

Rect paintedRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

Future<void> mount(
  WidgetTester tester, {
  String language = 'vi',
  Size size = const Size(1440, 1000),
  double scale = 1,
  bool embedded = false,
  Brightness brightness = Brightness.light,
}) async {
  Widget calendar = RoomCalendar(
    key: UniqueKey(),
    organizationId: 'preview',
    accountId: 'preview-owner',
    service: calendarService(Calls()),
    initialMonth: DateTime(2026, 10),
    showTools: false,
  );
  if (embedded) calendar = WorkspacePageScope(child: calendar);
  await mountReview(
    tester,
    calendar,
    language: language,
    size: size,
    scale: scale,
    brightness: brightness,
  );
}

void main() {
  testWidgets('wider narrow cells keep lease end bubbles within their bounds', (
    tester,
  ) async {
    await mount(tester, language: 'en', size: const Size(320, 740), scale: 1.3);
    expect(find.byKey(const ValueKey('calendar-bubble-end')), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow timeline keeps hour text readable', (tester) async {
    await mount(tester, size: const Size(390, 844));
    final day = find.byKey(const ValueKey('calendar-day-2026-10-03'));
    final hour = find.descendant(of: day, matching: find.text('00'));
    expect(paintedRect(tester, hour).height, greaterThanOrEqualTo(12));
    expect(tester.takeException(), isNull);
  });
  testWidgets('calendar cell opens rental dialog without deferred actions', (
    tester,
  ) async {
    await mount(tester);
    await tapDay(tester, 'r104', 12);
    expect(
      find.byKey(const ValueKey('calendar-rental-dialog')),
      findsOneWidget,
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(const ValueKey('calendar-report')), findsNothing);
    expect(find.byKey(const ValueKey('calendar-new-cleaning')), findsNothing);
    expect(find.text('Hủy'), findsNothing);
    expect(find.byTooltip('Đóng'), findsOneWidget);
  });
  setUpAll(() async {
    for (final family in ['Roboto', 'Ahem']) {
      await (FontLoader(
        family,
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets('calendar uses desktop width and preserves six days', (
    tester,
  ) async {
    await mount(tester);
    final card = tester.getRect(find.byKey(const ValueKey('calendar-card')));
    expect(card.left, lessThanOrEqualTo(12));
    expect(1440 - card.right, lessThanOrEqualTo(12));
    final grid = find
        .byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal &&
              w.controller != null,
        )
        .first;
    final day = tester.getSize(
      find.byKey(const ValueKey('calendar-today-column')),
    );
    expect(tester.getSize(grid).width / day.width, inInclusiveRange(5.9, 6.2));
  });

  testWidgets('date and hour header uses 48 pixels', (tester) async {
    await mount(tester);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('calendar-today-column')))
          .height,
      48,
    );
  });

  testWidgets('rental chooser fits locales sizes scales and both embeddings', (
    tester,
  ) async {
    for (final embedded in [false, true]) {
      for (final language in ['en', 'vi']) {
        for (final size in [
          const Size(320, 740),
          const Size(800, 360),
          const Size(1440, 900),
        ]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            await mount(
              tester,
              embedded: embedded,
              language: language,
              size: size,
              scale: scale,
            );
            await tapDay(tester, 'r104', 12);
            final dialog = find.byKey(const ValueKey('calendar-rental-dialog'));
            expect(dialog, findsOneWidget);
            final rect = tester.getRect(dialog);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(size.width));
            expect(rect.bottom, lessThanOrEqualTo(size.height));
            final long = find.byKey(const ValueKey('calendar-new-long'));
            await tester.ensureVisible(long);
            await tester.pumpAndSettle();
            expect(long.hitTestable(), findsOneWidget);
            expect(
              find.byKey(const ValueKey('calendar-rental-close')).hitTestable(),
              findsOneWidget,
            );
            expect(
              tester.takeException(),
              isNull,
              reason: '$embedded $language $size $scale',
            );
            if (!embedded &&
                language == 'vi' &&
                scale == 1 &&
                size.width == 1440) {
              await tester.runAsync(() async {
                final boundary = tester.renderObject<RenderRepaintBoundary>(
                  find.byKey(const ValueKey('capture')),
                );
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File(
                  '.dart_tool/calendar-spacing/rental-dialog-desktop.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.tap(
              find.byKey(const ValueKey('calendar-rental-close')),
            );
            await tester.pumpAndSettle();
            expect(dialog, findsNothing);
          }
        }
      }
    }
  });

  testWidgets('single room row uses 30 pixels without shrinking stay bars', (
    tester,
  ) async {
    await mount(tester);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('calendar-room-r104'))).dy -
          tester
              .getTopLeft(find.byKey(const ValueKey('calendar-room-r103')))
              .dy,
      30,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('calendar-bar-booking:b1')))
          .height,
      24,
    );
  });

  testWidgets('visible hour labels have a readable gap including midnight', (
    tester,
  ) async {
    await mount(tester);
    final day = find.byKey(const ValueKey('calendar-today-column'));
    Rect hour(Finder parent, String label) => paintedRect(
      tester,
      find.descendant(of: parent, matching: find.text(label)),
    );
    final labels =
        tester
            .widgetList<Text>(
              find.descendant(
                of: day,
                matching: find.byWidgetPredicate(
                  (w) => w is Text && RegExp(r'^\d{2}$').hasMatch(w.data ?? ''),
                ),
              ),
            )
            .map((w) => w.data!)
            .toList()
          ..sort();
    expect(labels.length, greaterThanOrEqualTo(3));
    for (var i = 1; i < labels.length; i++) {
      expect(
        hour(day, labels[i]).left - hour(day, labels[i - 1]).right,
        greaterThanOrEqualTo(4.9),
      );
    }
    final next = find.byKey(const ValueKey('calendar-day-2026-10-03'));
    expect(
      hour(next, '00').left - hour(day, labels.last).right,
      greaterThanOrEqualTo(4.9),
    );
  });

  testWidgets(
    'Vietnamese month heading omits Thang across month and year boundaries',
    (tester) async {
      await mount(tester);
      final label = find.byKey(const ValueKey('calendar-month'));
      expect(tester.widget<Text>(label).data, '10, 2026');
      final grid = tester
          .widget<SingleChildScrollView>(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is SingleChildScrollView &&
                      w.scrollDirection == Axis.horizontal &&
                      w.controller != null,
                )
                .first,
          )
          .controller!;
      final dayW = tester
          .getSize(find.byKey(const ValueKey('calendar-today-column')))
          .width;
      grid.jumpTo(58 * dayW); // October 29 in the September–November window.
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(label).data, '10 – 11, 2026');
      await tester.tap(find.byKey(const ValueKey('calendar-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('calendar-next')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(label).data, '12, 2026');
      grid.jumpTo(58 * dayW); // December 29 in the November–January window.
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(label).data, '12, 2026 – 1, 2027');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'populated spacing in both languages sizes scales and embeddings',
    (tester) async {
      for (final embedded in [false, true]) {
        for (final language in ['en', 'vi']) {
          for (final size in [
            const Size(320, 740),
            const Size(390, 844),
            const Size(812, 375),
            const Size(1440, 1000),
            const Size(2048, 1021),
          ]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              await mount(
                tester,
                embedded: embedded,
                language: language,
                size: size,
                scale: scale,
              );
              final today = find.byKey(const ValueKey('calendar-today-column'));
              final visibleHours = tester
                  .widgetList<Text>(
                    find.descendant(
                      of: today,
                      matching: find.byWidgetPredicate(
                        (w) =>
                            w is Text &&
                            RegExp(r'^\d{2}$').hasMatch(w.data ?? ''),
                      ),
                    ),
                  )
                  .map((w) => w.data!)
                  .toList();
              expect(visibleHours.length, greaterThanOrEqualTo(2));
              for (final label in visibleHours) {
                final hour = find.descendant(
                  of: today,
                  matching: find.text(label),
                );
                expect(hour, findsOneWidget);
                expect(
                  paintedRect(tester, hour).height,
                  greaterThanOrEqualTo(12),
                );
                final headerBounds = tester.getRect(today);
                final hourBounds = paintedRect(tester, hour);
                expect(hourBounds.top, greaterThanOrEqualTo(headerBounds.top));
                expect(
                  hourBounds.bottom,
                  lessThanOrEqualTo(headerBounds.bottom),
                );
              }
              expect(
                find.byKey(const ValueKey('calendar-bar-lease:tenant-anh')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('calendar-bar-booking:b3')),
                findsOneWidget,
              );
              expect(
                tester.takeException(),
                isNull,
                reason: '$embedded $language $size $scale',
              );
            }
          }
        }
      }
    },
  );

  testWidgets('render populated calendar spacing with actual fonts', (
    tester,
  ) async {
    for (final shot in [
      ('vi', const Size(2048, 1021), 1.0, Brightness.light),
      ('en', const Size(1440, 1000), 1.0, Brightness.light),
      ('vi', const Size(320, 740), 2.0, Brightness.light),
      ('vi', const Size(812, 375), 1.3, Brightness.dark),
    ]) {
      await mount(
        tester,
        language: shot.$1,
        size: shot.$2,
        scale: shot.$3,
        brightness: shot.$4,
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('.dart_tool/calendar-spacing')
          ..createSync(recursive: true);
        await File(
          '${dir.path}/${shot.$1}-${shot.$2.width.toInt()}-${shot.$3}-${shot.$4.name}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
