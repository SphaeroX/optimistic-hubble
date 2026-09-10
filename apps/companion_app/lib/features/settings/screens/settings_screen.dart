import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/storage_manager.dart';
import '../../ai_gemini/services/gemini_service.dart';
import '../../connection/services/ble_service.dart';
import '../../recorder/controllers/recorder_controller.dart';
import '../../recordings/services/recording_sync_manager.dart';

/// Comprehensive Settings screen for Google Gemini AI, Audio recording DSP, Hardware Sync, and Storage.
class SettingsScreen extends StatefulWidget {
  final GeminiService geminiService;
  final BleService bleService;
  final RecordingSyncManager syncManager;
  final RecorderController? recorderController;

  const SettingsScreen({
    super.key,
    required this.geminiService,
    required this.bleService,
    required this.syncManager,
    this.recorderController,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _apiKeyController;
  late final TextEditingController _modelController;
  bool _obscureApiKey = true;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.geminiService.apiKey);
    _modelController = TextEditingController(text: widget.geminiService.selectedModel);
    widget.geminiService.addListener(_onGeminiServiceChanged);
  }

  void _onGeminiServiceChanged() {
    if (!mounted) return;
    if (_apiKeyController.text.isEmpty && widget.geminiService.apiKey.isNotEmpty) {
      _apiKeyController.text = widget.geminiService.apiKey;
    }
    if (_modelController.text != widget.geminiService.selectedModel) {
      _modelController.text = widget.geminiService.selectedModel;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.geminiService.removeListener(_onGeminiServiceChanged);
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _saveApiKey() async {
    await widget.geminiService.setApiKey(_apiKeyController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gemini API-Key verschlüsselt gespeichert!'),
          backgroundColor: AppTheme.accentGreen,
        ),
      );
    }
  }

