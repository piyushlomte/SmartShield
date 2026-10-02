import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/mesh_packet.dart';
import 'notification_service.dart';

class BleService with ChangeNotifier {
  static const String serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String rxCharUuid  = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"; // Phone -> Node
  static const String txCharUuid  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"; // Node -> Phone

  static const String _prefLastDeviceIdKey = "last_connected_ble_id";
  static const String _prefLastDeviceNameKey = "last_connected_ble_name";

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<List<int>>? _txNotifySub;
  Timer? _autoReconnectTimer;

  bool _isScanning = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isAutoConnecting = false;
  List<ScanResult> _scanResults = [];
  String _incomingBuffer = "";
  String _statusMessage = "Disconnected";

  final StreamController<MeshPacket> _packetStreamController = StreamController<MeshPacket>.broadcast();
  Stream<MeshPacket> get packetStream => _packetStreamController.stream;

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isAutoConnecting => _isAutoConnecting;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  List<ScanResult> get scanResults => _scanResults;
  String get statusMessage => _statusMessage;

  BleService() {
    _initBleState();
    _startAutoReconnectLoop();
  }

  void _initBleState() {
    FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      notifyListeners();
    });

    FlutterBluePlus.adapterState.listen((state) {
      if (state != BluetoothAdapterState.on) {
        _isConnected = false;
        _connectedDevice = null;
        _statusMessage = "Bluetooth is turned OFF";
        notifyListeners();
      } else {
        // Bluetooth turned ON -> attempt auto connect
        if (!_isConnected) {
          triggerAutoConnect();
        }
      }
    });
  }

  void _startAutoReconnectLoop() {
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!_isConnected && !_isScanning && !_isAutoConnecting) {
        triggerAutoConnect();
      }
    });
  }

  Future<bool> requestAllPermissions() async {
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
        Permission.notification,
      ].request();
      return true;
    } catch (e) {
      debugPrint('Permission request error: $e');
      return false;
    }
  }

  Future<void> triggerAutoConnect() async {
    if (_isConnected || _isScanning || _isAutoConnecting) return;
    _isAutoConnecting = true;
    _statusMessage = "Auto-connecting to Mesh device...";
    notifyListeners();

    try {
      // Scan and connect reliably (Android requires active scan to avoid Error 133)
      await startScan(isAutoScan: true);
    } catch (e) {
      debugPrint('Auto connect error: $e');
    } finally {
      _isAutoConnecting = false;
      notifyListeners();
    }
  }

  Future<void> startScan({bool isAutoScan = false}) async {
    if (_isScanning) return;

    await requestAllPermissions();

    try {
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
    } catch (_) {}

    _scanResults.clear();
    _isScanning = true;
    _statusMessage = isAutoScan ? "Searching for Heltec Mesh..." : "Scanning for devices...";
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    final lastDeviceId = prefs.getString(_prefLastDeviceIdKey);

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) async {
      results.sort((a, b) {
        String aName = (a.advertisementData.advName.isNotEmpty ? a.advertisementData.advName : a.device.platformName).toLowerCase();
        String bName = (b.advertisementData.advName.isNotEmpty ? b.advertisementData.advName : b.device.platformName).toLowerCase();
        bool aIsMesh = aName.contains('mesh') || aName.contains('heltec') || aName.contains('sos') || a.advertisementData.serviceUuids.any((u) => u.toString().toUpperCase().contains('6E40'));
        bool bIsMesh = bName.contains('mesh') || bName.contains('heltec') || bName.contains('sos') || b.advertisementData.serviceUuids.any((u) => u.toString().toUpperCase().contains('6E40'));
        if (aIsMesh && !bIsMesh) return -1;
        if (!aIsMesh && bIsMesh) return 1;
        return b.rssi.compareTo(a.rssi);
      });
      _scanResults = results;
      notifyListeners();

      // In auto scan mode, if matching device found, connect immediately
      if (isAutoScan && !_isConnected && !_isConnecting) {
        for (var result in results) {
          String name = (result.advertisementData.advName.isNotEmpty ? result.advertisementData.advName : result.device.platformName).toLowerCase();
          bool isMatch = name.contains('heltec') ||
              name.contains('mesh') ||
              name.contains('sos') ||
              (lastDeviceId != null && result.device.remoteId.str == lastDeviceId) ||
              result.advertisementData.serviceUuids.any((u) => u.toString().toUpperCase().contains('6E40'));

          if (isMatch) {
            _isConnecting = true;
            stopScan().then((_) {
              connect(result.device, isAuto: true);
            });
            break;
          }
        }
      }
    });

    try {
      if (FlutterBluePlus.isScanningNow) {
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
      }
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('BLE Scan error: $e');
      _statusMessage = "Scan error: $e";
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    _isScanning = false;
    _scanSub?.cancel();
    notifyListeners();
  }

  Future<bool> connect(BluetoothDevice device, {bool isAuto = false, int retryCount = 0}) async {
    if (_isConnected && _connectedDevice?.remoteId == device.remoteId) {
      return true;
    }
    _isConnecting = true;
    _isAutoConnecting = isAuto;

    try {
      await stopScan();
      await Future.delayed(const Duration(milliseconds: 200));

      String devName = device.platformName.isNotEmpty ? device.platformName : "Heltec Node";
      _statusMessage = "Connecting to $devName...";
      notifyListeners();

      // Monitor connection state
      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          _isConnected = true;
          _statusMessage = "Connected to $devName";
          NotificationService().showPersistentServiceNotification(
            deviceName: devName,
            status: "Online & Monitoring LoRa Mesh",
          );
          notifyListeners();
        } else if (state == BluetoothConnectionState.disconnected) {
          _isConnected = false;
          _rxCharacteristic = null;
          _txNotifySub?.cancel();
          _statusMessage = "Disconnected - Auto-reconnecting...";
          notifyListeners();
        }
      });

      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );
      _connectedDevice = device;

      // Save last successfully targeted device
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastDeviceIdKey, device.remoteId.str);
      await prefs.setString(_prefLastDeviceNameKey, devName);

      await Future.delayed(const Duration(milliseconds: 300));

      // Discover Services & Bind to exact Nordic UART Service
      List<BluetoothService> services = await device.discoverServices();
      BluetoothCharacteristic? exactRxChar;
      BluetoothCharacteristic? exactTxChar;

      for (var service in services) {
        for (var char in service.characteristics) {
          final charUuid = char.uuid.toString().toUpperCase();

          if (charUuid.contains("6E400003")) {
            exactTxChar = char;
          }
          if (charUuid.contains("6E400002")) {
            exactRxChar = char;
          }
        }
      }

      // Fallback if custom UUIDs were modified
      if (exactTxChar == null || exactRxChar == null) {
        for (var service in services) {
          for (var char in service.characteristics) {
            if (exactTxChar == null && (char.properties.notify || char.properties.indicate)) {
              exactTxChar = char;
            }
            if (exactRxChar == null && (char.properties.write || char.properties.writeWithoutResponse)) {
              exactRxChar = char;
            }
          }
        }
      }

      _txNotifySub?.cancel();
      if (exactTxChar != null) {
        try {
          await exactTxChar.setNotifyValue(true);
          _txNotifySub = exactTxChar.onValueReceived.listen(_onDataReceived);
          debugPrint('[BLE SERVICE] Successfully bound TX Notify: ${exactTxChar.uuid}');
        } catch (err) {
          debugPrint('Error enabling notify on TX char: $err');
        }
      }

      if (exactRxChar != null) {
        _rxCharacteristic = exactRxChar;
        debugPrint('[BLE SERVICE] Successfully bound RX Write: ${exactRxChar.uuid}');
      }

      // Request MTU
      try {
        await device.requestMtu(247);
      } catch (_) {}

      _isConnected = true;
      _statusMessage = "Connected to $devName";
      NotificationService().showPersistentServiceNotification(
        deviceName: devName,
        status: "Online & Monitoring LoRa Mesh",
      );
      notifyListeners();

      // Query Node for initial ID and telemetry
      Future.delayed(const Duration(milliseconds: 300), () {
        sendCommand({"cmd": "GET_STATUS"});
      });

      return true;
    } catch (e) {
      debugPrint('BLE Connect Error: $e');
      if (retryCount < 2) {
        debugPrint('Retrying connection to ${device.platformName} (Attempt ${retryCount + 2})...');
        _isConnecting = false;
        await Future.delayed(const Duration(milliseconds: 800));
        return connect(device, isAuto: isAuto, retryCount: retryCount + 1);
      }
      _isConnected = false;
      _connectedDevice = null;
      _statusMessage = "Failed to connect: $e";
      notifyListeners();
      return false;
    } finally {
      _isConnecting = false;
      _isAutoConnecting = false;
      notifyListeners();
    }
  }

  void _onDataReceived(List<int> bytes) {
    try {
      String chunk = utf8.decode(bytes, allowMalformed: true);
      _incomingBuffer += chunk;
      if (_incomingBuffer.length > 4096) {
        _incomingBuffer = "";
        return;
      }

      while (true) {
        int startIdx = _incomingBuffer.indexOf('{');
        if (startIdx < 0) {
          _incomingBuffer = "";
          break;
        }
        if (startIdx > 0) {
          _incomingBuffer = _incomingBuffer.substring(startIdx);
          startIdx = 0;
        }

        int depth = 0;
        int endIdx = -1;
        bool inQuotes = false;
        bool escape = false;

        for (int i = 0; i < _incomingBuffer.length; i++) {
          final c = _incomingBuffer[i];
          if (escape) {
            escape = false;
            continue;
          }
          if (c == '\\') {
            escape = true;
            continue;
          }
          if (c == '"') {
            inQuotes = !inQuotes;
            continue;
          }
          if (!inQuotes) {
            if (c == '{') depth++;
            else if (c == '}') {
              depth--;
              if (depth == 0) {
                endIdx = i;
                break;
              }
            }
          }
        }

        if (endIdx != -1) {
          String jsonStr = _incomingBuffer.substring(0, endIdx + 1);
          _incomingBuffer = _incomingBuffer.substring(endIdx + 1);

          try {
            final Map<String, dynamic> data = jsonDecode(jsonStr);
            debugPrint('[BLE IN] $jsonStr');
            final packet = MeshPacket.fromJson(data);
            _packetStreamController.add(packet);
          } catch (err) {
            debugPrint('Failed to parse JSON packet: $err');
          }
        } else {
          // Wait for more chunks to complete JSON object
          break;
        }
      }
    } catch (e) {
      debugPrint('BLE decode error: $e');
    }
  }

  Future<bool> sendCommand(Map<String, dynamic> command) async {
    if (!_isConnected || _rxCharacteristic == null) return false;
    try {
      String jsonStr = '${jsonEncode(command)}\n';
      debugPrint('[BLE OUT] $jsonStr');
      List<int> bytes = utf8.encode(jsonStr);
      bool withoutResp = _rxCharacteristic!.properties.writeWithoutResponse || !_rxCharacteristic!.properties.write;
      await _rxCharacteristic!.write(bytes, withoutResponse: withoutResp);
      return true;
    } catch (e) {
      debugPrint('BLE send command error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    _connectionStateSub?.cancel();
    _txNotifySub?.cancel();
    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
      _rxCharacteristic = null;
      _isConnected = false;
      _statusMessage = "Disconnected";
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _autoReconnectTimer?.cancel();
    _scanSub?.cancel();
    _connectionStateSub?.cancel();
    _txNotifySub?.cancel();
    _packetStreamController.close();
    super.dispose();
  }
}
