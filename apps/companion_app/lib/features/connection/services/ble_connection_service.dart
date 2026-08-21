import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart' hide BleCommand;
import '../../../core/constants/app_constants.dart';
import '../models/ble_device_item.dart';

enum ConnectionStatus { disconnected, scanning, connecting, connected }

class BleConnectionService extends ChangeNotifier {
  ConnectionStatus _status = ConnectionStatus.disconnected;
  BleDeviceItem? _connectedDevice;
  final List<BleDeviceItem> _discoveredDevices = [];
  
  DeviceState _deviceState = DeviceState.idle;
  int _lastTapTimestamp = 0;
  int _tapCount = 0;
  String _statusMessage = 'Ready to connect';

  // Getters
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isScanning => _status == ConnectionStatus.scanning;
  BleDeviceItem? get connectedDevice => _connectedDevice;
  List<BleDeviceItem> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  DeviceState get deviceState => _deviceState;
  int get lastTapTimestamp => _lastTapTimestamp;
  int get tapCount => _tapCount;
  String get statusMessage => _statusMessage;

  BleConnectionService() {
    _initBleListeners();
  }

  void _initBleListeners() {
    UniversalBle.onScanResult = (BleDevice scanResult) {
      final name = scanResult.name?.trim() ?? 'Unknown Device';
      final isXiao = name.contains('XIAO') || name.contains('Xiao') || name == AppConstants.bleDeviceName;
      final item = BleDeviceItem(
        id: scanResult.deviceId,
        name: name,
        rssi: scanResult.rssi ?? -100,
        isXiaoDevice: isXiao,
      );

      final index = _discoveredDevices.indexWhere((d) => d.id == item.id);
      if (index >= 0) {
        _discoveredDevices[index] = item;
      } else {
        _discoveredDevices.add(item);
      }
      notifyListeners();
    };

    UniversalBle.onConnectionChange = (String deviceId, bool isConnected, String? error) {
      if (isConnected) {
        _status = ConnectionStatus.connected;
        _statusMessage = 'Connected to ${_connectedDevice?.name ?? deviceId}';
        _subscribeToCharacteristics(deviceId);
      } else {
        _status = ConnectionStatus.disconnected;
        _statusMessage = 'Disconnected';
        _connectedDevice = null;
      }
      notifyListeners();
    };

    UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value, int? timestamp) {
      _handleCharacteristicValue(characteristicId.toLowerCase(), value);
    };
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 10)}) async {
    if (_status == ConnectionStatus.scanning) return;
    _discoveredDevices.clear();
    _status = ConnectionStatus.scanning;
    _statusMessage = 'Scanning for Xiao ESP32-C3...';
    notifyListeners();

    try {
      await UniversalBle.startScan();
      Timer(timeout, () {
        if (_status == ConnectionStatus.scanning) {
          stopScan();
        }
      });
    } catch (e) {
      _status = ConnectionStatus.disconnected;
      _statusMessage = 'Scan failed: $e';
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    try {
      await UniversalBle.stopScan();
    } catch (_) {}
    if (_status == ConnectionStatus.scanning) {
      _status = ConnectionStatus.disconnected;
      _statusMessage = 'Scan stopped';
      notifyListeners();
    }
  }

  Future<void> connect(BleDeviceItem device) async {
    await stopScan();
    _status = ConnectionStatus.connecting;
    _connectedDevice = device;
    _statusMessage = 'Connecting to ${device.name}...';
    notifyListeners();

    try {
      await UniversalBle.connect(device.id);
    } catch (e) {
      _status = ConnectionStatus.disconnected;
      _connectedDevice = null;
      _statusMessage = 'Connection error: $e';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      final id = _connectedDevice!.id;
      _statusMessage = 'Disconnecting...';
      notifyListeners();
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
    _status = ConnectionStatus.disconnected;
    _connectedDevice = null;
    notifyListeners();
  }

  Future<void> sendCommand(BleCommand cmd) async {
    if (!isConnected || _connectedDevice == null) {
      // If in mock or disconnected mode, simulate state transition
      _simulateCommand(cmd);
      return;
    }

    try {
      final bytes = Uint8List.fromList([cmd.rawValue]);
      await UniversalBle.write(
        _connectedDevice!.id,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharCmdUuid,
        bytes,
      );
    } catch (e) {
      _statusMessage = 'Failed to send command: $e';
      notifyListeners();
    }
  }

  Future<void> _subscribeToCharacteristics(String deviceId) async {
    try {
      await UniversalBle.discoverServices(deviceId);
      await UniversalBle.subscribeNotifications(
        deviceId,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharStateUuid,
      );
      await UniversalBle.subscribeNotifications(
        deviceId,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharTapUuid,
      );
    } catch (e) {
      debugPrint('Error subscribing to characteristics: $e');
    }
  }

  void _handleCharacteristicValue(String charUuid, Uint8List value) {
    if (charUuid == AppConstants.bleCharStateUuid.toLowerCase()) {
      if (value.isNotEmpty) {
        _deviceState = DeviceState.fromInt(value[0]);
        notifyListeners();
      }
    } else if (charUuid == AppConstants.bleCharTapUuid.toLowerCase()) {
      _tapCount++;
      _lastTapTimestamp = DateTime.now().millisecondsSinceEpoch;
      notifyListeners();
    }
  }

  // Simulation mode helper for instant testing on Windows / emulator without hardware
  void enableMockMode() {
    _status = ConnectionStatus.connected;
    _connectedDevice = BleDeviceItem(
      id: 'SIM-XIAO-C3-01',
      name: 'XIAO-Audio-Recorder (Simulated)',
      rssi: -42,
      isXiaoDevice: true,
    );
    _deviceState = DeviceState.idle;
    _statusMessage = 'Connected (Simulated Device)';
    notifyListeners();
  }

  void _simulateCommand(BleCommand cmd) {
    switch (cmd) {
      case BleCommand.startRecording:
        _deviceState = DeviceState.recording;
        _statusMessage = 'Recording started';
        break;
      case BleCommand.stopRecording:
        _deviceState = DeviceState.done;
        _statusMessage = 'Recording stopped';
        break;
      case BleCommand.startWifi:
        _deviceState = DeviceState.wifiActive;
        _statusMessage = 'Wi-Fi AP active: ${AppConstants.defaultApSsid}';
        break;
      case BleCommand.stopWifi:
        _deviceState = DeviceState.idle;
        _statusMessage = 'Wi-Fi AP stopped';
        break;
      case BleCommand.enterSleep:
        _deviceState = DeviceState.sleeping;
        _statusMessage = 'Device entering deep sleep';
        break;
      case BleCommand.clearStorage:
        _statusMessage = 'Flash storage cleared';
        break;
      case BleCommand.startL2capStream:
        _deviceState = DeviceState.transferring;
        _statusMessage = 'L2CAP Stream active';
        break;
      case BleCommand.none:
        break;
    }
    notifyListeners();
  }
}
