import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../constants/app_constants.dart';

class SyncProgressEvent {
  final String status;
  final double progress;
  final int bytesReceived;
  final int totalBytes;
  final String message;
  final String? filePath;

  const SyncProgressEvent({
    required this.status,
    required this.progress,
    required this.bytesReceived,
    required this.totalBytes,
    required this.message,
    this.filePath,
  });

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
  bool get isConnecting => status == 'connecting';
  bool get isTransferring => status == 'transferring';
}

class NativeAudioSyncBridge {
  static const MethodChannel _methodChannel = MethodChannel('com.sphaerox.companion_app/audio_sync');
  static const EventChannel _eventChannel = EventChannel('com.sphaerox.companion_app/sync_events');

  static final NativeAudioSyncBridge _instance = NativeAudioSyncBridge._internal();
  factory NativeAudioSyncBridge() => _instance;
  NativeAudioSyncBridge._internal();

  Stream<SyncProgressEvent>? _eventStream;

  bool get isPlatformAndroid => !kIsWeb && Platform.isAndroid;
  bool get isPlatformIOS => !kIsWeb && Platform.isIOS;

  Stream<SyncProgressEvent> get syncEvents {
    if (_eventStream == null && isPlatformAndroid) {
      _eventStream = _eventChannel.receiveBroadcastStream().map((dynamic event) {
        if (event is Map) {
          return SyncProgressEvent(
            status: event['status']?.toString() ?? 'unknown',
            progress: (event['progress'] as num?)?.toDouble() ?? 0.0,
            bytesReceived: (event['bytesReceived'] as num?)?.toInt() ?? 0,
            totalBytes: (event['totalBytes'] as num?)?.toInt() ?? 0,
            message: event['message']?.toString() ?? '',
            filePath: event['filePath']?.toString(),
          );
        }
        return const SyncProgressEvent(
          status: 'unknown',
          progress: 0.0,
          bytesReceived: 0,
          totalBytes: 0,
          message: '',
        );
      });
    }
    return _eventStream ?? const Stream.empty();
  }

  Future<bool> isL2capSupported() async {
    if (!isPlatformAndroid) return false;
    try {
      final bool? supported = await _methodChannel.invokeMethod<bool>('isL2capSupported');
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> startBleL2capSync({
    required String deviceAddress,
    required int fileId,
    int psm = AppConstants.bleL2capPsm,
    String? destinationPath,
  }) async {
    if (!isPlatformAndroid) return null;
    try {
      final String? path = await _methodChannel.invokeMethod<String>('startBleL2capSync', {
        'deviceAddress': deviceAddress,
        'fileId': fileId,
        'psm': psm,
        'destinationPath': ?destinationPath,
      });
      return path;
    } catch (e) {
      debugPrint('[NativeAudioSyncBridge] BLE L2CAP error: $e');
      rethrow;
    }
  }

  Future<String?> startWifiSoftApSync({
    required int fileId,
    String ssidPattern = AppConstants.defaultApSsidPattern,
    String passphrase = AppConstants.defaultApPassword,
    int startOffset = 0,
    String? destinationPath,
    bool keepConnected = false,
  }) async {
    if (!isPlatformAndroid) return null;
    try {
      final String? path = await _methodChannel.invokeMethod<String>('startWifiSoftApSync', {
        'fileId': fileId,
        'ssidPattern': ssidPattern,
        'passphrase': passphrase,
        'startOffset': startOffset,
        'destinationPath': ?destinationPath,
        'keepConnected': keepConnected,
      });
      return path;
    } catch (e) {
      debugPrint('[NativeAudioSyncBridge] Wi-Fi SoftAP sync error: $e');
      rethrow;
    }
  }

  Future<bool> connectWifiSoftAp({
    String ssidPattern = AppConstants.defaultApSsidPattern,
    String passphrase = AppConstants.defaultApPassword,
  }) async {
    if (!isPlatformAndroid) return false;
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('connectWifiSoftAp', {
        'ssidPattern': ssidPattern,
        'passphrase': passphrase,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('[NativeAudioSyncBridge] connectWifiSoftAp error: $e');
      return false;
    }
  }

  Future<void> disconnectWifiSoftAp() async {
    if (!isPlatformAndroid) return;
    try {
      await _methodChannel.invokeMethod('disconnectWifiSoftAp');
    } catch (e) {
      debugPrint('[NativeAudioSyncBridge] disconnectWifiSoftAp error: $e');
    }
  }

  Future<bool> isWifiConnected() async {
    if (!isPlatformAndroid) return false;
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('isWifiConnected');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancelSync() async {
    if (!isPlatformAndroid) return;
    try {
      await _methodChannel.invokeMethod('cancelSync');
    } catch (_) {}
  }
}
