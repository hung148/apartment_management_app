import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/firebase_options.dart';
import 'package:phan_mem_quan_ly_can_ho/firebase_staging_options.dart';

void main() {
  test('environment selection fails closed for unknown or unsupported targets', () {
    const environment = String.fromEnvironment('APP_ENV', defaultValue: 'existing');
    if (environment == 'existing') {
      expect(DefaultFirebaseOptions.currentPlatform.projectId, 'apartment-management-app-776b9');
    } else if (environment == 'staging') {
      expect(() => DefaultFirebaseOptions.currentPlatform, throwsUnsupportedError);
    } else {
      expect(() => DefaultFirebaseOptions.currentPlatform, throwsStateError);
    }
  });
  test('staging uses a separate project and existing configurations stay isolated', () {
    expect(stagingWebOptions.projectId, 'apartment-management-staging');
    expect(stagingWebOptions.authDomain, 'apartment-management-staging.firebaseapp.com');
    for (final option in [DefaultFirebaseOptions.web, DefaultFirebaseOptions.android,
      DefaultFirebaseOptions.ios, DefaultFirebaseOptions.macos, DefaultFirebaseOptions.windows]) {
      expect(option.projectId, 'apartment-management-app-776b9');
      expect(option.projectId, isNot(stagingWebOptions.projectId));
    }
  });
}
