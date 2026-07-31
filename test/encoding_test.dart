// test/encoding_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shade_transfer/constants/charset.dart';
import 'package:shade_transfer/services/encoding_service.dart';

void main() {
  group('Charset', () {
    test('has 55 characters', () {
      expect(Charset.base, 55);
      expect(Charset.all.length, 55);
    });

    test('excludes confusable characters', () {
      const forbidden = ['o', 'O', '0', '1', 'i', 'I', 'l'];
      for (final c in forbidden) {
        expect(Charset.all.contains(c), false, reason: 'Should exclude "$c"');
      }
    });

    test('no duplicates', () {
      final unique = Charset.all.split('').toSet();
      expect(unique.length, 55);
    });
  });

  group('Base-55 encoding', () {
    test('round-trip for zero', () {
      final encoded = EncodingService.encodeBigInt(BigInt.zero);
      final decoded = EncodingService.decodeBigInt(encoded);
      expect(decoded, BigInt.zero);
    });

    test('round-trip for small numbers', () {
      for (int i = 0; i < 1000; i++) {
        final n = BigInt.from(i);
        final encoded = EncodingService.encodeBigInt(n);
        final decoded = EncodingService.decodeBigInt(encoded);
        expect(decoded, n, reason: 'Failed at $i');
      }
    });

    test('round-trip for random strings', () {
      for (int i = 0; i < 500; i++) {
        final len = 1 + (i % 20);
        final original = EncodingService.randomString(len);
        final decoded = EncodingService.decodeBigInt(original);
        final reencoded =
            EncodingService.encodeBigInt(decoded, minLength: len);
        expect(reencoded, original, reason: 'Failed at $i');
      }
    });

    test('round-trip for large numbers', () {
      final big = BigInt.from(2).pow(128) - BigInt.one;
      final encoded = EncodingService.encodeBigInt(big);
      final decoded = EncodingService.decodeBigInt(encoded);
      expect(decoded, big);
    });

    test('rejects invalid characters', () {
      expect(
        () => EncodingService.decodeBigInt('o'),
        throwsFormatException,
      );
      expect(
        () => EncodingService.decodeBigInt('I'),
        throwsFormatException,
      );
      expect(
        () => EncodingService.decodeBigInt('0'),
        throwsFormatException,
      );
    });
  });

  group('ICE candidate encoding', () {
    test('round-trip for typical LAN address', () {
      final encoded =
          EncodingService.encodeIceCandidate('192.168.1.100', 8080);
      final result = EncodingService.decodeIceCandidate(encoded);
      expect(result.ip, '192.168.1.100');
      expect(result.port, 8080);
    });

    test('round-trip for port range boundaries', () {
      final low = EncodingService.encodeIceCandidate('192.168.0.2', 8000);
      final r1 = EncodingService.decodeIceCandidate(low);
      expect(r1.ip, '192.168.0.2');
      expect(r1.port, 8000);

      final high =
          EncodingService.encodeIceCandidate('192.168.255.254', 8150);
      final r2 = EncodingService.decodeIceCandidate(high);
      expect(r2.ip, '192.168.255.254');
      expect(r2.port, 8150);
    });

    test('rejects port out of range', () {
      expect(
        () => EncodingService.encodeIceCandidate('192.168.1.1', 7999),
        throwsRangeError,
      );
      expect(
        () => EncodingService.encodeIceCandidate('192.168.1.1', 8151),
        throwsRangeError,
      );
    });

    test('encoded result contains no forbidden characters', () {
      for (int p = 8000; p <= 8150; p += 7) {
        final encoded =
            EncodingService.encodeIceCandidate('192.168.1.100', p);
        for (final c in ['o', 'O', '0', '1', 'I', 'l']) {
          expect(encoded.contains(c), false,
              reason: 'ICE encoding for port $p contains "$c"');
        }
      }
    });
  });

  group('Checksum', () {
    test('detects correct data', () {
      final data = 'test data here';
      final cs = EncodingService.checksum(data);
      expect(EncodingService.verifyChecksum(data, cs), true);
    });

    test('detects single character change', () {
      final data = 'test data here';
      final cs = EncodingService.checksum(data);
      expect(EncodingService.verifyChecksum('test data herf', cs), false);
    });

    test('produces fixed length', () {
      for (int i = 0; i < 100; i++) {
        final data = EncodingService.randomString(i);
        final cs = EncodingService.checksum(data);
        expect(cs.length, 4);
      }
    });

    test('checksum contains no forbidden characters', () {
      for (int i = 0; i < 200; i++) {
        final data = EncodingService.randomString(i);
        final cs = EncodingService.checksum(data);
        for (final c in ['o', 'O', '0', '1', 'I', 'l']) {
          expect(cs.contains(c), false);
        }
      }
    });
  });

  group('Random string', () {
    test('correct length', () {
      for (int len = 1; len <= 32; len++) {
        expect(EncodingService.randomString(len).length, len);
      }
    });

    test('only contains valid characters', () {
      for (int i = 0; i < 100; i++) {
        final s = EncodingService.randomString(16);
        expect(EncodingService.isValidSignal(s), true);
      }
    });
  });
}