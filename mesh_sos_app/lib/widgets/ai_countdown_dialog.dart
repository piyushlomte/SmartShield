import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/ai_safety_service.dart';

class AiCountdownOverlay extends StatelessWidget {
  const AiCountdownOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final aiService = Provider.of<AiSafetyService>(context);

    if (!aiService.isCountdownActive) {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withOpacity(0.88),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.redAccent, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withOpacity(0.5),
                blurRadius: 30,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.psychology, color: Colors.redAccent, size: 28),
                  SizedBox(width: 8),
                  Text(
                    'AI SAFETY ENGINE ALERT',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'High-G Impact & Inactivity Detected!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI Anomaly Confidence: ${aiService.riskScore}%',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),

              // Glowing Countdown Circle
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 120,
                    width: 120,
                    child: CircularProgressIndicator(
                      value: aiService.countdownSeconds / 10.0,
                      strokeWidth: 8,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${aiService.countdownSeconds}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'SECONDS',
                        style: TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 1),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Text(
                'Auto-dispatching LoRa Emergency SOS if no response...',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 24),

              // Big Cancel Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    aiService.cancelCountdown();
                  },
                  icon: const Icon(Icons.check_circle_outline, color: Colors.black, size: 24),
                  label: const Text(
                    "I'M OK — CANCEL SOS",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
