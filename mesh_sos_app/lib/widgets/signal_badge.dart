import 'package:flutter/material.dart';

class SignalBadge extends StatelessWidget {
  final int rssi;
  final double snr;

  const SignalBadge({
    super.key,
    required this.rssi,
    required this.snr,
  });

  Color _getSignalColor() {
    if (rssi >= -85) return const Color(0xFF00E676); // Excellent (Green)
    if (rssi >= -105) return const Color(0xFFFFB300); // Fair (Yellow/Orange)
    return const Color(0xFFFF5252); // Weak (Red)
  }

  @override
  Widget build(BuildContext context) {
    final color = _getSignalColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_tethering, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '${rssi}dBm',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (snr != 0.0) ...[
            const SizedBox(width: 4),
            Text(
              'SNR: ${snr.toStringAsFixed(1)}',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
