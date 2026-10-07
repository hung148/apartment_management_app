import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'device_sealer.dart';

DeviceSealer createSealer() => _WebSealer();

/// Web: a browser AES-GCM key made "not extractable" (the page can use it but
/// never read it out), stored in IndexedDB. The saved copy in localStorage is
/// only "<12-byte iv + ciphertext>" in base64.
class _WebSealer implements DeviceSealer {
  static const _dbName = 'canho360-device', _store = 'keys', _id = 'readcache';
  Future<web.CryptoKey>? _key;
  final _random = Random.secure();

  static Future<T> _done<T extends JSAny?>(web.IDBRequest request) {
    final c = Completer<T>();
    request.onsuccess = ((web.Event _) => c.complete(request.result as T)).toJS;
    request.onerror = ((web.Event _) =>
        c.completeError(StateError('device_storage_unavailable'))).toJS;
    return c.future;
  }

  Future<web.IDBDatabase> _db() {
    final c = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_dbName, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_store);
    }).toJS;
    request.onsuccess = ((web.Event _) =>
        c.complete(request.result as web.IDBDatabase)).toJS;
    request.onerror = ((web.Event _) =>
        c.completeError(StateError('device_storage_unavailable'))).toJS;
    return c.future;
  }

  Future<web.CryptoKey> _loadOrMake() async {
    final db = await _db();
    try {
      final saved = await _done<JSAny?>(
        db.transaction(_store.toJS, 'readonly').objectStore(_store).get(_id.toJS),
      );
      if (saved != null && saved.isA<web.CryptoKey>()) {
        return saved as web.CryptoKey;
      }
      final made = await web.window.crypto.subtle
          .generateKey(
            {'name': 'AES-GCM', 'length': 256}.jsify() as JSObject,
            false, // not extractable: the key can never be read out
            ['encrypt'.toJS, 'decrypt'.toJS].toJS,
          )
          .toDart;
      final key = made as web.CryptoKey;
      await _done<JSAny?>(
        db.transaction(_store.toJS, 'readwrite').objectStore(_store).put(key, _id.toJS),
      );
      return key;
    } finally {
      db.close();
    }
  }

  Future<web.CryptoKey> get _keyNow {
    final key = _key ??= _loadOrMake();
    // A failed attempt is tried again next time.
    return key.catchError((Object e) {
      _key = null;
      throw e;
    });
  }

  @override
  Future<String> seal(String plain) async {
    final key = await _keyNow;
    final iv = Uint8List.fromList(List.generate(12, (_) => _random.nextInt(256)));
    final sealed = await web.window.crypto.subtle
        .encrypt(
          {'name': 'AES-GCM', 'iv': iv.toJS}.jsify() as JSObject,
          key,
          Uint8List.fromList(utf8.encode(plain)).toJS,
        )
        .toDart;
    final body = (sealed as JSArrayBuffer).toDart.asUint8List();
    return base64Encode([...iv, ...body]);
  }

  @override
  Future<String?> open(String sealed) async {
    try {
      final bytes = base64Decode(sealed);
      if (bytes.length < 13) return null;
      final key = await _keyNow;
      final plain = await web.window.crypto.subtle
          .decrypt(
            {'name': 'AES-GCM', 'iv': bytes.sublist(0, 12).toJS}.jsify() as JSObject,
            key,
            bytes.sublist(12).toJS,
          )
          .toDart;
      return utf8.decode((plain as JSArrayBuffer).toDart.asUint8List());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> forgetKey() async {
    _key = null;
    try {
      final db = await _db();
      try {
        await _done<JSAny?>(
          db.transaction(_store.toJS, 'readwrite').objectStore(_store).delete(_id.toJS),
        );
      } finally {
        db.close();
      }
    } catch (_) {}
  }
}
