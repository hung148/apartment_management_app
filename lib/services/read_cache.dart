import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_sealer.dart';

/// A server answer, and whether it is the copy saved on this device (shown
/// right away while the server is asked again) or the server's fresh answer.
class Saved<T> {
  const Saved(this.data, {required this.saved, required this.at});
  final T data;

  /// True: the copy saved on this device. False: just came from the server.
  final bool saved;

  /// When this answer came from the server.
  final DateTime at;
}

/// The copy of server answers kept on this device (2026-10-06, speed step 1).
///
/// Only for showing a screen right away: every screen still asks the server
/// and replaces the copy with the fresh answer, and every change still goes to
/// the server, which checks everything. The copy belongs to one signed-in
/// account: signing out or switching account wipes it (main.dart), and an
/// access error from the server wipes that organization's copy. Old copies
/// (over [maxAge]) and the oldest ones beyond [maxEntries] / [maxChars] are
/// dropped. Everything saved is encrypted ([DeviceSealer]); if the device
/// cannot encrypt, nothing is saved. On a computer the person did not ask to
/// remember ([enabled] false), nothing is saved at all.
class ReadCache {
  ReadCache(
    this._prefs, {
    required String? Function() account,
    required DeviceSealer sealer,
    bool Function()? enabled,
    DateTime Function()? now,
  }) : _account = account,
       _sealer = sealer,
       _enabled = enabled ?? (() => true),
       _now = now ?? DateTime.now;

  /// The app's copy, set in main.dart. Null in tests unless a test sets one.
  static ReadCache? shared;

  static const _prefix = 'rc1|';
  static const maxEntries = 40;
  static const maxChars = 3000000;
  static const maxAge = Duration(days: 30);

  final SharedPreferences _prefs;
  final String? Function() _account;
  final DeviceSealer _sealer;
  final bool Function() _enabled;
  final DateTime Function() _now;

  /// The same request always gives the same key, whatever the map order.
  static Object? _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _canonical(v[k])};
    }
    if (v is List) return [for (final x in v) _canonical(x)];
    return v;
  }

  String? _key(String call, Map<String, dynamic> payload) {
    final account = _account();
    if (account == null || account.isEmpty) return null;
    final id = sha256
        .convert(utf8.encode(jsonEncode([call, _canonical(payload)])))
        .toString()
        .substring(0, 32);
    return '$_prefix$account|$id';
  }

  /// Stored as "<savedAt ms>|<organization>|<json>".
  static (int, String, String)? _split(String? raw) {
    if (raw == null) return null;
    final a = raw.indexOf('|');
    final b = a < 0 ? -1 : raw.indexOf('|', a + 1);
    if (b < 0) return null;
    final at = int.tryParse(raw.substring(0, a));
    if (at == null) return null;
    return (at, raw.substring(a + 1, b), raw.substring(b + 1));
  }

  /// The saved answer to this request, or null.
  Future<Saved<Map<String, dynamic>>?> read(
    String call,
    Map<String, dynamic> payload,
  ) async {
    if (!_enabled()) return null;
    final key = _key(call, payload);
    if (key == null) return null;
    final parts = _split(_prefs.getString(key));
    if (parts == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(parts.$1);
    if (_now().difference(at) > maxAge) {
      _prefs.remove(key);
      return null;
    }
    try {
      final plain = await _sealer.open(parts.$3);
      // Key gone or data changed: this copy can never be read again.
      if (plain == null) {
        await _prefs.remove(key);
        return null;
      }
      // Signed out or switched account while decrypting.
      if (_key(call, payload) != key) return null;
      final data = jsonDecode(plain);
      if (data is! Map) return null;
      return Saved(Map<String, dynamic>.from(data), saved: true, at: at);
    } catch (_) {
      _prefs.remove(key);
      return null;
    }
  }

  /// Saves the server's answer to this request. Never fails the caller.
  Future<void> write(
    String call,
    Map<String, dynamic> payload,
    Map<String, dynamic> data, {
    String? organizationId,
  }) async {
    if (!_enabled()) return;
    final key = _key(call, payload);
    if (key == null) return;
    try {
      final json = jsonEncode(data);
      if (json.length > maxChars ~/ 4) {
        await _prefs.remove(key);
        return;
      }
      final org = (organizationId ?? '').replaceAll('|', '');
      final sealed = await _sealer.seal(json);
      // Signed out or switched account while encrypting: save nothing.
      if (_key(call, payload) != key || !_enabled()) return;
      await _prefs.setString(key, '${_now().millisecondsSinceEpoch}|$org|$sealed');
      await _trim();
    } catch (_) {
      // Full storage (web limit): drop the copy rather than fail the screen.
      await clear();
    }
  }

  Iterable<String> get _keys =>
      _prefs.getKeys().where((k) => k.startsWith(_prefix));

  Future<void> _trim() async {
    final entries = <(String, int, int)>[];
    var total = 0;
    for (final k in _keys) {
      final raw = _prefs.getString(k);
      final parts = _split(raw);
      if (parts == null) {
        await _prefs.remove(k);
        continue;
      }
      entries.add((k, parts.$1, raw!.length));
      total += raw.length;
    }
    entries.sort((a, b) => a.$2.compareTo(b.$2));
    var i = 0;
    while (i < entries.length &&
        (entries.length - i > maxEntries || total > maxChars)) {
      total -= entries[i].$3;
      await _prefs.remove(entries[i].$1);
      i++;
    }
  }

  /// Wipes every copy not belonging to [account] (all of them when null):
  /// sign-out and account switch. Signing out also throws the key away, so
  /// anything missed can never be opened.
  Future<void> keepOnlyAccount(String? account) async {
    final mine = account == null ? null : '$_prefix$account|';
    for (final k in _keys.toList()) {
      if (mine == null || !k.startsWith(mine)) await _prefs.remove(k);
    }
    if (account == null) await _sealer.forgetKey();
  }

  /// Wipes this account's copies of one organization (access removed).
  Future<void> forgetOrganization(String organizationId) async {
    final account = _account();
    for (final k in _keys.toList()) {
      if (account != null && !k.startsWith('$_prefix$account|')) continue;
      final parts = _split(_prefs.getString(k));
      if (parts == null || parts.$2 == organizationId) await _prefs.remove(k);
    }
  }

  /// Wipes every copy and throws the key away.
  Future<void> clear() async {
    for (final k in _keys.toList()) {
      await _prefs.remove(k);
    }
    await _sealer.forgetKey();
  }

  /// Errors that mean this account may no longer see the organization.
  static bool isAccessError(Object e) =>
      e is FirebaseFunctionsException &&
      const {'permission-denied', 'unauthenticated', 'not-found'}.contains(e.code);
}
