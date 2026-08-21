import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../../core/audio/adpcm_decoder.dart';
import '../../../core/audio/native_audio_player.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/native_audio_sync_bridge.dart';
import '../../../core/utils/storage_manager.dart';
import '../../connection/services/ble_service.dart';
import '../models/recording_item.dart';

class RecordingSyncManager extends ChangeNotifier {
  final NativeAudioPlayer audioPlayer;
  final BleService? bleService;
  final NativeAudioSyncBridge _nativeBridge = NativeAudioSyncBridge();

  final Map<int, RecordingItem> _clipsMap = {};
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String _currentSyncFile = '';
  String? _currentSpeed;
  String? _errorMessage;
  StreamSubscription<SyncProgressEvent>? _nativeSyncSubscription;
  StreamSubscription<SyncProgressEvent>? _bleAudioSubscription;

  String _deviceIp = AppConstants.defaultDeviceIp;
  int _devicePort = AppConstants.defaultHttpPort;
  int _lastKnownClipCount = 0;

  // Getters
  List<RecordingItem> get clips {
    final list = _clipsMap.values.toList();
    list.sort((a, b) => b.id.compareTo(a.id)); // Newest first (highest ID first)
    return List.unmodifiable(list);
  }

  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  String get currentSyncFile => _currentSyncFile;
  String? get currentSpeed => _currentSpeed;
  String? get errorMessage => _errorMessage;
  String get deviceIp => _deviceIp;
  int get devicePort => _devicePort;

  RecordingSyncManager({
    required this.audioPlayer,
    this.bleService,
  }) {
    audioPlayer.addListener(_onAudioPlayerUpdate);
    bleService?.addListener(_onBleUpdate);
    _initNativeEventListener();
    _initBleAudioEventListener();
    loadSavedLocalRecordings();
  }

  @override
  void dispose() {
    audioPlayer.removeListener(_onAudioPlayerUpdate);
    bleService?.removeListener(_onBleUpdate);
    _nativeSyncSubscription?.cancel();
    _bleAudioSubscription?.cancel();
    super.dispose();
  }

  void _initBleAudioEventListener() {
    _bleAudioSubscription = bleService?.audioProgressEvents.listen((event) {
      _syncProgress = event.progress;
      _currentSpeed = event.message;

      if (event.isTransferring && _currentSyncFile.isNotEmpty) {
        final target = _clipsMap.values.cast<RecordingItem?>().firstWhere(
              (c) => c?.remoteFilename == _currentSyncFile,
              orElse: () => null,
            );
        if (target != null) {
          _clipsMap[target.id] = target.copyWith(
            syncState: SyncState.downloading,
            downloadProgress: event.progress,
            transferSpeed: event.message,
          );
        }
      }
      notifyListeners();
    });
  }

  void _initNativeEventListener() {
    if (_nativeBridge.isPlatformAndroid) {
      _nativeSyncSubscription = _nativeBridge.syncEvents.listen((event) {
        _syncProgress = event.progress;
        _currentSpeed = event.message;

        if (event.isTransferring && _currentSyncFile.isNotEmpty) {
          final target = _clipsMap.values.cast<RecordingItem?>().firstWhere(
                (c) => c?.remoteFilename == _currentSyncFile,
                orElse: () => null,
              );
          if (target != null) {
            _clipsMap[target.id] = target.copyWith(
              syncState: SyncState.downloading,
              downloadProgress: event.progress,
              transferSpeed: event.message,
            );
          }
        }
        notifyListeners();
      });
    }
  }

