import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../features/connection/services/ble_connection_service.dart';
import '../features/connection/widgets/device_scanner_sheet.dart';
import '../features/recordings/services/audio_sync_service.dart';
import '../features/recordings/widgets/clip_list_item.dart';
import '../features/recordings/widgets/sync_progress_banner.dart';
import '../features/settings/screens/settings_tab.dart';
import '../features/telemetry/models/telemetry_state.dart';
import '../features/telemetry/widgets/battery_gauge_card.dart';
import '../features/telemetry/widgets/imu_motion_card.dart';
import '../features/telemetry/widgets/memory_storage_card.dart';

class DashboardScreen extends StatefulWidget {
  final BleConnectionService bleService;
  final AudioSyncService syncService;

  const DashboardScreen({
    super.key,
    required this.bleService,
    required this.syncService,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentTabIndex = 0;
  late TelemetryState _telemetryState;

  @override
  void initState() {
    super.initState();
    _telemetryState = TelemetryState.initial();
    widget.syncService.fetchDeviceClips();

    widget.bleService.addListener(_onBleServiceUpdate);
  }

  @override
  void dispose() {
    widget.bleService.removeListener(_onBleServiceUpdate);
    super.dispose();
  }

  void _onBleServiceUpdate() {
    setState(() {
      _telemetryState = _telemetryState.copyWith(
        tapCount: widget.bleService.tapCount,
      );
    });
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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 750;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primaryCyan.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.graphic_eq, color: AppTheme.primaryCyan, size: 20),
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
                  widget.bleService.isConnected
                      ? (widget.bleService.connectedDevice?.name ?? 'Connected')
                      : 'Disconnected',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.bleService.isConnected ? AppTheme.accentGreen : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Connection Status Pill
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: ActionChip(
              avatar: Icon(
                widget.bleService.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                size: 16,
                color: widget.bleService.isConnected ? AppTheme.accentGreen : AppTheme.primaryCyan,
              ),
              label: Text(
                widget.bleService.isConnected ? 'Connected' : 'Scan BLE',
                style: TextStyle(
                  color: widget.bleService.isConnected ? AppTheme.accentGreen : AppTheme.primaryCyan,
                  fontWeight: FontWeight.bold,
                ),
              ),
              backgroundColor: AppTheme.cardDark,
              side: BorderSide(
                color: widget.bleService.isConnected ? AppTheme.accentGreen : AppTheme.primaryCyan,
              ),
              onPressed: widget.bleService.isConnected
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
                _buildLiveMonitorTab(),
                _buildRecordingsTab(),
                SettingsTab(bleService: widget.bleService, syncService: widget.syncService),
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
  }

  Widget _buildLiveMonitorTab() {
    final devState = widget.bleService.deviceState;
    final isRecording = devState == DeviceState.recording;

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
            child: Row(
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
                        devState.description,
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
          ),
        ),
        const SizedBox(height: 16),

        // Telemetry Grid / Cards
        BatteryGaugeCard(telemetry: _telemetryState),
        const SizedBox(height: 14),
        ImuMotionCard(telemetry: _telemetryState),
        const SizedBox(height: 14),
        MemoryStorageCard(telemetry: _telemetryState),
      ],
    );
  }

  Widget _buildRecordingsTab() {
    return AnimatedBuilder(
      animation: widget.syncService,
      builder: (context, _) {
        final clips = widget.syncService.clips;
        final isSyncing = widget.syncService.isSyncing;

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
                  onPressed: isSyncing ? null : () => widget.syncService.syncAllClips(),
                  icon: const Icon(Icons.sync),
                  label: const Text('Wi-Fi Fast Sync'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress Banner
            SyncProgressBanner(
              isSyncing: isSyncing,
              progress: widget.syncService.syncProgress,
              currentFile: widget.syncService.currentSyncFile,
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
              ...List.generate(clips.length, (i) {
                return ClipListItem(
                  clip: clips[i],
                  onPlayToggle: () => widget.syncService.togglePlayback(i),
                );
              }),
          ],
        );
      },
    );
  }
}
