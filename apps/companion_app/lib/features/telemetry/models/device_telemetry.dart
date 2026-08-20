import '../../../core/constants/app_constants.dart';

class DeviceTelemetry {
  final DeviceState state;
  final int totalAudioBytes;
  final int sampleRate;
  final double batteryVoltage;
  final int batteryPercent;
  final bool isCharging;
  final int freeHeapBytes;
  final int totalHeapBytes;
  final int usedStorageBytes;
  final int totalStorageBytes;
  final int totalClips;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double motionMagnitude;
  final int tapCount;
  final DateTime lastUpdated;

  DeviceTelemetry({
    required this.state,
    required this.totalAudioBytes,
    required this.sampleRate,
    required this.batteryVoltage,
    required this.batteryPercent,
    required this.isCharging,
    required this.freeHeapBytes,
    required this.totalHeapBytes,
    required this.usedStorageBytes,
    required this.totalStorageBytes,
    required this.totalClips,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.motionMagnitude,
    required this.tapCount,
    required this.lastUpdated,
  });

  factory DeviceTelemetry.initial() {
    return DeviceTelemetry(
      state: DeviceState.idle,
      totalAudioBytes: 0,
      sampleRate: AppConstants.audioSampleRate,
      batteryVoltage: 4.15,
      batteryPercent: 95,
      isCharging: false,
      freeHeapBytes: 194560,
      totalHeapBytes: 327680,
      usedStorageBytes: 0,
      totalStorageBytes: 1966080, // ~1.92 MB LittleFS partition
      totalClips: 0,
      accelX: 0.01,
      accelY: 0.02,
      accelZ: 0.99,
      motionMagnitude: 0.99,
      tapCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  DeviceTelemetry copyWith({
    DeviceState? state,
    int? totalAudioBytes,
    int? sampleRate,
    double? batteryVoltage,
    int? batteryPercent,
    bool? isCharging,
    int? freeHeapBytes,
    int? totalHeapBytes,
    int? usedStorageBytes,
    int? totalStorageBytes,
    int? totalClips,
    double? accelX,
    double? accelY,
    double? accelZ,
    double? motionMagnitude,
    int? tapCount,
    DateTime? lastUpdated,
  }) {
    return DeviceTelemetry(
      state: state ?? this.state,
      totalAudioBytes: totalAudioBytes ?? this.totalAudioBytes,
      sampleRate: sampleRate ?? this.sampleRate,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      isCharging: isCharging ?? this.isCharging,
      freeHeapBytes: freeHeapBytes ?? this.freeHeapBytes,
      totalHeapBytes: totalHeapBytes ?? this.totalHeapBytes,
      usedStorageBytes: usedStorageBytes ?? this.usedStorageBytes,
      totalStorageBytes: totalStorageBytes ?? this.totalStorageBytes,
      totalClips: totalClips ?? this.totalClips,
      accelX: accelX ?? this.accelX,
      accelY: accelY ?? this.accelY,
      accelZ: accelZ ?? this.accelZ,
      motionMagnitude: motionMagnitude ?? this.motionMagnitude,
      tapCount: tapCount ?? this.tapCount,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
  }
}
