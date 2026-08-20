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
import '../../../core/utils/storage_manager.dart';
import '../models/recording_item.dart';

class RecordingSyncManager extends ChangeNotifier {
  final NativeAudioPlayer audioPlayer;
  final List<RecordingItem> _clips = [];
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String _currentSyncFile = '';
  String? _errorMessage;

  String _deviceIp = AppConstants.defaultDeviceIp;
  int _devicePort = AppConstants.defaultHttpPort;

  // Getters
  List<RecordingItem> get clips => List.unmodifiable(_clips);
  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  String get currentSyncFile => _currentSyncFile;
  String? get errorMessage => _errorMessage;
  String get deviceIp => _deviceIp;
  int get devicePort => _devicePort;

  RecordingSyncManager({required this.audioPlayer}) {
    audioPlayer.addListener(_onAudioPlayerUpdate);
    loadSavedLocalRecordings();
  }

  @override
  void dispose() {
    audioPlayer.removeListener(_onAudioPlayerUpdate);
    super.dispose();
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

  void updateEndpoint(String ip, int port) {
    _deviceIp = ip;
    _devicePort = port;
    notifyListeners();
  }

  /// Loads real WAV files previously downloaded and saved on this PC/device.
  Future<void> loadSavedLocalRecordings() async {
    try {
      final List<File> savedFiles = await LocalStorageManager.listSavedWavFiles();
      _clips.clear();

      for (int i = 0; i < savedFiles.length; i++) {
        final file = savedFiles[i];
        final size = file.lengthSync();
        // 16 kHz 16-bit mono PCM = 32,000 bytes/sec
        final durSec = size > 44 ? ((size - 44) / 32000.0) : 0.0;
        final name = file.uri.pathSegments.last;

        _clips.add(RecordingItem(
          id: i + 1,
          remoteFilename: name,
          sizeBytes: size,
          duration: Duration(milliseconds: (durSec * 1000).round()),
          sampleRate: 16000,
          recordedAt: file.lastModifiedSync(),
          syncState: SyncState.synced,
          downloadProgress: 1.0,
          localWavPath: file.path,
        ));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[RecordingSyncManager] Error loading local recordings: $e');
    }
  }

  /// Fetches real clips list from the ESP32 Wi-Fi server (http://192.168.4.1/api/clips).
  Future<void> fetchDeviceClips() async {
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('http://$_deviceIp:$_devicePort/api/clips');
      final response = await http.get(uri).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final dynamic list = data is Map ? data['clips'] : data;
        if (list is List) {
          _clips.clear();
          for (final item in list) {
            final rec = RecordingItem.fromApiJson(item as Map<String, dynamic>);
            // Check local file cache
            final localFile = await LocalStorageManager.getLocalFile('clip_${rec.id}.wav');
            if (localFile != null) {
              _clips.add(rec.copyWith(
                syncState: SyncState.synced,
                localWavPath: localFile.path,
              ));
            } else {
              _clips.add(rec);
            }
          }
          notifyListeners();
          return;
        }
      }
      throw Exception('Server returned ${response.statusCode}');
    } catch (e) {
      _errorMessage = 'Could not reach http://$_deviceIp:$_devicePort. Connect Wi-Fi to "${AppConstants.defaultApSsid}".';
      notifyListeners();
    }
  }

  /// Downloads a single clip from ESP32 over Wi-Fi, converts ADPCM to WAV, and saves to disk.
  Future<bool> downloadClip(int clipId) async {
    final index = _clips.indexWhere((c) => c.id == clipId);
    if (index < 0) return false;

    final clip = _clips[index];
    _clips[index] = clip.copyWith(syncState: SyncState.downloading, downloadProgress: 0.1);
    notifyListeners();

    try {
      final uri = Uri.parse('http://$_deviceIp:$_devicePort/api/download?id=$clipId');
      final client = http.Client();
      final request = http.Request('GET', uri);
      final response = await client.send(request).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('Download failed with status ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? clip.sizeBytes;
      final List<int> downloadedBytes = [];

      await for (final chunk in response.stream) {
        downloadedBytes.addAll(chunk);
        final progress = contentLength > 0
            ? (downloadedBytes.length / contentLength).clamp(0.0, 1.0)
            : 0.5;
        _clips[index] = _clips[index].copyWith(downloadProgress: progress);
        notifyListeners();
      }

      final rawData = Uint8List.fromList(downloadedBytes);
      Uint8List wavBytes;

      // Check if already standard WAV or raw ADPCM
      if (rawData.length > 4 && rawData[0] == 0x52 && rawData[1] == 0x49 && rawData[2] == 0x46 && rawData[3] == 0x46) {
        wavBytes = rawData;
      } else {
        // Decode IMA-ADPCM to 16-bit PCM WAV
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
      );
      notifyListeners();
      return true;
    } catch (e) {
      _clips[index] = _clips[index].copyWith(syncState: SyncState.error);
      _errorMessage = 'Download error: $e';
      notifyListeners();
      return false;
    }
  }

  /// High-Speed Wi-Fi Sync for all un-synced clips.
  Future<void> syncAllClips() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _syncProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      await fetchDeviceClips();

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

  /// Clears recordings from the ESP32 storage.
  Future<void> clearDeviceStorage() async {
    try {
      final uri = Uri.parse('http://$_deviceIp:$_devicePort/api/clear');
      await http.post(uri).timeout(const Duration(seconds: 4));
    } catch (_) {}
    _clips.clear();
    await loadSavedLocalRecordings();
    notifyListeners();
  }

  // ==========================================================================
  // Simulation Helper (only used when explicitly testing mock mode)
  // ==========================================================================
  Future<void> loadSimulatedClipsForTesting() async {
    final simClips = [
      RecordingItem(
        id: 101,
        remoteFilename: 'sim_voice_sample_01.adpcm',
        sizeBytes: 192000,
        duration: const Duration(seconds: 24),
        sampleRate: 16000,
        recordedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        syncState: SyncState.synced,
      ),
    ];

    for (final clip in simClips) {
      final syntheticWav = _generateSyntheticAudioWav(durationSeconds: 5);
      final savedFile = await LocalStorageManager.saveWavFile(
        filename: 'sim_clip_${clip.id}.wav',
        wavBytes: syntheticWav,
      );
      _clips.add(clip.copyWith(localWavPath: savedFile.path));
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
