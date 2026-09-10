import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeminiChatMessage {
  final String role; // 'user' or 'model'
  final String text;
  final DateTime timestamp;

  GeminiChatMessage({
    required this.role,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
      };

  factory GeminiChatMessage.fromJson(Map<String, dynamic> json) => GeminiChatMessage(
        role: json['role'] as String? ?? 'user',
        text: json['text'] as String? ?? '',
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Service for Google Gemini API integration (Audio transcription, AI chat, group summarization).
class GeminiService with ChangeNotifier {
  static const String _secureApiKey = 'dictula_gemini_api_key_secure';
  static const String _legacyPrefApiKey = 'dictula_gemini_api_key';
  static const String _prefModel = 'dictula_gemini_model';
  static const String defaultModel = 'gemini-3.8-flash';

  /// Standard recommended models for quick selection.
  static const List<String> availableModels = [
    'gemini-3.8-flash',
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-2.0-flash',
    'gemini-1.5-flash',
  ];

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  String _apiKey = '';
  String _selectedModel = defaultModel;
  bool _isInitialized = false;

  String get apiKey => _apiKey;
  String get selectedModel => _selectedModel;
  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  bool get isInitialized => _isInitialized;

  GeminiService() {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _selectedModel = prefs.getString(_prefModel) ?? defaultModel;

      // 1. Try reading encrypted API key from secure storage
      String? key;
      try {
        key = await _secureStorage.read(key: _secureApiKey);
      } catch (e) {
        debugPrint('[GeminiService] Error reading secure storage: $e');
      }

      // 2. Migration: If no secure key found, check legacy SharedPreferences
      if (key == null || key.trim().isEmpty) {
        final legacyKey = prefs.getString(_legacyPrefApiKey);
        if (legacyKey != null && legacyKey.trim().isNotEmpty) {
          debugPrint('[GeminiService] Migrating legacy API key to encrypted secure storage...');
          key = legacyKey.trim();
          try {
            await _secureStorage.write(key: _secureApiKey, value: key);
            // Clean up unencrypted key from SharedPreferences
            await prefs.remove(_legacyPrefApiKey);
          } catch (e) {
            debugPrint('[GeminiService] Migration to secure storage failed: $e');
          }
        }
      }

      _apiKey = key ?? '';
    } catch (e) {
      debugPrint('[GeminiService] _loadPreferences error: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Persistently and securely saves the Gemini API key.
  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    try {
      if (_apiKey.isEmpty) {
        await _secureStorage.delete(key: _secureApiKey);
      } else {
        await _secureStorage.write(key: _secureApiKey, value: _apiKey);
      }
      // Ensure legacy plain text key is removed from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_legacyPrefApiKey);
    } catch (e) {
      debugPrint('[GeminiService] Error writing to secure storage: $e');
      // Fallback in case secure storage fails on a specific desktop environment
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_legacyPrefApiKey, _apiKey);
    }
    notifyListeners();
  }

  /// Sets the active Gemini model. Accepts any custom model identifier.
  Future<void> setSelectedModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isNotEmpty) {
      _selectedModel = trimmed;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefModel, trimmed);
      notifyListeners();
    }
  }

  /// Transcribes an audio WAV file using Gemini Multimodal Audio understanding.
  Future<String> transcribeAudio({
    required String audioPath,
    String? languageHint = 'de',
  }) async {
    if (!hasApiKey) {
      throw Exception('Kein Gemini API-Key hinterlegt. Bitte in den Einstellungen hinterlegen.');
    }

    final File audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      throw Exception('Audiodatei nicht gefunden: $audioPath');
    }

    final Uint8List audioBytes = await audioFile.readAsBytes();
    if (audioBytes.isEmpty) {
      throw Exception('Audiodatei ist leer.');
    }

    final String base64Audio = base64Encode(audioBytes);
    final String url =
        'https://generativelanguage.googleapis.com/v1beta/models/$_selectedModel:generateContent?key=$_apiKey';

    final Map<String, dynamic> requestBody = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'inline_data': {
                'mime_type': 'audio/wav',
                'data': base64Audio,
              }
            },
            {
              'text':
                  'Du bist ein hochpräziser Transkriptions- und Diktat-Assistent für die Dictula App. '
                  'Aufgabe: Transkribiere diese Audioaufnahme vollständig und akkurat auf Deutsch. '
                  'Gliedere den Text mit Zeitstempeln [MM:SS] in sinnvolle Abschnitte. '
                  'Korrigiere Füllwörter dezent, aber behalte den originalen Wortlaut bei. '
                  'Formatiere Kernaussagen und Aufzählungspunkte leserlich in Markdown.'
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 4096,
      }
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        final errorJson = jsonDecode(response.body);
        final errorMsg = errorJson['error']?['message'] ?? response.body;
        throw Exception('Gemini API Fehler (${response.statusCode}): $errorMsg');
      }

      final Map<String, dynamic> responseData = jsonDecode(response.body);
      final candidates = responseData['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('Keine Transkription von Gemini empfangen.');
      }

      final content = candidates[0]['content'];
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        throw Exception('Leere Transkriptionsantwort.');
      }

      final String transcriptionText = parts.map((p) => p['text'] ?? '').join('\n').trim();
      return transcriptionText;
    } catch (e) {
      debugPrint('[GeminiService] Transcribe error: $e');
      rethrow;
    }
  }

  /// Sends a chat query regarding a specific recording context.
  Future<String> sendRecordingChatMessage({
    required String recordingTitle,
    required String? transcription,
    required String? groupName,
    required List<GeminiChatMessage> history,
    required String userMessage,
  }) async {
    if (!hasApiKey) {
      throw Exception('Kein Gemini API-Key hinterlegt.');
    }

    final String url =
        'https://generativelanguage.googleapis.com/v1beta/models/$_selectedModel:generateContent?key=$_apiKey';

    final String systemContext = 'Du bist der intelligente Sprachnotiz-Assistent von Dictula.\n'
        'Kontext der Aufnahme:\n'
        '• Titel: $recordingTitle\n'
        '• Gruppe: ${groupName ?? "Keine"}\n'
        '• Transkribierter Inhalt:\n${transcription ?? "(Noch keine Transkription vorhanden)"}\n\n'
        'Beantworte Fragen des Benutzers präzise basierend auf der Sprachnotiz und hilf bei Zusammenfassungen, Aufgabenlisten und Extrakten.';

    final List<Map<String, dynamic>> contents = [];

    // System instruction injected as first user turn or explicit prompt
    contents.add({
      'role': 'user',
      'parts': [
        {'text': systemContext}
      ]
    });
    contents.add({
      'role': 'model',
      'parts': [
        {'text': 'Verstanden! Ich stehe bereit, um Fragen zu "$recordingTitle" zu beantworten.'}
      ]
    });

    // History turns
    for (final msg in history) {
      contents.add({
        'role': msg.role == 'user' ? 'user' : 'model',
        'parts': [
          {'text': msg.text}
        ]
      });
    }

    // Current question
    contents.add({
      'role': 'user',
      'parts': [
        {'text': userMessage}
      ]
    });

    final Map<String, dynamic> requestBody = {
      'contents': contents,
      'generationConfig': {
        'temperature': 0.4,
        'maxOutputTokens': 2048,
      }
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      if (response.statusCode != 200) {
        final errorJson = jsonDecode(response.body);
        final errorMsg = errorJson['error']?['message'] ?? response.body;
        throw Exception('Gemini API Fehler (${response.statusCode}): $errorMsg');
      }

      final Map<String, dynamic> responseData = jsonDecode(response.body);
      final candidates = responseData['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('Keine Antwort von Gemini empfangen.');
      }

      final content = candidates[0]['content'];
      final parts = content?['parts'] as List?;
      final String answer = parts?.map((p) => p['text'] ?? '').join('\n').trim() ?? '';
      return answer;
    } catch (e) {
      debugPrint('[GeminiService] Chat error: $e');
      rethrow;
    }
  }

  /// Synthesizes and analyzes a collection of timestamped group recordings.
  Future<String> summarizeGroupRecordings({
    required String groupName,
    required List<Map<String, dynamic>> timestampedRecordings,
  }) async {
    if (!hasApiKey) {
      throw Exception('Kein Gemini API-Key hinterlegt.');
    }

    final String url =
        'https://generativelanguage.googleapis.com/v1beta/models/$_selectedModel:generateContent?key=$_apiKey';

    final StringBuffer logBuffer = StringBuffer();
    logBuffer.writeln('# Gruppe / Logbuch: $groupName\n');
    for (final rec in timestampedRecordings) {
      logBuffer.writeln('### [${rec['timestamp']}] ${rec['title']}');
      logBuffer.writeln('Transkript: ${rec['transcription'] ?? "(Keine Transkription)"}\n');
    }

    final String prompt =
        'Hier ist eine chronologische Sammlung von Sprachaufnahmen aus der Gruppe "$groupName":\n\n'
        '$logBuffer\n\n'
        'Aufgabe:\n'
        '1. Erstelle eine strukturierte Zusammenfassung des gesamten Verlaufs.\n'
        '2. Hebe Entwicklungen und Unterschiede zwischen den einzelnen Zeitpunkten hervor.\n'
        '3. Führe wichtige To-Dos oder Erkenntnisse stichpunktartig auf.';

    final Map<String, dynamic> requestBody = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 4096,
      }
    };

    final response = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );

    if (response.statusCode != 200) {
      throw Exception('Gemini API Fehler (${response.statusCode}): ${response.body}');
    }

    final Map<String, dynamic> responseData = jsonDecode(response.body);
    final candidates = responseData['candidates'] as List?;
    final parts = candidates?[0]?['content']?['parts'] as List?;
    return parts?.map((p) => p['text'] ?? '').join('\n').trim() ?? '';
  }
}