  Future<void> _saveModel() async {
    final modelText = _modelController.text.trim();
    if (modelText.isNotEmpty) {
      await widget.geminiService.setSelectedModel(modelText);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gemini-Modell auf "$modelText" gesetzt!'),
            backgroundColor: AppTheme.accentGreen,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Einstellungen', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          // Gemini API Card
          Card(
            color: AppTheme.cardDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF22324A)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: AppTheme.accentGreen, size: 22),
                      SizedBox(width: 8),
                      Text('Google Gemini API', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Für KI-Transkription, interaktiven Chat zu Sprachmemos und Gruppen-Zusammenfassungen.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 14),

                  // API Key Field
                  TextField(
                    controller: _apiKeyController,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: 'Gemini API Key',
                      hintText: 'AIzaSy...',
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(_obscureApiKey ? Icons.visibility : Icons.visibility_off, size: 18),
                            onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check, color: AppTheme.accentGreen, size: 20),
                            tooltip: 'Key verschlüsselt speichern',
                            onPressed: _saveApiKey,
                          ),
                        ],
                      ),
                    ),
                    onSubmitted: (_) => _saveApiKey(),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        widget.geminiService.hasApiKey ? Icons.lock : Icons.info_outline,
                        size: 13,
                        color: widget.geminiService.hasApiKey ? AppTheme.accentGreen : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        widget.geminiService.hasApiKey
                            ? 'Dauerhaft & verschlüsselt im Keystore gespeichert'
                            : 'Kein API-Key hinterlegt (aistudio.google.com)',
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.geminiService.hasApiKey ? AppTheme.accentGreen : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Model Selector & Manual Editor
                  const Text('KI-Modell:', style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      labelText: 'Modellbezeichnung (manuell anpassbar)',
                      hintText: GeminiService.defaultModel,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check, color: AppTheme.accentGreen, size: 20),
                        tooltip: 'Modell speichern',
                        onPressed: _saveModel,
                      ),
                    ),
                    onSubmitted: (_) => _saveModel(),
                  ),
                  const SizedBox(height: 10),
                  const Text('Schnellauswahl:', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: GeminiService.availableModels.map((model) {
                      final isSelected = widget.geminiService.selectedModel == model;
                      return ChoiceChip(
                        label: Text(
                          model == GeminiService.defaultModel ? '$model (Standard)' : model,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : AppTheme.textMuted,
                          ),
                        ),
                        selected: isSelected,
                        selectedColor: AppTheme.primaryCyan.withAlpha(80),
                        backgroundColor: const Color(0xFF131D2E),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryCyan : const Color(0xFF22324A),
                        ),
                        onSelected: (selected) {
                          if (selected) {
                            _modelController.text = model;
                            widget.geminiService.setSelectedModel(model);
                          }
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Audio & Diktiergerät Preferences
          Card(
            color: AppTheme.cardDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF22324A)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.mic, color: AppTheme.primaryCyan, size: 22),
                      SizedBox(width: 8),
                      Text('Diktiergerät & Aufnahme', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (widget.recorderController != null) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Rauschfilter (Noise Suppression)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Reduziert Hintergrundrauschen am Smartphone-Mikrofon', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      value: widget.recorderController!.recorderService.noiseFilterEnabled,
                      activeThumbColor: AppTheme.primaryCyan,
                      onChanged: (val) => setState(() => widget.recorderController!.recorderService.noiseFilterEnabled = val),
                    ),
                    const Divider(color: Color(0xFF1E2A3C), height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Signalton beim Fortsetzen (Piep)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Akustischer Piepton bei Pause-Ende und Schnittpunkten', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      value: widget.recorderController!.recorderService.beepOnResume,
                      activeThumbColor: AppTheme.primaryCyan,
                      onChanged: (val) => setState(() => widget.recorderController!.recorderService.beepOnResume = val),
                    ),
                    const Divider(color: Color(0xFF1E2A3C), height: 1),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Pausen überspringen (Silence Skip)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Verkürzt leise Passagen automatisch', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                      value: widget.recorderController!.recorderService.skipSilenceEnabled,
                      activeThumbColor: AppTheme.primaryCyan,
                      onChanged: (val) => setState(() => widget.recorderController!.recorderService.skipSilenceEnabled = val),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Hardware Sync Preferences
          Card(
            color: AppTheme.cardDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF22324A)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sync_alt, color: AppTheme.primaryCyan, size: 22),
                      SizedBox(width: 8),
                      Text('Hardware & Auto-Sync', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-Sync bei Verbindung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Frische Dateien bei BLE-Verbindung automatisch herunterladen', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    value: widget.syncManager.autoSyncOnConnect,
                    activeThumbColor: AppTheme.primaryCyan,
                    onChanged: (val) => setState(() => widget.syncManager.autoSyncOnConnect = val),
                  ),
                  const Divider(color: Color(0xFF1E2A3C), height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Nach Download vom ESP32 löschen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Gibt den Flash-Speicher des Geräts automatisch wieder frei', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    value: widget.syncManager.autoDeleteAfterSync,
                    activeThumbColor: AppTheme.primaryCyan,
                    onChanged: (val) => setState(() => widget.syncManager.autoDeleteAfterSync = val),
                  ),
                  const Divider(color: Color(0xFF1E2A3C), height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Wi-Fi Turbo Hotspot (Standard)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Öffnet Handy-Hotspot für schnellen Upload (> 2.0 MB/s)', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    value: widget.syncManager.preferWifiFastTransfer,
                    activeThumbColor: AppTheme.primaryCyan,
                    onChanged: (val) => setState(() => widget.syncManager.preferWifiFastTransfer = val),
                  ),
                  const Divider(color: Color(0xFF1E2A3C), height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Automatisch mit nächstem ESP32 koppeln (RSSI)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Verbindet automatisch mit dem stärksten XIAO-Signal', style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
                    value: widget.bleService.autoConnectEnabled,
                    activeThumbColor: AppTheme.primaryCyan,
                    onChanged: (val) => setState(() => widget.bleService.autoConnectEnabled = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Local Storage Explorer
          Card(
            color: AppTheme.cardDark,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFF22324A)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.folder, color: AppTheme.primaryCyan, size: 22),
                      SizedBox(width: 8),
                      Text('Lokaler Speicherordner', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<String>(
                    future: LocalStorageManager.getRecordingsDirectoryPath(),
                    builder: (context, snapshot) {
                      final path = snapshot.data ?? 'Wird geladen...';
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D1420),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF202E42)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_open, size: 18, color: AppTheme.primaryCyan),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SelectableText(
                                path,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16, color: AppTheme.primaryCyan),
                              tooltip: 'Pfad kopieren',
                              onPressed: snapshot.hasData
                                  ? () {
                                      Clipboard.setData(ClipboardData(text: path));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Speicherpfad kopiert!')),
                                      );
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => LocalStorageManager.openInFileManager(),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Im Datei-Manager öffnen'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // About Dictula
          const Center(
            child: Column(
              children: [
                Text(
                  '${AppConstants.appName} v${AppConstants.appVersion}',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white70),
                ),
                SizedBox(height: 4),
                Text(
                  'All-in-One Voice Recorder & IoT Hardware Companion',
                  style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
