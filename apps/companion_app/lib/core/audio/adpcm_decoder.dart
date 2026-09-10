import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// High-Performance IMA-ADPCM 4-bit to 16-bit Linear PCM Audio Decoder & WAV Generator.
/// Matches the ESP32-C3 firmware implementation in firmware/src/adpcm.cpp.
class AdpcmDecoder {
  AdpcmDecoder._();

  static const List<int> _stepTable = [
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
    19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
    876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
    5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
  ];

  static const List<int> _indexTable = [
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8
  ];

  /// Decodes 4-bit IMA-ADPCM encoded bytes into 16-bit signed PCM samples.
  /// Each input byte contains two 4-bit ADPCM nibbles (Low nibble first, then High nibble).
  static Int16List decodeAdpcmToPcm(Uint8List adpcmData) {
    final int numSamples = adpcmData.length * 2;
    final Int16List pcm = Int16List(numSamples);

    int predictor = 0;
    int stepIndex = 0;
    int pcmIndex = 0;

    for (int i = 0; i < adpcmData.length; ++i) {
      final int byteVal = adpcmData[i];

      // Sample 1: Low 4 bits
      final int nibble1 = byteVal & 0x0F;
      predictor = _decodeNibble(nibble1, predictor, stepIndex);
      stepIndex = _updateStepIndex(nibble1, stepIndex);
      pcm[pcmIndex++] = predictor;

      // Sample 2: High 4 bits
      final int nibble2 = (byteVal >> 4) & 0x0F;
      predictor = _decodeNibble(nibble2, predictor, stepIndex);
      stepIndex = _updateStepIndex(nibble2, stepIndex);
      pcm[pcmIndex++] = predictor;
    }

    return pcm;
  }

  static int _decodeNibble(int nibble, int predictor, int stepIndex) {
    final int step = _stepTable[stepIndex];
    int diff = step >> 3;

    if ((nibble & 0x04) != 0) diff += step;
    if ((nibble & 0x02) != 0) diff += (step >> 1);
    if ((nibble & 0x01) != 0) diff += (step >> 2);

    if ((nibble & 0x08) != 0) {
      predictor -= diff;
    } else {
      predictor += diff;
    }

    // Clamp to signed 16-bit integer range [-32768, 32767]
    if (predictor > 32767) return 32767;
    if (predictor < -32768) return -32768;
    return predictor;
  }

  static int _updateStepIndex(int nibble, int stepIndex) {
    int nextIndex = stepIndex + _indexTable[nibble & 0x0F];
    if (nextIndex < 0) nextIndex = 0;
    if (nextIndex > 88) nextIndex = 88;
    return nextIndex;
  }

  /// Wraps 16-bit PCM samples in a standard 44-byte Linear PCM RIFF/WAVE header.
  static Uint8List createWavFile({
    required Int16List pcmSamples,
    int sampleRate = 16000,
    int numChannels = 1,
  }) {
    final int bitsPerSample = 16;
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int byteRate = sampleRate * blockAlign;
    final int dataSize = pcmSamples.length * 2; // 2 bytes per 16-bit sample
    final int totalFileSize = 44 + dataSize;

    final ByteData header = ByteData(44);

    // 0..3 "RIFF"
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F

    // 4..7 Overall file size minus 8 bytes (little endian)
    header.setUint32(4, totalFileSize - 8, Endian.little);

    // 8..11 "WAVE"
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E

    // 12..15 "fmt " chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '

    // 16..19 fmt chunk size (16 for PCM format)
    header.setUint32(16, 16, Endian.little);

    // 20..21 Audio format (1 = Linear PCM)
    header.setUint16(20, 1, Endian.little);

    // 22..23 Channels (1 = Mono)
    header.setUint16(22, numChannels, Endian.little);

    // 24..27 Sample Rate (e.g. 16000 Hz)
    header.setUint32(24, sampleRate, Endian.little);

    // 28..31 Byte Rate (SampleRate * NumChannels * BitsPerSample/8)
    header.setUint32(28, byteRate, Endian.little);

    // 32..33 Block Align (NumChannels * BitsPerSample/8)
    header.setUint16(32, blockAlign, Endian.little);

    // 34..35 Bits per sample (16)
    header.setUint16(34, bitsPerSample, Endian.little);

    // 36..39 "data" chunk header
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a

    // 40..43 Data subchunk size (bytes of PCM data)
    header.setUint32(40, dataSize, Endian.little);

    // Combine Header + PCM bytes
    final Uint8List wavBytes = Uint8List(totalFileSize);
    wavBytes.setRange(0, 44, header.buffer.asUint8List());

    // Copy 16-bit PCM samples into wavBytes buffer (little-endian)
    final Uint8List pcmRawBytes = pcmSamples.buffer.asUint8List();
    wavBytes.setRange(44, totalFileSize, pcmRawBytes);

    return wavBytes;
  }

  /// Directly decodes an ADPCM byte stream into a playable WAV file buffer.
  static Uint8List decodeAdpcmToWav(Uint8List adpcmData, {int sampleRate = 16000}) {
    final Int16List pcm = decodeAdpcmToPcm(adpcmData);
    return createWavFile(pcmSamples: pcm, sampleRate: sampleRate);
  }

