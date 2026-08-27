// lib/services/signal_service.dart

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../constants/charset.dart';
import '../constants/config.dart';
import 'crypto_service.dart';
import 'encoding_service.dart';

class SignalException implements Exception {
  final String message;
  SignalException(this.message);

  @override
  String toString() => 'SignalException: $message';
}

class SignalExpiredException extends SignalException {
  SignalExpiredException(super.message);
}

class SignalData {
  final Uint8List salt;
  final DateTime createdAt;
  final ({String ip, int port}) ice;
  final String sessionKey;
  final String? sdp;

  SignalData({
    required this.salt,
    required this.createdAt,
    required this.ice,
    required this.sessionKey,
    required this.sdp,
  });

  bool get isExpired =>
      DateTime.now().toUtc().difference(createdAt) > Config.signalExpiry;
}

class SignalService {
  SignalService._();

  static const String _version = 'A';
  static const int _saltSize = 16;
  static const int _tsChars = 5;
  static const int _sdpLenChars = 4;

  static final int _saltChars = EncodingService.charsForBytes(_saltSize);
  static final int _keyBlobChars =
      EncodingService.charsForBytes(CryptoService.nonceSize +
          Config.sessionKeyLength +
          CryptoService.macSize);

  static int get _fixedHeaderLength =>
      1 + _saltChars + _tsChars + _keyBlobChars + 5 + _sdpLenChars;
  static int get _minLength => _fixedHeaderLength + Config.checksumLength;

  static final BigInt _maxTimestamp =
      BigInt.from(pow(Charset.base, _tsChars).toInt()) - BigInt.one;

  // ─── Create ──────────────────────────────────────────────

  static String create({
    required String peerDeviceId,
    required String sessionKey,
    required String ip,
    required int port,
    String? sdp,
    DateTime? now,
  }) {
    final salt = CryptoService.newSalt();
    final createdAt = (now ?? DateTime.now()).toUtc();
    final tsMinutes =
        BigInt.from(createdAt.millisecondsSinceEpoch ~/ Duration.millisecondsPerMinute);

    if (tsMinutes > _maxTimestamp || tsMinutes < BigInt.zero) {
      throw RangeError('Timestamp out of representable range');
    }

    final wrappedKey =
        CryptoService.wrapSessionKey(sessionKey, peerDeviceId, salt);
    final ice = EncodingService.encodeIceCandidate(ip, port);

    final hasSdp = sdp != null && sdp.isNotEmpty;
    Uint8List sealedSdp = Uint8List(0);
    if (hasSdp) {
      final transferKey = CryptoService.deriveTransferKey(sessionKey, salt);
      sealedSdp = CryptoService.seal(transferKey, utf8.encode(sdp));
    }

    final buf = StringBuffer()
      ..write(_version)
      ..write(EncodingService.encodeBytesFixed(salt))
      ..write(EncodingService.encodeBigInt(tsMinutes, minLength: _tsChars))
      ..write(EncodingService.encodeBytesFixed(wrappedKey))
      ..write(ice)
      ..write(
        EncodingService.encodeBigInt(
          BigInt.from(sealedSdp.length),
          minLength: _sdpLenChars,
        ),
      );

    if (hasSdp) {
      buf.write(EncodingService.encodeBytesFixed(sealedSdp));
    }

    final payload = buf.toString();
    return payload + EncodingService.checksum(payload);
  }

  // ─── Parse ───────────────────────────────────────────────

  static SignalData parse({
    required String signal,
    required String ownDeviceId,
    bool allowExpired = false,
  }) {
    final cleaned = signal.replaceAll(RegExp(r'\s'), '');

    if (!EncodingService.isValidSignal(cleaned)) {
      throw SignalException('Signal contains characters outside '
          'the 55-character set');
    }
    if (cleaned.length < _minLength) {
      throw SignalException('Signal too short (${cleaned.length} chars)');
    }
    if (cleaned[0] != _version) {
      throw SignalException('Unsupported signal version: "${cleaned[0]}"');
    }

    final body = cleaned.substring(0, cleaned.length - Config.checksumLength);
    final checksum = cleaned.substring(cleaned.length - Config.checksumLength);
    if (!EncodingService.verifyChecksum(body, checksum)) {
      throw SignalException('Checksum mismatch');
    }

    var offset = 1;
    final salt = Uint8List.fromList(
      EncodingService.decodeBytesFixed(
        body.substring(offset, offset + _saltChars),
        _saltSize,
      ),
    );
    offset += _saltChars;

    final tsMinutes = EncodingService.decodeBigInt(
      body.substring(offset, offset + _tsChars),
    );
    offset += _tsChars;

    final keyBlob = Uint8List.fromList(
      EncodingService.decodeBytesFixed(
        body.substring(offset, offset + _keyBlobChars),
        CryptoService.nonceSize + Config.sessionKeyLength +
            CryptoService.macSize,
      ),
    );
    offset += _keyBlobChars;

    final ice = EncodingService.decodeIceCandidate(
      body.substring(offset, offset + 5),
    );
    offset += 5;

    final sdpLength =
        EncodingService.decodeBigInt(body.substring(offset, offset +
            _sdpLenChars)).toInt();
    offset += _sdpLenChars;

    final createdAt = DateTime.utc(1970)
        .add(Duration(minutes: tsMinutes.toInt()));

    if (!allowExpired &&
        DateTime.now().toUtc().difference(createdAt) >
            Config.signalExpiry) {
      throw SignalExpiredException(
        'Signal created $createdAt has expired',
      );
    }

    final remaining = body.length - offset;
    final expectedSdpChars =
        sdpLength == 0 ? 0 : EncodingService.charsForBytes(sdpLength);
    if (remaining != expectedSdpChars) {
      throw SignalException(
        'Malformed signal: expected $expectedSdpChars SDP characters, '
        'found $remaining',
      );
    }

    final sessionKey =
        CryptoService.unwrapSessionKey(keyBlob, ownDeviceId, salt);

    String? sdp;
    if (sdpLength > 0) {
      final sealedSdp = Uint8List.fromList(
        EncodingService.decodeBytesFixed(
          body.substring(offset, offset + expectedSdpChars),
          sdpLength,
        ),
      );
      try {
        final transferKey =
            CryptoService.deriveTransferKey(sessionKey, salt);
        final plaintext = CryptoService.open(transferKey, sealedSdp);
        sdp = utf8.decode(plaintext);
      } on CryptoException catch (e) {
        throw SignalException('Failed to decrypt SDP: ${e.message}');
      }
    }

    return SignalData(
      salt: salt,
      createdAt: createdAt,
      ice: ice,
      sessionKey: sessionKey,
      sdp: sdp,
    );
  }

  // ─── Display helpers ─────────────────────────────────────

  static String formatForDisplay(String signal) {
    final cleaned = signal.replaceAll(RegExp(r'\s'), '');
    final buf = StringBuffer();
    for (var i = 0; i < cleaned.length; i++) {
      if (i > 0 && i % 5 == 0) buf.write(' ');
      buf.write(cleaned[i]);
    }
    return buf.toString();
  }
}
