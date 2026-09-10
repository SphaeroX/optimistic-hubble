import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/audio/audio_editor_service.dart';
import '../../../core/utils/storage_manager.dart';
import '../../ai_gemini/services/gemini_service.dart';
import '../models/dictula_recording.dart';
import '../models/recording_item.dart';

/// Central repository managing all local and hardware-imported voice recordings in Dictula.
class RecordingsRepository with ChangeNotifier {
  final List<DictulaRecording> _recordings = [];
  String _searchQuery = '';
  String? _filterGroupId;
  bool _isLoaded = false;

  List<DictulaRecording> get recordings => List.unmodifiable(_recordings);
  String get searchQuery => _searchQuery;
  String? get filterGroupId => _filterGroupId;
  bool get isLoaded => _isLoaded;

  /// Returns recordings filtered by search query and group, ordered by Pinned first, then newest.
  List<DictulaRecording> get filteredRecordings {
    return _recordings.where((rec) {
      if (_filterGroupId != null && rec.groupId != _filterGroupId) {
        return false;
      }
      if (_searchQuery.trim().isEmpty) return true;

      final query = _searchQuery.toLowerCase();
      final titleMatch = rec.title.toLowerCase().contains(query);
      final transMatch = (rec.transcription ?? '').toLowerCase().contains(query);
      final dateMatch = rec.formattedDate.toLowerCase().contains(query);
      return titleMatch || transMatch || dateMatch;
    }).toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) {
          return a.isPinned ? -1 : 1;
        }
        return b.recordedAt.compareTo(a.recordedAt);
      });
  }

  RecordingsRepository() {
    loadRecordings();
  }

  Future<File> _getStorageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/dictula_recordings.json');
  }

  Future<void> loadRecordings() async {
    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _recordings.clear();
        _recordings.addAll(jsonList.map((j) => DictulaRecording.fromJson(j as Map<String, dynamic>)));
      } else {
        // Also scan local disk for any preexisting WAV recordings in storage
        await syncWithLocalStorage();
      }
    } catch (e) {
      debugPrint('[RecordingsRepository] Error loading recordings: $e');
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  /// Scans the local recordings directory on disk and imports any WAV files not yet in the repository.
  Future<void> syncWithLocalStorage() async {
    try {
      final dirPath = await LocalStorageManager.getRecordingsDirectoryPath();
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;

      bool changed = false;
      final entities = await dir.list().toList();
      for (final entity in entities) {
        if (entity is File && entity.path.toLowerCase().endsWith('.wav')) {
          final existing = _recordings.any((r) => r.localWavPath == entity.path);
          if (!existing) {
            final stat = await entity.stat();
            final int size = stat.size;
            final double durSec = size > 44 ? ((size - 44) / 32000.0) : 0.0;
            final name = entity.uri.pathSegments.last;

            int? clipId;
            final match = RegExp(r'clip_(\d+)').firstMatch(name);
            if (match != null) {
              clipId = int.tryParse(match.group(1)!);
            }

            final String title = clipId != null
                ? 'Hardware Aufnahme #${clipId.toString().padLeft(3, '0')}'
                : 'Sprachnotiz ${DateFormat('dd.MM.yyyy HH:mm').format(stat.modified)}';
            final String id = clipId != null
                ? 'hw_${clipId}_${stat.modified.millisecondsSinceEpoch}'
                : 'rec_${stat.modified.millisecondsSinceEpoch}';

            final waveform = await AudioEditorService.extractWaveformPoints(entity);

            _recordings.insert(0, DictulaRecording(
              id: id,
              title: title,
              localWavPath: entity.path,
              duration: Duration(milliseconds: (durSec * 1000).round()),
              fileSizeBytes: size,
              recordedAt: stat.modified,
              source: clipId != null ? RecordingSource.hardware : RecordingSource.phone,
              hardwareClipId: clipId,
              syncState: SyncState.synced,
              waveformSamples: waveform,
            ));
            changed = true;
          }
        }
      }
      if (changed) {
        await _save();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[RecordingsRepository] Error syncing with local storage: $e');
    }
  }

  /// Registers or synchronizes pending hardware clips detected on the MCU via BLE telemetry.
  void registerPendingHardwareClips(List<RecordingItem> hwClips) {
    bool changed = false;
    for (final clip in hwClips) {
      final existingIndex = _recordings.indexWhere(
        (r) => (r.source == RecordingSource.hardware &&
                r.syncState != SyncState.synced &&
                r.hardwareClipId == clip.id) ||
            (clip.localWavPath != null &&
                clip.localWavPath!.isNotEmpty &&
                r.localWavPath == clip.localWavPath),
      );

      if (existingIndex == -1) {
        final title = 'Hardware Aufnahme #${clip.id.toString().padLeft(3, '0')}';
        final newRec = DictulaRecording(
          id: 'hw_${clip.id}_${clip.recordedAt.millisecondsSinceEpoch}',
          title: title,
          localWavPath: clip.localWavPath ?? '',
          duration: clip.duration,
          fileSizeBytes: clip.sizeBytes,
          recordedAt: clip.recordedAt,
          source: RecordingSource.hardware,
          hardwareClipId: clip.id,
          syncState: clip.syncState,
        );
        _recordings.insert(0, newRec);
        changed = true;
      } else {
        final existing = _recordings[existingIndex];
        if (existing.syncState != clip.syncState ||
            (clip.localWavPath != null && existing.localWavPath != clip.localWavPath)) {
          _recordings[existingIndex] = existing.copyWith(
            syncState: clip.syncState,
            localWavPath: clip.localWavPath ?? existing.localWavPath,
            duration: clip.duration.inMilliseconds > 0 ? clip.duration : existing.duration,
            fileSizeBytes: clip.sizeBytes > 0 ? clip.sizeBytes : existing.fileSizeBytes,
          );
          changed = true;
        }
      }
    }
    if (changed) {
      _save();
      notifyListeners();
    }
  }

  /// Removes unsynced pending hardware clips whose ID is no longer present on device.
  void pruneUnsyncedHardwareClips(int totalClipsOnDevice) {
    bool changed = false;
    _recordings.removeWhere((r) {
      if (r.source == RecordingSource.hardware && r.syncState != SyncState.synced) {
        if (r.hardwareClipId == null || r.hardwareClipId! > totalClipsOnDevice || totalClipsOnDevice == 0) {
          changed = true;
          return true;
        }
      }
      return false;
    });
    if (changed) {
      _save();
      notifyListeners();
    }
  }

  Future<void> _save() async {
    try {
      final file = await _getStorageFile();
      final jsonList = _recordings.map((r) => r.toJson()).toList();
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonList));
    } catch (e) {
      debugPrint('[RecordingsRepository] Error saving recordings: $e');
    }
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setFilterGroupId(String? groupId) {
    _filterGroupId = groupId;
    notifyListeners();
  }

  /// Adds a new phone recording and persists it.
  Future<DictulaRecording> addPhoneRecording({
    required String filePath,
    required Duration duration,
    String? customTitle,
    String? groupId,
    List<double>? waveform,
  }) async {
    final file = File(filePath);
    final int size = await file.exists() ? await file.length() : 0;
    final now = DateTime.now();
    final String defaultTitle = 'Sprachnotiz ${DateFormat('dd.MM.yyyy HH:mm').format(now)}';
    final String id = 'rec_${now.millisecondsSinceEpoch}';

    final points = waveform ?? (await AudioEditorService.extractWaveformPoints(file));

    final recording = DictulaRecording(
      id: id,
      title: (customTitle != null && customTitle.trim().isNotEmpty) ? customTitle.trim() : defaultTitle,
      localWavPath: filePath,
      duration: duration,
      fileSizeBytes: size,
      recordedAt: now,
      groupId: groupId,
      source: RecordingSource.phone,
      waveformSamples: points,
    );

    _recordings.insert(0, recording);
    await _save();
    notifyListeners();
    return recording;
  }

  /// Imports or updates a hardware recording synced from the XIAO ESP32.
  Future<DictulaRecording> importHardwareClip({
    required int clipId,
    required String localWavPath,
    required Duration duration,
    required int sizeBytes,
    DateTime? recordedAt,
  }) async {
    final now = recordedAt ?? DateTime.now();
    final file = File(localWavPath);
    final points = await AudioEditorService.extractWaveformPoints(file);

    final existingIndex = _recordings.indexWhere(
      (r) => (r.source == RecordingSource.hardware &&
              r.syncState != SyncState.synced &&
              r.hardwareClipId == clipId) ||
          (localWavPath.isNotEmpty && r.localWavPath == localWavPath),
    );

    if (existingIndex != -1) {
      final updated = _recordings[existingIndex].copyWith(
        localWavPath: localWavPath,
        duration: duration,
        fileSizeBytes: sizeBytes,
        syncState: SyncState.synced,
        waveformSamples: points.isNotEmpty ? points : null,
      );
      _recordings[existingIndex] = updated;
      await _save();
      notifyListeners();
      return updated;
    } else {
      final String title = 'Hardware Aufnahme ${DateFormat('dd.MM.yyyy HH:mm').format(now)}';
      final newRec = DictulaRecording(
        id: 'hw_${clipId}_${now.millisecondsSinceEpoch}',
        title: title,
        localWavPath: localWavPath,
        duration: duration,
        fileSizeBytes: sizeBytes,
        recordedAt: now,
        source: RecordingSource.hardware,
        hardwareClipId: clipId,
        syncState: SyncState.synced,
        waveformSamples: points,
      );
      _recordings.insert(0, newRec);
      await _save();
      notifyListeners();
      return newRec;
    }
  }

  Future<void> updateRecording(DictulaRecording updated) async {
    final index = _recordings.indexWhere((r) => r.id == updated.id);
    if (index != -1) {
      _recordings[index] = updated;
      await _save();
      notifyListeners();
    }
  }

  Future<void> togglePin(String id) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      _recordings[index] = _recordings[index].copyWith(isPinned: !_recordings[index].isPinned);
      await _save();
      notifyListeners();
    }
  }

  Future<void> renameRecording(String id, String newTitle) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      _recordings[index] = _recordings[index].copyWith(title: newTitle.trim());
      await _save();
      notifyListeners();
    }
  }

  Future<void> setGroup(String id, String? groupId) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      _recordings[index] = _recordings[index].copyWith(groupId: groupId);
      await _save();
      notifyListeners();
    }
  }

  Future<void> updateTranscription(String id, String transcription) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      _recordings[index] = _recordings[index].copyWith(transcription: transcription);
      await _save();
      notifyListeners();
    }
  }

  Future<void> addChatMessage(String id, GeminiChatMessage message) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      final updatedHistory = List<GeminiChatMessage>.from(_recordings[index].chatHistory)..add(message);
      _recordings[index] = _recordings[index].copyWith(chatHistory: updatedHistory);
      await _save();
      notifyListeners();
    }
  }

  Future<void> addPhoto(String id, String photoPath) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      final updatedPhotos = List<String>.from(_recordings[index].photoPaths)..add(photoPath);
      _recordings[index] = _recordings[index].copyWith(photoPaths: updatedPhotos);
      await _save();
      notifyListeners();
    }
  }

  Future<void> removePhoto(String id, String photoPath) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      final updatedPhotos = List<String>.from(_recordings[index].photoPaths)..remove(photoPath);
      _recordings[index] = _recordings[index].copyWith(photoPaths: updatedPhotos);
      await _save();
      notifyListeners();
    }
  }

  Future<void> addAttachment(String id, String filePath) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      final updatedAttachments = List<String>.from(_recordings[index].attachmentPaths)..add(filePath);
      _recordings[index] = _recordings[index].copyWith(attachmentPaths: updatedAttachments);
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeAttachment(String id, String filePath) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      final updatedAttachments = List<String>.from(_recordings[index].attachmentPaths)..remove(filePath);
      _recordings[index] = _recordings[index].copyWith(attachmentPaths: updatedAttachments);
      await _save();
      notifyListeners();
    }
  }

  Future<void> deleteRecording(String id, {bool deleteFilesOnDisk = true}) async {
    final index = _recordings.indexWhere((r) => r.id == id);
    if (index != -1) {
      final rec = _recordings[index];
      if (deleteFilesOnDisk) {
        try {
          final audioFile = File(rec.localWavPath);
          if (await audioFile.exists()) {
            await audioFile.delete();
          }
        } catch (e) {
          debugPrint('[RecordingsRepository] Error deleting audio file: $e');
        }
      }
      _recordings.removeAt(index);
      await _save();
      notifyListeners();
    }
  }

  /// Deletes multiple recordings in batch and cleans up local audio files.
  Future<void> deleteMultipleRecordings(Iterable<String> ids, {bool deleteFilesOnDisk = true}) async {
    final idSet = ids.toSet();
    if (idSet.isEmpty) return;

    if (deleteFilesOnDisk) {
      for (final rec in _recordings) {
        if (idSet.contains(rec.id)) {
          try {
            final audioFile = File(rec.localWavPath);
            if (await audioFile.exists()) {
              await audioFile.delete();
            }
          } catch (e) {
            debugPrint('[RecordingsRepository] Error deleting audio file: $e');
          }
        }
      }
    }

    _recordings.removeWhere((r) => idSet.contains(r.id));
    await _save();
    notifyListeners();
  }

  DictulaRecording? getRecordingById(String id) {
    try {
      return _recordings.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  List<DictulaRecording> getRecordingsForGroup(String groupId) {
    return _recordings.where((r) => r.groupId == groupId).toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
  }
}
