import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class SyncProgressBanner extends StatelessWidget {
  final bool isSyncing;
  final double progress;
  final String currentFile;

  const SyncProgressBanner({
    super.key,
    required this.isSyncing,
    required this.progress,
    required this.currentFile,
  });

  @override
  Widget build(BuildContext context) {
    if (!isSyncing) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryCyan.withAlpha(128)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'High-Speed Wi-Fi Syncing: $currentFile',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryCyan,
                  fontSize: 13,
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
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
            ),
          ),
        ],
      ),
    );
  }
}
