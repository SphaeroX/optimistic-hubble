import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../audio/adpcm_decoder.dart';

class LocalStorageManager {
  LocalStorageManager._();

  static Directory? _cachedDirectory;

  /// Returns the persistent directory where downloaded recordings and WAV files are stored.
  /// On Android: /storage/emulated/0/Android/data/com.sphaerox.companion_app/files/Recordings
  /// On Windows: %USERPROFILE%\Documents\XiaoAudioCompanion\Recordings
  static Future<Directory> getRecordingsDirectory() async {
    if (_cachedDirectory != null && _cachedDirectory!.existsSync()) {
      return _cachedDirectory!;
    }

    Directory baseDir;
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final docsDir = await getApplicationDocumentsDirectory();
        baseDir = Directory(p.join(docsDir.path, 'XiaoAudioCompanion', 'Recordings'));
      } else if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          baseDir = Directory(p.join(extDir.path, 'Recordings'));
        } else {
          final docsDir = await getApplicationDocumentsDirectory();
          baseDir = Directory(p.join(docsDir.path, 'Recordings'));
        }
      } else {
        final docsDir = await getApplicationDocumentsDirectory();
        baseDir = Directory(p.join(docsDir.path, 'Recordings'));
      }
    } catch (_) {
      baseDir = Directory(p.join(Directory.current.path, 'recordings'));
    }

    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }

    // Migrate any legacy WAV files from old app root documents directory
    try {
      final oldDocsDir = await getApplicationDocumentsDirectory();
      if (oldDocsDir.existsSync() && oldDocsDir.path != baseDir.path) {
        for (final entity in oldDocsDir.listSync()) {
          if (entity is File && entity.path.endsWith('.wav')) {
            final destPath = p.join(baseDir.path, p.basename(entity.path));
            if (!File(destPath).existsSync()) {
              entity.copySync(destPath);
              entity.deleteSync();
            }
          }
        }
      }
    } catch (_) {}

    _cachedDirectory = baseDir;
    return baseDir;
  }

  /// Returns the human-readable absolute path where recordings are stored on this device.
  static Future<String> getRecordingsDirectoryPath() async {
    final dir = await getRecordingsDirectory();
    return dir.path;
  }

  /// Saves a WAV file to local disk, ensuring it is in standard 16-bit Linear PCM format.
  static Future<File> saveWavFile({
    required String filename,
    required Uint8List wavBytes,
  }) async {
    final dir = await getRecordingsDirectory();
    final String cleanName = filename.endsWith('.wav') ? filename : '$filename.wav';
    final filePath = p.join(dir.path, cleanName);
    
    // Automatically decode any IMA-ADPCM data into standard Linear 16-bit PCM WAV
    final Uint8List pcmBytes = AdpcmDecoder.ensureLinearPcmWav(wavBytes);
    
    final file = File(filePath);
    await file.writeAsBytes(pcmBytes, flush: true);
    return file;
  }

  /// Checks if a file exists locally.
  static Future<bool> hasLocalFile(String filename) async {
    final file = await getLocalFile(filename);
    return file != null && file.existsSync();
  }

  /// Gets the local File if it exists.
  static Future<File?> getLocalFile(String filename) async {
    final dir = await getRecordingsDirectory();
    final String cleanName = filename.endsWith('.wav') ? filename : '$filename.wav';
    final file = File(p.join(dir.path, cleanName));
    if (file.existsSync()) return file;

    // Fallback: Check padded / unpadded variants (e.g. clip_1.wav vs clip_001.wav)
    final match = RegExp(r'clip_(\d+)\.wav').firstMatch(cleanName);
    if (match != null) {
      final numVal = int.tryParse(match.group(1)!);
      if (numVal != null) {
        final paddedName = 'clip_${numVal.toString().padLeft(3, '0')}.wav';
        final paddedFile = File(p.join(dir.path, paddedName));
        if (paddedFile.existsSync()) return paddedFile;

        final unpaddedName = 'clip_$numVal.wav';
        final unpaddedFile = File(p.join(dir.path, unpaddedName));
        if (unpaddedFile.existsSync()) return unpaddedFile;
      }
    }
    return null;
  }

  /// Generates a unique filename for an imported hardware clip to avoid overwriting or collision.
  static String generateHardwareClipFilename(int clipId, [DateTime? timestamp]) {
    final time = timestamp ?? DateTime.now();
    return 'hw_clip_${clipId}_${time.millisecondsSinceEpoch}.wav';
  }

  /// Returns a unique target File instance for an imported hardware clip.
  static Future<File> getTargetHardwareFile(int clipId, [DateTime? timestamp]) async {
    final filename = generateHardwareClipFilename(clipId, timestamp);
    return getTargetFile(filename);
  }

  /// Returns the target File instance in the recordings directory, regardless of whether it already exists on disk.
  static Future<File> getTargetFile(String filename) async {
    final dir = await getRecordingsDirectory();
    final String cleanName = filename.endsWith('.wav') ? filename : '$filename.wav';
    return File(p.join(dir.path, cleanName));
  }

  /// Deletes a local WAV file from disk if it exists.
  static Future<bool> deleteLocalFile(String filename) async {
    final file = await getLocalFile(filename);
    if (file != null && file.existsSync()) {
      try {
        await file.delete();
        return true;
      } catch (e) {
        debugPrint('[LocalStorageManager] Error deleting $filename: $e');
        return false;
      }
    }
    return false;
  }

  /// Deletes a local file by its absolute path.
  static Future<bool> deleteLocalFileByPath(String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      debugPrint('[LocalStorageManager] Error deleting file at $filePath: $e');
    }
    return false;
  }

  /// Lists all local saved WAV recording files.
  static Future<List<File>> listSavedWavFiles() async {
    final dir = await getRecordingsDirectory();
    if (!dir.existsSync()) return [];
    final entries = dir.listSync();
    return entries.whereType<File>().where((f) => f.path.endsWith('.wav')).toList()
      ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
  }

  /// Opens the recordings folder in Windows Explorer or system file manager.
  static Future<void> openInFileManager() async {
    final dir = await getRecordingsDirectory();
    try {
      if (Platform.isWindows) {
        final winPath = p.normalize(dir.path).replaceAll('/', '\\');
        await Process.run('explorer.exe', [winPath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [dir.path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [dir.path]);
      } else {
        await OpenFile.open(dir.path);
      }
    } catch (e) {
      debugPrint('[LocalStorageManager] Fallback opening directory with OpenFile: $e');
      await OpenFile.open(dir.path);
    }
  }

  /// Opens a specific file with system default application.
  static Future<void> openFile(String filePath) async {
    await OpenFile.open(filePath);
  }

  /// Shares a local audio WAV file with external applications (e.g. WhatsApp, Gmail, Telegram).
  static Future<ShareResult> shareFile({
    required String filePath,
    String? text,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('Audio file not found at: $filePath');
    }

    // Guarantee that audio file is valid Linear 16-bit PCM WAV before sharing
    final validFile = await AdpcmDecoder.ensureFileIsLinearPcmWav(file);
    final filename = p.basename(validFile.path);

    final xfile = XFile(
      validFile.path,
      mimeType: 'audio/wav',
      name: filename,
    );

    return await SharePlus.instance.share(
      ShareParams(
        files: [xfile],
        text: text,
        subject: subject ?? filename,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}

