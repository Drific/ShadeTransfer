// lib/services/encoding_service.dart

import 'dart:math';
import 'dart:typed_data';
import '../constants/charset.dart';
import '../constants/config.dart';

class EncodingService {
  EncodingService._();

  // ─── Base-55 encode / decode ────────────────────────────

  static String encodeBigInt(BigInt number) {
    if (number == BigInt.zero) {
      return Charset.charAt(0);
    }

    final buf = StringBuffer();
    var n = number;
    while (n > BigInt.zero) {
      buf.write(Charset.charAt((n % BigInt.from(Charset.base)).toInt()));
      n ~/= BigInt.from(Charset.base);
    }

    return buf.toString().split('').reversed.join();
  }

  static BigInt decodeBigInt(String encoded) {
    var result = BigInt.zero;
    for (int i = 0; i < encoded.length; i++) {
      final idx = Charset.indexOf(encoded[i]);
      if (idx < 0) {
        throw FormatException('Invalid character: ${encoded[i]}');
      }
      result = result * BigInt.from(Charset.base) + BigInt.from(idx);
    }
    return result;
  }

  // ─── Bytes ↔ BigInt ─────────────────────────────────────

  static BigInt bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static List<int> bigIntToBytes(BigInt number, int length) {
    final bytes = Uint8List(length);
    var n = number;
    for (int i = length - 1; i >= 0; i--) {
      bytes[i] = (n & BigInt.from(0xFF)).toInt();
      n >>= 8;
    }
    return bytes;
  }

  // ─── Convenience: bytes → base-55 string ────────────────

  static String encodeBytes(List<int> bytes) {
    return encodeBigInt(bytesToBigInt(bytes));
  }

  static List<int> decodeBytes(String encoded, int byteLength) {
    return bigIntToBytes(decodeBigInt(encoded), byteLength);
  }

  // ─── Random string (from charset) ───────────────────────

  static String randomString(int length) {
    final rng = Random.secure();
    return List.generate(
      length,
      (_) => Charset.charAt(rng.nextInt(Charset.base)),
    ).join();
  }

  // ─── ICE candidate encoding (IP + port → 5 chars) ───────

  static String encodeIceCandidate(String ip, int port) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      throw FormatException('Expected IPv4, got: $ip');
    }
    if (port < Config.portRangeMin || port > Config.portRangeMax) {
      throw RangeError(
        'Port must be ${Config.portRangeMin}-${Config.portRangeMax}',
      );
    }

    final a = int.parse(parts[2]); // 0-255
    final b = int.parse(parts[3]); // 0-255
    final portOffset = port - Config.portRangeMin; // 0-150

    // a(8 bits) + b(8 bits) + portOffset(8 bits) = 24 bits
    final value = (a << 16) | (b << 8) | portOffset;

    return encodeBigInt(BigInt.from(value)).padLeft(5, Charset.charAt(0));
  }

  static ({String ip, int port}) decodeIceCandidate(String encoded) {
    final value = decodeBigInt(encoded).toInt();
    final a = (value >> 16) & 0xFF;
    final b = (value >> 8) & 0xFF;
    final portOffset = value & 0xFF;
    final port = Config.portRangeMin + portOffset;

    return (ip: '192.168.$a.$b', port: port);
  }

  // ─── Checksum ───────────────────────────────────────────

  static String checksum(String data) {
    int hash = 0;
    for (int i = 0; i < data.length; i++) {
      hash ^= data.codeUnitAt(i) << ((i % 4) * 8);
      hash = hash & 0xFFFFFFFF;
    }
    return encodeBigInt(BigInt.from(hash))
        .padLeft(Config.checksumLength, Charset.charAt(0))
        .substring(0, Config.checksumLength);
  }

  static bool verifyChecksum(String data, String expected) {
    return checksum(data) == expected;
  }

  // ─── Validation ─────────────────────────────────────────

  static bool isValidSignal(String signal) {
    if (signal.isEmpty) return false;
    for (int i = 0; i < signal.length; i++) {
      if (!Charset.isValid(signal[i])) return false;
    }
    return true;
  }
}
