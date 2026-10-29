@TestOn('browser')
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/app_window.dart' as app;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Windows browsers start without the native window manager', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(kIsWeb, isTrue);
    await expectLater(app.initializeAppWindow(), completes);
  });
}
