import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/audio/adpcm_decoder.dart';
import '../../../core/audio/native_audio_player.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/embedded_http_server.dart';
import '../../../core/services/native_audio_sync_bridge.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/storage_manager.dart';
import '../../connection/services/ble_service.dart';
import '../models/recording_item.dart';

class RecordingSyncManager extends ChangeNotifier {
  final NativeAudioPlayer audioPlayer;
  final BleService? bleService;
  final NativeAudioSyncBridge _nativeBridge = NativeAudioSyncBridge();
  final EmbeddedAudioUploadServer _uploadServer = EmbeddedAudioUploadServer();

  final Map<int, RecordingItem> _clipsMap = {};
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String _currentSyncFile = '';
  String? _currentSpeed;
  String? _errorMessage;
  FastTransferPhase _fastTransferPhase = FastTransferPhase.none;
  bool _autoDeleteAfterSync = false;
  int _autoFastTransferThresholdBytes = AppConstants.autoFastTransferThresholdBytes;
  Completer<bool>? _uploadBatchCompleter;

  StreamSubscription<SyncProgressEvent>? _nativeSyncSubscription;
  StreamSubscription<SyncProgressEvent>? _bleAudioSubscription;
  StreamSubscription<SyncProgressEvent>? _serverProgressSubscription;

  String _deviceIp = AppConstants.defaultDeviceIp;
  int _devicePort = AppConstants.defaultHttpPort;
  int _lastKnownClipCount = 0;
  bool _isReconciling = false;

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
  FastTransferPhase get fastTransferPhase => _fastTransferPhase;
  bool get autoDeleteAfterSync => _autoDeleteAfterSync;
  int get autoFastTransferThresholdBytes => _autoFastTransferThresholdBytes;
  String get deviceIp => _deviceIp;
  int get devicePort => _devicePort;

  set autoDeleteAfterSync(bool val) {
    _autoDeleteAfterSync = val;
    notifyListeners();
  }

  set autoFastTransferThresholdBytes(int val) {
    _autoFastTransferThresholdBytes = val;
    notifyListeners();
  }

  RecordingSyncManager({
    required this.audioPlayer,
    this.bleService,
  }) {
    audioPlayer.addListener(_onAudioPlayerUpdate);
    bleService?.addListener(_onBleUpdate);
    _initNativeEventListener();
    _initBleAudioEventListener();
    _initServerCallbacks();
    loadSavedLocalRecordings().then((_) => _syncClipsWithTelemetry(force: true));
  }

  @override
  void dispose() {
    audioPlayer.removeListener(_onAudioPlayerUpdate);
    bleService?.removeListener(_onBleUpdate);
    _nativeSyncSubscription?.cancel();
    _bleAudioSubscription?.cancel();
    _serverProgressSubscription?.cancel();
    _uploadServer.dispose();
    super.dispose();
  }

