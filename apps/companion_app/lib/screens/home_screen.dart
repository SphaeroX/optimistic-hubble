import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../features/ai_gemini/services/gemini_service.dart';
import '../features/connection/services/ble_service.dart';
import '../features/connection/widgets/device_scanner_sheet.dart';
import '../features/debug_console/debug_log_sheet.dart';
import '../features/device/screens/device_tab.dart';
import '../features/groups/screens/groups_tab.dart';
import '../features/groups/services/groups_repository.dart';
import '../features/recorder/controllers/recorder_controller.dart';
import '../features/recorder/screens/recorder_tab.dart';
import '../features/recordings/screens/recordings_tab.dart';
import '../features/recordings/services/recording_sync_manager.dart';
import '../features/recordings/services/recordings_repository.dart';
import '../features/settings/screens/settings_screen.dart';

/// Root HomeScreen of Dictula with 4-tab navigation and top AppBar actions.
class HomeScreen extends StatefulWidget {
  final BleService bleService;
  final RecordingSyncManager syncManager;
  final RecordingsRepository recordingsRepository;
  final GroupsRepository groupsRepository;
  final GeminiService geminiService;
  final RecorderController recorderController;

  const HomeScreen({
    super.key,
    required this.bleService,
    required this.syncManager,
    required this.recordingsRepository,
    required this.groupsRepository,
    required this.geminiService,
    required this.recorderController,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
            content: const Text('Kein Gerät in Reichweite gefunden.'),
            action: SnackBarAction(label: 'Manueller Scan', onPressed: _openDeviceScanner),
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

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          geminiService: widget.geminiService,
          bleService: widget.bleService,
          syncManager: widget.syncManager,
          recorderController: widget.recorderController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 750;

    return AnimatedBuilder(
      animation: Listenable.merge([widget.bleService, widget.recorderController]),
      builder: (context, _) {
        final isConnected = widget.bleService.isConnected;
        final devState = widget.bleService.telemetry.state;
        final isHwRecording = isConnected && devState == DeviceState.recording;
        final isPhoneRecording = widget.recorderController.recorderService.isRecording;
        final isAnyRecording = isHwRecording || isPhoneRecording;

        return Scaffold(
          appBar: AppBar(
            titleSpacing: 12,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: (isAnyRecording
                            ? AppTheme.accentRed
                            : (isConnected ? AppTheme.primaryCyan : AppTheme.cardDark))
                        .withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isAnyRecording ? Icons.fiber_manual_record : Icons.graphic_eq,
                    color: isAnyRecording
                        ? AppTheme.accentRed
                        : (isConnected ? AppTheme.primaryCyan : AppTheme.textMuted),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  AppConstants.appName,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ],
            ),
            actions: [
              // Hardware Quick Connect Chip
              ActionChip(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                avatar: (widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentOrange),
                      )
                    : Icon(
                        isConnected ? Icons.bluetooth_connected : Icons.bluetooth_searching,
                        size: 14,
                        color: isConnected ? AppTheme.accentGreen : AppTheme.primaryCyan,
                      ),
                label: Text(
                  isConnected
                      ? 'ESP32'
                      : (widget.bleService.isAutoConnecting
                          ? 'Suche...'
                          : (widget.bleService.isConnecting ? '...' : 'ESP32')),
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
                          : const Color(0xFF2B3D56)),
                ),
                onPressed: isConnected
                    ? () => widget.bleService.disconnect()
                    : ((widget.bleService.isConnecting || widget.bleService.isAutoConnecting)
                        ? null
                        : _handleConnect),
              ),
              const SizedBox(width: 4),

              // Debug Console Button
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.terminal, color: AppTheme.primaryCyan, size: 20),
                tooltip: 'Hardware Debug Konsole',
                onPressed: _openDebugConsole,
              ),

              // Settings Gear Button
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
                  tooltip: 'Einstellungen & Gemini Key',
                  onPressed: _openSettings,
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
                      icon: Icon(Icons.mic_none),
                      selectedIcon: Icon(Icons.mic),
                      label: Text('Recorder'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.audiotrack_outlined),
                      selectedIcon: Icon(Icons.audiotrack),
                      label: Text('Aufnahmen'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder),
                      label: Text('Gruppen'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.memory_outlined),
                      selectedIcon: Icon(Icons.memory),
                      label: Text('Device'),
                    ),
                  ],
                ),
              Expanded(
                child: IndexedStack(
                  index: _currentTabIndex,
                  children: [
                    // Tab 0: Recorder
                    RecorderTab(
                      controller: widget.recorderController,
                      groupsRepository: widget.groupsRepository,
                    ),

                    // Tab 1: Aufnahmen
                    RecordingsTab(
                      repository: widget.recordingsRepository,
                      groupsRepository: widget.groupsRepository,
                      geminiService: widget.geminiService,
                      audioPlayer: widget.syncManager.audioPlayer,
                      syncManager: widget.syncManager,
                      bleService: widget.bleService,
                      recorderController: widget.recorderController,
                      onSwitchToRecorderTab: () => setState(() => _currentTabIndex = 0),
                    ),

                    // Tab 2: Gruppen
                    GroupsTab(
                      groupsRepository: widget.groupsRepository,
                      recordingsRepository: widget.recordingsRepository,
                      geminiService: widget.geminiService,
                      recorderController: widget.recorderController,
                      onSwitchToRecorderTab: () => setState(() => _currentTabIndex = 0),
                    ),

                    // Tab 3: Device
                    DeviceTab(
                      bleService: widget.bleService,
                      syncManager: widget.syncManager,
                    ),
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
                      icon: Icon(Icons.mic_none),
                      selectedIcon: Icon(Icons.mic),
                      label: 'Recorder',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.audiotrack_outlined),
                      selectedIcon: Icon(Icons.audiotrack),
                      label: 'Aufnahmen',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder),
                      label: 'Gruppen',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.memory_outlined),
                      selectedIcon: Icon(Icons.memory),
                      label: 'Device',
                    ),
                  ],
                ),
        );
      },
    );
  }
}
