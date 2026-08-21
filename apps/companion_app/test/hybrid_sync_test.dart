import 'package:flutter_test/flutter_test.dart';
import 'package:companion_app/core/constants/app_constants.dart';
import 'package:companion_app/core/services/native_audio_sync_bridge.dart';
import 'package:companion_app/features/recordings/models/recording_item.dart';

void main() {
  group('Tiered Adaptive Hybrid Sync Tests', () {
    test('Tier 1 vs Tier 2 size threshold correctly assigns recommended tier', () {
      final smallClip = RecordingItem(
        id: 1,
        remoteFilename: 'clip_001.wav',
        sizeBytes: 192000, // 192 KB (< 2.0 MB)
        duration: const Duration(seconds: 24),
        sampleRate: 16000,
        recordedAt: DateTime.now(),
      );

      final largeClip = RecordingItem(
        id: 2,
        remoteFilename: 'clip_002.wav',
        sizeBytes: 4800000, // 4.8 MB (>= 2.0 MB)
        duration: const Duration(minutes: 10),
        sampleRate: 16000,
        recordedAt: DateTime.now(),
      );

      expect(smallClip.recommendedTier, SyncTier.bleL2cap);
      expect(largeClip.recommendedTier, SyncTier.wifiTurbo);
    });

    test('RecordingItem fromApiJson creates valid model with adaptive tier', () {
      final json = {
        'id': 105,
        'filename': 'clip_105.wav',
        'size': 2400000, // 2.4 MB -> Wi-Fi Turbo
        'duration': 300.0,
        'sampleRate': 16000,
      };

      final item = RecordingItem.fromApiJson(json);

      expect(item.id, 105);
      expect(item.remoteFilename, 'clip_105.wav');
      expect(item.sizeBytes, 2400000);
      expect(item.recommendedTier, SyncTier.wifiTurbo);
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
    });
  });
}
