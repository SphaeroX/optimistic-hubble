class BleDeviceItem {
  final String id;
  final String name;
  final int rssi;
  final bool isHardwareDevice;

  BleDeviceItem({
    required this.id,
    required this.name,
    required this.rssi,
    this.isHardwareDevice = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDeviceItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
