import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../ai_gemini/services/gemini_service.dart';
import '../../recorder/controllers/recorder_controller.dart';
import '../../recordings/models/dictula_recording.dart';
import '../../recordings/services/recordings_repository.dart';
import '../models/recording_group.dart';
import '../services/groups_repository.dart';

/// Tab 3: Groups and chronological voice logs with AI multi-clip synthesis.
class GroupsTab extends StatefulWidget {
  final GroupsRepository groupsRepository;
  final RecordingsRepository recordingsRepository;
  final GeminiService geminiService;
  final RecorderController? recorderController;
  final VoidCallback? onSwitchToRecorderTab;

  const GroupsTab({
    super.key,
    required this.groupsRepository,
    required this.recordingsRepository,
    required this.geminiService,
    this.recorderController,
    this.onSwitchToRecorderTab,
  });

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> {
  final List<int> _availableColors = [
    0xFF00E5FF, // Cyan
    0xFFFF9100, // Orange
    0xFF00E676, // Green
    0xFFFF5252, // Red
    0xFFD500F9, // Purple
    0xFFFFD600, // Yellow
  ];

  void _showCreateGroupDialog({RecordingGroup? groupToEdit}) {
    final nameController = TextEditingController(text: groupToEdit?.name ?? '');
    final descController = TextEditingController(text: groupToEdit?.description ?? '');
    int selectedColor = groupToEdit?.colorValue ?? _availableColors[0];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(groupToEdit != null ? Icons.edit : Icons.create_new_folder, color: AppTheme.primaryCyan),
              const SizedBox(width: 8),
              Text(groupToEdit != null ? 'Gruppe bearbeiten' : 'Neue Gruppe anlegen'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name der Gruppe / des Logs', border: OutlineInputBorder()),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: 'Beschreibung (optional)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('Farb-Akzent:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _availableColors.map((colorVal) {
                  final isSelected = selectedColor == colorVal;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = colorVal),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(colorVal),
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                      ),
                      child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.black) : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final nav = Navigator.of(ctx);
                if (groupToEdit != null) {
                  await widget.groupsRepository.updateGroup(
                    groupToEdit.copyWith(name: name, description: descController.text.trim(), colorValue: selectedColor),
                  );
                } else {
                  await widget.groupsRepository.createGroup(
                    name: name,
                    description: descController.text.trim(),
                    colorValue: selectedColor,
                  );
                }
                nav.pop();
              },
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGroupSummaryModal(RecordingGroup group, List<DictulaRecording> recordings) async {
    if (!widget.geminiService.hasApiKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte zuerst den Gemini API-Key in den Einstellungen hinterlegen.')),
      );
      return;
    }

