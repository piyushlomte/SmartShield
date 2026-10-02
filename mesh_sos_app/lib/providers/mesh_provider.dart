import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:latlong2/latlong.dart';
import '../models/mesh_packet.dart';
import '../models/chat_message.dart';
import '../models/mesh_node.dart';
import '../services/ble_service.dart';
import '../services/location_service.dart';
import '../services/db_service.dart';
import '../services/notification_service.dart';

class MeshProvider with ChangeNotifier {
  final BleService _bleService;
  final LocationService _locationService;
  final DbService _dbService = DbService.instance;

  final Map<int, MeshNode> _nodes = {};
  final List<ChatMessage> _messages = [];
  String _activeChannel = 'Public';
  int _localNodeId = 0x0001;
  int _localBattery = 100;
  String _searchQuery = '';

  void updateLocalNodeInfo(int id, int battery) {
    _localNodeId = id;
    _localBattery = battery;
    notifyListeners();
  }

  Map<int, MeshNode> get nodes => _nodes;
  String get activeChannel => _activeChannel;
  int get localNodeId => _localNodeId;
  String get localHexId => '0x${_localNodeId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
  int get localBattery => _localBattery;
  String get searchQuery => _searchQuery;

  List<ChatMessage> get messages {
    var list = _messages.where((m) {
      if (_activeChannel == 'Public') {
        return m.channel == 'Public' || m.recipientId == 65535;
      } else if (_activeChannel == 'Direct') {
        return m.channel == 'Direct' || m.recipientId != 65535;
      } else if (_activeChannel.startsWith('DM:')) {
        int targetId = int.tryParse(_activeChannel.substring(3)) ?? 0;
        return (m.senderId == targetId && m.recipientId == _localNodeId) ||
               (m.senderId == _localNodeId && m.recipientId == targetId);
      } else {
        return m.channel == _activeChannel || m.recipientId == 65535;
      }
    }).toList();

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((m) => m.text.toLowerCase().contains(q) || m.hexSenderId.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  MeshProvider(this._bleService, this._locationService) {
    _bleService.packetStream.listen(_handleIncomingPacket);
    _loadStoredMessages();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> syncPhoneGpsToNode() async {
    final pos = _locationService.currentPosition;
    if (pos != null && _bleService.isConnected) {
      final dynamicLandmark = await _locationService.fetchDynamicMapLocation(pos.latitude, pos.longitude);
      await _bleService.sendCommand({
        "cmd": "PHONE_GPS",
        "lat": pos.latitude,
        "lon": pos.longitude,
        "area": dynamicLandmark['area'] ?? '',
        "near": dynamicLandmark['near'] ?? '',
      });
      await _bleService.sendCommand({
        "cmd": "SET_LANDMARK",
        "area": dynamicLandmark['area'] ?? '',
        "near": dynamicLandmark['near'] ?? '',
      });
    }
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

  Future<void> clearCurrentChannelHistory() async {
    _messages.removeWhere((m) => m.channel == _activeChannel);
    notifyListeners();
  }

  String exportChatTranscript() {
    final buffer = StringBuffer();
    buffer.writeln('=== SMART-SHIELD MESH CHAT TRANSCRIPT ===');
    buffer.writeln('Channel: $_activeChannel');
    buffer.writeln('Export Time: ${DateTime.now().toIso8601String()}');
    buffer.writeln('------------------------------------------');
    for (var m in messages) {
      buffer.writeln('[${m.timestamp.toIso8601String()}] ${m.hexSenderId} -> ${m.hexRecipientId}: ${m.text}');
      if (m.hasLocation) {
        buffer.writeln('  GPS: ${m.latitude}, ${m.longitude}');
      }
    }
    return buffer.toString();
  }

  Future<void> sendMessage(
    String text, {
    int recipientId = 65535,
    bool attachLocation = false,
  }) async {
    if (text.trim().isEmpty) return;

    final msgId = const Uuid().v4();
    final pos = _locationService.currentPosition;
    final double? lat = (attachLocation && pos != null) ? pos.latitude : null;
    final double? lon = (attachLocation && pos != null) ? pos.longitude : null;

    final chatMsg = ChatMessage(
      id: msgId,
      senderId: _localNodeId,
      recipientId: recipientId,
      text: text,
      timestamp: DateTime.now(),
      isOutgoing: true,
      status: MessageStatus.sending,
      channel: _activeChannel,
      latitude: lat,
      longitude: lon,
    );

    _messages.add(chatMsg);
    await _dbService.insertMessage(chatMsg);
    notifyListeners();

    // Prepare BLE command payload
    final command = {
      "cmd": "CHAT",
      "dst": recipientId,
      "msg": text,
      if (lat != null && lon != null) ...{
        "lat": lat,
        "lon": lon,
      }
    };

    bool sent = await _bleService.sendCommand(command);
    final nextStatus = sent ? MessageStatus.relayed : MessageStatus.failed;
    final updated = chatMsg.copyWith(status: nextStatus);
    int idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx != -1) {
      _messages[idx] = updated;
      await _dbService.updateMessageStatus(msgId, nextStatus);
      notifyListeners();
    }
  }

  Future<void> retryMessage(String msgId) async {
    final idx = _messages.indexWhere((m) => m.id == msgId);
    if (idx == -1) return;
    final msg = _messages[idx];

    final command = {
      "cmd": "CHAT",
      "dst": msg.recipientId,
      "msg": msg.text,
      if (msg.hasLocation) ...{
        "lat": msg.latitude,
        "lon": msg.longitude,
      }
    };

    bool sent = await _bleService.sendCommand(command);
    final nextStatus = sent ? MessageStatus.relayed : MessageStatus.failed;
    _messages[idx] = msg.copyWith(status: nextStatus);
    await _dbService.updateMessageStatus(msgId, nextStatus);
    notifyListeners();
  }

  /// Interactive loopback / benchmark simulator for bench testing without 2nd radio
  void simulateIncomingMessage({
    required int fromNodeId,
    required String messageText,
    double? lat,
    double? lon,
  }) {
    final newMsg = ChatMessage(
      id: const Uuid().v4(),
      senderId: fromNodeId,
      recipientId: _localNodeId,
      text: messageText,
      timestamp: DateTime.now(),
      isOutgoing: false,
      status: MessageStatus.delivered,
      rssi: -78,
      snr: 9.5,
      channel: _activeChannel,
      latitude: lat,
      longitude: lon,
      hops: 1,
      senderName: 'Simulated Node 0x${fromNodeId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
    );

    _messages.add(newMsg);
    _dbService.insertMessage(newMsg);
    notifyListeners();

    NotificationService().showChatNotification(
      senderId: fromNodeId,
      senderName: newMsg.senderName ?? 'Node 0x${fromNodeId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
      message: messageText,
      lat: lat ?? 0.0,
      lon: lon ?? 0.0,
    );
  }

  void _handleIncomingPacket(MeshPacket pkt) async {
    // 0. Handle Local Node Status sync from paired Heltec
    if (pkt.type == PacketType.health && pkt.senderId != 0) {
      _localNodeId = pkt.senderId;
      _localBattery = pkt.batteryPercent;
      syncPhoneGpsToNode();
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

      // Check if message is already recorded (Deduplication within 4s window for identical incoming messages)
      bool isDuplicate = _messages.any((m) =>
          !m.isOutgoing &&
          m.senderId == pkt.senderId &&
          m.text.trim() == pkt.payload.trim() &&
          m.timestamp.difference(pkt.timestamp).inSeconds.abs() < 4);

      if (!isDuplicate) {
        final nodeName = _nodes[pkt.senderId]?.name ?? 'Node 0x${pkt.senderId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
        final msgChannel = (pkt.recipientId == 65535) ? 'Public' : (_activeChannel == 'Public' ? 'Direct' : _activeChannel);
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
          hops: pkt.hopCount,
          latitude: pkt.latitude != 0.0 ? pkt.latitude : null,
          longitude: pkt.longitude != 0.0 ? pkt.longitude : null,
          channel: msgChannel,
          senderName: nodeName,
        );

        _messages.add(newMsg);
        await _dbService.insertMessage(newMsg);

        // Trigger local notification with GPS location link if available
        NotificationService().showChatNotification(
          senderId: pkt.senderId,
          senderName: nodeName,
          message: pkt.payload,
          lat: pkt.latitude,
          lon: pkt.longitude,
        );
      }
    }

    // 3. Handle Delivery ACK / Confirmation
    if (pkt.type == PacketType.ack) {
      for (int i = 0; i < _messages.length; i++) {
        if (_messages[i].isOutgoing && (_messages[i].status == MessageStatus.sending || _messages[i].status == MessageStatus.relayed)) {
          _messages[i] = _messages[i].copyWith(status: MessageStatus.delivered);
          await _dbService.updateMessageStatus(_messages[i].id, MessageStatus.delivered);
        }
      }
      notifyListeners();
    }

    notifyListeners();
  }
}
