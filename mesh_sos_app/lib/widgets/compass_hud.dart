import 'dart:math';
import 'package:flutter/material.dart';

class CompassHud extends StatelessWidget {
  final double currentHeading;   // In degrees (0 - 360)
  final double targetBearing;    // In degrees (0 - 360)
  final double distanceMeters;   // In meters
  final String targetName;

  const CompassHud({
    super.key,
    required this.currentHeading,
    required this.targetBearing,
    required this.distanceMeters,
    required this.targetName,
  });

  @override
  Widget build(BuildContext context) {
    // Relative angle between current phone heading and target node bearing
    double relativeAngle = targetBearing - currentHeading;
    double rad = (relativeAngle * pi) / 180.0;

    String distStr = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(2)} km'
        : '${distanceMeters.toStringAsFixed(0)} m';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121820),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2F81F7).withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TARGET: $targetName',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                distStr,
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Circular Radar Dial
          SizedBox(
            height: 160,
            width: 160,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer ring
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 2),
                  ),
                ),
                // Inner concentric range ring
                Container(
                  height: 90,
                  width: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white10, width: 1),
                  ),
                ),
                // Cardinal indicators
                const Positioned(top: 4, child: Text('N', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold))),
                const Positioned(bottom: 4, child: Text('S', style: TextStyle(color: Colors.white54, fontSize: 10))),
                const Positioned(left: 6, child: Text('W', style: TextStyle(color: Colors.white54, fontSize: 10))),
                const Positioned(right: 6, child: Text('E', style: TextStyle(color: Colors.white54, fontSize: 10))),

                // Rotating Bearing Pointer
                Transform.rotate(
                  angle: rad,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.navigation, color: Color(0xFFFF9800), size: 36),
                      Container(height: 30, width: 2, color: const Color(0xFFFF9800).withOpacity(0.5)),
                    ],
                  ),
                ),

                // Center Node Dot
                Container(
                  height: 10,
                  width: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF2F81F7),
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Bearing: ${targetBearing.toStringAsFixed(0)}°  |  Heading: ${currentHeading.toStringAsFixed(0)}°',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
