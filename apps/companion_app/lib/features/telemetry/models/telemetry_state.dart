class TelemetryState {
  final bool hasRealData;
  final double? batteryVoltage;
  final int? batteryPercent;
  final bool isCharging;
  final int? freeHeapBytes;
  final int totalHeapBytes;
  final int? usedStorageBytes;
  final int totalStorageBytes;
  final double? accelX;
  final double? accelY;
  final double? accelZ;
  final double? motionMagnitude;
  final int tapCount;
  final DateTime? lastUpdated;

  TelemetryState({
    this.hasRealData = false,
    this.batteryVoltage,
    this.batteryPercent,
    this.isCharging = false,
    this.freeHeapBytes,
    this.totalHeapBytes = 327680,
    this.usedStorageBytes,
    this.totalStorageBytes = 16777216,
    this.accelX,
    this.accelY,
    this.accelZ,
    this.motionMagnitude,
    required this.tapCount,
    this.lastUpdated,
  });

  factory TelemetryState.initial() {
    return TelemetryState(
      hasRealData: false,
      batteryVoltage: null,
      batteryPercent: null,
      isCharging: false,
      freeHeapBytes: null,
      totalHeapBytes: 327680,
      usedStorageBytes: null,
      totalStorageBytes: 16777216,
      accelX: null,
      accelY: null,
      accelZ: null,
      motionMagnitude: null,
      tapCount: 0,
      lastUpdated: null,
    );
  }

  TelemetryState copyWith({
    bool? hasRealData,
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
      hasRealData: hasRealData ?? this.hasRealData,
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
