import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SmartwatchConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  error,
}

class SmartwatchTelemetry {
  final int heartRate;
  final int stepCount;
  final int batteryPercent;
  final bool fallDetected;
  final bool sosTriggered;
  final double? latitude;
  final double? longitude;
  final DateTime timestamp;

  const SmartwatchTelemetry({
    this.heartRate = 0,
    this.stepCount = 0,
    this.batteryPercent = 100,
    this.fallDetected = false,
    this.sosTriggered = false,
    this.latitude,
    this.longitude,
    required this.timestamp,
  });

  SmartwatchTelemetry copyWith({
    int? heartRate,
    int? stepCount,
    int? batteryPercent,
    bool? fallDetected,
    bool? sosTriggered,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
  }) {
    return SmartwatchTelemetry(
      heartRate: heartRate ?? this.heartRate,
      stepCount: stepCount ?? this.stepCount,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      fallDetected: fallDetected ?? this.fallDetected,
      sosTriggered: sosTriggered ?? this.sosTriggered,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

class SmartwatchService {
  static final SmartwatchService _instance = SmartwatchService._internal();
  factory SmartwatchService() => _instance;
  SmartwatchService._internal();

  static const String _prefSavedWatchId = 'smartwatch_saved_device_id';
  static const String _prefSavedWatchName = 'smartwatch_saved_device_name';
  static const String _prefAutoConnectEnabled = 'smartwatch_auto_connect_enabled';

  // Standard BLE GATT UUIDs for Wearables & Smartwatches
  static final Guid heartRateServiceUuid = Guid('0000180d-0000-1000-8000-00805f9b34fb');
  static final Guid heartRateCharUuid = Guid('00002a37-0000-1000-8000-00805f9b34fb');
  static final Guid batteryServiceUuid = Guid('0000180f-0000-1000-8000-00805f9b34fb');
  static final Guid batteryCharUuid = Guid('00002a19-0000-1000-8000-00805f9b34fb');
  
  // Custom SmartShield Wearable SOS Companion GATT UUIDs
  static final Guid watchSosServiceUuid = Guid('5A530001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Guid watchSosNotifyCharUuid = Guid('5A530002-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Guid watchHapticWriteCharUuid = Guid('5A530003-B5A3-F393-E0A9-E50E24DCCA9E');

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _hapticChar;
  StreamSubscription? _scanSub;
  StreamSubscription? _stateSub;
  Timer? _autoReconnectTimer;

  final _stateController = StreamController<SmartwatchConnectionState>.broadcast();
  Stream<SmartwatchConnectionState> get stateStream => _stateController.stream;
  SmartwatchConnectionState _state = SmartwatchConnectionState.disconnected;
  SmartwatchConnectionState get state => _state;

  final _telemetryController = StreamController<SmartwatchTelemetry>.broadcast();
  Stream<SmartwatchTelemetry> get telemetryStream => _telemetryController.stream;
  SmartwatchTelemetry _lastTelemetry = SmartwatchTelemetry(timestamp: DateTime.now());
  SmartwatchTelemetry get lastTelemetry => _lastTelemetry;

  final _sosTriggerController = StreamController<String>.broadcast();
  Stream<String> get sosTriggerStream => _sosTriggerController.stream;

  String? _savedDeviceId;
  String? _savedDeviceName;
  bool _autoConnectEnabled = true;

  String? get connectedDeviceName => _connectedDevice?.platformName.isNotEmpty == true 
      ? _connectedDevice!.platformName 
      : _savedDeviceName;
  String? get savedDeviceId => _savedDeviceId;
  bool get isAutoConnectEnabled => _autoConnectEnabled;

  /// Initialize service and attempt auto-connection if previously authorized
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _savedDeviceId = prefs.getString(_prefSavedWatchId);
    _savedDeviceName = prefs.getString(_prefSavedWatchName);
    _autoConnectEnabled = prefs.getBool(_prefAutoConnectEnabled) ?? true;

    if (_savedDeviceId != null && _autoConnectEnabled) {
      debugPrint('[Smartwatch] Found saved watch: $_savedDeviceName ($_savedDeviceId). Initiating auto-reconnect...');
      _startAutoReconnectLoop();
    }
  }

  /// Request 1-time Bluetooth & Location Permissions
  Future<bool> requestPermissions() async {
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final allGranted = statuses.values.every((s) => s.isGranted || s.isLimited);
      return allGranted;
    } catch (e) {
      debugPrint('[Smartwatch] Error requesting permissions: $e');
      return false;
    }
  }

  /// Set Auto-Connect preference
  Future<void> setAutoConnect(bool enabled) async {
    _autoConnectEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoConnectEnabled, enabled);
    if (enabled && _connectedDevice == null && _savedDeviceId != null) {
      _startAutoReconnectLoop();
    } else if (!enabled) {
      _autoReconnectTimer?.cancel();
    }
  }

  /// Start scanning for Smartwatches & Wearables
  Future<List<ScanResult>> scanForSmartwatches({Duration timeout = const Duration(seconds: 8)}) async {
    final granted = await requestPermissions();
    if (!granted) {
      debugPrint('[Smartwatch] Bluetooth permissions denied.');
      return [];
    }

    _updateState(SmartwatchConnectionState.scanning);
    final List<ScanResult> results = [];

    try {
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );

      _scanSub?.cancel();
      _scanSub = FlutterBluePlus.scanResults.listen((list) {
        for (final r in list) {
          final name = r.device.platformName.toLowerCase();
          final isWatchLikely = name.contains('watch') || 
                                name.contains('band') || 
                                name.contains('fit') || 
                                name.contains('gear') || 
                                name.contains('smart') ||
                                name.contains('sos') ||
                                r.advertisementData.serviceUuids.contains(heartRateServiceUuid) ||
                                r.advertisementData.serviceUuids.contains(watchSosServiceUuid);

          if (isWatchLikely || r.device.platformName.isNotEmpty) {
            final idx = results.indexWhere((existing) => existing.device.remoteId == r.device.remoteId);
            if (idx >= 0) {
              results[idx] = r;
            } else {
              results.add(r);
            }
          }
        }
      });

      await Future.delayed(timeout);
      await FlutterBluePlus.stopScan();
      _updateState(_connectedDevice != null ? SmartwatchConnectionState.connected : SmartwatchConnectionState.disconnected);
    } catch (e) {
      debugPrint('[Smartwatch] Scan error: $e');
      _updateState(SmartwatchConnectionState.error);
    }

    return results;
  }

