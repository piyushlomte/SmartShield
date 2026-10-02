import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'mesh_packet.dart';

enum IncidentEventType {
  sosTriggered('SOS Triggered', '🚨'),
  sosValidationStarted('Validation Grace Period', '⏳'),
  sosBroadcasted('LoRa Broadcast Dispatched', '📡'),
  ackReceived('Auto-ACK Received', '✅'),
  rescueAccepted('Rescue Response Accepted', '🤝'),
  rescueClaimLocked('Rescue Swarm Claim Locked', '🔒'),
  sosResolved('Emergency Resolved / Cancelled', '🛡️'),
  silentCancelDuress('Duress / Silent-Cancel Code', '⚠️'),
  deadManPrompt('Dead-Man Check-In Prompt', '⏱️'),
  deadManMissed('Dead-Man Check-In Missed', '🚨'),
  fallImpactDetected('AI Fall & Impact Anomaly', '💥'),
  signalAnomalyDetected('RF Signal Fingerprint Anomaly', '📉'),
  telemetryReport('Telemetry Status Sync', '📊');

  final String label;
  final String icon;
  const IncidentEventType(this.label, this.icon);
}

class IncidentRecord {
  final String id;
  final DateTime timestamp;
  final IncidentEventType eventType;
  final int senderId;
  final double latitude;
  final double longitude;
  final GpsSource gpsSource;
  final int riskScore;
  final int confidenceScore;
  final int signalAnomalyScore;
  final int timeToReserveMins;
  final int rescueLockToken;
  final int rssi;
  final double snr;
  final int batteryPercent;
  final String details;
  final String previousHash;
  final String recordHash;

  IncidentRecord({
    required this.id,
    DateTime? timestamp,
    required this.eventType,
    required this.senderId,
    required this.latitude,
    required this.longitude,
    required this.gpsSource,
    this.riskScore = 0,
    this.confidenceScore = 0,
    this.signalAnomalyScore = 0,
    this.timeToReserveMins = 720,
    this.rescueLockToken = 0,
    this.rssi = 0,
    this.snr = 0.0,
    this.batteryPercent = 100,
    required this.details,
    this.previousHash = '0000000000000000000000000000000000000000000000000000000000000000',
    String? recordHash,
  })  : timestamp = timestamp ?? DateTime.now(),
        recordHash = recordHash ??
            _computeHash(
              previousHash: previousHash,
              id: id,
              timestamp: timestamp ?? DateTime.now(),
              eventType: eventType,
              senderId: senderId,
              latitude: latitude,
              longitude: longitude,
              riskScore: riskScore,
              details: details,
            );

  static String _computeHash({
    required String previousHash,
    required String id,
    required DateTime timestamp,
    required IncidentEventType eventType,
    required int senderId,
    required double latitude,
    required double longitude,
    required int riskScore,
    required String details,
  }) {
    final raw = '$previousHash|$id|${timestamp.toIso8601String()}|${eventType.name}|$senderId|$latitude|$longitude|$riskScore|$details';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  String get hexSenderId => '0x${senderId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  String get shortHash => recordHash.length >= 12 ? recordHash.substring(0, 12).toUpperCase() : recordHash;

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'eventType': eventType.name,
    'senderId': senderId,
    'latitude': latitude,
    'longitude': longitude,
    'gpsSource': gpsSource.name,
    'riskScore': riskScore,
    'confidenceScore': confidenceScore,
    'signalAnomalyScore': signalAnomalyScore,
    'timeToReserveMins': timeToReserveMins,
    'rescueLockToken': rescueLockToken,
    'rssi': rssi,
    'snr': snr,
    'batteryPercent': batteryPercent,
    'details': details,
    'previousHash': previousHash,
    'recordHash': recordHash,
  };

  factory IncidentRecord.fromJson(Map<String, dynamic> json) => IncidentRecord(
    id: json['id'] ?? '',
    timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
    eventType: IncidentEventType.values.firstWhere(
      (e) => e.name == json['eventType'],
      orElse: () => IncidentEventType.sosTriggered,
    ),
    senderId: json['senderId'] ?? 0,
    latitude: (json['latitude'] ?? 0.0).toDouble(),
    longitude: (json['longitude'] ?? 0.0).toDouble(),
    gpsSource: GpsSource.values.firstWhere(
      (e) => e.name == json['gpsSource'],
      orElse: () => GpsSource.none,
    ),
    riskScore: json['riskScore'] ?? 0,
    confidenceScore: json['confidenceScore'] ?? 0,
    signalAnomalyScore: json['signalAnomalyScore'] ?? 0,
    timeToReserveMins: json['timeToReserveMins'] ?? 720,
    rescueLockToken: json['rescueLockToken'] ?? 0,
    rssi: json['rssi'] ?? 0,
    snr: (json['snr'] ?? 0.0).toDouble(),
    batteryPercent: json['batteryPercent'] ?? 100,
    details: json['details'] ?? '',
    previousHash: json['previousHash'] ?? '0000000000000000000000000000000000000000000000000000000000000000',
    recordHash: json['recordHash'],
  );
}
