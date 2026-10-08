import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/time_zone_picker.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets('dark narrow picker keeps close reachable above keyboard', (
    t,
  ) async {
    await mountReview(
      t,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => chooseTimeZone(context, 'Asia/Ho_Chi_Minh'),
          child: const Text('Open'),
        ),
      ),
      language: 'vi',
      size: const Size(320, 740),
      scale: 2,
      brightness: Brightness.dark,
    );
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    t.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(t.view.resetViewInsets);
    await t.enterText(
      find.byKey(const ValueKey('timezone-search')),
      'Singapore',
    );
    await t.pumpAndSettle();
    expect(find.byTooltip('Đóng').hitTestable(), findsOneWidget);
    await t.ensureVisible(find.text('Asia/Singapore'));
    await t.pumpAndSettle();
    expect(find.text('Asia/Singapore').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.runAsync(() async {
      final im = await t
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          )
          .toImage();
      final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
      await Directory('.dart_tool/timezone-layout').create(recursive: true);
      await File(
        '.dart_tool/timezone-layout/dark-keyboard.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      im.dispose();
    });
    await t.tap(find.text('Asia/Singapore'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('timezone-search')), findsNothing);
  });
  for (final language in ['en', 'vi']) {
    for (final size in [
      const Size(320, 740),
      const Size(812, 375),
      const Size(1440, 1000),
    ]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('time zone list $language $size $scale', (t) async {
          String? result = 'unchanged';
          await mountReview(
            t,
            Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await chooseTimeZone(context, 'Asia/Ho_Chi_Minh');
                },
                child: const Text('Open'),
              ),
            ),
            language: language,
            size: size,
            scale: scale,
          );
          await t.tap(find.text('Open'));
          await t.pumpAndSettle();
          final tr = AppTranslations(Locale(language));
          expect(find.byTooltip(tr['close']).hitTestable(), findsOneWidget);
          final search = find.byKey(const ValueKey('timezone-search'));
          await t.enterText(search, 'Argentina');
          await t.pumpAndSettle();
          expect(find.text('America/Argentina/La_Rioja'), findsOneWidget);
          expect(t.widget<TextField>(search).decoration?.labelText, isNull);
          expect(find.text(tr['timezone_search']), findsOneWidget);
          expect(t.takeException(), isNull);
          if ((size.width == 320 && scale == 2) ||
              (size.width == 1440 && scale == 1)) {
            await t.runAsync(() async {
              final im = await t
                  .renderObject<RenderRepaintBoundary>(
                    find.byKey(const ValueKey('capture')),
                  )
                  .toImage();
              final bytes = await im.toByteData(format: ui.ImageByteFormat.png);
              await Directory(
                '.dart_tool/timezone-layout',
              ).create(recursive: true);
              await File(
                '.dart_tool/timezone-layout/$language-${size.width.toInt()}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              im.dispose();
            });
          }
          await t.enterText(search, 'unmatched zone');
          await t.pumpAndSettle();
          expect(find.text(tr['timezone_no_results']), findsOneWidget);
          await t.tap(find.byTooltip(tr['close']));
          await t.pumpAndSettle();
          expect(result, isNull);
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
