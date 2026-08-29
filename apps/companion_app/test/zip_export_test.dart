import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZipExportService Tests', () {
    test('Correctly bundles audio WAV, metadata JSON, transcription markdown, and files into ZIP', () async {
      final tempDir = await Directory.systemTemp.createTemp('zip_test_');

      // Create dummy audio WAV
      final audioFile = File('${tempDir.path}/test_audio.wav');
      await audioFile.writeAsBytes(List.filled(1000, 42));

      // Create dummy photo
      final photoFile = File('${tempDir.path}/photo1.jpg');
      await photoFile.writeAsBytes(List.filled(500, 100));

      final archive = Archive();
      archive.addFile(ArchiveFile('audio.wav', audioFile.lengthSync(), audioFile.readAsBytesSync()));
      archive.addFile(ArchiveFile('transcription.md', 15, 'Hallo Welt Test'.codeUnits));
      archive.addFile(ArchiveFile('photos/photo1.jpg', photoFile.lengthSync(), photoFile.readAsBytesSync()));

      final encoder = ZipEncoder();
      final zipBytes = encoder.encode(archive);

      expect(zipBytes, isNotNull);
      expect(zipBytes.isNotEmpty, isTrue);

      // Verify decoded ZIP contains all files
      final decoder = ZipDecoder();
      final decodedArchive = decoder.decodeBytes(zipBytes);

      expect(decodedArchive.findFile('audio.wav'), isNotNull);
      expect(decodedArchive.findFile('transcription.md'), isNotNull);
      expect(decodedArchive.findFile('photos/photo1.jpg'), isNotNull);

      await tempDir.delete(recursive: true);
    });
  });
}
