import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class LocalStorageManager {
  LocalStorageManager._();

  static Directory? _cachedDirectory;

  /// Returns the persistent directory where downloaded recordings and WAV files are stored.
  static Future<Directory> getRecordingsDirectory() async {
    if (_cachedDirectory != null && _cachedDirectory!.existsSync()) {
      return _cachedDirectory!;
    }

    Directory baseDir;
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final docsDir = await getApplicationDocumentsDirectory();
        baseDir = Directory(p.join(docsDir.path, 'XiaoAudioCompanion', 'Recordings'));
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }
    } catch (_) {
      baseDir = Directory(p.join(Directory.current.path, 'recordings'));
    }

    if (!baseDir.existsSync()) {
      baseDir.createSync(recursive: true);
    }

    _cachedDirectory = baseDir;
    return baseDir;
  }

  /// Saves a WAV file to local disk and returns the absolute file path.
  static Future<File> saveWavFile({
    required String filename,
    required Uint8List wavBytes,
  }) async {
    final dir = await getRecordingsDirectory();
    final String cleanName = filename.endsWith('.wav') ? filename : '$filename.wav';
    final filePath = p.join(dir.path, cleanName);
    final file = File(filePath);
    await file.writeAsBytes(wavBytes, flush: true);
    return file;
  }

  /// Checks if a file exists locally.
  static Future<bool> hasLocalFile(String filename) async {
    final dir = await getRecordingsDirectory();
    final String cleanName = filename.endsWith('.wav') ? filename : '$filename.wav';
    final file = File(p.join(dir.path, cleanName));
    return file.existsSync();
  }

  /// Gets the local File if it exists.
  static Future<File?> getLocalFile(String filename) async {
    final dir = await getRecordingsDirectory();
    final String cleanName = filename.endsWith('.wav') ? filename : '$filename.wav';
    final file = File(p.join(dir.path, cleanName));
    return file.existsSync() ? file : null;
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
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [dir.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [dir.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [dir.path]);
    }
  }
}
