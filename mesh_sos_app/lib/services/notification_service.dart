import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    try {
      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      // Create Android Notification Channels
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();

        const AndroidNotificationChannel sosChannel = AndroidNotificationChannel(
          'sos_emergency_channel',
          '🚨 Emergency SOS Alerts',
          description: 'High-priority distress alerts from LoRa Mesh network',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        );

        const AndroidNotificationChannel chatChannel = AndroidNotificationChannel(
          'mesh_chat_channel',
          '💬 Mesh Chat & Messages',
          description: 'Incoming text messages and acknowledgements from mesh nodes',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        );

        const AndroidNotificationChannel serviceChannel = AndroidNotificationChannel(
          'mesh_service_channel',
          '📡 Mesh BLE Connection Service',
          description: 'Keeps Heltec LoRa device connected in background',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        );

        await androidImplementation.createNotificationChannel(sosChannel);
        await androidImplementation.createNotificationChannel(chatChannel);
        await androidImplementation.createNotificationChannel(serviceChannel);
      }

      _isInitialized = true;
      debugPrint('✅ [NOTIFICATIONS] NotificationService initialized successfully');
    } catch (e) {
      debugPrint('❌ [NOTIFICATIONS] Error initializing: $e');
    }
  }

  void _onNotificationResponse(NotificationResponse response) {
    debugPrint('🔔 [NOTIFICATION CLICKED] Payload: ${response.payload}');
  }

  Future<void> showSosNotification({
    required int senderId,
    required double lat,
    required double lon,
    required String text,
  }) async {
    String hexId = '0x${senderId.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    String mapUrl = (lat != 0.0 || lon != 0.0) ? 'https://maps.google.com/?q=$lat,$lon' : '';
    String locationStr = (lat != 0.0 || lon != 0.0)
        ? '📍 Coordinates: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}\n🗺️ Map Link: $mapUrl'
        : '⚠️ GPS coords pending';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'sos_emergency_channel',
      '🚨 Emergency SOS Alerts',
      channelDescription: 'High-priority distress alerts from LoRa Mesh network',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'EMERGENCY SOS ALERT from $hexId',
      fullScreenIntent: true,
      category: AndroidNotificationCategory.alarm,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 800, 300, 800, 300, 1000]),
      styleInformation: BigTextStyleInformation(
        'Node $hexId broadcasted an emergency distress signal!\n\n"$text"\n\n$locationStr',
        contentTitle: '🚨 EMERGENCY SOS: Node $hexId',
        summaryText: 'LoRa Mesh Distress Beacon',
      ),
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.critical,
      ),
    );

    await _flutterLocalNotificationsPlugin.show(
      senderId,
      '🚨 EMERGENCY SOS: Node $hexId',
      '"$text" - $locationStr',
      notificationDetails,
      payload: 'SOS_$senderId',
    );
  }

  Future<void> showRescueAcknowledgedNotification({
    required int responderId,
    required String responderName,
    required String message,
    double lat = 0.0,
    double lon = 0.0,
  }) async {
    String mapSuffix = (lat != 0.0 && lon != 0.0)
        ? '\n\n📍 Responder Location: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}\n🗺️ Map Link: https://maps.google.com/?q=$lat,$lon'
        : '';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'sos_emergency_channel',
      '🚨 Emergency SOS Alerts',
      channelDescription: 'High-priority distress alerts and rescue confirmations',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        '$responderName has acknowledged your emergency SOS!\n\n"$message"$mapSuffix',
        contentTitle: '✅ RESCUE CONFIRMED: $responderName',
        summaryText: 'Help is on the way',
      ),
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.critical,
      ),
    );

    await _flutterLocalNotificationsPlugin.show(
      responderId.hashCode ^ 0x55AA,
      '✅ RESCUE CONFIRMED: $responderName',
      message,
      notificationDetails,
      payload: 'SOS_ACK_$responderId',
    );
  }

  Future<void> showChatNotification({
    required int senderId,
    required String senderName,
    required String message,
    double lat = 0.0,
    double lon = 0.0,
  }) async {
    String mapSuffix = (lat != 0.0 && lon != 0.0)
        ? '\n\n📍 GPS: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}\n🗺️ Map: https://maps.google.com/?q=$lat,$lon'
        : '';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'mesh_chat_channel',
      '💬 Mesh Chat & Messages',
      channelDescription: 'Incoming text messages from mesh nodes',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        '$message$mapSuffix',
        contentTitle: '💬 $senderName',
      ),
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _flutterLocalNotificationsPlugin.show(
      senderId.hashCode,
      '💬 $senderName',
      message,
      notificationDetails,
      payload: 'CHAT_$senderId',
    );
  }

  Future<void> showPersistentServiceNotification({
    required String deviceName,
    required String status,
  }) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'mesh_service_channel',
      '📡 Mesh BLE Connection Service',
      channelDescription: 'Keeps Heltec LoRa device connected in background',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false,
      enableVibration: false,
    );

    final NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: false,
        presentSound: false,
      ),
    );

    await _flutterLocalNotificationsPlugin.show(
      9999,
      '📡 SmartShield LoRa Mesh: $deviceName',
      status,
      notificationDetails,
      payload: 'SERVICE',
    );
  }

  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
  }
}
