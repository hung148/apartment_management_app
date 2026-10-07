// B7b: the Google pop-up that lets an owner connect Google Drive.
// Web uses Google Identity Services (code flow); other platforms connect from
// the web app (the connection lives on the server, so uploads work everywhere).
export 'drive_connect_stub.dart' if (dart.library.js_interop) 'drive_connect_web.dart';
