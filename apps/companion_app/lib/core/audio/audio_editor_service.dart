import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

/// Service for WAV file editing, punch-in trimming, beep tone synthesis, and audio concatenation.
class AudioEditorService {
  AudioEditorService._();

  /// Generates a synthetic sinusoidal PCM beep tone (16-bit Mono PCM).
  /// [durationMs]: duration in milliseconds (default 90ms)
  /// [frequencyHz]: frequency in Hertz (default 880 Hz)
  /// [sampleRate]: audio sample rate (default 16000 Hz)
  static Uint8List generateBeepPcm({
    int durationMs = 90,
    double frequencyHz = 880.0,
    int sampleRate = 16000,
    double volume = 0.6,
  }) {
    final int totalSamples = (sampleRate * (durationMs / 1000.0)).round();
    final ByteData byteData = ByteData(totalSamples * 2);

    final int attackSamples = (sampleRate * 0.01).round(); // 10ms attack
    final int decaySamples = (sampleRate * 0.015).round(); // 15ms decay

    for (int i = 0; i < totalSamples; i++) {
      final double t = i / sampleRate;
      double amplitude = sin(2 * pi * frequencyHz * t) * volume;

      // Envelope to eliminate audible clicking
      if (i < attackSamples) {
        amplitude *= (i / attackSamples);
      } else if (i > totalSamples - decaySamples) {
        amplitude *= ((totalSamples - i) / decaySamples);
      }

      final int sampleValue = (amplitude * 32767.0).clamp(-32768.0, 32767.0).round();
      byteData.setInt16(i * 2, sampleValue, Endian.little);
    }

    return byteData.buffer.asUint8List();
  }

  /// Trims an existing WAV file up to [cutoffTime], discarding all subsequent audio.
  /// Returns the trimmed WAV file bytes.
  static Future<Uint8List?> trimWavFile(File wavFile, Duration cutoffTime) async {
    if (!await wavFile.exists()) return null;
    final Uint8List bytes = await wavFile.readAsBytes();
    return trimWavBytes(bytes, cutoffTime);
  }

  /// Trims WAV bytes up to [cutoffTime].
  static Uint8List trimWavBytes(Uint8List wavBytes, Duration cutoffTime) {
    if (wavBytes.length < 44) return wavBytes;

    final ByteData byteData = ByteData.sublistView(wavBytes);
    
    // Validate 'RIFF' and 'WAVE'
    final String riff = String.fromCharCodes(wavBytes.sublist(0, 4));
    final String wave = String.fromCharCodes(wavBytes.sublist(8, 12));
    if (riff != 'RIFF' || wave != 'WAVE') {
      debugPrint('[AudioEditorService] Warning: Not a standard RIFF/WAVE header');
      return wavBytes;
    }

    // Read Channels & Sample Rate
    final int channels = byteData.getUint16(22, Endian.little);
    final int sampleRate = byteData.getUint32(24, Endian.little);
    final int bitsPerSample = byteData.getUint16(34, Endian.little);
    final int bytesPerSample = (bitsPerSample / 8).round() * channels;

    // Find 'data' subchunk
    int dataOffset = 12;
    int dataSize = 0;
    while (dataOffset + 8 <= wavBytes.length) {
      final String chunkId = String.fromCharCodes(wavBytes.sublist(dataOffset, dataOffset + 4));
      final int chunkSize = byteData.getUint32(dataOffset + 4, Endian.little);
      if (chunkId == 'data') {
        dataOffset += 8;
        dataSize = chunkSize;
        break;
      }
      dataOffset += 8 + chunkSize;
    }

    if (dataOffset >= wavBytes.length) {
      dataOffset = 44;
      dataSize = wavBytes.length - 44;
    }

    final double cutoffSec = cutoffTime.inMilliseconds / 1000.0;
    int targetPcmBytes = (cutoffSec * sampleRate * bytesPerSample).round();
    // Align to sample boundary
    targetPcmBytes -= (targetPcmBytes % bytesPerSample);

    if (targetPcmBytes > dataSize) {
      targetPcmBytes = dataSize;
    } else if (targetPcmBytes < 0) {
      targetPcmBytes = 0;
    }

    final Uint8List trimmedPcm = wavBytes.sublist(dataOffset, dataOffset + targetPcmBytes);
    return createWavFromPcm(
      pcmData: trimmedPcm,
      sampleRate: sampleRate,
      numChannels: channels,
      bitsPerSample: bitsPerSample,
    );
  }

