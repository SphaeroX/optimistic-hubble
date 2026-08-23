import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:companion_app/core/audio/native_audio_player.dart';
import 'package:companion_app/core/constants/app_constants.dart';
import 'package:companion_app/core/services/native_audio_sync_bridge.dart';
import 'package:companion_app/features/connection/services/ble_service.dart';
import 'package:companion_app/features/recordings/models/recording_item.dart';
import 'package:companion_app/features/recordings/services/recording_sync_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('2-Stage Plaud Note Hybrid Sync Tests', () {
    test('Clips correctly categorize into BLE Standard or WiFi Fast Transfer tier', () {
      final smallClip = RecordingItem(
        id: 1,
        remoteFilename: 'clip_001.wav',
        sizeBytes: 192000, // 192 KB (< 512 KB threshold)
        duration: const Duration(seconds: 24),
        sampleRate: 16000,
        recordedAt: DateTime.now(),
      );

      final largeClip = RecordingItem(
        id: 2,
        remoteFilename: 'clip_002.wav',
        sizeBytes: 4800000, // 4.8 MB (>= 512 KB threshold)
        duration: const Duration(minutes: 10),
        sampleRate: 16000,
        recordedAt: DateTime.now(),
      );

      expect(smallClip.recommendedTier, SyncTier.bleStandard);
      expect(smallClip.isFastTransferRecommended, isFalse);
      expect(largeClip.recommendedTier, SyncTier.wifiFast);
      expect(largeClip.isFastTransferRecommended, isTrue);
    });

    test('RecordingItem fromApiJson creates valid model with dynamic tier', () {
      final json = {
        'id': 105,
        'filename': 'clip_105.wav',
        'size': 2400000,
        'duration': 300.0,
        'sampleRate': 16000,
      };

      final item = RecordingItem.fromApiJson(json);

      expect(item.id, 105);
      expect(item.remoteFilename, 'clip_105.wav');
      expect(item.sizeBytes, 2400000);
      expect(item.recommendedTier, SyncTier.wifiFast);
      expect(item.isFastTransferRecommended, isTrue);
      expect(item.syncState, SyncState.onDevice);
    });

    test('SyncProgressEvent accurately reports transfer lifecycle', () {
      const connectingEvent = SyncProgressEvent(
        status: 'connecting',
        progress: 0.0,
        bytesReceived: 0,
        totalBytes: 500000,
        message: 'Opening L2CAP...',
      );
      expect(connectingEvent.isConnecting, isTrue);
      expect(connectingEvent.isTransferring, isFalse);

      const transferEvent = SyncProgressEvent(
        status: 'transferring',
        progress: 0.5,
        bytesReceived: 250000,
        totalBytes: 500000,
        message: '124.5 KB/s (BLE L2CAP)',
      );
      expect(transferEvent.isTransferring, isTrue);
      expect(transferEvent.progress, 0.5);

      const completedEvent = SyncProgressEvent(
        status: 'completed',
        progress: 1.0,
        bytesReceived: 500000,
        totalBytes: 500000,
        message: 'Sync complete',
        filePath: '/data/user/0/com.sphaerox.companion_app/files/clip_105.wav',
      );
      expect(completedEvent.isCompleted, isTrue);
      expect(completedEvent.filePath, isNotNull);

      const failedEvent = SyncProgressEvent(
        status: 'failed',
        progress: 0.0,
        bytesReceived: 0,
        totalBytes: 0,
        message: 'Wi-Fi connection timed out',
      );
      expect(failedEvent.isFailed, isTrue);
      expect(failedEvent.isCompleted, isFalse);

      const cancelledEvent = SyncProgressEvent(
        status: 'cancelled',
        progress: 0.0,
        bytesReceived: 0,
        totalBytes: 0,
        message: 'Sync cancelled by user',
      );
      expect(cancelledEvent.status, 'cancelled');
      expect(cancelledEvent.isCompleted, isFalse);
      expect(cancelledEvent.isFailed, isTrue);
      expect(cancelledEvent.currentPhase, FastTransferPhase.failed);

      const hsEvent = SyncProgressEvent(
        status: 'handshaking',
        progress: 0.5,
        bytesReceived: 0,
        totalBytes: 0,
        message: 'Handshaking...',
      );
      expect(hsEvent.isHandshaking, isTrue);
      expect(hsEvent.currentPhase, FastTransferPhase.handshaking);
    });

    test('NativeAudioSyncBridge platform fallback returns safe defaults on non-Android platforms', () async {
      final bridge = NativeAudioSyncBridge();
      expect(bridge, isNotNull);

      // On non-Android (e.g. host unit test environment), these safely return null/false without crashing
      final l2capSupported = await bridge.isL2capSupported();
      expect(l2capSupported, isFalse);

      final isWifiConn = await bridge.isWifiConnected();
      expect(isWifiConn, isFalse);

      final isHotspot = await bridge.isHotspotActive();
      expect(isHotspot, isFalse);

      final hotspotInfo = await bridge.startLocalOnlyHotspot(port: 8080);
      expect(hotspotInfo, isNull);

      final stopRes = await bridge.stopLocalOnlyHotspot();
      expect(stopRes, isTrue);

      final connectRes = await bridge.connectWifiSoftAp();
      expect(connectRes, isFalse);

      final singleSyncWithOffset = await bridge.startWifiSoftApSync(
        fileId: 10,
        startOffset: 16384,
        destinationPath: '/tmp/test_clip_10.wav',
        keepConnected: true,
      );
      expect(singleSyncWithOffset, isNull);

      final singleSync = await bridge.startWifiSoftApSync(
        fileId: 10,
        destinationPath: '/tmp/test_clip_10.wav',
        keepConnected: true,
      );
      expect(singleSync, isNull);

      final l2capSync = await bridge.startBleL2capSync(
        deviceAddress: 'AA:BB:CC:DD:EE:FF',
        fileId: 10,
        destinationPath: '/tmp/test_clip_10.wav',
      );
      expect(l2capSync, isNull);

      await bridge.disconnectWifiSoftAp();
      await bridge.cancelSync();
    });

    test('HTTP Range calculation and partial resume progress logic', () {
      int calculateTotal(bool isPartial, int resumeOffset, int responseContentLength) {
        final actualOffset = isPartial ? resumeOffset : 0;
        return responseContentLength + actualOffset;
      }

      int calculateReceived(bool isPartial, int resumeOffset, int bytesFromStream) {
        final actualOffset = isPartial ? resumeOffset : 0;
        return actualOffset + bytesFromStream;
      }

      const int fullFileSize = 500000;
      const int resumeOffset = 200000;
      const int remainingBytes = 300000;

      // 1. When server returns 206 Partial Content (Range satisfied)
      final total206 = calculateTotal(true, resumeOffset, remainingBytes);
      expect(total206, fullFileSize);

      final received206 = calculateReceived(true, resumeOffset, 150000);
      final double progress206 = (received206 / total206).clamp(0.0, 1.0);
      expect(progress206, 0.7);

      // 2. When server returns 200 OK (server ignored Range header, sends full 500000 from 0)
      final total200 = calculateTotal(false, resumeOffset, fullFileSize);
      expect(total200, fullFileSize);

      final received200 = calculateReceived(false, resumeOffset, 150000);
      final double progress200 = (received200 / total200).clamp(0.0, 1.0);
      expect(progress200, 0.3);
    });

    test('RecordingItem copyWith correctly preserves and updates properties', () {
      final item = RecordingItem(
        id: 42,
        remoteFilename: 'clip_042.wav',
        sizeBytes: 1024000,
        duration: const Duration(seconds: 64),
        sampleRate: 16000,
        recordedAt: DateTime(2026, 8, 21),
      );

      expect(item.syncState, SyncState.onDevice);
      expect(item.downloadProgress, 0.0);

      final downloading = item.copyWith(
        syncState: SyncState.downloading,
        downloadProgress: 0.45,
        transferSpeed: '148.5 KB/s (BLE 5.0 High-Throughput)',
      );
      expect(downloading.syncState, SyncState.downloading);
      expect(downloading.downloadProgress, 0.45);
      expect(downloading.transferSpeed, '148.5 KB/s (BLE 5.0 High-Throughput)');
      expect(downloading.id, 42);

      final synced = downloading.copyWith(
        syncState: SyncState.synced,
        downloadProgress: 1.0,
        localWavPath: '/recordings/clip_42.wav',
        crcVerified: true,
      );
      expect(synced.syncState, SyncState.synced);
      expect(synced.downloadProgress, 1.0);
      expect(synced.localWavPath, '/recordings/clip_42.wav');
      expect(synced.crcVerified, isTrue);
    });

    test('BleCommand enum contains deleteClip with rawValue 9', () {
      expect(BleCommand.deleteClip.rawValue, 9);
      expect(BleCommand.values.contains(BleCommand.deleteClip), isTrue);
    });

    test('RecordingSyncManager resetFastTransferState resets phase to none and clears progress/errors', () async {
      final audioPlayer = FakeNativeAudioPlayer();
      final bleService = BleService();
      bleService.enableMockMode();
      final manager = RecordingSyncManager(
        audioPlayer: audioPlayer,
        bleService: bleService,
      );

      // Perform a simulated fast transfer to put it into completed state
      await manager.loadSimulatedClipsForTesting();
      final ok = await manager.startFastTransfer();
      expect(ok, isTrue);
      expect(manager.fastTransferPhase, FastTransferPhase.completed);

      // Reset state
      manager.resetFastTransferState();
      expect(manager.fastTransferPhase, FastTransferPhase.none);
      expect(manager.errorMessage, isNull);
      expect(manager.syncProgress, 0.0);
      expect(manager.currentSyncFile, isEmpty);
      expect(manager.currentSpeed, isNull);

      // Verify that after reset, a new transfer can be initiated
      final okAgain = await manager.startFastTransfer();
      expect(okAgain, isTrue);
      expect(manager.fastTransferPhase, FastTransferPhase.completed);

      manager.dispose();
      bleService.dispose();
      audioPlayer.dispose();
    });

    test('RecordingSyncManager fetchDeviceClips resets fast transfer state when idle', () async {
      final audioPlayer = FakeNativeAudioPlayer();
      final bleService = BleService();
      bleService.enableMockMode();
      final manager = RecordingSyncManager(
        audioPlayer: audioPlayer,
        bleService: bleService,
      );

      await manager.loadSimulatedClipsForTesting();
      await manager.startFastTransfer();
      expect(manager.fastTransferPhase, FastTransferPhase.completed);

      // Fetch clips should reset phase to none
      await manager.fetchDeviceClips();
      expect(manager.fastTransferPhase, FastTransferPhase.none);

      manager.dispose();
      bleService.dispose();
      audioPlayer.dispose();
    });

    test('BleService triggerSimulatedTap simulates hardware tap toggling recording and spiking IMU', () {
      final bleService = BleService();
      bleService.enableMockMode();

      expect(bleService.telemetry.state, DeviceState.idle);
      expect(bleService.telemetry.tapCount, 0);

      // Tap 1: Idle -> Starts Recording + IMU shock spike
      bleService.triggerSimulatedTap();
      expect(bleService.telemetry.state, DeviceState.recording);
      expect(bleService.telemetry.tapCount, 1);
      expect(bleService.telemetry.motionMagnitude, greaterThan(1.4));
      expect(bleService.tapHistory.length, 1);
      expect(bleService.tapHistory.first.tapIndex, 1);

      // Tap 2: Recording -> Stops Recording
      bleService.triggerSimulatedTap();
      expect(bleService.telemetry.state, DeviceState.done);
      expect(bleService.telemetry.tapCount, 2);
      expect(bleService.tapHistory.length, 2);
      expect(bleService.tapHistory.first.tapIndex, 2);

      bleService.dispose();
    });

    test('BleService enableMockMode provides live IMU accelerometer data', () {
      final bleService = BleService();
      bleService.enableMockMode();

      expect(bleService.isMockMode, isTrue);
      expect(bleService.telemetry.hasRealData, isTrue);
      expect(bleService.telemetry.accelX, isNotNull);
      expect(bleService.telemetry.accelY, isNotNull);
      expect(bleService.telemetry.accelZ, isNotNull);
      expect(bleService.telemetry.motionMagnitude, isNotNull);

      bleService.dispose();
    });
  });
}

class FakeNativeAudioPlayer extends ChangeNotifier implements NativeAudioPlayer {
  @override
  bool get isPlaying => false;

  @override
  String? get currentFilePath => null;

  @override
  Duration get currentPosition => Duration.zero;

  @override
  Duration get totalDuration => Duration.zero;

  @override
  double get progressFraction => 0.0;

  @override
  Future<bool> playFile(String filePath, {Duration? duration}) async => true;

  @override
  Future<void> pause() async {}

  @override
  void stop() {}
}