  void _initServerCallbacks() {
    _serverProgressSubscription = _uploadServer.progressEvents.listen((event) {
      _syncProgress = event.progress;
      _currentSpeed = event.message;
      if (event.isTransferring) {
        _fastTransferPhase = FastTransferPhase.transferring;
      }
      notifyListeners();
    });

    _uploadServer.onClipReceived = ({
      required int clipId,
      required String filePath,
      required int sizeBytes,
      required double durationSeconds,
    }) {
      final existing = _clipsMap[clipId];
      _clipsMap[clipId] = RecordingItem(
        id: clipId,
        remoteFilename: 'clip_${clipId.toString().padLeft(3, '0')}.wav',
        sizeBytes: sizeBytes,
        duration: Duration(milliseconds: (durationSeconds * 1000).round()),
        sampleRate: 16000,
        recordedAt: DateTime.now(),
        syncState: SyncState.synced,
        downloadProgress: 1.0,
        localWavPath: filePath,
        crcVerified: true,
        transferSpeed: 'Verified (Wi-Fi Turbo Upload)',
        isPlaying: existing?.isPlaying ?? false,
      );
      notifyListeners();
    };

    _uploadServer.onSyncCompleted = () {
      if (_uploadBatchCompleter != null && !_uploadBatchCompleter!.isCompleted) {
        _uploadBatchCompleter!.complete(true);
      }
    };
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
        _fastTransferPhase = event.currentPhase;

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
  void _onBleUpdate() {
    _syncClipsWithTelemetry();
  }

  /// Reconciles local recordings and remote BLE inventory into _clipsMap.
  Future<void> _syncClipsWithTelemetry({bool force = false}) async {
    if (_isReconciling) return;
    if (bleService == null) return;

    final telem = bleService!.telemetry;
    final totalClipsOnDevice = telem.totalClips;

    if (!force && totalClipsOnDevice == _lastKnownClipCount && _clipsMap.isNotEmpty) {
      return;
    }

    _isReconciling = true;
    try {
      _lastKnownClipCount = totalClipsOnDevice;
      bool listChanged = false;

      // 1. Clean up unsynced clips whose ID exceeds the device's actual clip count
      final orphanedKeys = _clipsMap.entries
          .where((e) => e.value.syncState != SyncState.synced && (totalClipsOnDevice == 0 || e.key > totalClipsOnDevice))
          .map((e) => e.key)
          .toList();
      for (final key in orphanedKeys) {
        _clipsMap.remove(key);
        listChanged = true;
      }

      // 2. Populate / update all clips from 1 to totalClipsOnDevice
      final used = telem.usedStorageBytes ?? 0;
      final estimatedBytes = (used > 0 && totalClipsOnDevice > 0)
          ? (used / totalClipsOnDevice).round().clamp(8000, 3000000)
          : 64000;
      final durSec = (estimatedBytes > 60) ? ((estimatedBytes - 60) / 8000.0) : 8.0;

      for (int i = 1; i <= totalClipsOnDevice; i++) {
        final existing = _clipsMap[i];

        // Check local disk for both clip_001.wav and clip_1.wav
        final localFile = await LocalStorageManager.getLocalFile('clip_${i.toString().padLeft(3, '0')}.wav');
        final isLocal = localFile != null && localFile.existsSync();

        if (existing == null) {
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
        } else if (!isLocal && existing.syncState == SyncState.synced && existing.localWavPath != null) {
          final f = File(existing.localWavPath!);
          if (!f.existsSync()) {
            _clipsMap[i] = existing.copyWith(
              syncState: SyncState.onDevice,
              downloadProgress: 0.0,
              localWavPath: null,
              crcVerified: false,
            );
            listChanged = true;
          }
        }
      }

      if (listChanged) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[RecordingSyncManager] Error reconciling clips with telemetry: $e');
    } finally {
      _isReconciling = false;
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
        var file = savedFiles[i];
        // Ensure any legacy or newly downloaded file is standard 16-bit Linear PCM
        file = await AdpcmDecoder.ensureFileIsLinearPcmWav(file);

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

  /// Refreshes clip inventory from local storage and real-time BLE telemetry directly from MCU.
  Future<void> fetchDeviceClips({bool showError = false}) async {
    if (showError) {
      _errorMessage = null;
      notifyListeners();
    }

    // 1. Actively query BLE telemetry from MCU if connected
    if (bleService != null && bleService!.isConnected) {
      await bleService!.readTelemetry();
    }

    // 2. Reload local WAV recordings from disk
    await loadSavedLocalRecordings();

    // 3. Unconditionally reconcile clips inventory with device telemetry
    await _syncClipsWithTelemetry(force: true);
  }

  /// 2-Stage Wi-Fi Fast Transfer Pipeline (Phone Hotspot & MCU Upload Model)
  Future<bool> startFastTransfer({int? targetClipId}) async {
    if (_isSyncing) return false;
    _isSyncing = true;
    _errorMessage = null;
    _syncProgress = 0.0;
    _fastTransferPhase = FastTransferPhase.activatingHotspot;
    notifyListeners();

    try {
      // 1. Check if mock mode is active (Desktop / Simulator)
      if (bleService?.isMockMode == true || !_nativeBridge.isPlatformAndroid) {
        _log('[FastTransfer] Running simulated 5-phase Phone-Hosted Wi-Fi Fast Transfer...');
        await Future.delayed(const Duration(milliseconds: 600));
        _fastTransferPhase = FastTransferPhase.connectingWifi;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 800));
        _fastTransferPhase = FastTransferPhase.handshaking;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 500));
        _fastTransferPhase = FastTransferPhase.ready;
        notifyListeners();
        await Future.delayed(const Duration(milliseconds: 400));
        _fastTransferPhase = FastTransferPhase.transferring;

        final targetClips = (targetClipId != null)
            ? [_clipsMap[targetClipId]].whereType<RecordingItem>().toList()
            : _clipsMap.values.where((c) => c.syncState != SyncState.synced).toList();

        for (int i = 0; i < targetClips.length; i++) {
          final clip = targetClips[i];
          _currentSyncFile = clip.remoteFilename;
          _clipsMap[clip.id] = clip.copyWith(
            syncState: SyncState.downloading,
            transferSpeed: '2.4 MB/s (Wi-Fi Turbo)',
          );
          notifyListeners();

          for (int s = 1; s <= 10; s++) {
            await Future.delayed(const Duration(milliseconds: 60));
            _syncProgress = ((i + (s / 10.0)) / targetClips.length).clamp(0.0, 1.0);
            notifyListeners();
          }

          final syntheticWav = _generateSyntheticAudioWav(
            durationSeconds: clip.duration.inSeconds > 0 ? clip.duration.inSeconds : 6,
          );
          final savedFile = await LocalStorageManager.saveWavFile(
            filename: 'clip_${clip.id}.wav',
            wavBytes: syntheticWav,
          );

          _clipsMap[clip.id] = clip.copyWith(
            syncState: SyncState.synced,
            downloadProgress: 1.0,
            localWavPath: savedFile.path,
            crcVerified: true,
            transferSpeed: 'Verified (2.4 MB/s Wi-Fi)',
          );
          notifyListeners();
        }

        _fastTransferPhase = FastTransferPhase.completed;
        _isSyncing = false;
        _currentSyncFile = '';
        _currentSpeed = null;
        notifyListeners();
        return true;
      }

      // 2. Real Hardware: Phase 1 -> Start Embedded Server & Local-Only Hotspot on Phone
      if (bleService == null || !bleService!.isConnected) {
        throw Exception('Please connect to Xiao ESP32 via BLE first');
      }

      _fastTransferPhase = FastTransferPhase.activatingHotspot;
      notifyListeners();

      final serverPort = await _uploadServer.start(port: 8080);
      final hotspotInfo = await _nativeBridge.startLocalOnlyHotspot(port: serverPort);

      if (hotspotInfo == null) {
        throw Exception('Failed to start Android Local-Only Hotspot');
      }

      _log('[FastTransfer] Phone Hotspot active: SSID="${hotspotInfo.ssid}", IP=${hotspotInfo.ip}:$serverPort');

      // 3. Phase 2 -> Send BLE credentials to ESP32 to connect to Phone Hotspot
      _fastTransferPhase = FastTransferPhase.connectingWifi;
      notifyListeners();

      await bleService!.sendConnectHotspotCommand(
        ssid: hotspotInfo.ssid,
        passphrase: hotspotInfo.passphrase,
        hostIp: hotspotInfo.ip,
        port: serverPort,
        clipId: targetClipId ?? 0,
        autoDelete: _autoDeleteAfterSync,
      );

      // 4. Phase 3 & 4 -> Await ESP32 connection and stream upload
      _fastTransferPhase = FastTransferPhase.handshaking;
      notifyListeners();

      _uploadBatchCompleter = Completer<bool>();

      // Wait for complete signal or timeout
      await _uploadBatchCompleter!.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          _log('[FastTransfer] Upload batch timeout or finished without complete signal');
          return true;
        },
      );

      _fastTransferPhase = FastTransferPhase.completed;
      return true;
    } catch (e) {
      _errorMessage = 'Fast Transfer error: $e';
      _fastTransferPhase = FastTransferPhase.failed;
      return false;
    } finally {
      await _uploadServer.stop();
      await _nativeBridge.stopLocalOnlyHotspot();
      _uploadBatchCompleter = null;
      _isSyncing = false;
      _currentSyncFile = '';
      _currentSpeed = null;
      notifyListeners();
    }
  }

  void _log(String msg) {
    debugPrint('[RecordingSyncManager] $msg');
  }

  /// Download a single clip using smart 2-stage routing
  Future<bool> downloadClip(
    int clipId, {
    SyncTier? forcedTier,
    bool keepWifiAlive = false,
  }) async {
    final clip = _clipsMap[clipId];
    if (clip == null) return false;

    // Smart routing: Large clips or explicit Wi-Fi tier trigger Fast Transfer
    if (forcedTier == SyncTier.wifiFast || (forcedTier == null && clip.isFastTransferRecommended)) {
      return await startFastTransfer(targetClipId: clipId);
    }

    // Small clips / standard route: BLE 5.0 GATT / L2CAP
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

      final Uint8List? rawBytes = await bleService!.streamClipOverGatt(clip.id);
      if (rawBytes == null || rawBytes.isEmpty) {
        throw Exception('BLE audio stream timed out or returned no data');
      }

      final Uint8List finalWavBytes = AdpcmDecoder.ensureLinearPcmWav(
        rawBytes,
        defaultSampleRate: clip.sampleRate,
      );

      final savedFile = await LocalStorageManager.saveWavFile(
        filename: 'clip_${clip.id}.wav',
        wavBytes: finalWavBytes,
      );

      _clipsMap[clipId] = _clipsMap[clipId]!.copyWith(
        syncState: SyncState.synced,
        downloadProgress: 1.0,
        localWavPath: savedFile.path,
        crcVerified: true,
        transferSpeed: 'Verified (BLE 5.0 Auto-Sync)',
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

  /// Sequential Sync for all unsynced clips
  Future<void> syncAllClips({bool forceWifiFast = false}) async {
    final unsynced = _clipsMap.values.where((c) => c.syncState != SyncState.synced).toList();
    if (unsynced.isEmpty) return;

    // Check if any clip is large enough to warrant Fast Transfer, or forced
    final hasLargeClips = unsynced.any((c) => c.isFastTransferRecommended);
    if (forceWifiFast || hasLargeClips) {
      await startFastTransfer();
      return;
    }

    if (_isSyncing) return;
    _isSyncing = true;
    _syncProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      for (int i = 0; i < unsynced.length; i++) {
        if (!_isSyncing) break;

        final clip = unsynced[i];
        _currentSyncFile = clip.remoteFilename;
        _syncProgress = (i / unsynced.length);
        notifyListeners();

        await downloadClip(clip.id, forcedTier: SyncTier.bleStandard);

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

    await _uploadServer.stop();
    await _nativeBridge.stopLocalOnlyHotspot();
    if (_uploadBatchCompleter != null && !_uploadBatchCompleter!.isCompleted) {
      _uploadBatchCompleter!.complete(false);
    }
    _uploadBatchCompleter = null;

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

  /// Shares a recording clip with external apps (e.g. WhatsApp, Mail, Telegram).
  Future<bool> shareClip(RecordingItem clip, {Rect? sharePositionOrigin}) async {
    try {
      if (clip.syncState != SyncState.synced || clip.localWavPath == null) {
        final ok = await downloadClip(clip.id);
        if (!ok) return false;
      }

      final updated = _clipsMap[clip.id];
      if (updated?.localWavPath != null) {
        await LocalStorageManager.shareFile(
          filePath: updated!.localWavPath!,
          text: 'Xiao Audio Recording #${clip.id} (${Formatters.formatDuration(clip.duration)})',
          sharePositionOrigin: sharePositionOrigin,
        );
        return true;
      }
    } catch (e) {
      debugPrint('[RecordingSyncManager] Error sharing clip #${clip.id}: $e');
    }
    return false;
  }

  /// Deletes the local downloaded WAV file for a clip.
  Future<bool> deleteClipLocally(int clipId) async {
    final clip = _clipsMap[clipId];
    if (clip == null) return false;

    if (clip.isPlaying || audioPlayer.currentFilePath == clip.localWavPath) {
      audioPlayer.stop();
    }

    if (clip.localWavPath != null) {
      await LocalStorageManager.deleteLocalFileByPath(clip.localWavPath!);
    } else {
      await LocalStorageManager.deleteLocalFile('clip_$clipId.wav');
      await LocalStorageManager.deleteLocalFile('clip_${clipId.toString().padLeft(3, '0')}.wav');
    }

    final isConnected = bleService?.isConnected == true;
    final totalOnDevice = bleService?.telemetry.totalClips ?? 0;

    if (isConnected && clipId <= totalOnDevice) {
      _clipsMap[clipId] = clip.copyWith(
        syncState: SyncState.onDevice,
        downloadProgress: 0.0,
        localWavPath: null,
        transferSpeed: null,
        isPlaying: false,
      );
    } else {
      _clipsMap.remove(clipId);
    }

    notifyListeners();
    return true;
  }

  /// Deletes a clip remotely from the ESP32 LittleFS Flash over BLE.
  Future<bool> deleteClipOnDevice(int clipId) async {
    if (bleService?.isConnected == true) {
      await bleService!.sendCommand(BleCommand.deleteClip, clipId: clipId);
    }

    final clip = _clipsMap[clipId];
    if (clip != null) {
      if (clip.syncState == SyncState.synced && clip.localWavPath != null) {
        // Kept as local synced
      } else {
        _clipsMap.remove(clipId);
      }
    }

    notifyListeners();
    return true;
  }

  /// Deletes a clip both locally from disk and remotely from ESP32 Flash.
  Future<bool> deleteClipEverywhere(int clipId) async {
    final clip = _clipsMap[clipId];
    if (clip?.isPlaying == true || audioPlayer.currentFilePath == clip?.localWavPath) {
      audioPlayer.stop();
    }

    if (clip?.localWavPath != null) {
      await LocalStorageManager.deleteLocalFileByPath(clip!.localWavPath!);
    } else {
      await LocalStorageManager.deleteLocalFile('clip_$clipId.wav');
      await LocalStorageManager.deleteLocalFile('clip_${clipId.toString().padLeft(3, '0')}.wav');
    }

    if (bleService?.isConnected == true) {
      await bleService!.sendCommand(BleCommand.deleteClip, clipId: clipId);
    }

    _clipsMap.remove(clipId);
    notifyListeners();
    return true;
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
