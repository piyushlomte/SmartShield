import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sos_provider.dart';
import '../models/sos_alert.dart';
import '../services/location_service.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _noteController = TextEditingController();
  bool _silentMode = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _noteController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sosProvider = Provider.of<SosProvider>(context);
    final locationService = Provider.of<LocationService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Beacon', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Row(
            children: [
              const Text('Silent Mode', style: TextStyle(fontSize: 12)),
              Switch(
                value: _silentMode,
                activeColor: Colors.redAccent,
                onChanged: (val) {
                  setState(() => _silentMode = val);
                },
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Emergency State Indicator / Active Broadcast Card
          if (sosProvider.isSelfSosActive)
            _buildActiveSosCard(context, sosProvider)
          else
            _buildTriggerSection(context, sosProvider, locationService),

          const SizedBox(height: 24),

          // Distress Category Selector
          const Text(
            'Distress Classification',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: DistressCategory.values.map((cat) {
              final isSelected = sosProvider.selectedCategory == cat;
              return ChoiceChip(
                label: Text('${cat.icon} ${cat.title}'),
                selected: isSelected,
                selectedColor: Colors.red.withOpacity(0.3),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.redAccent : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                onSelected: (selected) {
                  if (selected) sosProvider.setCategory(cat);
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Custom Situation Details Note
          TextField(
            controller: _noteController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: 'Additional situation notes (Optional)',
              labelStyle: const TextStyle(color: Colors.white54),
              hintText: 'e.g. 2 people, 1 with broken ankle, cliffside',
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onChanged: (val) => sosProvider.setDistressNote(val),
          ),

          const SizedBox(height: 24),

          // Emergency Telemetry & GPS Provenance Status
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: Color(0xFF00E676), size: 18),
                    SizedBox(width: 8),
                    Text('Emergency Fallback & Protocol', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '• Preemption Queue: SOS bypasses all mesh chat traffic\n'
                  '• GPS Fallback: Phone GNSS automatically bridges if NEO-6M has no lock\n'
                  '• Repeat Frequency: Beacon broadcasts every 15s across 4 mesh hops',
                  style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7), height: 1.4),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Emergency Logs History
          if (sosProvider.alertHistory.isNotEmpty) ...[
            const Text(
              'Emergency Dispatch Logs',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 10),
            ...sosProvider.alertHistory.map((alert) => _buildAlertLogItem(context, alert)),
          ],
        ],
      ),
    );
  }

  Widget _buildTriggerSection(BuildContext context, SosProvider sos, LocationService loc) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              sos.triggerSos(silent: _silentMode);
            },
            child: Container(
              height: 180,
              width: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [Color(0xFFFF1744), Color(0xFFB71C1C)],
                  radius: 0.85,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 25,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 54, color: Colors.white),
                  SizedBox(height: 6),
                  Text(
                    'BROADCAST SOS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    'Tap to Dispatch',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _silentMode
                ? '⚠️ Silent Mode Active: OLED & sound will be suppressed'
                : 'Will transmit high-priority alert + coordinates to all mesh nodes',
            textAlign: TextAlign.center,
            style: TextStyle(color: _silentMode ? Colors.orange : Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSosCard(BuildContext context, SosProvider sos) {
    final selfAlert = sos.alertHistory.firstWhere((a) => a.isSelf, orElse: () => sos.alertHistory.first);
    final hasRescueResponse = selfAlert.responderName != null;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: hasRescueResponse
                ? const Color(0xFF0D47A1)
                : Color.lerp(const Color(0xFFB71C1C), const Color(0xFFD50000), _pulseController.value),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: hasRescueResponse ? Colors.blue.withOpacity(0.5) : Colors.red.withOpacity(0.6),
                blurRadius: 15 * _pulseController.value,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(
                hasRescueResponse ? Icons.verified_user : Icons.emergency_share,
                size: 48,
                color: Colors.white,
              ),
              const SizedBox(height: 10),
              Text(
                hasRescueResponse ? 'RESCUE TEAM EN ROUTE!' : 'EMERGENCY BEACON ACTIVE',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              if (hasRescueResponse) ...[
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF00E676)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Acknowledged by: ${selfAlert.responderName}',
                        style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '"${selfAlert.responseMessage ?? 'Help is on the way!'}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ] else
                const Text(
                  'Broadcasting location and distress signal over LoRa mesh...',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => sos.cancelSos(),
                icon: const Icon(Icons.cancel, color: Colors.black),
                label: const Text('CANCEL / RESOLVE SOS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAlertLogItem(BuildContext context, SosAlert alert) {
    final sos = Provider.of<SosProvider>(context, listen: false);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: alert.isResolved
              ? const Color(0xFF00E676).withOpacity(0.5)
              : (alert.responderName != null ? Colors.blue.withOpacity(0.6) : Colors.red.withOpacity(0.5)),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(alert.category.icon, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.senderName} (${alert.category.title})',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                    ),
                    Text(
                      'GPS: ${alert.latitude.toStringAsFixed(4)}, ${alert.longitude.toStringAsFixed(4)} (${alert.gpsSource.label})',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (alert.isResolved)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E676).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('SAFE / RESOLVED', style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            alert.message,
            style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13),
          ),

          // Responder status badge
          if (alert.responderName != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D47A1).withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
              ),
              child: Text(
                '🚑 Rescue Dispatched by ${alert.responderName}: "${alert.responseMessage ?? 'Help en route'}"',
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ],

          // 2-Way Rescue Response Action Bar (For Remote Distress calls)
          if (!alert.isSelf && !alert.isResolved) ...[
            const SizedBox(height: 10),
            const Text('2-Way Rescue Response:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.directions_run, color: Color(0xFF00E676), size: 14),
                  label: const Text('🚑 Moving to your GPS', style: TextStyle(fontSize: 11)),
                  backgroundColor: const Color(0xFF161B22),
                  onPressed: () {
                    sos.sendRescueResponse(alert.senderId, "Help is on the way! Moving to your coordinates.");
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Rescue confirmation dispatched over LoRa mesh!')),
                    );
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.shield, color: Colors.cyanAccent, size: 14),
                  label: const Text('🚁 Rescue dispatched. Stay put', style: TextStyle(fontSize: 11)),
                  backgroundColor: const Color(0xFF161B22),
                  onPressed: () {
                    sos.sendRescueResponse(alert.senderId, "Rescue team dispatched. Stay at your current coordinates.");
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Rescue dispatched notification sent!')),
                    );
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.medical_services, color: Colors.redAccent, size: 14),
                  label: const Text('🩹 First aid en route', style: TextStyle(fontSize: 11)),
                  backgroundColor: const Color(0xFF161B22),
                  onPressed: () {
                    sos.sendRescueResponse(alert.senderId, "Medical supplies and first aid en route.");
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Medical assistance response sent!')),
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
