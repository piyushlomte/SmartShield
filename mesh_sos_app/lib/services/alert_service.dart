import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/sos_alert.dart';
import 'notification_service.dart';

class AlertService with ChangeNotifier {
  SosAlert? _activeEmergency;
  bool _isSirenMuted = false;
  Timer? _alertLoopTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();

  SosAlert? get activeEmergency => _activeEmergency;
  bool get hasActiveEmergency => _activeEmergency != null;
  bool get isSirenMuted => _isSirenMuted;

  AlertService() {
    _initAudio();
  }

  void _initAudio() {
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
  }

  void triggerEmergencyAlert(SosAlert alert) {
    _activeEmergency = alert;
    _isSirenMuted = false;
    notifyListeners();

    // 1. Post Loud Mobile Notification
    NotificationService().showSosNotification(
      senderId: alert.senderId,
      lat: alert.latitude,
      lon: alert.longitude,
      text: alert.message,
    );

    // 2. Start Repeating Siren & Heavy Vibration Loop
    _startAlertLoop();
  }

  void _startAlertLoop() {
    _alertLoopTimer?.cancel();
    _playAlarmBeep();

    _alertLoopTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (_activeEmergency == null || _isSirenMuted) {
        timer.cancel();
        return;
      }
      _playAlarmBeep();
    });
  }

  void _playAlarmBeep() async {
    if (_isSirenMuted) return;

    // Heavy system haptic feedback pattern
    try {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 200), () => HapticFeedback.heavyImpact());
      Future.delayed(const Duration(milliseconds: 400), () => HapticFeedback.heavyImpact());
      Future.delayed(const Duration(milliseconds: 600), () => SystemSound.play(SystemSoundType.alert));
    } catch (_) {}

    debugPrint('🚨 [SIREN ALERT SOUND & VIBRATION ACTIVE] Node ${_activeEmergency?.hexId}');
  }

  void muteSiren() {
    _isSirenMuted = true;
    _alertLoopTimer?.cancel();
    try {
      _audioPlayer.stop();
    } catch (_) {}
    notifyListeners();
  }

  void updateEmergencyResponse(String responderName, String responseText) {
    if (_activeEmergency != null) {
      _activeEmergency = _activeEmergency!.copyWith(
        responderName: responderName,
        responseMessage: responseText,
        responseTime: DateTime.now(),
      );
      notifyListeners();
    }
  }

  void dismissEmergency() {
    _activeEmergency = null;
    _isSirenMuted = false;
    _alertLoopTimer?.cancel();
    try {
      _audioPlayer.stop();
    } catch (_) {}
    notifyListeners();
  }

  @override
  void dispose() {
    _alertLoopTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}
