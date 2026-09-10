import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictula/core/audio/adpcm_decoder.dart';
import 'package:dictula/core/services/audio_share_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioShareService Tests', () {
    test('Returns failure when filePath is null', () async {
      final result = await AudioShareService.shareAudio(filePath: null, title: 'Test');
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('Keine Audiodatei'));
    });

    test('Returns failure when filePath does not exist on disk', () async {
      final result = await AudioShareService.shareAudio(
        filePath: '/non/existent/path/audio.wav',
        title: 'Test',
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('existiert lokal nicht'));
    });

    test('Returns failure when audio file is empty', () async {
      final tempDir = await Directory.systemTemp.createTemp('audio_share_test_');
      final emptyFile = File('${tempDir.path}/empty.wav');
      await emptyFile.writeAsBytes([]);

      final result = await AudioShareService.shareAudio(
        filePath: emptyFile.path,
        title: 'Empty Audio',
      );
      expect(result.success, isFalse);
      expect(result.errorMessage, contains('ist leer'));

      await tempDir.delete(recursive: true);
    });

    test('Validates linear PCM WAV generation from ADPCM samples', () {
      final rawAdpcm = Uint8List.fromList([0x12, 0x34, 0x56, 0x78]);
      final wavBytes = AdpcmDecoder.decodeAdpcmToWav(rawAdpcm);

      expect(AdpcmDecoder.isLinearPcmWav(wavBytes), isTrue);
      expect(wavBytes.length, greaterThan(44));
    });
  });
}
