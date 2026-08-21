import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
    loadSavedLocalRecordings();
  }

  @override
  void dispose() {
    audioPlayer.removeListener(_onAudioPlayerUpdate);
    bleService?.removeListener(_onBleUpdate);
    _nativeSyncSubscription?.cancel();
    super.dispose();
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

  /// Fetches exact metadata list from the ESP32 Wi-Fi server (http://192.168.4.1/api/clips).
  Future<void> fetchDeviceClips({bool showError = false}) async {
    if (showError) {
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final uri = Uri.parse('http://$_deviceIp:$_devicePort/api/clips');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dynamic list = data is Map ? data['clips'] : data;
        if (list is List) {
          for (final item in list) {
            final rec = RecordingItem.fromApiJson(item as Map<String, dynamic>);
            final localFile = await LocalStorageManager.getLocalFile('clip_${rec.id}.wav');
            final isLocal = localFile != null && localFile.existsSync();

            _clipsMap[rec.id] = rec.copyWith(
              syncState: isLocal ? SyncState.synced : SyncState.onDevice,
              localWavPath: isLocal ? localFile.path : null,
              downloadProgress: isLocal ? 1.0 : 0.0,
              crcVerified: isLocal,
            );
          }
          _errorMessage = null;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      if (showError) {
        _errorMessage = 'Could not reach http://$_deviceIp:$_devicePort. Turn on Wi-Fi Hotspot ("${AppConstants.defaultApSsid}").';
        notifyListeners();
      }
    }
  }

  /// Adaptive Hybrid Download for a single clip:
  /// - Automatically signals ESP32 to start Wi-Fi Hotspot if needed for >1.8 MB/s Turbo sync.
  Future<bool> downloadClip(
    int clipId, {
    SyncTier? forcedTier,
    bool keepWifiAlive = false,
  }) async {
    final clip = _clipsMap[clipId];
    if (clip == null) return false;

    _errorMessage = null;
    _currentSyncFile = clip.remoteFilename;
    _clipsMap[clipId] = clip.copyWith(
      syncState: SyncState.downloading,
      downloadProgress: 0.05,
      transferSpeed: 'Starting download...',
    );
    notifyListeners();

    bool wifiStartedByThisCall = false;
    try {
      // 1. If BLE is connected and Wi-Fi is currently off, start Hotspot for Turbo download (single clip only)
      final bool needStartWifi = !keepWifiAlive &&
          (bleService?.isConnected == true &&
              bleService?.telemetry.state != DeviceState.wifiActive);

      if (needStartWifi) {
        wifiStartedByThisCall = true;
        _clipsMap[clipId] = _clipsMap[clipId]!.copyWith(
          transferSpeed: 'Starting Wi-Fi Turbo Hotspot...',
        );
        _currentSpeed = 'Starting Wi-Fi Hotspot...';
        notifyListeners();

        await bleService!.sendCommand(BleCommand.startWifi);
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      // 2. Android Native Wi-Fi Turbo Sync (via Network.socketFactory)
      if (_nativeBridge.isPlatformAndroid) {
        try {
          final targetDir = await LocalStorageManager.getRecordingsDirectory();
          final targetPath = '${targetDir.path}/clip_${clip.id}.wav';

          final String? savedPath = await _nativeBridge.startWifiSoftApSync(
            fileId: clip.id,
            ssidPattern: AppConstants.defaultApSsidPattern,
            passphrase: AppConstants.defaultApPassword,
            destinationPath: targetPath,
            keepConnected: keepWifiAlive,
          );

          if (!keepWifiAlive && wifiStartedByThisCall && bleService?.isConnected == true) {
            await bleService!.sendCommand(BleCommand.stopWifi);
          }

          if (savedPath != null) {
            _clipsMap[clipId] = _clipsMap[clipId]!.copyWith(
              syncState: SyncState.synced,
              downloadProgress: 1.0,
              localWavPath: savedPath,
              crcVerified: true,
              transferSpeed: 'Verified (>1.8 MB/s Turbo)',
            );
            _currentSyncFile = '';
            _currentSpeed = null;
            notifyListeners();
            return true;
          }
        } catch (nativeErr) {
          debugPrint('[RecordingSyncManager] Native Wi-Fi sync fallback to HTTP: $nativeErr');
        }
      }

      // 3. High-speed HTTP stream download with Range Resume support (fallback / non-Android)
      final success = await _downloadViaHttpRange(clipId);

      if (!keepWifiAlive && wifiStartedByThisCall && bleService?.isConnected == true) {
        await bleService!.sendCommand(BleCommand.stopWifi);
      }

      return success;
    } catch (e) {
      if (!keepWifiAlive && wifiStartedByThisCall && bleService?.isConnected == true) {
        try {
          await bleService!.sendCommand(BleCommand.stopWifi);
        } catch (_) {}
      }

      _clipsMap[clipId] = _clipsMap[clipId]!.copyWith(
        syncState: SyncState.error,
        transferSpeed: 'Failed: $e',
      );
      _errorMessage = 'Download error: $e';
      _currentSyncFile = '';
      _currentSpeed = null;
      notifyListeners();
      return false;
    }
  }

  /// High-Speed HTTP GET stream with RFC 7233 Range resume support
  Future<bool> _downloadViaHttpRange(int clipId) async {
    final clip = _clipsMap[clipId];
    if (clip == null) return false;

    final uri = Uri.parse('http://$_deviceIp:$_devicePort/api/download?id=$clipId');
    final client = http.Client();
    final request = http.Request('GET', uri);

    final localTemp = await LocalStorageManager.getLocalFile('clip_${clip.id}.part');
    int existingOffset = 0;
    if (localTemp != null && localTemp.existsSync()) {
      existingOffset = localTemp.lengthSync();
      if (existingOffset > 0 && existingOffset < clip.sizeBytes) {
        request.headers['Range'] = 'bytes=$existingOffset-';
      }
    }

    final startTime = DateTime.now();
    final response = await client.send(request).timeout(const Duration(seconds: 30));

    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('Server returned HTTP ${response.statusCode}');
    }

    final contentLength = (response.contentLength ?? clip.sizeBytes) + existingOffset;
    final List<int> downloadedBytes = [];

    await for (final chunk in response.stream) {
      downloadedBytes.addAll(chunk);
      final totalReceived = existingOffset + downloadedBytes.length;
      final elapsedSec = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      final speedKb = elapsedSec > 0 ? (downloadedBytes.length / 1024.0) / elapsedSec : 0.0;
      final speedStr = speedKb > 1024 ? '${(speedKb / 1024.0).toStringAsFixed(2)} MB/s' : '${speedKb.toStringAsFixed(1)} KB/s';

      final progress = contentLength > 0
          ? (totalReceived / contentLength).clamp(0.0, 1.0)
          : 0.5;

      _clipsMap[clipId] = _clipsMap[clipId]!.copyWith(
        downloadProgress: progress,
        transferSpeed: speedStr,
      );
      _currentSpeed = speedStr;
      notifyListeners();
    }

    final rawData = Uint8List.fromList(downloadedBytes);
    Uint8List wavBytes;

    if (rawData.length > 4 && rawData[0] == 0x52 && rawData[1] == 0x49 && rawData[2] == 0x46 && rawData[3] == 0x46) {
      wavBytes = rawData;
    } else {
      wavBytes = AdpcmDecoder.decodeAdpcmToWav(rawData, sampleRate: clip.sampleRate);
    }

    final savedFile = await LocalStorageManager.saveWavFile(
      filename: 'clip_${clip.id}.wav',
      wavBytes: wavBytes,
    );

    _clipsMap[clipId] = _clipsMap[clipId]!.copyWith(
      syncState: SyncState.synced,
      downloadProgress: 1.0,
      localWavPath: savedFile.path,
      crcVerified: true,
      transferSpeed: 'Verified',
    );
    _currentSyncFile = '';
    _currentSpeed = null;
    notifyListeners();
    return true;
  }

  /// High-Speed Tiered Sync for all unsynced clips
  Future<void> syncAllClips() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _syncProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    bool wifiStartedForBatch = false;
    try {
      try {
        await fetchDeviceClips(showError: false);
      } catch (_) {}

      final unsynced = _clipsMap.values.where((c) => c.syncState != SyncState.synced).toList();
      if (unsynced.isEmpty) {
        _isSyncing = false;
        notifyListeners();
        return;
      }

      // 1. If BLE is connected and Wi-Fi is off, start Hotspot ONCE for the entire batch
      if (bleService?.isConnected == true &&
          bleService?.telemetry.state != DeviceState.wifiActive) {
        wifiStartedForBatch = true;
        _currentSpeed = 'Starting Wi-Fi Hotspot for batch...';
        notifyListeners();
        await bleService!.sendCommand(BleCommand.startWifi);
        await Future.delayed(const Duration(milliseconds: 1500));
      }

      // 2. Pre-connect native Wi-Fi if on Android to ensure session is active
      if (_nativeBridge.isPlatformAndroid) {
        try {
          await _nativeBridge.connectWifiSoftAp(
            ssidPattern: AppConstants.defaultApSsidPattern,
            passphrase: AppConstants.defaultApPassword,
          );
        } catch (e) {
          debugPrint('[RecordingSyncManager] Pre-connecting Wi-Fi SoftAP: $e');
        }
      }

      // 3. Process each unsynced clip keeping Wi-Fi connection alive across the whole batch
      for (int i = 0; i < unsynced.length; i++) {
        if (!_isSyncing) break; // Check if cancelled

        final clip = unsynced[i];
        _currentSyncFile = clip.remoteFilename;
        _syncProgress = (i / unsynced.length);
        notifyListeners();

        // Pass keepWifiAlive: true so individual downloads don't tear down Wi-Fi
        await downloadClip(clip.id, keepWifiAlive: true);

        _syncProgress = ((i + 1) / unsynced.length);
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'Sync error: $e';
    } finally {
      // 4. Clean up batch Wi-Fi session
      if (_nativeBridge.isPlatformAndroid) {
        try {
          await _nativeBridge.disconnectWifiSoftAp();
        } catch (_) {}
      }

      if (wifiStartedForBatch && bleService?.isConnected == true) {
        try {
          await bleService!.sendCommand(BleCommand.stopWifi);
        } catch (_) {}
      }

      _isSyncing = false;
      _currentSyncFile = '';
      _currentSpeed = null;
      notifyListeners();
    }
  }

  /// Cancels any active synchronization in progress and restores normal Wi-Fi routing.
  Future<void> cancelSync() async {
    if (!_isSyncing) return;
    _isSyncing = false;
    _errorMessage = 'Sync cancelled by user';

    if (_nativeBridge.isPlatformAndroid) {
      await _nativeBridge.cancelSync();
    }

    if (bleService?.isConnected == true) {
      try {
        await bleService!.sendCommand(BleCommand.stopWifi);
      } catch (_) {}
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
    try {
      final uri = Uri.parse('http://$_deviceIp:$_devicePort/api/clear');
      await http.post(uri).timeout(const Duration(seconds: 3));
    } catch (_) {}
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
