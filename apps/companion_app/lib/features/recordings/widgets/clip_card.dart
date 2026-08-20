import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/storage_manager.dart';
import '../models/recording_item.dart';

class ClipCard extends StatelessWidget {
  final RecordingItem clip;
  final VoidCallback onPlayToggle;
  final VoidCallback onDownload;

  const ClipCard({
    super.key,
    required this.clip,
    required this.onPlayToggle,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isSynced = clip.syncState == SyncState.synced;
    final isDownloading = clip.syncState == SyncState.downloading;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: clip.isPlaying
              ? AppTheme.primaryCyan
              : isSynced
                  ? const Color(0xFF2E3E58)
                  : const Color(0xFF1E2838),
          width: clip.isPlaying ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                // Play / Pause Circle
                CircleAvatar(
                  radius: 24,
                  backgroundColor: clip.isPlaying
                      ? AppTheme.accentGreen
                      : isSynced
                          ? AppTheme.primaryCyan.withAlpha(40)
                          : const Color(0xFF243248),
                  child: IconButton(
                    icon: Icon(
                      clip.isPlaying
                          ? Icons.pause
                          : (isSynced ? Icons.play_arrow : Icons.cloud_download),
                      color: clip.isPlaying
                          ? Colors.black
                          : (isSynced ? AppTheme.primaryCyan : Colors.white70),
                      size: 24,
                    ),
                    onPressed: isSynced ? onPlayToggle : onDownload,
                  ),
                ),
                const SizedBox(width: 14),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Clip #${clip.id} (${clip.remoteFilename})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          _buildStatusBadge(isSynced, isDownloading),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.timer_outlined, size: 14, color: AppTheme.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            Formatters.formatDuration(clip.duration),
                            style: const TextStyle(
                              color: AppTheme.primaryCyan,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.data_usage, size: 14, color: AppTheme.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            Formatters.formatBytes(clip.sizeBytes),
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF131B2A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${clip.sampleRate ~/ 1000}kHz ADPCM',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Progress bar if downloading
            if (isDownloading) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: clip.downloadProgress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF243248),
                  valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                ),
              ),
            ],

            // Action row if synced
            if (isSynced && clip.localWavPath != null) ...[
              const SizedBox(height: 10),
              const Divider(color: Color(0xFF243248), height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Stored as standard 16-bit PCM WAV',
                    style: TextStyle(color: AppTheme.textMuted.withAlpha(180), fontSize: 11),
                  ),
                  TextButton.icon(
                    onPressed: () => LocalStorageManager.openInFileManager(),
                    icon: const Icon(Icons.folder_open, size: 16, color: AppTheme.primaryCyan),
                    label: const Text(
                      'Open Folder',
                      style: TextStyle(fontSize: 12, color: AppTheme.primaryCyan),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(bool isSynced, bool isDownloading) {
    if (isDownloading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.primaryCyan.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.primaryCyan),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primaryCyan),
            ),
            SizedBox(width: 5),
            Text('Syncing...', style: TextStyle(fontSize: 11, color: AppTheme.primaryCyan, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    if (isSynced) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.accentGreen.withAlpha(30),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.accentGreen),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: AppTheme.accentGreen),
            SizedBox(width: 4),
            Text('Synced (WAV)', style: TextStyle(fontSize: 11, color: AppTheme.accentGreen, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF243248),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('Flash Memory Only', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
    );
  }
}
