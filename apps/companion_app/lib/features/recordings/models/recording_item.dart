enum SyncState {
  onDevice,    // Clip is on ESP32 LittleFS flash only
  downloading, // Wi-Fi transfer in progress
  synced,      // Downloaded and converted to WAV on local disk
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
  });

  factory RecordingItem.fromApiJson(Map<String, dynamic> json) {
    final int id = json['id'] as int? ?? 1;
    final String name = json['filename'] as String? ?? 'clip_$id.adpcm';
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
    );
  }
}
