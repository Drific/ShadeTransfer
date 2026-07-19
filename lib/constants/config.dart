// lib/constants/config.dart

class Config {
  Config._();

  // Device identifier
  static const int deviceIdLength = 8;

  // Communication key
  static const int sessionKeyLength = 16;

  // ICE candidate encoding
  static const int portRangeMin = 8000;
  static const int portRangeMax = 8150; // 151 ports

  // Checksum
  static const int checksumLength = 4;

  // Transfer
  static const int chunkSize = 64 * 1024; // 64KB

  // Signal expiry
  static const Duration signalExpiry = Duration(minutes: 10);

  // WebRTC
  static const List<Map<String, String>> iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
  ];
}