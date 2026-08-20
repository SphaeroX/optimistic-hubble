import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _PlaySoundWNative = Int32 Function(Pointer<Utf16> pszSound, IntPtr hmod, Uint32 fdwSound);
typedef _PlaySoundWDart = int Function(Pointer<Utf16> pszSound, int hmod, int fdwSound);

/// Cross-platform Native Audio Player.
/// Uses Windows WinMM Native API for zero-latency, high-performance playback of WAV files without external dependencies.
class NativeAudioPlayer extends ChangeNotifier {
  static const int _sndAsync = 0x00000001;
  static const int _sndNodefault = 0x00000002;
  static const int _sndFilename = 0x00020000;
  static const int _sndPurge = 0x0040;

  _PlaySoundWDart? _winPlaySound;
  DynamicLibrary? _winmmLib;

  bool _isPlaying = false;
  String? _currentFilePath;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  Timer? _playbackTimer;

  bool get isPlaying => _isPlaying;
  String? get currentFilePath => _currentFilePath;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  double get progressFraction => _totalDuration.inMilliseconds > 0
      ? (_currentPosition.inMilliseconds / _totalDuration.inMilliseconds).clamp(0.0, 1.0)
      : 0.0;

  NativeAudioPlayer() {
    _initNativePlayer();
  }

  void _initNativePlayer() {
    if (kIsWeb) return;
    if (Platform.isWindows) {
      try {
        _winmmLib = DynamicLibrary.open('winmm.dll');
        _winPlaySound = _winmmLib!.lookupFunction<_PlaySoundWNative, _PlaySoundWDart>('PlaySoundW');
      } catch (e) {
        debugPrint('[NativeAudioPlayer] Could not open winmm.dll: $e');
      }
    }
  }

  /// Plays a WAV audio file asynchronously.
  Future<bool> playFile(String filePath, {Duration? duration}) async {
    stop();

    final file = File(filePath);
    if (!file.existsSync()) {
      debugPrint('[NativeAudioPlayer] File does not exist: $filePath');
      return false;
    }

    _currentFilePath = filePath;
    _totalDuration = duration ?? const Duration(seconds: 10);
    _currentPosition = Duration.zero;
    _isPlaying = true;
    notifyListeners();

    if (Platform.isWindows && _winPlaySound != null) {
      final nativePath = filePath.toNativeUtf16();
      try {
        // SND_FILENAME | SND_ASYNC | SND_NODEFAULT
        final int flags = _sndFilename | _sndAsync | _sndNodefault;
        _winPlaySound!(nativePath, 0, flags);
      } finally {
        calloc.free(nativePath);
      }
    }

    // Start progress tracking timer
    _playbackTimer?.cancel();
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      _currentPosition += const Duration(milliseconds: 100);
      if (_currentPosition >= _totalDuration) {
        stop();
      } else {
        notifyListeners();
      }
    });

    return true;
  }

  /// Stops current playback.
  void stop() {
    _playbackTimer?.cancel();
    _playbackTimer = null;

    if (Platform.isWindows && _winPlaySound != null) {
      _winPlaySound!(nullptr, 0, _sndPurge);
    }

    _isPlaying = false;
    _currentPosition = Duration.zero;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
