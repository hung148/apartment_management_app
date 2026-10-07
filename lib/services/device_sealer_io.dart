import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'device_sealer.dart';

DeviceSealer createSealer() => _SecureStoreSealer();

/// Android: a random AES-GCM key kept by Android's protected store
/// (flutter_secure_storage, backed by the Android Keystore). The saved copy
/// holds only "<12-byte nonce + ciphertext + 16-byte tag>" in base64.
class _SecureStoreSealer implements DeviceSealer {
  static const _id = 'canho360_readcache_key';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _aes = AesGcm.with256bits();
  Future<SecretKey>? _key;

  Future<SecretKey> _loadOrMake() async {
    final saved = await _storage.read(key: _id);
    if (saved != null) {
      try {
        final bytes = base64Decode(saved);
        if (bytes.length == 32) return SecretKey(bytes);
      } catch (_) {}
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(key: _id, value: base64Encode(bytes));
    return SecretKey(bytes);
  }

  Future<SecretKey> get _keyNow {
    final key = _key ??= _loadOrMake();
    return key.catchError((Object e) {
      _key = null;
      throw e;
    });
  }

  @override
  Future<String> seal(String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: await _keyNow);
    return base64Encode(box.concatenation());
  }

  @override
  Future<String?> open(String sealed) async {
    try {
      final box = SecretBox.fromConcatenation(
        base64Decode(sealed),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      return utf8.decode(await _aes.decrypt(box, secretKey: await _keyNow));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> forgetKey() async {
    _key = null;
    try {
      await _storage.delete(key: _id);
    } catch (_) {}
  }
}
