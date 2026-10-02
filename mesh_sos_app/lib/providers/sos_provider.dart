import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/sos_alert.dart';
import '../models/mesh_packet.dart';
import '../models/incident_record.dart';
import '../services/ble_service.dart';
import '../services/location_service.dart';
import '../services/alert_service.dart';
import '../services/notification_service.dart';
import '../services/incident_journal_service.dart';

class SosProvider with ChangeNotifier {
  final BleService _bleService;
  final LocationService _locationService;
  final AlertService _alertService;

  bool _isSelfSosActive = false;
  bool _isSilentSos = false;
  bool _isDuressCancel = false;
  LifecycleState _lifecycleState = LifecycleState.normal;
  int _riskScore = 0;
  int _confidenceScore = 90;
  int _signalAnomalyScore = 0;
  int _timeToReserveMins = 720;
  int _rescueLockToken = 0;
  int _retryCount = 0;
  int _localNodeId = 0;
  DistressCategory _selectedCategory = DistressCategory.general;
  String _customDistressNote = '';
  final List<SosAlert> _alertHistory = [];
  final List<LatLng> _breadcrumbs = [];

  bool get isSelfSosActive => _isSelfSosActive;
  bool get isSilentSos => _isSilentSos;
  bool get isDuressCancel => _isDuressCancel;
  LifecycleState get lifecycleState => _lifecycleState;
  int get riskScore => _riskScore;
  int get confidenceScore => _confidenceScore;
  int get signalAnomalyScore => _signalAnomalyScore;
  int get timeToReserveMins => _timeToReserveMins;
  int get rescueLockToken => _rescueLockToken;
  int get retryCount => _retryCount;
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

