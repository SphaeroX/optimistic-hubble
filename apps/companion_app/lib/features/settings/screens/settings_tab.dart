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
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Plaud Note 2-Stage Sync Architecture Overview
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bolt, color: AppTheme.primaryCyan, size: 22),
                    SizedBox(width: 8),
                    Text(
                      '2-Stage Sync Architecture (Plaud Note Model)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Optimized two-stage data transfer designed for battery efficiency and high-speed audio synchronization:',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                _buildSyncTierRow(
                  icon: Icons.bluetooth_audio,
                  color: AppTheme.primaryCyan,
                  title: 'Stage 1: BLE 5.0 Auto-Sync (<5 mA)',
                  desc: 'Permanent low-energy connection. Telemetry (10 Hz), remote commands, and silent auto-sync of small clips (< 500 KB).',
                ),
                const SizedBox(height: 10),
                _buildSyncTierRow(
                  icon: Icons.wifi_tethering,
                  color: AppTheme.accentOrange,
                  title: 'Stage 2: WiFi Fast Transfer (> 2.0 MB/s)',
                  desc: 'On-demand high-speed SoftAP transfer (~10-20x faster than BLE). 5-phase handshake state machine with RFC 7233 Range resume.',
                ),
                const SizedBox(height: 10),
                _buildSyncTierRow(
                  icon: Icons.verified_user,
                  color: AppTheme.accentPurple,
                  title: 'Data Integrity & CRC32 Verification',
                  desc: 'Every audio frame and completed WAV file is CRC32 verified before saving to local disk.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Fast Transfer Options & Preferences
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune, color: AppTheme.primaryCyan, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Fast Transfer Preferences',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-Delete after Sync', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Automatically delete audio clips from ESP32 flash memory once downloaded and verified locally (Plaud style).',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  value: widget.syncManager.autoDeleteAfterSync,
                  activeThumbColor: AppTheme.primaryCyan,
                  onChanged: (val) {
                    setState(() {
                      widget.syncManager.autoDeleteAfterSync = val;
                    });
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
                      onPressed: () => widget.bleService.sendCommand(BleCommand.enterSleep),
                      icon: const Icon(Icons.bedtime),
                      label: const Text('Deep Sleep (<10µA)'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
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
                          widget.bleService.sendCommand(BleCommand.clearStorage);
                          await widget.syncManager.clearDeviceStorage();
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Flash format command sent successfully.')),
                            );
                          }
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
                  'Downloaded recordings are automatically validated (CRC32) and stored as standard Linear 16-bit PCM WAV files in your local documents directory.',
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
                      'System & Protocol Specs',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow('Target MCU', 'Seeed Studio XIAO ESP32-C3 (RISC-V 160MHz)'),
                _buildInfoRow('Sync Architecture', '2-Stage Plaud Note Hybrid (BLE 5.0 + Wi-Fi SoftAP)'),
                _buildInfoRow('Stage 1 (BLE 5.0)', 'GATT / L2CAP CoC Auto-Sync (<5 mA)'),
                _buildInfoRow('Stage 2 (Wi-Fi Fast)', 'SoftAP 802.11 b/g/n (>2.0 MB/s Turbo HTTP)'),
                _buildInfoRow('Handshake Protocol', '5-Phase State Machine (NONE->CONN->HS->READY->XFER)'),
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

  Widget _buildSyncTierRow({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(desc, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ],
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
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
