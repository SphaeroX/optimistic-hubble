class BleDeviceItem {
  final String id;
  final String name;
  final int rssi;
  final bool isHardwareDevice;

  BleDeviceItem({
    required this.id,
    required this.name,
    required this.rssi,
    bool? isHardwareDevice,
    bool? isXiaoDevice,
  }) : isHardwareDevice = isHardwareDevice ?? isXiaoDevice ?? false;

  bool get isXiaoDevice => isHardwareDevice;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDeviceItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
