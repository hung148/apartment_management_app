import 'package:intl/intl.dart';
import '../../utils/localizations/app_localizations.dart';

String teamDate(Object? value, AppTranslations translations) {
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) return translations['team_unspecified'];
  return DateFormat(translations.dateTimeFormat).format(date.toLocal());
}
