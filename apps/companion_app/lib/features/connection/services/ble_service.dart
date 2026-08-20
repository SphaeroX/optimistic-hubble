import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart' hide BleCommand;
import '../../../core/constants/app_constants.dart';
import '../../telemetry/models/device_telemetry.dart';
import '../../telemetry/models/tap_event.dart';
import '../models/ble_device_item.dart';

enum ConnectionStatus { disconnected, scanning, connecting, connected }

class LogEntry {
  final DateTime time;
  final String tag;
  final String message;
  final bool isError;

  LogEntry(this.tag, this.message, {this.isError = false}) : time = DateTime.now();

  String get formattedTime {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class BleService extends ChangeNotifier {
  ConnectionStatus _status = ConnectionStatus.disconnected;
  BleDeviceItem? _connectedDevice;
  final List<BleDeviceItem> _discoveredDevices = [];
  final List<LogEntry> _logs = [];
  final List<TapEvent> _tapHistory = [];

  DeviceTelemetry _telemetry = DeviceTelemetry.initial();
  String _statusMessage = 'Disconnected';
  bool _isMockMode = false;
  Timer? _mockTelemetryTimer;

  // Multi-packet audio chunk buffer
  final Map<int, Uint8List> _audioChunks = {};

  // Getters
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isScanning => _status == ConnectionStatus.scanning;
  bool get isMockMode => _isMockMode;
  BleDeviceItem? get connectedDevice => _connectedDevice;
  List<BleDeviceItem> get discoveredDevices => List.unmodifiable(_discoveredDevices);
  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<TapEvent> get tapHistory => List.unmodifiable(_tapHistory);
  DeviceTelemetry get telemetry => _telemetry;
  String get statusMessage => _statusMessage;

  BleService() {
    _initBleCallbacks();
    _log('BLE', 'Universal BLE Engine Initialized');
  }

  void _log(String tag, String message, {bool isError = false}) {
    final entry = LogEntry(tag, message, isError: isError);
    _logs.insert(0, entry);
    if (_logs.length > 200) _logs.removeLast();
    notifyListeners();
  }

  void _initBleCallbacks() {
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
        if (isXiao) {
          _log('SCAN', 'Discovered XIAO ESP32-C3 peripheral: ${item.id} (RSSI: ${item.rssi} dBm)');
        }
      }
      notifyListeners();
    };

    UniversalBle.onConnectionChange = (String deviceId, bool isConnected, String? error) async {
      _log('BLE', 'Connection Callback for $deviceId: connected=$isConnected ${error != null ? "error=$error" : ""}');

      if (isConnected) {
        _status = ConnectionStatus.connected;
        _connectedDevice ??= _discoveredDevices.firstWhere(
          (d) => d.id == deviceId,
          orElse: () => BleDeviceItem(id: deviceId, name: 'XIAO-Audio-Recorder', rssi: 0, isXiaoDevice: true),
        );
        _statusMessage = 'Connected to ${_connectedDevice!.name}';
        notifyListeners();

        await _setupConnectedGatt(deviceId);
      } else {
        _status = ConnectionStatus.disconnected;
        _statusMessage = 'Disconnected';
        _connectedDevice = null;
        _telemetry = DeviceTelemetry.initial(); // Reset to disconnected state
        notifyListeners();
      }
    };

    UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value, int? timestamp) {
      _handleIncomingCharacteristic(characteristicId.toLowerCase(), value);
    };
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 12)}) async {
    if (_status == ConnectionStatus.scanning) return;
    _discoveredDevices.clear();
    _status = ConnectionStatus.scanning;
    _statusMessage = 'Scanning for Xiao ESP32-C3...';
    _log('SCAN', 'Started BLE scan for UUID ${AppConstants.bleServiceUuid}');
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
      _log('SCAN', 'Scan error: $e', isError: true);
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
      _log('SCAN', 'Scan stopped');
      notifyListeners();
    }
  }

  Future<void> connect(BleDeviceItem device) async {
    await stopScan();
    _status = ConnectionStatus.connecting;
    _connectedDevice = device;
    _statusMessage = 'Connecting to ${device.name}...';
    _log('BLE', 'Initiating connection to ${device.id} (${device.name})');
    notifyListeners();

    try {
      await UniversalBle.connect(device.id);
      
      // Delay slightly and check connection state
      await Future.delayed(const Duration(milliseconds: 300));
      final state = await UniversalBle.getConnectionState(device.id);
      _log('BLE', 'Queried connection state for ${device.id}: $state');

      if (state == BleConnectionState.connected) {
        _status = ConnectionStatus.connected;
        _statusMessage = 'Connected to ${device.name}';
        notifyListeners();
        await _setupConnectedGatt(device.id);
      }
    } catch (e) {
      _status = ConnectionStatus.disconnected;
      _connectedDevice = null;
      _statusMessage = 'Connection error: $e';
      _log('BLE', 'Failed to connect: $e', isError: true);
      notifyListeners();
    }
  }

  Future<void> _setupConnectedGatt(String deviceId) async {
    try {
      _log('GATT', 'Discovering GATT services for $deviceId...');
      final services = await UniversalBle.discoverServices(deviceId);
      _log('GATT', 'Discovered ${services.length} services on peripheral');

      await _subscribeToCharacteristics(deviceId);
      await _readInitialState(deviceId);
    } catch (e) {
      _log('GATT', 'Service setup error: $e', isError: true);
    }
  }

  Future<void> _readInitialState(String deviceId) async {
    try {
      _log('GATT', 'Reading initial State Characteristic...');
      final val = await UniversalBle.read(
        deviceId,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharStateUuid,
      );
      if (val.isNotEmpty) {
        _parseStatePayload(val);
        _log('GATT', 'Initial State received from hardware: ${_telemetry.state.label}');
      }
    } catch (e) {
      _log('GATT', 'Could not read initial state: $e');
    }
  }

  Future<void> disconnect() async {
    _mockTelemetryTimer?.cancel();
    if (_isMockMode) {
      _isMockMode = false;
      _status = ConnectionStatus.disconnected;
      _connectedDevice = null;
      _telemetry = DeviceTelemetry.initial();
      _statusMessage = 'Disconnected';
      _log('MOCK', 'Simulated device disconnected');
      notifyListeners();
      return;
    }

    if (_connectedDevice != null) {
      final id = _connectedDevice!.id;
      _statusMessage = 'Disconnecting...';
      _log('BLE', 'Disconnecting from $id...');
      notifyListeners();
      try {
        await UniversalBle.disconnect(id);
      } catch (_) {}
    }
    _status = ConnectionStatus.disconnected;
    _connectedDevice = null;
    _telemetry = DeviceTelemetry.initial();
    notifyListeners();
  }

  Future<void> sendCommand(BleCommand cmd) async {
    _log('CMD', 'Sending BLE Command: ${cmd.name} (Code: ${cmd.rawValue})');

    if (_isMockMode) {
      _simulateCommand(cmd);
      return;
    }

    if (!isConnected || _connectedDevice == null) {
      _log('CMD', 'Cannot send command: No device connected', isError: true);
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
      _log('CMD', 'Command ${cmd.name} transmitted successfully to hardware');
    } catch (e) {
      _log('CMD', 'Failed to send command ${cmd.name}: $e', isError: true);
    }
  }

  Future<void> _subscribeToCharacteristics(String deviceId) async {
    try {
      await UniversalBle.subscribeNotifications(
        deviceId,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharStateUuid,
      );
      _log('GATT', 'Subscribed to State Characteristic (19b10001)');

      await UniversalBle.subscribeNotifications(
        deviceId,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharTapUuid,
      );
      _log('GATT', 'Subscribed to Tap/IMU Characteristic (19b10003)');

      await UniversalBle.subscribeNotifications(
        deviceId,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharAudioUuid,
      );
      _log('GATT', 'Subscribed to Audio Stream Characteristic (19b10002)');
    } catch (e) {
      _log('GATT', 'Subscription error: $e', isError: true);
    }
  }

  void _handleIncomingCharacteristic(String charUuid, Uint8List value) {
    if (charUuid == AppConstants.bleCharStateUuid.toLowerCase()) {
      _parseStatePayload(value);
    } else if (charUuid == AppConstants.bleCharTapUuid.toLowerCase()) {
      _parseTapPayload(value);
    } else if (charUuid == AppConstants.bleCharAudioUuid.toLowerCase()) {
      _parseAudioChunkPayload(value);
    }
  }

  void _parseStatePayload(Uint8List value) {
    if (value.length < 7) return;
    final state = DeviceState.fromInt(value[0]);
    final totalBytes = value[1] | (value[2] << 8) | (value[3] << 16) | (value[4] << 24);
    final sampleRate = value[5] | (value[6] << 8);

    _telemetry = _telemetry.copyWith(
      hasRealData: true,
      state: state,
      totalAudioBytes: totalBytes,
      sampleRate: sampleRate > 0 ? sampleRate : AppConstants.audioSampleRate,
      lastUpdated: DateTime.now(),
    );
    _log('STATE', 'Hardware State: ${state.label} | Recorded: $totalBytes B | Rate: $sampleRate Hz');
    notifyListeners();
  }

  void _parseTapPayload(Uint8List value) {
    if (value.length < 5) return;
    final int fixedShock = value[1] | (value[2] << 8) | (value[3] << 16) | (value[4] << 24);
    final double magnitude = fixedShock / 1000.0;
    final newCount = _telemetry.tapCount + 1;

    final tapEvent = TapEvent(
      timestamp: DateTime.now(),
      shockMagnitude: magnitude > 0 ? magnitude : 1.45,
      tapIndex: newCount,
    );

    _tapHistory.insert(0, tapEvent);
    if (_tapHistory.length > 50) _tapHistory.removeLast();

    _telemetry = _telemetry.copyWith(
      hasRealData: true,
      tapCount: newCount,
      motionMagnitude: tapEvent.shockMagnitude,
      lastUpdated: DateTime.now(),
    );

    _log('IMU', 'Hardware Tap Detected! Magnitude: ${tapEvent.shockMagnitude.toStringAsFixed(2)}g');
    notifyListeners();
  }

  void _parseAudioChunkPayload(Uint8List value) {
    if (value.length < 6) return;
    final chunkIdx = value[0] | (value[1] << 8);
    final totalChunks = value[2] | (value[3] << 8);
    final payloadLen = value[4] | (value[5] << 8);

    if (value.length < 6 + payloadLen) return;
    final payload = value.sublist(6, 6 + payloadLen);

    _audioChunks[chunkIdx] = payload;
    _log('AUDIO', 'Received Audio Chunk #$chunkIdx of $totalChunks ($payloadLen bytes)');

    if (_audioChunks.length == totalChunks) {
      final List<int> fullAudio = [];
      for (int i = 0; i < totalChunks; i++) {
        if (_audioChunks.containsKey(i)) {
          fullAudio.addAll(_audioChunks[i]!);
        }
      }
      _audioChunks.clear();
      _log('AUDIO', 'All $totalChunks audio chunks reconstructed (${fullAudio.length} bytes)');
    }
    notifyListeners();
  }

  // ==========================================================================
  // Simulation Mode (Only enabled when explicitly clicked by user)
  // ==========================================================================
  void enableMockMode() {
    _isMockMode = true;
    _status = ConnectionStatus.connected;
    _connectedDevice = BleDeviceItem(
      id: 'SIM-XIAO-C3-01',
      name: 'XIAO-Audio-Recorder (Simulated)',
      rssi: -38,
      isXiaoDevice: true,
    );
    _telemetry = _telemetry.copyWith(
      hasRealData: true,
      batteryVoltage: 4.12,
      batteryPercent: 92,
      freeHeapBytes: 194560,
      usedStorageBytes: 420 * 1024,
      motionMagnitude: 0.98,
      accelX: 0.02,
      accelY: 0.05,
      accelZ: 0.98,
      lastUpdated: DateTime.now(),
    );
    _statusMessage = 'Connected (Simulated Hardware)';
    _log('MOCK', 'Enabled Hardware Simulation Mode for PC Testing');

    _mockTelemetryTimer?.cancel();
    _mockTelemetryTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!_isMockMode || !isConnected) {
        timer.cancel();
        return;
      }
      _telemetry = _telemetry.copyWith(
        batteryVoltage: 4.10 + (timer.tick % 5) * 0.01,
        freeHeapBytes: 194560 - (timer.tick * 64) % 4096,
        lastUpdated: DateTime.now(),
      );
      notifyListeners();
    });

    notifyListeners();
  }

  void triggerSimulatedTap() {
    final newCount = _telemetry.tapCount + 1;
    final event = TapEvent(
      timestamp: DateTime.now(),
      shockMagnitude: 1.45 + (newCount % 3) * 0.25,
      tapIndex: newCount,
    );
    _tapHistory.insert(0, event);
    _telemetry = _telemetry.copyWith(
      hasRealData: true,
      tapCount: newCount,
      motionMagnitude: event.shockMagnitude,
      lastUpdated: DateTime.now(),
    );
    _log('MOCK', 'Simulated Tap Triggered: ${event.shockMagnitude.toStringAsFixed(2)}g');
    notifyListeners();
  }

  void _simulateCommand(BleCommand cmd) {
    switch (cmd) {
      case BleCommand.startRecording:
        _telemetry = _telemetry.copyWith(state: DeviceState.recording);
        _statusMessage = 'Recording started';
        _log('MOCK', 'State -> RECORDING (I2S Mic active)');
        break;
      case BleCommand.stopRecording:
        _telemetry = _telemetry.copyWith(
          state: DeviceState.done,
          totalAudioBytes: _telemetry.totalAudioBytes + 96000,
        );
        _statusMessage = 'Recording stopped';
        _log('MOCK', 'State -> DONE');
        Timer(const Duration(seconds: 1), () {
          if (_isMockMode) {
            _telemetry = _telemetry.copyWith(state: DeviceState.idle);
            notifyListeners();
          }
        });
        break;
      case BleCommand.startWifi:
        _telemetry = _telemetry.copyWith(state: DeviceState.wifiActive);
        _statusMessage = 'Wi-Fi AP active';
        _log('MOCK', 'State -> WIFI_ACTIVE (SoftAP SSID: ${AppConstants.defaultApSsid})');
        break;
      case BleCommand.stopWifi:
        _telemetry = _telemetry.copyWith(state: DeviceState.idle);
        _statusMessage = 'Wi-Fi AP stopped';
        _log('MOCK', 'State -> IDLE (SoftAP closed)');
        break;
      case BleCommand.enterSleep:
        _telemetry = _telemetry.copyWith(state: DeviceState.sleeping);
        _statusMessage = 'Deep Sleep (<10µA)';
        _log('MOCK', 'State -> SLEEPING (Deep sleep active)');
        break;
      case BleCommand.none:
        break;
    }
    notifyListeners();
  }
}
