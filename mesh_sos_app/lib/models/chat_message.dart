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
  });

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
    );
  }

  ChatMessage copyWith({MessageStatus? status}) {
    return ChatMessage(
      id: id,
      senderId: senderId,
      recipientId: recipientId,
      text: text,
      timestamp: timestamp,
      isOutgoing: isOutgoing,
      status: status ?? this.status,
      rssi: rssi,
      snr: snr,
      channel: channel,
    );
  }
}
