import 'package:intl/intl.dart';
import '../../ai_gemini/services/gemini_service.dart';
import 'recording_item.dart';

enum RecordingSource {
  phone,
  hardware,
}

/// Unified data model for all recordings within Dictula (Mobile & Hardware).
class DictulaRecording {
  final String id;
  final String title;
  final String localWavPath;
  final Duration duration;
  final int fileSizeBytes;
  final DateTime recordedAt;
  final bool isPinned;
  final String? groupId;
  final List<String> photoPaths;
  final List<String> attachmentPaths;
  final String? transcription;
  final List<GeminiChatMessage> chatHistory;
  final RecordingSource source;
  final int? hardwareClipId;
  final SyncState syncState;
  final List<double> waveformSamples;

  DictulaRecording({
    required this.id,
    required this.title,
    required this.localWavPath,
    required this.duration,
    required this.fileSizeBytes,
    required this.recordedAt,
    this.isPinned = false,
    this.groupId,
    List<String>? photoPaths,
    List<String>? attachmentPaths,
    this.transcription,
    List<GeminiChatMessage>? chatHistory,
    this.source = RecordingSource.phone,
    this.hardwareClipId,
    this.syncState = SyncState.synced,
    List<double>? waveformSamples,
  })  : photoPaths = photoPaths ?? const [],
        attachmentPaths = attachmentPaths ?? const [],
        chatHistory = chatHistory ?? const [],
        waveformSamples = waveformSamples ?? const [];

  String get formattedDate => DateFormat('dd.MM.yyyy HH:mm').format(recordedAt);
  String get formattedDuration {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${duration.inHours > 0 ? '${duration.inHours}:' : ''}$minutes:$seconds';
  }

  bool get hasTranscription => transcription != null && transcription!.trim().isNotEmpty;
  bool get hasAttachments => photoPaths.isNotEmpty || attachmentPaths.isNotEmpty;

  DictulaRecording copyWith({
    String? id,
    String? title,
    String? localWavPath,
    Duration? duration,
    int? fileSizeBytes,
    DateTime? recordedAt,
    bool? isPinned,
    String? groupId,
    List<String>? photoPaths,
    List<String>? attachmentPaths,
    String? transcription,
    List<GeminiChatMessage>? chatHistory,
    RecordingSource? source,
    int? hardwareClipId,
    SyncState? syncState,
    List<double>? waveformSamples,
  }) {
    return DictulaRecording(
      id: id ?? this.id,
      title: title ?? this.title,
      localWavPath: localWavPath ?? this.localWavPath,
      duration: duration ?? this.duration,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      recordedAt: recordedAt ?? this.recordedAt,
      isPinned: isPinned ?? this.isPinned,
      groupId: groupId ?? this.groupId,
      photoPaths: photoPaths ?? this.photoPaths,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
      transcription: transcription ?? this.transcription,
      chatHistory: chatHistory ?? this.chatHistory,
      source: source ?? this.source,
      hardwareClipId: hardwareClipId ?? this.hardwareClipId,
      syncState: syncState ?? this.syncState,
      waveformSamples: waveformSamples ?? this.waveformSamples,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'localWavPath': localWavPath,
        'durationMs': duration.inMilliseconds,
        'fileSizeBytes': fileSizeBytes,
        'recordedAt': recordedAt.toIso8601String(),
        'isPinned': isPinned,
        'groupId': groupId,
        'photoPaths': photoPaths,
        'attachmentPaths': attachmentPaths,
        'transcription': transcription,
        'chatHistory': chatHistory.map((m) => m.toJson()).toList(),
        'source': source.name,
        'hardwareClipId': hardwareClipId,
        'syncState': syncState.name,
        'waveformSamples': waveformSamples,
      };

  factory DictulaRecording.fromJson(Map<String, dynamic> json) => DictulaRecording(
        id: json['id'] as String? ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: json['title'] as String? ?? 'Sprachnotiz',
        localWavPath: json['localWavPath'] as String? ?? '',
        duration: Duration(milliseconds: json['durationMs'] as int? ?? 0),
        fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
        recordedAt: DateTime.tryParse(json['recordedAt'] as String? ?? '') ?? DateTime.now(),
        isPinned: json['isPinned'] as bool? ?? false,
        groupId: json['groupId'] as String?,
        photoPaths: (json['photoPaths'] as List?)?.map((e) => e.toString()).toList() ?? [],
        attachmentPaths: (json['attachmentPaths'] as List?)?.map((e) => e.toString()).toList() ?? [],
        transcription: json['transcription'] as String?,
        chatHistory: (json['chatHistory'] as List?)
                ?.map((e) => GeminiChatMessage.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        source: json['source'] == 'hardware' ? RecordingSource.hardware : RecordingSource.phone,
        hardwareClipId: json['hardwareClipId'] as int?,
        syncState: SyncState.values.firstWhere(
          (s) => s.name == (json['syncState'] as String? ?? 'synced'),
          orElse: () => SyncState.synced,
        ),
        waveformSamples: (json['waveformSamples'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
      );
}