    if (recordings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Diese Gruppe enthält noch keine Aufnahmen zum Zusammenfassen.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _GroupAiSummaryView(
        group: group,
        recordings: recordings,
        geminiService: widget.geminiService,
      ),
    );
  }

  void _recordDirectlyIntoGroup(RecordingGroup group) {
    if (widget.recorderController == null) return;
    widget.recorderController!.selectedGroupId = group.id;
    widget.onSwitchToRecorderTab?.call();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.groupsRepository, widget.recordingsRepository]),
      builder: (context, _) {
        final groups = widget.groupsRepository.groups;

        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header & Add Group Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Gruppen & Logbücher', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                        Text('${groups.length} Gruppe${groups.length == 1 ? '' : 'n'} angelegt', style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: () => _showCreateGroupDialog(),
                    icon: const Icon(Icons.add, size: 22),
                    tooltip: 'Neue Gruppe anlegen',
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primaryCyan,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              if (groups.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: const Center(
                    child: Text('Noch keine Gruppen erstellt.\nTippe auf "Neue Gruppe" um Sprachnotizen zu bündeln.'),
                  ),
                )
              else
                ...groups.map((group) {
                  final groupRecs = widget.recordingsRepository.getRecordingsForGroup(group.id);
                  final totalSec = groupRecs.fold<int>(0, (acc, r) => acc + r.duration.inSeconds);
                  final formattedTotal = '${totalSec ~/ 60}m ${totalSec % 60}s';

                  return Card(
                    margin: const EdgeInsets.only(bottom: 16),
                    color: AppTheme.cardDark,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: group.color.withAlpha(80), width: 1.2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Group Title & Actions
                          Row(
                            children: [
                              CircleAvatar(radius: 8, backgroundColor: group.color),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  group.name,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18, color: AppTheme.textMuted),
                                onPressed: () => _showCreateGroupDialog(groupToEdit: group),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.accentRed),
                                onPressed: () => widget.groupsRepository.deleteGroup(group.id),
                              ),
                            ],
                          ),
                          if (group.description != null && group.description!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(group.description!, style: const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                          ],
                          const SizedBox(height: 12),

                          // Metadata Chips
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF192537),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('${groupRecs.length} Notizen', style: const TextStyle(fontSize: 11, color: Colors.white70)),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF192537),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text('Gesamt: $formattedTotal', style: const TextStyle(fontSize: 11, color: AppTheme.primaryCyan)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Timeline Preview of Recordings
                          if (groupRecs.isNotEmpty) ...[
                            const Text('Chronologischer Verlauf (Logs):', style: TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            ...groupRecs.take(3).map(
                              (r) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    const Icon(Icons.access_time, size: 13, color: AppTheme.primaryCyan),
                                    const SizedBox(width: 6),
                                    Text(
                                      DateFormat('dd.MM HH:mm').format(r.recordedAt),
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryCyan),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        r.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12, color: Colors.white),
                                      ),
                                    ),
                                    Text(r.formattedDuration, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                                  ],
                                ),
                              ),
                            ),
                            if (groupRecs.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('+ ${groupRecs.length - 3} weitere Sprachaufnahmen', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                              ),
                            const SizedBox(height: 12),
                          ],

                          // Group Action Buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => _recordDirectlyIntoGroup(group),
                                  icon: const Icon(Icons.mic, size: 16),
                                  label: const Text('Hier aufnehmen', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: group.color,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _showGroupSummaryModal(group, groupRecs),
                                  icon: const Icon(Icons.auto_awesome, size: 16, color: AppTheme.accentGreen),
                                  label: const Text('KI-Zusammenfassung', style: TextStyle(fontSize: 11)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.accentGreen,
                                    side: const BorderSide(color: AppTheme.accentGreen),
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _GroupAiSummaryView extends StatefulWidget {
  final RecordingGroup group;
  final List<DictulaRecording> recordings;
  final GeminiService geminiService;

  const _GroupAiSummaryView({
    required this.group,
    required this.recordings,
    required this.geminiService,
  });

  @override
  State<_GroupAiSummaryView> createState() => _GroupAiSummaryViewState();
}

class _GroupAiSummaryViewState extends State<_GroupAiSummaryView> {
  bool _isLoading = true;
  String _summaryText = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateSummary();
  }

  Future<void> _generateSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final List<Map<String, dynamic>> items = widget.recordings.map((r) => {
            'timestamp': DateFormat('dd.MM.yyyy HH:mm').format(r.recordedAt),
            'title': r.title,
            'transcription': r.transcription ?? 'Keine Transkription vorhanden',
          }).toList();

      final summary = await widget.geminiService.summarizeGroupRecordings(
        groupName: widget.group.name,
        timestampedRecordings: items,
      );

      if (mounted) {
        setState(() {
          _summaryText = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.accentGreen, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('KI-Zusammenfassung: ${widget.group.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 14),
          if (_isLoading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppTheme.accentGreen),
                    SizedBox(height: 14),
                    Text('Gemini analysiert die Sprachaufnahmen chronologisch...', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.accentRed, size: 36),
                    const SizedBox(height: 8),
                    Text('Fehler: $_error', textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.accentRed, fontSize: 12)),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _generateSummary, child: const Text('Erneut versuchen')),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  _summaryText,
                  style: const TextStyle(fontSize: 13.5, height: 1.45, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