  /// Connect to a specific Smartwatch and save credentials for 1-time auto-connect
  Future<bool> connectToWatch(BluetoothDevice device) async {
    try {
      _updateState(SmartwatchConnectionState.connecting);
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      await device.connect(
        timeout: const Duration(seconds: 12),
        autoConnect: false,
      );

      _connectedDevice = device;
      _savedDeviceId = device.remoteId.str;
      _savedDeviceName = device.platformName.isNotEmpty ? device.platformName : 'Smartwatch';

      // Save for 1-time auto connection
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSavedWatchId, _savedDeviceId!);
      await prefs.setString(_prefSavedWatchName, _savedDeviceName!);

      _monitorConnectionState(device);
      await _discoverAndSubscribeServices(device);

      _updateState(SmartwatchConnectionState.connected);
      debugPrint('[Smartwatch] Successfully connected and paired to: $_savedDeviceName');
      return true;
    } catch (e) {
      debugPrint('[Smartwatch] Connection failed: $e');
      _updateState(SmartwatchConnectionState.error);
      _startAutoReconnectLoop();
      return false;
    }
  }

  /// Monitor active connection state and auto-reconnect if link drops
  void _monitorConnectionState(BluetoothDevice device) {
    _stateSub?.cancel();
    _stateSub = device.connectionState.listen((s) {
      if (s == BluetoothConnectionState.connected) {
        _updateState(SmartwatchConnectionState.connected);
      } else if (s == BluetoothConnectionState.disconnected) {
        _updateState(SmartwatchConnectionState.disconnected);
        _connectedDevice = null;
        _hapticChar = null;
        if (_autoConnectEnabled && _savedDeviceId != null) {
          _startAutoReconnectLoop();
        }
      }
    });
  }

  /// Background Auto-Reconnect Loop (Uses saved 1-time MAC/UUID)
  void _startAutoReconnectLoop() {
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      if (_connectedDevice != null || !_autoConnectEnabled || _savedDeviceId == null) {
        timer.cancel();
        return;
      }

      debugPrint('[Smartwatch Auto-Connect] Looking for saved watch: $_savedDeviceId');
      try {
        final targetDevice = BluetoothDevice.fromId(_savedDeviceId!);
        await targetDevice.connect(
          timeout: const Duration(seconds: 5),
          autoConnect: false,
        );
        _connectedDevice = targetDevice;
        _monitorConnectionState(targetDevice);
        await _discoverAndSubscribeServices(targetDevice);
        _updateState(SmartwatchConnectionState.connected);
        debugPrint('[Smartwatch Auto-Connect] Reconnected successfully to $_savedDeviceName!');
        timer.cancel();
      } catch (e) {
        debugPrint('[Smartwatch Auto-Connect] Device not in range yet...');
      }
    });
  }

  /// Discover GATT services for Biometrics, SOS triggers & Haptic vibration
  Future<void> _discoverAndSubscribeServices(BluetoothDevice device) async {
    try {
      final services = await device.discoverServices();
      for (final service in services) {
        // 1. Standard Heart Rate Service
        if (service.uuid == heartRateServiceUuid) {
          for (final c in service.characteristics) {
            if (c.uuid == heartRateCharUuid) {
              await c.setNotifyValue(true);
              c.lastValueStream.listen((data) {
                if (data.isNotEmpty) {
                  final bpm = _parseHeartRate(data);
                  _lastTelemetry = _lastTelemetry.copyWith(
                    heartRate: bpm,
                    timestamp: DateTime.now(),
                  );
                  _telemetryController.add(_lastTelemetry);
                }
              });
            }
          }
        }

        // 2. Standard Battery Service
        if (service.uuid == batteryServiceUuid) {
          for (final c in service.characteristics) {
            if (c.uuid == batteryCharUuid) {
              final val = await c.read();
              if (val.isNotEmpty) {
                _lastTelemetry = _lastTelemetry.copyWith(
                  batteryPercent: val[0],
                  timestamp: DateTime.now(),
                );
                _telemetryController.add(_lastTelemetry);
              }
            }
          }
        }

        // 3. SmartShield Wearable SOS & Haptic Service
        if (service.uuid == watchSosServiceUuid) {
          for (final c in service.characteristics) {
            if (c.uuid == watchSosNotifyCharUuid) {
              await c.setNotifyValue(true);
              c.lastValueStream.listen((bytes) {
                _handleWatchSosPacket(bytes);
              });
            }
            if (c.uuid == watchHapticWriteCharUuid) {
              _hapticChar = c;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[Smartwatch] Service discovery error: $e');
    }
  }

  int _parseHeartRate(List<int> data) {
    if (data.isEmpty) return 0;
    final flags = data[0];
    final is16Bit = (flags & 0x01) != 0;
    if (is16Bit && data.length >= 3) {
      return data[1] + (data[2] << 8);
    } else if (data.length >= 2) {
      return data[1];
    }
    return 0;
  }

  void _handleWatchSosPacket(List<int> bytes) {
    try {
      final jsonStr = utf8.decode(bytes);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      
      final isSos = map['sos'] == true;
      final isFall = map['fall'] == true;
      final hr = map['hr'] as int? ?? _lastTelemetry.heartRate;
      final lat = (map['lat'] as num?)?.toDouble();
      final lon = (map['lon'] as num?)?.toDouble();

      _lastTelemetry = _lastTelemetry.copyWith(
        heartRate: hr,
        sosTriggered: isSos,
        fallDetected: isFall,
        latitude: lat,
        longitude: lon,
        timestamp: DateTime.now(),
      );
      _telemetryController.add(_lastTelemetry);

      if (isSos) {
        _sosTriggerController.add('SMARTWATCH_BUTTON_SOS');
      } else if (isFall) {
        _sosTriggerController.add('SMARTWATCH_FALL_DETECTED');
      }
    } catch (e) {
      debugPrint('[Smartwatch] Error parsing watch SOS packet: $e');
    }
  }

  /// Send Emergency Rescue Haptic Vibration Pulse to Smartwatch
  Future<void> sendHapticAlert({int intensity = 3, int patternCode = 1}) async {
    if (_hapticChar == null) {
      debugPrint('[Smartwatch] Haptic characteristic not available.');
      return;
    }
    try {
      final payload = utf8.encode(jsonEncode({
        'cmd': 'HAPTIC_PULSE',
        'intensity': intensity,
        'pattern': patternCode,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
      await _hapticChar!.write(payload, withoutResponse: true);
      debugPrint('[Smartwatch] Haptic emergency buzz sent to watch.');
    } catch (e) {
      debugPrint('[Smartwatch] Failed to send haptic buzz: $e');
    }
  }

  /// Forget Saved Smartwatch (Clear 1-time auto-connect)
  Future<void> forgetDevice() async {
    _autoReconnectTimer?.cancel();
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    _savedDeviceId = null;
    _savedDeviceName = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefSavedWatchId);
    await prefs.remove(_prefSavedWatchName);
    _updateState(SmartwatchConnectionState.disconnected);
  }

  /// Simulate Live Telemetry for Testing / Demos
  void simulateTelemetry({int hr = 78, int steps = 4250, int bat = 89, bool fall = false}) {
    _lastTelemetry = _lastTelemetry.copyWith(
      heartRate: hr,
      stepCount: steps,
      batteryPercent: bat,
      fallDetected: fall,
      timestamp: DateTime.now(),
    );
    _telemetryController.add(_lastTelemetry);
  }

  void _updateState(SmartwatchConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _autoReconnectTimer?.cancel();
    _scanSub?.cancel();
    _stateSub?.cancel();
    _stateController.close();
    _telemetryController.close();
    _sosTriggerController.close();
  }
}
