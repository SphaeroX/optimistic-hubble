import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictula/core/audio/audio_editor_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioEditorService Tests', () {
    test('generateBeepPcm produces non-empty sinusoidal PCM buffer with correct length', () {
      final pcm = AudioEditorService.generateBeepPcm(
        durationMs: 100,
        frequencyHz: 880,
        sampleRate: 16000,
      );

      // 16000 samples/sec * 0.1s = 1600 samples * 2 bytes/sample = 3200 bytes
      expect(pcm.length, equals(3200));
      expect(pcm.any((b) => b != 0), isTrue);
    });

    test('createWavFromPcm produces standard 44-byte RIFF/WAVE header', () {
      final pcm = Uint8List(1600); // 800 samples
      final wav = AudioEditorService.createWavFromPcm(
        pcmData: pcm,
        sampleRate: 16000,
        numChannels: 1,
        bitsPerSample: 16,
      );

      expect(wav.length, equals(44 + 1600));

      final riff = String.fromCharCodes(wav.sublist(0, 4));
      final wave = String.fromCharCodes(wav.sublist(8, 12));
      final fmt = String.fromCharCodes(wav.sublist(12, 16));
      final data = String.fromCharCodes(wav.sublist(36, 40));

      expect(riff, equals('RIFF'));
      expect(wave, equals('WAVE'));
      expect(fmt, equals('fmt '));
      expect(data, equals('data'));

      expect(AudioEditorService.getSampleRate(wav), equals(16000));
      expect(AudioEditorService.getChannels(wav), equals(1));
      expect(AudioEditorService.getBitsPerSample(wav), equals(16));
    });

    test('trimWavBytes correctly truncates audio at cutoff time', () {
      // 2 seconds audio @ 16kHz 16-bit Mono = 32000 samples = 64000 PCM bytes
      final pcm = Uint8List(64000);
      final wav = AudioEditorService.createWavFromPcm(pcmData: pcm, sampleRate: 16000);

      // Cutoff at 1.0 second -> should have 32000 PCM bytes + 44 header bytes
      final trimmed = AudioEditorService.trimWavBytes(wav, const Duration(seconds: 1));
      expect(trimmed.length, equals(44 + 32000));
      expect(AudioEditorService.extractPcmData(trimmed).length, equals(32000));
    });
  });
}
