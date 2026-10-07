import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/dashboard/deleted_organization_recovery_dialog.dart';
import 'account_entry_test.dart' as fixtures;

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'recover confirms current organization and retries the same operation after a lost reply',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      var failed = false, done = false;
      await fixtures.mount(
        t,
        DeletedOrganizationRecoveryDialog(
          transport: (name, data) async {
            if (data['action'] == 'recoveryList')
              return {
                'organizations': done
                    ? []
                    : [
                        {
                          'id': 'deleted',
                          'name': 'Deleted property portfolio',
                          'deleteAt': '2026-11-01T00:00:00Z',
                        },
                      ],
              };
            calls.add(data);
            if (!failed) {
              failed = true;
              throw StateError('lost reply');
            }
            done = true;
            return {};
          },
        ),
      );
      await t.pumpAndSettle();
      final start = find.widgetWithText(
        FilledButton,
        'Restore into current organization',
      );
      await t.ensureVisible(start);
      await t.pumpAndSettle();
      await t.tap(start);
      await t.pumpAndSettle();
      expect(calls, isEmpty);
      final confirm = find
          .widgetWithText(FilledButton, 'Restore into current organization')
          .last;
      await t.ensureVisible(confirm);
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pumpAndSettle();
      expect(calls.length, 1);
      final retry = find.widgetWithText(FilledButton, 'Refresh');
      await t.ensureVisible(retry);
      await t.pumpAndSettle();
      await t.tap(retry);
      await t.pumpAndSettle();
      expect(calls.length, 2);
    expect(find.text('Data was restored into your current organization.'), findsOneWidget);
      expect(calls[0], calls[1]);
      expect(
        find.text('No deleted organization data is available for recovery.'),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  for (final locale in ['en', 'vi'])
    for (final size in [
      const Size(360, 800),
      const Size(800, 360),
      const Size(1440, 900),
    ])
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('recovery dialog $locale $size $scale', (t) async {
          await fixtures.mount(
            t,
            DeletedOrganizationRecoveryDialog(
              transport: (_, data) async => {
                'organizations': [
                  {
                    'id': 'deleted',
                    'name':
                        'Riverside — Khu căn hộ và khách sạn phía Đông có tên dài',
                    'deleteAt': '2026-11-01T00:00:00Z',
                  },
                ],
              },
            ),
            locale: locale,
            size: size,
            scale: scale,
          );
          await t.pumpAndSettle();
          final button = find.byType(FilledButton);
          await t.ensureVisible(button);
          await t.pumpAndSettle();
          expect(button.hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
          if ((locale == 'vi' && size.width == 360 && scale == 2) ||
              (locale == 'en' && size.width == 1440 && scale == 1)) {
            await t.runAsync(() async {
              final boundary =
                  t.element(find.byKey(fixtures.captureKey)).renderObject!
                      as RenderRepaintBoundary;
              final picture = await boundary.toImage();
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(
                '.dart_tool/recovery-layout',
              ).create(recursive: true);
              await File(
                '.dart_tool/recovery-layout/$locale-${size.width.toInt()}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }
        });
      }
}
