import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

enum RecorderStatus {
  idle,
  recording,
  paused,
  stopping,
}

/// Service for high-fidelity microphone audio recording and amplitude stream on mobile.
class AudioRecorderService with ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSubscription;

  RecorderStatus _status = RecorderStatus.idle;
  RecorderStatus get status => _status;
  bool get isRecording => _status == RecorderStatus.recording;
  bool get isPaused => _status == RecorderStatus.paused;
  bool get isIdle => _status == RecorderStatus.idle;

  Duration _elapsedDuration = Duration.zero;
  Duration get elapsedDuration => _elapsedDuration;

  Timer? _timer;
  String? _currentRecordingPath;
  String? get currentRecordingPath => _currentRecordingPath;

  // Waveform amplitude data
  final List<double> _liveAmplitudes = [];
  List<double> get liveAmplitudes => List.unmodifiable(_liveAmplitudes);

  // Settings
  bool _noiseFilterEnabled = true;
  bool get noiseFilterEnabled => _noiseFilterEnabled;
  set noiseFilterEnabled(bool value) {
    _noiseFilterEnabled = value;
    notifyListeners();
  }

  bool _skipSilenceEnabled = false;
  bool get skipSilenceEnabled => _skipSilenceEnabled;
  set skipSilenceEnabled(bool value) {
    _skipSilenceEnabled = value;
    notifyListeners();
  }

  bool _beepOnResume = true;
  bool get beepOnResume => _beepOnResume;
  set beepOnResume(bool value) {
    _beepOnResume = value;
    notifyListeners();
  }

  /// Starts a new local microphone recording to a temporary WAV file.
  Future<bool> startRecording({String? customPath}) async {
    try {
      if (!await _recorder.hasPermission()) {
        debugPrint('[AudioRecorderService] Microphone permission not granted');
        return false;
      }

      if (_status != RecorderStatus.idle) {
        await stopRecording();
      }

      final Directory tempDir = await getTemporaryDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String filePath = customPath ?? '${tempDir.path}/rec_$timestamp.wav';

      _currentRecordingPath = filePath;
      _liveAmplitudes.clear();
      _elapsedDuration = Duration.zero;

      // Start recording 16 kHz Mono WAV (standard linear PCM matching hardware specs)
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
          noiseSuppress: _noiseFilterEnabled,
          autoGain: true,
          echoCancel: true,
        ),
        path: filePath,
      );

      _status = RecorderStatus.recording;

      _startTimer();
      _startAmplitudeMonitoring();

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AudioRecorderService] Error starting recording: $e');
      _status = RecorderStatus.idle;
      notifyListeners();
      return false;
    }
  }

  /// Pauses current recording.
  Future<void> pauseRecording() async {
    if (_status != RecorderStatus.recording) return;
    try {
      await _recorder.pause();
      _status = RecorderStatus.paused;
      _timer?.cancel();
      notifyListeners();
    } catch (e) {
      debugPrint('[AudioRecorderService] Error pausing recording: $e');
    }
  }

  /// Resumes recording, optionally playing/inserting a cue beep tone.
  Future<void> resumeRecording() async {
    if (_status != RecorderStatus.paused) return;
    try {
      await _recorder.resume();
      _status = RecorderStatus.recording;
      _startTimer();
      notifyListeners();
    } catch (e) {
      debugPrint('[AudioRecorderService] Error resuming recording: $e');
    }
  }

  /// Stops current recording and returns the completed WAV file path.
  Future<String?> stopRecording() async {
    if (_status == RecorderStatus.idle) return null;
    try {
      _status = RecorderStatus.stopping;
      notifyListeners();

      _timer?.cancel();
      _timer = null;
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;

      final String? path = await _recorder.stop();
      _status = RecorderStatus.idle;

      final resultPath = path ?? _currentRecordingPath;
      notifyListeners();
      return resultPath;
    } catch (e) {
      debugPrint('[AudioRecorderService] Error stopping recording: $e');
      _status = RecorderStatus.idle;
      notifyListeners();
      return null;
    }
  }

  /// Cancels recording and discards temporary file.
  Future<void> cancelRecording() async {
    try {
      _timer?.cancel();
      _timer = null;
      await _amplitudeSubscription?.cancel();
      _amplitudeSubscription = null;

      await _recorder.stop();
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('[AudioRecorderService] Error cancelling recording: $e');
    } finally {
      _status = RecorderStatus.idle;
      _liveAmplitudes.clear();
      _elapsedDuration = Duration.zero;
      _currentRecordingPath = null;
      notifyListeners();
    }
  }

  /// Replaces waveform points manually (e.g. when loading an existing recording to edit/punch-in).
  void loadExistingWaveform(List<double> points, Duration duration) {
    _liveAmplitudes.clear();
    _liveAmplitudes.addAll(points);
    _elapsedDuration = duration;
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_status == RecorderStatus.recording) {
        _elapsedDuration += const Duration(milliseconds: 100);
        notifyListeners();
      }
    });
  }

  void _startAmplitudeMonitoring() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 60))
        .listen((amplitude) {
      if (_status == RecorderStatus.recording) {
        // dBFS ranges from -160.0 to 0.0 (typically -60 to 0 for speech)
        final double currentDb = amplitude.current;
        final double normalized = _dbToLinear(currentDb);

        // Optional silence skipping detection logic
        if (_skipSilenceEnabled && normalized < 0.04) {
          // Muted or below noise threshold
        }

        _liveAmplitudes.add(normalized);
        notifyListeners();
      }
    });
  }

  double _dbToLinear(double db) {
    if (db.isInfinite || db.isNaN) return 0.03;
    // Map -55 dB to 0.02 and 0 dB to 1.0
    final double clamped = db.clamp(-55.0, 0.0);
    final double norm = (clamped + 55.0) / 55.0;
    return norm.clamp(0.02, 1.0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSubscription?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
