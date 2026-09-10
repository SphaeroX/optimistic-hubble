enum SyncStatus { local, onDevice, syncing, synced }

class AudioClip {
  final String filename;
  final int sizeBytes;
  final Duration duration;
  final DateTime recordedAt;
  final SyncStatus syncStatus;
  final double syncProgress;
  final bool isPlaying;

  AudioClip({
    required this.filename,
    required this.sizeBytes,
    required this.duration,
    required this.recordedAt,
    this.syncStatus = SyncStatus.onDevice,
    this.syncProgress = 0.0,
    this.isPlaying = false,
  });

  bool get isSynced => syncStatus == SyncStatus.synced || syncStatus == SyncStatus.local;

  factory AudioClip.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? 'clip.adpcm';
    final size = json['size'] as int? ?? 0;
    
    // 16 kHz mono 4-bit IMA-ADPCM = 8,000 bytes per second
    final calculatedDurationSeconds = size > 0 ? (size / 8000.0).round() : 0;

    return AudioClip(
      filename: name,
      sizeBytes: size,
      duration: Duration(seconds: calculatedDurationSeconds),
      recordedAt: DateTime.now(),
      syncStatus: SyncStatus.onDevice,
    );
  }

  AudioClip copyWith({
    String? filename,
    int? sizeBytes,
    Duration? duration,
    DateTime? recordedAt,
    SyncStatus? syncStatus,
    double? syncProgress,
    bool? isPlaying,
  }) {
    return AudioClip(
      filename: filename ?? this.filename,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      duration: duration ?? this.duration,
      recordedAt: recordedAt ?? this.recordedAt,
      syncStatus: syncStatus ?? this.syncStatus,
      syncProgress: syncProgress ?? this.syncProgress,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}
