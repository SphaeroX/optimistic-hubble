import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/models/recording_group.dart';
import '../models/dictula_recording.dart';
import '../models/recording_item.dart';

/// Card widget displaying a Dictula voice recording item with waveform preview, badges, and quick actions.
class RecordingCard extends StatelessWidget {
  final DictulaRecording recording;
  final RecordingGroup? group;
  final bool isPlaying;
  final VoidCallback onPlayToggle;
  final VoidCallback onTap;
  final VoidCallback onPinToggle;
  final VoidCallback onShareAudio;
  final VoidCallback onShareZip;
  final VoidCallback onDelete;

  const RecordingCard({
    super.key,
    required this.recording,
    this.group,
    required this.isPlaying,
    required this.onPlayToggle,
    required this.onTap,
    required this.onPinToggle,
    required this.onShareAudio,
    required this.onShareZip,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isHardware = recording.source == RecordingSource.hardware;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: recording.isPinned ? const Color(0xFF132035) : AppTheme.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: recording.isPinned
              ? AppTheme.primaryCyan.withAlpha(120)
              : const Color(0xFF223046),
          width: recording.isPinned ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Pin, Title, Source & Group Badge, Menu
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Play / Download / Progress Circle
                  GestureDetector(
                    onTap: onPlayToggle,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isPlaying
                            ? AppTheme.primaryCyan
                            : (recording.syncState == SyncState.onDevice
                                ? AppTheme.accentOrange.withAlpha(30)
                                : (isHardware ? const Color(0xFF1E3A5F) : const Color(0xFF1B283C))),
                        border: Border.all(
                          color: isPlaying
                              ? AppTheme.primaryCyan
                              : (recording.syncState == SyncState.onDevice
                                  ? AppTheme.accentOrange.withAlpha(120)
                                  : const Color(0xFF2C3E58)),
                        ),
                      ),
                      child: recording.syncState == SyncState.downloading
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan),
                              ),
                            )
                          : Icon(
                              recording.syncState == SyncState.onDevice
                                  ? Icons.bolt
                                  : (isPlaying ? Icons.pause : Icons.play_arrow),
                              color: isPlaying
                                  ? Colors.black
                                  : (recording.syncState == SyncState.onDevice
                                      ? AppTheme.accentOrange
                                      : AppTheme.primaryCyan),
                              size: 24,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Title, Date, Badges
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (recording.isPinned)
                              const Padding(
                                padding: EdgeInsets.only(right: 6),
                                child: Icon(Icons.push_pin, size: 14, color: AppTheme.primaryCyan),
                              ),
                            Expanded(
                              child: Text(
                                recording.title,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              recording.formattedDate,
                              style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '•  ${recording.formattedDuration}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.primaryCyan,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // More Options Menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20, color: AppTheme.textMuted),
                    onSelected: (val) {
                      if (val == 'pin') onPinToggle();
                      if (val == 'share_audio') onShareAudio();
                      if (val == 'share_zip') onShareZip();
                      if (val == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'pin',
                        child: Row(
                          children: [
                            Icon(
                              recording.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                              size: 18,
                              color: AppTheme.primaryCyan,
                            ),
                            const SizedBox(width: 8),
                            Text(recording.isPinned ? 'Lösen' : 'Oben anpinnen'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'share_audio',
                        child: Row(
                          children: [
                            Icon(Icons.audiotrack, size: 18, color: AppTheme.primaryCyan),
                            SizedBox(width: 8),
                            Text('Audiodatei teilen'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'share_zip',
                        child: Row(
                          children: [
                            Icon(Icons.archive, size: 18, color: AppTheme.accentOrange),
                            SizedBox(width: 8),
                            Text('Als ZIP teilen'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: AppTheme.accentRed),
                            SizedBox(width: 8),
                            Text('Löschen'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Badges & Tag Indicators Row
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  // Source Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isHardware
                          ? const Color(0xFF0D3B66).withAlpha(120)
                          : const Color(0xFF1E2E40),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isHardware ? const Color(0xFF1A659E) : const Color(0xFF2C3E58),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isHardware ? Icons.memory : Icons.phone_android,
                          size: 11,
                          color: isHardware ? AppTheme.accentOrange : AppTheme.primaryCyan,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isHardware ? 'Hardware XIAO' : 'Handy',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isHardware ? AppTheme.accentOrange : AppTheme.primaryCyan,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sync Status Badge for Hardware Recordings
                  if (isHardware && recording.syncState == SyncState.onDevice)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppTheme.accentOrange.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.accentOrange.withAlpha(100)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bolt, size: 11, color: AppTheme.accentOrange),
                          SizedBox(width: 4),
                          Text(
                            'Auf Gerät (Tippen zum Laden)',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.accentOrange),
                          ),
                        ],
                      ),
                    )
                  else if (isHardware && recording.syncState == SyncState.downloading)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryCyan.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.primaryCyan.withAlpha(100)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 9,
                            height: 9,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.primaryCyan),
                          ),
                          SizedBox(width: 5),
                          Text(
                            'Synchronisiert...',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.primaryCyan),
                          ),
                        ],
                      ),
                    )
                  else if (isHardware && recording.syncState == SyncState.synced)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.accentGreen.withAlpha(90)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline, size: 11, color: AppTheme.accentGreen),
                          SizedBox(width: 4),
                          Text(
                            'Lokal gesichert',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppTheme.accentGreen),
                          ),
                        ],
                      ),
                    ),

                  // Group Badge if assigned
                  if (group != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: group!.color.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: group!.color.withAlpha(100)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(radius: 3.5, backgroundColor: group!.color),
                          const SizedBox(width: 4),
                          Text(
                            group!.name,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: group!.color,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Transcription Badge
                  if (recording.hasTranscription)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppTheme.accentGreen.withAlpha(25),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.accentGreen.withAlpha(90)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, size: 11, color: AppTheme.accentGreen),
                          SizedBox(width: 4),
                          Text(
                            'Transkribiert',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentGreen,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Attachments & Photos Badge
                  if (recording.hasAttachments)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF24334A),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.attach_file, size: 11, color: Colors.white70),
                          const SizedBox(width: 3),
                          Text(
                            '${recording.photoPaths.length + recording.attachmentPaths.length}',
                            style: const TextStyle(fontSize: 10.5, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              // Transcription Snippet preview if available
              if (recording.hasTranscription) ...[
                const SizedBox(height: 8),
                Text(
                  recording.transcription!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
