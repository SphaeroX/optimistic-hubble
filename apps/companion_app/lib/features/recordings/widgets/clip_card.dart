import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/storage_manager.dart';
import '../models/recording_item.dart';

class ClipCard extends StatelessWidget {
  final RecordingItem clip;
  final VoidCallback onPlayToggle;
  final VoidCallback onDownload;
  final VoidCallback? onShare;
  final VoidCallback? onDeleteLocal;
  final VoidCallback? onDeleteRemote;
  final VoidCallback? onDeleteEverywhere;
  final Function(SyncTier tier)? onDownloadWithTier;
  final bool isConnectedToMcu;

  const ClipCard({
    super.key,
    required this.clip,
    required this.onPlayToggle,
    required this.onDownload,
    this.onShare,
    this.onDeleteLocal,
    this.onDeleteRemote,
    this.onDeleteEverywhere,
    this.onDownloadWithTier,
    this.isConnectedToMcu = false,
  });

  void _showDeleteDialog(BuildContext context) {
    final isSynced = clip.syncState == SyncState.synced && clip.localWavPath != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131B2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accentRed.withAlpha(40),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: AppTheme.accentRed, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Aufnahme #${clip.id} löschen',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wie möchtest du Clip #${clip.id} (${clip.remoteFilename}) löschen?',
              style: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            if (isSynced && onDeleteLocal != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.phone_android, color: AppTheme.primaryCyan),
                title: const Text('Nur lokal löschen', style: TextStyle(fontSize: 14, color: Colors.white)),
                subtitle: const Text('WAV-Datei vom Smartphone/PC entfernen', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDeleteLocal?.call();
                },
              ),
            if (onDeleteRemote != null && isConnectedToMcu)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.memory, color: AppTheme.accentOrange),
                title: const Text('Vom ESP32 Flash löschen', style: TextStyle(fontSize: 14, color: Colors.white)),
                subtitle: const Text('Aus dem internen Speicher des Geräts entfernen', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDeleteRemote?.call();
                },
              ),
            if (onDeleteEverywhere != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_forever, color: AppTheme.accentRed),
                title: const Text('Überall löschen', style: TextStyle(fontSize: 14, color: AppTheme.accentRed, fontWeight: FontWeight.bold)),
                subtitle: const Text('Sowohl lokal als auch vom Geräte-Flash löschen', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                onTap: () {
                  Navigator.pop(ctx);
                  onDeleteEverywhere?.call();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen', style: TextStyle(color: AppTheme.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleOpenFolder(BuildContext context) async {
    await LocalStorageManager.openInFileManager();
    final dirPath = await LocalStorageManager.getRecordingsDirectoryPath();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          'Speicherort: $dirPath',
          style: const TextStyle(fontSize: 12),
        ),
        action: SnackBarAction(
          label: 'Kopieren',
          textColor: AppTheme.primaryCyan,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: dirPath));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSynced = clip.syncState == SyncState.synced;
    final isDownloading = clip.syncState == SyncState.downloading;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          children: [
            Row(
              children: [
                // Play / Download Circle Action
                CircleAvatar(
                  radius: 21,
                  backgroundColor: clip.isPlaying
                      ? AppTheme.accentGreen
                      : isSynced
                          ? AppTheme.primaryCyan.withAlpha(40)
                          : AppTheme.accentOrange.withAlpha(30),
                  child: IconButton(
                    iconSize: 22,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      clip.isPlaying
                          ? Icons.pause
                          : (isSynced ? Icons.play_arrow : Icons.bolt),
                      color: clip.isPlaying
                          ? Colors.black
                          : (isSynced ? AppTheme.primaryCyan : AppTheme.accentOrange),
                    ),
                    tooltip: clip.isPlaying
                        ? 'Pause'
                        : (isSynced ? 'Abspielen' : 'WiFi Fast Transfer'),
                    onPressed: isSynced ? onPlayToggle : onDownload,
                  ),
                ),
                const SizedBox(width: 12),

                // Name & Duration/Size Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clip.remoteFilename,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, size: 13, color: AppTheme.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            Formatters.formatDuration(clip.duration),
                            style: const TextStyle(
                              color: AppTheme.primaryCyan,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('•', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                          const SizedBox(width: 6),
                          Text(
                            isSynced
                                ? '${Formatters.formatBytes(clip.sizeBytes)} (PCM)'
                                : '${Formatters.formatBytes(clip.sizeBytes)} (Gerät)',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Status Badge
                _buildStatusBadge(isSynced, isDownloading),

                const SizedBox(width: 4),

                // 3-Dots Action Menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: AppTheme.textMuted, size: 20),
                  tooltip: 'Optionen',
                  color: const Color(0xFF131B2A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFF243248)),
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case 'share':
                        onShare?.call();
                        break;
                      case 'folder':
                        _handleOpenFolder(context);
                        break;
                      case 'download':
                        onDownload();
                        break;
                      case 'delete':
                        _showDeleteDialog(context);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (isSynced && onShare != null)
                      const PopupMenuItem<String>(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Icons.share, color: AppTheme.accentGreen, size: 18),
                            SizedBox(width: 10),
                            Text('Teilen', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    if (isSynced)
                      const PopupMenuItem<String>(
                        value: 'folder',
                        child: Row(
                          children: [
                            Icon(Icons.folder_open, color: AppTheme.primaryCyan, size: 18),
                            SizedBox(width: 10),
                            Text('Speicherort öffnen', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    if (!isSynced)
                      const PopupMenuItem<String>(
                        value: 'download',
                        child: Row(
                          children: [
                            Icon(Icons.bolt, color: AppTheme.accentOrange, size: 18),
                            SizedBox(width: 10),
                            Text('WiFi Fast Transfer', style: TextStyle(color: Colors.white, fontSize: 13)),
                          ],
                        ),
                      ),
                    const PopupMenuDivider(height: 8),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: AppTheme.accentRed, size: 18),
                          SizedBox(width: 10),
                          Text('Löschen...', style: TextStyle(color: AppTheme.accentRed, fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Progress bar if downloading
            if (isDownloading) ...[
              const SizedBox(height: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: clip.downloadProgress,
                      minHeight: 5,
                      backgroundColor: const Color(0xFF243248),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryCyan),
                    ),
                  ),
                  if (clip.transferSpeed != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      clip.transferSpeed!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.primaryCyan,
                      ),
                    ),
                  ],
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
            Text('Lokal', style: TextStyle(fontSize: 11, color: AppTheme.accentGreen, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF243248),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF384C6C)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.memory, size: 12, color: AppTheme.accentOrange),
          SizedBox(width: 4),
          Text('Auf Gerät', style: TextStyle(fontSize: 11, color: AppTheme.accentOrange, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

