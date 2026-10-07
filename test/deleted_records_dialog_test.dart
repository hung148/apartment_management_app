import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/dashboard/deleted_records_dialog.dart';
import 'account_entry_test.dart' as fixtures;

void main() {
  testWidgets('permission loss clears cached deleted-record names', (t) async {
    await fixtures.mount(t,DeletedRecordsDialog(organizationId:'org',transport:(_,data)async {
      if(data['action']=='list')return {'records':[{'id':'deleted','name':'Private former guest','type':'bookings','deleteAt':'2026-11-01T00:00:00Z'}]};
      throw FirebaseFunctionsException(code:'permission-denied',message:'record_recovery_denied');
    }));await t.pumpAndSettle();
    final restore=find.widgetWithText(OutlinedButton,'Restore record');await t.ensureVisible(restore);await t.pumpAndSettle();await t.tap(restore);await t.pumpAndSettle();
    final confirm=find.widgetWithText(FilledButton,'Restore record');await t.ensureVisible(confirm);await t.pumpAndSettle();await t.tap(confirm);await t.pumpAndSettle();
    expect(find.text('Private former guest'),findsNothing);
  });
  setUpAll(() async {
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Roboto-Regular.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  testWidgets(
    'record recovery confirms and retries exactly after a lost reply',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      var tries = 0, done = false;
      await fixtures.mount(
        t,
        DeletedRecordsDialog(
          organizationId: 'org',
          transport: (_, data) async {
            if (data['action'] == 'list')
              return {
                'records': done
                    ? []
                    : [
                        {
                          'id': 'trash',
                          'name': 'Room 101',
                          'type': 'rooms',
                          'deleteAt': '2026-11-01T00:00:00Z',
                        },
                      ],
              };
            calls.add(data);
            if (tries++ == 0) throw StateError('lost');
            done = true;
            return {};
          },
        ),
      );
      await t.pumpAndSettle();
      final restore = find.widgetWithText(OutlinedButton, 'Restore record');
      await t.ensureVisible(restore);
      await t.pumpAndSettle();
      await t.tap(restore);
      await t.pumpAndSettle();
      final confirm = find.widgetWithText(FilledButton, 'Restore record');
      await t.ensureVisible(confirm);
      await t.pumpAndSettle();
      await t.tap(confirm);
      await t.pumpAndSettle();
      expect(calls.length, 1);
      await t.ensureVisible(restore);
      await t.pumpAndSettle();
      await t.tap(restore);
      await t.pumpAndSettle();
      expect(calls.length, 2);
      expect(calls[0], calls[1]);
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
        testWidgets('records recovery $locale $size $scale', (t) async {
          await fixtures.mount(
            t,
            DeletedRecordsDialog(
              organizationId: 'org',
              transport: (_, data) async => {
                'records': [
                  {
                    'id': 'deleted',
                    'name': 'Riverside — Phòng gia đình phía Đông có tên dài', 'context': 'Tòa nhà Riverside — Khu căn hộ phía Đông',
                    'type': 'rooms',
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
          final button = find.byType(OutlinedButton);
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
                '.dart_tool/recovery-layout/records-$locale-${size.width.toInt()}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
          }
        });
      }
}
