import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart' hide BleCommand;
import '../../../core/constants/app_constants.dart';
import '../../../core/services/native_audio_sync_bridge.dart';
import '../../../core/services/permission_service.dart';
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
  bool _isAutoConnecting = false;
  bool _autoConnectEnabled = true;

  bool _isGattConfigured = false;
  String? _currentGattDeviceId;

  // Multi-packet audio chunk buffer
  final Map<int, Uint8List> _audioChunks = {};
  final StreamController<SyncProgressEvent> _audioProgressController = StreamController<SyncProgressEvent>.broadcast();
  Stream<SyncProgressEvent> get audioProgressEvents => _audioProgressController.stream;
  int _activeDownloadClipId = 0;
  DateTime? _downloadStartTime;
  Completer<Uint8List?>? _activeDownloadCompleter;

  // Getters
  ConnectionStatus get status => _status;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isScanning => _status == ConnectionStatus.scanning;
  bool get isConnecting => _status == ConnectionStatus.connecting;
  bool get isAutoConnecting => _isAutoConnecting;
  bool get autoConnectEnabled => _autoConnectEnabled;
  set autoConnectEnabled(bool value) {
    _autoConnectEnabled = value;
    notifyListeners();
  }
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
          _log('SCAN', 'Discovered XIAO peripheral: ${item.name} (${item.id}) RSSI: ${item.rssi} dBm');
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
          orElse: () => BleDeviceItem(id: deviceId, name: AppConstants.bleDeviceName, rssi: 0, isXiaoDevice: true),
        );
        _statusMessage = 'Connected to ${_connectedDevice!.name}';
        notifyListeners();

        await _setupConnectedGatt(deviceId);
      } else {
        _status = ConnectionStatus.disconnected;
        _statusMessage = 'Disconnected';
        _connectedDevice = null;
        _isGattConfigured = false;
        _currentGattDeviceId = null;
        _telemetry = DeviceTelemetry.initial();
        notifyListeners();
      }
    };

    UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value, int? timestamp) {
      _handleIncomingCharacteristic(characteristicId, value);
    };
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 12)}) async {
    if (_status == ConnectionStatus.scanning) return;

    // Check runtime permissions first on Android
    final hasPerm = await PermissionService.requestAppPermissions();
    if (!hasPerm) {
      _log('PERM', 'Bluetooth permissions not granted by user', isError: true);
    }

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
    _isAutoConnecting = false;
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

  /// Automatically scan for nearby Xiao devices, select the one with the strongest signal
  /// (highest RSSI / closest proximity), and establish connection without manual picker.
  Future<bool> autoConnectNearestXiao({
    Duration scanWindow = const Duration(milliseconds: 1500),
    Duration totalTimeout = const Duration(seconds: 6),
  }) async {
    if (isConnected) return true;

    if (_isMockMode) {
      enableMockMode();
      return true;
    }

    final hasPerm = await PermissionService.requestAppPermissions();
    if (!hasPerm) {
      _log('PERM', 'Bluetooth permissions not granted for auto-connect', isError: true);
    }

    _isAutoConnecting = true;
    _status = ConnectionStatus.scanning;
    _statusMessage = 'Searching for nearest Xiao device...';
    _discoveredDevices.clear();
    _log('AUTOCONNECT', 'Starting proximity scan for nearest Xiao ESP32 (RSSI auto-selection)...');
    notifyListeners();

    try {
      await UniversalBle.startScan();
    } catch (e) {
      _isAutoConnecting = false;
      _status = ConnectionStatus.disconnected;
      _statusMessage = 'Auto-connect scan failed: $e';
      _log('AUTOCONNECT', 'Scan failed: $e', isError: true);
      notifyListeners();
      return false;
    }

    final startTime = DateTime.now();
    final deadline = startTime.add(totalTimeout);
    BleDeviceItem? targetDevice;

    while (DateTime.now().isBefore(deadline) && _isAutoConnecting) {
      final xiaoCandidates = _discoveredDevices.where((d) =>
        d.isXiaoDevice ||
        d.name.toLowerCase().contains('xiao') ||
        d.name == AppConstants.bleDeviceName
      ).toList();

      final elapsed = DateTime.now().difference(startTime);
      if (xiaoCandidates.isNotEmpty && elapsed >= scanWindow) {
        // Sort descending by RSSI (closest / best radio link first, e.g. -45 dBm > -75 dBm)
        xiaoCandidates.sort((a, b) => b.rssi.compareTo(a.rssi));
        targetDevice = xiaoCandidates.first;
        _log('AUTOCONNECT', 'Found ${xiaoCandidates.length} candidate(s). Selected strongest: ${targetDevice.name} (${targetDevice.id}) with RSSI: ${targetDevice.rssi} dBm');
        break;
      }

      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!_isAutoConnecting) {
      await stopScan();
      return false;
    }

    if (targetDevice != null) {
      _statusMessage = 'Connecting to nearest: ${targetDevice.name} (${targetDevice.rssi} dBm)...';
      notifyListeners();
      await connect(targetDevice);
      _isAutoConnecting = false;
      notifyListeners();
      return isConnected;
    } else {
      await stopScan();
      _isAutoConnecting = false;
      _status = ConnectionStatus.disconnected;
      _statusMessage = 'No Xiao device found in range';
      _log('AUTOCONNECT', 'No matching Xiao device discovered within range', isError: true);
      notifyListeners();
      return false;
    }
  }

  Future<void> connect(BleDeviceItem device) async {
    _mockTelemetryTimer?.cancel();
    _isMockMode = false;

    await stopScan();
    _status = ConnectionStatus.connecting;
    _connectedDevice = device;
    _statusMessage = 'Connecting to ${device.name}...';
    _log('BLE', 'Initiating connection to ${device.id} (${device.name})');
    notifyListeners();

    try {
      await UniversalBle.connect(device.id, timeout: const Duration(seconds: 15));
      _status = ConnectionStatus.connected;
      _statusMessage = 'Connected to ${device.name}';
      notifyListeners();

      await _setupConnectedGatt(device.id);
    } catch (e) {
      _status = ConnectionStatus.disconnected;
      _connectedDevice = null;
      _isGattConfigured = false;
      _currentGattDeviceId = null;
      _statusMessage = 'Connection error: $e';
      _log('BLE', 'Failed to connect: $e', isError: true);
      notifyListeners();
    }
  }

  Future<void> _setupConnectedGatt(String deviceId) async {
    if (_isGattConfigured && _currentGattDeviceId == deviceId) return;
    _isGattConfigured = true;
    _currentGattDeviceId = deviceId;

    try {
      _log('GATT', 'Discovering GATT services for $deviceId...');
      final services = await UniversalBle.discoverServices(deviceId);
      _log('GATT', 'Discovered ${services.length} services on peripheral');

      // Small delay for Windows WinRT link stabilization
      await Future.delayed(const Duration(milliseconds: 100));

      await _subscribeToCharacteristics(deviceId);
      await _readInitialState(deviceId);
    } catch (e) {
      _log('GATT', 'GATT setup warning: $e');
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
      _log('GATT', 'Initial read note: $e');
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
    _isGattConfigured = false;
    _currentGattDeviceId = null;
    _telemetry = DeviceTelemetry.initial();
    notifyListeners();
  }

  Future<void> sendConnectHotspotCommand({
    required String ssid,
    required String passphrase,
    required String hostIp,
    required int port,
    int clipId = 0,
    bool autoDelete = false,
  }) async {
    _log('CMD', 'Sending Hotspot Connect Info to MCU: SSID="$ssid", IP=$hostIp:$port, Clip=$clipId, Delete=$autoDelete');

    if (_isMockMode) {
      _simulateCommand(BleCommand.connectHotspot);
      return;
    }

    if (!isConnected || _connectedDevice == null) {
      _log('CMD', 'Cannot send hotspot command: No device connected', isError: true);
      return;
    }

    final Map<String, dynamic> jsonPayload = {
      'cmd': BleCommand.connectHotspot.rawValue,
      'ssid': ssid,
      'pass': passphrase,
      'ip': hostIp,
      'port': port,
      'id': clipId,
      'del': autoDelete,
    };

    final String jsonStr = jsonEncode(jsonPayload);
    final bytes = Uint8List.fromList(utf8.encode(jsonStr));

    bool success = false;
    try {
      await UniversalBle.write(
        _connectedDevice!.id,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharCmdUuid,
        bytes,
        withoutResponse: false,
      );
      success = true;
    } catch (_) {
      try {
        await UniversalBle.write(
          _connectedDevice!.id,
          AppConstants.bleServiceUuid,
          AppConstants.bleCharCmdUuid,
          bytes,
          withoutResponse: true,
        );
        success = true;
      } catch (e) {
        _log('CMD', 'Failed to send Hotspot Connect command: $e', isError: true);
      }
    }

    if (success) {
      _statusMessage = 'Transmitted Hotspot credentials to MCU';
      _log('CMD', 'Hotspot credentials received by MCU, awaiting STA Wi-Fi upload...');
      notifyListeners();
    }
  }

  Future<void> sendCommand(BleCommand cmd, {int clipId = 0, int offset = 0}) async {
    _log('CMD', 'Sending BLE Command: ${cmd.name} (Code: ${cmd.rawValue}) [Clip: $clipId, Offset: $offset]');

    if (_isMockMode) {
      _simulateCommand(cmd);
      return;
    }

    if (!isConnected || _connectedDevice == null) {
      _log('CMD', 'Cannot send command: No device connected', isError: true);
      return;
    }

    final List<int> cmdPayload = [cmd.rawValue];
    if (clipId > 0 || offset > 0) {
      cmdPayload.add(clipId & 0xFF);
      cmdPayload.add((clipId >> 8) & 0xFF);
      cmdPayload.add(offset & 0xFF);
      cmdPayload.add((offset >> 8) & 0xFF);
      cmdPayload.add((offset >> 16) & 0xFF);
      cmdPayload.add((offset >> 24) & 0xFF);
    }
    final bytes = Uint8List.fromList(cmdPayload);
    bool success = false;

    // 1. Try write to Command Characteristic (with response)
    try {
      await UniversalBle.write(
        _connectedDevice!.id,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharCmdUuid,
        bytes,
        withoutResponse: false,
      );
      success = true;
    } catch (_) {
      // 2. Fallback: Try write without response
      try {
        await UniversalBle.write(
          _connectedDevice!.id,
          AppConstants.bleServiceUuid,
          AppConstants.bleCharCmdUuid,
          bytes,
          withoutResponse: true,
        );
        success = true;
      } catch (_) {
        // 3. Fallback: Try write to State Characteristic
        try {
          await UniversalBle.write(
            _connectedDevice!.id,
            AppConstants.bleServiceUuid,
            AppConstants.bleCharStateUuid,
            bytes,
            withoutResponse: false,
          );
          success = true;
        } catch (e3) {
          _log('CMD', 'Failed to send command ${cmd.name}: $e3', isError: true);
        }
      }
    }

    if (success) {
      _log('CMD', 'Command ${cmd.name} transmitted successfully to hardware');
      if (cmd == BleCommand.startWifi) {
        _statusMessage = 'Starting Wi-Fi Hotspot on hardware...';
        notifyListeners();
      } else if (cmd == BleCommand.startL2capStream) {
        _statusMessage = 'Starting L2CAP Stream for Clip #$clipId...';
        notifyListeners();
      }
    }
  }

  Future<void> _subscribeToCharacteristics(String deviceId) async {
    // 1. State / Telemetry characteristic
    try {
      await UniversalBle.subscribeNotifications(
        deviceId,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharStateUuid,
      );
      _log('GATT', 'Subscribed to State/Telemetry Characteristic');
    } catch (e) {
      _log('GATT', 'Subscribe State notice: $e');
    }

    await Future.delayed(const Duration(milliseconds: 60));

    // 2. Tap / IMU shock characteristic
    try {
      await UniversalBle.subscribeNotifications(
        deviceId,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharTapUuid,
      );
      _log('GATT', 'Subscribed to Tap/IMU Characteristic');
    } catch (e) {
      _log('GATT', 'Subscribe Tap notice: $e');
    }

    await Future.delayed(const Duration(milliseconds: 60));

    // 3. Audio chunk streaming characteristic
    try {
      await UniversalBle.subscribeNotifications(
        deviceId,
        AppConstants.bleServiceUuid,
        AppConstants.bleCharAudioUuid,
      );
      _log('GATT', 'Subscribed to Audio Stream Characteristic');
    } catch (e) {
      _log('GATT', 'Subscribe Audio notice: $e');
    }
  }

  void _handleIncomingCharacteristic(String charUuid, Uint8List value) {
    final cleanUuid = charUuid.toLowerCase().replaceAll('-', '');
    if (cleanUuid.contains('ff01') || BleUuidParser.compareStrings(charUuid, AppConstants.bleCharStateUuid)) {
      _parseStatePayload(value);
    } else if (cleanUuid.contains('ff03') || BleUuidParser.compareStrings(charUuid, AppConstants.bleCharTapUuid)) {
      _parseTapPayload(value);
    } else if (cleanUuid.contains('ff02') || BleUuidParser.compareStrings(charUuid, AppConstants.bleCharAudioUuid)) {
      _parseAudioChunkPayload(value);
    }
  }

  void _parseStatePayload(Uint8List value) {
    if (value.length < 7) return;

    final ByteData bd = ByteData.sublistView(value);
    final state = DeviceState.fromInt(bd.getUint8(0));
    final totalBytes = bd.getUint32(1, Endian.little);
    final sampleRate = bd.getUint16(5, Endian.little);

    double? batteryVoltage;
    int? batteryPercent;
    bool isCharging = false;
    int? freeHeap;
    int? usedStorage;
    int? totalStorage;
    int? totalClips;
    double? accelX;
    double? accelY;
    double? accelZ;
    double? motionMag;
    int? tapCount;

    if (value.length >= 10) {
      final mv = bd.getUint16(7, Endian.little);
      batteryVoltage = mv > 0 ? (mv / 1000.0) : 4.18;
      batteryPercent = bd.getUint8(9);
    }
    if (value.length >= 11) {
      isCharging = bd.getUint8(10) == 1;
    }
    if (value.length >= 15) {
      freeHeap = bd.getUint32(11, Endian.little);
    }
    if (value.length >= 19) {
      usedStorage = bd.getUint32(15, Endian.little);
    }
    if (value.length >= 23) {
      totalStorage = bd.getUint32(19, Endian.little);
    }
    if (value.length >= 25) {
      totalClips = bd.getUint16(23, Endian.little);
    }
    if (value.length >= 31) {
      accelX = bd.getInt16(25, Endian.little) / 1000.0;
      accelY = bd.getInt16(27, Endian.little) / 1000.0;
      accelZ = bd.getInt16(29, Endian.little) / 1000.0;
    }
    if (value.length >= 33) {
      motionMag = bd.getUint16(31, Endian.little) / 1000.0;
    }
    if (value.length >= 35) {
      tapCount = bd.getUint16(33, Endian.little);
    }

    _telemetry = _telemetry.copyWith(
      hasRealData: true,
      state: state,
      totalAudioBytes: totalBytes,
      sampleRate: sampleRate > 0 ? sampleRate : AppConstants.audioSampleRate,
      batteryVoltage: batteryVoltage ?? _telemetry.batteryVoltage ?? 4.18,
      batteryPercent: batteryPercent ?? _telemetry.batteryPercent ?? 98,
      isCharging: isCharging,
      freeHeapBytes: freeHeap ?? _telemetry.freeHeapBytes,
      usedStorageBytes: usedStorage ?? _telemetry.usedStorageBytes,
      totalStorageBytes: totalStorage ?? _telemetry.totalStorageBytes,
      totalClips: totalClips ?? _telemetry.totalClips,
      accelX: accelX ?? _telemetry.accelX,
      accelY: accelY ?? _telemetry.accelY,
      accelZ: accelZ ?? _telemetry.accelZ,
      motionMagnitude: motionMag ?? _telemetry.motionMagnitude,
      tapCount: tapCount ?? _telemetry.tapCount,
      lastUpdated: DateTime.now(),
    );

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

    _log('IMU', 'Hardware Tap Detected! Shock: ${tapEvent.shockMagnitude.toStringAsFixed(2)}g');
    notifyListeners();
  }

  void _parseAudioChunkPayload(Uint8List value) {
    if (value.length < 6) return;
    final ByteData bd = ByteData.sublistView(value);
    final chunkIdx = bd.getUint16(0, Endian.little);
    final totalChunks = bd.getUint16(2, Endian.little);
    final payloadLen = bd.getUint16(4, Endian.little);

    int clipId = _activeDownloadClipId;
    Uint8List payload;

    if (value.length >= 8 && value.length >= 8 + payloadLen) {
      clipId = bd.getUint16(6, Endian.little);
      payload = value.sublist(8, 8 + payloadLen);
    } else if (value.length >= 6 + payloadLen) {
      payload = value.sublist(6, 6 + payloadLen);
    } else {
      return;
    }

    if (_activeDownloadClipId != clipId || _audioChunks.isEmpty) {
      _activeDownloadClipId = clipId;
      _audioChunks.clear();
      _downloadStartTime ??= DateTime.now();
    }

    _audioChunks[chunkIdx] = payload;

    final progress = totalChunks > 0 ? (_audioChunks.length / totalChunks).clamp(0.0, 1.0) : 0.0;

    double speedKb = 0.0;
    if (_downloadStartTime != null) {
      final elapsedSec = DateTime.now().difference(_downloadStartTime!).inMilliseconds / 1000.0;
      if (elapsedSec > 0.05) {
        speedKb = ((_audioChunks.length * payloadLen) / 1024.0) / elapsedSec;
      }
    }

    final speedStr = speedKb > 0 ? '${speedKb.toStringAsFixed(1)} KB/s (BLE 5.0 High-Throughput)' : 'Streaming...';

    _audioProgressController.add(SyncProgressEvent(
      status: 'transferring',
      progress: progress,
      bytesReceived: _audioChunks.length * payloadLen,
      totalBytes: totalChunks * payloadLen,
      message: speedStr,
    ));

    if (_audioChunks.length >= totalChunks && totalChunks > 0) {
      final List<int> fullAudio = [];
      for (int i = 0; i < totalChunks; i++) {
        if (_audioChunks.containsKey(i)) {
          fullAudio.addAll(_audioChunks[i]!);
        }
      }
      _audioChunks.clear();
      _log('AUDIO', 'Clip #$clipId reconstructed (${fullAudio.length} bytes in $totalChunks chunks)');
      final resultBytes = Uint8List.fromList(fullAudio);
      if (_activeDownloadCompleter != null && !_activeDownloadCompleter!.isCompleted) {
        _activeDownloadCompleter!.complete(resultBytes);
      }
    }
    notifyListeners();
  }

  /// Request Xiao ESP32 to stream the audio file over high-throughput BLE GATT notifications
  Future<Uint8List?> streamClipOverGatt(int clipId) async {
    if (!isConnected) {
      _log('AUDIO', 'Cannot stream clip #$clipId: Not connected to BLE', isError: true);
      return null;
    }

    _activeDownloadClipId = clipId;
    _audioChunks.clear();
    _downloadStartTime = DateTime.now();
    _activeDownloadCompleter = Completer<Uint8List?>();

    _log('AUDIO', 'Requesting BLE stream for clip #$clipId...');
    await sendCommand(BleCommand.startL2capStream, clipId: clipId);

    try {
      final result = await _activeDownloadCompleter!.future.timeout(
        const Duration(seconds: 40),
        onTimeout: () {
          _log('AUDIO', 'Stream timeout for clip #$clipId', isError: true);
          return null;
        },
      );
      return result;
    } catch (e) {
      _log('AUDIO', 'Stream exception for clip #$clipId: $e', isError: true);
      return null;
    } finally {
      _activeDownloadCompleter = null;
      _downloadStartTime = null;
    }
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
      batteryVoltage: 4.15,
      batteryPercent: 95,
      isCharging: true,
      freeHeapBytes: 194560,
      usedStorageBytes: 420 * 1024,
      totalStorageBytes: 1966080,
      totalClips: 4,
      motionMagnitude: 0.98,
      accelX: 0.02,
      accelY: 0.05,
      accelZ: 0.98,
      tapCount: 0,
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
        batteryVoltage: 4.12 + (timer.tick % 5) * 0.01,
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
      case BleCommand.clearStorage:
        _telemetry = _telemetry.copyWith(usedStorageBytes: 0, totalClips: 0);
        _statusMessage = 'Flash Storage Cleared';
        _log('MOCK', 'Flash storage cleared');
        break;
      case BleCommand.startL2capStream:
        _telemetry = _telemetry.copyWith(state: DeviceState.transferring);
        _statusMessage = 'L2CAP Stream active';
        _log('MOCK', 'State -> TRANSFERRING (L2CAP CoC)');
        break;
      case BleCommand.connectHotspot:
        _telemetry = _telemetry.copyWith(state: DeviceState.transferring);
        _statusMessage = 'ESP32 connected to Phone Hotspot (Uploading clips)';
        _log('MOCK', 'State -> TRANSFERRING (ESP32 Upload via Phone Hotspot)');
        break;
      case BleCommand.deleteClip:
        final newCount = (_telemetry.totalClips > 0) ? _telemetry.totalClips - 1 : 0;
        _telemetry = _telemetry.copyWith(totalClips: newCount);
        _statusMessage = 'Clip deleted from storage';
        _log('MOCK', 'Clip deleted from storage (Remaining: $newCount)');
        break;
      case BleCommand.none:
        break;
    }
    notifyListeners();
  }
}

