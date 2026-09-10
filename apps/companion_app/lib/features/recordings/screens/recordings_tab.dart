import 'package:flutter/material.dart';
import '../../../core/audio/native_audio_player.dart';
import '../../../core/services/audio_share_service.dart';
import '../../../core/services/zip_export_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../ai_gemini/services/gemini_service.dart';
import '../../connection/services/ble_service.dart';
import '../../groups/services/groups_repository.dart';
import '../../recorder/controllers/recorder_controller.dart';
import '../models/dictula_recording.dart';
import '../models/recording_item.dart';
import '../services/recording_sync_manager.dart';
import '../services/recordings_repository.dart';
import '../widgets/recording_card.dart';
import '../widgets/sync_progress_banner.dart';
import 'recording_detail_sheet.dart';

/// Tab 2: Recordings list with real-time search, group filters, inline playback, and detail modal.
class RecordingsTab extends StatefulWidget {
  final RecordingsRepository repository;
  final GroupsRepository groupsRepository;
  final GeminiService geminiService;
  final NativeAudioPlayer audioPlayer;
  final RecordingSyncManager? syncManager;
  final BleService? bleService;
  final RecorderController? recorderController;
  final VoidCallback? onSwitchToRecorderTab;

  const RecordingsTab({
    super.key,
    required this.repository,
    required this.groupsRepository,
    required this.geminiService,
    required this.audioPlayer,
    this.syncManager,
    this.bleService,
    this.recorderController,
    this.onSwitchToRecorderTab,
  });

  @override
  State<RecordingsTab> createState() => _RecordingsTabState();
}

