import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/audio_clip.dart';

class ClipListItem extends StatelessWidget {
  final AudioClip clip;
  final VoidCallback onPlayToggle;
  final VoidCallback? onShare;

  const ClipListItem({
    super.key,
    required this.clip,
    required this.onPlayToggle,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final isSynced = clip.syncStatus == SyncStatus.synced;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Play/Pause button
            CircleAvatar(
              radius: 22,
              backgroundColor: clip.isPlaying
                  ? AppTheme.accentGreen
                  : isSynced
                      ? AppTheme.primaryCyan.withAlpha(51)
                      : const Color(0xFF243248),
              child: IconButton(
                icon: Icon(
                  clip.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: clip.isPlaying ? Colors.black : (isSynced ? AppTheme.primaryCyan : AppTheme.textMuted),
                  size: 20,
                ),
                onPressed: onPlayToggle,
              ),
            ),
            const SizedBox(width: 14),

            // Clip details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clip.filename,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        Formatters.formatDuration(clip.duration),
                        style: const TextStyle(
                          color: AppTheme.primaryCyan,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        clip.isSynced
                            ? '${Formatters.formatBytes(clip.sizeBytes)} (PCM)'
                            : '${Formatters.formatBytes(clip.sizeBytes)} (Gerät)',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '16kHz ADPCM',
                        style: TextStyle(
                          color: AppTheme.textMuted.withAlpha(180),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            if (isSynced && onShare != null)
              IconButton(
                icon: const Icon(Icons.share, color: AppTheme.primaryCyan, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Audiodatei teilen (WhatsApp, etc.)',
                onPressed: onShare,
              ),

            // Sync Status Indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isSynced ? AppTheme.accentGreen.withAlpha(30) : AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSynced ? AppTheme.accentGreen : const Color(0xFF2E3E58),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isSynced ? Icons.cloud_done : Icons.cloud_outlined,
                    size: 14,
                    color: isSynced ? AppTheme.accentGreen : AppTheme.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isSynced ? 'Synced' : 'On Flash',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSynced ? AppTheme.accentGreen : AppTheme.textMuted,
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
}
