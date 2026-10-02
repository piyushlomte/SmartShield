import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ble_service.dart';
import '../services/location_service.dart';
import '../services/ai_safety_service.dart';
import '../widgets/signal_badge.dart';
import '../widgets/ai_emergency_assistant_card.dart';
import 'incident_journal_screen.dart';
import 'ai_assistant_screen.dart';
import 'mesh_topology_screen.dart';
import 'rescue_beacon_screen.dart';
import 'research_benchmark_screen.dart';
import 'smartwatch_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meshProvider = Provider.of<MeshProvider>(context);
    final bleService = Provider.of<BleService>(context);
    final locationService = Provider.of<LocationService>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final aiService = Provider.of<AiSafetyService>(context);

    final onlineNodesCount = meshProvider.nodes.values.where((n) => n.isOnline).length;
    final phonePos = locationService.currentPosition;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset(
            'assets/images/app_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Colors.redAccent),
          ),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SmartShield SOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text('Offline LoRa Mesh & GPS', style: TextStyle(fontSize: 10, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.watch_outlined, color: Color(0xFF00E5FF)),
            tooltip: 'Smartwatch Companion HUD',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SmartwatchScreen()),
              );
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              themeProvider.isTrailMode ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
              color: themeProvider.isTrailMode ? Colors.amber : null,
            ),
            tooltip: 'Toggle Trail Mode (AMOLED Saver)',
            onPressed: () => themeProvider.toggleTrailMode(),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              bleService.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: bleService.isConnected ? const Color(0xFF00E676) : Colors.grey,
            ),
            tooltip: bleService.isConnected ? 'Connected to Heltec' : 'Scan & Auto Connect',
            onPressed: () => _showBleDialog(context, bleService),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Auto BLE Connect Status Banner
          if (!bleService.isConnected)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2F81F7).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2F81F7)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bleService.statusMessage,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Auto-pairing with Heltec-Mesh-SOS in background...',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _showBleDialog(context, bleService),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    child: const Text('Manage', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 12)),
                  ),
                ],
              ),
            ),

          // AI Emergency Engine & Explainable Risk Assistant
          const AiEmergencyAssistantCard(),
          const SizedBox(height: 12),

          // Node Hardware Status Card
          _buildNodeStatusCard(context, meshProvider, bleService, locationService),
          const SizedBox(height: 14),

          // AI Edge Safety & Anomaly Engine Card
          _buildAiSafetyCard(context, aiService),
          const SizedBox(height: 16),

          // Quick Statistics Grid
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  'Mesh Nodes',
                  '$onlineNodesCount Active',
                  Icons.hub,
                  const Color(0xFF2F81F7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  context,
                  'Radio Band',
                  '865.200 MHz (IN)',
                  Icons.radio,
                  const Color(0xFFFF9800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  context,
                  'Offline GPS',
                  phonePos != null
                      ? '${phonePos.latitude.toStringAsFixed(4)}, ${phonePos.longitude.toStringAsFixed(4)}'
                      : 'Searching...',
                  Icons.satellite_alt,
                  phonePos != null ? const Color(0xFF00E676) : Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMetricTile(
                  context,
                  'Channel',
                  meshProvider.activeChannel,
                  Icons.chat_bubble_outline,
                  const Color(0xFFE040FB),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Nearby Active Mesh Nodes List with Distance & Bearing
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.near_me, size: 18, color: Color(0xFF00E676)),
                  const SizedBox(width: 6),
                  Text(
                    'Nearby Users & Nodes',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Text(
                '${meshProvider.nodes.length} Discovered',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (meshProvider.nodes.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: const Center(
                child: Column(
                  children: [
                    Icon(Icons.radar, size: 36, color: Colors.white30),
                    SizedBox(height: 10),
                    Text(
                      'Listening on LoRa mesh frequency...\nNearby users will appear here with live distance.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.4, fontSize: 12),
                    ),
                  ],
                ),
              ),
            )
          else
            ...meshProvider.nodes.values.map(
              (node) => _buildNodeListTile(context, node, locationService),
            ),
        ],
      ),
    );
  }

  Widget _buildNodeStatusCard(
    BuildContext context,
    MeshProvider mesh,
    BleService ble,
    LocationService loc,
  ) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF161B22), Color(0xFF21262D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F81F7).withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.router, color: Color(0xFF2F81F7), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ble.isConnected
                            ? ble.connectedDevice?.platformName ?? 'Heltec Node'
                            : 'Heltec Mesh Node',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                      Text(
                        'ID: 0x${mesh.localNodeId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: ble.isConnected ? const Color(0xFF00E676).withOpacity(0.15) : Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  ble.isConnected ? 'PAIRED' : 'AUTO-SEARCH',
                  style: TextStyle(
                    color: ble.isConnected ? const Color(0xFF00E676) : Colors.orange,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniInfo('Battery', '${mesh.localBattery}%', Icons.battery_charging_full),
              _buildMiniInfo(
                'Coordinates',
                loc.currentPosition != null
                    ? '${loc.currentPosition!.latitude.toStringAsFixed(4)}, ${loc.currentPosition!.longitude.toStringAsFixed(4)}'
                    : 'Searching',
                Icons.my_location,
              ),
              _buildMiniInfo('Mesh Protocol', 'SX1262 LoRa', Icons.security),
            ],
          ),
          if (loc.currentPosition != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF238636).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF238636).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.temple_hindu_rounded, size: 16, color: Color(0xFF00E676)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${loc.currentNearPlace} • ${loc.currentAreaName}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF00E676)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!ble.isConnected)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: const Text('Connect Device Manually', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2F81F7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _showBleDialog(context, ble),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAiSafetyCard(BuildContext context, AiSafetyService ai) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ai.isEnabled ? const Color(0xFF00E676).withOpacity(0.4) : Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: ai.isEnabled ? const Color(0xFF00E676).withOpacity(0.15) : Colors.white10,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.psychology,
                      color: ai.isEnabled ? const Color(0xFF00E676) : Colors.grey,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Edge Safety Engine',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                      ),
                      Text(
                        'Fall, Impact & Inactivity Guard',
                        style: TextStyle(fontSize: 10, color: Colors.white54),
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: ai.isEnabled,
                activeColor: const Color(0xFF00E676),
                onChanged: (val) => ai.setEnabled(val),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniInfo(
                'Live Motion G',
                '${(ai.currentG / 9.8).toStringAsFixed(2)} G',
                Icons.speed,
              ),
              _buildMiniInfo(
                'Anomaly State',
                ai.isCountdownActive
                    ? '⚠️ COUNTDOWN'
                    : (ai.isEnabled ? '🟢 Normal' : '⚪ Standby'),
                Icons.health_and_safety,
              ),
              _buildMiniInfo(
                'Auto-SOS Delay',
                '10 Seconds',
                Icons.timer_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.science_outlined, size: 16, color: Colors.cyanAccent),
              label: const Text(
                '🧪 Test AI Fall & Impact Trigger',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.cyanAccent, width: 1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () {
                ai.simulateFallEvent();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniInfo(String title, String val, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 10, color: Colors.white54)),
            Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile(BuildContext context, String title, String val, IconData icon, Color accent) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          const SizedBox(height: 2),
          Text(
            val,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeListTile(BuildContext context, dynamic node, LocationService loc) {
    final pos = loc.currentPosition;
    double dist = 0.0;
    double bearing = 0.0;
    bool hasGps = node.latitude != 0.0 && node.longitude != 0.0;

    if (pos != null && hasGps) {
      dist = LocationService.calculateDistance(pos.latitude, pos.longitude, node.latitude, node.longitude);
      bearing = LocationService.calculateBearing(pos.latitude, pos.longitude, node.latitude, node.longitude);
      if (bearing < 0) bearing += 360;
    }

    String distStr = dist > 1000 ? '${(dist / 1000).toStringAsFixed(1)} km away' : '${dist.toInt()} m away';
    String dirStr = _getCardinalDirection(bearing);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: node.isSosActive ? Colors.red : Colors.white10,
          width: node.isSosActive ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: node.isSosActive ? Colors.red : const Color(0xFF2F81F7),
            radius: 18,
            child: Icon(
              node.isSosActive ? Icons.warning : Icons.person,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 2),
                if (hasGps && pos != null)
                  Row(
                    children: [
                      const Icon(Icons.navigation, size: 12, color: Color(0xFF00E676)),
                      const SizedBox(width: 4),
                      Text(
                        '$distStr • $dirStr (${bearing.toInt()}°)',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                else
                  Text(
                    'Hops: ${node.hopCount} | Bat: ${node.batteryPercent}% | ${hasGps ? "GPS Fix" : "No GPS"}',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
              ],
            ),
          ),
          SignalBadge(rssi: node.rssi, snr: node.snr),
        ],
      ),
    );
  }

  String _getCardinalDirection(double bearing) {
    if (bearing >= 337.5 || bearing < 22.5) return 'N';
    if (bearing >= 22.5 && bearing < 67.5) return 'NE';
    if (bearing >= 67.5 && bearing < 112.5) return 'E';
    if (bearing >= 112.5 && bearing < 157.5) return 'SE';
    if (bearing >= 157.5 && bearing < 202.5) return 'S';
    if (bearing >= 202.5 && bearing < 247.5) return 'SW';
    if (bearing >= 247.5 && bearing < 292.5) return 'W';
    return 'NW';
  }

  void _showBleDialog(BuildContext context, BleService ble) {
    ble.startScan();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF30363D))),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Connect Heltec Node', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            Consumer<BleService>(
              builder: (_, s, __) => s.isScanning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2F81F7)))
                  : IconButton(
                      icon: const Icon(Icons.refresh, size: 20, color: Colors.blueAccent),
                      tooltip: 'Rescan',
                      onPressed: () => ble.startScan(),
                    ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: Consumer<BleService>(
            builder: (context, service, _) {
              if (service.scanResults.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(service.isScanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled, size: 40, color: Colors.white54),
                      const SizedBox(height: 12),
                      Text(
                        service.isScanning ? 'Scanning for Heltec-Mesh-SOS...' : 'No Bluetooth devices found.',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        service.statusMessage,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.security, size: 16),
                        label: const Text('Check Permissions & Rescan'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF21262D), foregroundColor: Colors.white),
                        onPressed: () => service.startScan(),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Found ${service.scanResults.length} device(s) nearby:',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      itemCount: service.scanResults.length,
                      separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                      itemBuilder: (context, i) {
                        final r = service.scanResults[i];
                        final advName = r.advertisementData.advName;
                        final platName = r.device.platformName;
                        final displayName = advName.isNotEmpty
                            ? advName
                            : (platName.isNotEmpty ? platName : 'Device (${r.device.remoteId.str})');
                        final isHeltec = displayName.toLowerCase().contains('heltec') ||
                            displayName.toLowerCase().contains('mesh') ||
                            displayName.toLowerCase().contains('sos') ||
                            r.advertisementData.serviceUuids.any((u) => u.toString().toUpperCase().contains('6E40'));

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isHeltec ? const Color(0xFF00E676).withValues(alpha: 0.2) : Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.bluetooth,
                              color: isHeltec ? const Color(0xFF00E676) : Colors.white70,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            displayName,
                            style: TextStyle(
                              fontWeight: isHeltec ? FontWeight.bold : FontWeight.normal,
                              color: isHeltec ? const Color(0xFF00E676) : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${r.device.remoteId.str} | RSSI: ${r.rssi} dBm${r.advertisementData.serviceUuids.isNotEmpty ? " • 6E40 Mesh" : ""}',
                            style: const TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isHeltec ? const Color(0xFF00E676) : const Color(0xFF2F81F7),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () async {
                              bool ok = await service.connect(r.device);
                              if (context.mounted && ok) {
                                Navigator.of(ctx).pop();
                              }
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ble.stopScan();
              Navigator.of(ctx).pop();
            },
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
