import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../models/incident_record.dart';
import '../models/mesh_packet.dart';
import 'incident_journal_service.dart';

enum FallDetectionState {
  idle,
  freefallDetected,
  impactDetected,
  inactivityConfirmed,
  countdownActive,
  sosTriggered,
}

class AiSafetyService with ChangeNotifier {
  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
  bool _isEnabled = true;
  double _sensitivity = 1.0;

  FallDetectionState _state = FallDetectionState.idle;
  double _currentG = 9.8;
  double _maxImpactG = 0.0;
  int _riskScore = 0; // 0 to 100%
  int _confidenceScore = 90; // 0 to 100%
  int _signalAnomalyScore = 0; // §10.1 Signal Anomaly Score
  int _timeToReserveMins = 720; // §10.6 Predictive Battery Mins
  int _countdownSeconds = 10;
  Timer? _countdownTimer;

  // §10.3 Dead-Man's-Switch / Passive Check-In State
  bool _isDeadManEnabled = false;
  int _deadManIntervalMins = 15; // 15, 30, 60 mins
  int _deadManCountdownSeconds = 60;
  bool _isDeadManPromptActive = false;
  Timer? _deadManTimer;
  Timer? _deadManPromptTimer;

  // Anomaly & Motion Tracker
  final List<double> _recentMagnitudes = [];
  DateTime? _freefallStartTime;
  DateTime? _impactTime;

  // Callback to trigger SOS
  Function(String reason, int riskScore)? onAutoSosTriggered;
  Function(bool isPromptActive)? onDeadManStateChanged;

  bool get isEnabled => _isEnabled;
  FallDetectionState get state => _state;
  double get currentG => _currentG;
  double get maxImpactG => _maxImpactG;
  int get riskScore => _riskScore;
  int get confidenceScore => _confidenceScore;
  int get signalAnomalyScore => _signalAnomalyScore;
  int get timeToReserveMins => _timeToReserveMins;
  int get countdownSeconds => _countdownSeconds;
  bool get isCountdownActive => _state == FallDetectionState.countdownActive;

  bool get isDeadManEnabled => _isDeadManEnabled;
  int get deadManIntervalMins => _deadManIntervalMins;
  int get deadManCountdownSeconds => _deadManCountdownSeconds;
  bool get isDeadManPromptActive => _isDeadManPromptActive;

