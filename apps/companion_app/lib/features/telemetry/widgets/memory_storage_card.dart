import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/telemetry_state.dart';

class MemoryStorageCard extends StatelessWidget {
  final TelemetryState telemetry;

  const MemoryStorageCard({super.key, required this.telemetry});

  @override
  Widget build(BuildContext context) {
    final hasData = telemetry.hasRealData;
    final usedStorage = telemetry.usedStorageBytes ?? 0;
    final totalStorage = telemetry.totalStorageBytes;
    final freeHeap = telemetry.freeHeapBytes;

    final storageFraction = (hasData && totalStorage > 0)
        ? usedStorage / totalStorage
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.sd_storage, color: AppTheme.primaryCyan, size: 22),
                SizedBox(width: 8),
                Text(
                  'Storage & Memory (LittleFS)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Storage Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Flash Storage Used:', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                Text(
                  hasData
                      ? '${Formatters.formatBytes(usedStorage)} / ${Formatters.formatBytes(totalStorage)}'
                      : '-- / --',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: storageFraction.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: const Color(0xFF243248),
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
              ),
            ),
            const SizedBox(height: 14),

            // Free Heap
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Free RAM Heap:', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                Text(
                  hasData && freeHeap != null ? Formatters.formatBytes(freeHeap) : '-- KB',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: hasData ? AppTheme.accentGreen : AppTheme.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
