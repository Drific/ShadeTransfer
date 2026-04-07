import 'dart:convert';

class SignalingData {
  final String type; // 'offer'
  final String sdp;
  final List<IceCandidateData> candidates;

  SignalingData({
    required this.type,
    required this.sdp,
    required this.candidates,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'sdp': sdp,
        'candidates': candidates.map((c) => c.toJson()).toList(),
      };

  factory SignalingData.fromJson(Map<String, dynamic> json) => SignalingData(
        type: json['type'] as String,
        sdp: json['sdp'] as String,
        candidates: (json['candidates'] as List)
            .map((c) => IceCandidateData.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  String toBase64() => base64Encode(utf8.encode(jsonEncode(toJson())));

  factory SignalingData.fromBase64(String base64Str) {
    final jsonStr = utf8.decode(base64Decode(base64Str));
    return SignalingData.fromJson(jsonDecode(jsonStr));
  }
}

class IceCandidateData {
  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  IceCandidateData({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  Map<String, dynamic> toJson() => {
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      };

  factory IceCandidateData.fromJson(Map<String, dynamic> json) =>
      IceCandidateData(
        candidate: json['candidate'] as String,
        sdpMid: json['sdpMid'] as String?,
        sdpMLineIndex: json['sdpMLineIndex'] as int?,
      );
}
