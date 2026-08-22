/// Application and Firmware Protocol Constants for XIAO ESP32-C3
class AppConstants {
  AppConstants._();

  // App Metadata
  static const String appName = 'Xiao Audio Companion';
  static const String appVersion = '1.0.0';

  // BLE Service & Characteristics UUIDs (128-bit Custom Service)
  static const String bleDeviceName = 'XIAO-Audio-Recorder';
  static const String bleServiceUuid = '19b10000-e8f2-537e-4f6c-d104768a1214';
  static const String bleCharStateUuid = '19b10001-e8f2-537e-4f6c-d104768a1214';
  static const String bleCharAudioUuid = '19b10002-e8f2-537e-4f6c-d104768a1214';
  static const String bleCharTapUuid = '19b10003-e8f2-537e-4f6c-d104768a1214';
  static const String bleCharCmdUuid = '19b10004-e8f2-537e-4f6c-d104768a1214';

  // BLE L2CAP Connection-Oriented Channels (CoC)
  static const int bleL2capPsm = 0x0081;

  // 2-Stage Plaud Note Hybrid Sync Thresholds
  // Clips < 500 KB: Tier 1 BLE Standard Auto-Sync (Silent, no user action required)
  // Clips >= 500 KB or Manual Fast Transfer: Tier 2 Wi-Fi Fast Transfer (> 2.0 MB/s)
  static const int autoFastTransferThresholdBytes = 524288; // 512 KB (approx. 1 min audio)
  static const int tier1MaxSizeBytes = 2097152; // 2.0 MB

  // Wi-Fi SoftAP Sync Defaults
  static const String defaultApSsid = 'XIAO-Audio-Hotspot';
  static const String defaultApSsidPattern = 'XIAO-Audio-.*';
  static const String defaultApPassword = 'xiaoesp32c3';
  static const String defaultDeviceIp = '192.168.4.1';
  static const int defaultHttpPort = 80;

  // Audio Specs
  static const int audioSampleRate = 16000; // 16 kHz
  static const int audioBitsPerSample = 4; // IMA-ADPCM (4 bits/sample = 8 KB/s)
  static const int audioChannels = 1; // Mono
}

/// Device Operational States (matching firmware enum DeviceState)
enum DeviceState {
  idle(0, 'Idle', 'Standby mode, ready to record'),
  recording(1, 'Recording', 'I2S Mic active, capturing audio'),
  transferring(2, 'Transferring', 'Syncing clips over BLE/Wi-Fi'),
  done(3, 'Done', 'Operation completed successfully'),
  wifiActive(4, 'Wi-Fi Hotspot Active', 'High-speed sync server running'),
  sleeping(5, 'Sleeping', 'Ultra-low power deep sleep');

  final int rawValue;
  final String label;
  final String description;

  const DeviceState(this.rawValue, this.label, this.description);

  static DeviceState fromInt(int value) {
    return DeviceState.values.firstWhere(
      (s) => s.rawValue == value,
      orElse: () => DeviceState.idle,
    );
  }
}

/// Remote Control BLE Commands (matching firmware enum BleCommand)
enum BleCommand {
  none(0),
  startWifi(1),
  stopWifi(2),
  enterSleep(3),
  startRecording(4),
  stopRecording(5),
  clearStorage(6),
  startL2capStream(7);

  final int rawValue;
  const BleCommand(this.rawValue);
}

/// 2-Stage Sync Architecture Tiers (Plaud Note Model)
enum SyncTier {
  bleStandard('BLE 5.0 Auto-Sync', 'Silent background sync & live telemetry (<5 mA)'),
  wifiFast('WiFi Fast Transfer', 'On-demand high-speed Wi-Fi Turbo sync (>2.0 MB/s)');

  final String label;
  final String description;
  const SyncTier(this.label, this.description);
}

/// 5-Phase Wi-Fi Fast Transfer State Machine
enum FastTransferPhase {
  none(0, 'Standby', 'Ready to initiate Fast Transfer'),
  activatingHotspot(1, 'Activating Hotspot', 'Sending BLE command to start ESP32 Access Point...'),
  connectingWifi(2, 'Connecting Wi-Fi', 'Connecting to XIAO-Audio-Hotspot...'),
  handshaking(3, 'Handshaking', 'Verifying device connection and storage index...'),
  ready(4, 'Ready', 'Device ready for high-speed streaming'),
  transferring(5, 'Turbo Transfer', 'Downloading audio data via high-speed HTTP stream...'),
  completed(6, 'Complete', 'Fast Transfer successfully verified and saved!'),
  failed(7, 'Error', 'Transfer failed or was cancelled');

  final int stepIndex;
  final String title;
  final String description;
  const FastTransferPhase(this.stepIndex, this.title, this.description);

  bool get isActive => this == activatingHotspot || this == connectingWifi || this == handshaking || this == ready || this == transferring;
  bool get isDone => this == completed;
  bool get isError => this == failed;
}
