/// Release switches decided at build time.
///
/// Override one with --dart-define, e.g. --dart-define=V2_ORG_CREATION=true.
/// The server has its own copy of each switch (functions/index.js) and refuses
/// the feature while its switch is off, so both must be turned on together.
class ReleaseFlags {
  static const _environment = String.fromEnvironment('APP_ENV', defaultValue: 'existing');

  /// G8: new organizations are created as version 2 (server-managed access,
  /// roles, Gmail staff). On in staging builds; production waits until v2 has
  /// the calendar and statistics.
  static const v2OrganizationCreation = bool.fromEnvironment(
    'V2_ORG_CREATION',
    defaultValue: _environment == 'staging',
  );
}
