import 'package:cloud_functions/cloud_functions.dart';
import 'team_service.dart' show TeamTransport;
import 'app_functions.dart';

/// What the server saved.
class SavedProfile {
  final String name;
  final String? phone;
  const SavedProfile(this.name, this.phone);
}

/// Personal information (Settings > Personal information), saved by the
/// server so the new name also reaches every organization's member list.
class ProfileService {
  final TeamTransport _transport;
  ProfileService({TeamTransport? transport}) : _transport = transport ?? _firebase;

  static Future<Map<String, dynamic>> _firebase(String callable, Map<String, dynamic> data) async {
    final response = await appCallable(callable).call(data);
    return Map<String, dynamic>.from(response.data as Map);
  }

  static const nameMaxLength = 100;
  static const phoneMaxLength = 30;

  /// Same rules as the server: letters and spaces collapse, 1-100 characters.
  static String cleanName(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool isValidName(String value) {
    final name = cleanName(value);
    return name.isNotEmpty && name.length <= nameMaxLength;
  }

  /// Empty is allowed (no phone). Otherwise digits with optional leading +,
  /// spaces, dots, dashes or brackets, and 8-15 digits in total.
  static bool isValidPhone(String value) {
    final phone = value.trim();
    if (phone.isEmpty) return true;
    final digits = phone.replaceAll(RegExp(r'\D'), '').length;
    return phone.length <= phoneMaxLength &&
        RegExp(r'^\+?[0-9 ().-]+$').hasMatch(phone) &&
        digits >= 8 &&
        digits <= 15;
  }

  /// Returns the saved name and phone (null when cleared).
  Future<SavedProfile> update({required String name, required String phone}) async {
    final data = await _transport('myProfile', {
      'action': 'update',
      'name': cleanName(name),
      'phone': phone.trim(),
    });
    return SavedProfile(data['name'] as String? ?? cleanName(name), data['phone'] as String?);
  }

  /// Copies a confirmed new sign-in email to the profile and memberships.
  Future<void> syncEmail() => _transport('myProfile', {'action': 'syncEmail'});
}
