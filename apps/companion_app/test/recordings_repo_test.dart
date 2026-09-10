import 'package:flutter_test/flutter_test.dart';
import 'package:dictula/features/recordings/models/dictula_recording.dart';
import 'package:dictula/features/recordings/models/recording_item.dart';
import 'package:dictula/features/groups/models/recording_group.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecordingsRepository Tests', () {
    test('DictulaRecording JSON serialization and deserialization roundtrip', () {
      final now = DateTime.now();
      final rec = DictulaRecording(
        id: 'rec_12345',
        title: 'Meeting Notiz',
        localWavPath: '/path/to/rec.wav',
        duration: const Duration(minutes: 2, seconds: 15),
        fileSizeBytes: 65536,
        recordedAt: now,
        isPinned: true,
        groupId: 'grp_daily',
        photoPaths: ['/path/to/img1.jpg'],
        attachmentPaths: ['/path/to/doc.pdf'],
        transcription: 'Das ist ein wichtiges Meeting-Protokoll.',
        source: RecordingSource.phone,
        waveformSamples: [0.1, 0.4, 0.8, 0.2],
      );

      final json = rec.toJson();
      final fromJson = DictulaRecording.fromJson(json);

      expect(fromJson.id, equals('rec_12345'));
      expect(fromJson.title, equals('Meeting Notiz'));
      expect(fromJson.isPinned, isTrue);
      expect(fromJson.groupId, equals('grp_daily'));
      expect(fromJson.photoPaths.length, equals(1));
      expect(fromJson.attachmentPaths.length, equals(1));
      expect(fromJson.transcription, equals('Das ist ein wichtiges Meeting-Protokoll.'));
      expect(fromJson.waveformSamples.length, equals(4));
    });

    test('RecordingGroup JSON serialization roundtrip', () {
      final group = RecordingGroup(
        id: 'grp_001',
        name: 'Tagesberichte',
        description: 'Tägliche Protokolle',
        colorValue: 0xFF00E5FF,
        createdAt: DateTime.now(),
      );

      final json = group.toJson();
      final fromJson = RecordingGroup.fromJson(json);

      expect(fromJson.id, equals('grp_001'));
      expect(fromJson.name, equals('Tagesberichte'));
      expect(fromJson.colorValue, equals(0xFF00E5FF));
    });

    test('registerPendingHardwareClips and pruneUnsyncedHardwareClips lifecycle', () {
      final repo = FakeRecordingsRepository();

      final hwClips = [
        RecordingItem(
          id: 1,
          remoteFilename: 'clip_001.wav',
          sizeBytes: 64000,
          duration: const Duration(seconds: 8),
          sampleRate: 16000,
          recordedAt: DateTime.now(),
          syncState: SyncState.onDevice,
        ),
        RecordingItem(
          id: 2,
          remoteFilename: 'clip_002.wav',
          sizeBytes: 128000,
          duration: const Duration(seconds: 16),
          sampleRate: 16000,
          recordedAt: DateTime.now(),
          syncState: SyncState.onDevice,
        ),
      ];

      repo.registerPendingHardwareClips(hwClips);
      expect(repo.recordings.length, 2);
      expect(repo.recordings.any((r) => r.hardwareClipId == 1 && r.syncState == SyncState.onDevice), isTrue);
      expect(repo.recordings.any((r) => r.hardwareClipId == 2 && r.syncState == SyncState.onDevice), isTrue);

      // Prune if device reports only 1 clip remains
      repo.pruneUnsyncedHardwareClips(1);
      expect(repo.recordings.length, 1);
      expect(repo.recordings.first.hardwareClipId, 1);
    });

    test('deleteMultipleRecordings removes all targeted recordings from list', () {
      final repo = FakeRecordingsRepository();
      repo.addFakeRecording('rec_1');
      repo.addFakeRecording('rec_2');
      repo.addFakeRecording('rec_3');
      expect(repo.recordings.length, 3);

      repo.deleteMultipleRecordings({'rec_1', 'rec_3'});
      expect(repo.recordings.length, 1);
      expect(repo.recordings.first.id, 'rec_2');
    });
  });
}

class FakeRecordingsRepository {
  final List<DictulaRecording> _recordings = [];
  List<DictulaRecording> get recordings => List.unmodifiable(_recordings);

  void registerPendingHardwareClips(List<RecordingItem> hwClips) {
    for (final clip in hwClips) {
      final existingIndex = _recordings.indexWhere((r) => r.hardwareClipId == clip.id);
      if (existingIndex == -1) {
        _recordings.insert(0, DictulaRecording(
          id: 'hw_${clip.id}',
          title: 'Hardware Aufnahme #${clip.id.toString().padLeft(3, '0')}',
          localWavPath: clip.localWavPath ?? '',
          duration: clip.duration,
          fileSizeBytes: clip.sizeBytes,
          recordedAt: clip.recordedAt,
          source: RecordingSource.hardware,
          hardwareClipId: clip.id,
          syncState: clip.syncState,
        ));
      }
    }
  }

  void pruneUnsyncedHardwareClips(int totalClipsOnDevice) {
    _recordings.removeWhere((r) {
      if (r.source == RecordingSource.hardware && r.syncState != SyncState.synced) {
        return (r.hardwareClipId == null || r.hardwareClipId! > totalClipsOnDevice || totalClipsOnDevice == 0);
      }
      return false;
    });
  }

  void addFakeRecording(String id) {
    _recordings.add(DictulaRecording(
      id: id,
      title: 'Recording $id',
      localWavPath: '/path/to/$id.wav',
      duration: const Duration(seconds: 10),
      fileSizeBytes: 1024,
      recordedAt: DateTime.now(),
      source: RecordingSource.phone,
    ));
  }

  void deleteMultipleRecordings(Iterable<String> ids) {
    final idSet = ids.toSet();
    _recordings.removeWhere((r) => idSet.contains(r.id));
  }
}
