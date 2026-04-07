import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/file_metadata.dart';
import '../models/transfer_session.dart';
import 'encryption_service.dart';
import 'webrtc_service.dart';

class TransferMessage {
  final String type;
  final Map<String, dynamic> data;

  TransferMessage({required this.type, required this.data});

  factory TransferMessage.fromJson(String json) {
    final map = jsonDecode(json) as Map<String, dynamic>;
    return TransferMessage(
      type: map['type'] as String,
      data: map['data'] as Map<String, dynamic>,
    );
  }

  String toJson() => jsonEncode({'type': type, 'data': data});

  static const String fileMetadata = 'file_metadata';
  static const String chunk = 'chunk';
  static const String chunkAck = 'chunk_ack';
  static const String transferStart = 'transfer_start';
  static const String transferPause = 'transfer_pause';
  static const String transferResume = 'transfer_resume';
  static const String transferCancel = 'transfer_cancel';
  static const String transferComplete = 'transfer_complete';
  static const String aesKey = 'aes_key';
  static const String publicKey = 'public_key';
  static const String requestMissingChunks = 'request_missing_chunks';
  static const String missingChunks = 'missing_chunks';
}

class FileTransferService {
  final WebRTCConnection _connection;
  final EncryptionService _encryption;
  
  TransferSession? _currentSession;
  File? _sourceFile;
  File? _destinationFile;
  
  final _sessionController = StreamController<TransferSession>.broadcast();
  final _progressController = StreamController<double>.broadcast();
  
  Stream<TransferSession> get sessionStream => _sessionController.stream;
  Stream<double> get progressStream => _progressController.stream;
  TransferSession? get currentSession => _currentSession;
  
  Timer? _speedTimer;
  int _lastTransferredBytes = 0;
  bool _isPaused = false;
  Completer<void>? _pauseCompleter;

  FileTransferService(this._connection, this._encryption) {
    _connection.textMessageStream.listen(_handleMessage);
  }

  Future<void> sendPublicKey() async {
    final publicKey = _encryption.exportPublicKey();
    final msg = TransferMessage(
      type: TransferMessage.publicKey,
      data: {'publicKey': publicKey},
    );
    await _connection.sendText(msg.toJson());
  }

  Future<void> sendFile(String filePath) async {
    _sourceFile = File(filePath);
    if (!await _sourceFile!.exists()) {
      throw Exception('File not found: $filePath');
    }

    final fileBytes = await _sourceFile!.readAsBytes();
    final fileName = p.basename(filePath);
    final fileSize = fileBytes.length;
    final mimeType = _getMimeType(fileName);
    final checksum = _encryption.computeChecksum(fileBytes);

    final metadata = FileMetadata(
      name: fileName,
      size: fileSize,
      mimeType: mimeType,
      checksum: checksum,
    );

    _currentSession = TransferSession(
      sessionId: metadata.fileId,
      direction: TransferDirection.send,
      fileMetadata: metadata,
      status: TransferStatus.waitingConnection,
      startTime: DateTime.now(),
    );

    _notifySessionUpdate();

    // Send file metadata
    final metadataMsg = TransferMessage(
      type: TransferMessage.fileMetadata,
      data: metadata.toJson(),
    );
    await _connection.sendText(metadataMsg.toJson());

    // Generate and send AES key
    _encryption.generateAESKey();
    final encryptedKey = _encryption.encryptAESKey();
    final aesKeyMsg = TransferMessage(
      type: TransferMessage.aesKey,
      data: {'encryptedKey': encryptedKey},
    );
    await _connection.sendText(aesKeyMsg.toJson());

    // Wait for receiver to acknowledge
    _currentSession!.status = TransferStatus.connected;
    _notifySessionUpdate();
  }

  void startTransfer() async {
    if (_currentSession == null || _sourceFile == null) return;

    _currentSession!.status = TransferStatus.transferring;
    _notifySessionUpdate();
    _startSpeedMonitoring();

    final fileBytes = await _sourceFile!.readAsBytes();
    final metadata = _currentSession!.fileMetadata!;
    final chunkSize = metadata.chunkSize;
    int startChunk = 0;

    // Resume from last acknowledged chunk
    if (_currentSession!.acknowledgedChunks.isNotEmpty) {
      startChunk = _currentSession!.acknowledgedChunks.reduce(max) + 1;
    }

    final startMsg = TransferMessage(
      type: TransferMessage.transferStart,
      data: {
        'sessionId': metadata.fileId,
        'startChunk': startChunk,
      },
    );
    await _connection.sendText(startMsg.toJson());

    for (int i = startChunk; i < metadata.totalChunks; i++) {
      if (_isPaused) {
        _pauseCompleter = Completer<void>();
        await _pauseCompleter!.future;
        if (_currentSession!.status == TransferStatus.cancelled) return;
      }

      final start = i * chunkSize;
      final end = (start + chunkSize).clamp(0, fileBytes.length);
      final chunkData = fileBytes.sublist(start, end);

      // Encrypt chunk
      final encryptedChunk = _encryption.encryptData(Uint8List.fromList(chunkData));

      // Send chunk metadata
      final chunkMsg = TransferMessage(
        type: TransferMessage.chunk,
        data: {
          'index': i,
          'fileId': metadata.fileId,
          'size': encryptedChunk.length,
        },
      );
      await _connection.sendText(chunkMsg.toJson());

      // Send encrypted chunk data
      await _connection.sendBinary(encryptedChunk);

      _currentSession!.transferredChunks = i + 1;
      _currentSession!.transferredBytes = end;
      _notifySessionUpdate();
      _progressController.add(_currentSession!.progress);
    }

    final completeMsg = TransferMessage(
      type: TransferMessage.transferComplete,
      data: {'fileId': metadata.fileId},
    );
    await _connection.sendText(completeMsg.toJson());

    _currentSession!.status = TransferStatus.completed;
    _currentSession!.endTime = DateTime.now();
    _notifySessionUpdate();
    _stopSpeedMonitoring();
  }

