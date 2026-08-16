import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../models/mesh_packet.dart';
import '../models/chat_message.dart';
import '../models/mesh_node.dart';
import '../services/ble_service.dart';
import '../services/db_service.dart';

class MeshProvider with ChangeNotifier {
  final BleService _bleService;
  final DbService _dbService = DbService.instance;

  final Map<int, MeshNode> _nodes = {};
  final List<ChatMessage> _messages = [];
  String _activeChannel = 'Public';
  int _localNodeId = 0x0001;
  int _localBattery = 100;

  void updateLocalNodeInfo(int id, int battery) {
    _localNodeId = id;
    _localBattery = battery;
    notifyListeners();
  }

  Map<int, MeshNode> get nodes => _nodes;
  List<ChatMessage> get messages => _messages.where((m) => m.channel == _activeChannel).toList();
  String get activeChannel => _activeChannel;
  int get localNodeId => _localNodeId;
  int get localBattery => _localBattery;

  MeshProvider(this._bleService) {
    _bleService.packetStream.listen(_handleIncomingPacket);
    _loadStoredMessages();
  }

  Future<void> _loadStoredMessages() async {
    final list = await _dbService.getMessages(channel: _activeChannel);
    _messages.clear();
    _messages.addAll(list);
    notifyListeners();
  }

  void setActiveChannel(String channel) {
    _activeChannel = channel;
    _loadStoredMessages();
  }

  Future<void> sendMessage(String text, {int recipientId = 65535}) async {
    if (text.trim().isEmpty) return;

    final msgId = const Uuid().v4();
    final chatMsg = ChatMessage(
      id: msgId,
      senderId: _localNodeId,
      recipientId: recipientId,
      text: text,
      timestamp: DateTime.now(),
      isOutgoing: true,
      status: MessageStatus.sending,
      channel: _activeChannel,
    );

    _messages.add(chatMsg);
    await _dbService.insertMessage(chatMsg);
    notifyListeners();

    // Send over BLE to ESP32 node
    final command = {
      "cmd": "CHAT",
      "dst": recipientId,
      "msg": text,
    };

    bool sent = await _bleService.sendCommand(command);
    if (sent) {
      final updated = chatMsg.copyWith(status: MessageStatus.relayed);
      int idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx != -1) {
        _messages[idx] = updated;
        await _dbService.updateMessageStatus(msgId, MessageStatus.relayed);
        notifyListeners();
      }
    }
  }

  void _handleIncomingPacket(MeshPacket pkt) async {
    // 0. Handle Local Node Status sync from paired Heltec
    if (pkt.type == PacketType.health && pkt.senderId != 0) {
      _localNodeId = pkt.senderId;
      _localBattery = pkt.batteryPercent;
      notifyListeners();
      return;
    }

    // 1. Update or create sender Node in directory
    if (pkt.senderId != 0 && pkt.senderId != _localNodeId) {
      final existing = _nodes[pkt.senderId];
      _nodes[pkt.senderId] = (existing ?? MeshNode(nodeId: pkt.senderId, name: 'Node ${pkt.senderId.toRadixString(16).toUpperCase()}')).copyWith(
        latitude: pkt.latitude != 0.0 ? pkt.latitude : existing?.latitude,
        longitude: pkt.longitude != 0.0 ? pkt.longitude : existing?.longitude,
        gpsSource: pkt.gpsSource,
        batteryPercent: pkt.batteryPercent,
        rssi: pkt.rssi,
        snr: pkt.snr,
        hopCount: pkt.hopCount,
        lastSeen: DateTime.now(),
        isSosActive: pkt.type == PacketType.sos || pkt.type == PacketType.silentSos,
      );
    }

    // 2. Handle Chat Messages (Prevent duplicates & self-echoes)
    if (pkt.type == PacketType.chat && pkt.payload.trim().isNotEmpty) {
      // Ignore if packet originated from our local node
      if (pkt.senderId == _localNodeId && _localNodeId != 0) {
        return;
      }

      // Check if message is already recorded (Deduplication within 20s window)
      bool isDuplicate = _messages.any((m) =>
          m.senderId == pkt.senderId &&
          m.text.trim() == pkt.payload.trim() &&
          m.timestamp.difference(pkt.timestamp).inSeconds.abs() < 20);

      if (!isDuplicate) {
        final newMsg = ChatMessage(
          id: const Uuid().v4(),
          senderId: pkt.senderId,
          recipientId: pkt.recipientId,
          text: pkt.payload,
          timestamp: pkt.timestamp,
          isOutgoing: false,
          status: MessageStatus.delivered,
          rssi: pkt.rssi,
          snr: pkt.snr,
          channel: _activeChannel, // Map to active conversation
        );

        _messages.add(newMsg);
        await _dbService.insertMessage(newMsg);
      }
    }

    // 3. Handle Delivery ACK / Confirmation
    if (pkt.type == PacketType.ack) {
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].isOutgoing && _messages[i].status == MessageStatus.sending) {
          _messages[i] = _messages[i].copyWith(status: MessageStatus.relayed);
          await _dbService.updateMessageStatus(_messages[i].id, MessageStatus.relayed);
        }
      }
    }

    notifyListeners();
  }
}
