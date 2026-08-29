import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/audio/audio_editor_service.dart';
import '../../../core/audio/audio_recorder_service.dart';
import '../../../core/audio/native_audio_player.dart';
import '../../../core/utils/storage_manager.dart';
import '../../recordings/models/dictula_recording.dart';
import '../../recordings/services/recordings_repository.dart';

enum RecorderMode {
  idle,
  recording,
  paused,
  scrubbing,
  previewPlaying,
}

/// Controller managing the state and lifecycle of the on-device audio recorder & waveform punch-in editor.
class RecorderController with ChangeNotifier {
  final AudioRecorderService recorderService;
  final RecordingsRepository recordingsRepository;
  final NativeAudioPlayer audioPlayer;

  RecorderMode _mode = RecorderMode.idle;
  RecorderMode get mode => _mode;

  String? _baseWavPath;
  String? get baseWavPath => _baseWavPath;

  Duration _totalDuration = Duration.zero;
  Duration get totalDuration => _totalDuration;

  Duration _scrubPosition = Duration.zero;
  Duration get scrubPosition => _scrubPosition;

  String? _selectedGroupId;
  String? get selectedGroupId => _selectedGroupId;
  set selectedGroupId(String? val) {
    _selectedGroupId = val;
    notifyListeners();
  }

  String _recordingTitle = '';
  String get recordingTitle => _recordingTitle;
  set recordingTitle(String val) {
    _recordingTitle = val;
    notifyListeners();
  }

  bool _isPunchInMode = false;
  bool get isPunchInMode => _isPunchInMode;

  RecorderController({
    required this.recorderService,
    required this.recordingsRepository,
    required this.audioPlayer,
  }) {
    recorderService.addListener(_onRecorderUpdate);
    audioPlayer.addListener(_onPlayerUpdate);
  }

  @override
  void dispose() {
    recorderService.removeListener(_onRecorderUpdate);
    audioPlayer.removeListener(_onPlayerUpdate);
    super.dispose();
  }

  void _onRecorderUpdate() {
    if (recorderService.isRecording) {
      _mode = RecorderMode.recording;
      _totalDuration = recorderService.elapsedDuration;
      _scrubPosition = _totalDuration;
    } else if (recorderService.isPaused) {
      if (_mode != RecorderMode.scrubbing && _mode != RecorderMode.previewPlaying) {
        _mode = RecorderMode.paused;
      }
    }
    notifyListeners();
  }

  void _onPlayerUpdate() {
    if (_mode == RecorderMode.previewPlaying) {
      if (!audioPlayer.isPlaying) {
        _mode = RecorderMode.paused;
        notifyListeners();
      }
    }
  }

  /// Starts a fresh microphone recording.
  Future<void> startFreshRecording() async {
    audioPlayer.stop();
    _isPunchInMode = false;
    _baseWavPath = null;
    _scrubPosition = Duration.zero;
    _totalDuration = Duration.zero;

    final success = await recorderService.startRecording();
    if (success) {
      _mode = RecorderMode.recording;
    } else {
      _mode = RecorderMode.idle;
    }
    notifyListeners();
  }

  /// Pauses recording and enters inspection / editing mode.
  Future<void> pauseRecording() async {
    await recorderService.pauseRecording();
    _mode = RecorderMode.paused;
    _scrubPosition = recorderService.elapsedDuration;
    _totalDuration = recorderService.elapsedDuration;
    notifyListeners();
  }

