import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_theme.dart';

void main() {
  tearDown(() => AppThemePalette.setPrimary(AppThemeColors.teal));

  test('Every organization identity follows the palette with readable initials', () {
    for (final primary in AppThemeColors.presets) {
      AppThemePalette.setPrimary(primary);
      for (var index = 0; index < 30; index++) {
        final gradient = AppThemePalette.identityGradient('organization-$index');
        for (final color in gradient) {
          expect(color.a, 1);
          expect(1.05 / (color.computeLuminance() + .05), greaterThanOrEqualTo(4.5));
          expect(HSLColor.fromColor(color).hue,
              closeTo(HSLColor.fromColor(primary).hue, 1));
        }
      }
    }
  });

  test('Primary middle accent keeps white header text readable for every preset', () {
    for (final primary in AppThemeColors.presets) {
      AppThemePalette.setPrimary(primary);
      final background = AppThemePalette.primaryMid;
      final ratio = (Colors.white.computeLuminance() + .05) /
          (background.computeLuminance() + .05);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: 'Preset $primary');
    }
  });

  test('Selected theme persists and restores card accents', () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = AppThemeNotifier();
    final restored = AppThemeNotifier();
    addTearDown(notifier.dispose);
    addTearDown(restored.dispose);
    final before = AppThemePalette.identityGradient('organization');
    await notifier.setPrimary(AppThemeColors.rose);
    final expected = AppThemePalette.identityGradient('organization');
    expect(expected, isNot(equals(before)));
    AppThemePalette.setPrimary(AppThemeColors.teal);
    await restored.load();
    expect(restored.primary, AppThemeColors.rose);
    expect(AppThemePalette.identityGradient('organization'), expected);
  });
}
