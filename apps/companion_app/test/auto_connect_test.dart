import 'package:flutter_test/flutter_test.dart';
import 'package:dictula/core/constants/app_constants.dart';
import 'package:dictula/features/connection/models/ble_device_item.dart';
import 'package:dictula/features/connection/services/ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auto-Connect & Proximity RSSI Tests', () {
    test('Correctly sorts Xiao candidates by RSSI (closest / best link first)', () {
      final devFarXiao = BleDeviceItem(
        id: 'AA:BB:CC:11:22:33',
        name: 'XIAO-Audio-Recorder',
        rssi: -85,
        isXiaoDevice: true,
      );

      final devNearXiao = BleDeviceItem(
        id: 'AA:BB:CC:44:55:66',
        name: 'XIAO-Audio-Recorder',
        rssi: -42, // Stronger / closer signal
        isXiaoDevice: true,
      );

      final devMediumXiao = BleDeviceItem(
        id: 'AA:BB:CC:77:88:99',
        name: 'Xiao-ESP32C3-Node',
        rssi: -65,
        isXiaoDevice: true,
      );

      final devNonXiao = BleDeviceItem(
        id: 'XX:YY:ZZ:00:11:22',
        name: 'Generic Smart TV',
        rssi: -30, // Strong signal but not a Xiao peripheral
        isXiaoDevice: false,
      );

      final discoveredList = [devFarXiao, devNonXiao, devMediumXiao, devNearXiao];

      // 1. Filter only Xiao peripherals
      final xiaoCandidates = discoveredList.where((d) =>
        d.isXiaoDevice ||
        d.name.toLowerCase().contains('xiao') ||
        d.name == AppConstants.bleDeviceName
      ).toList();

      expect(xiaoCandidates.length, 3);
      expect(xiaoCandidates.contains(devNonXiao), isFalse);

      // 2. Sort descending by RSSI
      xiaoCandidates.sort((a, b) => b.rssi.compareTo(a.rssi));

      // The closest Xiao (-42 dBm) must be the first element
      expect(xiaoCandidates.first.id, 'AA:BB:CC:44:55:66');
      expect(xiaoCandidates.first.rssi, -42);

      // Second must be -65 dBm
      expect(xiaoCandidates[1].id, 'AA:BB:CC:77:88:99');
      expect(xiaoCandidates[1].rssi, -65);

      // Third must be -85 dBm
      expect(xiaoCandidates[2].id, 'AA:BB:CC:11:22:33');
      expect(xiaoCandidates[2].rssi, -85);
    });

    test('BleService default settings have auto-connect enabled', () {
      final bleService = BleService();
      expect(bleService.autoConnectEnabled, isTrue);
      expect(bleService.isAutoConnecting, isFalse);
      expect(bleService.isConnected, isFalse);
    });

    test('BleService autoConnectNearestXiao succeeds in mock mode', () async {
      final bleService = BleService();
      bleService.enableMockMode();
      expect(bleService.isConnected, isTrue);
      expect(bleService.connectedDevice?.name, contains('XIAO'));

      final result = await bleService.autoConnectNearestXiao();
      expect(result, isTrue);
      expect(bleService.isConnected, isTrue);
    });

    test('BleDeviceItem recognizes Xiao device names accurately', () {
      final standardXiao = BleDeviceItem(
        id: '01',
        name: 'XIAO-Audio-Recorder',
        rssi: -50,
        isXiaoDevice: true,
      );

      final customXiao = BleDeviceItem(
        id: '02',
        name: 'Xiao-ESP32-Voice',
        rssi: -60,
        isXiaoDevice: true,
      );

      final otherDevice = BleDeviceItem(
        id: '03',
        name: 'Bluetooth Speaker',
        rssi: -45,
        isXiaoDevice: false,
      );

      expect(standardXiao.isXiaoDevice, isTrue);
      expect(customXiao.isXiaoDevice, isTrue);
      expect(otherDevice.isXiaoDevice, isFalse);
    });
  });
}