  /// Concatenates two WAV files (or WAV + Beep + WAV) with identical or normalized audio format.
  static Future<File> punchInAndConcatWav({
    required File baseWavFile,
    required Duration cutoffPoint,
    required File newWavChunkFile,
    required File outputFile,
    bool insertBeep = true,
  }) async {
    final Uint8List baseWavBytes = await baseWavFile.readAsBytes();
    final Uint8List trimmedBaseWav = trimWavBytes(baseWavBytes, cutoffPoint);

    final Uint8List basePcm = extractPcmData(trimmedBaseWav);
    final int sampleRate = getSampleRate(trimmedBaseWav);
    final int channels = getChannels(trimmedBaseWav);
    final int bitsPerSample = getBitsPerSample(trimmedBaseWav);

    final Uint8List newChunkWavBytes = await newWavChunkFile.readAsBytes();
    final Uint8List newChunkPcm = extractPcmData(newChunkWavBytes);

    final BytesBuilder pcmBuilder = BytesBuilder();
    pcmBuilder.add(basePcm);

    if (insertBeep && basePcm.isNotEmpty) {
      final Uint8List beepPcm = generateBeepPcm(
        durationMs: 80,
        frequencyHz: 880,
        sampleRate: sampleRate,
      );
      pcmBuilder.add(beepPcm);
    }

    pcmBuilder.add(newChunkPcm);

    final Uint8List combinedWav = createWavFromPcm(
      pcmData: pcmBuilder.toBytes(),
      sampleRate: sampleRate,
      numChannels: channels,
      bitsPerSample: bitsPerSample,
    );

    await outputFile.writeAsBytes(combinedWav, flush: true);
    return outputFile;
  }

  /// Appends a new WAV recording chunk to an existing WAV file.
  static Future<File> appendWavChunks({
    required File originalWavFile,
    required File appendedWavFile,
    required File outputFile,
    bool insertBeep = false,
  }) async {
    final Uint8List originalBytes = await originalWavFile.readAsBytes();
    final Uint8List appendedBytes = await appendedWavFile.readAsBytes();

    final Uint8List originalPcm = extractPcmData(originalBytes);
    final Uint8List appendedPcm = extractPcmData(appendedBytes);

    final int sampleRate = getSampleRate(originalBytes);
    final int channels = getChannels(originalBytes);
    final int bitsPerSample = getBitsPerSample(originalBytes);

    final BytesBuilder pcmBuilder = BytesBuilder();
    pcmBuilder.add(originalPcm);

    if (insertBeep && originalPcm.isNotEmpty) {
      final Uint8List beepPcm = generateBeepPcm(
        durationMs: 70,
        frequencyHz: 750,
        sampleRate: sampleRate,
      );
      pcmBuilder.add(beepPcm);
    }

    pcmBuilder.add(appendedPcm);

    final Uint8List fullWav = createWavFromPcm(
      pcmData: pcmBuilder.toBytes(),
      sampleRate: sampleRate,
      numChannels: channels,
      bitsPerSample: bitsPerSample,
    );

    await outputFile.writeAsBytes(fullWav, flush: true);
    return outputFile;
  }

