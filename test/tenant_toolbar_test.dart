import 'package:phan_mem_quan_ly_can_ho/widgets/compact_summary_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/tenant_toolbar.dart';
import 'tenant_summary_card_test.dart' show fonts;

void main() {
  for (final kind in ['tenant', 'building']) {
    testWidgets(
      '$kind toolbar fills width and keeps actions aligned and search editable',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await fonts();
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        for (final language in ['en', 'vi']) {
          for (final size in [
            const Size(320, 640),
            const Size(375, 812),
            const Size(812, 375),
            const Size(1440, 900),
          ]) {
            for (final scale in [1.0, 1.3, 2.0]) {
              for (final brightness in Brightness.values) {
                tester.view.physicalSize = size;
                tester.view.devicePixelRatio = 1;
                var added = false;
                controller.clear();
                await tester.pumpWidget(
                  MaterialApp(
                    locale: Locale(language),
                    supportedLocales: const [Locale('en'), Locale('vi')],
                    localizationsDelegates: const [
                      AppTranslationsDelegate(),
                      ...GlobalMaterialLocalizations.delegates,
                    ],
                    theme: ThemeData(
                      brightness: brightness,
                      fontFamily: 'Roboto',
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: child!,
                    ),
                    home: Scaffold(
                      body: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: RepaintBoundary(
                            key: const ValueKey('capture'),
                            child: kind == 'building'
                                ? Builder(
                                    builder: (context) {
                                      final t = AppTranslations.of(context);
                                      return CompactSummaryToolbar(
                                        values: const ['128', '12', '3%'],
                                        labels: [
                                          t['stat_buildings'],
                                          t['stat_rooms'],
                                          t['stat_occupancy'],
                                        ],
                                        icons: const [
                                          Icons.apartment_rounded,
                                          Icons.meeting_room_outlined,
                                          Icons.pie_chart_outline,
                                        ],
                                        searchController: controller,
                                        searchTitle: t['building_search_title'],
                                        searchHint: t['building_search_hint'],
                                        addLabel: t['add_building'],
                                        addIcon: Icons.add_business_rounded,
                                        actionKeyPrefix: 'building',
                                        onAdd: () => added = true,
                                      );
                                    },
                                  )
                                : TenantToolbar(
                                    counts: const [128, 12, 3],
                                    searchController: controller,
                                    onAdd: () => added = true,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
                final search = find.byKey(ValueKey('$kind-search'));
                final add = find.byKey(ValueKey('$kind-add'));
                expect(tester.getCenter(search).dy, tester.getCenter(add).dy);
                expect(
                  tester.getRect(add).right,
                  closeTo(size.width - 16, 0.1),
                );
                await tester.tap(add);
                await tester.pumpAndSettle();
                expect(added, isTrue);
                if (const bool.fromEnvironment('TENANT_TOOLBAR_GOLDENS') &&
                    scale != 1.3) {
                  await expectLater(
                    find.byKey(const ValueKey('capture')),
                    matchesGoldenFile(
                      '../.dart_tool/toolbar-$kind-$language-${size.width.toInt()}-$scale-${brightness.name}.png',
                    ),
                  );
                }
                final before = tester.getRect(search);
                await tester.ensureVisible(
                  find.text(kind == 'tenant' ? '3' : '3%'),
                );
                await tester.pumpAndSettle();
                expect(
                  tester
                      .getRect(find.text(kind == 'tenant' ? '3' : '3%'))
                      .right,
                  lessThanOrEqualTo(tester.getRect(search).left),
                );
                expect(tester.getRect(search), before);
                await tester.tap(search);
                await tester.pumpAndSettle();
                expect(find.byType(TextField), findsOneWidget);
                await tester.enterText(
                  find.byType(TextField),
                  'Nguyễn Alexandria 0901234567',
                );
                await tester.testTextInput.receiveAction(
                  TextInputAction.search,
                );
                await tester.pumpAndSettle();
                expect(controller.text, 'Nguyễn Alexandria 0901234567');
                expect(tester.getRect(search), before);
                await tester.tap(search);
                await tester.pumpAndSettle();
                expect(find.text(controller.text), findsOneWidget);
                await tester.tap(
                  find.text(
                    AppTranslations(Locale(language))['tenant_clear_search'],
                  ),
                );
                await tester.pumpAndSettle();
                expect(controller.text, isEmpty);
                await tester.tap(
                  find.text(AppTranslations(Locale(language))['close']),
                );
                await tester.pumpAndSettle();
                expect(tester.takeException(), isNull);
              }
            }
          }
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
