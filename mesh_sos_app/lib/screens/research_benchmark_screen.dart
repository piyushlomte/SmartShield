import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/research_benchmark_service.dart';

class ResearchBenchmarkScreen extends StatelessWidget {
  const ResearchBenchmarkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: ResearchBenchmarkService.instance,
      child: Consumer<ResearchBenchmarkService>(
        builder: (context, bench, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Row(
                children: [
                  Icon(Icons.science_outlined, color: Color(0xFF00E676)),
                  SizedBox(width: 8),
                  Text('Research Benchmark & IEEE HUD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.copy_all, color: Color(0xFF58A6FF)),
                  tooltip: 'Copy IEEE LaTeX Table',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: bench.exportIeeeLatexTable()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ IEEE LaTeX Table copied to clipboard! Paste directly into Overleaf / Paper.'),
                        backgroundColor: Color(0xFF1F6FEB),
                      ),
                    );
                  },
                ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Empirical Model Formula Card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF30363D)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.functions, color: Color(0xFF00E676), size: 18),
                            SizedBox(width: 6),
                            Text('Mathematical Formulations (IEEE Model)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        SizedBox(height: 8),
                        Divider(color: Colors.white12, height: 1),
                        SizedBox(height: 8),
                        Text(
                          '• Path Loss: PL(d) = PL(d₀) + 10·η·log₁₀(d/d₀) + X_σ\n'
                          '• Link Cost: C(i,j) = (1 / SNR_ij) × (1 + 1/Batt_j) × HopCount\n'
                          '• Kalman Smoothed GPS: x̂_k = x̂_k⁻ + K_k(z_k - x̂_k⁻)',
                          style: TextStyle(color: Color(0xFF58A6FF), fontSize: 11, fontFamily: 'monospace', height: 1.5),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // 2. Metrics 4-Grid
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricBox(
                          title: 'PDR Efficiency',
                          val: '${bench.packetDeliveryRatio.toStringAsFixed(1)}%',
                          subtitle: '${bench.totalRx} RX / ${bench.totalTx} TX',
                          color: const Color(0xFF00E676),
                          icon: Icons.speed,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricBox(
                          title: 'Avg Roundtrip Latency',
                          val: '${bench.averageLatencyMs.toStringAsFixed(1)} ms',
                          subtitle: 'Sub-50ms Ultra Low',
                          color: const Color(0xFF58A6FF),
                          icon: Icons.timer,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricBox(
                          title: 'Mean Link RSSI',
                          val: '${bench.averageRssi.toStringAsFixed(0)} dBm',
                          subtitle: 'Sensitivity: -124 dBm',
                          color: const Color(0xFFFF9800),
                          icon: Icons.network_check,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricBox(
                          title: 'Mean Signal SNR',
                          val: '+${bench.averageSnr.toStringAsFixed(1)} dB',
                          subtitle: 'SF10 Demod Margin',
                          color: const Color(0xFFE040FB),
                          icon: Icons.multitrack_audio,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 3. Export Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.code, size: 16),
                          label: const Text('Copy LaTeX Table', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF238636),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: bench.exportIeeeLatexTable()));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ IEEE LaTeX Table copied!')),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Export CSV Data', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF58A6FF),
                            side: const BorderSide(color: Color(0xFF58A6FF)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: bench.exportCsv()));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ CSV Dataset copied to clipboard!')),
                            );
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // 4. Live Telemetry Sampling Stream
                  const Text('Live Packet Sampling Trace', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),

                  if (bench.dataPoints.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('No packets sampled yet. Transmit chat or SOS to generate live dataset.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    )
                  else
                    ...bench.dataPoints.reversed.take(8).map((dp) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Node 0x${dp.senderId.toRadixString(16).padLeft(4, '0').toUpperCase()} • Seq #${dp.seq}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                            Text(
                              '${dp.rssi} dBm | SNR: ${dp.snr.toStringAsFixed(1)}dB | ~${dp.latencyMs.toStringAsFixed(0)}ms',
                              style: const TextStyle(color: Color(0xFF00E676), fontSize: 10, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricBox({
    required String title,
    required String val,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 10)),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 6),
          Text(val, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        ],
      ),
    );
  }
}