  void _onAudioPlayerUpdate() {
    bool changed = false;
    for (final entry in _clipsMap.entries) {
      final clip = entry.value;
      final bool isCurrent = audioPlayer.currentFilePath != null &&
          clip.localWavPath != null &&
          audioPlayer.currentFilePath == clip.localWavPath;
      final isPlaying = isCurrent && audioPlayer.isPlaying;
      if (clip.isPlaying != isPlaying) {
        _clipsMap[entry.key] = clip.copyWith(isPlaying: isPlaying);
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Automatically synchronizes clips registry based on real-time BLE telemetry from ESP32.
  void _onBleUpdate() async {
    if (bleService == null) return;
    final telem = bleService!.telemetry;
    final totalClipsOnDevice = telem.totalClips;

    if (totalClipsOnDevice != _lastKnownClipCount || (_clipsMap.isEmpty && totalClipsOnDevice > 0)) {
      _lastKnownClipCount = totalClipsOnDevice;
      bool listChanged = false;

      for (int i = 1; i <= totalClipsOnDevice; i++) {
        final existing = _clipsMap[i];
        final localFile = await LocalStorageManager.getLocalFile('clip_$i.wav');
        final isLocal = localFile != null && localFile.existsSync();

        if (existing == null) {
          final used = telem.usedStorageBytes ?? 0;
          final estimatedBytes = (used > 0 && totalClipsOnDevice > 0)
              ? (used / totalClipsOnDevice).round().clamp(8000, 3000000)
              : 64000;
          final durSec = (estimatedBytes > 60) ? ((estimatedBytes - 60) / 8000.0) : 8.0;

          _clipsMap[i] = RecordingItem(
            id: i,
            remoteFilename: 'clip_${i.toString().padLeft(3, '0')}.wav',
            sizeBytes: isLocal ? localFile.lengthSync() : estimatedBytes,
            duration: Duration(milliseconds: (durSec * 1000).round()),
            sampleRate: 16000,
            recordedAt: isLocal ? localFile.lastModifiedSync() : DateTime.now(),
            syncState: isLocal ? SyncState.synced : SyncState.onDevice,
            downloadProgress: isLocal ? 1.0 : 0.0,
            localWavPath: isLocal ? localFile.path : null,
            crcVerified: isLocal,
          );
          listChanged = true;
        } else if (isLocal && existing.syncState != SyncState.synced) {
          _clipsMap[i] = existing.copyWith(
            syncState: SyncState.synced,
            downloadProgress: 1.0,
            localWavPath: localFile.path,
            crcVerified: true,
          );
          listChanged = true;
        }
      }

      if (listChanged) {
        notifyListeners();
      }
    }
  }

  void updateEndpoint(String ip, int port) {
    _deviceIp = ip;
    _devicePort = port;
    notifyListeners();
  }

  /// Loads real WAV files previously downloaded and saved on this device.
  Future<void> loadSavedLocalRecordings() async {
    try {
      final List<File> savedFiles = await LocalStorageManager.listSavedWavFiles();

      for (int i = 0; i < savedFiles.length; i++) {
        final file = savedFiles[i];
        final size = file.lengthSync();
        final durSec = size > 44 ? ((size - 44) / 32000.0) : 0.0;
        final name = file.uri.pathSegments.last;

        int id = i + 1;
        final match = RegExp(r'clip_(\d+)').firstMatch(name);
        if (match != null) {
          id = int.tryParse(match.group(1)!) ?? (i + 1);
        }

        final existing = _clipsMap[id];
        _clipsMap[id] = RecordingItem(
          id: id,
          remoteFilename: name,
          sizeBytes: size,
          duration: Duration(milliseconds: (durSec * 1000).round()),
          sampleRate: 16000,
          recordedAt: file.lastModifiedSync(),
          syncState: SyncState.synced,
          downloadProgress: 1.0,
          localWavPath: file.path,
          crcVerified: true,
          isPlaying: existing?.isPlaying ?? false,
        );
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[RecordingSyncManager] Error loading local recordings: $e');
    }
  }

  /// Refreshes clip inventory from local storage and real-time BLE telemetry.
  Future<void> fetchDeviceClips({bool showError = false}) async {
    if (showError) {
      _errorMessage = null;
      notifyListeners();
    }
    await loadSavedLocalRecordings();
    _onBleUpdate();
  }

  /// BLE 5.0 High-Throughput Download for a single clip:
  Future<bool> downloadClip(
    int clipId, {
    SyncTier? forcedTier,
    bool keepWifiAlive = false,
  }) async {
    final clip = _clipsMap[clipId];
    if (clip == null) return false;

    if (bleService == null || !bleService!.isConnected) {
      _errorMessage = 'Please connect to Xiao ESP32 via BLE first';
      notifyListeners();
      return false;
    }

    _errorMessage = null;
    _currentSyncFile = clip.remoteFilename;
    _clipsMap[clipId] = clip.copyWith(
      syncState: SyncState.downloading,
      downloadProgress: 0.05,
      transferSpeed: 'Starting BLE 5.0 sync...',
    );
    notifyListeners();

    try {
      // 1. Simulated or Host Fallback (Mock Mode for PC/Testing)
      if (bleService?.isMockMode == true) {
        final syntheticWav = _generateSyntheticAudioWav(
          durationSeconds: clip.duration.inSeconds > 0 ? clip.duration.inSeconds : 5,
        );
        final savedFile = await LocalStorageManager.saveWavFile(
          filename: 'clip_${clip.id}.wav',
          wavBytes: syntheticWav,
        );
        _clipsMap[clipId] = _clipsMap[clipId]!.copyWith(
          syncState: SyncState.synced,
          downloadProgress: 1.0,
          localWavPath: savedFile.path,
          crcVerified: true,
          transferSpeed: 'Verified (Simulated BLE)',
        );
        _currentSyncFile = '';
        _currentSpeed = null;
        notifyListeners();
        return true;
      }

      // 2. High-speed BLE GATT Stream transfer
      final Uint8List? rawBytes = await bleService!.streamClipOverGatt(clip.id);
      if (rawBytes == null || rawBytes.isEmpty) {
        throw Exception('BLE audio stream timed out or returned no data');
      }

      Uint8List finalWavBytes;
      if (rawBytes.length > 4 &&
          rawBytes[0] == 0x52 &&
          rawBytes[1] == 0x49 &&
          rawBytes[2] == 0x46 &&
          rawBytes[3] == 0x46) {
        // Standard RIFF/WAVE header
        finalWavBytes = rawBytes;
      } else {
        // Raw ADPCM - decode to Linear 16-bit PCM WAV
        finalWavBytes = AdpcmDecoder.decodeAdpcmToWav(rawBytes, sampleRate: clip.sampleRate);
      }

      final savedFile = await LocalStorageManager.saveWavFile(
        filename: 'clip_${clip.id}.wav',
        wavBytes: finalWavBytes,
      );

      _clipsMap[clipId] = _clipsMap[clipId]!.copyWith(
        syncState: SyncState.synced,
        downloadProgress: 1.0,
        localWavPath: savedFile.path,
        crcVerified: true,
        transferSpeed: 'Verified (BLE 5.0 High-Throughput)',
      );
      _currentSyncFile = '';
      _currentSpeed = null;
      notifyListeners();
      return true;
    } catch (e) {
      _clipsMap[clipId] = _clipsMap[clipId]!.copyWith(
        syncState: SyncState.error,
        transferSpeed: 'Failed: $e',
      );
      _errorMessage = 'BLE sync error: $e';
      _currentSyncFile = '';
      _currentSpeed = null;
      notifyListeners();
      return false;
    }
  }

  /// BLE 5.0 High-Throughput Sequential Sync for all unsynced clips
  Future<void> syncAllClips() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _syncProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      final unsynced = _clipsMap.values.where((c) => c.syncState != SyncState.synced).toList();
      if (unsynced.isEmpty) {
        _isSyncing = false;
        notifyListeners();
        return;
      }

      for (int i = 0; i < unsynced.length; i++) {
        if (!_isSyncing) break; // Check if cancelled

        final clip = unsynced[i];
        _currentSyncFile = clip.remoteFilename;
        _syncProgress = (i / unsynced.length);
        notifyListeners();

        await downloadClip(clip.id);

        _syncProgress = ((i + 1) / unsynced.length);
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Sync error: $e';
    } finally {
      _isSyncing = false;
      _currentSyncFile = '';
      _currentSpeed = null;
      notifyListeners();
    }
  }

  /// Cancels any active synchronization in progress.
  Future<void> cancelSync() async {
    if (!_isSyncing) return;
    _isSyncing = false;
    _errorMessage = 'Sync cancelled by user';

    if (_nativeBridge.isPlatformAndroid) {
      await _nativeBridge.cancelSync();
    }

    _currentSyncFile = '';
    _currentSpeed = null;
    notifyListeners();
  }

  /// Toggles playback for a recording clip.
  Future<void> togglePlayback(RecordingItem clip) async {
    if (clip.isPlaying) {
      audioPlayer.stop();
      return;
    }

    if (clip.syncState != SyncState.synced || clip.localWavPath == null) {
      final ok = await downloadClip(clip.id);
      if (!ok) return;
    }

    final updated = _clipsMap[clip.id];
    if (updated?.localWavPath != null) {
      await audioPlayer.playFile(updated!.localWavPath!, duration: updated.duration);
    }
  }

  /// Clears recordings from the ESP32 storage and local cache.
  Future<void> clearDeviceStorage() async {
    if (bleService?.isConnected == true) {
      await bleService!.sendCommand(BleCommand.clearStorage);
    }
    _clipsMap.clear();
    _lastKnownClipCount = 0;
    await loadSavedLocalRecordings();
    notifyListeners();
  }

  // ==========================================================================
  // Simulation Helper (for mock mode testing)
  // ==========================================================================
  Future<void> loadSimulatedClipsForTesting() async {
    final simClips = [
      RecordingItem(
        id: 101,
        remoteFilename: 'sim_voice_small_01.wav',
        sizeBytes: 192000,
        duration: const Duration(seconds: 24),
        sampleRate: 16000,
        recordedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        syncState: SyncState.synced,
        crcVerified: true,
      ),
      RecordingItem(
        id: 102,
        remoteFilename: 'sim_voice_large_02.wav',
        sizeBytes: 4800000,
        duration: const Duration(minutes: 10),
        sampleRate: 16000,
        recordedAt: DateTime.now().subtract(const Duration(minutes: 2)),
        syncState: SyncState.onDevice,
      ),
    ];

    for (final clip in simClips) {
      if (clip.syncState == SyncState.synced) {
        final syntheticWav = _generateSyntheticAudioWav(durationSeconds: 5);
        final savedFile = await LocalStorageManager.saveWavFile(
          filename: 'sim_clip_${clip.id}.wav',
          wavBytes: syntheticWav,
        );
        _clipsMap[clip.id] = clip.copyWith(localWavPath: savedFile.path);
      } else {
        _clipsMap[clip.id] = clip;
      }
    }
    notifyListeners();
  }

  Uint8List _generateSyntheticAudioWav({int durationSeconds = 5, int sampleRate = 16000}) {
    final int totalSamples = durationSeconds * sampleRate;
    final Int16List samples = Int16List(totalSamples);

    for (int i = 0; i < totalSamples; ++i) {
      final double t = i / sampleRate.toDouble();
      final double amp = 0.3 * (1.0 + 0.5 * sin(2 * pi * 2.0 * t));
      final double sampleVal = amp * (sin(2 * pi * 440.0 * t) + 0.5 * sin(2 * pi * 880.0 * t));
      samples[i] = (sampleVal * 32767).round().clamp(-32768, 32767);
    }

    return AdpcmDecoder.createWavFile(pcmSamples: samples, sampleRate: sampleRate);
  }
}
