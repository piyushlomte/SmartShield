import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';
import '../providers/sos_provider.dart';
import '../services/location_service.dart';
import '../services/offline_navigation_service.dart';
import '../models/mesh_node.dart';
import '../widgets/compass_hud.dart';
import 'smartwatch_screen.dart';

class MapStyleOption {
  final int id;
  final String name;
  final IconData icon;
  final String url;
  final List<String> subdomains;
  final double maxZoom;
  final String description;

  const MapStyleOption({
    required this.id,
    required this.name,
    required this.icon,
    required this.url,
    required this.subdomains,
    required this.maxZoom,
    required this.description,
  });
}

class MapRadarScreen extends StatefulWidget {
  const MapRadarScreen({super.key});

  @override
  State<MapRadarScreen> createState() => _MapRadarScreenState();
}

class _MapRadarScreenState extends State<MapRadarScreen> with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final OfflineNavigationService _navService = OfflineNavigationService();
  MeshNode? _selectedNode;
  int _selectedStyleIndex = 0; // 0: OSM Fast, 1: Tactical Dark, 2: Satellite, 3: Topo, 4: Offline Radar
  bool _showCompassHud = true;
  late AnimationController _sweepController;

  static const List<MapStyleOption> _styles = [
    MapStyleOption(
      id: 0,
      name: 'World Street Map (Fast & Open)',
      icon: Icons.map_outlined,
      url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
      subdomains: [],
      maxZoom: 19.0,
      description: 'Ultra-fast global street map • 100% Open & Free • No 403 Block',
    ),
    MapStyleOption(
      id: 1,
      name: 'Tactical Dark Canvas',
      icon: Icons.dark_mode_outlined,
      url: 'https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}',
      subdomains: [],
      maxZoom: 18.0,
      description: 'Low-light tactical dark mode • Zero 403 Block',
    ),
    MapStyleOption(
      id: 2,
      name: 'Esri Satellite Imagery',
      icon: Icons.satellite_alt_outlined,
      url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      subdomains: [],
      maxZoom: 18.0,
      description: 'High-res satellite terrain & aerial imagery',
    ),
    MapStyleOption(
      id: 3,
      name: 'Topographic Elevation',
      icon: Icons.terrain_outlined,
      url: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
      subdomains: [],
      maxZoom: 18.0,
      description: 'Elevation contours & wilderness trails',
    ),
    MapStyleOption(
      id: 4,
      name: '100% Offline Tactical Radar',
      icon: Icons.radar,
      url: '',
      subdomains: [],
      maxZoom: 20.0,
      description: 'Airplane Mode Ready • Zero Data • Instant Vector Canvas',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _sweepController.dispose();
    super.dispose();
  }

  void _showStyleSelectorModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.layers_outlined, color: Color(0xFF00E676)),
                      SizedBox(width: 8),
                      Text(
                        'Select Map Layer & Style',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Text(
                '⚡ All map layers are 100% Free & No API Key is required.',
                style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Divider(color: Colors.white12),
              ..._styles.map((style) {
                final isSelected = _selectedStyleIndex == style.id;
                return ListTile(
                  leading: Icon(
                    style.icon,
                    color: isSelected ? const Color(0xFF00E676) : Colors.white70,
                  ),
                  title: Text(
                    style.name,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF00E676) : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: Text(
                    style.description,
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFF00E676)) : null,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  tileColor: isSelected ? const Color(0xFF21262D) : null,
                  onTap: () {
                    setState(() {
                      _selectedStyleIndex = style.id;
                    });
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationService = Provider.of<LocationService>(context);
    final meshProvider = Provider.of<MeshProvider>(context);
    final sosProvider = Provider.of<SosProvider>(context);

    final pos = locationService.currentPosition;
    final LatLng currentCenter = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : const LatLng(21.1747, 79.1245); // Active default

    final currentStyle = _styles[_selectedStyleIndex];
    final isPureOfflineRadar = (currentStyle.id == 4);

    // Update active offline navigation progress
    if (pos != null && _navService.isNavigating) {
      _navService.updatePosition(LatLng(pos.latitude, pos.longitude));
    }

    // Calculate Bearing and Distance to Selected Node
    double targetBearing = 0.0;
    double targetDist = 0.0;
    if (_selectedNode != null && pos != null && _selectedNode!.latitude != 0.0) {
      targetDist = LocationService.calculateDistance(
        pos.latitude,
        pos.longitude,
        _selectedNode!.latitude,
        _selectedNode!.longitude,
      );
      targetBearing = LocationService.calculateBearing(
        pos.latitude,
        pos.longitude,
        _selectedNode!.latitude,
        _selectedNode!.longitude,
      );
    }

    // Virtual Tether / Separation Geofence Monitor (> 500m from any teammate)
    MeshNode? separatedNode;
    double separatedDistance = 0.0;
    if (pos != null) {
      for (final node in meshProvider.nodes.values) {
        if (node.latitude != 0.0 && node.longitude != 0.0) {
          final d = LocationService.calculateDistance(
            pos.latitude,
            pos.longitude,
            node.latitude,
            node.longitude,
          );
          if (d > 500.0 && (separatedNode == null || d > separatedDistance)) {
            separatedNode = node;
            separatedDistance = d;
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Offline Map & Radar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              currentStyle.name,
              style: const TextStyle(fontSize: 10, color: Color(0xFF00E676)),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.watch_outlined, color: Color(0xFF00E5FF)),
            tooltip: 'Smartwatch Companion',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SmartwatchScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(currentStyle.icon, color: const Color(0xFF00E676)),
            tooltip: 'Change Map Layer / Style',
            onPressed: () => _showStyleSelectorModal(context),
          ),
          IconButton(
            icon: Icon(_showCompassHud ? Icons.explore : Icons.explore_off),
            tooltip: 'Toggle Compass Radar HUD',
            onPressed: () {
              setState(() => _showCompassHud = !_showCompassHud);
            },
          ),
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Center on my location',
            onPressed: () async {
              if (pos != null) {
                _mapController.move(LatLng(pos.latitude, pos.longitude), 15);
              } else {
                await locationService.initLocation();
                if (!context.mounted) return;
                if (locationService.currentPosition != null) {
                  _mapController.move(
                    LatLng(locationService.currentPosition!.latitude, locationService.currentPosition!.longitude),
                    15,
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enable GPS / Location permission')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Street / Satellite / Radar Map Layer
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentCenter,
              initialZoom: 14.0,
              maxZoom: currentStyle.maxZoom,
              minZoom: 3.0,
            ),
            children: [
              if (!isPureOfflineRadar && currentStyle.url.isNotEmpty)
                TileLayer(
                  urlTemplate: currentStyle.url,
                  userAgentPackageName: 'com.offlinemesh.sos.mesh_sos_app',
                  subdomains: currentStyle.subdomains,
                  maxZoom: currentStyle.maxZoom,
                  panBuffer: 1,
                )
              else
                // 100% Offline Tactical Radar Canvas Background (Zero Network Requests)
                AnimatedBuilder(
                  animation: _sweepController,
                  builder: (context, _) {
                    return Container(
                      color: const Color(0xFF080C10),
                      child: CustomPaint(
                        painter: TacticalRadarGridPainter(
                          heading: locationService.currentHeading,
                          sweepAngle: _sweepController.value * 2 * pi,
                          userPos: pos != null ? LatLng(pos.latitude, pos.longitude) : null,
                          nodes: meshProvider.nodes.values.toList(),
                        ),
                        child: Container(),
                      ),
                    );
                  },
                ),

              // 2. Breadcrumbs Trail Polyline
              if (sosProvider.breadcrumbs.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: sosProvider.breadcrumbs,
                      color: Colors.redAccent.withValues(alpha: 0.8),
                      strokeWidth: 4.0,
                    ),
                  ],
                ),

              // 3. Google Maps-Style 100% Offline Navigation Polyline Layer
              if (_navService.isNavigating && _navService.currentRoute != null) ...[
                // Outer glowing halo
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _navService.currentRoute!.polylinePoints,
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.35),
                      strokeWidth: 12.0,
                    ),
                    // Inner bright primary route line
                    Polyline(
                      points: _navService.currentRoute!.polylinePoints,
                      color: const Color(0xFF00E5FF),
                      strokeWidth: 5.0,
                    ),
                  ],
                ),
                // Pulsating Destination Pin Marker
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _navService.currentRoute!.destinationPoint,
                      width: 64,
                      height: 64,
                      child: AnimatedBuilder(
                        animation: _sweepController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 24 + (_sweepController.value * 32),
                                height: 24 + (_sweepController.value * 32),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.redAccent.withValues(alpha: max(0.0, 1.0 - _sweepController.value)),
                                    width: 2.5,
                                  ),
                                ),
                              ),
                              const Icon(Icons.location_on, color: Colors.redAccent, size: 36),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],

              // 4. Map Markers
              MarkerLayer(
                markers: [
                  // Current Phone / Node Position Marker
                  if (pos != null)
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 48,
                      height: 48,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF2F81F7).withValues(alpha: 0.25),
                          border: Border.all(color: const Color(0xFF2F81F7), width: 3),
                        ),
                        child: const Icon(Icons.person_pin_circle, color: Color(0xFF58A6FF), size: 26),
                      ),
                    ),

                  // Discovered Mesh Node Markers
                  ...meshProvider.nodes.values
                      .where((n) => n.latitude != 0.0 && n.longitude != 0.0)
                      .map((node) {
                    final isSos = node.isSosActive;
                    final isSelected = _selectedNode?.nodeId == node.nodeId;
                    return Marker(
                      point: LatLng(node.latitude, node.longitude),
                      width: 60,
                      height: 60,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedNode = node);
                        },
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isSos
                                    ? Colors.red
                                    : (isSelected ? Colors.amber : const Color(0xFF00E676)),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: (isSos ? Colors.red : const Color(0xFF00E676)).withValues(alpha: 0.5),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isSos ? Icons.warning : Icons.radio,
                                color: Colors.black,
                                size: 16,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                node.hexId,
                                style: TextStyle(
                                  color: isSos ? Colors.redAccent : Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),

          // 5. Turn-by-Turn Navigation HUD Card OR Offline Radar Banner
          if (_navService.isNavigating && _navService.currentRoute != null)
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: _buildTurnByTurnNavigationCard(context),
            )
          else
            Positioned(
              top: 10,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isPureOfflineRadar
                      ? const Color(0xFF00E676).withValues(alpha: 0.15)
                      : const Color(0xFF161B22).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isPureOfflineRadar ? const Color(0xFF00E676) : Colors.white24,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPureOfflineRadar ? Icons.airplanemode_active : Icons.public,
                      color: isPureOfflineRadar ? const Color(0xFF00E676) : const Color(0xFF58A6FF),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isPureOfflineRadar
                            ? '✈️ 100% Airplane Mode Offline Radar • GPS & LoRa Active • 0 B Data Used'
                            : '⚡ Free Offline-Ready Map Layer (${currentStyle.name})',
                        style: TextStyle(
                          color: isPureOfflineRadar ? const Color(0xFF00E676) : Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _selectedStyleIndex = isPureOfflineRadar ? 0 : 4;
                        });
                      },
                      child: Text(
                        isPureOfflineRadar ? 'Switch Map' : 'Go Offline',
                        style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 6. Virtual Tether / Separation Warning
          if (separatedNode != null && !_navService.isNavigating)
            Positioned(
              top: 50,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFD29922).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.leak_remove, color: Colors.black, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Virtual Tether Alert: ${separatedNode.name} is ${(separatedDistance).toStringAsFixed(0)}m away (>500m separation)!',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 7. Compass Radar HUD Overlay
          if (_showCompassHud)
            Positioned(
              top: _navService.isNavigating ? 115 : (separatedNode != null ? 100 : 54),
              right: 12,
              child: CompassHud(
                currentHeading: locationService.currentHeading,
                targetBearing: targetBearing,
                distanceMeters: targetDist,
                targetName: _selectedNode != null ? _selectedNode!.hexId : (_navService.isNavigating ? 'TARGET' : 'No Target'),
              ),
            ),

          // 8. Selected Node Target Card with Direct Offline Navigation Action
          if (_selectedNode != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _selectedNode!.isSosActive ? Colors.red : const Color(0xFF2F81F7),
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _selectedNode!.isSosActive
                                ? Colors.red.withValues(alpha: 0.2)
                                : const Color(0xFF2F81F7).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _selectedNode!.isSosActive ? Icons.warning_amber_rounded : Icons.person_pin,
                            color: _selectedNode!.isSosActive ? Colors.redAccent : Colors.cyanAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedNode!.name,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Dist: ${targetDist > 1000 ? "${(targetDist / 1000).toStringAsFixed(1)} km" : "${targetDist.toStringAsFixed(0)} m"} • Bearing: ${targetBearing.toStringAsFixed(0)}° • Battery: ${_selectedNode!.batteryPercent}%',
                                style: const TextStyle(color: Colors.white70, fontSize: 11),
                              ),
                              Text(
                                'GPS: ${_selectedNode!.latitude.toStringAsFixed(5)}, ${_selectedNode!.longitude.toStringAsFixed(5)} (${_selectedNode!.gpsSource.label})',
                                style: const TextStyle(color: Colors.white38, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white54),
                          onPressed: () => setState(() => _selectedNode = null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _navService.isNavigating ? Colors.redAccent : const Color(0xFF00E5FF),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            icon: Icon(_navService.isNavigating ? Icons.stop_circle_outlined : Icons.directions),
                            label: Text(
                              _navService.isNavigating ? 'Stop Navigation' : 'Start 100% Offline Navigation',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            onPressed: () {
                              setState(() {
                                if (_navService.isNavigating) {
                                  _navService.stopNavigation();
                                } else if (pos != null) {
                                  _navService.calculateOfflineRoute(
                                    start: LatLng(pos.latitude, pos.longitude),
                                    destination: LatLng(_selectedNode!.latitude, _selectedNode!.longitude),
                                    destinationName: _selectedNode!.name,
                                  );
                                  _mapController.move(LatLng(pos.latitude, pos.longitude), 16);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Acquiring your GPS location for navigation...')),
                                  );
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTurnByTurnNavigationCard(BuildContext context) {
    final route = _navService.currentRoute!;
    final step = _navService.currentStep;
    final distRem = _navService.remainingDistanceMeters;
    final minsRem = (_navService.remainingSeconds / 60).ceil();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Colors.black87, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              step?.icon ?? Icons.navigation,
              color: const Color(0xFF00E5FF),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  step?.instruction ?? 'Proceed to Destination',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  step?.subText ?? 'Following 100% Offline Geodesic Trajectory',
                  style: const TextStyle(color: Color(0xFF8B949E), fontSize: 11),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      distRem >= 1000 ? '${(distRem / 1000).toStringAsFixed(1)} km' : '${distRem.round()} m',
                      style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    const Text('•', style: TextStyle(color: Colors.white38)),
                    const SizedBox(width: 8),
                    Text(
                      minsRem < 1 ? '< 1 min ETA' : '$minsRem min ETA',
                      style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54),
            tooltip: 'Exit Navigation',
            onPressed: () {
              setState(() {
                _navService.stopNavigation();
              });
            },
          ),
        ],
      ),
    );
  }
}

class TacticalRadarGridPainter extends CustomPainter {
  final double heading;
  final double sweepAngle;
  final LatLng? userPos;
  final List<MeshNode> nodes;

  TacticalRadarGridPainter({
    required this.heading,
    required this.sweepAngle,
    this.userPos,
    this.nodes = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = const Color(0xFF21262D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final greenPaint = Paint()
      ..color = const Color(0xFF00E676).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Draw concentric range rings (100m, 500m, 1km, 2.5km, 5km)
    double maxRadius = size.width > size.height ? size.height / 2 - 40 : size.width / 2 - 40;
    final ringLabels = ['100m', '500m', '1km', '2.5km', '5km'];
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (int i = 1; i <= 5; i++) {
      double r = maxRadius * (i / 5.0);
      canvas.drawCircle(center, r, i == 3 || i == 5 ? greenPaint : paint);

      // Label distance on rings
      textPainter.text = TextSpan(
        text: ringLabels[i - 1],
        style: const TextStyle(color: Color(0xFF00E676), fontSize: 9, fontFamily: 'monospace'),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(center.dx + 4, center.dy - r - 10));
    }

    // Draw Crosshair Axes
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);

    // Draw Animated Radar Sweep Sector
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: FractionalOffset.center,
        startAngle: 0.0,
        endAngle: pi / 2,
        colors: [
          const Color(0xFF00E676).withValues(alpha: 0.25),
          const Color(0xFF00E676).withValues(alpha: 0.0),
        ],
        transform: GradientRotation(sweepAngle),
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, maxRadius, sweepPaint);

    // Draw Cardinal Direction Markers (N, E, S, W) rotated by heading
    final cardinals = ['N', 'E', 'S', 'W'];
    final angles = [0.0, pi / 2, pi, 3 * pi / 2];

    for (int i = 0; i < 4; i++) {
      double rad = angles[i] - (heading * pi / 180.0);
      double x = center.dx + (maxRadius + 18) * sin(rad);
      double y = center.dy - (maxRadius + 18) * cos(rad);

      textPainter.text = TextSpan(
        text: cardinals[i],
        style: TextStyle(
          color: cardinals[i] == 'N' ? const Color(0xFF00E676) : Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
    }

    // Draw Node Vectors on Radar
    if (userPos != null) {
      for (final node in nodes) {
        if (node.latitude != 0.0 && node.longitude != 0.0) {
          double dist = LocationService.calculateDistance(userPos!.latitude, userPos!.longitude, node.latitude, node.longitude);
          double bearing = LocationService.calculateBearing(userPos!.latitude, userPos!.longitude, node.latitude, node.longitude);
          double relativeBearing = bearing - heading;
          double rad = (relativeBearing * pi) / 180.0;

          double scaledDist = min(dist / 5000.0, 1.0) * maxRadius;
          double nx = center.dx + scaledDist * sin(rad);
          double ny = center.dy - scaledDist * cos(rad);

          // Draw dotted vector line
          final vectorPaint = Paint()
            ..color = node.isSosActive ? Colors.redAccent.withValues(alpha: 0.8) : const Color(0xFF00E676).withValues(alpha: 0.6)
            ..strokeWidth = 1.2
            ..style = PaintingStyle.stroke;

          canvas.drawLine(center, Offset(nx, ny), vectorPaint);

          // Draw node blip
          final blipPaint = Paint()
            ..color = node.isSosActive ? Colors.redAccent : const Color(0xFF00E676)
            ..style = PaintingStyle.fill;

          canvas.drawCircle(Offset(nx, ny), 5, blipPaint);

          // Draw node label
          textPainter.text = TextSpan(
            text: '${node.hexId} (${dist.toStringAsFixed(0)}m)',
            style: TextStyle(
              color: node.isSosActive ? Colors.redAccent : Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          );
          textPainter.layout();
          textPainter.paint(canvas, Offset(nx + 8, ny - 6));
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant TacticalRadarGridPainter oldDelegate) =>
      oldDelegate.heading != heading || oldDelegate.sweepAngle != sweepAngle || oldDelegate.nodes.length != nodes.length;
}
