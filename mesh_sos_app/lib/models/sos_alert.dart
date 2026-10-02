import 'mesh_packet.dart';

enum DistressCategory {
  medical('Medical Emergency', '🚑'),
  injury('Trauma / Injury', '🩹'),
  trapped('Trapped / Rubble', '🪨'),
  lost('Lost / Disoriented', '🧭'),
  fire('Fire / Hazard', '🔥'),
  attack('Wildlife / Threat', '⚠️'),
  supplies('Supplies / Water', '💧'),
  general('General Assistance', '🆘');

  final String title;
  final String icon;
  const DistressCategory(this.title, this.icon);
}

class SosAlert {
  final String id;
  final int senderId;
  final String senderName;
  final double latitude;
  final double longitude;
  final GpsSource gpsSource;
  final String message;
  final DistressCategory category;
  final int hopCount;
  final int rssi;
  final double snr;
  final DateTime timestamp;
  final bool isResolved;
  final bool isSelf;
  final String? responderName;
  final String? responseMessage;
  final DateTime? responseTime;

  SosAlert({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.latitude,
    required this.longitude,
    required this.gpsSource,
    required this.message,
    this.category = DistressCategory.general,
    this.hopCount = 0,
    this.rssi = 0,
    this.snr = 0.0,
    DateTime? timestamp,
    this.isResolved = false,
    this.isSelf = false,
    this.responderName,
    this.responseMessage,
    this.responseTime,
  }) : timestamp = timestamp ?? DateTime.now();

  String get hexId => '0x${senderId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  String get distressText => message;
  String get googleMapsUrl => (latitude != 0.0 && longitude != 0.0)
      ? 'https://maps.google.com/?q=$latitude,$longitude'
      : '';
  bool get hasValidLocation => latitude != 0.0 && longitude != 0.0;

  SosAlert copyWith({
    bool? isResolved,
    String? responderName,
    String? responseMessage,
    DateTime? responseTime,
  }) {
    return SosAlert(
      id: id,
      senderId: senderId,
      senderName: senderName,
      latitude: latitude,
      longitude: longitude,
      gpsSource: gpsSource,
      message: message,
      category: category,
      hopCount: hopCount,
      rssi: rssi,
      snr: snr,
      timestamp: timestamp,
      isResolved: isResolved ?? this.isResolved,
      isSelf: isSelf,
      responderName: responderName ?? this.responderName,
      responseMessage: responseMessage ?? this.responseMessage,
      responseTime: responseTime ?? this.responseTime,
    );
  }
}
