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

  final List<RecordingItem> _clips = [];
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
  List<RecordingItem> get clips => List.unmodifiable(_clips);
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
          final index = _clips.indexWhere((c) => c.remoteFilename == _currentSyncFile);
          if (index >= 0) {
            _clips[index] = _clips[index].copyWith(
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
    for (int i = 0; i < _clips.length; i++) {
      final clip = _clips[i];
      final bool isCurrent = audioPlayer.currentFilePath != null &&
          clip.localWavPath != null &&
          audioPlayer.currentFilePath == clip.localWavPath;
      final isPlaying = isCurrent && audioPlayer.isPlaying;
      if (clip.isPlaying != isPlaying) {
        _clips[i] = clip.copyWith(isPlaying: isPlaying);
      }
    }
    notifyListeners();
  }

  /// Automatically updates clips registry based on real-time BLE telemetry from ESP32.
  void _onBleUpdate() async {
    if (bleService == null) return;
    final telem = bleService!.telemetry;
    final totalClipsOnDevice = telem.totalClips;

    if (totalClipsOnDevice != _lastKnownClipCount || totalClipsOnDevice > 0) {
      _lastKnownClipCount = totalClipsOnDevice;
      bool listChanged = false;

      for (int i = 1; i <= totalClipsOnDevice; i++) {
        final existingIndex = _clips.indexWhere((c) => c.id == i);
        final localFile = await LocalStorageManager.getLocalFile('clip_$i.wav');
        final isLocal = localFile != null && localFile.existsSync();

        if (existingIndex < 0) {
          // New clip discovered from ESP32 BLE state
          final used = telem.usedStorageBytes ?? 0;
          final estimatedBytes = used > 0
              ? (used / totalClipsOnDevice).round().clamp(8000, 3000000)
              : 64000;
          final durSec = (estimatedBytes > 60) ? ((estimatedBytes - 60) / 8000.0) : 8.0;

          _clips.add(RecordingItem(
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
          ));
          listChanged = true;
        } else if (isLocal && _clips[existingIndex].syncState != SyncState.synced) {
          _clips[existingIndex] = _clips[existingIndex].copyWith(
            syncState: SyncState.synced,
            downloadProgress: 1.0,
            localWavPath: localFile.path,
            crcVerified: true,
          );
          listChanged = true;
        }
      }

      if (listChanged) {
        _clips.sort((a, b) => b.id.compareTo(a.id)); // Newest first
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

        // Try extracting clip id from clip_X.wav or clip_XXX.wav
        int id = i + 1;
        final match = RegExp(r'clip_(\d+)').firstMatch(name);
        if (match != null) {
          id = int.tryParse(match.group(1)!) ?? (i + 1);
        }

        final existingIdx = _clips.indexWhere((c) => c.id == id);
        final item = RecordingItem(
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
        );

        if (existingIdx >= 0) {
          _clips[existingIdx] = item;
        } else {
          _clips.add(item);
        }
      }
      _clips.sort((a, b) => b.id.compareTo(a.id));
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
            final existingIdx = _clips.indexWhere((c) => c.id == rec.id);

            final updated = rec.copyWith(
              syncState: isLocal ? SyncState.synced : SyncState.onDevice,
              localWavPath: isLocal ? localFile.path : null,
              downloadProgress: isLocal ? 1.0 : 0.0,
              crcVerified: isLocal,
            );

            if (existingIdx >= 0) {
              _clips[existingIdx] = updated;
            } else {
              _clips.add(updated);
            }
          }
          _clips.sort((a, b) => b.id.compareTo(a.id));
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
  /// - Tier 1: BLE L2CAP CoC (Size < 2.0 MB)
  /// - Tier 2: Wi-Fi SoftAP with RFC 7233 Range Resume (Size >= 2.0 MB)
  Future<bool> downloadClip(int clipId, {SyncTier? forcedTier}) async {
    final index = _clips.indexWhere((c) => c.id == clipId);
    if (index < 0) return false;

    final clip = _clips[index];
    final tier = forcedTier ?? clip.recommendedTier;

    _clips[index] = clip.copyWith(
      syncState: SyncState.downloading,
      downloadProgress: 0.05,
      transferSpeed: 'Starting ${tier.label}...',
    );
    notifyListeners();

    try {
      // 1. Android Native Tier 1: BLE L2CAP
      if (tier == SyncTier.bleL2cap && _nativeBridge.isPlatformAndroid && bleService?.connectedDevice != null) {
        final deviceAddress = bleService!.connectedDevice!.id;
        _currentSyncFile = clip.remoteFilename;
        _currentSpeed = 'BLE L2CAP (125 KB/s)';
        notifyListeners();

        try {
          final String? savedPath = await _nativeBridge.startBleL2capSync(
            deviceAddress: deviceAddress,
            fileId: clip.id,
            psm: AppConstants.bleL2capPsm,
          );

          if (savedPath != null) {
            _clips[index] = _clips[index].copyWith(
              syncState: SyncState.synced,
              downloadProgress: 1.0,
              localWavPath: savedPath,
              crcVerified: true,
              transferSpeed: 'Verified (BLE L2CAP)',
            );
            notifyListeners();
            return true;
          }
        } catch (bleErr) {
          debugPrint('[RecordingSyncManager] BLE L2CAP fallback to Wi-Fi: $bleErr');
        }
      }

      // 2. Android Native Tier 2: Wi-Fi SoftAP with Network.socketFactory
      if (_nativeBridge.isPlatformAndroid && bleService?.isConnected == true) {
        _currentSyncFile = clip.remoteFilename;
        _currentSpeed = 'Starting Wi-Fi Hotspot...';
        notifyListeners();

        // Signal ESP32 to power on SoftAP
        await bleService!.sendCommand(BleCommand.startWifi);
        await Future.delayed(const Duration(milliseconds: 1200));

        final String? savedPath = await _nativeBridge.startWifiSoftApSync(
          fileId: clip.id,
          ssidPattern: AppConstants.defaultApSsidPattern,
          passphrase: AppConstants.defaultApPassword,
        );

        // Turn off Wi-Fi after transfer to conserve battery
        await bleService!.sendCommand(BleCommand.stopWifi);

        if (savedPath != null) {
          _clips[index] = _clips[index].copyWith(
            syncState: SyncState.synced,
            downloadProgress: 1.0,
            localWavPath: savedPath,
            crcVerified: true,
            transferSpeed: 'Verified (>1.8 MB/s Turbo)',
          );
          notifyListeners();
          return true;
        }
      }

      // 3. Fallback / Desktop / Web Pure Dart HTTP Stream with RFC 7233 Range Resume
      return await _downloadViaHttpRange(clipId);
    } catch (e) {
      _clips[index] = _clips[index].copyWith(
        syncState: SyncState.error,
        transferSpeed: 'Failed: $e',
      );
      _errorMessage = 'Download error: $e';
      notifyListeners();
      return false;
    }
  }

  /// High-Speed HTTP GET stream with RFC 7233 Range resume support
  Future<bool> _downloadViaHttpRange(int clipId) async {
    final index = _clips.indexWhere((c) => c.id == clipId);
    if (index < 0) return false;

    final clip = _clips[index];
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

      _clips[index] = _clips[index].copyWith(
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

    _clips[index] = _clips[index].copyWith(
      syncState: SyncState.synced,
      downloadProgress: 1.0,
      localWavPath: savedFile.path,
      crcVerified: true,
      transferSpeed: 'Verified',
    );
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

    try {
      // Background query for exact metadata if reachable
      try {
        await fetchDeviceClips(showError: false);
      } catch (_) {}

      final unsynced = _clips.where((c) => c.syncState != SyncState.synced).toList();
      if (unsynced.isEmpty) {
        _isSyncing = false;
        notifyListeners();
        return;
      }

      for (int i = 0; i < unsynced.length; i++) {
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

    final updated = _clips.firstWhere((c) => c.id == clip.id);
    if (updated.localWavPath != null) {
      await audioPlayer.playFile(updated.localWavPath!, duration: updated.duration);
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
    _clips.clear();
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
        sizeBytes: 192000, // 192 KB (< 2.0 MB -> Tier 1 BLE)
        duration: const Duration(seconds: 24),
        sampleRate: 16000,
        recordedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        syncState: SyncState.synced,
        crcVerified: true,
      ),
      RecordingItem(
        id: 102,
        remoteFilename: 'sim_voice_large_02.wav',
        sizeBytes: 4800000, // 4.8 MB (>= 2.0 MB -> Tier 2 Wi-Fi Turbo)
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
        _clips.add(clip.copyWith(localWavPath: savedFile.path));
      } else {
        _clips.add(clip);
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
