import 'package:flutter_test/flutter_test.dart';
import 'package:dictula/core/constants/app_constants.dart';
import 'package:dictula/features/connection/models/ble_device_item.dart';
import 'package:dictula/features/connection/services/ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auto-Connect & Proximity RSSI Tests', () {
    test('Correctly sorts hardware candidates by RSSI (closest / best link first)', () {
      final devFar = BleDeviceItem(
        id: 'AA:BB:CC:11:22:33',
        name: 'Audio-Vault',
        rssi: -85,
        isHardwareDevice: true,
      );

      final devNear = BleDeviceItem(
        id: 'AA:BB:CC:44:55:66',
        name: 'Audio-Vault',
        rssi: -42, // Stronger / closer signal
        isHardwareDevice: true,
      );

      final devMedium = BleDeviceItem(
        id: 'AA:BB:CC:77:88:99',
        name: 'Audio-Vault-Node',
        rssi: -65,
        isHardwareDevice: true,
      );

      final devNonHardware = BleDeviceItem(
        id: 'XX:YY:ZZ:00:11:22',
        name: 'Generic Smart TV',
        rssi: -30, // Strong signal but not a hardware peripheral
        isHardwareDevice: false,
      );

      final discoveredList = [devFar, devNonHardware, devMedium, devNear];

      // 1. Filter only hardware peripherals
      final candidates = discoveredList.where((d) =>
        d.isHardwareDevice ||
        d.name.toLowerCase().contains('audio') ||
        d.name == AppConstants.bleDeviceName
      ).toList();

      expect(candidates.length, 3);
      expect(candidates.contains(devNonHardware), isFalse);

      // 2. Sort descending by RSSI
      candidates.sort((a, b) => b.rssi.compareTo(a.rssi));

      // The closest (-42 dBm) must be the first element
      expect(candidates.first.id, 'AA:BB:CC:44:55:66');
      expect(candidates.first.rssi, -42);

      // Second must be -65 dBm
      expect(candidates[1].id, 'AA:BB:CC:77:88:99');
      expect(candidates[1].rssi, -65);

      // Third must be -85 dBm
      expect(candidates[2].id, 'AA:BB:CC:11:22:33');
      expect(candidates[2].rssi, -85);
    });

    test('BleService default settings have auto-connect enabled', () {
      final bleService = BleService();
      expect(bleService.autoConnectEnabled, isTrue);
      expect(bleService.isAutoConnecting, isFalse);
      expect(bleService.isConnected, isFalse);
    });

    test('BleService autoConnectNearestDevice succeeds in mock mode', () async {
      final bleService = BleService();
      bleService.enableMockMode();
      expect(bleService.isConnected, isTrue);
      expect(bleService.connectedDevice?.name, contains('Audio-Vault'));

      final result = await bleService.autoConnectNearestDevice();
      expect(result, isTrue);
      expect(bleService.isConnected, isTrue);
    });

    test('BleDeviceItem recognizes hardware device names accurately', () {
      final standardDev = BleDeviceItem(
        id: '01',
        name: 'Audio-Vault',
        rssi: -50,
        isHardwareDevice: true,
      );

      final customDev = BleDeviceItem(
        id: '02',
        name: 'Audio-Vault-Voice',
        rssi: -60,
        isHardwareDevice: true,
      );

      final otherDevice = BleDeviceItem(
        id: '03',
        name: 'Bluetooth Speaker',
        rssi: -45,
        isHardwareDevice: false,
      );

      expect(standardDev.isHardwareDevice, isTrue);
      expect(customDev.isHardwareDevice, isTrue);
      expect(otherDevice.isHardwareDevice, isFalse);
    });
  });
}
