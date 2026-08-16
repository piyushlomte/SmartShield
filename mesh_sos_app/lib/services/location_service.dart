import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

class LocationService with ChangeNotifier {
  Position? _currentPosition;
  double _currentHeading = 0.0;
  StreamSubscription<Position>? _positionStream;
  StreamSubscription<MagnetometerEvent>? _magStream;
  bool _isTracking = false;

  Position? get currentPosition => _currentPosition;
  double get currentHeading => _currentHeading;
  bool get isTracking => _isTracking;

  Future<bool> initLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // Get initial position
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      notifyListeners();
    } catch (e) {
      debugPrint('Error getting initial location: $e');
    }

    // Listen for position stream
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((position) {
      _currentPosition = position;
      notifyListeners();
    });

    // Listen for magnetometer heading
    try {
      _magStream = magnetometerEventStream().listen((event) {
        // Calculate heading in degrees from magnetometer vector (X, Y)
        double headingRad = atan2(event.y, event.x);
        double headingDeg = headingRad * (180.0 / pi);
        if (headingDeg < 0) headingDeg += 360;
        _currentHeading = headingDeg;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('Compass sensors not supported on this platform: $e');
    }

    _isTracking = true;
    notifyListeners();
    return true;
  }

  // Calculate distance in meters between two lat/lon coordinates (Haversine)
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  // Calculate bearing in degrees from current phone location to a target node
  static double calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.bearingBetween(lat1, lon1, lat2, lon2);
  }

  void stopTracking() {
    _positionStream?.cancel();
    _magStream?.cancel();
    _isTracking = false;
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}
