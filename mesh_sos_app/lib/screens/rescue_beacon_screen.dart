import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/location_service.dart';

class RescueBeaconScreen extends StatefulWidget {
  const RescueBeaconScreen({super.key});

  @override
  State<RescueBeaconScreen> createState() => _RescueBeaconScreenState();
}

class _RescueBeaconScreenState extends State<RescueBeaconScreen> {
  bool _isOpticalSosActive = false;
  bool _isScreenWhite = false;
  Timer? _morseTimer;
  int _morseIndex = 0;

  // Standard Morse SOS pattern: 3 dots (200ms), 3 dashes (600ms), 3 dots (200ms)
  // 1 = ON, 0 = OFF
  final List<int> _morsePattern = [
    // S: . . .
    1, 0, 1, 0, 1, 0, 0,
    // O: - - -
    1, 1, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 0,
    // S: . . .
    1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0,
  ];

  @override
  void dispose() {
    _morseTimer?.cancel();
    super.dispose();
  }

  void _toggleOpticalSos() {
    if (_isOpticalSosActive) {
      _morseTimer?.cancel();
      setState(() {
        _isOpticalSosActive = false;
        _isScreenWhite = false;
      });
    } else {
      setState(() {
        _isOpticalSosActive = true;
        _morseIndex = 0;
      });

      _morseTimer = Timer.periodic(const Duration(milliseconds: 180), (timer) {
        if (!_isOpticalSosActive) {
          timer.cancel();
          return;
        }

        final state = _morsePattern[_morseIndex];
        setState(() {
          _isScreenWhite = (state == 1);
        });

        if (state == 1) {
          HapticFeedback.lightImpact();
        }

        _morseIndex = (_morseIndex + 1) % _morsePattern.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationService = Provider.of<LocationService>(context);
    final pos = locationService.currentPosition;

    if (_isOpticalSosActive && _isScreenWhite) {
      return GestureDetector(
        onTap: _toggleOpticalSos,
        child: Container(
          color: Colors.white,
          alignment: Alignment.center,
          child: const Text(
            'TAP ANYWHERE TO STOP SOS STROBE',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.flashlight_on_outlined, color: Color(0xFFFF1744)),
            SizedBox(width: 8),
            Text('Optical & Acoustic Beacon', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 1. Full Screen Strobe Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isOpticalSosActive ? const Color(0xFFFF1744) : Colors.white12,
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _isOpticalSosActive ? Icons.flash_on : Icons.flash_off,
                    size: 54,
                    color: _isOpticalSosActive ? const Color(0xFFFF1744) : Colors.white54,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'International Morse SOS Strobe',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Pulsates full-screen white/red strobe in Morse Code (... --- ...) for aerial drone & SAR rescue detection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(_isOpticalSosActive ? Icons.stop : Icons.play_arrow),
                      label: Text(_isOpticalSosActive ? 'STOP OPTICAL STROBE' : 'START FULL-SCREEN STROBE'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isOpticalSosActive ? const Color(0xFF21262D) : const Color(0xFFFF1744),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _toggleOpticalSos,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. Exact GPS Coordinates Card for Voice Readout
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.location_on, color: Color(0xFF00E676), size: 18),
                      SizedBox(width: 8),
                      Text('Live SAR Coordinates (Voice Readout)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Latitude', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          Text(pos != null ? pos.latitude.toStringAsFixed(6) : 'Acquiring GPS...', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Longitude', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          Text(pos != null ? pos.longitude.toStringAsFixed(6) : 'Acquiring GPS...', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Heading', style: TextStyle(color: Colors.white38, fontSize: 10)),
                          Text('${locationService.currentHeading.toStringAsFixed(0)}°', style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
