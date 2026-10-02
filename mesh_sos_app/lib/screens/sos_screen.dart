import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/sos_provider.dart';
import '../models/sos_alert.dart';
import '../services/location_service.dart';
import '../services/ai_safety_service.dart';
import '../widgets/ai_emergency_assistant_card.dart';

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
    final aiService = Provider.of<AiSafetyService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Beacon', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.amberAccent),
            tooltip: 'Visual SOS Strobe Beacon',
            onPressed: () => _showStrobeDialog(context),
          ),
          IconButton(
            icon: Icon(
              Icons.av_timer,
              color: aiService.isDeadManEnabled ? const Color(0xFF00E676) : Colors.white54,
            ),
            tooltip: '§10.3 Dead-Man\'s-Switch / Passive Check-In',
            onPressed: () => _showDeadManDialog(context, aiService, sosProvider),
          ),
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
          // AI Emergency Engine & Explainable Risk Assistant
          const AiEmergencyAssistantCard(),
          const SizedBox(height: 12),

          // Emergency State Indicator / Active Broadcast Card
          if (sosProvider.isSelfSosActive)
            _buildActiveSosCard(context, sosProvider)
          else
            _buildTriggerSection(context, sosProvider, locationService),

          const SizedBox(height: 24),

          // Quick Situational Triage Fast-Dispatch Templates
          const Text(
            'Quick Emergency Triage Templates',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTriageTemplateCard(
                  context,
                  sosProvider,
                  icon: Icons.medical_services_outlined,
                  color: const Color(0xFFFF5252),
                  title: 'Medical Trauma',
                  category: DistressCategory.medical,
                  presetNote: 'Severe injury / trauma. Immediate first-aid requested!',
                ),
                _buildTriageTemplateCard(
                  context,
                  sosProvider,
                  icon: Icons.terrain_outlined,
                  color: const Color(0xFFFFB74D),
                  title: 'Trapped / Rubble',
                  category: DistressCategory.trapped,
                  presetNote: 'Trapped under rubble / obstacle. Extraction needed!',
                ),
                _buildTriageTemplateCard(
                  context,
                  sosProvider,
                  icon: Icons.local_fire_department_outlined,
                  color: const Color(0xFFFF7043),
                  title: 'Fire / Hazard',
                  category: DistressCategory.fire,
                  presetNote: 'Wildfire / toxic hazard condition. Evacuation required!',
                ),
                _buildTriageTemplateCard(
                  context,
                  sosProvider,
                  icon: Icons.water_drop_outlined,
                  color: const Color(0xFF42A5F5),
                  title: 'Supplies / Water',
                  category: DistressCategory.supplies,
                  presetNote: 'Severe dehydration / critical supplies depleted!',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

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
          // Emergency Call Banner Graphic
          Container(
            height: 90,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/images/emergency_banner.png',
                  height: 70,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.phone_in_talk, color: Colors.redAccent, size: 40),
                ),
                const SizedBox(width: 14),
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OFFLINE RESCUE BEACON',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'LoRa Mesh P2P Direct Dispatch',
                      style: TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),

          GestureDetector(
            onTap: () {
              sos.triggerSos(silent: _silentMode);
            },
            child: Container(
              height: 170,
              width: 170,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => sos.cancelSos(isDuress: false),
                    icon: const Icon(Icons.check_circle_outline, color: Colors.black),
                    label: const Text('RESOLVE SOS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () => sos.cancelSos(isDuress: true),
                    icon: const Icon(Icons.security, color: Colors.amber, size: 16),
                    label: const Text('Duress Cancel', style: TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.amber),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ],
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

          // Google Maps URL & Quick Navigation Bar
          if (alert.hasValidLocation) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00E676).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.map_outlined, color: Color(0xFF00E676), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Google Maps Navigation URL:',
                          style: TextStyle(fontSize: 10, color: Colors.white54, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          alert.googleMapsUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.white70, size: 16),
                    tooltip: 'Copy Google Maps URL',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: alert.googleMapsUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Copied: ${alert.googleMapsUrl}'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],

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

  void _showDeadManDialog(BuildContext context, AiSafetyService ai, SosProvider sos) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Row(
            children: [
              Icon(Icons.av_timer, color: Color(0xFF58A6FF), size: 22),
              SizedBox(width: 10),
              Text('Dead-Man\'s Switch', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '§10.3 Passive Check-In Mode: Automatically prompts you with haptic vibration at fixed intervals. If you do not tap "I am Safe" within 60s, emergency SOS is dispatched automatically.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable Passive Check-In', style: TextStyle(color: Colors.white, fontSize: 14)),
                value: ai.isDeadManEnabled,
                activeColor: const Color(0xFF00E676),
                onChanged: (val) {
                  setModalState(() => ai.setDeadManEnabled(val));
                  sos.sendDeadManConfig(val, ai.deadManIntervalMins);
                },
              ),
              if (ai.isDeadManEnabled) ...[
                const SizedBox(height: 10),
                const Text('Check-In Interval:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [15, 30, 60].map((mins) {
                    final isSel = ai.deadManIntervalMins == mins;
                    return ChoiceChip(
                      label: Text('$mins min'),
                      selected: isSel,
                      selectedColor: const Color(0xFF00E676).withOpacity(0.3),
                      labelStyle: TextStyle(
                        color: isSel ? const Color(0xFF00E676) : Colors.white70,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (sel) {
                        if (sel) {
                          setModalState(() => ai.setDeadManInterval(mins));
                          sos.sendDeadManConfig(true, mins);
                        }
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTriageTemplateCard(
    BuildContext context,
    SosProvider sos, {
    required IconData icon,
    required Color color,
    required String title,
    required DistressCategory category,
    required String presetNote,
  }) {
    final isSelected = sos.selectedCategory == category && sos.customDistressNote == presetNote;
    return GestureDetector(
      onTap: () {
        sos.setCategory(category);
        sos.setDistressNote(presetNote);
        _noteController.text = presetNote;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Selected template: $title'),
            duration: const Duration(seconds: 1),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.25) : const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? color : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showStrobeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _EmergencyStrobeDialog(),
    );
  }
}

class _EmergencyStrobeDialog extends StatefulWidget {
  const _EmergencyStrobeDialog();

  @override
  State<_EmergencyStrobeDialog> createState() => _EmergencyStrobeDialogState();
}

class _EmergencyStrobeDialogState extends State<_EmergencyStrobeDialog> with SingleTickerProviderStateMixin {
  late AnimationController _strobeController;

  @override
  void initState() {
    super.initState();
    _strobeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _strobeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _strobeController,
      builder: (context, child) {
        final isWhite = _strobeController.value > 0.5;
        return Scaffold(
          backgroundColor: isWhite ? Colors.white : Colors.black,
          body: InkWell(
            onTap: () => Navigator.pop(context),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.flash_on,
                    size: 80,
                    color: isWhite ? Colors.black : Colors.redAccent,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'SOS VISUAL STROBE ACTIVE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isWhite ? Colors.black : Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tap anywhere on screen to exit strobe',
                    style: TextStyle(
                      color: isWhite ? Colors.black54 : Colors.white54,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
