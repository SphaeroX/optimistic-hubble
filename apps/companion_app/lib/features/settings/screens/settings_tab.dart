import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

        // Bluetooth & Auto-Connect Preferences
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bluetooth_searching, color: AppTheme.primaryCyan, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Bluetooth & Auto-Connect',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Auto-Connect Nearest Device (RSSI)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'When tapping "Connect", automatically pair with the closest Xiao ESP32 with the strongest radio signal, bypassing manual device selection.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  value: widget.bleService.autoConnectEnabled,
                  activeThumbColor: AppTheme.primaryCyan,
                  onChanged: (val) {
                    setState(() {
                      widget.bleService.autoConnectEnabled = val;
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        widget.bleService.autoConnectNearestXiao();
                      },
                      icon: const Icon(Icons.flash_on, size: 16),
                      label: const Text('Test Auto-Connect', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryCyan,
                        side: const BorderSide(color: AppTheme.primaryCyan),
                      ),
                    ),
                  ],
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
                      'Local Storage',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Downloaded recordings are automatically converted to standard Linear 16-bit PCM WAV files (16 kHz Mono) and stored in your device storage:',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FutureBuilder<String>(
                  future: LocalStorageManager.getRecordingsDirectoryPath(),
                  builder: (context, snapshot) {
                    final path = snapshot.data ?? 'Loading path...';
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F1522),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF243248)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.folder_open, size: 18, color: AppTheme.primaryCyan),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SelectableText(
                              path,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 16, color: AppTheme.primaryCyan),
                            tooltip: 'Pfad kopieren',
                            onPressed: snapshot.hasData
                                ? () {
                                    Clipboard.setData(ClipboardData(text: path));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        duration: Duration(seconds: 2),
                                        content: Text('Speicherpfad in Zwischenablage kopiert!'),
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ],
                      ),
                    );
                  },
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
      ],
    );
  }
}
