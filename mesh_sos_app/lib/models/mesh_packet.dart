enum PacketType {
  chat(1),
  sos(2),
  position(3),
  ack(4),
  health(5),
  fallbackReq(6),
  silentSos(7),
  sosResponse(8),
  sosCancel(9),
  sosTriggered(10),
  silentCancel(11),
  rescueLock(12),
  checkinPrompt(13),
  checkinAck(14);

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

enum LifecycleState {
  normal(0),
  validating(1),
  sosGenerated(2),
  sosReceived(3),
  rescueAccepted(4),
  resolved(5),
  silentCancel(6);

  final int value;
  const LifecycleState(this.value);

  static LifecycleState fromValue(int val) {
    return LifecycleState.values.firstWhere(
      (e) => e.value == val,
      orElse: () => LifecycleState.normal,
    );
  }

  String get label {
    switch (this) {
      case LifecycleState.validating:
        return 'Validating (3s Grace)';
      case LifecycleState.sosGenerated:
        return 'Distress Active';
      case LifecycleState.sosReceived:
        return 'ACK Received';
      case LifecycleState.rescueAccepted:
        return 'Rescue Accepted (Locked)';
      case LifecycleState.resolved:
        return 'Resolved / Safe';
      case LifecycleState.silentCancel:
        return 'Duress Silent-Cancel (Low Prio)';
      case LifecycleState.normal:
        return 'Normal';
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
  final int riskScore;
  final int confidenceScore;
  final int signalAnomalyScore;
  final int timeToReserveMins;
  final int rescueLockToken;
  final LifecycleState lifecycleState;
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
    this.riskScore = 0,
    this.confidenceScore = 0,
    this.signalAnomalyScore = 0,
    this.timeToReserveMins = 720,
    this.rescueLockToken = 0,
    this.lifecycleState = LifecycleState.normal,
    required this.payload,
    this.rssi = 0,
    this.snr = 0.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory MeshPacket.fromJson(Map<String, dynamic> json) {
    return MeshPacket(
      packetId: json['pkt_id'] is int ? json['pkt_id'] : int.tryParse(json['pkt_id']?.toString() ?? '0') ?? 0,
      senderId: json['sender'] ?? json['id'] ?? 0,
      recipientId: json['dst'] ?? json['target'] ?? 65535,
      type: _parseType(json['type'], json['duress']),
      priority: json['prio'] ?? 0,
      hopCount: json['hops'] ?? 0,
      gpsSource: GpsSource.fromValue(json['gps_src'] ?? 0),
      latitude: (json['lat'] ?? 0.0).toDouble(),
      longitude: (json['lon'] ?? 0.0).toDouble(),
      batteryPercent: json['bat'] ?? 100,
      riskScore: json['risk'] ?? json['risk_score'] ?? 0,
      confidenceScore: json['conf'] ?? json['confidence'] ?? 0,
      signalAnomalyScore: json['sig_anom'] ?? json['signal_anomaly'] ?? 0,
      timeToReserveMins: json['time_res'] ?? json['time_to_reserve'] ?? 720,
      rescueLockToken: json['lock_token'] ?? json['rescue_lock'] ?? 0,
      lifecycleState: LifecycleState.fromValue(json['state'] ?? 0),
      payload: json['msg'] ?? json['text'] ?? '',
      rssi: json['rssi'] ?? 0,
      snr: (json['snr'] ?? 0.0).toDouble(),
    );
  }

  static PacketType _parseType(dynamic raw, dynamic duress) {
    if (raw == 'SOS_TRIGGERED') return PacketType.sosTriggered;
    if (raw == 'SOS_ALERT') return PacketType.sos;
    if (raw == 'SOS_RESPONSE') return PacketType.sosResponse;
    if (raw == 'SOS_CANCELLED') {
      if (duress == true || duress == 'true') return PacketType.silentCancel;
      return PacketType.sosCancel;
    }
    if (raw == 'RESCUE_LOCK') return PacketType.rescueLock;
    if (raw == 'CHECKIN_PROMPT') return PacketType.checkinPrompt;
    if (raw == 'CHECKIN_ACK') return PacketType.checkinAck;
    if (raw == 'CHAT_MSG') return PacketType.chat;
    if (raw == 'NODE_POS') return PacketType.position;
    if (raw == 'ACK' || raw == 'TX_CONFIRM') return PacketType.ack;
    if (raw == 'NODE_STATUS') return PacketType.health;
    if (raw is int) return PacketType.fromValue(raw);
    return PacketType.chat;
  }
}
