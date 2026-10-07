import 'package:intl/intl.dart';
import '../../utils/localizations/app_localizations.dart';

/// A record's room as people know it: the room number from the server, or the
/// internal room ID only when the room has no number (e.g. it was deleted).
String teamRoomLabel(Map<dynamic, dynamic> record) {
  final number = record['roomNumber'];
  if (number is String && number.isNotEmpty) return number;
  return '${record['roomId'] ?? ''}';
}

String teamDate(Object? value, AppTranslations translations) {
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) return translations['team_unspecified'];
  return DateFormat(translations.dateTimeFormat).format(date.toLocal());
}

/// A role's display name: the organization's own name if it has one, the
/// translated starter-template name, or "Custom role".
String teamRoleLabel(AppTranslations t, Object? role, [Object? name]) {
  if (name is String && name.trim().isNotEmpty) return name.trim();
  final key = 'team_role_$role';
  if (role is String && t.translationKeys.contains(key)) return t[key];
  return t['team_role_custom'];
}
