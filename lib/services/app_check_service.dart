import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

/// Call before Auth/Firestore/Functions are used. No release bypass or baked-in
/// debug token: provider registration is part of the coordinated release.
Future<void> activateAppCheck() async {
  const siteKey = String.fromEnvironment('APP_CHECK_WEB_SITE_KEY');
  if (kIsWeb && siteKey.trim().isEmpty) {
    throw StateError('APP_CHECK_WEB_SITE_KEY is required for the connected app. '
        'Use lib/team_preview.dart for the disconnected local preview.');
  }
  if (!kIsWeb &&
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS &&
      defaultTargetPlatform != TargetPlatform.macOS) {
    throw UnsupportedError('App Check is not configured for this platform. '
        'Use the web app until a supported attestation provider is available.');
  }
  await FirebaseAppCheck.instance.activate(
    providerWeb: kIsWeb ? ReCaptchaEnterpriseProvider(siteKey) : null,
    providerAndroid: const AndroidPlayIntegrityProvider(),
    providerApple: const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
}
