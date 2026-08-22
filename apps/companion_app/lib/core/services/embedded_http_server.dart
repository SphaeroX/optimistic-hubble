import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../utils/storage_manager.dart';
import 'native_audio_sync_bridge.dart';

typedef OnClipReceivedCallback = void Function({
  required int clipId,
  required String filePath,
  required int sizeBytes,
  required double durationSeconds,
});

typedef OnSyncCompletedCallback = void Function();

class EmbeddedAudioUploadServer {
  HttpServer? _server;
  bool _isRunning = false;
  int _serverPort = 8080;

  final StreamController<SyncProgressEvent> _progressController =
      StreamController<SyncProgressEvent>.broadcast();

  Stream<SyncProgressEvent> get progressEvents => _progressController.stream;

  OnClipReceivedCallback? onClipReceived;
  OnSyncCompletedCallback? onSyncCompleted;

  bool get isRunning => _isRunning;
  int get port => _serverPort;

  Future<int> start({int port = 8080}) async {
    if (_isRunning) {
      return _serverPort;
    }

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _serverPort = _server!.port;
      _isRunning = true;
      debugPrint('[EmbeddedAudioServer] Listening on http://0.0.0.0:$_serverPort');

      _server!.listen(
        _handleRequest,
        onError: (e) {
          debugPrint('[EmbeddedAudioServer] Server error: $e');
        },
        onDone: () {
          _isRunning = false;
          debugPrint('[EmbeddedAudioServer] Server stopped');
        },
      );

      return _serverPort;
    } catch (e) {
      debugPrint('[EmbeddedAudioServer] Failed to bind to port $port: $e');
      // Fallback to random available port
      _server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      _serverPort = _server!.port;
      _isRunning = true;
      debugPrint('[EmbeddedAudioServer] Fallback: Listening on http://0.0.0.0:$_serverPort');

      _server!.listen(_handleRequest);
      return _serverPort;
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    try {
      await _server?.close(force: true);
    } catch (e) {
      debugPrint('[EmbeddedAudioServer] Error stopping server: $e');
    } finally {
      _server = null;
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    final method = request.method.toUpperCase();

    // Enable CORS for all responses
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Origin, Content-Type, Content-Length, Range');

    if (method == 'OPTIONS') {
      response.statusCode = HttpStatus.noContent;
      await response.close();
      return;
    }

    if (path == '/api/upload' && method == 'POST') {
      await _handleUploadRequest(request);
      return;
    }

    if (path == '/api/complete' && (method == 'POST' || method == 'GET')) {
      _handleCompleteRequest(request);
      return;
    }

    if ((path == '/api/handshake' || path == '/api/status') && method == 'GET') {
      _handleHandshakeRequest(request);
      return;
    }

    // Default 404
    response.statusCode = HttpStatus.notFound;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'error': 'Not Found', 'path': path}));
    await response.close();
  }

  Future<void> _handleUploadRequest(HttpRequest request) async {
    final queryParams = request.uri.queryParameters;
    final int clipId = int.tryParse(queryParams['id'] ?? '1') ?? 1;
    final int headerLength = request.contentLength;
    final int expectedLength = int.tryParse(queryParams['size'] ?? '$headerLength') ?? headerLength;
    final double durationSec = double.tryParse(queryParams['duration'] ?? '0.0') ?? 0.0;

    debugPrint('[EmbeddedAudioServer] Receiving upload for Clip #$clipId (Expected: $expectedLength bytes)');

    final targetFile = await LocalStorageManager.getTargetFile('clip_$clipId.wav');
    final tempFile = File('${targetFile.path}.part');

    IOSink? sink;
    int bytesReceived = 0;
    final startTime = DateTime.now();

    _progressController.add(SyncProgressEvent(
      status: 'transferring',
      progress: 0.05,
      bytesReceived: 0,
      totalBytes: expectedLength > 0 ? expectedLength : 0,
      message: 'Receiving Clip #$clipId...',
      filePath: targetFile.path,
    ));

    try {
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      sink = tempFile.openWrite();

      await for (final chunk in request) {
        sink.add(chunk);
        bytesReceived += chunk.length;

        final elapsedSec = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
        final speedMb = elapsedSec > 0 ? (bytesReceived / (1024.0 * 1024.0)) / elapsedSec : 0.0;
        final progress = expectedLength > 0 ? (bytesReceived / expectedLength).clamp(0.0, 1.0) : 0.5;

        _progressController.add(SyncProgressEvent(
          status: 'transferring',
          progress: progress,
          bytesReceived: bytesReceived,
          totalBytes: expectedLength > 0 ? expectedLength : bytesReceived,
          message: '${speedMb.toStringAsFixed(2)} MB/s (Wi-Fi Turbo Upload)',
          filePath: targetFile.path,
        ));
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // Rename temp file to final destination
      if (targetFile.existsSync()) {
        targetFile.deleteSync();
      }
      await tempFile.rename(targetFile.path);

      debugPrint('[EmbeddedAudioServer] Clip #$clipId uploaded successfully (${targetFile.lengthSync()} bytes)');

      final calculatedDuration = durationSec > 0
          ? durationSec
          : (targetFile.lengthSync() > 44 ? (targetFile.lengthSync() - 44) / 32000.0 : 0.0);

      onClipReceived?.call(
        clipId: clipId,
        filePath: targetFile.path,
        sizeBytes: targetFile.lengthSync(),
        durationSeconds: calculatedDuration,
      );

      _progressController.add(SyncProgressEvent(
        status: 'completed',
        progress: 1.0,
        bytesReceived: targetFile.lengthSync(),
        totalBytes: targetFile.lengthSync(),
        message: 'Clip #$clipId saved and verified',
        filePath: targetFile.path,
      ));

      final response = request.response;
      response.statusCode = HttpStatus.ok;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({
        'status': 'ok',
        'clipId': clipId,
        'bytes': targetFile.lengthSync(),
        'saved': true,
      }));
      await response.close();
    } catch (e) {
      debugPrint('[EmbeddedAudioServer] Upload failed for Clip #$clipId: $e');
      try {
        await sink?.close();
      } catch (_) {}

      _progressController.add(SyncProgressEvent(
        status: 'failed',
        progress: 0.0,
        bytesReceived: bytesReceived,
        totalBytes: expectedLength,
        message: 'Upload error: $e',
      ));

      final response = request.response;
      response.statusCode = HttpStatus.internalServerError;
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({'error': e.toString()}));
      await response.close();
    }
  }

  void _handleCompleteRequest(HttpRequest request) {
    debugPrint('[EmbeddedAudioServer] MCU reported upload batch complete!');
    onSyncCompleted?.call();

    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({'status': 'completed', 'server': 'XiaoCompanionServer'}));
    response.close();
  }

  void _handleHandshakeRequest(HttpRequest request) {
    final response = request.response;
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode({
      'status': 'READY',
      'server': 'XiaoCompanionServer',
      'version': '2.0',
      'port': _serverPort,
    }));
    response.close();
  }

  void dispose() {
    stop();
    _progressController.close();
  }
}
