import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppThemeColors {
  static const teal = Color(0xFF176B70);
  static const indigo = Color(0xFF4F46E5);
  static const blue = Color(0xFF2563EB);
  static const purple = Color(0xFF7C3AED);
  static const amber = Color(0xFFB45309);
  static const rose = Color(0xFFBE123C);

  static const presets = <Color>[teal, indigo, blue, purple, amber, rose];
}

class AppThemePalette {
  static Color _primary = AppThemeColors.teal;

  static Color get primary => _primary;
  static Color get primaryDeep => Color.lerp(_primary, Colors.black, 0.45)!;
  // Keep the middle accent dark enough for white labels in headers and
  // buttons, including the amber and rose presets.
  static Color get primaryMid => Color.lerp(_primary, Colors.black, 0.12)!;
  static Color get primaryLight => Color.lerp(_primary, Colors.white, 0.90)!;

  // Identity accents stay in the chosen color family. Darkening keeps white
  // initials readable while giving adjacent cards a little variation.
  static List<Color> get identityColors => List.generate(
    7, (index) => Color.lerp(_primary, Colors.black, index * 0.045)!,
  );

  static List<Color> identityGradient(String id) {
    final colors = identityColors;
    final accent = colors[id.codeUnits.fold<int>(0, (sum, c) => sum + c) % colors.length];
    return [accent, Color.lerp(accent, Colors.black, 0.28)!];
  }

  static void setPrimary(Color color) => _primary = color;
}

class AppThemeNotifier extends ChangeNotifier {
  static const _preferenceKey = 'theme_primary_color';

  Color _primary = AppThemeColors.teal;

  Color get primary => _primary;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_preferenceKey);
    if (value != null) {
      _primary = Color(value);
    }
    AppThemePalette.setPrimary(_primary);
  }

  Future<void> setPrimary(Color color) async {
    if (_primary.value == color.value) return;
    _primary = color;
    AppThemePalette.setPrimary(color);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_preferenceKey, color.value);
  }
}

ThemeData buildAppTheme([
  Color primary = AppThemeColors.teal,
]) {
  return ThemeData(
    fontFamily: 'Roboto',
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: Color(0xFFE1E6E3)),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 4,
      contentPadding: EdgeInsets.symmetric(horizontal: 12),
      horizontalTitleGap: 12,
    ),
    expansionTileTheme: const ExpansionTileThemeData(
      tilePadding: EdgeInsets.symmetric(horizontal: 12),
      childrenPadding: EdgeInsets.fromLTRB(12, 0, 12, 12),
    ),
    scaffoldBackgroundColor: const Color(0xFFF6F7F4),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE1E6E3),
      thickness: 1,
      space: 16,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF6F7F4),
      foregroundColor: Color(0xFF172D3B),
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      titleSpacing: 12,
    ),
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: const Color(0xFF172D3B),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Color(0x221E1B4B),
      titleTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Color(0xFF172D3B),
      ),
      contentTextStyle: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 15,
        height: 1.5,
        color: Color(0xFF475569),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      errorMaxLines: 3,
      helperMaxLines: 3,
    ),
  );
}

