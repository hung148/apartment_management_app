import 'package:flutter/material.dart';

class AppTranslations {
  final Locale locale;
  AppTranslations(this.locale);

  static AppTranslations of(BuildContext context) {
    return Localizations.of<AppTranslations>(context, AppTranslations)!;
  }

  static final Map<String, Map<String, String>> _values = {
    'vi': {
      'select_language': 'Chọn ngôn ngữ',
      'vietnamese': 'Tiếng Việt',
      'english': 'Tiếng Anh',
      'dashboard': 'Trang chủ',
      'logout': 'Đăng xuất',
      'update': 'Cập nhật',
      'your_organizations': 'Tổ Chức Của Bạn',
      'join': 'Tham gia',
      'create': 'Tạo mới',
      'no_orgs': 'Chưa có tổ chức nào',
      'no_orgs_sub': 'Tạo tổ chức mới hoặc tham gia bằng mã mời',
      'hello': 'Xin chào!',
      'joined_at': 'Tham gia',
      'admin': 'Quản trị viên',
      'member': 'Thành viên',
    },
    'en': {
      'select_language': 'Select Language',
      'vietnamese': 'Vietnamese',
      'english': 'English',
      'dashboard': 'Dashboard',
      'logout': 'Logout',
      'update': 'Update',
      'your_organizations': 'Your Organizations',
      'join': 'Join',
      'create': 'Create',
      'no_orgs': 'No organizations yet',
      'no_orgs_sub': 'Create a new organization or join with an invite code',
      'hello': 'Hello!',
      'joined_at': 'Joined',
      'admin': 'Admin',
      'member': 'Member',
    },
  };

  String text(String key) => _values[locale.languageCode]?[key] ?? key;
  String operator [](String key) => text(key);
}

// Delegate để Flutter nhận diện bộ từ điển này
class AppTranslationsDelegate extends LocalizationsDelegate<AppTranslations> {
  const AppTranslationsDelegate();

  @override
  bool isSupported(Locale locale) => ['vi', 'en'].contains(locale.languageCode);

  @override
  Future<AppTranslations> load(Locale locale) async => AppTranslations(locale);

  @override
  bool shouldReload(AppTranslationsDelegate old) => false;
}