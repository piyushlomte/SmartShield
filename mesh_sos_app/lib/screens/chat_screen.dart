import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';
import '../services/location_service.dart';
import '../services/ble_service.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _selectedRecipientId = 65535; // 65535 = Broadcast to all nodes
  bool _attachGps = false;
  bool _isSearching = false;
  bool _showScrollDownButton = false;

  final Map<String, List<String>> _quickPhraseCategories = {
    "⚡ Tactical": [
      "📍 Waypoint reached",
      "🛑 Hold current position",
      "🏃 Moving to rally point",
      "👁️ Visual on target / area",
      "📶 Signal check / Copy?",
    ],
    "🩹 Medical / SAR": [
      "🚑 First aid required",
      "🪨 Obstacle / debris ahead",
      "💧 Water / rations depleted",
      "👍 Patient stabilized",
      "🚁 Requesting extraction",
    ],
    "⛺ Logistics": [
      "🏕️ Base camp established",
      "🔋 Battery running low",
      "🌧️ Inclement weather inbound",
      "📻 Standing by on 865MHz",
      "✅ All clear & safe",
    ],
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.hasClients) {
        // In reverse: true mode, offset > 100 means user scrolled up to read history
        final showBtn = _scrollController.offset > 120;
        if (showBtn != _showScrollDownButton) {
          setState(() => _showScrollDownButton = showBtn);
        }
      }
    });
  }

  @override
  void dispose() {
    _msgController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0, // 0.0 is the latest message at the bottom in reverse mode
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendCurrentMessage(MeshProvider meshProvider, BleService bleService) {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    if (!bleService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Note: Heltec node is disconnected. Connect in Settings/Bluetooth for LoRa radio transmit.'),
          backgroundColor: Color(0xFFD29922),
          duration: Duration(seconds: 3),
        ),
      );
    }

    meshProvider.sendMessage(
      text,
      recipientId: _selectedRecipientId,
      attachLocation: _attachGps,
    );

    _msgController.clear();
    setState(() {
      _attachGps = false;
    });
    _scrollToBottom();
  }

  void _showSimulatorDialog(BuildContext context, MeshProvider meshProvider) {
    final textController = TextEditingController(text: "Loud and clear! Standing by at Ridge Post.");
    final nodeController = TextEditingController(text: "2A3F");

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Row(
          children: [
            Icon(Icons.science_outlined, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text('Mesh Link Bench Simulator', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Simulate an incoming off-grid LoRa message from a remote node to test reception, notification, and mapping:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nodeController,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                labelText: 'Remote Node Hex ID',
                labelStyle: TextStyle(color: Colors.cyanAccent, fontSize: 12),
                hintText: 'e.g. 2A3F',
                filled: true,
                fillColor: Color(0xFF0D1117),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textController,
              maxLines: 2,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Message Payload',
                labelStyle: TextStyle(color: Colors.cyanAccent, fontSize: 12),
                filled: true,
                fillColor: Color(0xFF0D1117),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.play_arrow, color: Colors.black),
            label: const Text('Simulate Inbound', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent),
            onPressed: () {
              int nodeId = int.tryParse(nodeController.text.trim(), radix: 16) ?? 0x2A3F;
              final loc = Provider.of<LocationService>(context, listen: false).currentPosition;
              meshProvider.simulateIncomingMessage(
                fromNodeId: nodeId,
                messageText: textController.text.trim(),
                lat: loc?.latitude,
                lon: loc?.longitude,
              );
              Navigator.pop(ctx);
              _scrollToBottom();
            },
          ),
        ],
      ),
    );
  }

  void _showQuickPhraseModal(BuildContext context, MeshProvider meshProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '⚡ Tactical Preset Library',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView(
                  children: _quickPhraseCategories.entries.map((entry) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            entry.key,
                            style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: entry.value.map((phrase) {
                            return ActionChip(
                              label: Text(phrase, style: const TextStyle(color: Colors.white, fontSize: 12)),
                              backgroundColor: const Color(0xFF21262D),
                              side: const BorderSide(color: Colors.white10),
                              onPressed: () {
                                Navigator.pop(ctx);
                                meshProvider.sendMessage(
                                  phrase,
                                  recipientId: _selectedRecipientId,
                                  attachLocation: _attachGps,
                                );
                                _scrollToBottom();
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meshProvider = Provider.of<MeshProvider>(context);
    final bleService = Provider.of<BleService>(context);
    final locService = Provider.of<LocationService>(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search mesh messages...',
                  hintStyle: const TextStyle(color: Colors.white54),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white70),
                    onPressed: () {
                      _searchController.clear();
                      meshProvider.setSearchQuery('');
                      setState(() => _isSearching = false);
                    },
                  ),
                ),
                onChanged: (val) => meshProvider.setSearchQuery(val),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final activeCh = meshProvider.activeChannel;
                      final channelList = <String>['Public', 'Team Alpha', 'Base Camp', 'Medical / SAR', 'Direct'];
                      if (!channelList.contains(activeCh)) {
                        channelList.add(activeCh);
                      }
                      return DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: channelList.contains(activeCh) ? activeCh : 'Public',
                          dropdownColor: const Color(0xFF161B22),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                          items: channelList.map((ch) {
                            return DropdownMenuItem(
                              value: ch,
                              child: Text(ch == 'Direct' ? 'Direct Message' : 'Channel: #$ch'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) meshProvider.setActiveChannel(val);
                          },
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: bleService.isConnected ? const Color(0xFF00E676) : Colors.redAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _selectedRecipientId == 65535
                            ? 'Broadcast (All Nodes) • Node 0x${meshProvider.localNodeId.toRadixString(16).padLeft(4, '0').toUpperCase()}'
                            : 'Direct: Node 0x${_selectedRecipientId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                        style: TextStyle(
                          fontSize: 10,
                          color: bleService.isConnected ? const Color(0xFF00E676) : Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search Messages',
              onPressed: () => setState(() => _isSearching = true),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Channel & Direct Options',
            onSelected: (action) {
              if (action == 'all') {
                setState(() => _selectedRecipientId = 65535);
              } else if (action == 'simulate') {
                _showSimulatorDialog(context, meshProvider);
              } else if (action == 'export') {
                final txt = meshProvider.exportChatTranscript();
                Clipboard.setData(ClipboardData(text: txt));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chat transcript copied to clipboard!'),
                    backgroundColor: Color(0xFF1F6FEB),
                  ),
                );
              } else if (action == 'clear') {
                meshProvider.clearCurrentChannelHistory();
              } else if (action.startsWith('node:')) {
                int id = int.tryParse(action.substring(5)) ?? 65535;
                setState(() => _selectedRecipientId = id);
              }
            },
            itemBuilder: (context) {
              return [
                const PopupMenuItem(
                  value: 'all',
                  child: Row(
                    children: [
                      Icon(Icons.podcasts, color: Color(0xFF00E676), size: 18),
                      SizedBox(width: 8),
                      Text('Broadcast (All Mesh)'),
                    ],
                  ),
                ),
                if (meshProvider.nodes.isNotEmpty) const PopupMenuDivider(),
                ...meshProvider.nodes.values.map((node) {
                  return PopupMenuItem(
                    value: 'node:${node.nodeId}',
                    child: Row(
                      children: [
                        const Icon(Icons.person_pin, color: Colors.cyanAccent, size: 18),
                        SizedBox(width: 8),
                        Text('Direct: ${node.name}'),
                      ],
                    ),
                  );
                }),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'simulate',
                  child: Row(
                    children: [
                      Icon(Icons.science_outlined, color: Colors.cyanAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Bench Test Simulator'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.ios_share_outlined, color: Colors.white70, size: 18),
                      SizedBox(width: 8),
                      Text('Export Chat Log'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Clear Channel Messages', style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Direct 1-to-1 Indicator Banner
          if (_selectedRecipientId != 65535)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF161B22),
              child: Row(
                children: [
                  const Icon(Icons.lock, color: Color(0xFF00E676), size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Direct 2-Way to Node 0x${_selectedRecipientId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _selectedRecipientId = 65535),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF21262D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text('Back to Broadcast', style: TextStyle(color: Colors.blueAccent, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),

          // Horizontal Fast-Access Quick Phrase Bar
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: const Color(0xFF0D1117),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.bolt, color: Colors.amber, size: 16),
                  label: const Text('Preset Library', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  backgroundColor: const Color(0xFF21262D),
                  onPressed: () => _showQuickPhraseModal(context, meshProvider),
                ),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.location_on, color: Color(0xFF00E676), size: 14),
                  label: const Text('Share Waypoint', style: TextStyle(fontSize: 11)),
                  backgroundColor: const Color(0xFF161B22),
                  onPressed: () {
                    final pos = locService.currentPosition;
                    if (pos != null) {
                      meshProvider.sendMessage(
                        "📍 Shared Waypoint: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}",
                        recipientId: _selectedRecipientId,
                        attachLocation: true,
                      );
                      _scrollToBottom();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Acquiring GPS fix... please wait a moment.')),
                      );
                    }
                  },
                ),
                const SizedBox(width: 6),
                ActionChip(
                  label: const Text('👍 Safe & Clear', style: TextStyle(fontSize: 11)),
                  backgroundColor: const Color(0xFF161B22),
                  onPressed: () {
                    meshProvider.sendMessage('👍 All clear and operating normally.', recipientId: _selectedRecipientId);
                    _scrollToBottom();
                  },
                ),
                const SizedBox(width: 6),
                ActionChip(
                  label: const Text('📶 Radio Check', style: TextStyle(fontSize: 11)),
                  backgroundColor: const Color(0xFF161B22),
                  onPressed: () {
                    meshProvider.sendMessage('📶 Radio check on 865MHz. How copy?', recipientId: _selectedRecipientId);
                    _scrollToBottom();
                  },
                ),
                const SizedBox(width: 6),
                ActionChip(
                  label: const Text('🔋 Low Battery', style: TextStyle(fontSize: 11)),
                  backgroundColor: const Color(0xFF161B22),
                  onPressed: () {
                    meshProvider.sendMessage('🔋 Power low, reducing transmission intervals.', recipientId: _selectedRecipientId);
                    _scrollToBottom();
                  },
                ),
              ],
            ),
          ),

          // Message History List with Instant Bottom Anchor (reverse: true)
          Expanded(
            child: Stack(
              children: [
                meshProvider.messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.cell_tower, size: 48, color: Colors.white.withValues(alpha: 0.2)),
                            const SizedBox(height: 12),
                            Text(
                              'No messages in #${meshProvider.activeChannel} yet.\nMessages are routed off-grid across SX1262 LoRa mesh.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.science_outlined, size: 18),
                              label: const Text('Run Bench Test Simulator'),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.cyanAccent),
                              onPressed: () => _showSimulatorDialog(context, meshProvider),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        reverse: true, // Anchor latest message right at the bottom
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: meshProvider.messages.length,
                        itemBuilder: (context, i) {
                          // With reverse: true, item 0 is the newest / last message
                          final msg = meshProvider.messages[meshProvider.messages.length - 1 - i];
                          return GestureDetector(
                            onTap: () {
                              if (!msg.isOutgoing && msg.senderId != 0) {
                                setState(() => _selectedRecipientId = msg.senderId);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Target set to Node 0x${msg.senderId.toRadixString(16).toUpperCase()} (Direct Reply)'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: MessageBubble(
                              message: msg,
                              onLocationTap: () {
                                if (msg.hasLocation) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Waypoint: ${msg.latitude}, ${msg.longitude} - Switch to Map tab to view'),
                                      backgroundColor: const Color(0xFF1F6FEB),
                                    ),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),

                // Floating "Scroll to Latest Message" button when scrolled up
                if (_showScrollDownButton)
                  Positioned(
                    bottom: 12,
                    right: 14,
                    child: FloatingActionButton.small(
                      backgroundColor: const Color(0xFF1F6FEB),
                      foregroundColor: Colors.white,
                      tooltip: 'Scroll to Latest Message',
                      onPressed: _scrollToBottom,
                      child: const Icon(Icons.arrow_downward, size: 18),
                    ),
                  ),
              ],
            ),
          ),

          // Waypoint Attachment Chip Indicator
          if (_attachGps)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: const Color(0xFF1F6FEB).withValues(alpha: 0.2),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Color(0xFF00E676), size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Live GPS Waypoint will be attached to this message',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 16),
                    onPressed: () => setState(() => _attachGps = false),
                  ),
                ],
              ),
            ),

          // Message Input Field Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: const Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Attach GPS Waypoint toggle button
                  IconButton(
                    icon: Icon(
                      Icons.location_on_outlined,
                      color: _attachGps ? const Color(0xFF00E676) : Colors.white60,
                    ),
                    tooltip: 'Attach GPS Coordinates',
                    onPressed: () {
                      setState(() {
                        _attachGps = !_attachGps;
                      });
                    },
                  ),

                  // Text input
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _selectedRecipientId == 65535
                            ? 'Type broadcast message...'
                            : 'Direct reply to Node 0x${_selectedRecipientId.toRadixString(16).toUpperCase()}...',
                        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendCurrentMessage(meshProvider, bleService),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send button
                  IconButton.filled(
                    onPressed: () => _sendCurrentMessage(meshProvider, bleService),
                    icon: const Icon(Icons.send_rounded, color: Colors.black),
                    style: IconButton.styleFrom(backgroundColor: const Color(0xFF00E676)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
