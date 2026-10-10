import 'device_session_io.dart'
    if (dart.library.js_interop) 'device_session_web.dart'
    as platform;

/// "Remember this computer" (2026-10-06, Tom). On the web, a person signing in
/// on a shared computer can untick it: the sign-in then ends when the browser
/// closes, and nothing is saved on the computer (no device copy). The choice
/// lasts for this browser session only. Phones always remember.
bool get rememberThisDevice => platform.rememberThisDevice;

/// Records the choice made at sign-in (web only; ignored elsewhere).
void setRememberThisDevice(bool remember) =>
    platform.setRememberThisDevice(remember);

/// Whether the sign-in screen offers the choice (web only).
const offerRememberThisDevice = platform.offerRememberThisDevice;

/// Removes the page's own loading screen (web/index.html) once the app has
/// drawn its first frame (2026-10-09, speed). Nothing elsewhere.
void hideStartScreen() => platform.hideStartScreen();
