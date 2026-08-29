import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'adpcm_decoder.dart';

/// Cross-platform Audio Player powered by audioplayers.
/// Supports zero-latency, high-performance playback of WAV files on Windows, Android, iOS, macOS, and Linux.
class NativeAudioPlayer extends ChangeNotifier {
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isPlaying = false;
  String? _currentFilePath;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  StreamSubscription? _playerStateSubscription;
  StreamSubscription? _positionSubscription;
  StreamSubscription? _durationSubscription;

  bool get isPlaying => _isPlaying;
  String? get currentFilePath => _currentFilePath;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  double get progressFraction => _totalDuration.inMilliseconds > 0
      ? (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  NativeAudioPlayer() {
    _initPlayerListeners();
  }

  void _initPlayerListeners() {
    try {
      _audioPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {},
          ),
        ),
      );
      _audioPlayer.setVolume(1.0);
    } catch (e) {
      debugPrint('[NativeAudioPlayer] AudioContext setup error (non-fatal): $e');
    }

    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((state) {
      final playing = (state == PlayerState.playing);
      if (_isPlaying != playing) {
        _isPlaying = playing;
        notifyListeners();
      }
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        _isPlaying = false;
        _currentPosition = Duration.zero;
        notifyListeners();
      }
    });

    _positionSubscription = _audioPlayer.onPositionChanged.listen((pos) {
      _currentPosition = pos;
      notifyListeners();
    });

    _durationSubscription = _audioPlayer.onDurationChanged.listen((dur) {
      if (dur > Duration.zero) {
        _totalDuration = dur;
        notifyListeners();
      }
    });
  }

  /// Plays a WAV audio file asynchronously.
  Future<bool> play(String filePath, {Duration? duration}) => playFile(filePath, duration: duration);

  /// Plays a WAV audio file asynchronously.
  Future<bool> playFile(String filePath, {Duration? duration}) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      debugPrint('[NativeAudioPlayer] File does not exist: $filePath');
      return false;
    }

    try {
      if (_isPlaying && _currentFilePath == filePath) {
        await pause();
        return true;
      }

      await _audioPlayer.stop();

      // Ensure file is converted to standard 16-bit Linear PCM WAV before playing
      final validFile = await AdpcmDecoder.ensureFileIsLinearPcmWav(file);
      final playPath = validFile.path;

      _currentFilePath = playPath;
      if (duration != null && duration > Duration.zero) {
        _totalDuration = duration;
      }
      _currentPosition = Duration.zero;

      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setSource(DeviceFileSource(playPath));
      await _audioPlayer.resume();
      _isPlaying = true;
      notifyListeners();
      debugPrint('[NativeAudioPlayer] Playing audio file: $playPath (size: ${validFile.lengthSync()} bytes)');
      return true;
    } catch (e) {
      debugPrint('[NativeAudioPlayer] Error playing file: $e');
      _isPlaying = false;
      notifyListeners();
      return false;
    }
  }

  /// Pauses current playback.
  Future<void> pause() async {
    try {
      await _audioPlayer.pause();
      _isPlaying = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[NativeAudioPlayer] Error pausing: $e');
    }
  }

  /// Stops current playback.
  void stop() {
    try {
      _audioPlayer.stop();
    } catch (_) {}
    _isPlaying = false;
    _currentPosition = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }
}

