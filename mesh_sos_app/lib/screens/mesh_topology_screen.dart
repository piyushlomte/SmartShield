import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';
import '../services/ble_service.dart';
import '../models/mesh_node.dart';

class MeshTopologyScreen extends StatefulWidget {
  const MeshTopologyScreen({super.key});

  @override
  State<MeshTopologyScreen> createState() => _MeshTopologyScreenState();
}

class _MeshTopologyScreenState extends State<MeshTopologyScreen> {
  int? _pingingNodeId;
  String? _pingResult;

  void _pingNode(int targetNodeId, MeshProvider meshProvider, BleService bleService) async {
    setState(() {
      _pingingNodeId = targetNodeId;
      _pingResult = 'Pinging Node 0x${targetNodeId.toRadixString(16).padLeft(4, '0').toUpperCase()} over LoRa...';
    });

    final stopwatch = Stopwatch()..start();

    // Send a compact ping command via BLE
    final ok = await bleService.sendCommand({
      "cmd": "CHAT",
      "dst": targetNodeId,
      "msg": "PING",
    });

    stopwatch.stop();

    setState(() {
      _pingingNodeId = null;
      if (ok) {
        _pingResult = '✅ Ping Dispatched over LoRa! Latency: ~${stopwatch.elapsedMilliseconds}ms (Local BLE ACK)';
      } else {
        _pingResult = '❌ Ping Failed: Device disconnected or radio busy.';
      }
    });
  }

  Color _getSignalColor(int rssi) {
    if (rssi >= -80) return const Color(0xFF00E676);
    if (rssi >= -100) return const Color(0xFFD29922);
    return const Color(0xFFFF1744);
  }

  @override
  Widget build(BuildContext context) {
    final meshProvider = Provider.of<MeshProvider>(context);
    final bleService = Provider.of<BleService>(context);
    final nodes = meshProvider.nodes.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.hub_outlined, color: Color(0xFF58A6FF)),
            SizedBox(width: 8),
            Text('Mesh Topology & Signal HUD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. RF Physical Channel Parameters Card
            Container(
              padding: const EdgeInsets.all(14),
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
                          Icon(Icons.radio, color: Color(0xFF00E676), size: 18),
                          SizedBox(width: 8),
                          Text('LoRa Physical Layer (RF Spec)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      Text('India 865-867 MHz Band', style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 10),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _RfParamTile(label: 'Center Freq', val: '865.200 MHz'),
                      _RfParamTile(label: 'Bandwidth', val: '125.0 kHz'),
                      _RfParamTile(label: 'Spreading Factor', val: 'SF10 (High Range)'),
                      _RfParamTile(label: 'Coding Rate', val: '4/5'),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. Ping Feedback Banner
            if (_pingResult != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F6FEB).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1F6FEB)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.network_ping, color: Color(0xFF58A6FF), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_pingResult!, style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ],
                ),
              ),

            // 3. Discovered Nodes Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Active Mesh Nodes (${nodes.length})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  'Local Node: ${meshProvider.localHexId}',
                  style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),

            const SizedBox(height: 10),

            // 4. Nodes Topology List
            if (nodes.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.radar, color: Colors.white38, size: 36),
                    SizedBox(height: 8),
                    Text('Listening for neighboring LoRa beacons...', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    SizedBox(height: 4),
                    Text('Turn on Node 2 or press SOS to discover', style: TextStyle(color: Colors.white30, fontSize: 10)),
                  ],
                ),
              )
            else
              ...nodes.map((node) {
                final sigColor = _getSignalColor(node.rssi);
                final isPinging = _pingingNodeId == node.nodeId;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161B22),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: node.isSosActive ? Colors.redAccent : Colors.white12,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: sigColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              node.isSosActive ? Icons.warning : Icons.router,
                              color: node.isSosActive ? Colors.redAccent : sigColor,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      node.name,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    const SizedBox(width: 6),
                                    if (node.isSosActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Text('SOS ACTIVE', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'RSSI: ${node.rssi} dBm • SNR: ${node.snr.toStringAsFixed(1)} dB • Battery: ${node.batteryPercent}% • Hops: ${node.hopCount}',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                                if (node.latitude != 0.0)
                                  Text(
                                    'GPS: ${node.latitude.toStringAsFixed(4)}, ${node.longitude.toStringAsFixed(4)} (${node.gpsSource.label})',
                                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                                  ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF21262D),
                              foregroundColor: const Color(0xFF58A6FF),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: isPinging ? null : () => _pingNode(node.nodeId, meshProvider, bleService),
                            child: isPinging
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.network_ping, size: 14),
                                      SizedBox(width: 4),
                                      Text('Ping', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _RfParamTile extends StatelessWidget {
  final String label;
  final String val;
  const _RfParamTile({required this.label, required this.val});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        const SizedBox(height: 2),
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
