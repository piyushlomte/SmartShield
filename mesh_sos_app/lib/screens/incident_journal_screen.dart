import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/incident_journal_service.dart';

class IncidentJournalScreen extends StatelessWidget {
  const IncidentJournalScreen({super.key});

  void _showNotarizeQrDialog(BuildContext context) {
    final journal = IncidentJournalService.instance;
    final hashAnchor = journal.finalCumulativeAnchorHash;
    final isChainValid = journal.verifyChainIntegrity();

    final qrPayload = 'AI_SOS_NOTARIZATION|HASH:$hashAnchor|EVENTS:${journal.records.length}|VALID:$isChainValid|TS:${DateTime.now().toIso8601String()}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Row(
          children: [
            Icon(Icons.qr_code_2, color: Color(0xFF58A6FF), size: 24),
            SizedBox(width: 10),
            Text('Offline Notarization QR', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '§10.7 Cryptographic Hash-Chain Anchor: Scan this QR code with another rescue node to verify offline data integrity.',
              style: TextStyle(color: Colors.white70, fontSize: 11),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: QrImageView(
                data: qrPayload,
                version: QrVersions.auto,
                size: 200.0,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SHA-256 Merkle Anchor:', style: TextStyle(color: Colors.white54, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(
                    hashAnchor,
                    style: const TextStyle(color: Color(0xFF00E676), fontSize: 10, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Anchor Hash'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: hashAnchor));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cryptographic Anchor Hash copied!')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    final journal = IncidentJournalService.instance;
    final markdownReport = journal.generateMarkdownReport();
    final jsonReport = journal.generateJsonReport();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Row(
          children: [
            Icon(Icons.verified_user, color: Color(0xFF58A6FF), size: 22),
            SizedBox(width: 10),
            Text('Export Evidence Report', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The Incident Journal generates an immutable, tamper-evident audit record suitable for SAR operators, first responders, and forensic documentation.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Text(
                'Total Recorded Events: ${journal.records.length}\nHash Anchor: ${journal.finalCumulativeAnchorHash.substring(0, 16)}...\nChain Integrity: ${journal.verifyChainIntegrity() ? "VERIFIED" : "WARNING"}',
                style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.code, size: 16),
            label: const Text('Copy JSON'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: jsonReport));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Forensic JSON Report copied to clipboard!')),
              );
            },
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Markdown Report'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF238636)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: markdownReport));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Full Markdown Incident Evidence Report copied to clipboard!')),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final journal = IncidentJournalService.instance;

    return AnimatedBuilder(
      animation: journal,
      builder: (context, _) {
        final records = journal.records;
        final isChainValid = journal.verifyChainIntegrity();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Emergency Incident Journal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code, color: Color(0xFF58A6FF)),
                tooltip: 'Offline Notarization QR',
                onPressed: () => _showNotarizeQrDialog(context),
              ),
              IconButton(
                icon: const Icon(Icons.share, color: Color(0xFF58A6FF)),
                tooltip: 'Export Evidence Report',
                onPressed: () => _showExportDialog(context),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white54),
                tooltip: 'Clear Journal',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF161B22),
                      title: const Text('Clear Incident Journal?', style: TextStyle(color: Colors.white)),
                      content: const Text('This will erase the local session timeline.', style: TextStyle(color: Colors.white70)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                        TextButton(
                          onPressed: () {
                            journal.clearJournal();
                            Navigator.pop(ctx);
                          },
                          child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Cryptographic Hash-Chain Anchor Status Bar
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF0D1117),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isChainValid ? Icons.lock : Icons.lock_open,
                          size: 14,
                          color: isChainValid ? const Color(0xFF00E676) : Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'SHA-256 Hash Chain: ${isChainValid ? "Verified" : "Broken"}',
                          style: TextStyle(
                            color: isChainValid ? const Color(0xFF00E676) : Colors.redAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'Anchor: ${journal.finalCumulativeAnchorHash.substring(0, 10).toUpperCase()}...',
                      style: const TextStyle(color: Colors.white54, fontSize: 10, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_edu, size: 64, color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 16),
                            const Text(
                              'No Emergency Incidents Logged',
                              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'All distress activations, ACKs, and GPS events are recorded here.',
                              style: TextStyle(color: Colors.white38, fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final r = records[index];
                          final timeStr = DateFormat('HH:mm:ss').format(r.timestamp);
                          final dateStr = DateFormat('MMM dd, yyyy').format(r.timestamp);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161B22),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF30363D)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Header: Icon + Event Title + Time
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(r.eventType.icon, style: const TextStyle(fontSize: 18)),
                                        const SizedBox(width: 8),
                                        Text(
                                          r.eventType.label,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '$timeStr ($dateStr)',
                                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 8),

                                Text(
                                  r.details,
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),

                                const SizedBox(height: 10),

                                // Badges Row: Node ID, Risk, Conf, Location, RF, Hash Stamp
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _buildBadge('Node: ${r.hexSenderId}', const Color(0xFF58A6FF)),
                                    if (r.riskScore > 0)
                                      _buildBadge('Risk: ${r.riskScore}%', r.riskScore > 60 ? const Color(0xFFFF1744) : const Color(0xFFFFB300)),
                                    if (r.confidenceScore > 0)
                                      _buildBadge('Conf: ${r.confidenceScore}%', const Color(0xFF00E676)),
                                    if (r.signalAnomalyScore > 0)
                                      _buildBadge('RF Anomaly: ${r.signalAnomalyScore}%', Colors.purpleAccent),
                                    if (r.latitude != 0.0)
                                      _buildBadge(
                                        'GPS: ${r.latitude.toStringAsFixed(4)}, ${r.longitude.toStringAsFixed(4)} (${r.gpsSource.name})',
                                        const Color(0xFF79C0FF),
                                      ),
                                    if (r.rssi != 0)
                                      _buildBadge('RSSI: ${r.rssi}dBm / ${r.snr.toStringAsFixed(1)}dB', Colors.grey),
                                    _buildBadge('Hash: ${r.shortHash}', const Color(0xFF3FB950)),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: const Color(0xFF238636),
            icon: const Icon(Icons.download, color: Colors.white),
            label: const Text('Export Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            onPressed: () => _showExportDialog(context),
          ),
        );
      },
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }
}
