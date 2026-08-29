import 'package:flutter/material.dart';
import 'core/audio/audio_recorder_service.dart';
import 'core/audio/native_audio_player.dart';
import 'core/constants/app_constants.dart';
import 'core/services/permission_service.dart';
import 'core/theme/app_theme.dart';
import 'features/ai_gemini/services/gemini_service.dart';
import 'features/connection/services/ble_service.dart';
import 'features/groups/services/groups_repository.dart';
import 'features/recorder/controllers/recorder_controller.dart';
import 'features/recordings/services/recording_sync_manager.dart';
import 'features/recordings/services/recordings_repository.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DictulaApp());
}

class DictulaApp extends StatefulWidget {
  const DictulaApp({super.key});

  @override
  State<DictulaApp> createState() => _DictulaAppState();
}

class _DictulaAppState extends State<DictulaApp> {
  late final BleService _bleService;
  late final NativeAudioPlayer _audioPlayer;
  late final AudioRecorderService _recorderService;
  late final RecordingsRepository _recordingsRepository;
  late final GroupsRepository _groupsRepository;
  late final GeminiService _geminiService;
  late final RecordingSyncManager _syncManager;
  late final RecorderController _recorderController;

  @override
  void initState() {
    super.initState();
    _bleService = BleService();
    _audioPlayer = NativeAudioPlayer();
    _recorderService = AudioRecorderService();
    _recordingsRepository = RecordingsRepository();
    _groupsRepository = GroupsRepository();
    _geminiService = GeminiService();

    _syncManager = RecordingSyncManager(
      audioPlayer: _audioPlayer,
      bleService: _bleService,
      recordingsRepository: _recordingsRepository,
    );

    _recorderController = RecorderController(
      recorderService: _recorderService,
      recordingsRepository: _recordingsRepository,
      audioPlayer: _audioPlayer,
    );

    // Request necessary Bluetooth, Microphone, Location and storage permissions right after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PermissionService.requestAppPermissions();
    });
  }

  @override
  void dispose() {
    _bleService.dispose();
    _syncManager.dispose();
    _recorderController.dispose();
    _recorderService.dispose();
    _audioPlayer.dispose();
    _recordingsRepository.dispose();
    _groupsRepository.dispose();
    _geminiService.dispose();
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
      home: HomeScreen(
        bleService: _bleService,
        syncManager: _syncManager,
        recordingsRepository: _recordingsRepository,
        groupsRepository: _groupsRepository,
        geminiService: _geminiService,
        recorderController: _recorderController,
      ),
    );
  }
}

