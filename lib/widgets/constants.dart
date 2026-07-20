import 'package:phan_mem_quan_ly_can_ho/utils/app_localizations.dart';

// Canonical stored values — keep these stable, they're what gets saved to Firestore.
const List<String> kApartmentTypes = ['standard', 'deluxe', 'suite', 'penthouse'];

String aptTypeLabel(AppTranslations t, String value) {
  switch (value) {
    case 'standard':
      return t['apt_type_standard'];
    case 'deluxe':
      return t['apt_type_deluxe'];
    case 'suite':
      return t['apt_type_suite'];
    case 'penthouse':
      return t['apt_type_penthouse'];
    default:
      // Fallback for legacy free-text values already saved before this change
      return value;
  }
}

String normalizeAptType(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'standard';
  final v = raw.trim().toLowerCase();

  if (kApartmentTypes.contains(v)) return v; // already a canonical key

  // Legacy free-text saves — could be either language, regardless of
  // what locale the app is in right now. Map both, hardcoded.
  const legacyMap = {
    'tiêu chuẩn': 'standard', 'standard': 'standard',
    'cao cấp': 'deluxe',      'deluxe': 'deluxe',
    'suite': 'suite',
    'penthouse': 'penthouse',
  };

  return legacyMap[v] ?? v; // unknown → keep as-is (see Option A earlier)
}