  void _handleMessage(String message) async {
    try {
      final msg = TransferMessage.fromJson(message);

      switch (msg.type) {
        case TransferMessage.fileMetadata:
          await _handleFileMetadata(msg);
          break;
        case TransferMessage.aesKey:
          _handleAESKey(msg);
          break;
        case TransferMessage.chunk:
          _handleChunkMetadata(msg);
          break;
        case TransferMessage.chunkAck:
          _handleChunkAck(msg);
          break;
        case TransferMessage.transferStart:
          _handleTransferStart(msg);
          break;
        case TransferMessage.transferPause:
          _handleTransferPause(msg);
          break;
        case TransferMessage.transferResume:
          _handleTransferResume(msg);
          break;
        case TransferMessage.transferCancel:
          _handleTransferCancel(msg);
          break;
        case TransferMessage.transferComplete:
          _handleTransferComplete(msg);
          break;
        case TransferMessage.requestMissingChunks:
          _handleRequestMissingChunks(msg);
          break;
        case TransferMessage.missingChunks:
          _handleMissingChunks(msg);
          break;
        case TransferMessage.publicKey:
          _handlePublicKey(msg);
          break;
      }
    } catch (e) {
      // Log error handling message
    }
  }

  Future<void> _handleFileMetadata(TransferMessage msg) async {
    final metadata = FileMetadata.fromJson(msg.data);

    _currentSession = TransferSession(
      sessionId: metadata.fileId,
      direction: TransferDirection.receive,
      fileMetadata: metadata,
      status: TransferStatus.waitingConnection,
      startTime: DateTime.now(),
    );

    // Initialize received chunks list
    _currentSession!.receivedChunks = List.filled(metadata.totalChunks, 0, growable: false);

    final downloadDir = await _getDownloadDirectory();
    final safeName = _getSafeFileName(metadata.name);
    _destinationFile = File(p.join(downloadDir.path, safeName));

    _notifySessionUpdate();
  }

  void _handleAESKey(TransferMessage msg) {
    final encryptedKey = msg.data['encryptedKey'] as String;
    _encryption.decryptAESKey(encryptedKey);

    // Ready to receive
    if (_currentSession != null) {
      _currentSession!.status = TransferStatus.connected;
      _notifySessionUpdate();
    }
  }

  int _pendingChunkIndex = -1;
  Uint8List? _pendingChunkData;

  void _handleChunkMetadata(TransferMessage msg) {
    _pendingChunkIndex = msg.data['index'] as int;
    final size = msg.data['size'] as int;
    _pendingChunkData = Uint8List(size);
  }

  void handleChunkData(Uint8List encryptedData) async {
    if (_pendingChunkIndex < 0 || _pendingChunkData == null) return;
    if (_currentSession == null || _currentSession!.fileMetadata == null) return;

    try {
      // Decrypt chunk
      final decryptedData = _encryption.decryptData(encryptedData);

      // Write chunk to file
      final chunkSize = _currentSession!.fileMetadata!.chunkSize;
      final offset = _pendingChunkIndex * chunkSize;
      
      if (_destinationFile != null) {
        final raf = await _destinationFile!.open(mode: FileMode.writeOnlyAppend);
        await raf.setPosition(offset);
        await raf.writeFrom(decryptedData);
        await raf.close();
      }

      // Update session
      _currentSession!.transferredChunks++;
      _currentSession!.transferredBytes += decryptedData.length;
      _currentSession!.markChunkAcknowledged(_pendingChunkIndex);

      // Send acknowledgment
      final ackMsg = TransferMessage(
        type: TransferMessage.chunkAck,
        data: {
          'index': _pendingChunkIndex,
          'fileId': _currentSession!.fileMetadata!.fileId,
        },
      );
      await _connection.sendText(ackMsg.toJson());

      _notifySessionUpdate();
      _progressController.add(_currentSession!.chunkProgress);

      _pendingChunkIndex = -1;
      _pendingChunkData = null;
    } catch (e) {
      // Log error handling chunk data
    }
  }