  /// Extracts raw PCM data without the 44-byte RIFF/WAVE header.
  static Uint8List extractPcmData(Uint8List wavBytes) {
    if (wavBytes.length <= 44) return Uint8List(0);
    final ByteData byteData = ByteData.sublistView(wavBytes);

    int dataOffset = 12;
    int dataSize = wavBytes.length - 44;

    while (dataOffset + 8 <= wavBytes.length) {
      final String chunkId = String.fromCharCodes(wavBytes.sublist(dataOffset, dataOffset + 4));
      final int chunkSize = byteData.getUint32(dataOffset + 4, Endian.little);
      if (chunkId == 'data') {
        dataOffset += 8;
        dataSize = chunkSize;
        break;
      }
      dataOffset += 8 + chunkSize;
    }

    final int end = (dataOffset + dataSize <= wavBytes.length) ? (dataOffset + dataSize) : wavBytes.length;
    return wavBytes.sublist(dataOffset, end);
  }

  /// Reads Sample Rate from WAV header (defaults to 16000 Hz).
  static int getSampleRate(Uint8List wavBytes) {
    if (wavBytes.length < 28) return 16000;
    final ByteData byteData = ByteData.sublistView(wavBytes);
    return byteData.getUint32(24, Endian.little);
  }

  /// Reads Channels from WAV header (defaults to 1 - Mono).
  static int getChannels(Uint8List wavBytes) {
    if (wavBytes.length < 24) return 1;
    final ByteData byteData = ByteData.sublistView(wavBytes);
    return byteData.getUint16(22, Endian.little);
  }

  /// Reads Bits per sample from WAV header (defaults to 16-bit).
  static int getBitsPerSample(Uint8List wavBytes) {
    if (wavBytes.length < 36) return 16;
    final ByteData byteData = ByteData.sublistView(wavBytes);
    return byteData.getUint16(34, Endian.little);
  }

  /// Wraps raw PCM data in a standard 44-byte RIFF/WAVE header.
  static Uint8List createWavFromPcm({
    required Uint8List pcmData,
    int sampleRate = 16000,
    int numChannels = 1,
    int bitsPerSample = 16,
  }) {
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int dataSize = pcmData.length;
    final int totalSize = 36 + dataSize;

    final Uint8List wavHeader = Uint8List(44);
    final ByteData header = ByteData.sublistView(wavHeader);

    // RIFF chunk descriptor
    wavHeader.setRange(0, 4, 'RIFF'.codeUnits);
    header.setUint32(4, totalSize, Endian.little);
    wavHeader.setRange(8, 12, 'WAVE'.codeUnits);

    // "fmt " sub-chunk
    wavHeader.setRange(12, 16, 'fmt '.codeUnits);
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // "data" sub-chunk
    wavHeader.setRange(36, 40, 'data'.codeUnits);
    header.setUint32(40, dataSize, Endian.little);

    final BytesBuilder builder = BytesBuilder();
    builder.add(wavHeader);
    builder.add(pcmData);
    return builder.toBytes();
  }

  /// Computes a list of normalized amplitude values (0.0 to 1.0) from a WAV file for visual waveform rendering.
  static Future<List<double>> extractWaveformPoints(File wavFile, {int targetPoints = 100}) async {
    if (!await wavFile.exists()) return [];
    try {
      final Uint8List bytes = await wavFile.readAsBytes();
      final Uint8List pcm = extractPcmData(bytes);
      if (pcm.length < 2) return [];

      final ByteData byteData = ByteData.sublistView(pcm);
      final int totalSamples = pcm.length ~/ 2;
      if (totalSamples == 0) return [];

      final int step = max(1, totalSamples ~/ targetPoints);
      final List<double> points = [];

      for (int i = 0; i < totalSamples; i += step) {
        int maxVal = 0;
        final int end = min(i + step, totalSamples);
        for (int j = i; j < end; j++) {
          final int sample = byteData.getInt16(j * 2, Endian.little).abs();
          if (sample > maxVal) maxVal = sample;
        }
        final double normalized = (maxVal / 32767.0).clamp(0.02, 1.0);
        points.add(normalized);
      }
      return points;
    } catch (e) {
      debugPrint('[AudioEditorService] Error extracting waveform points: $e');
      return [];
    }
  }
}
