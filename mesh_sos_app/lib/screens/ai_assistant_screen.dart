import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/offline_ai_doctor_service.dart';
import '../providers/mesh_provider.dart';
import '../services/ble_service.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<TriageGuidance> _results = [];
  TriageGuidance? _selectedGuidance;

  @override
  void initState() {
    super.initState();
    _results = OfflineAiDoctorService.instance.getAllProtocols();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _results = OfflineAiDoctorService.instance.search(query);
    });
  }

  void _broadcastTriageToMesh(TriageGuidance guidance, MeshProvider meshProvider, BleService bleService) {
    meshProvider.sendMessage(
      '🚨 [AI-TRIAGE] ${guidance.loraSummary}',
      recipientId: 65535, // Broadcast
      attachLocation: true,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.emergency_share, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Broadcasted "${guidance.title}" triage report with GPS over LoRa Mesh!',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1F6FEB),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'CRITICAL':
        return const Color(0xFFFF1744);
      case 'URGENT':
        return const Color(0xFFFF9100);
      default:
        return const Color(0xFF00E676);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meshProvider = Provider.of<MeshProvider>(context);
    final bleService = Provider.of<BleService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.medical_services_outlined, color: Color(0xFF00E676)),
            SizedBox(width: 8),
            Text('Offline AI Triage Doctor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF238636).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF238636)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.offline_bolt, color: Color(0xFF00E676), size: 14),
                SizedBox(width: 4),
                Text('100% Offline AI', style: TextStyle(color: Color(0xFF00E676), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Query Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ask emergency symptom (e.g. bleeding, cpr, snake, burn)...',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF58A6FF)),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF0D1117),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),

          // 2. Quick Triage Category Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _buildQuickChip('🩸 Bleeding', 'bleed'),
                _buildQuickChip('🫀 CPR', 'cpr'),
                _buildQuickChip('🐍 Snakebite', 'snake'),
                _buildQuickChip('🦴 Fracture', 'fracture'),
                _buildQuickChip('🔥 Burns', 'burn'),
                _buildQuickChip('🪨 Rubble', 'rubble'),
                _buildQuickChip('💧 Water', 'water'),
              ],
            ),
          ),

          // 3. Guidance Cards List
          Expanded(
            child: _results.isEmpty
                ? const Center(
                    child: Text('No triage guidance matched. Try another symptom.', style: TextStyle(color: Colors.white54)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _results.length,
                    itemBuilder: (ctx, index) {
                      final item = _results[index];
                      final isExpanded = _selectedGuidance?.title == item.title;
                      final sevColor = _getSeverityColor(item.severity);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isExpanded ? sevColor : Colors.white12,
                            width: isExpanded ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          children: [
                            ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: sevColor.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  item.severity == 'CRITICAL' ? Icons.warning_rounded : Icons.health_and_safety,
                                  color: sevColor,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                item.title,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              subtitle: Text(
                                '${item.category} • ${item.severity}',
                                style: TextStyle(color: sevColor, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                              trailing: Icon(
                                isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                color: Colors.white54,
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedGuidance = isExpanded ? null : item;
                                });
                              },
                            ),

                            if (isExpanded) ...[
                              const Divider(color: Colors.white12, height: 1),
                              Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.checklist, color: Color(0xFF00E676), size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Immediate Action Steps:',
                                          style: TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ...item.immediateActions.map(
                                      (step) => Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    const Row(
                                      children: [
                                        Icon(Icons.report_problem_outlined, color: Color(0xFFFF1744), size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          'Critical Warnings & DON\'Ts:',
                                          style: TextStyle(color: Color(0xFFFF1744), fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    ...item.warnings.map(
                                      (w) => Padding(
                                        padding: const EdgeInsets.only(bottom: 4),
                                        child: Text('• $w', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: const Icon(Icons.emergency_share, size: 18),
                                        label: const Text('Broadcast Triage to LoRa Mesh', style: TextStyle(fontWeight: FontWeight.bold)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF1F6FEB),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        onPressed: () => _broadcastTriageToMesh(item, meshProvider, bleService),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickChip(String label, String query) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
        backgroundColor: const Color(0xFF21262D),
        side: const BorderSide(color: Colors.white12),
        onPressed: () {
          _searchController.text = query;
          _onSearchChanged(query);
        },
      ),
    );
  }
}
