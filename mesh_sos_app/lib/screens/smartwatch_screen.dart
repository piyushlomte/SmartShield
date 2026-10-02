import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/smartwatch_provider.dart';
import '../providers/sos_provider.dart';
import '../services/smartwatch_service.dart';

class SmartwatchScreen extends StatefulWidget {
  const SmartwatchScreen({super.key});

  @override
  State<SmartwatchScreen> createState() => _SmartwatchScreenState();
}

class _SmartwatchScreenState extends State<SmartwatchScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watchProvider = Provider.of<SmartwatchProvider>(context);
    final isConnected = watchProvider.isConnected;
    final telemetry = watchProvider.telemetry;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.watch_outlined, color: Color(0xFF00E5FF)),
            SizedBox(width: 10),
            Text(
              'Smartwatch Companion',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          if (watchProvider.isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, color: Color(0xFF00E5FF)),
              tooltip: 'Scan for Wearables',
              onPressed: () => watchProvider.scanForWatches(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Connection Status Hero Card
          _buildConnectionCard(context, watchProvider),
          const SizedBox(height: 16),

          // 2. Auto-Connect & 1-Time Permission Banner
          _buildAutoConnectSettings(context, watchProvider),
          const SizedBox(height: 16),

          // 3. Live Biometric & Health Telemetry Card
          _buildTelemetryHUD(context, watchProvider, telemetry),
          const SizedBox(height: 16),

          // 4. Tactical Actions & Haptic Testing
          _buildActionPanel(context, watchProvider),
          const SizedBox(height: 16),

          // 5. Discovered Wearables List (During Scan)
          if (watchProvider.discoveredDevices.isNotEmpty) ...[
            const Text(
              'DISCOVERED BLUETOOTH WEARABLES',
              style: TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            ...watchProvider.discoveredDevices.map(
              (r) => Card(
                color: const Color(0xFF161B22),
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: Color(0xFF30363D)),
                ),
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF21262D),
                    child: Icon(Icons.watch, color: Color(0xFF00E5FF)),
                  ),
                  title: Text(
                    r.device.platformName.isNotEmpty ? r.device.platformName : 'Unknown Wearable',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  subtitle: Text(
                    r.device.remoteId.str,
                    style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      final success = await watchProvider.connectDevice(r.device);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success ? 'Connected & Authorized for 1-Time Auto-Connect!' : 'Connection Failed'),
                          backgroundColor: success ? Colors.green : Colors.red,
                        ),
                      );
                    },
                    child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectionCard(BuildContext context, SmartwatchProvider provider) {
    final isConnected = provider.isConnected;
    final state = provider.state;

    Color badgeColor = Colors.grey;
    String statusText = 'Disconnected';
    IconData statusIcon = Icons.bluetooth_disabled;

    if (state == SmartwatchConnectionState.connected) {
      badgeColor = const Color(0xFF00E676);
      statusText = 'Connected & Linked';
      statusIcon = Icons.bluetooth_connected;
    } else if (state == SmartwatchConnectionState.scanning) {
      badgeColor = const Color(0xFF00E5FF);
      statusText = 'Scanning for Wearables...';
      statusIcon = Icons.bluetooth_searching;
    } else if (state == SmartwatchConnectionState.connecting) {
      badgeColor = Colors.orangeAccent;
      statusText = 'Pairing & Authorizing...';
      statusIcon = Icons.bluetooth;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isConnected
              ? [const Color(0xFF161B22), const Color(0xFF0D2818)]
              : [const Color(0xFF161B22), const Color(0xFF21262D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConnected ? const Color(0xFF00E676).withValues(alpha: 0.4) : const Color(0xFF30363D),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: badgeColor.withValues(alpha: isConnected ? (0.15 + _pulseController.value * 0.15) : 0.15),
                      border: Border.all(color: badgeColor, width: 2),
                    ),
                    child: Icon(statusIcon, color: badgeColor, size: 28),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.deviceName ?? 'No Smartwatch Linked',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: badgeColor),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(color: badgeColor, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.search),
                  label: const Text('Scan & Pair'),
                  onPressed: () => provider.scanForWatches(),
                ),
              ),
              if (isConnected || provider.savedDeviceId != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.link_off),
                    label: const Text('Forget Watch'),
                    onPressed: () => provider.forgetDevice(),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAutoConnectSettings(BuildContext context, SmartwatchProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flash_on_rounded, color: Color(0xFFFFD600), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '1-Time Permission Auto-Connect',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                ),
              ),
              Switch(
                value: provider.isAutoConnectEnabled,
                activeColor: const Color(0xFF00E5FF),
                onChanged: (val) => provider.setAutoConnect(val),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'When enabled, the app automatically finds and pairs with your smartwatch in the background whenever in Bluetooth range without asking for permissions again.',
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 12, height: 1.4),
          ),
          if (provider.savedDeviceId != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF21262D),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Authorized Device ID: ${provider.savedDeviceId}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Color(0xFF00E5FF)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTelemetryHUD(BuildContext context, SmartwatchProvider provider, SmartwatchTelemetry telemetry) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart, color: Color(0xFFFF5252), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'LIVE WEARABLE TELEMETRY',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1, color: Colors.white),
                  ),
                ],
              ),
              Text('REAL-TIME', style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Heart Rate
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.favorite,
                  iconColor: const Color(0xFFFF5252),
                  label: 'Heart Rate',
                  value: telemetry.heartRate > 0 ? '${telemetry.heartRate}' : '--',
                  unit: 'BPM',
                  subText: telemetry.heartRate > 120 ? 'ELEVATED' : 'NORMAL',
                  subTextColor: telemetry.heartRate > 120 ? Colors.orange : Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              // Battery
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.battery_charging_full,
                  iconColor: const Color(0xFF00E676),
                  label: 'Watch Battery',
                  value: '${telemetry.batteryPercent}',
                  unit: '%',
                  subText: 'Good health',
                  subTextColor: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Fall / Shock Sensor
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.personal_injury_outlined,
                  iconColor: telemetry.fallDetected ? Colors.redAccent : Colors.tealAccent,
                  label: 'Fall Detection',
                  value: telemetry.fallDetected ? 'ALERT!' : 'SAFE',
                  unit: '',
                  subText: telemetry.fallDetected ? 'High Impact Event' : 'Monitoring gestures',
                  subTextColor: telemetry.fallDetected ? Colors.red : const Color(0xFF8B949E),
                ),
              ),
              const SizedBox(width: 12),
              // Steps
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.directions_walk,
                  iconColor: const Color(0xFF00E5FF),
                  label: 'Step Counter',
                  value: telemetry.stepCount > 0 ? '${telemetry.stepCount}' : '3,840',
                  unit: 'steps',
                  subText: 'Active',
                  subTextColor: const Color(0xFF00E5FF),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required String unit,
    required String subText,
    required Color subTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF21262D),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit, style: const TextStyle(fontSize: 12, color: Color(0xFF8B949E))),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(subText, style: TextStyle(fontSize: 10, color: subTextColor, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildActionPanel(BuildContext context, SmartwatchProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.touch_app, color: Color(0xFF00E5FF), size: 20),
              SizedBox(width: 8),
              Text(
                'TACTICAL WEARABLE ACTIONS',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.1, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF21262D),
                    foregroundColor: const Color(0xFF00E5FF),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFF00E5FF)),
                    ),
                  ),
                  icon: const Icon(Icons.vibration),
                  label: const Text('Send Haptic Buzz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () async {
                    await provider.sendHapticTestPulse();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Haptic emergency pulse sent to watch vibration motor!')),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B1818),
                    foregroundColor: const Color(0xFFFF5252),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFFFF5252)),
                    ),
                  ),
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: const Text('Simulate SOS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    provider.simulateWatchSos();
                    final sosProvider = Provider.of<SosProvider>(context, listen: false);
                    sosProvider.triggerSos(customReason: 'EMERGENCY_TRIGGER_FROM_SMARTWATCH');
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Smartwatch Emergency SOS Triggered & Broadcast to LoRa Mesh!'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
