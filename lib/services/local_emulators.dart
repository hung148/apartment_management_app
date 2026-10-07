import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'app_functions.dart';

/// Local test mode, started by `tool\local.ps1` with
/// `--dart-define=LOCAL_EMULATORS=true`. The app then talks only to the
/// Firebase emulators on this computer (a demo project with no cloud data or
/// costs). Normal and staging builds never set the flag, so nothing changes
/// for them. Ports must match firebase.local.json.
const bool localEmulators = bool.fromEnvironment('LOCAL_EMULATORS');
const String localProjectId = 'demo-canho360';
const int localAuthPort = 9199, localFirestorePort = 8180, localFunctionsPort = 5101;

/// Demo project settings: the emulators accept any key; no real project is used.
const FirebaseOptions localFirebaseOptions = FirebaseOptions(
  apiKey: 'local-demo-key',
  appId: '1:000000000000:web:0000000000000000',
  messagingSenderId: '000000000000',
  projectId: localProjectId,
  authDomain: 'localhost',
);

/// Call right after Firebase.initializeApp and before anything uses Firebase.
///
/// On web every call goes to the app's own address; web_dev_config.yaml
/// forwards it to the right emulator (a page calling other localhost ports is
/// blocked in some browsers). Other platforms use the emulator ports directly.
Future<void> useLocalEmulators() async {
  final sameOrigin = kIsWeb;
  final host = sameOrigin ? Uri.base.host : 'localhost';
  final port = sameOrigin ? Uri.base.port : 0;
  await FirebaseAuth.instance.useAuthEmulator(host, sameOrigin ? port : localAuthPort);
  if (sameOrigin) {
    // Streaming through the dev server proxy is not reliable; long polling is.
    FirebaseFirestore.instance.settings = const Settings(webExperimentalForceLongPolling: true);
  }
  FirebaseFirestore.instance.useFirestoreEmulator(host, sameOrigin ? port : localFirestorePort);
  appFunctions.useFunctionsEmulator(host, sameOrigin ? port : localFunctionsPort);
}
