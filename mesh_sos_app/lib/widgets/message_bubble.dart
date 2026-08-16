import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chat_message.dart';
import 'signal_badge.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOut = message.isOutgoing;

    return Align(
      alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOut ? theme.colorScheme.primary.withOpacity(0.85) : theme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOut ? 16 : 4),
            bottomRight: Radius.circular(isOut ? 4 : 16),
          ),
          border: Border.all(
            color: isOut ? theme.colorScheme.primary : Colors.white.withOpacity(0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isOut) ...[
              Text(
                'Node 0x${message.senderId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              message.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.rssi != null) ...[
                  SignalBadge(rssi: message.rssi!, snr: message.snr ?? 0.0),
                  const SizedBox(width: 6),
                ],
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
                if (isOut) ...[
                  const SizedBox(width: 4),
                  _buildStatusIcon(message.status),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return const Icon(Icons.access_time, size: 12, color: Colors.white60);
      case MessageStatus.relayed:
        return const Icon(Icons.check, size: 12, color: Colors.white70);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 12, color: Color(0xFF00E676));
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: Colors.redAccent);
    }
  }
}
