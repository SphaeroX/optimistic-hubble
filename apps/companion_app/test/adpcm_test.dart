import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dictula/core/audio/adpcm_decoder.dart';

Uint8List _createSampleImaAdpcmWav(int sampleCount, int sampleRate) {
  final adpcmBytes = sampleCount ~/ 2;
  final chunkSize = 36 + 14 + adpcmBytes;
  final header = ByteData(60);

  // RIFF
  header.setUint8(0, 0x52); header.setUint8(1, 0x49); header.setUint8(2, 0x46); header.setUint8(3, 0x46);
  header.setUint32(4, chunkSize, Endian.little);
  header.setUint8(8, 0x57); header.setUint8(9, 0x41); header.setUint8(10, 0x56); header.setUint8(11, 0x45);

  // fmt (size 20, format 0x0011)
  header.setUint8(12, 0x66); header.setUint8(13, 0x6D); header.setUint8(14, 0x74); header.setUint8(15, 0x20);
  header.setUint32(16, 20, Endian.little);
  header.setUint16(20, 0x0011, Endian.little); // IMA ADPCM
  header.setUint16(22, 1, Endian.little);       // Mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, (sampleRate * 4) ~/ 8, Endian.little);
  header.setUint16(32, 1, Endian.little);
  header.setUint16(34, 4, Endian.little);       // 4-bit
  header.setUint16(36, 2, Endian.little);
  header.setUint16(38, 1, Endian.little);

  // fact
  header.setUint8(40, 0x66); header.setUint8(41, 0x61); header.setUint8(42, 0x63); header.setUint8(43, 0x74);
  header.setUint32(44, 4, Endian.little);
  header.setUint32(48, sampleCount, Endian.little);

  // data
  header.setUint8(52, 0x64); header.setUint8(53, 0x61); header.setUint8(54, 0x74); header.setUint8(55, 0x61);
  header.setUint32(56, adpcmBytes, Endian.little);

  final full = Uint8List(60 + adpcmBytes);
  full.setRange(0, 60, header.buffer.asUint8List());
  for (int i = 0; i < adpcmBytes; i++) {
    full[60 + i] = (i % 256);
  }
  return full;
}

void main() {
  group('AdpcmDecoder Tests', () {
    test('Decodes zero ADPCM buffer to PCM samples', () {
      final adpcmBytes = Uint8List(10); // 10 bytes = 20 samples
      final pcm = AdpcmDecoder.decodeAdpcmToPcm(adpcmBytes);

      expect(pcm.length, 20);
      for (final sample in pcm) {
        expect(sample, 0);
      }
    });

    test('Creates valid standard 44-byte RIFF/WAVE header', () {
      final pcm = Int16List(16000); // 1 sec at 16 kHz
      final wav = AdpcmDecoder.createWavFile(pcmSamples: pcm, sampleRate: 16000);

      expect(wav.length, 44 + 32000);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(AdpcmDecoder.isLinearPcmWav(wav), true);
    });

    test('Direct ADPCM to WAV stream conversion', () {
      final adpcm = Uint8List(8000); // 1 sec of 4-bit ADPCM
      final wav = AdpcmDecoder.decodeAdpcmToWav(adpcm, sampleRate: 16000);

      expect(wav.length, 32044);
      expect(AdpcmDecoder.isLinearPcmWav(wav), true);
    });

    test('ensureLinearPcmWav converts ESP32 60-byte IMA-ADPCM WAV to standard Linear PCM WAV', () {
      // 16000 samples = 8000 bytes ADPCM -> 60 bytes header + 8000 = 8060 bytes
      final imaAdpcmWav = _createSampleImaAdpcmWav(16000, 16000);
      expect(imaAdpcmWav.length, 8060);
      expect(AdpcmDecoder.isLinearPcmWav(imaAdpcmWav), false);

      final pcmWav = AdpcmDecoder.ensureLinearPcmWav(imaAdpcmWav);

      // Decoded output: 44 bytes standard header + 32000 bytes (16000 16-bit samples) = 32044 bytes
      expect(pcmWav.length, 32044);
      expect(AdpcmDecoder.isLinearPcmWav(pcmWav), true);

      // Check formatTag is 1 (Linear PCM)
      final bd = ByteData.sublistView(pcmWav);
      expect(bd.getUint16(20, Endian.little), 1);
      expect(bd.getUint16(22, Endian.little), 1); // Mono
      expect(bd.getUint32(24, Endian.little), 16000); // 16 kHz
      expect(bd.getUint16(34, Endian.little), 16); // 16-bit
    });

    test('ensureLinearPcmWav leaves valid Linear PCM WAV unchanged', () {
      final pcm = Int16List(8000);
      final validWav = AdpcmDecoder.createWavFile(pcmSamples: pcm, sampleRate: 16000);

      final result = AdpcmDecoder.ensureLinearPcmWav(validWav);
      expect(result, same(validWav));
    });

    test('ensureFileIsLinearPcmWav converts file on disk in-place', () async {
      final tempDir = Directory.systemTemp.createTempSync('adpcm_test_');
      try {
        final testFile = File('${tempDir.path}/test_clip.wav');
        final imaAdpcmWav = _createSampleImaAdpcmWav(4000, 16000);
        await testFile.writeAsBytes(imaAdpcmWav);

        expect(testFile.lengthSync(), 60 + 2000);

        final convertedFile = await AdpcmDecoder.ensureFileIsLinearPcmWav(testFile);
        expect(convertedFile.path, testFile.path);

        // 4000 samples * 2 bytes + 44 = 8044 bytes
        expect(convertedFile.lengthSync(), 8044);

        final bytes = await convertedFile.readAsBytes();
        expect(AdpcmDecoder.isLinearPcmWav(bytes), true);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });
}
