import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SyncProgressBanner extends StatelessWidget {
  final bool isSyncing;
  final double progress;
  final String currentFile;
  final String? currentSpeed;

  const SyncProgressBanner({
    super.key,
    required this.isSyncing,
    required this.progress,
    required this.currentFile,
    this.currentSpeed,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSyncing) return const SizedBox.shrink();

    final isWifiTurbo = currentSpeed != null && currentSpeed!.contains('Turbo');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isWifiTurbo ? AppTheme.accentOrange : AppTheme.primaryCyan).withAlpha(128),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isWifiTurbo ? AppTheme.accentOrange : AppTheme.primaryCyan,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Syncing: $currentFile',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.white,
                        ),
                      ),
                      if (currentSpeed != null)
                        Text(
                          currentSpeed!,
                          style: TextStyle(
                            fontSize: 11,
                            color: isWifiTurbo ? AppTheme.accentOrange : AppTheme.primaryCyan,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isWifiTurbo ? AppTheme.accentOrange : AppTheme.primaryCyan,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF243248),
              valueColor: AlwaysStoppedAnimation<Color>(
                isWifiTurbo ? AppTheme.accentOrange : AppTheme.primaryCyan,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
