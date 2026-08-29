import 'package:flutter_test/flutter_test.dart';
import 'package:dictula/features/recordings/models/dictula_recording.dart';
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
  });
}
