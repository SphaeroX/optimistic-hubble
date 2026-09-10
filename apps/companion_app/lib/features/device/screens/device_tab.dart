import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../connection/services/ble_service.dart';
import '../../connection/widgets/device_scanner_sheet.dart';
import '../../debug_console/debug_log_sheet.dart';
import '../../recordings/models/recording_item.dart';
import '../../recordings/services/recording_sync_manager.dart';
import '../../recordings/widgets/clip_card.dart';
import '../../recordings/widgets/fast_transfer_sheet.dart';
import '../../recordings/widgets/sync_progress_banner.dart';
import '../../recordings/widgets/waveform_visualizer.dart';
import '../../telemetry/models/telemetry_state.dart';
import '../../telemetry/widgets/battery_gauge_card.dart';
import '../../telemetry/widgets/imu_motion_card.dart';
import '../../telemetry/widgets/memory_storage_card.dart';
import '../../telemetry/widgets/tap_history_list.dart';

/// Tab 4: Hardware companion dashboard for Seeed Studio XIAO ESP32-C3 with telemetry, auto-sync, and Wi-Fi Fast Transfer.
class DeviceTab extends StatefulWidget {
  final BleService bleService;
  final RecordingSyncManager syncManager;

  const DeviceTab({
    super.key,
    required this.bleService,
    required this.syncManager,
  });

  @override
  State<DeviceTab> createState() => _DeviceTabState();
}

