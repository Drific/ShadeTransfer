// test/signal_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:shade_transfer/constants/config.dart';
import 'package:shade_transfer/services/crypto_service.dart';
import 'package:shade_transfer/services/encoding_service.dart';
import 'package:shade_transfer/services/signal_service.dart';

void main() {
  late String deviceId;
  late String sessionKey;

  setUp(() {
    deviceId = EncodingService.randomString(Config.deviceIdLength);
    sessionKey = CryptoService.newSessionKey();
  });

  group('Signal creation', () {
    test('creates valid fixed-length signal without SDP', () {
      final signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.1.100',
        port: 8080,
      );

      expect(EncodingService.isValidSignal(signal), true);
      expect(signal.length, 103);
    });

    test('appends variable-length encrypted SDP block', () {
      final noSdp = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.1.100',
        port: 8080,
      );
      final withSdp = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.1.100',
        port: 8080,
        sdp: "v=0\r\no=- 4611731400430051336 2 IN IP4 127.0.0.1\r\n",
      );

      expect(withSdp.length, greaterThan(noSdp.length));
      expect(EncodingService.isValidSignal(withSdp), true);
    });

    test('rejects invalid inputs', () {
      expect(
        () => SignalService.create(
          peerDeviceId: 'ABCDEFGO',
          sessionKey: sessionKey,
          ip: '192.168.1.100',
          port: 8080,
        ),
        throwsArgumentError,
      );
      expect(
        () => SignalService.create(
          peerDeviceId: deviceId,
          sessionKey: 'AB1DEFGH23456789',
          ip: '192.168.1.100',
          port: 8080,
        ),
        throwsArgumentError,
      );
      expect(
        () => SignalService.create(
          peerDeviceId: deviceId,
          sessionKey: sessionKey,
          ip: '10.0.0.5',
          port: 8080,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SignalService.create(
          peerDeviceId: deviceId,
          sessionKey: sessionKey,
          ip: '192.168.1.100',
          port: 9000,
        ),
        throwsRangeError,
      );
    });
  });

  group('Signal parsing', () {
    test('round trip without SDP', () {
      final signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.7.42',
        port: 8133,
      );

      final parsed = SignalService.parse(signal: signal, ownDeviceId: deviceId);

      expect(parsed.sessionKey, sessionKey);
      expect(parsed.ice.ip, '192.168.7.42');
      expect(parsed.ice.port, 8133);
      expect(parsed.sdp, isNull);
      expect(parsed.salt.length, 16);
      expect(parsed.isExpired, false);
    });

    test('round trip with SDP', () {
      const sdp = "v=0\r\no=- 1234567890 2 IN IP4 127.0.0.1\r\n"
          "s=-\r\nt=0 0\r\na=group:BUNDLE data\r\n";
      final signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.0.254',
        port: 8001,
        sdp: sdp,
      );

      final parsed = SignalService.parse(signal: signal, ownDeviceId: deviceId);

      expect(parsed.sessionKey, sessionKey);
      expect(parsed.ice.ip, '192.168.0.254');
      expect(parsed.ice.port, 8001);
      expect(parsed.sdp, sdp);
    });

    test('multiple round trips stay independent', () {
      for (var i = 0; i < 20; i++) {
        final own = EncodingService.randomString(Config.deviceIdLength);
        final key = CryptoService.newSessionKey();
        final port = 8000 + (i * 3) % 151;
        final signal = SignalService.create(
          peerDeviceId: own,
          sessionKey: key,
          ip: '192.168.${i % 256}.${(i * 17) % 256}',
          port: port,
          sdp: i % 2 == 0 ? 'v=0 $i' : null,
        );
        final parsed =
            SignalService.parse(signal: signal, ownDeviceId: own);
        expect(parsed.sessionKey, key);
        expect(parsed.ice.port, port);
        if (i % 2 == 0) {
          expect(parsed.sdp, 'v=0 $i');
        } else {
          expect(parsed.sdp, isNull);
        }
      }
    });

    test('wrong device ID cannot recover session key', () {
      final signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.1.100',
        port: 8080,
      );
      final attacker = EncodingService.randomString(Config.deviceIdLength);

      expect(
        () => SignalService.parse(signal: signal, ownDeviceId: attacker),
        throwsA(isA<CryptoException>()),
      );
    });

    test('whitespace and grouping tolerated on input', () {
      final signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.2.50',
        port: 8060,
        sdp: 'v=0',
      );

      final pretty = SignalService.formatForDisplay(signal);
      expect(pretty.contains(' '), true);

      final parsed =
          SignalService.parse(signal: pretty, ownDeviceId: deviceId);
      expect(parsed.sessionKey, sessionKey);
      expect(parsed.sdp, 'v=0');
    });

    test('too-short signals rejected', () {
      expect(
        () => SignalService.parse(
            signal: EncodingService.randomString(10), ownDeviceId: deviceId),
        throwsA(isA<SignalException>()),
      );
      expect(
        () => SignalService.parse(signal: '', ownDeviceId: deviceId),
        throwsA(isA<SignalException>()),
      );
    });

    test('signals with foreign characters rejected', () {
      expect(
        () => SignalService.parse(
            signal: '${EncodingService.randomString(102)}o',
            ownDeviceId: deviceId),
          throwsA(isA<SignalException>()),
      );
      expect(
        () => SignalService.parse(
            signal: '${EncodingService.randomString(103)}!x',
            ownDeviceId: deviceId),
        throwsA(isA<SignalException>()),
      );
    });

    test('checksum mismatch rejected', () {
      var signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.1.100',
        port: 8080,
      );

      final csIndex = signal.length - Config.checksumLength;
      final flipChar = signal[csIndex] == 'a' ? 'b' : 'a';
      signal = signal.replaceRange(csIndex, csIndex + 1, flipChar);

      expect(
        () => SignalService.parse(signal: signal, ownDeviceId: deviceId),
        throwsA(
          isA<SignalException>().having((e) => e.message, 'message',
              contains('Checksum')),
        ),
      );
    });

    test('tampered payload detected by checksum before any crypto runs',
        () {
      var signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.1.100',
        port: 8080,
      );

      final midIndex = signal.length ~/ 2;
      signal = signal.replaceRange(midIndex, midIndex + 1,
          signal[midIndex] == 'a' ? 'b' : 'a');

      expect(
        () => SignalService.parse(signal: signal, ownDeviceId: deviceId),
        throwsA(isA<SignalException>()),
      );
    });

    test('unsupported version char rejected', () {
      var signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.1.100',
        port: 8080,
      );

      final body = signal.substring(0, signal.length - 4);
      final replaced = 'B${body.substring(1)}';
      final resealed = replaced + EncodingService.checksum(replaced);

      expect(
        () => SignalService.parse(signal: resealed, ownDeviceId: deviceId),
        throwsA(
          isA<SignalException>().having(
            (e) => e.message,
            'message',
            contains('version'),
          ),
        ),
      );
    });
  });

  group('Signal expiry', () {
    test('expired signals rejected by default', () {
      final old = DateTime.now().toUtc().subtract(Config.signalExpiry);
      final signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.1.100',
        port: 8080,
        now: old.subtract(const Duration(minutes: 15)),
      );

      expect(
        () => SignalService.parse(signal: signal, ownDeviceId: deviceId),
        throwsA(isA<SignalExpiredException>()),
      );
    });

    test('allowExpired bypasses the expiry check', () {
      final old = DateTime.now()
          .toUtc()
          .subtract(Config.signalExpiry)
          .subtract(const Duration(minutes: 30));
      final signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.9.9',
        port: 8000,
        now: old,
      );

      final parsed = SignalService.parse(
        signal: signal,
        ownDeviceId: deviceId,
        allowExpired: true,
      );
      expect(parsed.sessionKey, sessionKey);
      expect(parsed.isExpired, true);
      expect(
        parsed.createdAt.isBefore(DateTime.now().toUtc()),
        true,
      );
    });

    test('fresh signals are not expired', () {
      final signal = SignalService.create(
        peerDeviceId: deviceId,
        sessionKey: sessionKey,
        ip: '192.168.1.100',
        port: 8080,
      );
      final parsed = SignalService.parse(signal: signal, ownDeviceId: deviceId);
      expect(parsed.isExpired, false);
    });
  });
}
