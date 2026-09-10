import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import '../../../core/audio/native_audio_player.dart';
import '../../../core/services/audio_share_service.dart';
import '../../../core/services/zip_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../ai_gemini/services/gemini_service.dart';
import '../../ai_gemini/widgets/gemini_chat_view.dart';
import '../../groups/services/groups_repository.dart';
import '../../recorder/controllers/recorder_controller.dart';
import '../models/dictula_recording.dart';
import '../services/recordings_repository.dart';

/// Full-featured bottom sheet modal for inspecting, editing, attaching photos/files, transcribing with Gemini, chatting, and exporting ZIP archives.
class RecordingDetailSheet extends StatefulWidget {
  final String recordingId;
  final RecordingsRepository repository;
  final GroupsRepository groupsRepository;
  final GeminiService geminiService;
  final NativeAudioPlayer audioPlayer;
  final RecorderController? recorderController;
  final VoidCallback? onSwitchToRecorderTab;

  const RecordingDetailSheet({
    super.key,
    required this.recordingId,
    required this.repository,
    required this.groupsRepository,
    required this.geminiService,
    required this.audioPlayer,
    this.recorderController,
    this.onSwitchToRecorderTab,
  });

  @override
  State<RecordingDetailSheet> createState() => _RecordingDetailSheetState();
}

