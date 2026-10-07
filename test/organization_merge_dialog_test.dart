import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/dashboard/organization_merge_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'account_entry_test.dart' as fixtures;

const organizations = [
  {'id': 'a', 'name': 'Riverside — Khu căn hộ và khách sạn phía Đông'},
  {'id': 'b', 'name': 'Test Import — Nhà và phòng có tên dài để kiểm tra'},
  {'id': 'c', 'name': 'Agreement UI verification'},
];
Future<void> mount(
  WidgetTester t,
  TeamTransport transport, {
  String locale = 'en',
  Size size = const Size(390, 844),
  double scale = 1,
}) async {
  await fixtures.mount(
    t,
    Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () => showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => RepaintBoundary(
              key: const ValueKey('merge-capture'),
              child: OrganizationMergeDialog(transport: transport),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    ),
    locale: locale,
    size: size,
    scale: scale,
  );
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
}

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
    'the complete Vietnamese name label remains painted on a narrow phone at 200 percent text',
    (t) async {
      await mount(
        t,
        (_, data) async => {'organizations': organizations},
        locale: 'vi',
        size: const Size(360, 800),
        scale: 2,
      );
      await t.ensureVisible(find.byType(TextField));
      await t.enterText(find.byType(TextField), 'Riverside');
      await t.pumpAndSettle();
      const label = 'Tên tổ chức chung';
      final paragraph = t.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.getBoxesForSelection(
          const TextSelection(
            baseOffset: label.length - 1,
            extentOffset: label.length,
          ),
        ),
        isNotEmpty,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'landscape keyboard leaves the name field and deletion action reachable with large Vietnamese text',
    (t) async {
      await mount(
        t,
        (_, data) async => {'organizations': organizations},
        locale: 'vi',
        size: const Size(800, 360),
        scale: 2,
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(TextField));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TextField).hitTestable(), findsOneWidget);
      await t.ensureVisible(find.byType(FilledButton).last);
      await t.pumpAndSettle();
      expect(find.byType(FilledButton).last.hitTestable(), findsOneWidget);
    },
  );
  testWidgets(
    'deletion requires explicit confirmation; interrupted submission retries the same operation and choices',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      var tries = 0;
      await mount(t, (name, data) async {
        if (data['action'] == 'preview')
          return {'organizations': organizations};
        calls.add(data);
        if (tries++ == 0) throw StateError('lost response');
        return {};
      });
      await t.ensureVisible(find.byType(TextField));
      await t.enterText(find.byType(TextField), 'Unified');
      await t.ensureVisible(find.byType(CheckboxListTile).at(1));
      await t.tap(find.byType(CheckboxListTile).at(1));
      await t.pumpAndSettle();
      final submit = find.widgetWithText(
        FilledButton,
        'Merge selected and delete others',
      );
      expect(t.widget<FilledButton>(submit).onPressed, isNull);
      await t.ensureVisible(find.byType(CheckboxListTile).last);
      await t.tap(find.byType(CheckboxListTile).last);
      await t.pumpAndSettle();
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(calls.single['mergeIds'], ['a', 'c']);
      expect(calls.single['confirmDelete'], true);
      expect(t.widget<TextField>(find.byType(TextField)).enabled, false);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(calls.length, 2);
      expect(calls[1], calls[0]);
      expect(find.byType(OrganizationMergeDialog), findsNothing);
    },
  );
  testWidgets('loading and preview failure retry without a mutation', (
    t,
  ) async {
    var n = 0;
    final pending = Completer<Map<String, dynamic>>();
    await fixtures.mount(
      t,
      OrganizationMergeDialog(
        transport: (name, data) {
          expect(data['action'], 'preview');
          return n++ == 0
              ? pending.future
              : Future.value({'organizations': organizations});
        },
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.completeError(StateError('offline'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await t.tap(find.byType(OutlinedButton));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
  for (final locale in ['en', 'vi'])
    for (final size in [
      const Size(360, 800),
      const Size(800, 360),
      const Size(1440, 900),
    ])
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('merge/delete dialog $locale $size $scale', (t) async {
          await mount(
            t,
            (_, data) async => {'organizations': organizations},
            locale: locale,
            size: size,
            scale: scale,
          );
          await t.ensureVisible(find.byType(CheckboxListTile).at(1));
          await t.tap(find.byType(CheckboxListTile).at(1));
          await t.pumpAndSettle();
          await t.ensureVisible(find.byType(TextField));
          await t.enterText(find.byType(TextField), 'Tổ chức chung Riverside');
          await t.pumpAndSettle();
          await t.ensureVisible(find.byType(CheckboxListTile).last);
          await t.tap(find.byType(CheckboxListTile).last);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          final submit = find.byType(FilledButton).last;
          await t.ensureVisible(submit);
          await t.pumpAndSettle();
          expect(submit.hitTestable(), findsOneWidget);
          expect(t.widget<FilledButton>(submit).onPressed, isNotNull);
          if ((locale == 'vi' && size.width == 360 && scale == 2) ||
              (locale == 'en' && size.width == 1440 && scale == 1)) {
            await t.runAsync(() async {
              final boundary =
                  t
                          .element(find.byKey(const ValueKey('merge-capture')))
                          .renderObject!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await Directory(
                '.dart_tool/single-organization-screenshots',
              ).create(recursive: true);
              await File(
                '.dart_tool/single-organization-screenshots/merge-$locale-${size.width.toInt()}-$scale.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        });
      }
}
