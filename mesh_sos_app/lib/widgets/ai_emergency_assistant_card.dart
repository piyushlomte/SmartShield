import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sos_provider.dart';
import '../services/ai_safety_service.dart';
import '../services/incident_journal_service.dart';
import '../models/mesh_packet.dart';
import '../screens/incident_journal_screen.dart';

class AiEmergencyAssistantCard extends StatelessWidget {
  const AiEmergencyAssistantCard({super.key});

  Color _getRiskColor(int score) {
    if (score <= 20) return const Color(0xFF00E676); // Green
    if (score <= 40) return const Color(0xFF29B6F6); // Blue
    if (score <= 60) return const Color(0xFFFFB300); // Amber
    if (score <= 80) return const Color(0xFFFF7043); // Orange
    return const Color(0xFFFF1744); // Neon Red
  }

  @override
  Widget build(BuildContext context) {
    final sosProvider = Provider.of<SosProvider>(context);
    final aiService = Provider.of<AiSafetyService>(context);
    final journal = IncidentJournalService.instance;

    final score = sosProvider.isSelfSosActive 
        ? (sosProvider.riskScore > 0 ? sosProvider.riskScore : 88)
        : (aiService.riskScore > 0 ? aiService.riskScore : sosProvider.riskScore);
    
    final confidence = sosProvider.confidenceScore > 0 ? sosProvider.confidenceScore : 92;
    final signalAnomaly = sosProvider.signalAnomalyScore > 0 ? sosProvider.signalAnomalyScore : aiService.signalAnomalyScore;
    final timeToReserve = sosProvider.timeToReserveMins > 0 ? sosProvider.timeToReserveMins : aiService.timeToReserveMins;

    final riskColor = _getRiskColor(score);
    final tierName = AiSafetyService.getRiskTierName(score);

    final reasons = aiService.getExplanationReasons(
      score: score,
      isSosActive: sosProvider.isSelfSosActive,
      isAckReceived: sosProvider.lifecycleState == LifecycleState.sosReceived || sosProvider.lifecycleState == LifecycleState.rescueAccepted,
      isRescueAccepted: sosProvider.lifecycleState == LifecycleState.rescueAccepted,
      retryCount: sosProvider.retryCount,
      batteryPct: 85,
      signalAnomaly: signalAnomaly,
      timeToReserve: timeToReserve,
      isDuress: sosProvider.lifecycleState == LifecycleState.silentCancel,
    );

    final recommendation = AiSafetyService.getActionableRecommendation(
      score: score,
      isSosActive: sosProvider.isSelfSosActive,
      isAckReceived: sosProvider.lifecycleState == LifecycleState.sosReceived,
      isRescueAccepted: sosProvider.lifecycleState == LifecycleState.rescueAccepted,
      signalAnomaly: signalAnomaly,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: riskColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: riskColor.withOpacity(0.08),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Title + Risk & Confidence Badges
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: riskColor.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.psychology_outlined, color: riskColor, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'AI Emergency Engine',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Edge Neural & Context (51 Features)',
                            style: TextStyle(color: Colors.white54, fontSize: 10),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: riskColor, width: 1),
                ),
                child: Text(
                  tierName,
                  style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Gauges: Risk Score + Confidence Metric
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Risk Severity Index', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text('$score / 100', style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: (score / 100.0).clamp(0.05, 1.0),
                        minHeight: 8,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(riskColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('Confidence', style: TextStyle(color: Colors.white54, fontSize: 10)),
                      const SizedBox(height: 2),
                      Text(
                        '$confidence%',
                        style: const TextStyle(color: Color(0xFF00E676), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Badges Row: Lifecycle State + Signal Anomaly + Battery Time-to-Reserve
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sync_alt, size: 13, color: Color(0xFF58A6FF)),
                    const SizedBox(width: 6),
                    Text(
                      sosProvider.lifecycleState.label,
                      style: const TextStyle(color: Color(0xFF58A6FF), fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (signalAnomaly > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purpleAccent),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.blur_on, size: 13, color: Colors.purpleAccent),
                      const SizedBox(width: 6),
                      Text(
                        'RF Anomaly: $signalAnomaly%',
                        style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.tealAccent.withOpacity(0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.battery_saver, size: 13, color: Colors.tealAccent),
                    const SizedBox(width: 6),
                    Text(
                      'Reserve: ~$timeToReserve min',
                      style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.w600, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // §10.3 Dead-Man's Switch Active Prompt Banner
          if (aiService.isDeadManPromptActive)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF5A1E00),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber, width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer, color: Colors.amber, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Passive Check-In Required!',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        Text(
                          'Auto-escalating to Emergency in ${aiService.deadManCountdownSeconds}s',
                          style: const TextStyle(color: Colors.amber, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    onPressed: () {
                      aiService.acknowledgeDeadManCheckIn();
                      sosProvider.sendCheckInAck();
                    },
                    child: const Text('I am Safe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // §10.8 Explainable Escalation Narratives
          const Text(
            'Explainable AI Assessment (Why?):',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          ...reasons.take(3).map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.arrow_right, size: 16, color: riskColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    r,
                    style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          )),

          const SizedBox(height: 10),

          // Actionable Recommendation Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lightbulb_outline, size: 16, color: Color(0xFFFFD600)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    recommendation,
                    style: const TextStyle(color: Colors.white, fontSize: 11, height: 1.3),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Cryptographic SHA-256 Anchor & Incident Journal Button
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.verified_user_outlined, size: 15, color: Color(0xFF58A6FF)),
                  label: Text(
                    'SHA-256 Anchor: ${journal.finalCumulativeAnchorHash.substring(0, 8).toUpperCase()}...',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF58A6FF), fontFamily: 'monospace'),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF30363D)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const IncidentJournalScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
