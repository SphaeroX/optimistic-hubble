class TelemetryState {
  final double batteryVoltage;
  final int batteryPercent;
  final bool isCharging;
  final int freeHeapBytes;
  final int totalHeapBytes;
  final int usedStorageBytes;
  final int totalStorageBytes;
  final double accelX;
  final double accelY;
  final double accelZ;
  final double motionMagnitude;
  final int tapCount;
  final DateTime lastUpdated;

  TelemetryState({
    required this.batteryVoltage,
    required this.batteryPercent,
    required this.isCharging,
    required this.freeHeapBytes,
    required this.totalHeapBytes,
    required this.usedStorageBytes,
    required this.totalStorageBytes,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.motionMagnitude,
    required this.tapCount,
    required this.lastUpdated,
  });

  factory TelemetryState.initial() {
    return TelemetryState(
      batteryVoltage: 4.12,
      batteryPercent: 92,
      isCharging: false,
      freeHeapBytes: 185320,
      totalHeapBytes: 327680,
      usedStorageBytes: 420 * 1024,
      totalStorageBytes: 1920 * 1024,
      accelX: 0.02,
      accelY: 0.05,
      accelZ: 0.98,
      motionMagnitude: 0.98,
      tapCount: 0,
      lastUpdated: DateTime.now(),
    );
  }

  TelemetryState copyWith({
    double? batteryVoltage,
    int? batteryPercent,
    bool? isCharging,
    int? freeHeapBytes,
    int? totalHeapBytes,
    int? usedStorageBytes,
    int? totalStorageBytes,
    double? accelX,
    double? accelY,
    double? accelZ,
    double? motionMagnitude,
    int? tapCount,
    DateTime? lastUpdated,
  }) {
    return TelemetryState(
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      isCharging: isCharging ?? this.isCharging,
      freeHeapBytes: freeHeapBytes ?? this.freeHeapBytes,
      totalHeapBytes: totalHeapBytes ?? this.totalHeapBytes,
      usedStorageBytes: usedStorageBytes ?? this.usedStorageBytes,
      totalStorageBytes: totalStorageBytes ?? this.totalStorageBytes,
      accelX: accelX ?? this.accelX,
      accelY: accelY ?? this.accelY,
      accelZ: accelZ ?? this.accelZ,
      motionMagnitude: motionMagnitude ?? this.motionMagnitude,
      tapCount: tapCount ?? this.tapCount,
      lastUpdated: lastUpdated ?? DateTime.now(),
    );
  }
}
