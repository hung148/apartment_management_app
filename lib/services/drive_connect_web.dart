import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'drive_connect_stub.dart' show DriveConnectError;
export 'drive_connect_stub.dart' show DriveConnectError;

/// True where the Google pop-up can open (the web app).
const bool driveConnectSupported = true;

// openid + email name the Google account; drive.file lets the app see only
// the files it creates.
const _scope = 'openid email https://www.googleapis.com/auth/drive.file';
Future<void>? _loading;

bool _ready() {
  final google = globalContext['google'];
  return google != null && (google as JSObject).has('accounts');
}

/// Loads Google's sign-in script ahead of the tap, so the pop-up opens
/// straight from the button press (browsers block late pop-ups).
Future<void> prepareDriveConnect() {
  if (_ready()) return Future.value();
  return _loading ??= () async {
    final document = globalContext['document']! as JSObject;
    final script = document.callMethod<JSObject>('createElement'.toJS, 'script'.toJS);
    final done = Completer<void>();
    script['src'] = 'https://accounts.google.com/gsi/client'.toJS;
    script['async'] = true.toJS;
    script['onload'] = ((JSAny? _) {
      if (!done.isCompleted) done.complete();
    }).toJS;
    script['onerror'] = ((JSAny? _) {
      if (!done.isCompleted) done.completeError(const DriveConnectError('script'));
    }).toJS;
    (document['head']! as JSObject).callMethod<JSAny?>('appendChild'.toJS, script);
    try {
      await done.future.timeout(const Duration(seconds: 20), onTimeout: () => throw const DriveConnectError('script'));
    } catch (_) {
      _loading = null; // try again on the next tap
      rethrow;
    }
  }();
}

/// Opens Google's pop-up and returns the one-time code for the server.
Future<String> requestDriveCode(String clientId) async {
  await prepareDriveConnect();
  final oauth2 = ((globalContext['google']! as JSObject)['accounts']! as JSObject)['oauth2']! as JSObject;
  final result = Completer<String>();
  final config = JSObject();
  config['client_id'] = clientId.toJS;
  config['scope'] = _scope.toJS;
  config['ux_mode'] = 'popup'.toJS;
  config['select_account'] = true.toJS;
  config['callback'] = ((JSObject response) {
    if (result.isCompleted) return;
    final map = response.dartify() as Map?;
    final code = map?['code'];
    if (code is String && code.isNotEmpty) {
      result.complete(code);
    } else {
      result.completeError(DriveConnectError('${map?['error'] ?? 'access_denied'}'));
    }
  }).toJS;
  config['error_callback'] = ((JSObject error) {
    if (result.isCompleted) return;
    final map = error.dartify() as Map?;
    result.completeError(DriveConnectError('${map?['type'] ?? 'popup_closed'}'));
  }).toJS;
  final client = oauth2.callMethod<JSObject>('initCodeClient'.toJS, config);
  client.callMethod<JSAny?>('requestCode'.toJS);
  return result.future;
}
