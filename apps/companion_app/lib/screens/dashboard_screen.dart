import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../features/connection/services/ble_service.dart';
import '../features/connection/widgets/device_scanner_sheet.dart';
import '../features/debug_console/debug_log_sheet.dart';
import '../features/recordings/models/recording_item.dart';
import '../features/recordings/services/recording_sync_manager.dart';
import '../features/recordings/widgets/clip_card.dart';
import '../features/recordings/widgets/fast_transfer_sheet.dart';
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

  Future<void> _handleConnect() async {
    if (widget.bleService.autoConnectEnabled) {
      final success = await widget.bleService.autoConnectNearestXiao();
      if (!success && mounted && !widget.bleService.isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No Xiao ESP32 found in range.'),
            action: SnackBarAction(
              label: 'Manual Scan',
              onPressed: _openDeviceScanner,
            ),
          ),
        );
      }
    } else {
      _openDeviceScanner();
    }
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
  bool _isRefreshingInventory = false;

  Future<void> _handleRefreshInventory() async {
    if (_isRefreshingInventory) return;
    setState(() => _isRefreshingInventory = true);
    try {
      await widget.syncManager.fetchDeviceClips(showError: true);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              'Aufnahmen aktualisiert: ${widget.syncManager.clips.length} Clip(s) gefunden',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshingInventory = false);
      }
    }
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
            titleSpacing: 12,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: (isRecording
                            ? AppTheme.accentRed
                            : (isConnected ? AppTheme.primaryCyan : AppTheme.cardDark))
                        .withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isRecording ? Icons.fiber_manual_record : Icons.graphic_eq,
                    color: isRecording
                        ? AppTheme.accentRed
                        : (isConnected ? AppTheme.primaryCyan : AppTheme.textMuted),
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        AppConstants.appName,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        isConnected
                            ? (widget.bleService.connectedDevice?.name ?? 'Connected')
                            : (widget.bleService.isAutoConnecting
                                ? 'Searching nearest...'
                                : (widget.bleService.isConnecting
                                    ? 'Connecting...'
                                    : 'Disconnected')),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 11,
                          color: isConnected
                              ? AppTheme.accentGreen
                              : ((widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                                  ? AppTheme.accentOrange
                                  : AppTheme.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Plaud Note Style WiFi Fast Transfer Prompt
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                  avatar: const Icon(Icons.bolt, size: 14, color: Colors.black),
                  label: const Text(
                    'WiFi Fast Transfer',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: AppTheme.primaryCyan,
                  side: BorderSide.none,
                  onPressed: () => _openFastTransferSheet(),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.terminal, color: AppTheme.primaryCyan, size: 20),
                tooltip: 'Hardware Debug Console',
                onPressed: _openDebugConsole,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  avatar: (widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppTheme.accentOrange),
                        )
                      : Icon(
                          isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                          size: 14,
                          color: isConnected ? AppTheme.accentGreen : AppTheme.primaryCyan,
                        ),
                  label: Text(
                    isConnected
                      ? 'Connected'
                      : (widget.bleService.isAutoConnecting
                          ? 'Searching'
                          : (widget.bleService.isConnecting ? '...' : 'Connect')),
                    style: TextStyle(
                      fontSize: 11,
                      color: isConnected
                          ? AppTheme.accentGreen
                          : ((widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                              ? AppTheme.accentOrange
                              : AppTheme.primaryCyan),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: AppTheme.cardDark,
                  side: BorderSide(
                    color: isConnected
                        ? AppTheme.accentGreen
                        : ((widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                            ? AppTheme.accentOrange
                            : AppTheme.primaryCyan),
                  ),
                  onPressed: isConnected
                      ? () => widget.bleService.disconnect()
                      : ((widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                          ? null
                          : _handleConnect),
                ),
              ),
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
      padding: const EdgeInsets.all(16),
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
                        isRecording
                            ? Icons.fiber_manual_record
                            : (isConnected ? Icons.sensors : Icons.sensors_off),
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
                            isConnected ? devState.label : 'Device Offline',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isRecording ? AppTheme.accentRed : Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            !isConnected
                                ? (widget.bleService.isAutoConnecting
                                    ? 'Scanning for nearest Xiao device (RSSI proximity)...'
                                    : (widget.bleService.isConnecting
                                        ? 'Establishing connection to Xiao peripheral...'
                                        : 'Click "Connect" to automatically pair with nearest Xiao'))
                                : (isRecording
                                    ? '${Formatters.formatBytes(telem.totalAudioBytes)} captured @ 16kHz'
                                    : devState.description),
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: (widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                          ? null
                          : (!isConnected
                              ? _handleConnect
                              : () {
                                  if (isRecording) {
                                    widget.bleService.sendCommand(BleCommand.stopRecording);
                                  } else {
                                    widget.bleService.sendCommand(BleCommand.startRecording);
                                  }
                                }),
                      icon: (widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : Icon(!isConnected
                              ? Icons.bluetooth
                              : (isRecording ? Icons.stop : Icons.mic), size: 18),
                      label: Text(!isConnected
                          ? ((widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                              ? 'Connecting...'
                              : 'Connect')
                          : (isRecording ? 'Stop' : 'Record')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRecording ? AppTheme.accentRed : AppTheme.primaryCyan,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Live Waveform Visualizer
                WaveformVisualizer(
                  isActive: isRecording || isPlayingAudio,
                  isRecording: isRecording,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

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
    final isConnected = widget.bleService.isConnected;
    final syncedCount = clips.where((c) => c.syncState == SyncState.synced).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Sync Header Title & Badge
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recordings',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${clips.length} clip${clips.length == 1 ? '' : 's'} on device / local',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E3E58)),
              ),
              child: Text(
                '$syncedCount/${clips.length} Synced',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryCyan,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Action Buttons Row
        Row(
          children: [
            Expanded(
              flex: 3,
              child: ElevatedButton.icon(
                onPressed: isSyncing ? null : () => _openFastTransferSheet(),
                icon: const Icon(Icons.bolt, size: 18, color: Colors.black),
                label: const Text(
                  'WiFi Fast Transfer',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryCyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: OutlinedButton.icon(
                onPressed: isSyncing ? null : () => widget.syncManager.syncAllClips(),
                icon: const Icon(Icons.bluetooth_audio, size: 16),
                label: const Text('BLE Sync', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryCyan,
                  side: const BorderSide(color: AppTheme.primaryCyan),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              onPressed: () => widget.syncManager.fetchDeviceClips(showError: true),
              icon: const Icon(Icons.refresh, size: 18, color: AppTheme.primaryCyan),
              tooltip: 'Refresh Inventory',
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 2-Stage Plaud Note Architecture Status Card
        Card(
          color: isConnected ? AppTheme.cardDark : const Color(0xFF131B2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF243248)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isConnected ? Icons.cloud_sync : Icons.cloud_off,
                  color: isConnected ? AppTheme.accentGreen : AppTheme.textMuted,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isConnected ? '2-Stage Sync Active (Plaud Note Model)' : 'Device Offline',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isConnected ? Colors.white : AppTheme.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isConnected
                            ? 'Stage 1: BLE Auto-Sync (<5mA) • Stage 2: Wi-Fi Fast Transfer (~2.4 MB/s)'
                            : 'Connect via BLE to enable auto-sync and high-speed Wi-Fi transfer',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

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
                const Icon(Icons.info_outline, color: AppTheme.accentRed, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    errorMsg,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                  onPressed: () => widget.syncManager.fetchDeviceClips(showError: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
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
            padding: const EdgeInsets.symmetric(vertical: 50),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.mic_none, size: 48, color: AppTheme.textMuted),
                  SizedBox(height: 12),
                  Text(
                    'No recordings stored yet.\n\n• Tap board or click "Record" to record audio\n• 2-Stage Sync: Silent BLE + On-Demand Wi-Fi Fast Transfer',
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
                isConnectedToMcu: isConnected,
                onPlayToggle: () => widget.syncManager.togglePlayback(clip),
                onDownload: () {
                  if (clip.isFastTransferRecommended) {
                    _openFastTransferSheet(targetClipId: clip.id);
                  } else {
                    widget.syncManager.downloadClip(clip.id);
                  }
                },
                onDeleteLocal: () => widget.syncManager.deleteClipLocally(clip.id),
                onDeleteRemote: () => widget.syncManager.deleteClipOnDevice(clip.id),
                onDeleteEverywhere: () => widget.syncManager.deleteClipEverywhere(clip.id),
              )),
      ],
    );
  }
}
