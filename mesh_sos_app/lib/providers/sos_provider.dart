import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/sos_alert.dart';
import '../models/mesh_packet.dart';
import '../services/ble_service.dart';
import '../services/location_service.dart';
import '../services/alert_service.dart';

class SosProvider with ChangeNotifier {
  final BleService _bleService;
  final LocationService _locationService;
  final AlertService _alertService;

  bool _isSelfSosActive = false;
  bool _isSilentSos = false;
  DistressCategory _selectedCategory = DistressCategory.general;
  String _customDistressNote = '';
  final List<SosAlert> _alertHistory = [];
  final List<LatLng> _breadcrumbs = [];

  bool get isSelfSosActive => _isSelfSosActive;
  bool get isSilentSos => _isSilentSos;
  DistressCategory get selectedCategory => _selectedCategory;
  String get customDistressNote => _customDistressNote;
  List<SosAlert> get alertHistory => _alertHistory;
  List<LatLng> get breadcrumbs => _breadcrumbs;

  SosProvider(this._bleService, this._locationService, this._alertService) {
    _bleService.packetStream.listen(_handleIncomingPacket);
  }

  void setCategory(DistressCategory category) {
    _selectedCategory = category;
    notifyListeners();
  }

  void setDistressNote(String note) {
    _customDistressNote = note;
    notifyListeners();
  }

  Future<bool> triggerSos({bool silent = false}) async {
    _isSelfSosActive = true;
    _isSilentSos = silent;

    final pos = _locationService.currentPosition;
    String fullMsg = '${_selectedCategory.title}: ${_customDistressNote.isEmpty ? 'Assistance required!' : _customDistressNote}';

    if (pos != null) {
      _breadcrumbs.add(LatLng(pos.latitude, pos.longitude));
    }

    final command = {
      "cmd": "SOS",
      "text": fullMsg,
      "silent": silent,
      "lat": pos?.latitude ?? 0.0,
      "lon": pos?.longitude ?? 0.0,
    };

    bool sent = await _bleService.sendCommand(command);

    // Also push phone GPS fallback coordinates over BLE
    if (pos != null) {
      await _bleService.sendCommand({
        "cmd": "PHONE_GPS",
        "lat": pos.latitude,
        "lon": pos.longitude,
      });
    }

    final selfAlert = SosAlert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: 0,
      senderName: 'You (This Node)',
      latitude: pos?.latitude ?? 0.0,
      longitude: pos?.longitude ?? 0.0,
      gpsSource: pos != null ? GpsSource.phone : GpsSource.none,
      message: fullMsg,
      category: _selectedCategory,
      isSelf: true,
    );

    _alertHistory.insert(0, selfAlert);
    if (!silent) {
      _alertService.triggerEmergencyAlert(selfAlert);
    }

    notifyListeners();
    return sent;
  }

  Future<bool> sendRescueResponse(int targetNodeId, String responseText) async {
    final command = {
      "cmd": "SOS_RESPONSE",
      "target": targetNodeId,
      "text": responseText,
    };

    bool sent = await _bleService.sendCommand(command);
    if (sent) {
      _alertService.updateEmergencyResponse('You (This Node)', responseText);
      notifyListeners();
    }
    return sent;
  }

  Future<void> cancelSos() async {
    _isSelfSosActive = false;
    _isSilentSos = false;
    await _bleService.sendCommand({"cmd": "CANCEL_SOS"});
    _alertService.dismissEmergency();
    notifyListeners();
  }

  void _handleIncomingPacket(MeshPacket pkt) {
    if (pkt.type == PacketType.sos || pkt.type == PacketType.silentSos) {
      final alert = SosAlert(
        id: '${pkt.senderId}_${pkt.packetId}_${pkt.timestamp.millisecondsSinceEpoch}',
        senderId: pkt.senderId,
        senderName: 'Node 0x${pkt.senderId.toRadixString(16).padLeft(4, '0').toUpperCase()}',
        latitude: pkt.latitude,
        longitude: pkt.longitude,
        gpsSource: pkt.gpsSource,
        message: pkt.payload,
        hopCount: pkt.hopCount,
        rssi: pkt.rssi,
        snr: pkt.snr,
        timestamp: pkt.timestamp,
        isSelf: false,
      );

      if (pkt.latitude != 0.0 && pkt.longitude != 0.0) {
        _breadcrumbs.add(LatLng(pkt.latitude, pkt.longitude));
      }

      // Deduplicate alert history if same alert arrived in last 15s
      bool exists = _alertHistory.any((a) =>
          a.senderId == pkt.senderId &&
          a.message == pkt.payload &&
          DateTime.now().difference(a.timestamp).inSeconds < 15);

      if (!exists) {
        _alertHistory.insert(0, alert);
      }

      _alertService.triggerEmergencyAlert(alert);
      notifyListeners();
    } else if (pkt.type == PacketType.sosResponse) {
      // 2-Way Rescue Response received from another node
      final responderName = 'Node 0x${pkt.senderId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
      _alertService.updateEmergencyResponse(responderName, pkt.payload);

      for (int i = 0; i < _alertHistory.length; i++) {
        if (_alertHistory[i].isSelf || _alertHistory[i].senderId == pkt.recipientId) {
          _alertHistory[i] = _alertHistory[i].copyWith(
            responderName: responderName,
            responseMessage: pkt.payload,
            responseTime: pkt.timestamp,
          );
        }
      }
      notifyListeners();
    } else if (pkt.type == PacketType.sosCancel) {
      // SOS Cancelled / Resolved by sender node
      if (_alertService.activeEmergency?.senderId == pkt.senderId) {
        _alertService.dismissEmergency();
      }
      for (int i = 0; i < _alertHistory.length; i++) {
        if (_alertHistory[i].senderId == pkt.senderId) {
          _alertHistory[i] = _alertHistory[i].copyWith(isResolved: true);
        }
      }
      notifyListeners();
    }
  }
}
