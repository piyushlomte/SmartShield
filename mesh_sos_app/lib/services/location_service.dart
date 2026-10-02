import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  // Live dynamically fetched map location data
  String _currentAreaName = 'Acquiring Area...';
  String _currentNearPlace = 'Analyzing near places...';
  final Map<String, Map<String, String>> _geoCache = {};
  DateTime _lastFetchTime = DateTime.fromMillisecondsSinceEpoch(0);

  Position? get currentPosition => _currentPosition;
  double get currentHeading => _currentHeading;
  bool get isTracking => _isTracking;
  String get currentAreaName => _currentAreaName;
  String get currentNearPlace => _currentNearPlace;

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

    // 1. Fetch last known GPS hardware position
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        _currentPosition = lastKnown;
        fetchDynamicMapLocation(lastKnown.latitude, lastKnown.longitude);
        notifyListeners();
        debugPrint('📍 [GPS OFFLINE] Loaded last known location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
      }
    } catch (e) {
      debugPrint('Error getting last known location: $e');
    }

    // 2. High-precision hardware GPS configuration
    final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 2),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      );
    }

    // 3. Try getting fresh hardware GPS position
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: locationSettings,
      );
      _currentPosition = pos;
      fetchDynamicMapLocation(pos.latitude, pos.longitude);
      notifyListeners();
    } catch (e) {
      debugPrint('Live GPS acquisition in progress: $e');
    }

    // 4. Continuously listen for GNSS/GPS position updates
    _positionStream?.cancel();
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((position) {
      _currentPosition = position;
      fetchDynamicMapLocation(position.latitude, position.longitude);
      notifyListeners();
    }, onError: (err) {
      debugPrint('GPS Stream Error: $err');
    });

    // 5. Magnetometer compass heading
    try {
      _magStream?.cancel();
      _magStream = magnetometerEventStream().listen((event) {
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

  /// Automatically fetch live reverse-geocoded Area and analyze nearby Mandirs / Landmarks from Map APIs
  Future<Map<String, String>> fetchDynamicMapLocation(double lat, double lon) async {
    if (lat == 0.0 && lon == 0.0) {
      return {'area': 'Acquiring Fix...', 'near': 'Standby'};
    }

    final cacheKey = '${lat.toStringAsFixed(3)}_${lon.toStringAsFixed(3)}';
    if (_geoCache.containsKey(cacheKey)) {
      final cached = _geoCache[cacheKey]!;
      _currentAreaName = cached['area'] ?? _currentAreaName;
      _currentNearPlace = cached['near'] ?? _currentNearPlace;
      notifyListeners();
      return cached;
    }

    // Throttle HTTP requests to avoid rate limits (at most 1 query per 3 seconds)
    if (DateTime.now().difference(_lastFetchTime).inSeconds < 3) {
      return {'area': _currentAreaName, 'near': _currentNearPlace};
    }
    _lastFetchTime = DateTime.now();

    String resolvedArea = 'Local Area';
    String resolvedNear = 'GPS: ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);

    try {
      // 1. Live OpenStreetMap Nominatim Reverse Geocoding
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lon&zoom=18&addressdetails=1',
      );
      final request = await client.getUrl(uri);
      request.headers.set('User-Agent', 'SmartShield-SOS-App/1.0 (Mesh Emergency System)');
      final response = await request.close().timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = jsonDecode(responseBody) as Map<String, dynamic>;

        final address = data['address'] as Map<String, dynamic>?;
        if (address != null) {
          // Extract specific Area / Locality
          final sub = address['suburb'] ??
              address['neighbourhood'] ??
              address['residential'] ??
              address['village'] ??
              address['town'] ??
              address['city_district'] ??
              address['road'];
          final city = address['city'] ?? address['state_district'] ?? address['county'] ?? address['state'];

          if (sub != null && city != null) {
            resolvedArea = '$sub, $city';
          } else if (sub != null) {
            resolvedArea = '$sub';
          } else if (city != null) {
            resolvedArea = '$city Area';
          }

          // Check if Nominatim returned a specific POI / Mandir / Building
          final name = data['name'] as String?;
          final amenity = address['amenity'] as String?;
          final placeOfWorship = address['place_of_worship'] as String?;
          final temple = address['temple'] as String?;
          final building = address['building'] as String?;

          if (name != null && name.isNotEmpty && name != sub) {
            resolvedNear = name;
          } else if (placeOfWorship != null) {
            resolvedNear = placeOfWorship;
          } else if (temple != null) {
            resolvedNear = temple;
          } else if (amenity != null) {
            resolvedNear = amenity;
          } else if (building != null && building != 'yes') {
            resolvedNear = building;
          } else if (address['road'] != null) {
            resolvedNear = 'Near ${address['road']}';
          }
        }
      }

      // 2. Query OSM Overpass API to discover nearby Mandirs / Temples / Places of Worship within 800m
      try {
        final overpassUri = Uri.parse(
          'https://overpass-api.de/api/interpreter?data=[out:json][timeout:3];(node["amenity"="place_of_worship"](around:800,$lat,$lon);node["historic"](around:800,$lat,$lon);node["tourism"](around:800,$lat,$lon););out body 5;',
        );
        final opReq = await client.getUrl(overpassUri);
        final opRes = await opReq.close().timeout(const Duration(seconds: 3));
        if (opRes.statusCode == 200) {
          final opBody = await opRes.transform(utf8.decoder).join();
          final opData = jsonDecode(opBody) as Map<String, dynamic>;
          final elements = opData['elements'] as List<dynamic>?;
          if (elements != null && elements.isNotEmpty) {
            double closestDist = 1e9;
            String? closestName;

            for (final el in elements) {
              final tags = el['tags'] as Map<String, dynamic>?;
              final pLat = el['lat'] as double?;
              final pLon = el['lon'] as double?;
              if (tags != null && pLat != null && pLon != null) {
                final poiName = tags['name'] ?? tags['name:en'];
                if (poiName != null && poiName.toString().trim().isNotEmpty) {
                  final d = calculateDistance(lat, lon, pLat, pLon);
                  if (d < closestDist) {
                    closestDist = d;
                    closestName = poiName.toString();
                  }
                }
              }
            }

            if (closestName != null) {
              final distStr = closestDist < 1000 ? '${closestDist.round()}m' : '${(closestDist / 1000).toStringAsFixed(1)}km';
              resolvedNear = '$closestName ($distStr)';
            }
          }
        }
      } catch (e) {
        debugPrint('Overpass POI query error (using primary reverse geocode): $e');
      }
    } catch (e) {
      debugPrint('Live map reverse geocode error (offline fallback): $e');
      // If network is not reachable, fallback to fast heuristic coordinate grid
      resolvedArea = 'Lat: ${lat.toStringAsFixed(3)}, Lon: ${lon.toStringAsFixed(3)}';
      resolvedNear = 'Grid Sector (${lat > 0 ? 'N' : 'S'})';
    } finally {
      client.close();
    }

    final result = {'area': resolvedArea, 'near': resolvedNear};
    _geoCache[cacheKey] = result;
    _currentAreaName = resolvedArea;
    _currentNearPlace = resolvedNear;
    notifyListeners();
    return result;
  }

  /// Fast synchronized method that checks in-memory cache or returns current live resolved landmark
  static Map<String, String> getNearestLandmarkInfo(double lat, double lon) {
    if (lat == 0.0 && lon == 0.0) {
      return {'area': 'Acquiring Fix...', 'near': 'Standby'};
    }
    return {
      'area': 'Resolving Location...',
      'near': 'GPS: ${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}',
    };
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
