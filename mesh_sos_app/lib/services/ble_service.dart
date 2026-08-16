import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/mesh_packet.dart';

class BleService with ChangeNotifier {
  static const String serviceUuid = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
  static const String rxCharUuid  = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"; // Phone -> Node
  static const String txCharUuid  = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"; // Node -> Phone

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSub;
  StreamSubscription<List<ScanResult>>? _scanSub;

  bool _isScanning = false;
  bool _isConnected = false;
  List<ScanResult> _scanResults = [];
  String _incomingBuffer = "";
  String _statusMessage = "Disconnected";

  final StreamController<MeshPacket> _packetStreamController = StreamController<MeshPacket>.broadcast();
  Stream<MeshPacket> get packetStream => _packetStreamController.stream;

  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  List<ScanResult> get scanResults => _scanResults;
  String get statusMessage => _statusMessage;

  BleService() {
    _initBleState();
  }

  void _initBleState() {
    FlutterBluePlus.adapterState.listen((state) {
      if (state != BluetoothAdapterState.on) {
        _isConnected = false;
        _connectedDevice = null;
        _statusMessage = "Bluetooth is turned OFF";
        notifyListeners();
      }
    });
  }

  Future<bool> requestAllPermissions() async {
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
        Permission.bluetooth,
      ].request();

      bool granted = statuses.values.every(
        (status) => status.isGranted || status.isLimited,
      );
      return granted;
    } catch (e) {
      debugPrint('Permission request error: $e');
      return false;
    }
  }

  Future<void> startScan() async {
    if (_isScanning) return;

    await requestAllPermissions();

    // Ensure Bluetooth is enabled
    try {
      if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
      }
    } catch (_) {}

    _scanResults.clear();
    _isScanning = true;
    _statusMessage = "Scanning for devices...";
    notifyListeners();

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      // Sort results: prioritize Heltec / SOS / Mesh devices
      results.sort((a, b) {
        bool aIsMesh = a.device.platformName.toLowerCase().contains('mesh') ||
            a.device.platformName.toLowerCase().contains('heltec') ||
            a.device.platformName.toLowerCase().contains('sos');
        bool bIsMesh = b.device.platformName.toLowerCase().contains('mesh') ||
            b.device.platformName.toLowerCase().contains('heltec') ||
            b.device.platformName.toLowerCase().contains('sos');
        if (aIsMesh && !bIsMesh) return -1;
        if (!aIsMesh && bIsMesh) return 1;
        return b.rssi.compareTo(a.rssi);
      });
      _scanResults = results;
      notifyListeners();
    });

    try {
      // Scan without restrictive UUID filter so all Heltec / ESP32 nodes are visible
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 12),
        androidUsesFineLocation: true,
      );
    } catch (e) {
      debugPrint('BLE Scan error: $e');
      _statusMessage = "Scan error: $e";
    } finally {
      Future.delayed(const Duration(seconds: 12), () {
        _isScanning = false;
        _statusMessage = _isConnected ? "Connected" : "Scan finished";
        notifyListeners();
      });
    }
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _isScanning = false;
    _scanSub?.cancel();
    notifyListeners();
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      await stopScan();
      _statusMessage = "Connecting to ${device.platformName}...";
      notifyListeners();

      await device.connect(
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );
      _connectedDevice = device;

      // Monitor connection state
      _connectionStateSub?.cancel();
      _connectionStateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          _isConnected = true;
          _statusMessage = "Connected to ${device.platformName}";
          notifyListeners();
        } else if (state == BluetoothConnectionState.disconnected) {
          _isConnected = false;
          _rxCharacteristic = null;
          _statusMessage = "Disconnected";
          notifyListeners();
        }
      });

      // Request MTU
      try {
        await device.requestMtu(247);
      } catch (_) {}

      // Discover Services
      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        for (var char in service.characteristics) {
          final charUuid = char.uuid.toString().toUpperCase();

          // Match Nordic UART TX or Notify characteristic
          if (charUuid.contains("6E400003") ||
              char.properties.notify ||
              char.properties.indicate) {
            try {
              await char.setNotifyValue(true);
              char.onValueReceived.listen(_onDataReceived);
            } catch (err) {
              debugPrint('Error enabling notify on $charUuid: $err');
            }
          }

          // Match Nordic UART RX or Write characteristic
          if (charUuid.contains("6E400002") ||
              char.properties.write ||
              char.properties.writeWithoutResponse) {
            _rxCharacteristic = char;
          }
        }
      }

      _isConnected = true;
      _statusMessage = "Connected & Ready";
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('BLE Connect Error: $e');
      _isConnected = false;
      _connectedDevice = null;
      _statusMessage = "Failed to connect: $e";
      notifyListeners();
      return false;
    }
  }

  void _onDataReceived(List<int> bytes) {
    try {
      String chunk = utf8.decode(bytes);
      _incomingBuffer += chunk;

      // Extract complete JSON objects
      while (_incomingBuffer.contains('{') && _incomingBuffer.contains('}')) {
        int startIdx = _incomingBuffer.indexOf('{');
        int endIdx = _incomingBuffer.indexOf('}', startIdx);
        if (endIdx != -1) {
          String jsonStr = _incomingBuffer.substring(startIdx, endIdx + 1);
          _incomingBuffer = _incomingBuffer.substring(endIdx + 1);

          try {
            final Map<String, dynamic> data = jsonDecode(jsonStr);
            final packet = MeshPacket.fromJson(data);
            _packetStreamController.add(packet);
          } catch (err) {
            debugPrint('Failed to parse JSON packet: $err');
          }
        } else {
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
      List<int> bytes = utf8.encode(jsonStr);
      await _rxCharacteristic!.write(bytes, withoutResponse: false);
      return true;
    } catch (e) {
      debugPrint('BLE send command error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    _connectionStateSub?.cancel();
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
    _scanSub?.cancel();
    _connectionStateSub?.cancel();
    _packetStreamController.close();
    super.dispose();
  }
}

