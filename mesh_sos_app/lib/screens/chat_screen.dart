import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _selectedRecipientId = 65535; // 65535 = Broadcast to all nodes

  final List<String> _quickPhrases = [
    "📍 Checked in at waypoint",
    "🔋 Battery running low",
    "🏕️ Setting up camp",
    "🛑 Hold position",
    "👍 All clear / safe",
    "📶 Signal check / Copy?",
  ];

  @override
  void dispose() {
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 60,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendCurrentMessage(MeshProvider meshProvider) {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    meshProvider.sendMessage(text, recipientId: _selectedRecipientId);
    _msgController.clear();
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meshProvider = Provider.of<MeshProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: meshProvider.activeChannel,
                dropdownColor: theme.cardColor,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                items: ['Public', 'Team Alpha', 'Base Camp'].map((ch) {
                  return DropdownMenuItem(value: ch, child: Text('Channel: #$ch'));
                }).toList(),
                onChanged: (val) {
                  if (val != null) meshProvider.setActiveChannel(val);
                },
              ),
            ),
            Text(
              _selectedRecipientId == 65535
                  ? 'Target: Broadcast (All Nodes)'
                  : 'Target: Node 0x${_selectedRecipientId.toRadixString(16).padLeft(4, '0').toUpperCase()} (Direct)',
              style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.tune),
            tooltip: 'Select Direct Message Recipient',
            onSelected: (nodeId) {
              setState(() => _selectedRecipientId = nodeId);
            },
            itemBuilder: (context) {
              return [
                const PopupMenuItem(
                  value: 65535,
                  child: Row(
                    children: [
                      Icon(Icons.podcasts, color: Color(0xFF00E676), size: 18),
                      SizedBox(width: 8),
                      Text('Broadcast (All Mesh Nodes)'),
                    ],
                  ),
                ),
                ...meshProvider.nodes.values.map((node) {
                  return PopupMenuItem(
                    value: node.nodeId,
                    child: Row(
                      children: [
                        const Icon(Icons.person_pin, color: Colors.cyanAccent, size: 18),
                        SizedBox(width: 8),
                        Text('Direct: ${node.name}'),
                      ],
                    ),
                  );
                }),
              ];
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Target recipient indicator bar if direct chat selected
          if (_selectedRecipientId != 65535)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: const Color(0xFF161B22),
              child: Row(
                children: [
                  const Icon(Icons.lock, color: Color(0xFF00E676), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Direct 2-Way to Node 0x${_selectedRecipientId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _selectedRecipientId = 65535),
                    child: const Text('Switch to Broadcast', style: TextStyle(color: Colors.blueAccent, fontSize: 11)),
                  ),
                ],
              ),
            ),

          // Quick phrase chips bar
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _quickPhrases.length,
              itemBuilder: (context, i) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(_quickPhrases[i], style: const TextStyle(fontSize: 11)),
                    backgroundColor: theme.cardColor,
                    onPressed: () {
                      meshProvider.sendMessage(_quickPhrases[i], recipientId: _selectedRecipientId);
                      _scrollToBottom();
                    },
                  ),
                );
              },
            ),
          ),

          // Message history list
          Expanded(
            child: meshProvider.messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages in #${meshProvider.activeChannel} yet.\nMessages are relayed 2-way off-grid over LoRa radio.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: meshProvider.messages.length,
                    itemBuilder: (context, i) {
                      final msg = meshProvider.messages[i];
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
                        child: MessageBubble(message: msg),
                      );
                    },
                  ),
          ),

          // Message Input Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.cardColor,
              border: const Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _selectedRecipientId == 65535
                            ? 'Type broadcast message...'
                            : 'Type direct reply to Node 0x${_selectedRecipientId.toRadixString(16).toUpperCase()}...',
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                        filled: true,
                        fillColor: const Color(0xFF0D1117),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendCurrentMessage(meshProvider),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _sendCurrentMessage(meshProvider),
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
