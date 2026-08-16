enum PacketType {
  chat(1),
  sos(2),
  position(3),
  ack(4),
  health(5),
  fallbackReq(6),
  silentSos(7),
  sosResponse(8),
  sosCancel(9);

  final int value;
  const PacketType(this.value);

  static PacketType fromValue(int val) {
    return PacketType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => PacketType.chat,
    );
  }
}

enum GpsSource {
  none(0),
  node(1),
  phone(2),
  lastKnown(3);

  final int value;
  const GpsSource(this.value);

  static GpsSource fromValue(int val) {
    return GpsSource.values.firstWhere(
      (e) => e.value == val,
      orElse: () => GpsSource.none,
    );
  }

  String get label {
    switch (this) {
      case GpsSource.node:
        return 'Node GPS (NEO-6M)';
      case GpsSource.phone:
        return 'Phone Fallback';
      case GpsSource.lastKnown:
        return 'Last Known Location';
      case GpsSource.none:
        return 'No Fix';
    }
  }
}

class MeshPacket {
  final int packetId;
  final int senderId;
  final int recipientId;
  final PacketType type;
  final int priority;
  final int hopCount;
  final GpsSource gpsSource;
  final double latitude;
  final double longitude;
  final int batteryPercent;
  final String payload;
  final int rssi;
  final double snr;
  final DateTime timestamp;

  MeshPacket({
    required this.packetId,
    required this.senderId,
    required this.recipientId,
    required this.type,
    required this.priority,
    required this.hopCount,
    required this.gpsSource,
    required this.latitude,
    required this.longitude,
    required this.batteryPercent,
    required this.payload,
    this.rssi = 0,
    this.snr = 0.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory MeshPacket.fromJson(Map<String, dynamic> json) {
    return MeshPacket(
      packetId: json['pkt_id'] is int ? json['pkt_id'] : int.tryParse(json['pkt_id']?.toString() ?? '0') ?? 0,
      senderId: json['sender'] ?? 0,
      recipientId: json['dst'] ?? json['target'] ?? 65535,
      type: _parseType(json['type']),
      priority: json['prio'] ?? 0,
      hopCount: json['hops'] ?? 0,
      gpsSource: GpsSource.fromValue(json['gps_src'] ?? 0),
      latitude: (json['lat'] ?? 0.0).toDouble(),
      longitude: (json['lon'] ?? 0.0).toDouble(),
      batteryPercent: json['bat'] ?? 100,
      payload: json['msg'] ?? json['text'] ?? '',
      rssi: json['rssi'] ?? 0,
      snr: (json['snr'] ?? 0.0).toDouble(),
    );
  }

  static PacketType _parseType(dynamic raw) {
    if (raw == 'SOS_ALERT' || raw == 'SOS_TRIGGERED') return PacketType.sos;
    if (raw == 'SOS_RESPONSE') return PacketType.sosResponse;
    if (raw == 'SOS_CANCELLED') return PacketType.sosCancel;
    if (raw == 'CHAT_MSG') return PacketType.chat;
    if (raw == 'NODE_POS') return PacketType.position;
    if (raw == 'ACK' || raw == 'TX_CONFIRM') return PacketType.ack;
    if (raw == 'NODE_STATUS') return PacketType.health;
    if (raw is int) return PacketType.fromValue(raw);
    return PacketType.chat;
  }
}
