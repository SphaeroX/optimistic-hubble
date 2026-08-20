import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../features/connection/services/ble_service.dart';
import '../features/connection/widgets/device_scanner_sheet.dart';
import '../features/debug_console/debug_log_sheet.dart';
import '../features/recordings/services/recording_sync_manager.dart';
import '../features/recordings/widgets/clip_card.dart';
import '../features/recordings/widgets/sync_progress_banner.dart';
import '../features/recordings/widgets/waveform_visualizer.dart';
import '../features/settings/screens/settings_tab.dart';
import '../features/telemetry/models/telemetry_state.dart';
import '../features/telemetry/widgets/battery_gauge_card.dart';
import '../features/telemetry/widgets/imu_motion_card.dart';
import '../features/telemetry/widgets/memory_storage_card.dart';
import '../features/telemetry/widgets/tap_history_list.dart';

class DashboardScreen extends StatefulWidget {
  final BleService bleService;
  final RecordingSyncManager syncManager;

  const DashboardScreen({
    super.key,
    required this.bleService,
    required this.syncManager,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentTabIndex = 0;

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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 750;

    return AnimatedBuilder(
      animation: Listenable.merge([widget.bleService, widget.syncManager]),
      builder: (context, _) {
        final isConnected = widget.bleService.isConnected;
        final devState = widget.bleService.telemetry.state;
        final isRecording = devState == DeviceState.recording;
        final isPlayingAudio = widget.syncManager.audioPlayer.isPlaying;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isRecording ? AppTheme.accentRed : AppTheme.primaryCyan).withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isRecording ? Icons.fiber_manual_record : Icons.graphic_eq,
                    color: isRecording ? AppTheme.accentRed : AppTheme.primaryCyan,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      AppConstants.appName,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      isConnected
                          ? (widget.bleService.connectedDevice?.name ?? 'Connected')
                          : 'Disconnected',
                      style: TextStyle(
                        fontSize: 11,
                        color: isConnected ? AppTheme.accentGreen : AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              // Debug Console Button
              IconButton(
                icon: const Icon(Icons.terminal, color: AppTheme.primaryCyan),
                tooltip: 'Hardware Debug Console',
                onPressed: _openDebugConsole,
              ),

              // Connection Status Action Chip
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: ActionChip(
                  avatar: Icon(
                    isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                    size: 16,
                    color: isConnected ? AppTheme.accentGreen : AppTheme.primaryCyan,
                  ),
                  label: Text(
                    isConnected ? 'Connected' : 'Scan BLE',
                    style: TextStyle(
                      color: isConnected ? AppTheme.accentGreen : AppTheme.primaryCyan,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: AppTheme.cardDark,
                  side: BorderSide(
                    color: isConnected ? AppTheme.accentGreen : AppTheme.primaryCyan,
                  ),
                  onPressed: isConnected
                      ? () => widget.bleService.disconnect()
                      : _openDeviceScanner,
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Row(
            children: [
              if (isDesktop)
                NavigationRail(
                  selectedIndex: _currentTabIndex,
                  onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Monitor'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.audiotrack_outlined),
                      selectedIcon: Icon(Icons.audiotrack),
                      label: Text('Recordings'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: Text('Settings'),
                    ),
                  ],
                ),
              Expanded(
                child: IndexedStack(
                  index: _currentTabIndex,
                  children: [
                    _buildLiveMonitorTab(isRecording, isPlayingAudio),
                    _buildRecordingsTab(),
                    SettingsTab(bleService: widget.bleService, syncManager: widget.syncManager),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: isDesktop
              ? null
              : NavigationBar(
                  selectedIndex: _currentTabIndex,
                  onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Monitor',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.audiotrack_outlined),
                      selectedIcon: Icon(Icons.audiotrack),
                      label: 'Recordings',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.tune_outlined),
                      selectedIcon: Icon(Icons.tune),
                      label: 'Settings',
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildLiveMonitorTab(bool isRecording, bool isPlayingAudio) {
    final devState = widget.bleService.telemetry.state;
    final telem = widget.bleService.telemetry;

    // Convert to TelemetryState for existing widget compatibility
    final uiTelemetry = TelemetryState(
      batteryVoltage: telem.batteryVoltage,
      batteryPercent: telem.batteryPercent,
      isCharging: telem.isCharging,
      freeHeapBytes: telem.freeHeapBytes,
      totalHeapBytes: telem.totalHeapBytes,
      usedStorageBytes: telem.usedStorageBytes,
      totalStorageBytes: telem.totalStorageBytes,
      accelX: telem.accelX,
      accelY: telem.accelY,
      accelZ: telem.accelZ,
      motionMagnitude: telem.motionMagnitude,
      tapCount: telem.tapCount,
      lastUpdated: telem.lastUpdated,
    );

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Real-Time Hardware Status Banner
        Card(
          color: isRecording ? AppTheme.accentRed.withAlpha(30) : AppTheme.cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isRecording ? AppTheme.accentRed : const Color(0xFF243248),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (isRecording ? AppTheme.accentRed : AppTheme.primaryCyan).withAlpha(40),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isRecording ? Icons.fiber_manual_record : Icons.sensors,
                        color: isRecording ? AppTheme.accentRed : AppTheme.primaryCyan,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            devState.label,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isRecording ? AppTheme.accentRed : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isRecording
                                ? 'Recording: ${Formatters.formatBytes(telem.totalAudioBytes)} captured @ 16kHz'
                                : devState.description,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        if (isRecording) {
                          widget.bleService.sendCommand(BleCommand.stopRecording);
                        } else {
                          widget.bleService.sendCommand(BleCommand.startRecording);
                        }
                      },
                      icon: Icon(isRecording ? Icons.stop : Icons.mic),
                      label: Text(isRecording ? 'Stop' : 'Record'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRecording ? AppTheme.accentRed : AppTheme.primaryCyan,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Live Waveform Visualizer
                WaveformVisualizer(
                  isActive: isRecording || isPlayingAudio,
                  isRecording: isRecording,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Telemetry Grid / Cards
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
      ],
    );
  }

  Widget _buildRecordingsTab() {
    final clips = widget.syncManager.clips;
    final isSyncing = widget.syncManager.isSyncing;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Sync Header & Trigger
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Audio Clips on Device',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${clips.length} recordings stored in LittleFS Flash',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: isSyncing ? null : () => widget.syncManager.syncAllClips(),
              icon: const Icon(Icons.sync),
              label: const Text('Wi-Fi Fast Sync'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Progress Banner
        SyncProgressBanner(
          isSyncing: isSyncing,
          progress: widget.syncManager.syncProgress,
          currentFile: widget.syncManager.currentSyncFile,
        ),

        // Clips List
        if (clips.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: const Center(
              child: Text(
                'No recordings yet.\nTap "Record" or double-tap the XIAO sensor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textMuted),
              ),
            ),
          )
        else
          ...clips.map((clip) => ClipCard(
                clip: clip,
                onPlayToggle: () => widget.syncManager.togglePlayback(clip),
                onDownload: () => widget.syncManager.downloadClip(clip.id),
              )),
      ],
    );
  }
}
