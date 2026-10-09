import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/organization_currency_screen.dart';
import 'package:phan_mem_quan_ly_can_ho/screens/team/account_workspace_dialog.dart';
import 'package:phan_mem_quan_ly_can_ho/services/team_service.dart';
import 'package:phan_mem_quan_ly_can_ho/preview/team_preview_store.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'team_review_test.dart' show mountReview;
import 'room_rates_test.dart' show press, reveal;
import 'access_editor_test.dart' show choose;

Widget screen(TeamService service) => OrganizationCurrencyScreen(
  organizationId: 'preview',
  service: service,
  onChanged: () {},
);
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
    'save lost reply retries identical intent and preserves existing building',
    (t) async {
      final store = TeamPreviewStore();
      store.buildings.first['currency'] = 'VND';
      final calls = <Map<String, dynamic>>[];
      final service = TeamService(
        transport: (n, d) async {
          final r = await store.call(n, d);
          if (d['action'] == 'updateCurrency') {
            calls.add(Map.of(d));
            if (calls.length == 1) throw StateError('lost');
          }
          return r;
        },
      );
      await mountReview(t, screen(service));
      await choose(t, 'organization-currency-VND', 'USD');
      await press(t, 'Save currency');
      expect(find.textContaining('result is uncertain'), findsOneWidget);
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('organization-currency-USD')),
            )
            .onChanged,
        isNull,
      );
      await press(t, 'Save currency');
      expect(calls.length, 2);
      expect(calls[0], calls[1]);
      expect(store.organizationCurrency, 'USD');
      expect(store.buildings.first['currency'], 'VND');
      expect(find.text('Currency saved.'), findsOneWidget);
    },
  );
  testWidgets('staff can read; revoked save and stale edit require reload', (
    t,
  ) async {
    final store = TeamPreviewStore()..workspaceRole = 'staff';
    await mountReview(t, screen(store.service));
    expect(find.text('Save currency'), findsNothing);
    expect(find.textContaining('requires the Change'), findsOneWidget);
    for (final code in ['permission-denied', 'aborted']) {
      final service = TeamService(
        transport: (n, d) async {
          if (d['action'] == 'updateCurrency')
            throw FirebaseFunctionsException(code: code, message: 'Rejected');
          return {'currency': 'VND', 'revision': 0, 'canChange': true};
        },
      );
      await mountReview(t, screen(service));
      await press(t, 'Save currency');
      expect(find.text('Save currency'), findsNothing);
      await press(t, 'Reload');
      expect(find.text('Save currency'), findsOneWidget);
    }
  });
  for (final lang in ['en', 'vi'])
    for (final size in [
      const Size(320, 740),
      const Size(812, 375),
      const Size(1440, 1000),
    ])
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('currency dialog $lang $size $scale', (t) async {
          final store = TeamPreviewStore();
          final tr = AppTranslations(Locale(lang));
          await mountReview(
            t,
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showAccountWorkspaceDialog(
                  context,
                  option: accountWorkspaceOptions.singleWhere(
                    (o) => o.id == 'currency',
                  ),
                  organizationId: 'preview',
                  service: store.service,
                  onChanged: () {},
                ),
                child: const Text('Open'),
              ),
            ),
            language: lang,
            size: size,
            scale: scale,
          );
          await t.tap(find.text('Open'));
          await t.pumpAndSettle();
          await reveal(t, find.text(tr['organization_currency_reload']));
          expect(
            find.text(tr['organization_currency_reload']).hitTestable(),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          final save = t.getRect(
            find.widgetWithText(FilledButton, tr['organization_currency_save']),
          );
          final reload = t.getRect(
            find.widgetWithText(
              OutlinedButton,
              tr['organization_currency_reload'],
            ),
          );
          expect(reload.top - save.bottom, greaterThanOrEqualTo(16));
          if (lang == 'vi' && size.width == 320 && scale == 2 ||
              lang == 'en' && size.width == 1440 && scale == 1) {
            await t.runAsync(() async {
              final im = await t
                  .renderObject<RenderRepaintBoundary>(
                    find.byKey(const ValueKey('capture')),
                  )
                  .toImage();
              final b = await im.toByteData(format: ui.ImageByteFormat.png);
              await Directory(
                '.dart_tool/currency-layout',
              ).create(recursive: true);
              await File(
                '.dart_tool/currency-layout/$lang-${size.width.toInt()}.png',
              ).writeAsBytes(b!.buffer.asUint8List());
              im.dispose();
            });
          }
        });
      }
}
