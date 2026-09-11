import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../audio/adpcm_decoder.dart';

/// Result container for audio sharing actions.
class AudioShareResult {
  final bool success;
  final String? errorMessage;

  const AudioShareResult({required this.success, this.errorMessage});
}

/// Service for sharing recordings directly as standard audio files (WAV)
/// compatible with WhatsApp, Telegram, email, and native system players.
class AudioShareService {
  AudioShareService._();

  /// Shares a recording's audio file via the platform's native share sheet.
  ///
  /// Ensures the file is in linear PCM WAV format (decodes ADPCM if required),
  /// assigns a clean, user-friendly filename based on [title], and specifies
  /// the standard `audio/wav` MIME type so WhatsApp and other messengers handle
  /// it as a playable audio message.
  static Future<AudioShareResult> shareAudio({
    required String? filePath,
    required String title,
  }) async {
    try {
      if (filePath == null || filePath.isEmpty) {
        return const AudioShareResult(
          success: false,
          errorMessage: 'Keine Audiodatei zugeordnet. Bitte zuerst vom Controller synchronisieren.',
        );
      }

      final sourceFile = File(filePath);
      if (!await sourceFile.exists()) {
        return const AudioShareResult(
          success: false,
          errorMessage: 'Audiodatei existiert lokal nicht. Bitte zuerst herunterladen.',
        );
      }

      final sourceBytes = await sourceFile.readAsBytes();
      if (sourceBytes.isEmpty) {
        return const AudioShareResult(
          success: false,
          errorMessage: 'Die Audiodatei ist leer.',
        );
      }

      // Ensure standard Linear PCM WAV
      Uint8List wavBytes;
      if (AdpcmDecoder.isLinearPcmWav(sourceBytes)) {
        wavBytes = sourceBytes;
      } else {
        // If raw ADPCM or non-standard, decode to standard 16 kHz 16-bit PCM WAV
        debugPrint('[AudioShareService] Source is not standard Linear PCM WAV, decoding...');
        wavBytes = AdpcmDecoder.decodeAdpcmToWav(sourceBytes);
      }

      // Generate clean filename
      final safeTitle = title.replaceAll(RegExp(r'[^\w\s\-_äöüÄÖÜß]'), '').trim();
      final baseName = safeTitle.isEmpty ? 'Dictula_Aufnahme' : safeTitle;
      final fileName = '$baseName.wav';

      final tempDir = await getTemporaryDirectory();
      final shareFile = File('${tempDir.path}/$fileName');
      await shareFile.writeAsBytes(wavBytes, flush: true);

      final shareResult = await Share.shareXFiles(
        [
          XFile(
            shareFile.path,
            mimeType: 'audio/wav',
            name: fileName,
          ),
        ],
        text: 'Dictula Sprachaufnahme: $title',
        subject: title,
      );

      debugPrint('[AudioShareService] Share completed with status: ${shareResult.status}');
      return const AudioShareResult(success: true);
    } catch (e, stack) {
      debugPrint('[AudioShareService] Error sharing audio: $e\n$stack');
      return AudioShareResult(
        success: false,
        errorMessage: 'Fehler beim Teilen der Audiodatei: $e',
      );
    }
  }

  /// Shares multiple recording audio files simultaneously via the platform's native share sheet.
  ///
  /// Decodes ADPCM files to standard Linear PCM WAV if required, ensures valid temporary files,
  /// and forwards all audio files as a single batch to `Share.shareXFiles`.
  static Future<AudioShareResult> shareMultipleAudios({
    required List<({String? filePath, String title})> items,
  }) async {
    try {
      if (items.isEmpty) {
        return const AudioShareResult(
          success: false,
          errorMessage: 'Keine Aufnahmen zum Teilen ausgewählt.',
        );
      }

      final validItems = <({String filePath, String title})>[];
      for (final item in items) {
        final p = item.filePath;
        if (p != null && p.isNotEmpty && File(p).existsSync()) {
          validItems.add((filePath: p, title: item.title));
        }
      }

      if (validItems.isEmpty) {
        return const AudioShareResult(
          success: false,
          errorMessage: 'Keine gültigen lokalen Audiodateien zum Teilen gefunden.',
        );
      }

      final tempDir = await getTemporaryDirectory();
      final List<XFile> filesToShare = [];

      for (int i = 0; i < validItems.length; i++) {
        final item = validItems[i];
        final sourceFile = File(item.filePath);
        final sourceBytes = await sourceFile.readAsBytes();
        if (sourceBytes.isEmpty) continue;

        Uint8List wavBytes;
        if (AdpcmDecoder.isLinearPcmWav(sourceBytes)) {
          wavBytes = sourceBytes;
        } else {
          wavBytes = AdpcmDecoder.decodeAdpcmToWav(sourceBytes);
        }

        final safeTitle = item.title.replaceAll(RegExp(r'[^\w\s\-_äöüÄÖÜß]'), '').trim();
        final baseName = safeTitle.isEmpty ? 'Dictula_Aufnahme_${i + 1}' : safeTitle;
        final fileName = '${baseName}_${i + 1}.wav';

        final shareFile = File('${tempDir.path}/$fileName');
        await shareFile.writeAsBytes(wavBytes, flush: true);

        filesToShare.add(
          XFile(
            shareFile.path,
            mimeType: 'audio/wav',
            name: fileName,
          ),
        );
      }

      if (filesToShare.isEmpty) {
        return const AudioShareResult(
          success: false,
          errorMessage: 'Keine gültigen lokalen Audiodateien zum Teilen gefunden.',
        );
      }

      final shareResult = await Share.shareXFiles(
        filesToShare,
        text: '${filesToShare.length} Dictula Sprachaufnahmen geteilt',
        subject: '${filesToShare.length} Sprachaufnahmen',
      );

      debugPrint('[AudioShareService] Batch share of ${filesToShare.length} files completed with status: ${shareResult.status}');
      return const AudioShareResult(success: true);
    } catch (e, stack) {
      debugPrint('[AudioShareService] Error sharing multiple audio files: $e\n$stack');
      return AudioShareResult(
        success: false,
        errorMessage: 'Fehler beim Teilen mehrerer Audiodateien: $e',
      );
    }
  }
}

