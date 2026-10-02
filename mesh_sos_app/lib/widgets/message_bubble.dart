import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../models/chat_message.dart';
import 'signal_badge.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final LatLng? userLocation;
  final VoidCallback? onLocationTap;

  const MessageBubble({
    super.key,
    required this.message,
    this.userLocation,
    this.onLocationTap,
  });

  @override
  Widget build(BuildContext context) {
    final isOut = message.isOutgoing;

    return Align(
      alignment: isOut ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isOut
              ? const Color(0xFF1F6FEB).withValues(alpha: 0.85)
              : const Color(0xFF161B22),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isOut ? 16 : 4),
            bottomRight: Radius.circular(isOut ? 4 : 16),
          ),
          border: Border.all(
            color: isOut
                ? const Color(0xFF388BFD)
                : Colors.white.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isOut ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Sender header for incoming packets
            if (!isOut) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF58A6FF),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    message.senderName ?? 'Node ${message.hexSenderId}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF79C0FF),
                    ),
                  ),
                  if (message.recipientId != 65535) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.lock, size: 10, color: Color(0xFF00E676)),
                    const Text(
                      ' (Direct)',
                      style: TextStyle(fontSize: 9, color: Color(0xFF00E676)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
            ],

            // Message text
            Text(
              message.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.3,
              ),
            ),

            // Location Waypoint Attachment
            if (message.hasLocation) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: onLocationTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00E676).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFF00E676), size: 16),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'GPS Waypoint Shared',
                            style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${message.latitude!.toStringAsFixed(5)}, ${message.longitude!.toStringAsFixed(5)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 10),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 6),

            // Bottom metadata: RSSI, SNR, Hop count, Time, Status
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.rssi != null && message.rssi != 0) ...[
                  SignalBadge(rssi: message.rssi!, snr: message.snr ?? 0.0),
                  const SizedBox(width: 6),
                ],
                if (message.hops != null && message.hops! > 0) ...[
                  Text(
                    '${message.hops} hop${message.hops! > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  DateFormat('HH:mm').format(message.timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.6),
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
        return const Icon(Icons.done_all, size: 13, color: Color(0xFF00E676));
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: Colors.redAccent);
    }
  }
}
