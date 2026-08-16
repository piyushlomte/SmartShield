import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ble_service.dart';
import '../services/location_service.dart';
import '../providers/mesh_provider.dart';

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  bool _antennaAttached = false;
  bool _offlineMapsDownloaded = true;
  bool _sosTested = false;

  @override
  Widget build(BuildContext context) {
    final bleService = Provider.of<BleService>(context);
    final locationService = Provider.of<LocationService>(context);
    final meshProvider = Provider.of<MeshProvider>(context);

    final bool bleReady = bleService.isConnected;
    final bool gpsReady = locationService.currentPosition != null;
    final bool batteryReady = meshProvider.localBattery > 50;

    final int readyCount = (_antennaAttached ? 1 : 0) +
        (_offlineMapsDownloaded ? 1 : 0) +
        (_sosTested ? 1 : 0) +
        (bleReady ? 1 : 0) +
        (gpsReady ? 1 : 0) +
        (batteryReady ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pre-Departure Checklist', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Readiness Score Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: readyCount == 6
                    ? [const Color(0xFF1B5E20), const Color(0xFF2E7D32)]
                    : [const Color(0xFF161B22), const Color(0xFF21262D)],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: readyCount == 6 ? const Color(0xFF00E676) : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  readyCount == 6 ? Icons.verified : Icons.checklist_rtl,
                  size: 40,
                  color: readyCount == 6 ? const Color(0xFF00E676) : const Color(0xFFFF9800),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        readyCount == 6 ? 'ALL SYSTEMS READY' : 'READINESS: $readyCount / 6 CHECKS',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        readyCount == 6
                            ? 'Your hardware & app are prepped for off-grid operation.'
                            : 'Complete all steps before going into zero-coverage zones.',
                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Checklist items
          _buildCheckItem(
            'LoRa Antenna Attached',
            'Never power on or transmit without a 433/868MHz antenna attached to prevent PA damage.',
            _antennaAttached,
            (val) => setState(() => _antennaAttached = val),
          ),
          _buildCheckItem(
            'Heltec Node Paired via BLE',
            bleReady ? 'Connected (${bleService.connectedDevice?.platformName})' : 'Not Connected. Pair in dashboard.',
            bleReady,
            null,
          ),
          _buildCheckItem(
            'GPS Fix Acquired',
            gpsReady ? 'Active Satellite Fix Locked' : 'Waiting for GPS fix or phone location service.',
            gpsReady,
            null,
          ),
          _buildCheckItem(
            'Node Battery > 50%',
            'Current Battery: ${meshProvider.localBattery}%',
            batteryReady,
            null,
          ),
          _buildCheckItem(
            'Offline Map Tiles Cached',
            'OpenStreetMap tiles cached in memory for zero-signal mapping.',
            _offlineMapsDownloaded,
            (val) => setState(() => _offlineMapsDownloaded = val),
          ),
          _buildCheckItem(
            'Touch SOS Hardware Test',
            'Verified 3-sec long touch on TTP223 produces haptic confirmation buzz.',
            _sosTested,
            (val) => setState(() => _sosTested = val),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckItem(String title, String desc, bool isChecked, Function(bool)? onChanged) {
    return Card(
      color: Theme.of(context).cardColor,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: isChecked,
              activeColor: const Color(0xFF00E676),
              onChanged: onChanged != null ? (v) => onChanged(v ?? false) : null,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      decoration: isChecked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
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
