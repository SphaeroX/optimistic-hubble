import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/telemetry_state.dart';

class ImuMotionCard extends StatelessWidget {
  final TelemetryState telemetry;

  const ImuMotionCard({super.key, required this.telemetry});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.vibration, color: AppTheme.primaryCyan, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'IMU & Tap Detection',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                Chip(
                  label: Text('${telemetry.tapCount} Taps'),
                  backgroundColor: AppTheme.primaryCyan.withAlpha(40),
                  side: const BorderSide(color: AppTheme.primaryCyan),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAxisIndicator('X-Axis', telemetry.accelX),
                _buildAxisIndicator('Y-Axis', telemetry.accelY),
                _buildAxisIndicator('Z-Axis', telemetry.accelZ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Motion Intensity:',
                  style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                ),
                Text(
                  '${telemetry.motionMagnitude.toStringAsFixed(2)} g',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryCyan,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAxisIndicator(String label, double value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E3E58)),
          ),
          child: Text(
            '${value >= 0 ? "+" : ""}${value.toStringAsFixed(2)}g',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
