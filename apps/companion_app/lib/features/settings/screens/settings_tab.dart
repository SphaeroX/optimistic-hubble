import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/storage_manager.dart';
import '../../connection/services/ble_service.dart';
import '../../recordings/services/recording_sync_manager.dart';

class SettingsTab extends StatefulWidget {
  final BleService bleService;
  final RecordingSyncManager syncManager;

  const SettingsTab({
    super.key,
    required this.bleService,
    required this.syncManager,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late final TextEditingController _ssidController;
  late final TextEditingController _passController;
  late final TextEditingController _ipController;

  @override
  void initState() {
    super.initState();
    _ssidController = TextEditingController(text: AppConstants.defaultApSsid);
    _passController = TextEditingController(text: AppConstants.defaultApPassword);
    _ipController = TextEditingController(text: widget.syncManager.deviceIp);
  }

  @override
  void dispose() {
    _ssidController.dispose();
    _passController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Wi-Fi SoftAP Sync Config
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.wifi, color: AppTheme.primaryCyan, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Wi-Fi SoftAP Sync Config',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _ssidController,
                  decoration: const InputDecoration(
                    labelText: 'Hotspot SSID',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.router),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'WPA2 Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'Device IP Address (Gateway)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.network_ping),
                  ),
                  onChanged: (val) {
                    widget.syncManager.updateEndpoint(val.trim(), AppConstants.defaultHttpPort);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Device Remote Control
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.settings_remote, color: AppTheme.primaryCyan, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'ESP32 Remote Controls (BLE)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => widget.bleService.sendCommand(BleCommand.startWifi),
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Start SoftAP Server'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.bleService.sendCommand(BleCommand.stopWifi),
                      icon: const Icon(Icons.wifi_off),
                      label: const Text('Stop SoftAP'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => widget.bleService.sendCommand(BleCommand.enterSleep),
                      icon: const Icon(Icons.bedtime),
                      label: const Text('Deep Sleep (<10µA)'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Clear Storage?'),
                            content: const Text('This will erase all recorded ADPCM audio clips from LittleFS flash.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
                                child: const Text('Erase All'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          await widget.syncManager.clearDeviceStorage();
                        }
                      },
                      icon: const Icon(Icons.delete_forever, color: Colors.white),
                      label: const Text('Format Flash Memory', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Local Storage Folder
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder, color: AppTheme.primaryCyan, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Local Storage & Recordings',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Downloaded recordings are automatically converted to standard Linear 16-bit PCM WAV and stored in your Documents directory.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () => LocalStorageManager.openInFileManager(),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open Local Recordings Folder'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // About & System Info
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.primaryCyan, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'System & Hardware Specs',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Target MCU', 'Seeed Studio XIAO ESP32-C3 (RISC-V 160MHz)'),
                _buildInfoRow('Audio Codec', '16 kHz IMA-ADPCM 4-bit Mono (8 KB/s)'),
                _buildInfoRow('Microphone', 'I2S Stereo/Mono Digital MEMS'),
                _buildInfoRow('IMU Sensor', 'LSM6DS3 / BMI160 6-Axis + Tap Detector'),
                _buildInfoRow('Storage FileSystem', 'LittleFS (Partition: no_ota.csv ~1.9MB)'),
                _buildInfoRow('App Version', '${AppConstants.appName} v${AppConstants.appVersion}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
