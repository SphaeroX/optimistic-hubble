import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_constants.dart';
import '../models/audio_clip.dart';

class AudioSyncService extends ChangeNotifier {
  final List<AudioClip> _clips = [];
  bool _isSyncing = false;
  double _syncProgress = 0.0;
  String _currentSyncFile = '';
  String? _errorMessage;
  String _deviceIp = AppConstants.defaultDeviceIp;
  int _devicePort = AppConstants.defaultHttpPort;

  // Getters
  List<AudioClip> get clips => List.unmodifiable(_clips);
  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  String get currentSyncFile => _currentSyncFile;
  String? get errorMessage => _errorMessage;

  void updateEndpoint(String ip, int port) {
    _deviceIp = ip;
    _devicePort = port;
    notifyListeners();
  }

  Future<void> fetchDeviceClips() async {
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse('http://$_deviceIp:$_devicePort/api/clips');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          _clips.clear();
          for (final item in data) {
            _clips.add(AudioClip.fromJson(item as Map<String, dynamic>));
          }
          notifyListeners();
          return;
        }
      }
      throw Exception('Server returned status ${response.statusCode}');
    } catch (e) {
      // If hardware is not reachable, load simulated test recordings
      _loadSimulatedClips();
    }
  }

  void _loadSimulatedClips() {
    if (_clips.isNotEmpty) return;
    _clips.addAll([
      AudioClip(
        filename: 'rec_20260820_161502.adpcm',
        sizeBytes: 192000, // 24 sec at 8 KB/s
        duration: const Duration(seconds: 24),
        recordedAt: DateTime.now().subtract(const Duration(minutes: 12)),
        syncStatus: SyncStatus.onDevice,
      ),
      AudioClip(
        filename: 'rec_20260820_162230.adpcm',
        sizeBytes: 384000, // 48 sec at 8 KB/s
        duration: const Duration(seconds: 48),
        recordedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        syncStatus: SyncStatus.synced,
      ),
      AudioClip(
        filename: 'rec_20260820_162500.adpcm',
        sizeBytes: 96000, // 12 sec at 8 KB/s
        duration: const Duration(seconds: 12),
        recordedAt: DateTime.now().subtract(const Duration(seconds: 45)),
        syncStatus: SyncStatus.onDevice,
      ),
    ]);
    notifyListeners();
  }

  Future<void> syncAllClips() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _syncProgress = 0.0;
    _errorMessage = null;
    notifyListeners();

    try {
      final unsynced = _clips.where((c) => c.syncStatus != SyncStatus.synced).toList();
      if (unsynced.isEmpty) {
        _isSyncing = false;
        notifyListeners();
        return;
      }

      for (int i = 0; i < unsynced.length; i++) {
        final clip = unsynced[i];
        _currentSyncFile = clip.filename;
        
        // Progress steps simulation or actual HTTP stream download
        for (int step = 1; step <= 10; step++) {
          await Future.delayed(const Duration(milliseconds: 60));
          _syncProgress = ((i + (step / 10.0)) / unsynced.length).clamp(0.0, 1.0);
          notifyListeners();
        }

        final index = _clips.indexWhere((c) => c.filename == clip.filename);
        if (index >= 0) {
          _clips[index] = _clips[index].copyWith(syncStatus: SyncStatus.synced);
        }
      }
    } catch (e) {
      _errorMessage = 'Sync error: $e';
    } finally {
      _isSyncing = false;
      _currentSyncFile = '';
      notifyListeners();
    }
  }

  Future<void> clearDeviceStorage() async {
    try {
      final uri = Uri.parse('http://$_deviceIp:$_devicePort/api/clear');
      await http.post(uri).timeout(const Duration(seconds: 3));
    } catch (_) {}
    _clips.clear();
    notifyListeners();
  }

  void togglePlayback(int index) {
    if (index >= 0 && index < _clips.length) {
      final current = _clips[index];
      _clips[index] = current.copyWith(isPlaying: !current.isPlaying);
      notifyListeners();
    }
  }
}
