import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Service for exporting complete Dictula projects and recordings as self-contained ZIP archives.
class ZipExportService {
  ZipExportService._();

  /// Bundles a recording, its metadata, transcriptions, images, and attachments into a ZIP archive and triggers the native share sheet.
  static Future<bool> exportAndShareZip({
    required String title,
    required DateTime recordedAt,
    required Duration duration,
    required String audioPath,
    String? transcription,
    String? groupName,
    List<String> photoPaths = const [],
    List<String> attachmentPaths = const [],
  }) async {
    try {
      final Archive archive = Archive();

      // 1. Audio WAV file
      final File audioFile = File(audioPath);
      if (await audioFile.exists()) {
        final Uint8List audioBytes = await audioFile.readAsBytes();
        final String audioExt = p.extension(audioPath).isNotEmpty ? p.extension(audioPath) : '.wav';
        archive.addFile(ArchiveFile('audio$audioExt', audioBytes.length, audioBytes));
      }

      // 2. Transcription text / markdown
      if (transcription != null && transcription.trim().isNotEmpty) {
        final Uint8List transBytes = utf8.encode(transcription);
        archive.addFile(ArchiveFile('transcription.md', transBytes.length, transBytes));
      }

      // 3. Metadata JSON
      final Map<String, dynamic> metadata = {
        'title': title,
        'recordedAt': recordedAt.toIso8601String(),
        'durationSeconds': duration.inSeconds,
        'durationFormatted': duration.toString().split('.').first,
        'group': groupName,
        'hasTranscription': transcription != null && transcription.isNotEmpty,
        'photoCount': photoPaths.length,
        'attachmentCount': attachmentPaths.length,
        'exportedAt': DateTime.now().toIso8601String(),
        'generator': 'Dictula Voice Platform',
      };
      final Uint8List metaBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(metadata));
      archive.addFile(ArchiveFile('metadata.json', metaBytes.length, metaBytes));

      // 4. Photos
      for (int i = 0; i < photoPaths.length; i++) {
        final File photoFile = File(photoPaths[i]);
        if (await photoFile.exists()) {
          final Uint8List photoBytes = await photoFile.readAsBytes();
          final String baseName = p.basename(photoPaths[i]);
          archive.addFile(ArchiveFile('photos/$baseName', photoBytes.length, photoBytes));
        }
      }

      // 5. Attachments / Documents
      for (int i = 0; i < attachmentPaths.length; i++) {
        final File attachFile = File(attachmentPaths[i]);
        if (await attachFile.exists()) {
          final Uint8List attachBytes = await attachFile.readAsBytes();
          final String baseName = p.basename(attachmentPaths[i]);
          archive.addFile(ArchiveFile('attachments/$baseName', attachBytes.length, attachBytes));
        }
      }

      // 6. Encode ZIP
      final ZipEncoder encoder = ZipEncoder();
      final List<int> zipData = encoder.encode(archive);
      if (zipData.isEmpty) {
        debugPrint('[ZipExportService] Failed to encode ZIP archive');
        return false;
      }

      // 7. Write ZIP to temporary directory
      final Directory tempDir = await getTemporaryDirectory();
      final String safeTitle = title.replaceAll(RegExp(r'[^\w\s\.-]'), '_').trim();
      final String zipFilename = 'Dictula_${safeTitle.isEmpty ? "Recording" : safeTitle}.zip';
      final File zipFile = File('${tempDir.path}/$zipFilename');
      await zipFile.writeAsBytes(zipData, flush: true);

      // 8. Share via system share sheet
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipFile.path, mimeType: 'application/zip', name: zipFilename)],
          text: 'Dictula Sprachnotiz: $title',
          subject: 'Dictula Export - $title',
        ),
      );

      return result.status == ShareResultStatus.success || result.status == ShareResultStatus.dismissed;
    } catch (e) {
      debugPrint('[ZipExportService] Error exporting ZIP: $e');
      return false;
    }
  }

  /// Bundles multiple recordings and their associated metadata/attachments into a single ZIP archive.
  static Future<bool> exportAndShareMultipleZip({
    required List<({
      String title,
      DateTime recordedAt,
      Duration duration,
      String audioPath,
      String? transcription,
      String? groupName,
      List<String> photoPaths,
      List<String> attachmentPaths,
    })> recordings,
  }) async {
    try {
      if (recordings.isEmpty) return false;

      final Archive archive = Archive();
      final List<Map<String, dynamic>> manifest = [];

      for (int i = 0; i < recordings.length; i++) {
        final rec = recordings[i];
        final safeTitle = rec.title.replaceAll(RegExp(r'[^\w\s\.-]'), '_').trim();
        final folderName = '${(i + 1).toString().padLeft(2, '0')}_${safeTitle.isEmpty ? "Aufnahme" : safeTitle}';

        // 1. Audio WAV file
        final File audioFile = File(rec.audioPath);
        if (await audioFile.exists()) {
          final Uint8List audioBytes = await audioFile.readAsBytes();
          final String audioExt = p.extension(rec.audioPath).isNotEmpty ? p.extension(rec.audioPath) : '.wav';
          archive.addFile(ArchiveFile('$folderName/audio$audioExt', audioBytes.length, audioBytes));
        }

        // 2. Transcription
        if (rec.transcription != null && rec.transcription!.trim().isNotEmpty) {
          final Uint8List transBytes = utf8.encode(rec.transcription!);
          archive.addFile(ArchiveFile('$folderName/transcription.md', transBytes.length, transBytes));
        }

        // 3. Manifest entry
        manifest.add({
          'index': i + 1,
          'title': rec.title,
          'recordedAt': rec.recordedAt.toIso8601String(),
          'durationSeconds': rec.duration.inSeconds,
          'group': rec.groupName,
          'hasTranscription': rec.transcription != null && rec.transcription!.isNotEmpty,
          'photos': rec.photoPaths.length,
          'attachments': rec.attachmentPaths.length,
        });
      }

      // Add overall manifest.json
      final Uint8List manifestBytes = utf8.encode(const JsonEncoder.withIndent('  ').convert({
        'totalRecordings': recordings.length,
        'exportedAt': DateTime.now().toIso8601String(),
        'generator': 'Dictula Voice Platform',
        'recordings': manifest,
      }));
      archive.addFile(ArchiveFile('manifest.json', manifestBytes.length, manifestBytes));

      // Encode ZIP
      final ZipEncoder encoder = ZipEncoder();
      final List<int> zipData = encoder.encode(archive);
      if (zipData.isEmpty) return false;

      final Directory tempDir = await getTemporaryDirectory();
      final String zipFilename = 'Dictula_Export_${recordings.length}_Aufnahmen.zip';
      final File zipFile = File('${tempDir.path}/$zipFilename');
      await zipFile.writeAsBytes(zipData, flush: true);

      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipFile.path, mimeType: 'application/zip', name: zipFilename)],
          text: '${recordings.length} Dictula Sprachaufnahmen im ZIP-Archiv',
          subject: 'Dictula Multi-Export (${recordings.length} Aufnahmen)',
        ),
      );

      return result.status == ShareResultStatus.success || result.status == ShareResultStatus.dismissed;
    } catch (e) {
      debugPrint('[ZipExportService] Error exporting multi-ZIP: $e');
      return false;
    }
  }
}

