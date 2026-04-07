import 'dart:convert';

class FileMetadata {
  final String name;
  final int size;
  final String mimeType;
  final String checksum; // SHA-256 hash of the file
  final int chunkSize;
  final int totalChunks;
  final String fileId;

  FileMetadata({
    required this.name,
    required this.size,
    required this.mimeType,
    required this.checksum,
    this.chunkSize = 64 * 1024, // 64KB default chunk size
    int? totalChunks,
    String? fileId,
  })  : totalChunks = totalChunks ?? (size / chunkSize).ceil(),
        fileId = fileId ?? _generateFileId();

  static String _generateFileId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp * 31) % 1000000;
    return 'file_${timestamp}_$random';
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'mimeType': mimeType,
        'checksum': checksum,
        'chunkSize': chunkSize,
        'totalChunks': totalChunks,
        'fileId': fileId,
      };

  factory FileMetadata.fromJson(Map<String, dynamic> json) => FileMetadata(
        name: json['name'] as String,
        size: json['size'] as int,
        mimeType: json['mimeType'] as String,
        checksum: json['checksum'] as String,
        chunkSize: json['chunkSize'] as int,
        totalChunks: json['totalChunks'] as int,
        fileId: json['fileId'] as String,
      );

  String toBase64() => base64Encode(utf8.encode(jsonEncode(toJson())));

  factory FileMetadata.fromBase64(String base64Str) {
    final jsonStr = utf8.decode(base64Decode(base64Str));
    return FileMetadata.fromJson(jsonDecode(jsonStr));
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
