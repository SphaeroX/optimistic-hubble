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

  // Hybrid Sync Thresholds (Section 4.1 & 4.2)
  // Clips < 2.0 MB: Tier 1 BLE 5.0 (Silent Background Sync, < 18s)
  // Clips >= 2.0 MB: Tier 2 Wi-Fi SoftAP (High-Speed Turbo Sync, > 1.8 MB/s)
  static const int tier1MaxSizeBytes = 2097152; // 2.0 MB (approx. 4 min audio)

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

/// Audio Sync Tier Strategy (Tier 1 BLE vs Tier 2 Wi-Fi SoftAP)
enum SyncTier {
  bleL2cap('BLE Fast', 'Tier 1: Silent BLE 5.0 (No Wi-Fi state switch)'),
  wifiTurbo('Wi-Fi Turbo', 'Tier 2: High-Speed SoftAP (> 1.8 MB/s + Range Resume)');

  final String label;
  final String description;
  const SyncTier(this.label, this.description);
}
