import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/storage_manager.dart';
import '../models/recording_item.dart';

class ClipCard extends StatelessWidget {
  final RecordingItem clip;
  final VoidCallback onPlayToggle;
  final VoidCallback onDownload;
  final Function(SyncTier tier)? onDownloadWithTier;

  const ClipCard({
    super.key,
    required this.clip,
    required this.onPlayToggle,
    required this.onDownload,
    this.onDownloadWithTier,
  });

  @override
  Widget build(BuildContext context) {
    final isSynced = clip.syncState == SyncState.synced;
    final isDownloading = clip.syncState == SyncState.downloading;
    final isFastTransfer = clip.isFastTransferRecommended;

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
                          : (isFastTransfer ? AppTheme.accentOrange : AppTheme.primaryCyan).withAlpha(40),
                  child: IconButton(
                    icon: Icon(
                      clip.isPlaying
                          ? Icons.pause
                          : (isSynced ? Icons.play_arrow : (isFastTransfer ? Icons.bolt : Icons.bluetooth_audio)),
                      color: clip.isPlaying
                          ? Colors.black
                          : (isSynced
                              ? AppTheme.primaryCyan
                              : (isFastTransfer ? AppTheme.accentOrange : AppTheme.primaryCyan)),
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
                          Expanded(
                            child: Text(
                              'Clip #${clip.id} (${clip.remoteFilename})',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          _buildStatusBadge(isSynced, isDownloading),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 4),
                              Text(
                                Formatters.formatDuration(clip.duration),
                                style: const TextStyle(
                                  color: AppTheme.primaryCyan,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.data_usage, size: 14, color: AppTheme.textMuted),
                              const SizedBox(width: 4),
                              Text(
                                Formatters.formatBytes(clip.sizeBytes),
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                          // Tier Recommendation Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isFastTransfer ? AppTheme.accentOrange : AppTheme.primaryCyan).withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: (isFastTransfer ? AppTheme.accentOrange : AppTheme.primaryCyan).withAlpha(80),
                              ),
                            ),
                            child: Text(
                              isFastTransfer ? 'Fast Transfer (Wi-Fi)' : 'BLE Auto-Sync',
                              style: TextStyle(
                                color: isFastTransfer ? AppTheme.accentOrange : AppTheme.primaryCyan,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: clip.downloadProgress,
                      minHeight: 6,
                      backgroundColor: const Color(0xFF243248),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        !isFastTransfer ? AppTheme.primaryCyan : AppTheme.accentOrange,
                      ),
                    ),
                  ),
                  if (clip.transferSpeed != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      clip.transferSpeed!,
                      style: TextStyle(
                        fontSize: 11,
                        color: !isFastTransfer ? AppTheme.primaryCyan : AppTheme.accentOrange,
                      ),
                    ),
                  ],
                ],
              ),
            ],

            // Action row if synced
            if (isSynced && clip.localWavPath != null) ...[
              const SizedBox(height: 10),
              const Divider(color: Color(0xFF243248), height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified, size: 14, color: AppTheme.accentGreen),
                      const SizedBox(width: 4),
                      Text(
                        'CRC32 Verified PCM WAV',
                        style: TextStyle(color: AppTheme.textMuted.withAlpha(200), fontSize: 11),
                      ),
                    ],
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
      child: const Text('Flash Only', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
    );
  }
}
