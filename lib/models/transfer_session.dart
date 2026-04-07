import 'dart:typed_data';

import 'file_metadata.dart';

enum TransferStatus {
  idle,
  waitingConnection,
  connecting,
  connected,
  transferring,
  paused,
  completed,
  failed,
  cancelled,
}

enum TransferDirection { send, receive }

class TransferSession {
  final String sessionId;
  final FileMetadata? fileMetadata;
  final TransferDirection direction;
  TransferStatus status;
  int transferredBytes;
  int transferredChunks;
  double speed; // bytes per second
  DateTime? startTime;
  DateTime? endTime;
  String? errorMessage;
  List<int>? receivedChunks;
  Set<int> acknowledgedChunks;
  String? savePath;

  TransferSession({
    required this.sessionId,
    required this.direction,
    this.fileMetadata,
    this.status = TransferStatus.idle,
    this.transferredBytes = 0,
    this.transferredChunks = 0,
    this.speed = 0,
    this.startTime,
    this.endTime,
    this.errorMessage,
    this.receivedChunks,
    Set<int>? acknowledgedChunks,
    this.savePath,
  }) : acknowledgedChunks = acknowledgedChunks ?? {};

  double get progress {
    if (fileMetadata == null || fileMetadata!.size == 0) return 0;
    return transferredBytes / fileMetadata!.size;
  }

  double get chunkProgress {
    if (fileMetadata == null || fileMetadata!.totalChunks == 0) return 0;
    return transferredChunks / fileMetadata!.totalChunks;
  }

  String get formattedSpeed {
    if (speed < 1024) return '${speed.toStringAsFixed(0)} B/s';
    if (speed < 1024 * 1024) {
      return '${(speed / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(speed / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  Duration? get estimatedTimeRemaining {
    if (speed <= 0 || fileMetadata == null) return null;
    final remainingBytes = fileMetadata!.size - transferredBytes;
    final remainingSeconds = remainingBytes / speed;
    return Duration(seconds: remainingSeconds.ceil());
  }

  String get formattedETA {
    final eta = estimatedTimeRemaining;
    if (eta == null) return '--:--';
    final minutes = eta.inMinutes;
    final seconds = eta.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void markChunkAcknowledged(int chunkIndex) {
    acknowledgedChunks.add(chunkIndex);
  }

  bool isChunkAcknowledged(int chunkIndex) {
    return acknowledgedChunks.contains(chunkIndex);
  }

  List<int> getPendingChunks() {
    if (fileMetadata == null) return [];
    final pending = <int>[];
    for (int i = 0; i < fileMetadata!.totalChunks; i++) {
      if (!acknowledgedChunks.contains(i)) {
        pending.add(i);
      }
    }
    return pending;
  }
}

class TransferChunk {
  final int index;
  final Uint8List data;
  final String fileId;

  TransferChunk({
    required this.index,
    required this.data,
    required this.fileId,
  });

  Map<String, dynamic> toMetadata() => {
        'index': index,
        'fileId': fileId,
        'size': data.length,
      };

  factory TransferChunk.fromMetadata(Map<String, dynamic> meta, Uint8List data) =>
      TransferChunk(
        index: meta['index'] as int,
        data: data,
        fileId: meta['fileId'] as String,
      );
}
