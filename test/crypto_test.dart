// test/crypto_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shade_transfer/constants/charset.dart';
import 'package:shade_transfer/constants/config.dart';
import 'package:shade_transfer/services/crypto_service.dart';
import 'package:shade_transfer/services/encoding_service.dart';

void main() {
  group('Random material', () {
    test('randomBytes has correct length and is random-ish', () {
      final a = CryptoService.randomBytes(32);
      final b = CryptoService.randomBytes(32);
      expect(a.length, 32);
      expect(b.length, 32);
      expect(a, isNot(equals(b)));
    });

    test('newSalt produces distinct salts', () {
      final s1 = CryptoService.newSalt();
      final s2 = CryptoService.newSalt();
      expect(s1.length, 16);
      expect(s1, isNot(equals(s2)));
    });

    test('newSessionKey uses the 55-character set', () {
      final key = CryptoService.newSessionKey();
      expect(key.length, Config.sessionKeyLength);
      expect(EncodingService.isValidSignal(key), true);
    });
  });

  group('HKDF', () {
    test('deterministic for same input', () {
      final ikm = utf8.encode('device-identifier');
      final salt = Uint8List.fromList(List.filled(16, 0xAA));
      final info = utf8.encode('info');

      final k1 = CryptoService.hkdf(ikm, salt: salt, info: info, length: 32);
      final k2 = CryptoService.hkdf(ikm, salt: salt, info: info, length: 32);

      expect(k1, equals(k2));
      expect(k1.length, 32);
    });

    test('different salt or ikm produce different keys', () {
      final salt = Uint8List(16);
      final k1 = CryptoService.hkdf(
        utf8.encode('aaa'),
        salt: salt,
        info: utf8.encode('x'),
        length: 32,
      );
      final k2 = CryptoService.hkdf(
        utf8.encode('aab'),
        salt: salt,
        info: utf8.encode('x'),
        length: 32,
      );
      final k3 = CryptoService.hkdf(
        utf8.encode('aaa'),
        salt: Uint8List.fromList(Uint8List(16)..[0] = 1),
        info: utf8.encode('x'),
        length: 32,
      );

      expect(k1, isNot(equals(k2)));
      expect(k1, isNot(equals(k3)));
    });

    test('output lengths split cleanly', () {
      final prk = CryptoService.hkdfExtract(
          utf8.encode('salt'), utf8.encode('ikm'));
      final a = CryptoService.hkdfExpand(prk, utf8.encode('seal'), 64);
      expect(a.length, 64);
      expect(
        a.sublist(0, 32),
        isNot(equals(a.sublist(32))),
        reason: 'Enc and MAC subkeys should differ',
      );
    });

    test('rejects non-positive output length', () {
      final prk = CryptoService.hkdfExtract(
          utf8.encode('salt'), utf8.encode('ikm'));
      expect(
        () => CryptoService.hkdfExpand(prk, <int>[], 0),
        throwsArgumentError,
      );
    });
  });

  group('ChaCha20 raw cipher', () {
    test('encrypt-decrypt round trip with same key/nonce', () {
      final key = CryptoService.randomBytes(32);
      final nonce = CryptoService.randomBytes(12);
      final data = CryptoService.randomBytes(1000);

      final ct = CryptoService.chacha20(key, nonce, data);
      final pt = CryptoService.chacha20(key, nonce, ct);

      expect(pt, equals(data));
      expect(ct, isNot(equals(data)));
    });

    test('different nonce yields different ciphertext', () {
      final key = CryptoService.randomBytes(32);
      final data = Uint8List.fromList(utf8.encode('same plaintext'));
      final c1 =
          CryptoService.chacha20(key, CryptoService.randomBytes(12), data);
      final c2 =
          CryptoService.chacha20(key, CryptoService.randomBytes(12), data);
      expect(c1, isNot(equals(c2)));
    });

    test('RFC 7539 section 2.4.2 known-answer vector', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final nonce =
          Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0x4a, 0, 0, 0, 0]);
      final plaintext = utf8.encode(
          "Ladies and Gentlemen of the class of '99: If I could offer "
          'you only one tip for the future, sunscreen would be it.');
      expect(plaintext.length, 114);

      const rfcCiphertextHex =
          '6e2e359a2568f98041ba0728dd0d6981'
          'e97e7aec1d4360c20a27afccfd9fae0b'
          'f91b65c5524733ab8f593dabcd62b357'
          '1639d624e65152ab8f530c359f0861d8'
          '07ca0dbf500d6a6156a38e088a22b65e'
          '52bc514d16ccf806818ce91ab7793736'
          '5af90bbf74a35be6b40b8eedf2785e42'
          '874d';
      final expected = Uint8List.fromList([
        for (var i = 0; i < rfcCiphertextHex.length; i += 2)
          int.parse(rfcCiphertextHex.substring(i, i + 2), radix: 16),
      ]);

      final padded = [...List<int>.filled(64, 0), ...plaintext];
      final ct = CryptoService.chacha20(key, nonce, padded);

      expect(ct.length, 64 + 114);
      expect(ct.sublist(64), equals(expected));
    });

    test('rejects wrong key and nonce sizes', () {
      final goodNonce = CryptoService.randomBytes(12);
      expect(
        () => CryptoService.chacha20(
            CryptoService.randomBytes(31), goodNonce, [0]),
        throwsArgumentError,
      );
      expect(
        () => CryptoService.chacha20(CryptoService.randomBytes(32),
            CryptoService.randomBytes(11), [0]),
        throwsArgumentError,
      );
    });
  });

  group('Seal / Open envelope', () {
    test('round trip preserves plaintext', () {
      final key = CryptoService.randomBytes(32);
      final plaintext = CryptoService.randomBytes(211);

      final sealed = CryptoService.seal(key, plaintext);
      expect(sealed.length, plaintext.length + 12 + 16);

      final opened = CryptoService.open(key, sealed);
      expect(opened, equals(plaintext));
    });

    test('empty plaintext works', () {
      final key = CryptoService.randomBytes(32);
      final sealed = CryptoService.seal(key, []);
      expect(sealed.length, 28);
      expect(CryptoService.open(key, sealed), isEmpty);
    });

    test('tampered ciphertext fails authentication', () {
      final key = CryptoService.randomBytes(32);
      final sealed = CryptoService.seal(key, utf8.encode('attack at dawn'));

      sealed[13] ^= 0xFF;
      expect(() => CryptoService.open(key, sealed), throwsA(isA<CryptoException>()));
    });

    test('tampered MAC fails authentication', () {
      final key = CryptoService.randomBytes(32);
      final sealed = CryptoService.seal(key, utf8.encode('hello'));

      sealed[sealed.length - 1] ^= 0x01;
      expect(() => CryptoService.open(key, sealed), throwsA(isA<CryptoException>()));
    });

    test('wrong key fails authentication', () {
      final sealed = CryptoService.seal(
          CryptoService.randomBytes(32), utf8.encode('secret'));
      expect(
        () => CryptoService.open(CryptoService.randomBytes(32), sealed),
        throwsA(isA<CryptoException>()),
      );
    });

    test('too-short payload rejected', () {
      expect(
        () => CryptoService.open(
            CryptoService.randomBytes(32), Uint8List(10)),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  group('Session key wrapping', () {
    late String deviceId;
    late String sessionKey;

    setUp(() {
      deviceId = EncodingService.randomString(Config.deviceIdLength);
      sessionKey = CryptoService.newSessionKey();
    });

    test('wrap then unwrap returns original key', () {
      final salt = CryptoService.newSalt();
      final wrapped = CryptoService.wrapSessionKey(sessionKey, deviceId, salt);

      expect(EncodingService.isValidSignal(sessionKey), true);
      expect(wrapped.length,
          12 + Config.sessionKeyLength + 16);

      final unwrapped =
          CryptoService.unwrapSessionKey(wrapped, deviceId, salt);
      expect(unwrapped, equals(sessionKey));
    });

    test('different salt produces different wrap', () {
      final w1 =
          CryptoService.wrapSessionKey(sessionKey, deviceId, CryptoService.newSalt());
      final w2 =
          CryptoService.wrapSessionKey(sessionKey, deviceId, CryptoService.newSalt());
      expect(w1, isNot(equals(w2)));
    });

    test('wrong device ID fails to unwrap', () {
      final salt = CryptoService.newSalt();
      final wrapped = CryptoService.wrapSessionKey(sessionKey, deviceId, salt);
      final other = EncodingService.randomString(Config.deviceIdLength);

      expect(
        () => CryptoService.unwrapSessionKey(wrapped, other, salt),
        throwsA(isA<CryptoException>()),
        reason: 'Only the owner of the device ID can recover the key',
      );
    });

    test('corrupted wrap fails to unwrap', () {
      final salt = CryptoService.newSalt();
      final wrapped = CryptoService.wrapSessionKey(sessionKey, deviceId, salt);
      wrapped[3] ^= 0xFF;

      expect(
        () => CryptoService.unwrapSessionKey(wrapped, deviceId, salt),
        throwsA(isA<CryptoException>()),
      );
    });

    test('validates device ID format', () {
      expect(
        () => CryptoService.wrapSessionKey(
            sessionKey, 'AB1DEFGH', CryptoService.newSalt()),
        throwsArgumentError,
      );
      expect(
        () => CryptoService.wrapSessionKey(
            sessionKey, 'ABCDEFG', CryptoService.newSalt()),
        throwsArgumentError,
      );
      expect(
        () => CryptoService.wrapSessionKey(
            sessionKey, 'ABCDEFGO', CryptoService.newSalt()),
        throwsArgumentError,
      );
    });

    test('validates session key format', () {
      expect(
        () => CryptoService.wrapSessionKey(
            'a1b2c3d4e5f6g7h8', deviceId, CryptoService.newSalt()),
        throwsArgumentError,
      );
      expect(
        () => CryptoService.wrapSessionKey(
            'shortkey', deviceId, CryptoService.newSalt()),
        throwsArgumentError,
      );
    });
  });

  group('Derive transfer key', () {
    test('derived from session key and salt', () {
      final sk = CryptoService.newSessionKey();
      final salt1 = CryptoService.newSalt();
      final salt2 = CryptoService.newSalt();

      expect(CryptoService.deriveTransferKey(sk, salt1).length, 32);
      expect(
        CryptoService.deriveTransferKey(sk, salt1),
        isNot(equals(CryptoService.deriveTransferKey(sk, salt2))),
      );
      expect(
        CryptoService.deriveTransferKey(sk, salt1),
        isNot(equals(
            CryptoService.deriveTransferKey(CryptoService.newSessionKey(), salt1))),
      );
    });

    test('all derived keys are 32 bytes over many runs', () {
      for (var i = 0; i < 50; i++) {
        expect(CryptoService.deriveTransferKey(
                CryptoService.newSessionKey(), CryptoService.newSalt())
            .length, 32);
      }
    });
  });

  group('Forbidden characters never leak', () {
    test('wrapped keys are pure base-55 numbers when encoded', () {
      for (var i = 0; i < 20; i++) {
        final wrapped = CryptoService.wrapSessionKey(
          CryptoService.newSessionKey(),
          EncodingService.randomString(Config.deviceIdLength),
          CryptoService.newSalt(),
        );
        final encoded = EncodingService.encodeBytesFixed(wrapped);
        expect(encoded.length, EncodingService.charsForBytes(wrapped.length));
        for (final c in ['o', 'O', '0', '1', 'I', 'l']) {
          expect(encoded.contains(c), false);
        }
      }
    });

    test('charset base stays 55', () {
      expect(Charset.base, 55);
    });
  });
}
