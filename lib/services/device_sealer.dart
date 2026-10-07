import 'device_sealer_io.dart'
    if (dart.library.js_interop) 'device_sealer_web.dart'
    as platform;

/// Encrypts the device copy of server answers (2026-10-06, Tom: "keep it
/// encoded"). AES-GCM with a key that never leaves the device's protected
/// storage: on the web a browser key that cannot be read out (kept in the
/// browser's IndexedDB), on Android a key kept by Android's protected store
/// (flutter_secure_storage). Without the key the saved copy is unreadable.
abstract class DeviceSealer {
  /// Encrypts [plain]; throws when the device cannot (then nothing is saved).
  Future<String> seal(String plain);

  /// Decrypts; null when it cannot (key gone, data changed).
  Future<String?> open(String sealed);

  /// Throws the key away: everything sealed before can no longer be opened.
  Future<void> forgetKey();
}

/// The sealer for this platform.
DeviceSealer createDeviceSealer() => platform.createSealer();