  void _handleChunkAck(TransferMessage msg) {
    final index = msg.data['index'] as int;
    _currentSession?.markChunkAcknowledged(index);
  }

  void _handleTransferStart(TransferMessage msg) {
    if (_currentSession != null) {
      _currentSession!.status = TransferStatus.transferring;
      _notifySessionUpdate();
      _startSpeedMonitoring();
    }
  }

  void _handleTransferPause(TransferMessage msg) {
    if (_currentSession != null) {
      _currentSession!.status = TransferStatus.paused;
      _notifySessionUpdate();
    }
  }

  void _handleTransferResume(TransferMessage msg) {
    if (_currentSession != null) {
      _currentSession!.status = TransferStatus.transferring;
      _notifySessionUpdate();
    }
  }

  void _handleTransferCancel(TransferMessage msg) {
    if (_currentSession != null) {
      _currentSession!.status = TransferStatus.cancelled;
      _notifySessionUpdate();
      _stopSpeedMonitoring();
    }
  }

  void _handleTransferComplete(TransferMessage msg) async {
    if (_currentSession != null && _destinationFile != null) {
      // Verify checksum
      final fileBytes = await _destinationFile!.readAsBytes();
      final computedChecksum = _encryption.computeChecksum(fileBytes);
      
      if (computedChecksum == _currentSession!.fileMetadata!.checksum) {
        _currentSession!.status = TransferStatus.completed;
      } else {
        _currentSession!.status = TransferStatus.failed;
        _currentSession!.errorMessage = 'Checksum verification failed';
      }
      
      _currentSession!.endTime = DateTime.now();
      _notifySessionUpdate();
      _stopSpeedMonitoring();
    }
  }

  void _handleRequestMissingChunks(TransferMessage msg) {
    // Handle resumable transfer
  }

  void _handleMissingChunks(TransferMessage msg) {
    // Handle missing chunks request
  }

  void _handlePublicKey(TransferMessage msg) {
    final publicKey = msg.data['publicKey'] as String;
    _encryption.importPeerPublicKey(publicKey);
  }

  Future<void> pauseTransfer() async {
    _isPaused = true;
    if (_currentSession != null) {
      _currentSession!.status = TransferStatus.paused;
      final pauseMsg = TransferMessage(
        type: TransferMessage.transferPause,
        data: {'sessionId': _currentSession!.sessionId},
      );
      await _connection.sendText(pauseMsg.toJson());
      _notifySessionUpdate();
    }
  }

  Future<void> resumeTransfer() async {
    _isPaused = false;
    _pauseCompleter?.complete();
    if (_currentSession != null) {
      _currentSession!.status = TransferStatus.transferring;
      final resumeMsg = TransferMessage(
        type: TransferMessage.transferResume,
        data: {'sessionId': _currentSession!.sessionId},
      );
      await _connection.sendText(resumeMsg.toJson());
      _notifySessionUpdate();
    }
  }

  Future<void> cancelTransfer() async {
    _isPaused = true;
    if (_currentSession != null) {
      _currentSession!.status = TransferStatus.cancelled;
      final cancelMsg = TransferMessage(
        type: TransferMessage.transferCancel,
        data: {'sessionId': _currentSession!.sessionId},
      );
      await _connection.sendText(cancelMsg.toJson());
      _notifySessionUpdate();
      _stopSpeedMonitoring();
    }
  }

  void _startSpeedMonitoring() {
    _lastTransferredBytes = _currentSession?.transferredBytes ?? 0;
    _speedTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_currentSession != null) {
        final currentBytes = _currentSession!.transferredBytes;
        // speed = bytes per second, timer is 500ms so multiply by 2
        _currentSession!.speed = ((currentBytes - _lastTransferredBytes) * 2).toDouble();
        _lastTransferredBytes = currentBytes;
        _notifySessionUpdate();
      }
    });
  }

  void _stopSpeedMonitoring() {
    _speedTimer?.cancel();
    _speedTimer = null;
  }

  void _notifySessionUpdate() {
    if (_currentSession != null) {
      _sessionController.add(_currentSession!);
    }
  }

  Future<Directory> _getDownloadDirectory() async {
    if (Platform.isAndroid) {
      return await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    } else if (Platform.isWindows) {
      return await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }

  String _getSafeFileName(String fileName) {
    final invalidChars = RegExp(r'[<>:"/\\|?*]');
    return fileName.replaceAll(invalidChars, '_');
  }

  String _getMimeType(String fileName) {
    final ext = p.extension(fileName).toLowerCase();
    final mimeTypes = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.pdf': 'application/pdf',
      '.doc': 'application/msword',
      '.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.xls': 'application/vnd.ms-excel',
      '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.zip': 'application/zip',
      '.mp4': 'video/mp4',
      '.mp3': 'audio/mpeg',
      '.txt': 'text/plain',
    };
    return mimeTypes[ext] ?? 'application/octet-stream';
  }

  void dispose() {
    _stopSpeedMonitoring();
    _sessionController.close();
    _progressController.close();
  }
}