  AiSafetyService() {
    startMonitoring();
  }

  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    if (enabled) {
      startMonitoring();
    } else {
      stopMonitoring();
      cancelCountdown();
    }
    notifyListeners();
  }

  void setSensitivity(double s) {
    _sensitivity = s.clamp(0.5, 2.0);
    notifyListeners();
  }

  void setSignalAnomaly(int score) {
    _signalAnomalyScore = score;
    notifyListeners();
  }

  void setTimeToReserve(int mins) {
    _timeToReserveMins = mins;
    notifyListeners();
  }

  // ===========================================================================
  // §10.3 DEAD-MAN'S-SWITCH / PASSIVE CHECK-IN MODE
  // ===========================================================================
  void setDeadManEnabled(bool enabled) {
    _isDeadManEnabled = enabled;
    _deadManTimer?.cancel();
    _deadManPromptTimer?.cancel();
    _isDeadManPromptActive = false;

    if (enabled) {
      _startDeadManIntervalTimer();
    }
    notifyListeners();
  }

  void setDeadManInterval(int mins) {
    _deadManIntervalMins = mins.clamp(5, 120);
    if (_isDeadManEnabled) {
      _startDeadManIntervalTimer();
    }
    notifyListeners();
  }

  void _startDeadManIntervalTimer() {
    _deadManTimer?.cancel();
    _deadManTimer = Timer.periodic(Duration(minutes: _deadManIntervalMins), (timer) {
      _triggerDeadManPrompt();
    });
  }

  void _triggerDeadManPrompt() {
    _isDeadManPromptActive = true;
    _deadManCountdownSeconds = 60;
    notifyListeners();
    onDeadManStateChanged?.call(true);

    IncidentJournalService.instance.logEvent(
      IncidentRecord(
        id: 'DEADMAN_PROMPT_${DateTime.now().millisecondsSinceEpoch}',
        eventType: IncidentEventType.deadManPrompt,
        senderId: 0,
        latitude: 0.0,
        longitude: 0.0,
        gpsSource: GpsSource.none,
        riskScore: 35,
        details: 'Passive Check-In Prompt initiated ($_deadManIntervalMins min interval). User has 60s to confirm.',
      ),
    );

    _deadManPromptTimer?.cancel();
    _deadManPromptTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_deadManCountdownSeconds > 1) {
        _deadManCountdownSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        _deadManCountdownSeconds = 0;
        _isDeadManPromptActive = false;
        notifyListeners();
        onDeadManStateChanged?.call(false);

        // Auto-generate Emergency SOS due to missed check-in
        IncidentJournalService.instance.logEvent(
          IncidentRecord(
            id: 'DEADMAN_MISSED_${DateTime.now().millisecondsSinceEpoch}',
            eventType: IncidentEventType.deadManMissed,
            senderId: 0,
            latitude: 0.0,
            longitude: 0.0,
            gpsSource: GpsSource.none,
            riskScore: 85,
            details: 'User failed to acknowledge Dead-Man check-in prompt. Auto-escalating to Emergency SOS.',
          ),
        );

        onAutoSosTriggered?.call(
          "Passive Check-In Missed / Prolonged Inactivity Anomaly",
          85,
        );
      }
    });
  }

  void acknowledgeDeadManCheckIn() {
    if (_isDeadManPromptActive) {
      _deadManPromptTimer?.cancel();
      _isDeadManPromptActive = false;
      _deadManCountdownSeconds = 60;
      notifyListeners();
      onDeadManStateChanged?.call(false);

      IncidentJournalService.instance.logEvent(
        IncidentRecord(
          id: 'DEADMAN_ACK_${DateTime.now().millisecondsSinceEpoch}',
          eventType: IncidentEventType.telemetryReport,
          senderId: 0,
          latitude: 0.0,
          longitude: 0.0,
          gpsSource: GpsSource.none,
          riskScore: 0,
          details: 'Passive Check-In acknowledged by user. User confirmed safe.',
        ),
      );
    }
  }

  // ===========================================================================
  // KINEMATIC FALL DETECTION
  // ===========================================================================
  void startMonitoring() {
    _sensorSubscription?.cancel();
    try {
      _sensorSubscription = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(_processSensorData, onError: (e) {
        debugPrint('Sensor error: $e');
      });
    } catch (e) {
      debugPrint('Error starting accelerometer: $e');
    }
  }

  void stopMonitoring() {
    _sensorSubscription?.cancel();
    _sensorSubscription = null;
  }

  void _processSensorData(AccelerometerEvent event) {
    if (!_isEnabled || isCountdownActive) return;

    double magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    _currentG = magnitude;

    _recentMagnitudes.add(magnitude);
    if (_recentMagnitudes.length > 50) {
      _recentMagnitudes.removeAt(0);
    }

    final now = DateTime.now();

    // 1. Stage 1: Freefall detection (G < 3.5 m/s^2)
    if (magnitude < (3.5 * _sensitivity)) {
      if (_freefallStartTime == null) {
        _freefallStartTime = now;
        _state = FallDetectionState.freefallDetected;
      }
    }

    // 2. Stage 2: Heavy Impact spike (G > 22.0 m/s^2) shortly after freefall or sudden shock
    if (magnitude > (22.0 * _sensitivity)) {
      _maxImpactG = max(_maxImpactG, magnitude);
      _impactTime = now;
      _state = FallDetectionState.impactDetected;
      _riskScore = min(98, (45 + (magnitude * 1.8)).toInt());
    }

    // 3. Stage 3: Inactivity / Motionless evaluation (300ms to 2.5s after impact)
    if (_impactTime != null && now.difference(_impactTime!).inMilliseconds > 400) {
      double avg = _recentMagnitudes.reduce((a, b) => a + b) / _recentMagnitudes.length;
      double variance = _recentMagnitudes.map((v) => pow(v - avg, 2)).reduce((a, b) => a + b) / _recentMagnitudes.length;

      if (variance < 2.5) {
        _state = FallDetectionState.inactivityConfirmed;
        _freefallStartTime = null;
        _impactTime = null;
        startCountdown(anomalyType: "Fall & Inactivity Confirmed");
      } else {
        if (now.difference(_impactTime!).inSeconds > 3) {
          _freefallStartTime = null;
          _impactTime = null;
          _state = FallDetectionState.idle;
        }
      }
    }
  }

  void startCountdown({String anomalyType = "High Impact & Fall"}) {
    if (_state == FallDetectionState.countdownActive) return;

    _state = FallDetectionState.countdownActive;
    _countdownSeconds = 10;
    _riskScore = max(_riskScore, 85);
    _confidenceScore = 94;
    notifyListeners();

    IncidentJournalService.instance.logEvent(
      IncidentRecord(
        id: 'FALL_${DateTime.now().millisecondsSinceEpoch}',
        eventType: IncidentEventType.fallImpactDetected,
        senderId: 0,
        latitude: 0.0,
        longitude: 0.0,
        gpsSource: GpsSource.none,
        riskScore: _riskScore,
        confidenceScore: _confidenceScore,
        details: 'G-Force Impact: ${_maxImpactG.toStringAsFixed(1)}G followed by user inactivity.',
      ),
    );

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdownSeconds > 1) {
        _countdownSeconds--;
        notifyListeners();
      } else {
        timer.cancel();
        _countdownSeconds = 0;
        _state = FallDetectionState.sosTriggered;
        notifyListeners();

        onAutoSosTriggered?.call(
          "AI Emergency: $anomalyType Detected (Risk: $_riskScore%, Impact: ${_maxImpactG.toStringAsFixed(1)}G)",
          _riskScore,
        );
      }
    });
  }

  void cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownSeconds = 10;
    _state = FallDetectionState.idle;
    _maxImpactG = 0.0;
    _freefallStartTime = null;
    _impactTime = null;
    notifyListeners();
  }

  void simulateFallEvent() {
    _maxImpactG = 28.4;
    _riskScore = 92;
    startCountdown(anomalyType: "Simulated Impact & Inactivity");
  }

  // ===========================================================================
  // §10.8 EXPLAINABLE ESCALATION NARRATIVES
  // ===========================================================================
  List<String> getExplanationReasons({
    required int score,
    required bool isSosActive,
    bool hasGps = true,
    bool isAckReceived = false,
    bool isRescueAccepted = false,
    int retryCount = 0,
    int batteryPct = 100,
    int rssi = -75,
    double snr = 6.0,
    int signalAnomaly = 0,
    int timeToReserve = 720,
    bool isDuress = false,
  }) {
    final reasons = <String>[];

    if (isDuress) {
      reasons.add('§10.4 Duress Silent-Cancel Code active: Cancelled on OLED but held at LOW priority for rescue verification.');
    }
    if (signalAnomaly > 0) {
      reasons.add('§10.1 RF Signal Fingerprint Anomaly ($signalAnomaly%): Rapid attenuation detected consistent with submersion or burial.');
    }
    if (isSosActive) {
      reasons.add('Distress beacon actively broadcasting on high-priority preemptive queue.');
    }
    if (_maxImpactG > 20.0) {
      reasons.add('High kinetic G-Force impact (${_maxImpactG.toStringAsFixed(1)}G) detected.');
    }
    if (retryCount > 0 && !isAckReceived) {
      reasons.add('§10.8 Escalated to CRITICAL because: $retryCount unacknowledged transmissions AND link degraded.');
    }
    if (isAckReceived && !isRescueAccepted) {
      reasons.add('Remote mesh node acknowledged delivery; awaiting rescue dispatch confirmation.');
    }
    if (isRescueAccepted) {
      reasons.add('§10.5 Rescue Swarm Claim locked: Rescue operator actively accepted incident; response dispatched.');
    }
    if (batteryPct <= 10 || timeToReserve <= 60) {
      reasons.add('§10.6 Predictive Battery Degradation: ~$timeToReserve mins remaining until <5% SOS-Only Reserve.');
    } else if (batteryPct <= 20) {
      reasons.add('Battery entering power saving threshold.');
    }
    if (rssi < -110 || snr < -5.0) {
      reasons.add('RF channel signal degraded (${rssi}dBm / ${snr.toStringAsFixed(1)}dB SNR). Adaptive retry active.');
    }
    if (hasGps) {
      reasons.add('High-precision location fix verified for tactical navigation.');
    } else {
      reasons.add('GPS fix degraded; employing fallback last-known telemetry coordinates.');
    }

    if (reasons.isEmpty) {
      reasons.add('System operating in normal standby monitoring mode.');
    }
    return reasons;
  }

  static String getRiskTierName(int score) {
    if (score <= 20) return 'SAFE';
    if (score <= 40) return 'LOW';
    if (score <= 60) return 'MEDIUM';
    if (score <= 80) return 'HIGH';
    return 'CRITICAL';
  }

  static String getActionableRecommendation({
    required int score,
    required bool isSosActive,
    required bool isAckReceived,
    required bool isRescueAccepted,
    int signalAnomaly = 0,
  }) {
    if (signalAnomaly > 50) {
      return 'Severe RF signal attenuation detected (potential burial/cave-in). Node switching to adaptive high-penetration SF.';
    }
    if (isRescueAccepted) {
      return 'Search & Rescue node has locked claim and confirmed dispatch. Remain in current location and conserve device power.';
    }
    if (isAckReceived) {
      return 'Distress frame successfully delivered to mesh peers. Awaiting manual rescue team acceptance.';
    }
    if (isSosActive) {
      return 'Adaptive multi-hop retransmission active. Keep node antenna upright and oriented towards open terrain.';
    }
    if (score > 60) {
      return 'High anomaly risk detected. Confirm user status or activate manual SOS if stranded.';
    }
    return 'Mesh network links nominal. Ready for offline emergency distress transmission.';
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _deadManTimer?.cancel();
    _deadManPromptTimer?.cancel();
    _sensorSubscription?.cancel();
    super.dispose();
  }
}
