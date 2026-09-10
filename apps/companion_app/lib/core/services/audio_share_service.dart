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
}
