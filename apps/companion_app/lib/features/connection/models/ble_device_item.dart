class BleDeviceItem {
  final String id;
  final String name;
  final int rssi;
  final bool isXiaoDevice;

  BleDeviceItem({
    required this.id,
    required this.name,
    required this.rssi,
    required this.isXiaoDevice,
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
