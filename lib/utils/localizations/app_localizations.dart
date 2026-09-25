import 'package:flutter/material.dart';

// Translation text lives in one file per language. Lookup, fallback, parameter
// substitution, and locale-specific date formatting remain here.
part 'translations_vi.dart';
part 'translations_en.dart';

class AppTranslations {
  String get defaultCurrency => isVietnamese ? 'VND' : 'USD';
  final Locale locale;
  AppTranslations(this.locale);

  static AppTranslations of(BuildContext context) {
    return Localizations.of<AppTranslations>(context, AppTranslations)!;
  }

  static final Map<String, Map<String, String>> _values = {
    'vi': _viTranslations,
    'en': _enTranslations,
  };

  String text(String key) => _values[locale.languageCode]?[key] ?? key;
  Set<String> get translationKeys => Set.unmodifiable(_values[locale.languageCode]?.keys ?? const <String>[]);

  String operator [](String key) => text(key);

  String textWithParams(String key, Map<String, dynamic> params) {
    String template = text(key);
    params.forEach((key, value) {
      template = template.replaceAll('{{$key}}', value.toString());
    });
    return template;
  }
}

class AppTranslationsDelegate extends LocalizationsDelegate<AppTranslations> {
  const AppTranslationsDelegate();

  @override
  bool isSupported(Locale locale) => ['vi', 'en'].contains(locale.languageCode);

  @override
  Future<AppTranslations> load(Locale locale) async => AppTranslations(locale);

  @override
  bool shouldReload(AppTranslationsDelegate old) => false;
}

extension DatePickerFormatting on AppTranslations {
  bool get isVietnamese => locale.languageCode == 'vi';
  String get dateFormat => isVietnamese ? 'dd/MM/yyyy' : 'MM/dd/yyyy';

  /// Day-and-month only, for compact ranges like "01/03 - 31/03/2026".
  String get dateFormatShort => isVietnamese ? 'dd/MM' : 'MM/dd';

  /// Two-digit year, for space-constrained chips and table cells.
  String get dateFormatCompact => isVietnamese ? 'dd/MM/yy' : 'MM/dd/yy';

  /// Date plus 24-hour time.
  String get dateTimeFormat => '$dateFormat HH:mm';

  /// Localized weekday name — use with [dateFormat] for a short header,
  /// or call [formatLongDate] for the full written-out form.
  String shortWeekdayName(DateTime date) {
    const vi = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];
    const en = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return (isVietnamese ? vi : en)[date.weekday % 7];
  }

  String weekdayName(DateTime date) {
    const vi = ['Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy'];
    const en = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    return (isVietnamese ? vi : en)[date.weekday % 7];
  }

  String formatLongDate(DateTime date) {
    if (isVietnamese) return _formatVietnameseDate(date);
    return _formatEnglishDate(date);
  }

  String _formatVietnameseDate(DateTime date) {
    final weekdays = ['Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư', 'Thứ năm', 'Thứ sáu', 'Thứ bảy'];
    return '${weekdays[date.weekday % 7]}, ngày ${date.day} tháng ${date.month} năm ${date.year}';
  }

  String _formatEnglishDate(DateTime date) {
    final weekdays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final day = date.day;
    String suffix;
    if (day >= 11 && day <= 13) {
      suffix = 'th';
    } else {
      switch (day % 10) {
        case 1: suffix = 'st'; break;
        case 2: suffix = 'nd'; break;
        case 3: suffix = 'rd'; break;
        default: suffix = 'th';
      }
    }
    return '${weekdays[date.weekday % 7]}, ${months[date.month - 1]} $day$suffix, ${date.year}';
  }
}

