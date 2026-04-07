import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/signaling_data.dart';
import '../models/transfer_session.dart';
import 'encryption_service.dart';
import 'file_transfer_service.dart';
import 'logger_service.dart';
import 'webrtc_service.dart' as webrtc;

class AppStateProvider extends ChangeNotifier {
  final EncryptionService encryption = EncryptionService();
  final webrtc.WebRTCConnection connection = webrtc.WebRTCConnection();
  final AppLogger logger = AppLogger();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  FileTransferService? _transferService;
  FileTransferService? get transferService => _transferService;

  SignalingData? _localSignaling;
  SignalingData? get localSignaling => _localSignaling;

  bool _isSender = false;
  bool get isSender => _isSender;



  final List<String> _selectedFiles = [];
  List<String> get selectedFiles => List.unmodifiable(_selectedFiles);

  TransferSession? _currentSession;
  TransferSession? get currentSession => _currentSession;

  webrtc.ConnectionState _connectionState = webrtc.ConnectionState.idle;
  webrtc.ConnectionState get connectionState => _connectionState;

  String _statusMessage = '';
  String get statusMessage => _statusMessage;

  AppStateProvider() {
    _init();
  }

  Future<void> _init() async {
    logger.info('AppState', 'Initializing app state');
    connection.stateStream.listen((state) {
      _connectionState = state;
      logger.info('AppState', 'Connection state changed: $state');
      if (state == webrtc.ConnectionState.connected) {
        _sendPublicKey();
      }
      notifyListeners();
    });

    await _checkInterruptedTransfers();
    notifyListeners();
  }

  Future<void> _checkInterruptedTransfers() async {
    logger.info('AppState', 'Checking for interrupted transfers');
  }

  void setSenderMode() {
    _isSender = true;
    logger.info('AppState', 'Set to sender mode');
    notifyListeners();
  }

  void setReceiverMode() {
    _isSender = false;
    logger.info('AppState', 'Set to receiver mode');
    notifyListeners();
  }



  void addFile(String path) {
    if (!_selectedFiles.contains(path)) {
      _selectedFiles.add(path);
      logger.info('AppState', 'Added file: $path');
      notifyListeners();
    }
  }

  void addFolder(String folderPath) {
    try {
      final dir = Directory(folderPath);
      if (dir.existsSync()) {
        final files = dir.listSync(recursive: true, followLinks: false);
        int count = 0;
        for (final entity in files) {
          if (entity is File && !_selectedFiles.contains(entity.path)) {
            _selectedFiles.add(entity.path);
            count++;
          }
        }
        logger.info('AppState', 'Added folder: $folderPath ($count files)');
        notifyListeners();
      }
    } catch (e) {
      logger.error('AppState', 'Failed to add folder: $e');
    }
  }

  void removeFile(String path) {
    _selectedFiles.remove(path);
    logger.info('AppState', 'Removed file: $path');
    notifyListeners();
  }

  void clearFiles() {
    _selectedFiles.clear();
    logger.info('AppState', 'Cleared all files');
    notifyListeners();
  }

  int get totalSelectedSize {
    int total = 0;
    for (final path in _selectedFiles) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          total += file.lengthSync();
        }
      } catch (_) {}
    }
    return total;
  }



  Future<SignalingData> generateOffer() async {
    logger.info('AppState', 'Generating WebRTC offer');
    _localSignaling = await connection.createOffer();
    _transferService = FileTransferService(connection, encryption);
    _transferService!.sessionStream.listen((session) {
      _currentSession = session;
      notifyListeners();
    });
    _transferService!.progressStream.listen((progress) {
      _updateTransferNotification();
    });
    notifyListeners();
    return _localSignaling!;
  }

  Future<void> receiveOffer(SignalingData offer) async {
    logger.info('AppState', 'Receiving WebRTC offer');
    await connection.handleOffer(offer);
    _transferService = FileTransferService(connection, encryption);
    _transferService!.sessionStream.listen((session) {
      _currentSession = session;
      notifyListeners();
    });
    _transferService!.progressStream.listen((progress) {
      _updateTransferNotification();
    });

    connection.dataStream.listen((data) {
      _transferService?.handleChunkData(data);
    });

    // Send public key after connection
    _sendPublicKey();

    notifyListeners();
  }

  Future<void> startFileTransfer() async {
    if (_selectedFiles.isNotEmpty && _transferService != null) {
      logger.info('AppState', 'Starting file transfer: ${_selectedFiles.length} files');
      for (final path in _selectedFiles) {
        await _transferService!.sendFile(path);
      }
    }
  }

  Future<void> pauseTransfer() async {
    logger.info('AppState', 'Pausing transfer');
    await _transferService?.pauseTransfer();
  }

  Future<void> resumeTransfer() async {
    logger.info('AppState', 'Resuming transfer');
    await _transferService?.resumeTransfer();
  }

  Future<void> cancelTransfer() async {
    logger.info('AppState', 'Cancelling transfer');
    await _transferService?.cancelTransfer();
  }

  void setStatusMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void _sendPublicKey() {
    _transferService?.sendPublicKey();
  }



  void _updateTransferNotification() {
    if (_currentSession == null || _currentSession!.fileMetadata == null) return;
    final metadata = _currentSession!.fileMetadata!;
    final progress = (_currentSession!.transferredBytes / metadata.size * 100).round();
    _notifications.show(
      0,
      '传输中',
      '${metadata.name} - $progress%',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'transfer_channel',
          'Transfer Notifications',
          channelDescription: 'Notifications for file transfer progress',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          progress: _currentSession!.transferredBytes.toInt(),
          maxProgress: metadata.size.toInt(),
        ),
      ),
    );
  }



  void reset() {
    logger.info('AppState', 'Resetting app state');
    _localSignaling = null;
    _isSender = false;
    _selectedFiles.clear();
    _currentSession = null;
    _connectionState = webrtc.ConnectionState.idle;
    _statusMessage = '';
    _transferService?.dispose();
    _transferService = null;
    connection.close();
    notifyListeners();
  }

  @override
  void dispose() {
    logger.info('AppState', 'Disposing app state');
    _transferService?.dispose();
    connection.dispose();
    encryption.dispose();
    super.dispose();
  }
}
