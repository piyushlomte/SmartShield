import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/sos_alert.dart';

class AlertService with ChangeNotifier {
  SosAlert? _activeEmergency;
  bool _isSirenMuted = false;
  Timer? _vibrationLoopTimer;

  SosAlert? get activeEmergency => _activeEmergency;
  bool get hasActiveEmergency => _activeEmergency != null;
  bool get isSirenMuted => _isSirenMuted;

  void triggerEmergencyAlert(SosAlert alert) {
    _activeEmergency = alert;
    _isSirenMuted = false;
    notifyListeners();

    _startVibrationPulse();
  }

  void _startVibrationPulse() {
    _vibrationLoopTimer?.cancel();
    _vibrationLoopTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (_activeEmergency == null || _isSirenMuted) {
        timer.cancel();
        return;
      }
      // Haptic pulse simulation / trigger
      debugPrint('🚨 [EMERGENCY HAPTIC & SIREN PULSE] Distress from Node ${_activeEmergency!.hexId}');
    });
  }

  void muteSiren() {
    _isSirenMuted = true;
    _vibrationLoopTimer?.cancel();
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
    _vibrationLoopTimer?.cancel();
    notifyListeners();
  }

  @override
  void dispose() {
    _vibrationLoopTimer?.cancel();
    super.dispose();
  }
}
