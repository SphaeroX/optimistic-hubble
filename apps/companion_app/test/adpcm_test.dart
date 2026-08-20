import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:companion_app/core/audio/adpcm_decoder.dart';

void main() {
  group('AdpcmDecoder Tests', () {
    test('Decodes zero ADPCM buffer to PCM samples', () {
      final adpcmBytes = Uint8List(10); // 10 bytes = 20 samples
      final pcm = AdpcmDecoder.decodeAdpcmToPcm(adpcmBytes);

      expect(pcm.length, 20);
      // All samples decoded from zero should be zero
      for (final sample in pcm) {
        expect(sample, 0);
      }
    });

    test('Creates valid standard 44-byte RIFF/WAVE header', () {
      final pcm = Int16List(16000); // 1 sec at 16 kHz
      final wav = AdpcmDecoder.createWavFile(pcmSamples: pcm, sampleRate: 16000);

      expect(wav.length, 44 + 32000);
      // Check RIFF magic
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      // Check WAVE magic
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      // Check fmt subchunk
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      // Check data subchunk
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    });

    test('Direct ADPCM to WAV stream conversion', () {
      final adpcm = Uint8List(8000); // 1 sec of 4-bit ADPCM
      final wav = AdpcmDecoder.decodeAdpcmToWav(adpcm, sampleRate: 16000);

      // 8000 bytes ADPCM = 16000 samples = 32000 bytes PCM + 44 bytes header = 32044 bytes
      expect(wav.length, 32044);
    });
  });
}
