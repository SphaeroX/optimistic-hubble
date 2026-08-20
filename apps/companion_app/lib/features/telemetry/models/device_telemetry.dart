import '../../../core/constants/app_constants.dart';

class DeviceTelemetry {
  final bool hasRealData;
  final DeviceState state;
  final int totalAudioBytes;
  final int sampleRate;
  final double? batteryVoltage;
  final int? batteryPercent;
  final bool isCharging;
  final int? freeHeapBytes;
  final int? totalHeapBytes;
  final int? usedStorageBytes;
  final int? totalStorageBytes;
  final int totalClips;
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final double? motionMagnitude;
  final int tapCount;
  final DateTime? lastUpdated;

  DeviceTelemetry({
    this.hasRealData = false,
    required this.state,
    required this.totalAudioBytes,
    required this.sampleRate,
    this.batteryVoltage,
    this.batteryPercent,
    this.isCharging = false,
    this.freeHeapBytes,
    this.totalHeapBytes,
    this.usedStorageBytes,
    this.totalStorageBytes,
    required this.totalClips,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.motionMagnitude,
    required this.tapCount,
    this.lastUpdated,
  });

  factory DeviceTelemetry.initial() {
    return DeviceTelemetry(
      hasRealData: false,
      state: DeviceState.idle,
      totalAudioBytes: 0,
      sampleRate: AppConstants.audioSampleRate,
      batteryVoltage: null,
      batteryPercent: null,
      isCharging: false,
      freeHeapBytes: null,
      totalHeapBytes: 327680,
      usedStorageBytes: null,
      totalStorageBytes: 1966080,
      totalClips: 0,
      accelX: null,
      accelY: null,
      accelZ: null,
      motionMagnitude: null,
      tapCount: 0,
      lastUpdated: null,
    );
  }

  DeviceTelemetry copyWith({
    bool? hasRealData,
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
      hasRealData: hasRealData ?? this.hasRealData,
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
