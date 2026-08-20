import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/telemetry_state.dart';

class BatteryGaugeCard extends StatelessWidget {
  final TelemetryState telemetry;

  const BatteryGaugeCard({super.key, required this.telemetry});

  @override
  Widget build(BuildContext context) {
    final percent = telemetry.batteryPercent;
    final color = percent > 50
        ? AppTheme.accentGreen
        : percent > 20
            ? AppTheme.accentOrange
            : AppTheme.accentRed;

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
                    Icon(
                      telemetry.isCharging ? Icons.battery_charging_full : Icons.battery_std,
                      color: color,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Battery & Power',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                Text(
                  Formatters.formatVoltage(telemetry.batteryVoltage),
                  style: const TextStyle(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: percent / 100.0,
                      minHeight: 12,
                      backgroundColor: const Color(0xFF243248),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              telemetry.isCharging ? 'Status: Charging via USB-C' : 'Status: Operating on LiPo Battery',
              style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
