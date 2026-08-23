import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../models/tap_event.dart';

class TapHistoryList extends StatelessWidget {
  final List<TapEvent> tapHistory;
  final VoidCallback onSimulateTap;

  const TapHistoryList({
    super.key,
    required this.tapHistory,
    required this.onSimulateTap,
  });

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
                    Icon(Icons.touch_app, color: AppTheme.primaryCyan, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Tap & Wakeup History',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                OutlinedButton.icon(
                  onPressed: onSimulateTap,
                  icon: const Icon(Icons.touch_app, size: 14),
                  label: const Text('Test Tap (Start/Stop)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (tapHistory.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: const Center(
                  child: Text(
                    'No tap triggers recorded yet.\nDouble-tap the XIAO board or click "Test Tap (Start/Stop)" to toggle recording.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tapHistory.length,
                  separatorBuilder: (_, _) => const Divider(color: Color(0xFF243248), height: 8),
                  itemBuilder: (context, index) {
                    final event = tapHistory[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.primaryCyan,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Tap #${event.tapIndex}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ],
                          ),
                          Text(
                            '${event.shockMagnitude.toStringAsFixed(2)} g',
                            style: const TextStyle(
                              color: AppTheme.accentOrange,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            event.formattedTime,
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
