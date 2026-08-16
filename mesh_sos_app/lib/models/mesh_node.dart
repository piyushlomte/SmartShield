import 'mesh_packet.dart';

class MeshNode {
  final int nodeId;
  final String name;
  final double latitude;
  final double longitude;
  final GpsSource gpsSource;
  final int batteryPercent;
  final int rssi;
  final double snr;
  final int hopCount;
  final DateTime lastSeen;
  final bool isSosActive;

  MeshNode({
    required this.nodeId,
    required this.name,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.gpsSource = GpsSource.none,
    this.batteryPercent = 100,
    this.rssi = 0,
    this.snr = 0.0,
    this.hopCount = 0,
    DateTime? lastSeen,
    this.isSosActive = false,
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get hexId => '0x${nodeId.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  bool get isOnline => DateTime.now().difference(lastSeen).inMinutes < 5;

  MeshNode copyWith({
    String? name,
    double? latitude,
    double? longitude,
    GpsSource? gpsSource,
    int? batteryPercent,
    int? rssi,
    double? snr,
    int? hopCount,
    DateTime? lastSeen,
    bool? isSosActive,
  }) {
    return MeshNode(
      nodeId: nodeId,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      gpsSource: gpsSource ?? this.gpsSource,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      rssi: rssi ?? this.rssi,
      snr: snr ?? this.snr,
      hopCount: hopCount ?? this.hopCount,
      lastSeen: lastSeen ?? this.lastSeen,
      isSosActive: isSosActive ?? this.isSosActive,
    );
  }
}
