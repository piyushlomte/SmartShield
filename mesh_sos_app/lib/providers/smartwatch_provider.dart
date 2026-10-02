import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/smartwatch_service.dart';

class SmartwatchProvider with ChangeNotifier {
  final SmartwatchService _service = SmartwatchService();

  SmartwatchConnectionState _state = SmartwatchConnectionState.disconnected;
  SmartwatchConnectionState get state => _state;
  bool get isConnected => _state == SmartwatchConnectionState.connected;
  bool get isScanning => _state == SmartwatchConnectionState.scanning;

  SmartwatchTelemetry _telemetry = SmartwatchTelemetry(timestamp: DateTime.now());
  SmartwatchTelemetry get telemetry => _telemetry;

  List<ScanResult> _discoveredDevices = [];
  List<ScanResult> get discoveredDevices => _discoveredDevices;

  String? get deviceName => _service.connectedDeviceName;
  String? get savedDeviceId => _service.savedDeviceId;
  bool get isAutoConnectEnabled => _service.isAutoConnectEnabled;

  StreamSubscription? _stateSub;
  StreamSubscription? _telemetrySub;
  StreamSubscription? _sosSub;

  Function(String reason)? onWatchSosTriggered;

  SmartwatchProvider() {
    _init();
  }

  Future<void> _init() async {
    await _service.init();
    _state = _service.state;
    _telemetry = _service.lastTelemetry;

    _stateSub = _service.stateStream.listen((newState) {
      _state = newState;
      notifyListeners();
    });

    _telemetrySub = _service.telemetryStream.listen((newTelemetry) {
      _telemetry = newTelemetry;
      notifyListeners();
    });

    _sosSub = _service.sosTriggerStream.listen((reason) {
      if (onWatchSosTriggered != null) {
        onWatchSosTriggered!(reason);
      }
      notifyListeners();
    });

    notifyListeners();
  }

  Future<void> scanForWatches() async {
    _discoveredDevices = [];
    notifyListeners();
    _discoveredDevices = await _service.scanForSmartwatches();
    notifyListeners();
  }

  Future<bool> connectDevice(BluetoothDevice device) async {
    final success = await _service.connectToWatch(device);
    notifyListeners();
    return success;
  }

  Future<void> setAutoConnect(bool enabled) async {
    await _service.setAutoConnect(enabled);
    notifyListeners();
  }

  Future<void> forgetDevice() async {
    await _service.forgetDevice();
    _discoveredDevices = [];
    notifyListeners();
  }

  Future<void> sendHapticTestPulse() async {
    await _service.sendHapticAlert(intensity: 3, patternCode: 1);
  }

  void simulateWatchSos() {
    _service.simulateTelemetry(hr: 135, steps: 5120, bat: 85, fall: true);
    if (onWatchSosTriggered != null) {
      onWatchSosTriggered!('SMARTWATCH_SIMULATED_SOS');
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _telemetrySub?.cancel();
    _sosSub?.cancel();
    super.dispose();
  }
}
