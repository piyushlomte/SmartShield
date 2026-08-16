import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/mesh_provider.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meshProvider = Provider.of<MeshProvider>(context);

    final localNodeHex = '0x${meshProvider.localNodeId.toRadixString(16).padLeft(4, '0').toUpperCase()}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mesh Contacts & Pairing', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // QR Code Pairing Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                const Text(
                  'Your Node QR Pairing Key',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Teammates can scan this to verify direct encryption keys off-grid',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: 'MESHSOS:$localNodeHex:KEY_AES256_DEFAULT_HASH',
                    version: QrVersions.auto,
                    size: 140,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Node ID: $localNodeHex',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Discovered Node List
          Text(
            'Saved Mesh Contacts (${meshProvider.nodes.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 12),

          if (meshProvider.nodes.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text(
                  'No remote contacts discovered yet.\nNodes within LoRa range appear automatically.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, height: 1.4),
                ),
              ),
            )
          else
            ...meshProvider.nodes.values.map((node) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: theme.cardColor,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF2F81F7),
                    child: Text(node.name.isNotEmpty ? node.name[0] : '#', style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(node.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('ID: ${node.hexId} | Bat: ${node.batteryPercent}%', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.chat_bubble_outline, color: Color(0xFF2F81F7)),
                    onPressed: () {
                      meshProvider.setActiveChannel('Direct');
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Switched to direct channel with ${node.name}')),
                      );
                    },
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
