import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_dialog.dart';

Material dialogSurface(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(of: find.byType(Dialog), matching: find.byType(Material))
      .first,
);

void main() {
  for (final alert in [false, true]) {
    testWidgets(
      '${alert ? 'Alert' : 'Custom'} dialog follows a changing theme',
      (tester) async {
        for (final dark in [false, true]) {
          final style = DialogThemeData(
            backgroundColor: dark ? Colors.black87 : Colors.amber.shade50,
            surfaceTintColor: Colors.purple,
            shadowColor: Colors.red,
            elevation: dark ? 3 : 11,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dark ? 22 : 7),
              side: const BorderSide(color: Colors.orange, width: 2),
            ),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                dialogTheme: style,
              ),
              home: alert
                  ? const AppAlertDialog(content: Text('Review payment'))
                  : const AppDialog(child: Text('Review payment')),
            ),
          );
          await tester.pumpAndSettle();
          final surface = dialogSurface(tester);
          expect(surface.color, style.backgroundColor);
          expect(surface.surfaceTintColor, style.surfaceTintColor);
          expect(surface.shadowColor, style.shadowColor);
          expect(surface.elevation, style.elevation);
          expect(surface.shape, style.shape);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'Explicit dialog appearance overrides the theme, including zero elevation',
    (tester) async {
      const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(9)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const AppDialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            shape: shape,
            child: Text('Custom surface'),
          ),
        ),
      );
      final surface = dialogSurface(tester);
      expect(surface.color, Colors.transparent);
      expect(surface.elevation, 0);
      expect(surface.shape, shape);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: const AppAlertDialog(
            shape: shape,
            content: Text('Custom shape'),
          ),
        ),
      );
      expect(dialogSurface(tester).shape, shape);
    },
  );

  testWidgets(
    'Populated dialogs retain scrolling and reachable actions across display settings',
    (tester) async {
      await (FontLoader(
        'Roboto',
      )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [
        const Size(360, 640),
        const Size(812, 375),
        const Size(1280, 900),
      ]) {
        tester.view.physicalSize = size;
        for (final vi in [false, true]) {
          for (final scale in [1.0, 1.3, 2.0]) {
            for (final primary in [AppThemeColors.teal, AppThemeColors.rose]) {
              for (final alert in [false, true]) {
                var saved = false;
                final title = vi
                    ? 'Xác nhận thông tin thanh toán'
                    : 'Confirm payment details';
                final save = vi ? 'Lưu thay đổi' : 'Save changes';
                final cancel = vi ? 'Hủy' : 'Cancel';
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      vi
                          ? 'Nguyễn Thị Minh Phương — Phòng căn hộ hướng vườn 1208'
                          : 'Alexandra Montgomery — Garden-facing apartment 1208',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      vi
                          ? 'Tiền thuê: 12,500,000 VND · Chưa thanh toán'
                          : 'Rent: 12,500,000 VND · Pending payment',
                    ),
                    for (var i = 0; i < 8; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          vi
                              ? 'Kiểm tra thông tin người thuê, kỳ thanh toán và các khoản phí trước khi lưu.'
                              : 'Review the tenant details, billing period, and additional charges before saving.',
                        ),
                      ),
                    TextField(
                      decoration: InputDecoration(
                        labelText: vi ? 'Ghi chú' : 'Notes',
                      ),
                    ),
                    const Text('END', key: ValueKey('end')),
                  ],
                );
                final actions = [
                  TextButton(onPressed: () {}, child: Text(cancel)),
                  FilledButton(
                    onPressed: () => saved = true,
                    child: Text(save),
                  ),
                ];
                final theme = buildAppTheme(primary);
                await tester.pumpWidget(
                  MaterialApp(
                    theme: theme,
                    home: RepaintBoundary(
                      key: const ValueKey('capture'),
                      child: Scaffold(
                        body: Builder(
                          builder: (context) => MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              textScaler: TextScaler.linear(scale),
                              viewInsets: EdgeInsets.only(
                                bottom: alert ? 0 : 160,
                              ),
                            ),
                            child: alert
                                ? AppAlertDialog(
                                    title: Text(title),
                                    content: details,
                                    actions: actions,
                                  )
                                : AppDialog(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: SingleChildScrollView(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Text(
                                                    title,
                                                    style: theme
                                                        .textTheme
                                                        .titleLarge,
                                                  ),
                                                  const SizedBox(height: 12),
                                                  details,
                                                ],
                                              ),
                                            ),
                                          ),
                                          OverflowBar(
                                            spacing: 8,
                                            overflowSpacing: 4,
                                            children: actions,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$size vi=$vi scale=$scale alert=$alert',
                );
                expect(dialogSurface(tester).shape, theme.dialogTheme.shape);
                expect(
                  DefaultTextStyle.of(
                    tester.element(find.text(title)),
                  ).style.fontFamily,
                  'Roboto',
                  reason: 'Dialog headings must use the app font',
                );
                expect(find.text(save).hitTestable(), findsOneWidget);
                final before = tester.getRect(find.text(save));
                await tester.scrollUntilVisible(
                  find.byKey(const ValueKey('end')),
                  200,
                  scrollable: find
                      .descendant(
                        of: find.byType(SingleChildScrollView).first,
                        matching: find.byType(Scrollable),
                      )
                      .first,
                );
                await tester.pumpAndSettle();
                expect(
                  find.byKey(const ValueKey('end')).hitTestable(),
                  findsOneWidget,
                  reason: '$size vi=$vi scale=$scale alert=$alert',
                );
                expect(tester.getRect(find.text(save)), before);
                await tester.tap(find.text(save));
                expect(saved, isTrue);
                expect(tester.takeException(), isNull);
                // Opt-in artifacts: normal test runs do not write screenshots.
                const capture = bool.fromEnvironment('CAPTURE_DIALOGS');
                if (capture &&
                    vi &&
                    scale == 2 &&
                    primary == AppThemeColors.rose) {
                  await tester.drag(
                    find.byType(SingleChildScrollView).first,
                    const Offset(0, 2400),
                  );
                  await tester.pumpAndSettle();
                  final boundary = tester.renderObject<RenderRepaintBoundary>(
                    find.byKey(const ValueKey('capture')),
                  );
                  await tester.runAsync(() async {
                    final image = await boundary.toImage();
                    final bytes = await image.toByteData(
                      format: ui.ImageByteFormat.png,
                    );
                    final file = File(
                      'build/dialog-review/${size.width.toInt()}-${alert ? 'alert' : 'form'}.png',
                    );
                    await file.parent.create(recursive: true);
                    await file.writeAsBytes(bytes!.buffer.asUint8List());
                    image.dispose();
                  });
                }
              }
            }
          }
        }
      }
    },
  );
}
