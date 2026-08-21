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
        final isRecording = isConnected && devState == DeviceState.recording;
        final isPlayingAudio = widget.syncManager.audioPlayer.isPlaying;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isRecording ? AppTheme.accentRed : (isConnected ? AppTheme.primaryCyan : AppTheme.cardDark)).withAlpha(50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isRecording ? Icons.fiber_manual_record : Icons.graphic_eq,
                    color: isRecording ? AppTheme.accentRed : (isConnected ? AppTheme.primaryCyan : AppTheme.textMuted),
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
                          : (widget.bleService.isConnecting ? 'Connecting...' : 'Disconnected (No Device)'),
                      style: TextStyle(
                        fontSize: 11,
                        color: isConnected
                            ? AppTheme.accentGreen
                            : (widget.bleService.isConnecting ? AppTheme.accentOrange : AppTheme.textMuted),
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
                  avatar: widget.bleService.isConnecting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentOrange),
                        )
                      : Icon(
                          isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                          size: 16,
                          color: isConnected ? AppTheme.accentGreen : AppTheme.primaryCyan,
                        ),
                  label: Text(
                    isConnected ? 'Connected' : (widget.bleService.isConnecting ? 'Connecting...' : 'Scan BLE'),
                    style: TextStyle(
                      color: isConnected
                          ? AppTheme.accentGreen
                          : (widget.bleService.isConnecting ? AppTheme.accentOrange : AppTheme.primaryCyan),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: AppTheme.cardDark,
                  side: BorderSide(
                    color: isConnected
                        ? AppTheme.accentGreen
                        : (widget.bleService.isConnecting ? AppTheme.accentOrange : AppTheme.primaryCyan),
                  ),
                  onPressed: isConnected
                      ? () => widget.bleService.disconnect()
                      : (widget.bleService.isConnecting ? null : _openDeviceScanner),
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
                    _buildLiveMonitorTab(isConnected, isRecording, isPlayingAudio),
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

  Widget _buildLiveMonitorTab(bool isConnected, bool isRecording, bool isPlayingAudio) {
    final devState = widget.bleService.telemetry.state;
    final telem = widget.bleService.telemetry;

    final uiTelemetry = TelemetryState(
      hasRealData: isConnected && telem.hasRealData,
      batteryVoltage: telem.batteryVoltage,
      batteryPercent: telem.batteryPercent,
      isCharging: telem.isCharging,
      freeHeapBytes: telem.freeHeapBytes,
      totalHeapBytes: telem.totalHeapBytes ?? 327680,
      usedStorageBytes: telem.usedStorageBytes,
      totalStorageBytes: telem.totalStorageBytes ?? 1966080,
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
                        color: (isRecording ? AppTheme.accentRed : (isConnected ? AppTheme.primaryCyan : AppTheme.textMuted)).withAlpha(40),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isRecording ? Icons.fiber_manual_record : (isConnected ? Icons.sensors : Icons.sensors_off),
                        color: isRecording ? AppTheme.accentRed : (isConnected ? AppTheme.primaryCyan : AppTheme.textMuted),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected ? devState.label : 'Device Offline',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isRecording ? AppTheme.accentRed : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            !isConnected
                                ? 'Click "Scan BLE" in the top right to connect your XIAO ESP32-C3'
                                : (isRecording
                                    ? 'Recording active: ${Formatters.formatBytes(telem.totalAudioBytes)} captured @ 16kHz'
                                    : devState.description),
                            style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: !isConnected
                          ? _openDeviceScanner
                          : () {
                              if (isRecording) {
                                widget.bleService.sendCommand(BleCommand.stopRecording);
                              } else {
                                widget.bleService.sendCommand(BleCommand.startRecording);
                              }
                            },
                      icon: Icon(!isConnected ? Icons.bluetooth : (isRecording ? Icons.stop : Icons.mic)),
                      label: Text(!isConnected ? 'Connect' : (isRecording ? 'Stop' : 'Record')),
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
    final errorMsg = widget.syncManager.errorMessage;

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
                  'Recordings (Adaptive Sync)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${clips.length} recordings available locally / on device',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                ),
              ],
            ),
            ElevatedButton.icon(
              onPressed: isSyncing ? null : () => widget.syncManager.syncAllClips(),
              icon: const Icon(Icons.sync),
              label: const Text('Adaptive Sync All'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Error message banner if any
        if (errorMsg != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.accentRed.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accentRed),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off, color: AppTheme.accentRed, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    errorMsg,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Progress Banner
        SyncProgressBanner(
          isSyncing: isSyncing,
          progress: widget.syncManager.syncProgress,
          currentFile: widget.syncManager.currentSyncFile,
          currentSpeed: widget.syncManager.currentSpeed,
        ),

        // Clips List
        if (clips.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.mic_none, size: 48, color: AppTheme.textMuted),
                  SizedBox(height: 12),
                  Text(
                    'No recordings stored yet.\n\n• Tier 1: Silent BLE 5.0 sync for clips < 2.0 MB\n• Tier 2: Wi-Fi Turbo (>1.8 MB/s) with Range Resume for clips ≥ 2.0 MB',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  ),
                ],
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
