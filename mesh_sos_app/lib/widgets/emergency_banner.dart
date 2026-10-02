import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/alert_service.dart';
import '../screens/sos_screen.dart';

class EmergencyBanner extends StatelessWidget {
  const EmergencyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final alertService = Provider.of<AlertService>(context);
    final alert = alertService.activeEmergency;

    if (alert == null) return const SizedBox.shrink();

    final hasCoords = alert.latitude != 0.0 && alert.longitude != 0.0;
    final hasRescue = alert.responderName != null;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SosScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: hasRescue
                ? [const Color(0xFF0D47A1), const Color(0xFF1565C0)]
                : [const Color(0xFFD50000), const Color(0xFFB71C1C)],
          ),
          boxShadow: [
            BoxShadow(
              color: hasRescue ? Colors.blue.withOpacity(0.4) : Colors.red.withOpacity(0.4),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              hasRescue ? Icons.directions_run : Icons.warning_amber_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        hasRescue ? 'RESCUE EN ROUTE' : 'SOS: ${alert.senderName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (hasCoords) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '📍 ${alert.latitude.toStringAsFixed(4)}, ${alert.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasRescue
                        ? '${alert.responderName}: "${alert.responseMessage ?? 'Help on the way!'}"'
                        : alert.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => alertService.muteSiren(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: hasRescue ? Colors.blue : Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(alertService.isSirenMuted ? 'Muted' : 'Mute', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

