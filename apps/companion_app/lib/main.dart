import 'package:flutter/material.dart';
import 'core/audio/native_audio_player.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/connection/services/ble_service.dart';
import 'features/recordings/services/recording_sync_manager.dart';
import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XiaoCompanionApp());
}

class XiaoCompanionApp extends StatefulWidget {
  const XiaoCompanionApp({super.key});

  @override
  State<XiaoCompanionApp> createState() => _XiaoCompanionAppState();
}

class _XiaoCompanionAppState extends State<XiaoCompanionApp> {
  late final BleService _bleService;
  late final NativeAudioPlayer _audioPlayer;
  late final RecordingSyncManager _syncManager;

  @override
  void initState() {
    super.initState();
    _bleService = BleService();
    _audioPlayer = NativeAudioPlayer();
    _syncManager = RecordingSyncManager(
      audioPlayer: _audioPlayer,
      bleService: _bleService,
    );
  }

  @override
  void dispose() {
    _bleService.dispose();
    _syncManager.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      home: DashboardScreen(
        bleService: _bleService,
        syncManager: _syncManager,
      ),
    );
  }
}