class _DeviceTabState extends State<DeviceTab> {
  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await widget.syncManager.fetchDeviceClips(showError: true);
    } catch (e) {
      debugPrint('[DeviceTab] Refresh error: $e');
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }
  void _openDeviceScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DeviceScannerSheet(bleService: widget.bleService),
    );
    widget.bleService.startScan();
  }

  void _openDebugConsole() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DebugLogSheet(bleService: widget.bleService),
    );
  }

  void _openFastTransferSheet({int? targetClipId}) {
    if (!widget.syncManager.isSyncing) {
      widget.syncManager.resetFastTransferState();
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FastTransferSheet(
        bleService: widget.bleService,
        syncManager: widget.syncManager,
        targetClipId: targetClipId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.bleService, widget.syncManager]),
      builder: (context, _) {
        final isConnected = widget.bleService.isConnected;
        final devState = widget.bleService.telemetry.state;
        final isRecording = isConnected && devState == DeviceState.recording;
        final telem = widget.bleService.telemetry;

        final uiTelemetry = TelemetryState(
          hasRealData: isConnected && telem.hasRealData,
          batteryVoltage: telem.batteryVoltage,
          batteryPercent: telem.batteryPercent,
          isCharging: telem.isCharging,
          freeHeapBytes: telem.freeHeapBytes,
          totalHeapBytes: telem.totalHeapBytes ?? 327680,
          usedStorageBytes: telem.usedStorageBytes,
          totalStorageBytes: telem.totalStorageBytes ?? 16777216,
          accelX: telem.accelX,
          accelY: telem.accelY,
          accelZ: telem.accelZ,
          motionMagnitude: telem.motionMagnitude,
          tapCount: telem.tapCount,
          lastUpdated: telem.lastUpdated,
        );

        return Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Hardware Connection & Remote Record Header Card
              Card(
                color: isConnected
                    ? (isRecording ? AppTheme.accentRed.withAlpha(30) : AppTheme.cardDark)
                    : const Color(0xFF141D2B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: isConnected
                        ? (isRecording ? AppTheme.accentRed : AppTheme.primaryCyan)
                        : const Color(0xFF243248),
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (isRecording
                                      ? AppTheme.accentRed
                                      : (isConnected ? AppTheme.primaryCyan : AppTheme.textMuted))
                                  .withAlpha(40),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isRecording ? Icons.fiber_manual_record : Icons.sensors,
                              color: isRecording
                                  ? AppTheme.accentRed
                                  : (isConnected ? AppTheme.primaryCyan : AppTheme.textMuted),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isConnected ? 'XIAO ESP32-C3 Verbunden' : 'XIAO Nicht verbunden',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isConnected ? Colors.white : AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isConnected
                                      ? (isRecording
                                          ? '${Formatters.formatBytes(telem.totalAudioBytes)} aufgenommen @ 16kHz'
                                          : devState.description)
                                      : 'Kopple deine Hardware für drahtlose Audio-Synchronisation',
                                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isConnected)
                            ElevatedButton.icon(
                              onPressed: () {
                                if (isRecording) {
                                  widget.bleService.sendCommand(BleCommand.stopRecording);
                                } else {
                                  widget.bleService.sendCommand(BleCommand.startRecording);
                                }
                              },
                              icon: Icon(isRecording ? Icons.stop : Icons.mic, size: 18),
                              label: Text(isRecording ? 'Stop' : 'Aufnahme'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isRecording ? AppTheme.accentRed : AppTheme.primaryCyan,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                            )
                          else
                            ElevatedButton.icon(
                              onPressed: _openDeviceScanner,
                              icon: const Icon(Icons.bluetooth_searching, size: 16),
                              label: const Text('Koppeln'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryCyan,
                                foregroundColor: Colors.black,
                              ),
                            ),
                        ],
                      ),

                      if (isConnected) ...[
                        const SizedBox(height: 14),
                        WaveformVisualizer(
                          isActive: isRecording,
                          isRecording: isRecording,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Action Buttons Row: Wi-Fi Turbo Sync, Refresh & Debug Console
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isConnected && !widget.syncManager.isSyncing
                          ? () => _openFastTransferSheet()
                          : null,
                      icon: const Icon(Icons.bolt, size: 18, color: Colors.black),
                      label: const Text(
                        'Wi-Fi Fast Transfer',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryCyan,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: _isRefreshing ? null : _handleRefresh,
                    icon: _isRefreshing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryCyan),
                          )
                        : const Icon(Icons.refresh, color: AppTheme.primaryCyan, size: 20),
                    tooltip: 'Hardware & Telemetrie aktualisieren',
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: _openDebugConsole,
                    icon: const Icon(Icons.terminal, color: AppTheme.primaryCyan, size: 20),
                    tooltip: 'Hardware Debug Konsole',
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Progress Banner if active
              SyncProgressBanner(
                isSyncing: widget.syncManager.isSyncing,
                progress: widget.syncManager.syncProgress,
                currentFile: widget.syncManager.currentSyncFile,
                currentSpeed: widget.syncManager.currentSpeed,
              ),

              // Hardware Sync Preferences Card
              Card(
                color: AppTheme.cardDark,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF223046)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Automatisch synchronisieren beim Verbinden',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Lädt neue Hardware-Dateien bei BLE-Verbindung automatisch herunter',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                        value: widget.syncManager.autoSyncOnConnect,
                        activeThumbColor: AppTheme.primaryCyan,
                        onChanged: (val) => widget.syncManager.autoSyncOnConnect = val,
                      ),
                      const Divider(color: Color(0xFF1E2A3C), height: 1),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Nach Download vom Gerät löschen (Standard)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Gibt den Flash-Speicher des ESP32 automatisch wieder frei',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                        value: widget.syncManager.autoDeleteAfterSync,
                        activeThumbColor: AppTheme.primaryCyan,
                        onChanged: (val) => widget.syncManager.autoDeleteAfterSync = val,
                      ),
                      const Divider(color: Color(0xFF1E2A3C), height: 1),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Wi-Fi Turbo Hotspot (Standard)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        subtitle: const Text(
                          'Öffnet Handy-Hotspot für schnellen Upload (> 2.0 MB/s)',
                          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                        value: widget.syncManager.preferWifiFastTransfer,
                        activeThumbColor: AppTheme.primaryCyan,
                        onChanged: (val) => widget.syncManager.preferWifiFastTransfer = val,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Telemetry Grid
              BatteryGaugeCard(telemetry: uiTelemetry),
              const SizedBox(height: 14),
              ImuMotionCard(telemetry: uiTelemetry),
              const SizedBox(height: 14),
              TapHistoryList(
                tapHistory: widget.bleService.tapHistory,
                onSimulateTap: () => widget.bleService.triggerSimulatedTap(),
              ),
              const SizedBox(height: 14),
              MemoryStorageCard(telemetry: uiTelemetry),
              const SizedBox(height: 14),

              // Hardware Recordings List on ESP32 Flash
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Hardware Aufnahmen (${widget.syncManager.clips.length})',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  if (widget.syncManager.clips.any((c) => c.syncState != SyncState.synced))
                    TextButton.icon(
                      onPressed: widget.syncManager.isSyncing ? null : () => widget.syncManager.syncAllClips(),
                      icon: const Icon(Icons.download, size: 16, color: AppTheme.primaryCyan),
                      label: const Text('Alle laden', style: TextStyle(fontSize: 12, color: AppTheme.primaryCyan)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.syncManager.clips.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardDark,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF223046)),
                  ),
                  child: Center(
                    child: Text(
                      isConnected
                          ? 'Keine Aufnahmen im Flash-Speicher gefunden.\nNimm etwas auf oder tippe auf Aktualisieren.'
                          : 'Hardware nicht verbunden. Verbinde den XIAO ESP32, um Clips anzuzeigen.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                    ),
                  ),
                )
              else
                ...widget.syncManager.clips.map((clip) => ClipCard(
                  clip: clip,
                  isConnectedToMcu: isConnected,
                  onPlayToggle: () => widget.syncManager.togglePlayback(clip),
                  onDownload: () => _openFastTransferSheet(targetClipId: clip.id),
                  onShare: () => widget.syncManager.shareClip(clip),
                  onDeleteLocal: () => widget.syncManager.deleteClipLocally(clip.id),
                  onDeleteRemote: () => widget.syncManager.deleteClipOnDevice(clip.id),
                  onDeleteEverywhere: () => widget.syncManager.deleteClipEverywhere(clip.id),
                )),
              const SizedBox(height: 14),

              // Format Storage Button
              if (isConnected)
                ElevatedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('ESP32 Flash formatieren?'),
                        content: const Text('Alle auf dem Gerät gespeicherten Audio-Dateien werden unwiderruflich gelöscht.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
                            child: const Text('Formatieren'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      widget.bleService.sendCommand(BleCommand.clearStorage);
                      await widget.syncManager.clearDeviceStorage();
                    }
                  },
                  icon: const Icon(Icons.delete_forever, color: Colors.white),
                  label: const Text('ESP32 Flash-Speicher leeren', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentRed),
                ),
            ],
          ),
        );
      },
    );
  }
}
