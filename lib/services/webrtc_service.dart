import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/signaling_data.dart';
import 'logger_service.dart';

enum ConnectionState {
  idle,
  creating,
  waitingForPeer,
  connecting,
  connected,
  disconnected,
  failed,
}

class WebRTCConnection {
  final _logger = AppLogger();
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  final List<RTCIceCandidate> _localCandidates = [];
  ConnectionState _state = ConnectionState.idle;

  final _stateController = StreamController<ConnectionState>.broadcast();
  final _messageController = StreamController<Uint8List>.broadcast();
  final _textMessageController = StreamController<String>.broadcast();

  Stream<ConnectionState> get stateStream => _stateController.stream;
  Stream<Uint8List> get dataStream => _messageController.stream;
  Stream<String> get textMessageStream => _textMessageController.stream;
  ConnectionState get state => _state;
  bool get isConnected => _state == ConnectionState.connected;

  static const int maxMessageSize = 256 * 1024; // 256KB max message size

  final Map<String, dynamic> _config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  void _updateState(ConnectionState newState) {
    _logger.info('WebRTC', 'State: $_state -> $newState');
    _state = newState;
    _stateController.add(_state);
  }

  Future<SignalingData> createOffer() async {
    _logger.info('WebRTC', 'Creating offer');
    _updateState(ConnectionState.creating);

    _peerConnection = await createPeerConnection(_config);
    _setupPeerConnection();

    _dataChannel = await _peerConnection!.createDataChannel(
      'fileTransfer',
      RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 30,
    );
    _setupDataChannel(_dataChannel!);

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await _waitForIceCandidates();

    final candidates = _localCandidates
        .map((c) => IceCandidateData(
              candidate: c.candidate!,
              sdpMid: c.sdpMid,
              sdpMLineIndex: c.sdpMLineIndex,
            ))
        .toList();

    final localDesc = await _peerConnection!.getLocalDescription();

    return SignalingData(
      type: 'offer',
      sdp: localDesc!.sdp!,
      candidates: candidates,
    );
  }

  Future<void> handleOffer(SignalingData offer) async {
    _updateState(ConnectionState.connecting);

    _peerConnection = await createPeerConnection(_config);
    _setupPeerConnection();

    _peerConnection!.onDataChannel = (channel) {
      _dataChannel = channel;
      _setupDataChannel(channel);
    };

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer.sdp, 'offer'),
    );

    for (final candidate in offer.candidates) {
      await _peerConnection!.addCandidate(RTCIceCandidate(
        candidate.candidate,
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      ));
    }

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await _waitForIceCandidates();
    // Do not return SignalingData, connection establishes directly
  }

  void _setupPeerConnection() {
    _peerConnection!.onIceCandidate = (candidate) {
      _localCandidates.add(candidate);
    };

    _peerConnection!.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _updateState(ConnectionState.connected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _updateState(ConnectionState.disconnected);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _updateState(ConnectionState.failed);
          break;
        default:
          break;
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
        _updateState(ConnectionState.connected);
      }
    };
  }

  void _setupDataChannel(RTCDataChannel channel) {
    channel.onMessage = (message) {
      if (message.isBinary) {
        _messageController.add(message.binary);
      } else {
        _textMessageController.add(message.text);
      }
    };

    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _updateState(ConnectionState.connected);
      }
    };
  }

  Future<void> _waitForIceCandidates() async {
    int waitCount = 0;
    while (_peerConnection!.iceGatheringState !=
        RTCIceGatheringState.RTCIceGatheringStateComplete) {
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
      if (waitCount > 100) break; // Max 10 seconds wait
    }
  }

  Future<void> sendBinary(Uint8List data) async {
    if (_dataChannel == null ||
        _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Data channel not open');
    }

    if (data.length <= maxMessageSize) {
      await _dataChannel!.send(RTCDataChannelMessage.fromBinary(data));
    } else {
      // Split into chunks
      int offset = 0;
      while (offset < data.length) {
        final end = (offset + maxMessageSize).clamp(0, data.length);
        final chunk = data.sublist(offset, end);
        await _dataChannel!.send(RTCDataChannelMessage.fromBinary(chunk));
        offset = end;
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  Future<void> sendText(String text) async {
    if (_dataChannel == null ||
        _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw Exception('Data channel not open');
    }
    await _dataChannel!.send(RTCDataChannelMessage(text));
  }

  Future<void> close() async {
    _updateState(ConnectionState.idle);
    await _dataChannel?.close();
    await _peerConnection?.close();
    _dataChannel = null;
    _peerConnection = null;
    _localCandidates.clear();
  }

  void dispose() {
    close();
    _stateController.close();
    _messageController.close();
    _textMessageController.close();
  }
}