class _RecordingsTabState extends State<RecordingsTab> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedIds = <String>{};
  String? _currentlyPlayingPath;
  bool _isRefreshing = false;

  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.audioPlayer.addListener(_onPlayerStateChanged);
  }

  @override
  void dispose() {
    widget.audioPlayer.removeListener(_onPlayerStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onPlayerStateChanged() {
    if (mounted) setState(() {});
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
    });
  }

  void _toggleSelectAll(List<DictulaRecording> currentList) {
    setState(() {
      final allIds = currentList.map((r) => r.id).toSet();
      if (_selectedIds.containsAll(allIds)) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(allIds);
      }
    });
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      if (widget.syncManager != null) {
        await widget.syncManager!.fetchDeviceClips(showError: true);
      } else {
        await widget.repository.syncWithLocalStorage();
      }
    } catch (e) {
      debugPrint('[RecordingsTab] Refresh error: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _handleSyncClip(DictulaRecording rec) async {
    if (rec.hardwareClipId == null || widget.syncManager == null) return;
    final clipId = rec.hardwareClipId!;

    if (widget.bleService?.isConnected != true && widget.bleService?.isMockMode != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte zuerst oben mit dem XIAO ESP32 verbinden.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    await widget.syncManager!.downloadClip(clipId);
  }

  Future<void> _handleSyncAll() async {
    if (widget.syncManager == null) return;
    if (widget.bleService?.isConnected != true && widget.bleService?.isMockMode != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte zuerst oben mit dem XIAO ESP32 verbinden.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await widget.syncManager!.syncAllClips();
  }

  void _openDetailSheet(DictulaRecording rec) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecordingDetailSheet(
        recordingId: rec.id,
        repository: widget.repository,
        groupsRepository: widget.groupsRepository,
        geminiService: widget.geminiService,
        audioPlayer: widget.audioPlayer,
        recorderController: widget.recorderController,
        onSwitchToRecorderTab: widget.onSwitchToRecorderTab,
      ),
    );
  }

  Future<void> _handleShareZip(DictulaRecording rec) async {
    final group = widget.groupsRepository.getGroupById(rec.groupId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ZIP-Archiv wird erstellt und geteilt...'), duration: Duration(seconds: 1)),
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

  Future<void> _handleShareAudio(DictulaRecording rec) async {
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

  void _handleDelete(DictulaRecording rec) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aufnahme löschen?'),
        content: Text('Möchtest du "${rec.title}" wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (_selectedIds.contains(rec.id)) {
                setState(() => _selectedIds.remove(rec.id));
              }
              widget.repository.deleteRecording(rec.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            child: const Text('Löschen', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBatchDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$count Aufnahmen löschen?'),
        content: Text(
          count == 1
              ? 'Möchtest du die ausgewählte Aufnahme wirklich unwiderruflich löschen?'
              : 'Möchtest du die $count ausgewählten Sprachaufnahmen wirklich unwiderruflich vom Gerät löschen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
            child: Text('Löschen ($count)', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final idsToDelete = Set<String>.from(_selectedIds);
      _clearSelection();
      await widget.repository.deleteMultipleRecordings(idsToDelete);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count Aufnahme${count == 1 ? '' : 'n'} gelöscht.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[widget.repository, widget.groupsRepository];
    if (widget.syncManager != null) listenables.add(widget.syncManager!);
    if (widget.bleService != null) listenables.add(widget.bleService!);

    return AnimatedBuilder(
      animation: Listenable.merge(listenables),
      builder: (context, _) {
        final list = widget.repository.filteredRecordings;
        final groups = widget.groupsRepository.groups;
        final activeGroupId = widget.repository.filterGroupId;
        final isSyncing = widget.syncManager?.isSyncing == true;
        final pendingHwCount = list.where((r) => r.source == RecordingSource.hardware && r.syncState != SyncState.synced).length;

        final allRepoIds = widget.repository.recordings.map((r) => r.id).toSet();
        _selectedIds.retainWhere(allRepoIds.contains);

        return PopScope(
          canPop: !_isSelectionMode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _isSelectionMode) {
              _clearSelection();
            }
          },
          child: Scaffold(
            body: Column(
              children: [
                // Search & Filter Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => widget.repository.setSearchQuery(val),
                    decoration: InputDecoration(
                      hintText: 'Aufnahmen in Echtzeit suchen...',
                      hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                      prefixIcon: const Icon(Icons.search, color: AppTheme.primaryCyan, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: AppTheme.textMuted),
                              onPressed: () {
                                _searchController.clear();
                                widget.repository.setSearchQuery('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.cardDark,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF223046)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFF223046)),
                      ),
                    ),
                  ),
                ),

                // Group Filter Chips Bar
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      FilterChip(
                        selected: activeGroupId == null,
                        label: const Text('Alle Aufnahmen', style: TextStyle(fontSize: 11)),
                        backgroundColor: AppTheme.cardDark,
                        selectedColor: AppTheme.primaryCyan.withAlpha(50),
                        side: BorderSide(
                          color: activeGroupId == null ? AppTheme.primaryCyan : const Color(0xFF243248),
                        ),
                        onSelected: (_) => widget.repository.setFilterGroupId(null),
                      ),
                      const SizedBox(width: 8),
                      ...groups.map(
                        (g) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            avatar: CircleAvatar(radius: 4, backgroundColor: g.color),
                            selected: activeGroupId == g.id,
                            label: Text(g.name, style: const TextStyle(fontSize: 11)),
                            backgroundColor: AppTheme.cardDark,
                            selectedColor: g.color.withAlpha(50),
                            side: BorderSide(
                              color: activeGroupId == g.id ? g.color : const Color(0xFF243248),
                            ),
                            onSelected: (_) {
                              widget.repository.setFilterGroupId(activeGroupId == g.id ? null : g.id);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Header Toolbar: Contextual Selection Bar OR Standard Count & Refresh
                if (_isSelectionMode)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF152238),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryCyan.withAlpha(90)),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, size: 20, color: Colors.white70),
                          tooltip: 'Auswahl beenden',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: _clearSelection,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_selectedIds.length} ausgewählt',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          icon: Icon(
                            _selectedIds.length == list.length && list.isNotEmpty
                                ? Icons.deselect
                                : Icons.select_all,
                            size: 16,
                            color: AppTheme.primaryCyan,
                          ),
                          label: Text(
                            _selectedIds.length == list.length && list.isNotEmpty
                                ? 'Keine'
                                : 'Alle',
                            style: const TextStyle(fontSize: 12, color: AppTheme.primaryCyan),
                          ),
                          onPressed: () => _toggleSelectAll(list),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.accentRed),
                          tooltip: 'Ausgewählte löschen',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          onPressed: _selectedIds.isEmpty ? null : _handleBatchDelete,
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${list.length} Sprachaufnahme${list.length == 1 ? '' : 'n'}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textMuted),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          icon: _isRefreshing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan),
                                )
                              : const Icon(Icons.refresh, size: 18, color: AppTheme.primaryCyan),
                          tooltip: 'Aufnahmen aktualisieren (Controller & Speicher)',
                          onPressed: _isRefreshing ? null : _handleRefresh,
                        ),
                      ],
                    ),
                  ),

                // Pending Controller Recordings Sync Action (in separate row below)
                if (pendingHwCount > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
                    child: InkWell(
                      onTap: isSyncing ? null : _handleSyncAll,
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppTheme.accentOrange.withAlpha(25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.accentOrange.withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.bolt, size: 15, color: AppTheme.accentOrange),
                            const SizedBox(width: 6),
                            Text(
                              '$pendingHwCount neu auf Controller (Sync)',
                              style: const TextStyle(fontSize: 12, color: AppTheme.accentOrange, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Active Sync Progress Banner if syncing
                if (widget.syncManager != null && isSyncing)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: SyncProgressBanner(
                      isSyncing: isSyncing,
                      progress: widget.syncManager!.syncProgress,
                      currentFile: widget.syncManager!.currentSyncFile,
                      currentSpeed: widget.syncManager!.currentSpeed,
                    ),
                  ),

                // Recordings List with Pull-to-Refresh
                Expanded(
                  child: RefreshIndicator(
                    color: AppTheme.primaryCyan,
                    backgroundColor: AppTheme.cardDark,
                    onRefresh: _handleRefresh,
                    child: list.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                              Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.audiotrack, size: 48, color: AppTheme.textMuted.withAlpha(120)),
                                    const SizedBox(height: 12),
                                    Text(
                                      _searchController.text.isNotEmpty
                                          ? 'Keine Treffer für "${_searchController.text}"'
                                          : 'Noch keine Aufnahmen vorhanden.\n\nNimm direkt im Tab "Recorder" auf\noder synchronisiere deine XIAO ESP32 Hardware.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: list.length,
                            itemBuilder: (context, index) {
                              final rec = list[index];
                              final group = widget.groupsRepository.getGroupById(rec.groupId);
                              final isThisPlaying = widget.audioPlayer.isPlaying && _currentlyPlayingPath == rec.localWavPath;
                              final isSelected = _selectedIds.contains(rec.id);

                              return RecordingCard(
                                recording: rec,
                                group: group,
                                isPlaying: isThisPlaying,
                                isSelectionMode: _isSelectionMode,
                                isSelected: isSelected,
                                onLongPress: () => _toggleSelection(rec.id),
                                onPlayToggle: () {
                                  if (_isSelectionMode) {
                                    _toggleSelection(rec.id);
                                    return;
                                  }
                                  if (rec.syncState == SyncState.onDevice) {
                                    _handleSyncClip(rec);
                                    return;
                                  }
                                  if (isThisPlaying) {
                                    widget.audioPlayer.stop();
                                    _currentlyPlayingPath = null;
                                  } else {
                                    _currentlyPlayingPath = rec.localWavPath;
                                    widget.audioPlayer.play(rec.localWavPath);
                                  }
                                  setState(() {});
                                },
                                onTap: () {
                                  if (_isSelectionMode) {
                                    _toggleSelection(rec.id);
                                    return;
                                  }
                                  if (rec.syncState == SyncState.onDevice) {
                                    _handleSyncClip(rec);
                                  } else {
                                    _openDetailSheet(rec);
                                  }
                                },
                                onPinToggle: () => widget.repository.togglePin(rec.id),
                                onShareAudio: () => _handleShareAudio(rec),
                                onShareZip: () => _handleShareZip(rec),
                                onDelete: () => _handleDelete(rec),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
