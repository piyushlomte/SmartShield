enum MessageStatus {
  sending,
  relayed,
  delivered,
  failed;
}

class ChatMessage {
  final String id;
  final int senderId;
  final int recipientId;
  final String text;
  final DateTime timestamp;
  final bool isOutgoing;
  final MessageStatus status;
  final int? rssi;
  final double? snr;
  final String channel;
  final double? latitude;
  final double? longitude;
  final int? hops;
  final String? senderName;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.timestamp,
    required this.isOutgoing,
    this.status = MessageStatus.delivered,
    this.rssi,
    this.snr,
    this.channel = 'Public',
    this.latitude,
    this.longitude,
    this.hops,
    this.senderName,
  });

  bool get hasLocation => latitude != null && longitude != null && latitude != 0.0 && longitude != 0.0;
  String get hexSenderId => '0x${senderId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  String get hexRecipientId => recipientId == 65535 ? 'BROADCAST' : '0x${recipientId.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'recipient_id': recipientId,
      'text': text,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'is_outgoing': isOutgoing ? 1 : 0,
      'status': status.name,
      'rssi': rssi,
      'snr': snr,
      'channel': channel,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      senderId: map['sender_id'],
      recipientId: map['recipient_id'],
      text: map['text'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
      isOutgoing: map['is_outgoing'] == 1,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.delivered,
      ),
      rssi: map['rssi'],
      snr: map['snr'] != null ? (map['snr'] as num).toDouble() : null,
      channel: map['channel'] ?? 'Public',
      latitude: map['lat'] != null ? (map['lat'] as num).toDouble() : null,
      longitude: map['lon'] != null ? (map['lon'] as num).toDouble() : null,
      hops: map['hops'],
      senderName: map['sender_name'],
    );
  }

  ChatMessage copyWith({
    MessageStatus? status,
    int? rssi,
    double? snr,
    int? hops,
    double? latitude,
    double? longitude,
  }) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      recipientId: recipientId,
      text: text,
      timestamp: timestamp,
      isOutgoing: isOutgoing,
      status: status ?? this.status,
      rssi: rssi ?? this.rssi,
      snr: snr ?? this.snr,
      channel: channel,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      hops: hops ?? this.hops,
      senderName: senderName,
    );
  }
}
