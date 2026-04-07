import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' as pc;

import 'logger_service.dart';

class EncryptionService {
  final _logger = AppLogger();
  late pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey> _keyPair;
  pc.RSAPublicKey? _peerPublicKey;
  late enc.Encrypter _rsaEncrypter;
  late enc.Key _aesKey;
  late enc.IV _aesIv;
  late enc.Encrypter _aesEncrypter;

  pc.RSAPublicKey get publicKey => _keyPair.publicKey;
  bool get hasPeerKey => _peerPublicKey != null;

  EncryptionService() {
    _generateKeyPair();
  }

  void _generateKeyPair() {
    _logger.info('Encryption', 'Generating RSA-2048 key pair');
    final secureRandom = pc.FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));

    final keyGen = pc.RSAKeyGenerator()
      ..init(pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        secureRandom,
      ));

    final pair = keyGen.generateKeyPair();
    _keyPair = pc.AsymmetricKeyPair<pc.RSAPublicKey, pc.RSAPrivateKey>(
      pair.publicKey as pc.RSAPublicKey,
      pair.privateKey as pc.RSAPrivateKey,
    );
    _rsaEncrypter = enc.Encrypter(enc.RSA(
      publicKey: _keyPair.publicKey,
      privateKey: _keyPair.privateKey,
    ));
    _logger.info('Encryption', 'RSA key pair generated');
  }

  String exportPublicKey() {
    final publicKey = _keyPair.publicKey;
    return base64Encode(utf8.encode(
      '${publicKey.modulus!.toRadixString(16)}|${publicKey.exponent!.toRadixString(16)}',
    ));
  }

  void importPeerPublicKey(String publicKeyStr) {
    _logger.info('Encryption', 'Importing peer public key');
    final decoded = utf8.decode(base64Decode(publicKeyStr));
    final parts = decoded.split('|');
    final modulus = BigInt.parse(parts[0], radix: 16);
    final exponent = BigInt.parse(parts[1], radix: 16);
    _peerPublicKey = pc.RSAPublicKey(modulus, exponent);
  }

  void generateAESKey() {
    _logger.info('Encryption', 'Generating AES-256 session key');
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final ivBytes = List<int>.generate(16, (_) => random.nextInt(256));
    _aesKey = enc.Key(Uint8List.fromList(keyBytes));
    _aesIv = enc.IV(Uint8List.fromList(ivBytes));
    _aesEncrypter = enc.Encrypter(enc.AES(_aesKey));
  }

  String encryptAESKey() {
    if (_peerPublicKey == null) {
      throw Exception('Peer public key not set');
    }
    final aesData = '${_aesKey.base64}|${_aesIv.base64}';
    final rsaWithPeer = enc.Encrypter(enc.RSA(
      publicKey: _peerPublicKey,
      privateKey: _keyPair.privateKey,
    ));
    return rsaWithPeer.encrypt(aesData).base64;
  }

  void decryptAESKey(String encryptedKey) {
    final decrypted = _rsaEncrypter.decrypt64(encryptedKey);
    final parts = decrypted.split('|');
    _aesKey = enc.Key.fromBase64(parts[0]);
    _aesIv = enc.IV.fromBase64(parts[1]);
    _aesEncrypter = enc.Encrypter(enc.AES(_aesKey));
  }

  Uint8List encryptData(Uint8List data) {
    final encrypted = _aesEncrypter.encryptBytes(data, iv: _aesIv);
    return Uint8List.fromList(encrypted.bytes);
  }

  Uint8List decryptData(Uint8List encryptedData) {
    final encrypted = enc.Encrypted(encryptedData);
    final decrypted = _aesEncrypter.decryptBytes(encrypted, iv: _aesIv);
    return Uint8List.fromList(decrypted);
  }

  String computeChecksum(Uint8List data) {
    final digest = pc.SHA256Digest();
    final hash = digest.process(data);
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  void dispose() {
    _peerPublicKey = null;
  }
}
