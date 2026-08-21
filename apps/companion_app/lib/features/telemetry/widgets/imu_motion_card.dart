import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/telemetry_state.dart';

class ImuMotionCard extends StatelessWidget {
  final TelemetryState telemetry;

  const ImuMotionCard({super.key, required this.telemetry});

  @override
  Widget build(BuildContext context) {
    final hasData = telemetry.hasRealData;
    final double mag = telemetry.motionMagnitude ?? 1.0;
    // Dynamic shock/movement component relative to 1.0g gravity
    final double dynamicShock = (mag - 1.0).abs();
    final bool isMoving = dynamicShock > 0.08;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.vibration,
                      color: isMoving ? AppTheme.accentGreen : AppTheme.primaryCyan,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'IMU & Tap Detection',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryCyan.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryCyan),
                  ),
                  child: Text(
                    '${telemetry.tapCount} Taps',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryCyan,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Real-time 3-Axis Readout Grid
            Row(
              children: [
                Expanded(child: _buildAxisIndicator('X-Axis (Pitch)', telemetry.accelX, hasData, Colors.blueAccent)),
                const SizedBox(width: 8),
                Expanded(child: _buildAxisIndicator('Y-Axis (Roll)', telemetry.accelY, hasData, Colors.orangeAccent)),
                const SizedBox(width: 8),
                Expanded(child: _buildAxisIndicator('Z-Axis (Yaw/G)', telemetry.accelZ, hasData, AppTheme.accentGreen)),
              ],
            ),
            const SizedBox(height: 14),

            // Motion Magnitude Bar & Indicator
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF131B2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF243248)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isMoving ? AppTheme.accentGreen : AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isMoving ? 'Sensor Moving' : 'Resting (1.0g Gravity)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isMoving ? AppTheme.accentGreen : AppTheme.textMuted,
                              fontWeight: isMoving ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        hasData ? '${mag.toStringAsFixed(2)} g' : '-- g',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'monospace',
                          color: isMoving ? AppTheme.accentGreen : AppTheme.primaryCyan,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: hasData ? (mag / 3.0).clamp(0.0, 1.0) : 0.0,
                      minHeight: 6,
                      backgroundColor: const Color(0xFF1D283A),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isMoving ? AppTheme.accentGreen : AppTheme.primaryCyan,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAxisIndicator(String label, double? value, bool hasData, Color accentColor) {
    final double v = value ?? 0.0;
    // Normalized value (-2.0g to +2.0g) -> 0.0 to 1.0 centered at 0.5
    final double normalized = ((v + 2.0) / 4.0).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF243248)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            hasData && value != null
                ? '${value >= 0 ? "+" : ""}${value.toStringAsFixed(2)}g'
                : '--',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: hasData ? normalized : 0.5,
              minHeight: 4,
              backgroundColor: const Color(0xFF1D283A),
              valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            ),
          ),
        ],
      ),
    );
  }
}
