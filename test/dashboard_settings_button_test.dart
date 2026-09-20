import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/dashboard_settings_button.dart';

void main() {
  testWidgets(
    'settings remains reachable over the hero across display settings',
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
        const Size(375, 812),
        const Size(812, 375),
        const Size(1440, 900),
      ]) {
        tester.view.physicalSize = size;
        for (final brightness in Brightness.values) {
          for (final language in ['en', 'vi']) {
            final translations = AppTranslations(Locale(language));
            for (final scale in [1.0, 1.3, 2.0]) {
              for (final badge in [false, true]) {
                var taps = 0;
                await tester.pumpWidget(
                  MaterialApp(
                    theme: ThemeData(
                      brightness: brightness,
                      fontFamily: 'Roboto',
                    ),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(scale),
                        disableAnimations: true,
                      ),
                      child: child!,
                    ),
                    home: Scaffold(
                      body: Align(
                        alignment: Alignment.topCenter,
                        child: RepaintBoundary(
                          key: const ValueKey('hero'),
                          child: SizedBox(
                            height: (size.width * .20).clamp(
                              size.width < 600 ? 138.0 : 160.0,
                              size.width < 600 ? 170.0 : 220.0,
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.asset(
                                  'assets/image/background_image3.jpg',
                                  fit: BoxFit.cover,
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.black.withValues(alpha: .62),
                                        Colors.black.withValues(alpha: .10),
                                      ],
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: SizedBox(
                                    height: kToolbarHeight,
                                    child: AppBar(
                                      backgroundColor: Colors.transparent,
                                      surfaceTintColor: Colors.transparent,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      title: Text(
                                        translations.text('dashboard'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      actions: [
                                        DashboardSettingsButton(
                                          tooltip: translations.text(
                                            'settings',
                                          ),
                                          showBadge: badge,
                                          onPressed: () => taps++,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                await tester.runAsync(() async {
                  await precacheImage(
                    const AssetImage('assets/image/background_image3.jpg'),
                    tester.element(find.byType(DashboardSettingsButton)),
                  );
                });
                await tester.pumpAndSettle();
                final button = find.byType(DashboardSettingsButton);
                final before = tester.getRect(button);
                expect(before.size, const Size(48, 48));
                expect(before.right, lessThanOrEqualTo(size.width));
                expect(
                  find.byTooltip(translations.text('settings')),
                  findsOneWidget,
                );
                expect(
                  tester.widget<Badge>(find.byType(Badge)).isLabelVisible,
                  badge,
                );
                await tester.tap(button);
                await tester.pumpAndSettle();
                expect(taps, 1);
                expect(tester.getRect(button), before);
                expect(tester.takeException(), isNull);
                if (const bool.fromEnvironment('SETTINGS_GOLDENS') &&
                    scale == 1.0 &&
                    badge) {
                  await expectLater(
                    find.byKey(const ValueKey('hero')),
                    matchesGoldenFile(
                      '../.dart_tool/settings-$language-${brightness.name}-${size.width.toInt()}.png',
                    ),
                  );
                }
              }
            }
          }
        }
      }
    },
  );
}
