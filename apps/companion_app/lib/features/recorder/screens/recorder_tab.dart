import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../groups/services/groups_repository.dart';
import '../controllers/recorder_controller.dart';
import '../widgets/interactive_waveform_editor.dart';

/// Tab 1: On-Device Voice Recorder with live waveform, timeline scrubbing, and punch-in audio overwrite.
class RecorderTab extends StatefulWidget {
  final RecorderController controller;
  final GroupsRepository groupsRepository;

  const RecorderTab({
    super.key,
    required this.controller,
    required this.groupsRepository,
  });

  @override
  State<RecorderTab> createState() => _RecorderTabState();
}

class _RecorderTabState extends State<RecorderTab> {
  final TextEditingController _titleTextController = TextEditingController();

  @override
  void dispose() {
    _titleTextController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
    return '$minutes:$seconds.$millis';
  }

  void _showSaveDialog() {
    _titleTextController.text = widget.controller.recordingTitle;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.save, color: AppTheme.primaryCyan),
            SizedBox(width: 8),
            Text('Aufnahme speichern'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleTextController,
              decoration: const InputDecoration(
                labelText: 'Titel der Sprachnotiz',
                hintText: 'Z. B. Meeting Notiz oder Tagesbericht',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            const Text('Gruppe zuweisen:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: widget.controller.selectedGroupId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Keine Gruppe (Standard)'),
                ),
                ...widget.groupsRepository.groups.map(
                  (g) => DropdownMenuItem<String?>(
                    value: g.id,
                    child: Row(
                      children: [
                        CircleAvatar(radius: 5, backgroundColor: g.color),
                        const SizedBox(width: 8),
                        Text(g.name),
                      ],
                    ),
                  ),
                ),
              ],
              onChanged: (val) {
                widget.controller.selectedGroupId = val;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              widget.controller.recordingTitle = _titleTextController.text;
              Navigator.pop(ctx);
              final rec = await widget.controller.saveRecording();
              if (mounted && rec != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Sprachnotiz "${rec.title}" erfolgreich gespeichert!'),
                    backgroundColor: AppTheme.accentGreen,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryCyan, foregroundColor: Colors.black),
            child: const Text('Speichern', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, widget.controller.recorderService, widget.groupsRepository]),
      builder: (context, _) {
        final recService = widget.controller.recorderService;
        final isRecording = recService.isRecording;
        final isPaused = recService.isPaused;
        final isIdle = recService.isIdle && widget.controller.totalDuration == Duration.zero;
        final totalDur = isRecording ? recService.elapsedDuration : widget.controller.totalDuration;
        final scrubPos = widget.controller.scrubPosition;
        final isPunchIn = widget.controller.isPunchInMode;
        final selectedGroup = widget.groupsRepository.getGroupById(widget.controller.selectedGroupId);

        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            children: [
              // Top Group & Metadata Selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ActionChip(
                    avatar: CircleAvatar(
                      radius: 6,
                      backgroundColor: selectedGroup?.color ?? AppTheme.primaryCyan,
                    ),
                    label: Text(
                      selectedGroup?.name ?? 'Gruppe wählen',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    backgroundColor: AppTheme.cardDark,
                    side: BorderSide(color: selectedGroup?.color ?? const Color(0xFF2E3E58)),
                    onPressed: () {
                      _showGroupPickerSheet();
                    },
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isRecording
                          ? AppTheme.accentRed.withAlpha(40)
                          : (isPaused ? AppTheme.accentOrange.withAlpha(40) : AppTheme.cardDark),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isRecording
                            ? AppTheme.accentRed
                            : (isPaused ? AppTheme.accentOrange : const Color(0xFF2E3E58)),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isRecording ? Icons.fiber_manual_record : (isPaused ? Icons.pause : Icons.mic_none),
                          size: 14,
                          color: isRecording
                              ? AppTheme.accentRed
                              : (isPaused ? AppTheme.accentOrange : AppTheme.textMuted),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isRecording
                              ? 'Aufnahme läuft'
                              : (isPaused ? 'Pausiert / Bearbeiten' : 'Bereit'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isRecording
                                ? AppTheme.accentRed
                                : (isPaused ? AppTheme.accentOrange : AppTheme.textMuted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Large Timer Counter
              Center(
                child: Column(
                  children: [
                    Text(
                      _formatDuration(isRecording ? recService.elapsedDuration : scrubPos),
                      style: TextStyle(
                        fontSize: 46,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'monospace',
                        color: isRecording ? AppTheme.accentRed : Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    if (!isRecording && totalDur > Duration.zero)
                      Text(
                        'Gesamtdauer: ${_formatDuration(totalDur)}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Interactive Waveform Editor (Height: 180px)
              SizedBox(
                height: 170,
                child: InteractiveWaveformEditor(
                  amplitudes: recService.liveAmplitudes,
                  totalDuration: totalDur,
                  currentPosition: scrubPos,
                  isRecording: isRecording,
                  isPaused: isPaused || widget.controller.mode == RecorderMode.scrubbing,
                  onScrub: (newPos) {
                    widget.controller.setScrubPosition(newPos);
                  },
                ),
              ),
              const SizedBox(height: 10),

              // Punch-In / Cutoff Banner
              if (isPunchIn) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.accentOrange.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.accentOrange),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.content_cut, color: AppTheme.accentOrange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Schnittpunkt bei ${_formatDuration(scrubPos)}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white),
                            ),
                            const Text(
                              'Ab hier weitersprechen & alte Spur abschneiden',
                              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => widget.controller.punchInFromCurrentPosition(),
                        icon: const Icon(Icons.mic, size: 16),
                        label: const Text('Punch-In', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accentOrange,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Main Recorder Controls Bar
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppTheme.cardDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF22324A)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Discard Button
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppTheme.accentRed, size: 26),
                      tooltip: 'Verwerfen',
                      onPressed: isIdle ? null : () => _confirmDiscard(),
                    ),

                    // Playback Preview Button
                    IconButton(
                      icon: Icon(
                        widget.controller.audioPlayer.isPlaying ? Icons.stop_circle : Icons.play_circle_fill,
                        color: AppTheme.primaryCyan,
                        size: 32,
                      ),
                      tooltip: 'Vorschau abspielen',
                      onPressed: isRecording || totalDur == Duration.zero
                          ? null
                          : () => widget.controller.togglePlaybackPreview(),
                    ),

                    // Primary Center Record / Pause Button
                    GestureDetector(
                      onTap: () {
                        if (isIdle) {
                          widget.controller.startFreshRecording();
                        } else if (isRecording) {
                          widget.controller.pauseRecording();
                        } else {
                          widget.controller.resumeRecording();
                        }
                      },
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRecording ? AppTheme.accentRed : AppTheme.primaryCyan,
                          boxShadow: [
                            BoxShadow(
                              color: (isRecording ? AppTheme.accentRed : AppTheme.primaryCyan).withAlpha(120),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          isRecording ? Icons.pause : Icons.mic,
                          color: isRecording ? Colors.white : Colors.black,
                          size: 34,
                        ),
                      ),
                    ),

                    // Rewind 5s Button
                    IconButton(
                      icon: const Icon(Icons.replay_5, color: Colors.white70, size: 26),
                      tooltip: '5 Sek. zurückspulen',
                      onPressed: isRecording || totalDur == Duration.zero
                          ? null
                          : () {
                              final newPos = scrubPos - const Duration(seconds: 5);
                              widget.controller.setScrubPosition(newPos);
                            },
                    ),

                    // Save / Checkmark Button
                    IconButton(
                      icon: const Icon(Icons.check_circle, color: AppTheme.accentGreen, size: 30),
                      tooltip: 'Speichern',
                      onPressed: isIdle ? null : _showSaveDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Audio Recording Filters & Options Card
              Card(
                color: AppTheme.cardDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF22324A)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Column(
                    children: [
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Rauschfilter (Noise Suppression)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Dämpft Hintergrundgeräusche bei der Aufnahme', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        value: recService.noiseFilterEnabled,
                        activeThumbColor: AppTheme.primaryCyan,
                        onChanged: isRecording ? null : (val) => recService.noiseFilterEnabled = val,
                      ),
                      const Divider(color: Color(0xFF1E2A3C), height: 1),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Signalton beim Fortsetzen (Piep)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Akustischer Piepton bei Pause-Ende und Schnitten', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        value: recService.beepOnResume,
                        activeThumbColor: AppTheme.primaryCyan,
                        onChanged: (val) => recService.beepOnResume = val,
                      ),
                      const Divider(color: Color(0xFF1E2A3C), height: 1),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pausen überspringen (Silence Skip)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Reduziert Sprachpausen bei langen Memos', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                        value: recService.skipSilenceEnabled,
                        activeThumbColor: AppTheme.primaryCyan,
                        onChanged: (val) => recService.skipSilenceEnabled = val,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmDiscard() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufnahme verwerfen?'),
        content: const Text('Die aktuelle Sprachaufnahme wird unwiderruflich gelöscht.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.controller.discardRecording();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            child: const Text('Verwerfen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showGroupPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gruppe für Aufnahme wählen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.clear, color: AppTheme.textMuted),
              title: const Text('Keine Gruppe'),
              trailing: widget.controller.selectedGroupId == null ? const Icon(Icons.check, color: AppTheme.primaryCyan) : null,
              onTap: () {
                widget.controller.selectedGroupId = null;
                Navigator.pop(ctx);
              },
            ),
            ...widget.groupsRepository.groups.map(
              (g) => ListTile(
                leading: CircleAvatar(radius: 8, backgroundColor: g.color),
                title: Text(g.name),
                subtitle: g.description != null ? Text(g.description!, style: const TextStyle(fontSize: 11)) : null,
                trailing: widget.controller.selectedGroupId == g.id ? const Icon(Icons.check, color: AppTheme.primaryCyan) : null,
                onTap: () {
                  widget.controller.selectedGroupId = g.id;
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