  /// Resumes recording normally from the end.
  Future<void> resumeRecording() async {
    if (_mode == RecorderMode.paused || _mode == RecorderMode.scrubbing) {
      if (recorderService.beepOnResume) {
        // Play acoustic feedback beep
        final beepBytes = AudioEditorService.generateBeepPcm(durationMs: 80, frequencyHz: 880);
        final tempDir = await getTemporaryDirectory();
        final beepFile = File('${tempDir.path}/beep_${DateTime.now().millisecondsSinceEpoch}.wav');
        final wavBytes = AudioEditorService.createWavFromPcm(pcmData: beepBytes);
        await beepFile.writeAsBytes(wavBytes);
        await audioPlayer.play(beepFile.path);
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await recorderService.resumeRecording();
      _mode = RecorderMode.recording;
      notifyListeners();
    }
  }

  /// Updates scrub cursor position across the recorded waveform.
  void setScrubPosition(Duration position) {
    if (_mode == RecorderMode.recording) return;
    _scrubPosition = position;
    if (_scrubPosition < Duration.zero) _scrubPosition = Duration.zero;
    if (_scrubPosition > _totalDuration) _scrubPosition = _totalDuration;
    _isPunchInMode = _scrubPosition < _totalDuration - const Duration(milliseconds: 500);
    _mode = RecorderMode.scrubbing;
    notifyListeners();
  }

  /// Executes punch-in: Cuts audio at [scrubPosition], plays short cue beep, and continues recording.
  Future<void> punchInFromCurrentPosition() async {
    try {
      final currentWavPath = await recorderService.stopRecording();
      if (currentWavPath == null) return;

      final currentFile = File(currentWavPath);
      final tempDir = await getTemporaryDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final File trimmedBaseFile = File('${tempDir.path}/trimmed_base_$timestamp.wav');

      // 1. Trim previous audio up to scrub position
      final Uint8List? trimmedBytes = await AudioEditorService.trimWavFile(currentFile, _scrubPosition);
      if (trimmedBytes != null) {
        await trimmedBaseFile.writeAsBytes(trimmedBytes);
        _baseWavPath = trimmedBaseFile.path;
      } else {
        _baseWavPath = currentWavPath;
      }

      // 2. Play audible resume beep
      if (recorderService.beepOnResume) {
        final beepBytes = AudioEditorService.generateBeepPcm(durationMs: 90, frequencyHz: 880);
        final beepFile = File('${tempDir.path}/beep_$timestamp.wav');
        final wavBytes = AudioEditorService.createWavFromPcm(pcmData: beepBytes);
        await beepFile.writeAsBytes(wavBytes);
        await audioPlayer.play(beepFile.path);
        await Future.delayed(const Duration(milliseconds: 110));
      }

      // 3. Start recording new chunk
      final String newChunkPath = '${tempDir.path}/chunk_$timestamp.wav';
      await recorderService.startRecording(customPath: newChunkPath);

      _isPunchInMode = false;
      _mode = RecorderMode.recording;
      notifyListeners();
    } catch (e) {
      debugPrint('[RecorderController] Error executing punch-in: $e');
    }
  }

  /// Toggles playback preview of the recorded audio up to current point.
  Future<void> togglePlaybackPreview() async {
    if (_mode == RecorderMode.previewPlaying) {
      audioPlayer.stop();
      _mode = RecorderMode.paused;
      notifyListeners();
      return;
    }

    if (recorderService.isRecording) {
      await pauseRecording();
    }

    // Save temporary audio state for playback
    final path = recorderService.currentRecordingPath;
    if (path != null && await File(path).exists()) {
      _mode = RecorderMode.previewPlaying;
      notifyListeners();
      await audioPlayer.play(path);
    }
  }

  /// Saves the finished recording permanently into Dictula's library.
  Future<DictulaRecording?> saveRecording() async {
    try {
      String? finalWavPath = await recorderService.stopRecording();
      if (finalWavPath == null && _baseWavPath == null) return null;

      final Directory saveDir = Directory(await LocalStorageManager.getRecordingsDirectoryPath());
      if (!await saveDir.exists()) await saveDir.create(recursive: true);

      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final File finalDestFile = File('${saveDir.path}/dictula_rec_$timestamp.wav');

      // If we had a base trimmed file and a new recorded chunk, stitch them together
      if (_baseWavPath != null && finalWavPath != null && _baseWavPath != finalWavPath) {
        final File baseFile = File(_baseWavPath!);
        final File newChunkFile = File(finalWavPath);
        if (await baseFile.exists() && await newChunkFile.exists()) {
          await AudioEditorService.appendWavChunks(
            originalWavFile: baseFile,
            appendedWavFile: newChunkFile,
            outputFile: finalDestFile,
            insertBeep: recorderService.beepOnResume,
          );
        } else if (await baseFile.exists()) {
          await baseFile.copy(finalDestFile.path);
        } else {
          await newChunkFile.copy(finalDestFile.path);
        }
      } else if (finalWavPath != null) {
        final srcFile = File(finalWavPath);
        if (await srcFile.exists()) {
          await srcFile.copy(finalDestFile.path);
        }
      }

      // Add to repository
      final rec = await recordingsRepository.addPhoneRecording(
        filePath: finalDestFile.path,
        duration: _totalDuration,
        customTitle: _recordingTitle.trim().isNotEmpty ? _recordingTitle.trim() : null,
        groupId: _selectedGroupId,
      );

      // Reset controller state
      reset();
      return rec;
    } catch (e) {
      debugPrint('[RecorderController] Error saving recording: $e');
      return null;
    }
  }

  /// Discards the current recording session.
  Future<void> discardRecording() async {
    audioPlayer.stop();
    await recorderService.cancelRecording();
    reset();
  }

  void reset() {
    _mode = RecorderMode.idle;
    _baseWavPath = null;
    _isPunchInMode = false;
    _scrubPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _recordingTitle = '';
    notifyListeners();
  }
}
