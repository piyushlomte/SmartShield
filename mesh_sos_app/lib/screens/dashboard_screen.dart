import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ble_service.dart';
import '../services/location_service.dart';
import '../widgets/signal_badge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meshProvider = Provider.of<MeshProvider>(context);
    final bleService = Provider.of<BleService>(context);
    final locationService = Provider.of<LocationService>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    final onlineNodesCount = meshProvider.nodes.values.where((n) => n.isOnline).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Mesh SOS', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(
              themeProvider.isTrailMode ? Icons.wb_sunny_outlined : Icons.dark_mode_outlined,
              color: themeProvider.isTrailMode ? Colors.amber : null,
            ),
            tooltip: 'Toggle Trail Mode (AMOLED Saver)',
            onPressed: () => themeProvider.toggleTrailMode(),
          ),
          IconButton(
            icon: Icon(
              bleService.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: bleService.isConnected ? const Color(0xFF00E676) : Colors.grey,
            ),
            onPressed: () => _showBleDialog(context, bleService),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Node Hardware Status Card
          _buildNodeStatusCard(context, meshProvider, bleService, locationService),
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
                  '433 / 868 MHz',
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
                  'GPS Fix',
                  locationService.currentPosition != null ? 'Active Lock' : 'Searching...',
                  Icons.satellite_alt,
                  locationService.currentPosition != null ? const Color(0xFF00E676) : Colors.orange,
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
          const SizedBox(height: 20),

          // Nearby Active Mesh Nodes List
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nearby Mesh Members',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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
              ),
              child: const Center(
                child: Text(
                  'Listening on LoRa frequency...\nNo remote nodes detected yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, height: 1.4),
                ),
              ),
            )
          else
            ...meshProvider.nodes.values.map((node) => _buildNodeListTile(context, node)),
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
                            : 'Node Disconnected',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                      Text(
                        'ID: 0x${mesh.localNodeId.toRadixString(16).toUpperCase()}',
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
                  ble.isConnected ? 'PAIRED' : 'OFFLINE',
                  style: TextStyle(
                    color: ble.isConnected ? const Color(0xFF00E676) : Colors.red,
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
                'Phone GPS',
                loc.currentPosition != null
                    ? '${loc.currentPosition!.latitude.toStringAsFixed(3)}, ${loc.currentPosition!.longitude.toStringAsFixed(3)}'
                    : 'Searching',
                Icons.my_location,
              ),
              _buildMiniInfo('Mesh Protocol', 'AES / Priority', Icons.security),
            ],
          ),
          if (!ble.isConnected)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.bluetooth_searching, size: 18),
                  label: const Text('Scan & Connect LoRa Node', style: TextStyle(fontWeight: FontWeight.bold)),
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
          Text(val, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildNodeListTile(BuildContext context, dynamic node) {
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
                Text(
                  'Hops: ${node.hopCount} | Bat: ${node.batteryPercent}% | GPS: ${node.gpsSource.label}',
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
                        final name = r.device.platformName.isEmpty ? 'Unknown BLE Device' : r.device.platformName;
                        final isHeltec = name.toLowerCase().contains('heltec') || name.toLowerCase().contains('mesh') || name.toLowerCase().contains('sos');

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isHeltec ? const Color(0xFF00E676).withOpacity(0.2) : Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.bluetooth,
                              color: isHeltec ? const Color(0xFF00E676) : Colors.white70,
                              size: 18,
                            ),
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontWeight: isHeltec ? FontWeight.bold : FontWeight.normal,
                              color: isHeltec ? const Color(0xFF00E676) : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '${r.device.remoteId.str} | RSSI: ${r.rssi} dBm',
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

