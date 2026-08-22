import '../../../core/constants/app_constants.dart';

enum SyncState {
  onDevice,    // Clip is on ESP32 LittleFS flash only
  downloading, // Transfer in progress (BLE or Wi-Fi)
  synced,      // Downloaded and verified on local disk
  error        // Sync failed
}

class RecordingItem {
  final int id;
  final String remoteFilename;
  final int sizeBytes;
  final Duration duration;
  final int sampleRate;
  final DateTime recordedAt;
  final SyncState syncState;
  final double downloadProgress;
  final String? localWavPath;
  final bool isPlaying;
  final SyncTier recommendedTier;
  final String? transferSpeed;
  final bool crcVerified;

  RecordingItem({
    required this.id,
    required this.remoteFilename,
    required this.sizeBytes,
    required this.duration,
    required this.sampleRate,
    required this.recordedAt,
    this.syncState = SyncState.onDevice,
    this.downloadProgress = 0.0,
    this.localWavPath,
    this.isPlaying = false,
    SyncTier? recommendedTier,
    this.transferSpeed,
    this.crcVerified = false,
  }) : recommendedTier = recommendedTier ??
            (sizeBytes >= AppConstants.autoFastTransferThresholdBytes || duration.inSeconds >= 60
                ? SyncTier.wifiFast
                : SyncTier.bleStandard);

  bool get isFastTransferRecommended =>
      recommendedTier == SyncTier.wifiFast || sizeBytes >= AppConstants.autoFastTransferThresholdBytes;

  factory RecordingItem.fromApiJson(Map<String, dynamic> json) {
    final int id = json['id'] as int? ?? 1;
    final String name = json['filename'] as String? ?? 'clip_$id.wav';
    final int size = json['size'] as int? ?? 0;
    final double durSec = (json['duration'] as num?)?.toDouble() ?? (size > 0 ? (size / 8000.0) : 0.0);
    final int rate = json['sampleRate'] as int? ?? 16000;

    return RecordingItem(
      id: id,
      remoteFilename: name,
      sizeBytes: size,
      duration: Duration(milliseconds: (durSec * 1000).round()),
      sampleRate: rate,
      recordedAt: DateTime.now(),
      syncState: SyncState.onDevice,
    );
  }

  RecordingItem copyWith({
    int? id,
    String? remoteFilename,
    int? sizeBytes,
    Duration? duration,
    int? sampleRate,
    DateTime? recordedAt,
    SyncState? syncState,
    double? downloadProgress,
    String? localWavPath,
    bool? isPlaying,
    SyncTier? recommendedTier,
    String? transferSpeed,
    bool? crcVerified,
  }) {
    return RecordingItem(
      id: id ?? this.id,
      remoteFilename: remoteFilename ?? this.remoteFilename,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      duration: duration ?? this.duration,
      sampleRate: sampleRate ?? this.sampleRate,
      recordedAt: recordedAt ?? this.recordedAt,
      syncState: syncState ?? this.syncState,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      localWavPath: localWavPath ?? this.localWavPath,
      isPlaying: isPlaying ?? this.isPlaying,
      recommendedTier: recommendedTier ?? this.recommendedTier,
      transferSpeed: transferSpeed ?? this.transferSpeed,
      crcVerified: crcVerified ?? this.crcVerified,
    );
  }
}
