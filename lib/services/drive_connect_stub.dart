/// Why the Google pop-up gave no code: 'popup_closed' (the person closed it),
/// 'popup_failed_to_open' (blocked by the browser), 'access_denied',
/// 'script' (Google could not be reached) or 'unsupported' (not the web app).
class DriveConnectError implements Exception {
  final String reason;
  const DriveConnectError(this.reason);
  @override
  String toString() => 'DriveConnectError($reason)';
}

/// True where the Google pop-up can open (the web app).
const bool driveConnectSupported = false;

/// Loads Google's sign-in script ahead of the tap (web only).
Future<void> prepareDriveConnect() async {}

/// Opens Google's pop-up and returns the one-time code for the server.
Future<String> requestDriveCode(String clientId) async => throw const DriveConnectError('unsupported');
