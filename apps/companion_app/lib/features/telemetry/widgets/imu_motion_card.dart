import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/telemetry_state.dart';

class ImuMotionCard extends StatelessWidget {
  final TelemetryState telemetry;

  const ImuMotionCard({super.key, required this.telemetry});

  @override
  Widget build(BuildContext context) {
    final hasData = telemetry.hasRealData;
    final mag = telemetry.motionMagnitude ?? 1.0;
    final isShock = hasData && mag >= 1.40;

    // Intensity progress clamped between 0.0 (0g) and 1.0 (3.0g)
    final intensityProgress = (mag / 3.0).clamp(0.0, 1.0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: (isShock ? AppTheme.accentOrange : AppTheme.primaryCyan).withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isShock ? Icons.bolt : Icons.vibration,
                        color: isShock ? AppTheme.accentOrange : AppTheme.primaryCyan,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'IMU & Tap Detection',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        if (hasData)
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: AppTheme.accentGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Live Stream',
                                style: TextStyle(fontSize: 10, color: AppTheme.accentGreen, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAxisIndicator('X-Axis', telemetry.accelX, hasData),
                _buildAxisIndicator('Y-Axis', telemetry.accelY, hasData),
                _buildAxisIndicator('Z-Axis', telemetry.accelZ, hasData),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Motion Intensity:',
                      style: TextStyle(fontSize: 13, color: AppTheme.textMuted),
                    ),
                    if (isShock) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accentOrange.withAlpha(40),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.accentOrange, width: 0.8),
                        ),
                        child: const Text(
                          'SHOCK / TAP',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.accentOrange,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  hasData && telemetry.motionMagnitude != null
                      ? '${telemetry.motionMagnitude!.toStringAsFixed(2)} g'
                      : '-- g',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    fontFamily: 'monospace',
                    color: isShock ? AppTheme.accentOrange : AppTheme.primaryCyan,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: hasData ? intensityProgress : 0.0,
                minHeight: 6,
                backgroundColor: const Color(0xFF131B2A),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isShock ? AppTheme.accentOrange : AppTheme.primaryCyan,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAxisIndicator(String label, double? value, bool hasData) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF131B2A),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2E3E58)),
          ),
          child: Text(
            hasData && value != null
                ? '${value >= 0 ? "+" : ""}${value.toStringAsFixed(2)}g'
                : '--',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