  Future<bool> triggerSos({bool silent = false, String? customReason}) async {
    _isSelfSosActive = true;
    _isSilentSos = silent;
    _isDuressCancel = false;
    _lifecycleState = LifecycleState.sosGenerated;
    _riskScore = 88;
    _confidenceScore = 95;
    _retryCount = 0;

    final pos = _locationService.currentPosition;
    final note = customReason ?? (_customDistressNote.isEmpty ? 'Assistance required!' : _customDistressNote);
    String fullMsg = '${_selectedCategory.title}: $note';

    if (pos != null) {
      _breadcrumbs.add(LatLng(pos.latitude, pos.longitude));
    }

    final lm = pos != null
        ? {'area': _locationService.currentAreaName, 'near': _locationService.currentNearPlace}
        : {'area': '', 'near': ''};

    final command = {
      "cmd": "SOS",
      "text": fullMsg,
      "silent": silent,
      "lat": pos?.latitude ?? 0.0,
      "lon": pos?.longitude ?? 0.0,
      "area": lm['area'] ?? '',
      "near": lm['near'] ?? '',
    };

    bool sent = await _bleService.sendCommand(command);

    if (pos != null) {
      await _bleService.sendCommand({
        "cmd": "PHONE_GPS",
        "lat": pos.latitude,
        "lon": pos.longitude,
        "area": lm['area'] ?? '',
        "near": lm['near'] ?? '',
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

    IncidentJournalService.instance.logEvent(
      IncidentRecord(
        id: 'SOS_${DateTime.now().millisecondsSinceEpoch}',
        eventType: IncidentEventType.sosBroadcasted,
        senderId: 0,
        latitude: pos?.latitude ?? 0.0,
        longitude: pos?.longitude ?? 0.0,
        gpsSource: pos != null ? GpsSource.phone : GpsSource.none,
        riskScore: _riskScore,
        confidenceScore: _confidenceScore,
        signalAnomalyScore: _signalAnomalyScore,
        timeToReserveMins: _timeToReserveMins,
        details: fullMsg,
      ),
    );

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

      IncidentJournalService.instance.logEvent(
        IncidentRecord(
          id: 'RESP_${DateTime.now().millisecondsSinceEpoch}',
          eventType: IncidentEventType.rescueAccepted,
          senderId: 0,
          latitude: _locationService.currentPosition?.latitude ?? 0.0,
          longitude: _locationService.currentPosition?.longitude ?? 0.0,
          gpsSource: GpsSource.phone,
          riskScore: 30,
          confidenceScore: 98,
          rescueLockToken: targetNodeId,
          details: 'Accepted distress & locked claim for Node 0x${targetNodeId.toRadixString(16).toUpperCase()}: $responseText',
        ),
      );

      notifyListeners();
    }
    return sent;
  }

  Future<void> cancelSos({bool isDuress = false}) async {
    _isSelfSosActive = false;
    _isSilentSos = false;
    _isDuressCancel = isDuress;
    _lifecycleState = isDuress ? LifecycleState.silentCancel : LifecycleState.resolved;
    _riskScore = isDuress ? 35 : 0;
    _retryCount = 0;

    await _bleService.sendCommand({
      "cmd": "CANCEL_SOS",
      "duress": isDuress,
    });
    _alertService.dismissEmergency();

    IncidentJournalService.instance.logEvent(
      IncidentRecord(
        id: '${isDuress ? "DURESS" : "RESOLVED"}_${DateTime.now().millisecondsSinceEpoch}',
        eventType: isDuress ? IncidentEventType.silentCancelDuress : IncidentEventType.sosResolved,
        senderId: 0,
        latitude: _locationService.currentPosition?.latitude ?? 0.0,
        longitude: _locationService.currentPosition?.longitude ?? 0.0,
        gpsSource: GpsSource.phone,
        riskScore: _riskScore,
        confidenceScore: 100,
        details: isDuress
            ? 'Duress Silent-Cancel executed (OLED appears safe, held at LOW priority for rescue).'
            : 'SOS marked resolved / user safe.',
      ),
    );

    notifyListeners();
  }

  Future<void> sendDeadManConfig(bool enabled, int intervalMins) async {
    await _bleService.sendCommand({
      "cmd": "DEAD_MAN_CONFIG",
      "enabled": enabled,
      "interval_sec": intervalMins * 60,
    });
  }

  Future<void> sendCheckInAck() async {
    await _bleService.sendCommand({"cmd": "CHECKIN_ACK"});
  }

  void _handleIncomingPacket(MeshPacket pkt) {
    if (pkt.signalAnomalyScore > 0) {
      _signalAnomalyScore = pkt.signalAnomalyScore;
    }
    if (pkt.timeToReserveMins > 0) {
      _timeToReserveMins = pkt.timeToReserveMins;
    }

    if (pkt.type == PacketType.health || pkt.type == PacketType.sosTriggered) {
      if (pkt.senderId != 0) {
        _localNodeId = pkt.senderId;
      }
    }

    if (pkt.type == PacketType.sosTriggered) {
      _isSelfSosActive = true;
      _riskScore = pkt.riskScore > 0 ? pkt.riskScore : 85;
      _confidenceScore = pkt.confidenceScore > 0 ? pkt.confidenceScore : 90;
      _lifecycleState = pkt.lifecycleState;

      final alertText = pkt.payload.isEmpty ? '🚨 Emergency SOS Active (Hardware Button Triggered)' : pkt.payload;
      
      final selfAlert = SosAlert(
        id: 'TRIG_${DateTime.now().millisecondsSinceEpoch}',
        senderId: pkt.senderId,
        senderName: 'You (Hardware Button Triggered)',
        latitude: pkt.latitude,
        longitude: pkt.longitude,
        gpsSource: pkt.gpsSource,
        message: alertText,
        category: DistressCategory.general,
        isSelf: true,
      );

      IncidentJournalService.instance.logEvent(
        IncidentRecord(
          id: 'TRIG_${DateTime.now().millisecondsSinceEpoch}',
          eventType: IncidentEventType.sosTriggered,
          senderId: pkt.senderId,
          latitude: pkt.latitude,
          longitude: pkt.longitude,
          gpsSource: pkt.gpsSource,
          riskScore: _riskScore,
          confidenceScore: _confidenceScore,
          signalAnomalyScore: _signalAnomalyScore,
          timeToReserveMins: _timeToReserveMins,
          details: alertText,
        ),
      );

      notifyListeners();
    } else if (pkt.type == PacketType.sos || pkt.type == PacketType.silentSos) {
      // STRICT FILTER: If this SOS packet is from my own local node, IGNORE it (Do not alert self!)
      if (_localNodeId != 0 && pkt.senderId == _localNodeId) {
        debugPrint('[SOS FILTER] Ignored self-originated SOS packet from node 0x${pkt.senderId.toRadixString(16)}');
        return;
      }
      if (_isSelfSosActive && (pkt.senderId == _localNodeId || pkt.senderId == 0)) {
        debugPrint('[SOS FILTER] Ignored self SOS loopback');
        return;
      }
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

      _riskScore = pkt.riskScore > 0 ? pkt.riskScore : 90;
      _confidenceScore = pkt.confidenceScore > 0 ? pkt.confidenceScore : 92;
      _lifecycleState = pkt.lifecycleState;

      if (pkt.latitude != 0.0 && pkt.longitude != 0.0) {
        _breadcrumbs.add(LatLng(pkt.latitude, pkt.longitude));
      }

      bool exists = _alertHistory.any((a) =>
          a.senderId == pkt.senderId &&
          a.message == pkt.payload &&
          DateTime.now().difference(a.timestamp).inSeconds < 15);

      if (!exists) {
        _alertHistory.insert(0, alert);

        NotificationService().showSosNotification(
          senderId: pkt.senderId,
          lat: pkt.latitude,
          lon: pkt.longitude,
          text: pkt.payload.isEmpty ? '🚨 Emergency SOS from Node 0x${pkt.senderId.toRadixString(16).toUpperCase()}' : pkt.payload,
        );

        IncidentJournalService.instance.logEvent(
          IncidentRecord(
            id: alert.id,
            eventType: IncidentEventType.sosBroadcasted,
            senderId: pkt.senderId,
            latitude: pkt.latitude,
            longitude: pkt.longitude,
            gpsSource: pkt.gpsSource,
            riskScore: _riskScore,
            confidenceScore: _confidenceScore,
            signalAnomalyScore: _signalAnomalyScore,
            timeToReserveMins: _timeToReserveMins,
            rssi: pkt.rssi,
            snr: pkt.snr,
            batteryPercent: pkt.batteryPercent,
            details: pkt.payload,
          ),
        );
      }

      _alertService.triggerEmergencyAlert(alert);
      notifyListeners();
    } else if (pkt.type == PacketType.sosResponse || pkt.type == PacketType.rescueLock) {
      _isSelfSosActive = false;
      _lifecycleState = LifecycleState.rescueAccepted;
      _riskScore = 25;
      _rescueLockToken = pkt.rescueLockToken;
      final responderName = 'Node 0x${pkt.senderId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
      _alertService.updateEmergencyResponse(responderName, pkt.payload);

      NotificationService().showRescueAcknowledgedNotification(
        responderId: pkt.senderId,
        responderName: responderName,
        message: pkt.payload.isEmpty ? 'Rescue help is on the way (Claim Locked)!' : pkt.payload,
        lat: pkt.latitude,
        lon: pkt.longitude,
      );

      IncidentJournalService.instance.logEvent(
        IncidentRecord(
          id: 'ACK_${DateTime.now().millisecondsSinceEpoch}',
          eventType: IncidentEventType.rescueAccepted,
          senderId: pkt.senderId,
          latitude: pkt.latitude,
          longitude: pkt.longitude,
          gpsSource: pkt.gpsSource,
          riskScore: 25,
          confidenceScore: 98,
          rescueLockToken: _rescueLockToken,
          rssi: pkt.rssi,
          snr: pkt.snr,
          details: 'Rescue Accepted (Claim Locked by 0x${pkt.senderId.toRadixString(16).toUpperCase()}): ${pkt.payload}',
        ),
      );

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
    } else if (pkt.type == PacketType.ack) {
      if (_isSelfSosActive) {
        _lifecycleState = LifecycleState.sosReceived;
        _confidenceScore = 98;
        IncidentJournalService.instance.logEvent(
          IncidentRecord(
            id: 'MAC_ACK_${DateTime.now().millisecondsSinceEpoch}',
            eventType: IncidentEventType.ackReceived,
            senderId: pkt.senderId,
            latitude: 0.0,
            longitude: 0.0,
            gpsSource: GpsSource.none,
            riskScore: _riskScore,
            confidenceScore: 98,
            rssi: pkt.rssi,
            snr: pkt.snr,
            details: 'Delivery ACK confirmed by peer node.',
          ),
        );
        notifyListeners();
      }
    } else if (pkt.type == PacketType.sosCancel || pkt.type == PacketType.silentCancel) {
      bool isDuress = (pkt.type == PacketType.silentCancel);
      _lifecycleState = isDuress ? LifecycleState.silentCancel : LifecycleState.resolved;
      _riskScore = isDuress ? 35 : 0;
      if (_alertService.activeEmergency?.senderId == pkt.senderId) {
        _alertService.dismissEmergency();
      }
      for (int i = 0; i < _alertHistory.length; i++) {
        if (_alertHistory[i].senderId == pkt.senderId) {
          _alertHistory[i] = _alertHistory[i].copyWith(isResolved: true);
        }
      }
      notifyListeners();
    } else if (pkt.type == PacketType.health) {
      if (pkt.riskScore > 0) _riskScore = pkt.riskScore;
      if (pkt.confidenceScore > 0) _confidenceScore = pkt.confidenceScore;
      if (pkt.signalAnomalyScore > 0) _signalAnomalyScore = pkt.signalAnomalyScore;
      if (pkt.timeToReserveMins > 0) _timeToReserveMins = pkt.timeToReserveMins;
      _lifecycleState = pkt.lifecycleState;
      notifyListeners();
    }
  }
}
