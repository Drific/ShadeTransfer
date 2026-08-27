// lib/services/crypto_service.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart' as pc;

import '../constants/config.dart';
import 'encoding_service.dart';

class CryptoException implements Exception {
  final String message;
  CryptoException(this.message);

  @override
  String toString() => 'CryptoException: $message';
}

class CryptoService {
  CryptoService._();

  static const int keySize = 32;
  static const int nonceSize = 12;
  static const int macSize = 16;
  static const int saltSize = 16;

  static final Random _rng = Random.secure();

  static const String _wrapInfo = 'ShadeTransfer/v1/key-wrap';
  static const String _dataInfo = 'ShadeTransfer/v1/data';
  static const String _sealInfo = 'ShadeTransfer/v1/seal';

  // ─── Random material ─────────────────────────────────────

  static Uint8List randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _rng.nextInt(256)),
    );
  }

  static Uint8List newSalt() => randomBytes(saltSize);

  static String newSessionKey() =>
      EncodingService.randomString(Config.sessionKeyLength);

  // ─── HKDF (RFC 5869) ─────────────────────────────────────

  static Uint8List hkdfExtract(List<int> salt, List<int> ikm) {
    final actualSalt =
        salt.isEmpty ? Uint8List(keySize) : Uint8List.fromList(salt);
    return _hmac(actualSalt, ikm);
  }

  static Uint8List hkdfExpand(
    List<int> prk,
    List<int> info,
    int length,
  ) {
    if (length <= 0) {
      throw ArgumentError('HKDF output length must be positive');
    }
    final hashLen = 32;
    final iterations = (length + hashLen - 1) ~/ hashLen;
    if (iterations > 255) {
      throw ArgumentError('HKDF output length too large');
    }

    final okm = BytesBuilder();
    var previous = <int>[];
    for (var i = 1; i <= iterations; i++) {
      previous = _hmac(prk, [...previous, ...info, i]);
      okm.add(previous);
    }
    return Uint8List.sublistView(okm.toBytes(), 0, length);
  }

  static Uint8List hkdf(
    List<int> ikm, {
    required List<int> salt,
    required List<int> info,
    required int length,
  }) {
    return hkdfExpand(hkdfExtract(salt, ikm), info, length);
  }

  // ─── Key derivation ──────────────────────────────────────

  static Uint8List deriveWrappingKey(String deviceId, Uint8List salt) {
    _validateDeviceId(deviceId);
    return hkdf(
      utf8.encode(deviceId),
      salt: salt,
      info: utf8.encode(_wrapInfo),
      length: keySize,
    );
  }

  static Uint8List deriveTransferKey(String sessionKey, Uint8List salt) {
    _validateSessionKey(sessionKey);
    return hkdf(
      utf8.encode(sessionKey),
      salt: salt,
      info: utf8.encode(_dataInfo),
      length: keySize,
    );
  }

  // ─── ChaCha20 (RFC 7539) stream cipher ───────────────────

  static Uint8List chacha20(Uint8List key, Uint8List nonce, List<int> data) {
    if (key.length != keySize) {
      throw ArgumentError('ChaCha20 key must be $keySize bytes');
    }
    if (nonce.length != nonceSize) {
      throw ArgumentError('ChaCha20 nonce must be $nonceSize bytes');
    }

    final cipher = pc.ChaCha7539Engine()
      ..init(true, pc.ParametersWithIV(pc.KeyParameter(key), nonce));
    return cipher.process(Uint8List.fromList(data));
  }

  // ─── Authenticated envelope: nonce ‖ ciphertext ‖ mac ────

  static Uint8List seal(Uint8List masterKey, List<int> plaintext) {
    final subkeys =
        hkdfExpand(masterKey, utf8.encode(_sealInfo), keySize * 2);
    final encKey = Uint8List.sublistView(subkeys, 0, keySize);
    final macKey = Uint8List.sublistView(subkeys, keySize);

    final nonce = randomBytes(nonceSize);
    final ciphertext = chacha20(encKey, nonce, plaintext);
    final mac =
        Uint8List.sublistView(_hmac(macKey, [...nonce, ...ciphertext]), 0,
            macSize);

    final out = BytesBuilder();
    out.add(nonce);
    out.add(ciphertext);
    out.add(mac);
    return out.toBytes();
  }

  static Uint8List open(Uint8List masterKey, Uint8List sealed) {
    if (sealed.length < nonceSize + macSize) {
      throw CryptoException('Sealed payload too short');
    }

    final subkeys =
        hkdfExpand(masterKey, utf8.encode(_sealInfo), keySize * 2);
    final encKey = Uint8List.sublistView(subkeys, 0, keySize);
    final macKey = Uint8List.sublistView(subkeys, keySize);

    final nonce = Uint8List.sublistView(sealed, 0, nonceSize);
    final ciphertext =
        Uint8List.sublistView(sealed, nonceSize, sealed.length - macSize);
    final receivedMac =
        Uint8List.sublistView(sealed, sealed.length - macSize);

    final expectedMac = Uint8List.sublistView(
        _hmac(macKey, [...nonce, ...ciphertext]), 0, macSize);

    if (!_constantTimeEquals(receivedMac, expectedMac)) {
      throw CryptoException('Authentication failed');
    }

    return chacha20(encKey, nonce, ciphertext);
  }

  // ─── Session key wrapping ────────────────────────────────

  static Uint8List wrapSessionKey(
    String sessionKey,
    String peerDeviceId,
    Uint8List salt,
  ) {
    _validateSessionKey(sessionKey);
    final wrappingKey = deriveWrappingKey(peerDeviceId, salt);
    return seal(wrappingKey, utf8.encode(sessionKey));
  }

  static String unwrapSessionKey(
    Uint8List wrapped,
    String ownDeviceId,
    Uint8List salt,
  ) {
    final wrappingKey = deriveWrappingKey(ownDeviceId, salt);
    late final Uint8List plaintext;
    try {
      plaintext = open(wrappingKey, wrapped);
    } on CryptoException {
      throw CryptoException('Wrong device ID or corrupted signal');
    }
    try {
      return utf8.decode(plaintext);
    } on FormatException {
      throw CryptoException('Decrypted session key is not valid UTF-8');
    }
  }

  // ─── Internal helpers ────────────────────────────────────

  static Uint8List _hmac(List<int> key, List<int> data) {
    return Uint8List.fromList(
      crypto.Hmac(crypto.sha256, key).convert(data).bytes,
    );
  }

  static bool _constantTimeEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static void _validateDeviceId(String deviceId) {
    if (deviceId.length != Config.deviceIdLength ||
        !EncodingService.isValidSignal(deviceId)) {
      throw ArgumentError(
        'Device ID must be ${Config.deviceIdLength} '
        'characters from the 55-character set',
      );
    }
  }

  static void _validateSessionKey(String sessionKey) {
    if (sessionKey.length != Config.sessionKeyLength ||
        !EncodingService.isValidSignal(sessionKey)) {
      throw ArgumentError(
        'Session key must be ${Config.sessionKeyLength} '
        'characters from the 55-character set',
      );
    }
  }
}
