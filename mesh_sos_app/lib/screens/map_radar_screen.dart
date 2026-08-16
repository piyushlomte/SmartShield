import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/mesh_provider.dart';
import '../providers/sos_provider.dart';
import '../services/location_service.dart';
import '../models/mesh_node.dart';
import '../widgets/compass_hud.dart';

class MapRadarScreen extends StatefulWidget {
  const MapRadarScreen({super.key});

  @override
  State<MapRadarScreen> createState() => _MapRadarScreenState();
}

class _MapRadarScreenState extends State<MapRadarScreen> {
  final MapController _mapController = MapController();
  MeshNode? _selectedNode;
  bool _showCompassHud = true;
  bool _offlineRadarMode = false;

  @override
  Widget build(BuildContext context) {
    final locationService = Provider.of<LocationService>(context);
    final meshProvider = Provider.of<MeshProvider>(context);
    final sosProvider = Provider.of<SosProvider>(context);

    final pos = locationService.currentPosition;
    final LatLng currentCenter = pos != null
        ? LatLng(pos.latitude, pos.longitude)
        : const LatLng(12.9716, 77.5946); // Default fallback

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Map & Radar', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: Icon(_offlineRadarMode ? Icons.grid_view : Icons.map),
            tooltip: _offlineRadarMode ? 'Switch to Street Map' : 'Switch to Tactical Grid Radar',
            onPressed: () {
              setState(() => _offlineRadarMode = !_offlineRadarMode);
            },
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
          // 1. Street Map Tile Layer (or Pure Tactical Grid in Offline mode)
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: currentCenter,
              initialZoom: 14.0,
            ),
            children: [
              if (!_offlineRadarMode)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.offlinemesh.sos',
                )
              else
                // Dark Tactical Radar Canvas Background
                Container(
                  color: const Color(0xFF0D1117),
                  child: CustomPaint(
                    painter: TacticalRadarGridPainter(
                      heading: locationService.currentHeading,
                    ),
                    child: Container(),
                  ),
                ),

              // 2. Breadcrumbs Trail Polyline
              if (sosProvider.breadcrumbs.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: sosProvider.breadcrumbs,
                      color: Colors.redAccent.withOpacity(0.8),
                      strokeWidth: 4.0,
                    ),
                  ],
                ),

              // 3. Map Markers
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
                          color: const Color(0xFF2F81F7).withOpacity(0.25),
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
                          setState(() {
                            _selectedNode = node;
                            _showCompassHud = true;
                          });
                        },
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: isSos ? Colors.red : (isSelected ? const Color(0xFF2F81F7) : const Color(0xFF161B22)),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSos ? Colors.yellow : (isSelected ? Colors.cyanAccent : Colors.white),
                                  width: 2.5,
                                ),
                              ),
                              child: Icon(
                                isSos ? Icons.warning : Icons.radio,
                                color: isSos ? Colors.white : const Color(0xFF00E676),
                                size: 18,
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                node.name,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
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

          // Offline Mode Banner Indicator
          if (_offlineRadarMode)
            Positioned(
              top: 12,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00E676), width: 1.5),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.radar, color: Color(0xFF00E676), size: 14),
                    SizedBox(width: 6),
                    Text(
                      'TACTICAL GRID (100% OFFLINE)',
                      style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          // Nearby Mesh Nodes Quick Selector Bar (Top Right / Bottom)
          if (meshProvider.nodes.isNotEmpty)
            Positioned(
              top: _offlineRadarMode ? 50 : 12,
              left: 16,
              right: 16,
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: meshProvider.nodes.values.map((node) {
                    final isSelected = _selectedNode?.nodeId == node.nodeId;
                    final isSos = node.isSosActive;
                    double dist = 0.0;
                    if (pos != null && node.latitude != 0.0) {
                      dist = LocationService.calculateDistance(pos.latitude, pos.longitude, node.latitude, node.longitude);
                    }
                    final distStr = dist > 1000 ? '${(dist / 1000).toStringAsFixed(1)}km' : '${dist.toInt()}m';

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: Icon(
                          isSos ? Icons.warning : Icons.radio,
                          color: isSos ? Colors.red : (isSelected ? Colors.cyanAccent : const Color(0xFF00E676)),
                          size: 16,
                        ),
                        label: Text(
                          '${node.name} (${node.latitude != 0.0 ? distStr : "No GPS"})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSos ? Colors.redAccent : Colors.white,
                          ),
                        ),
                        backgroundColor: isSelected ? const Color(0xFF2F81F7).withOpacity(0.3) : const Color(0xFF161B22),
                        side: BorderSide(
                          color: isSos ? Colors.red : (isSelected ? const Color(0xFF2F81F7) : Colors.white24),
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedNode = node;
                            _showCompassHud = true;
                          });
                          if (node.latitude != 0.0 && node.longitude != 0.0) {
                            _mapController.move(LatLng(node.latitude, node.longitude), 15);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          // Floating Radar Compass Bearing HUD
          if (_showCompassHud && _selectedNode != null && pos != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: CompassHud(
                currentHeading: locationService.currentHeading,
                targetBearing: targetBearing,
                distanceMeters: targetDist,
                targetName: _selectedNode!.name,
              ),
            ),
        ],
      ),
    );
  }
}

class TacticalRadarGridPainter extends CustomPainter {
  final double heading;
  TacticalRadarGridPainter({required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = const Color(0xFF30363D).withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final greenPaint = Paint()
      ..color = const Color(0xFF00E676).withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Draw concentric range rings (100m, 500m, 1km, 5km)
    double maxRadius = size.width > size.height ? size.height / 2 - 30 : size.width / 2 - 30;
    for (int i = 1; i <= 4; i++) {
      double r = maxRadius * (i / 4.0);
      canvas.drawCircle(center, r, i % 2 == 0 ? greenPaint : paint);
    }

    // Draw crosshair axes
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);

    // Draw cardinal direction markers
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final cardinals = ['N', 'E', 'S', 'W'];
    final offsets = [
      Offset(center.dx - 5, center.dy - maxRadius - 18),
      Offset(center.dx + maxRadius + 6, center.dy - 6),
      Offset(center.dx - 5, center.dy + maxRadius + 4),
      Offset(center.dx - maxRadius - 18, center.dy - 6),
    ];

    for (int i = 0; i < 4; i++) {
      textPainter.text = TextSpan(
        text: cardinals[i],
        style: TextStyle(
          color: cardinals[i] == 'N' ? const Color(0xFF00E676) : Colors.white38,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(canvas, offsets[i]);
    }
  }

  @override
  bool shouldRepaint(covariant TacticalRadarGridPainter oldDelegate) =>
      oldDelegate.heading != heading;
}