class _RecordingDetailSheetState extends State<RecordingDetailSheet> with SingleTickerProviderStateMixin {
  late TabController _aiTabController;
  bool _isTranscribing = false;
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _aiTabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _aiTabController.dispose();
    super.dispose();
  }

  DictulaRecording? get _recording => widget.repository.getRecordingById(widget.recordingId);

  Future<void> _handleRename() async {
    final rec = _recording;
    if (rec == null) return;

    final controller = TextEditingController(text: rec.title);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufnahme umbenennen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Titel', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty) {
      await widget.repository.renameRecording(rec.id, newName);
    }
  }

  Future<void> _handleAttachPhoto(ImageSource source) async {
    final rec = _recording;
    if (rec == null) return;

    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (picked != null) {
        await widget.repository.addPhoto(rec.id, picked.path);
      }
    } catch (e) {
      debugPrint('[RecordingDetailSheet] Error picking image: $e');
    }
  }

  Future<void> _handleAttachFile() async {
    final rec = _recording;
    if (rec == null) return;

    try {
      final List<PlatformFile> pickedFiles = await FilePicker.pickFiles();
      for (final file in pickedFiles) {
        if (file.path != null) {
          await widget.repository.addAttachment(rec.id, file.path!);
        }
      }
    } catch (e) {
      debugPrint('[RecordingDetailSheet] Error picking file: $e');
    }
  }

  Future<void> _handleTranscribe() async {
    final rec = _recording;
    if (rec == null || _isTranscribing) return;

    if (!widget.geminiService.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst den Gemini API-Key in den Einstellungen hinterlegen.')),
      );
      return;
    }

    setState(() => _isTranscribing = true);
    try {
      final text = await widget.geminiService.transcribeAudio(audioPath: rec.localWavPath);
      await widget.repository.updateTranscription(rec.id, text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transkription mit Gemini erfolgreich abgeschlossen!'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transkriptionsfehler: $e'), backgroundColor: AppTheme.accentRed),
        );
      }
    } finally {
      if (mounted) setState(() => _isTranscribing = false);
    }
  }

  Future<void> _handleExportZip() async {
    final rec = _recording;
    if (rec == null) return;

    final group = widget.groupsRepository.getGroupById(rec.groupId);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ZIP-Archiv wird gepackt und geteilt...'), duration: Duration(seconds: 1)),
    );

    final success = await ZipExportService.exportAndShareZip(
      title: rec.title,
      recordedAt: rec.recordedAt,
      duration: rec.duration,
      audioPath: rec.localWavPath,
      transcription: rec.transcription,
      groupName: group?.name,
      photoPaths: rec.photoPaths,
      attachmentPaths: rec.attachmentPaths,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fehler beim Exportieren des ZIP-Archivs.')),
      );
    }
  }

  Future<void> _handleShareAudio() async {
    final rec = _recording;
    if (rec == null) return;

    final result = await AudioShareService.shareAudio(
      filePath: rec.localWavPath,
      title: rec.title,
    );

    if (!result.success && mounted && result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage!),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
  }

  void _handleContinueRecording() {
    final rec = _recording;
    if (rec == null || widget.recorderController == null) return;

    Navigator.pop(context);
    widget.recorderController!.recordingTitle = '${rec.title} (Fortsetzung)';
    widget.recorderController!.selectedGroupId = rec.groupId;
    widget.onSwitchToRecorderTab?.call();
  }

  void _handleDelete() {
    final rec = _recording;
    if (rec == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufnahme löschen?'),
        content: Text('Möchtest du "${rec.title}" wirklich dauerhaft löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              widget.repository.deleteRecording(rec.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rec = _recording;
    if (rec == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('Aufnahme nicht gefunden.')),
      );
    }

    final group = widget.groupsRepository.getGroupById(rec.groupId);
    final isPlaying = widget.audioPlayer.isPlaying;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0C121D),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Top drag pill
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E3E58),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Scrollable content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(18),
                  children: [
                    // Title, Rename, and Header Info
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (rec.isPinned)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(Icons.push_pin, size: 16, color: AppTheme.primaryCyan),
                                    ),
                                  Expanded(
                                    child: Text(
                                      rec.title,
                                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 18, color: AppTheme.primaryCyan),
                                    tooltip: 'Titel bearbeiten',
                                    onPressed: _handleRename,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${rec.formattedDate}  •  ${rec.formattedDuration}  •  ${Formatters.formatBytes(rec.fileSizeBytes)}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Source & Group Badges Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: rec.source == RecordingSource.hardware
                                ? const Color(0xFF0D3B66)
                                : const Color(0xFF1E2E40),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                rec.source == RecordingSource.hardware ? Icons.memory : Icons.phone_android,
                                size: 12,
                                color: rec.source == RecordingSource.hardware ? AppTheme.accentOrange : AppTheme.primaryCyan,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                rec.source == RecordingSource.hardware ? 'Hardware XIAO' : 'Handy Aufnahme',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: rec.source == RecordingSource.hardware ? AppTheme.accentOrange : AppTheme.primaryCyan,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ActionChip(
                          avatar: CircleAvatar(radius: 5, backgroundColor: group?.color ?? Colors.grey),
                          label: Text(group?.name ?? 'Gruppe zuweisen', style: const TextStyle(fontSize: 11)),
                          backgroundColor: AppTheme.cardDark,
                          onPressed: () => _showChangeGroupDialog(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Audio Player Card
                    Card(
                      color: AppTheme.cardDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFF243248)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                ElevatedButton(
                                  onPressed: () {
                                    if (isPlaying) {
                                      widget.audioPlayer.stop();
                                    } else {
                                      widget.audioPlayer.play(rec.localWavPath);
                                    }
                                    setState(() {});
                                  },
                                  style: ElevatedButton.styleFrom(
                                    shape: const CircleBorder(),
                                    padding: const EdgeInsets.all(14),
                                    backgroundColor: AppTheme.primaryCyan,
                                    foregroundColor: Colors.black,
                                  ),
                                  child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 24),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isPlaying ? 'Wiedergabe läuft...' : 'Bereit zum Abspielen',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        rec.formattedDuration,
                                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _handleContinueRecording,
                                  icon: const Icon(Icons.replay, size: 16),
                                  label: const Text('Weiterführen', style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.accentGreen,
                                    side: const BorderSide(color: AppTheme.accentGreen),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Attachments Section: Photos & Documents
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Fotos & Anhänge', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.camera_alt, color: AppTheme.primaryCyan, size: 20),
                              tooltip: 'Foto aufnehmen',
                              onPressed: () => _handleAttachPhoto(ImageSource.camera),
                            ),
                            IconButton(
                              icon: const Icon(Icons.photo_library, color: AppTheme.primaryCyan, size: 20),
                              tooltip: 'Aus Galerie wählen',
                              onPressed: () => _handleAttachPhoto(ImageSource.gallery),
                            ),
                            IconButton(
                              icon: const Icon(Icons.attach_file, color: AppTheme.primaryCyan, size: 20),
                              tooltip: 'Datei anhängen',
                              onPressed: _handleAttachFile,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Photos Horizontal Preview
                    if (rec.photoPaths.isNotEmpty)
                      SizedBox(
                        height: 90,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: rec.photoPaths.length,
                          separatorBuilder: (context, index) => const SizedBox(width: 8),
                          itemBuilder: (ctx, idx) {
                            final photoPath = rec.photoPaths[idx];
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(photoPath),
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      width: 90,
                                      height: 90,
                                      color: const Color(0xFF1B283C),
                                      child: const Icon(Icons.broken_image, color: AppTheme.textMuted),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () => widget.repository.removePhoto(rec.id, photoPath),
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Colors.black87,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.close, size: 14, color: Colors.white),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                    // Attachments List
                    if (rec.attachmentPaths.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...rec.attachmentPaths.map(
                        (path) => Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          color: const Color(0xFF131D2D),
                          child: ListTile(
                            dense: true,
                            leading: const Icon(Icons.insert_drive_file, color: AppTheme.primaryCyan, size: 20),
                            title: Text(path.split(Platform.pathSeparator).last, style: const TextStyle(fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.accentRed),
                              onPressed: () => widget.repository.removeAttachment(rec.id, path),
                            ),
                            onTap: () => OpenFile.open(path),
                          ),
                        ),
                      ),
                    ],

                    if (rec.photoPaths.isEmpty && rec.attachmentPaths.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101724),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF1E2B3E)),
                        ),
                        child: const Center(
                          child: Text(
                            'Keine Fotos oder Dokumente angehängt.\nKamera- oder Büroklammer-Symbol antippen zum Hinzufügen.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ),
                      ),

                    const SizedBox(height: 14),

                    // AI Transkript & Chat Container
                    Container(
                      height: 380,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1622),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF22324A)),
                      ),
                      child: Column(
                        children: [
                          TabBar(
                            controller: _aiTabController,
                            indicatorColor: AppTheme.primaryCyan,
                            tabs: const [
                              Tab(icon: Icon(Icons.text_snippet_outlined, size: 18), text: 'Transkript'),
                              Tab(icon: Icon(Icons.chat_outlined, size: 18), text: 'KI-Chat'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              controller: _aiTabController,
                              children: [
                                // Tab 1: Transkript Text
                                rec.hasTranscription
                                    ? Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.end,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.copy, size: 18, color: AppTheme.primaryCyan),
                                                  tooltip: 'Transkript kopieren',
                                                  onPressed: () {
                                                    Clipboard.setData(ClipboardData(text: rec.transcription!));
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('Transkript kopiert!')),
                                                    );
                                                  },
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.refresh, size: 18, color: AppTheme.primaryCyan),
                                                  tooltip: 'Erneut transkribieren',
                                                  onPressed: _handleTranscribe,
                                                ),
                                              ],
                                            ),
                                            Expanded(
                                              child: SingleChildScrollView(
                                                child: SelectableText(
                                                  rec.transcription!,
                                                  style: const TextStyle(fontSize: 13, height: 1.45, color: Colors.white),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            const Icon(Icons.mic_none, size: 36, color: AppTheme.textMuted),
                                            const SizedBox(height: 8),
                                            const Text('Noch keine Transkription vorhanden.', style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                                            const SizedBox(height: 10),
                                            ElevatedButton.icon(
                                              onPressed: _handleTranscribe,
                                              icon: const Icon(Icons.auto_awesome, size: 16),
                                              label: const Text('Jetzt transkribieren'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppTheme.accentGreen,
                                                foregroundColor: Colors.black,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                // Tab 2: Gemini Chat
                                GeminiChatView(
                                  recording: rec,
                                  groupName: group?.name,
                                  geminiService: widget.geminiService,
                                  repository: widget.repository,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Action Buttons Row: Pin, Audio Share, ZIP Export
                    Row(
                      children: [
                        IconButton.outlined(
                          onPressed: () => widget.repository.togglePin(rec.id),
                          icon: Icon(
                            rec.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                            color: AppTheme.primaryCyan,
                            size: 19,
                          ),
                          tooltip: rec.isPinned ? 'Oben lösen' : 'Oben anpinnen',
                          style: IconButton.styleFrom(
                            side: const BorderSide(color: AppTheme.primaryCyan),
                            padding: const EdgeInsets.all(12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _handleShareAudio,
                            icon: const Icon(Icons.share, color: Colors.black, size: 17),
                            label: const Text('Audio teilen', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black, fontSize: 13)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryCyan,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _handleExportZip,
                            icon: const Icon(Icons.archive, color: AppTheme.accentOrange, size: 17),
                            label: const Text('Als ZIP', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accentOrange, fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.accentOrange),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Delete Button
                    Center(
                      child: TextButton.icon(
                        onPressed: _handleDelete,
                        icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed, size: 18),
                        label: const Text('Aufnahme löschen', style: TextStyle(color: AppTheme.accentRed, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showChangeGroupDialog() {
    final rec = _recording;
    if (rec == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardDark,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gruppe für Aufnahme zuweisen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.clear, color: AppTheme.textMuted),
              title: const Text('Keine Gruppe'),
              trailing: rec.groupId == null ? const Icon(Icons.check, color: AppTheme.primaryCyan) : null,
              onTap: () {
                widget.repository.setGroup(rec.id, null);
                Navigator.pop(ctx);
              },
            ),
            ...widget.groupsRepository.groups.map(
              (g) => ListTile(
                leading: CircleAvatar(radius: 8, backgroundColor: g.color),
                title: Text(g.name),
                trailing: rec.groupId == g.id ? const Icon(Icons.check, color: AppTheme.primaryCyan) : null,
                onTap: () {
                  widget.repository.setGroup(rec.id, g.id);
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