  /// Checks if a byte buffer contains a standard Linear PCM WAV file.
  static bool isLinearPcmWav(Uint8List bytes) {
    if (bytes.length < 44) return false;
    final bool isRiff = bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46;
    final bool isWave = bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45;
    if (!isRiff || !isWave) return false;

    final bd = ByteData.sublistView(bytes);
    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bd.getUint32(offset + 4, Endian.little);
      final chunkDataOffset = offset + 8;
      if (chunkId == 'fmt ') {
        if (chunkDataOffset + 16 <= bytes.length) {
          final formatTag = bd.getUint16(chunkDataOffset, Endian.little);
          final bitsPerSample = bd.getUint16(chunkDataOffset + 14, Endian.little);
          return formatTag == 1 && bitsPerSample == 16;
        }
      }
      offset = chunkDataOffset + chunkSize + (chunkSize % 2);
    }
    return false;
  }

  /// Ensures that the provided audio data is converted to a standard 16-bit Linear PCM WAV.
  /// If [bytes] is already a valid Linear PCM WAV file, it is returned unchanged.
  /// If [bytes] contains a RIFF container with IMA-ADPCM (format 0x0011) or raw ADPCM data,
  /// it is decoded and wrapped in a standard 44-byte Linear PCM WAV header.
  static Uint8List ensureLinearPcmWav(Uint8List bytes, {int defaultSampleRate = 16000}) {
    if (bytes.length < 12) {
      return bytes;
    }

    final bool isRiff = bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46; // "RIFF"
    final bool isWave = bytes.length >= 12 && bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45; // "WAVE"

    if (isRiff && isWave) {
      final ByteData bd = ByteData.sublistView(bytes);
      int offset = 12;
      int formatTag = 0;
      int numChannels = 1;
      int sampleRate = defaultSampleRate;
      int bitsPerSample = 16;
      int dataOffset = -1;
      int dataSize = 0;

      while (offset + 8 <= bytes.length) {
        final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        final chunkSize = bd.getUint32(offset + 4, Endian.little);
        final chunkDataOffset = offset + 8;

        if (chunkId == 'fmt ') {
          if (chunkDataOffset + 16 <= bytes.length) {
            formatTag = bd.getUint16(chunkDataOffset, Endian.little);
            numChannels = bd.getUint16(chunkDataOffset + 2, Endian.little);
            sampleRate = bd.getUint32(chunkDataOffset + 4, Endian.little);
            bitsPerSample = bd.getUint16(chunkDataOffset + 14, Endian.little);
          }
        } else if (chunkId == 'data') {
          dataOffset = chunkDataOffset;
          dataSize = chunkSize;
          if (dataOffset + dataSize > bytes.length) {
            dataSize = bytes.length - dataOffset;
          }
          break;
        }

        offset = chunkDataOffset + chunkSize + (chunkSize % 2);
      }

      // If already standard Linear PCM (16-bit), return immediately
      if (formatTag == 1 && bitsPerSample == 16) {
        return bytes;
      }

      // Extract ADPCM data subchunk
      Uint8List adpcmPayload;
      if (dataOffset >= 0 && dataOffset < bytes.length) {
        adpcmPayload = bytes.sublist(dataOffset, dataOffset + dataSize);
      } else if (bytes.length > 60) {
        adpcmPayload = bytes.sublist(60);
      } else if (bytes.length > 44) {
        adpcmPayload = bytes.sublist(44);
      } else {
        adpcmPayload = Uint8List(0);
      }

      final Int16List pcmSamples = decodeAdpcmToPcm(adpcmPayload);
      return createWavFile(
        pcmSamples: pcmSamples,
        sampleRate: sampleRate > 0 ? sampleRate : defaultSampleRate,
        numChannels: numChannels > 0 ? numChannels : 1,
      );
    } else {
      // Raw ADPCM stream without RIFF container
      final Int16List pcmSamples = decodeAdpcmToPcm(bytes);
      return createWavFile(
        pcmSamples: pcmSamples,
        sampleRate: defaultSampleRate,
        numChannels: 1,
      );
    }
  }

  /// Verifies a file on disk and converts it in-place to 16-bit Linear PCM WAV if needed.
  static Future<File> ensureFileIsLinearPcmWav(File file, {int defaultSampleRate = 16000}) async {
    if (!file.existsSync()) return file;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length < 12) return file;

      if (isLinearPcmWav(bytes)) {
        return file;
      }

      final convertedBytes = ensureLinearPcmWav(bytes, defaultSampleRate: defaultSampleRate);
      await file.writeAsBytes(convertedBytes, flush: true);
      debugPrint('[AdpcmDecoder] Converted ${file.path} to standard 16-bit Linear PCM WAV (${convertedBytes.length} bytes)');
    } catch (e) {
      debugPrint('[AdpcmDecoder] Error checking/converting file ${file.path}: $e');
    }
    return file;
  }
}
