import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/connection/services/ble_connection_service.dart';
import 'features/recordings/services/audio_sync_service.dart';
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
  late final BleConnectionService _bleService;
  late final AudioSyncService _syncService;

  @override
  void initState() {
    super.initState();
    _bleService = BleConnectionService();
    _syncService = AudioSyncService();
  }

  @override
  void dispose() {
    _bleService.dispose();
    _syncService.dispose();
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
        syncService: _syncService,
      ),
    );
  }
}
