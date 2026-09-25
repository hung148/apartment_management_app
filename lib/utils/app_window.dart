import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

Future<void> initializeAppWindow() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    await windowManager.ensureInitialized();
    const WindowOptions windowOptions = WindowOptions(
      minimumSize: Size(480, 600),
      size: Size(1200, 800),
      center: true,
      title: 'Phần Mềm Quản Lý Căn Hộ',
    );
    await windowManager.waitUntilReadyToShow(windowOptions);
    await windowManager.show();
  }
}

