import 'package:web/web.dart' as web;

// Kept in sessionStorage: gone when the browser (or this tab) closes, exactly
// like a sign-in made without "Remember this computer".
const _forget = 'canho360_forget_device';

bool get rememberThisDevice {
  try {
    return web.window.sessionStorage.getItem(_forget) != '1';
  } catch (_) {
    return false; // storage blocked: save nothing
  }
}

void setRememberThisDevice(bool remember) {
  try {
    if (remember) {
      web.window.sessionStorage.removeItem(_forget);
    } else {
      web.window.sessionStorage.setItem(_forget, '1');
    }
  } catch (_) {}
}

const offerRememberThisDevice = true;

/// The loading screen in web/index.html, shown from the first moment the page
/// opens until the app draws (2026-10-09, speed).
void hideStartScreen() {
  try {
    web.document.getElementById('start-screen')?.remove();
  } catch (_) {}
}
