import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:dictula/features/ai_gemini/services/gemini_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('GeminiService Tests', () {
    test('default model is gemini-3.8-flash', () async {
      final service = GeminiService();
      // Allow async _loadPreferences to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(service.selectedModel, 'gemini-3.8-flash');
      expect(service.hasApiKey, isFalse);
    });

    test('can set and persist custom model name', () async {
      final service = GeminiService();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await service.setSelectedModel('gemini-3.8-flash-custom-2026');
      expect(service.selectedModel, 'gemini-3.8-flash-custom-2026');

      // Verify persistence in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dictula_gemini_model'), 'gemini-3.8-flash-custom-2026');
    });

    test('can set and retrieve encrypted API key', () async {
      final service = GeminiService();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await service.setApiKey('AIzaSyTestKey123456');
      expect(service.apiKey, 'AIzaSyTestKey123456');
      expect(service.hasApiKey, isTrue);

      // Verify a new service instance loads the key from secure storage
      final newService = GeminiService();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(newService.apiKey, 'AIzaSyTestKey123456');
    });

    test('migrates legacy SharedPreferences API key to secure storage', () async {
      // Simulate existing legacy plain text key in SharedPreferences
      SharedPreferences.setMockInitialValues({
        'dictula_gemini_api_key': 'AIzaSyLegacyKey999',
      });
      FlutterSecureStorage.setMockInitialValues({});

      final service = GeminiService();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Key should be loaded
      expect(service.apiKey, 'AIzaSyLegacyKey999');
      expect(service.hasApiKey, isTrue);

      // Plain text key must be deleted from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('dictula_gemini_api_key'), isNull);

      // Next service instance should load it from secure storage
      final secondService = GeminiService();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(secondService.apiKey, 'AIzaSyLegacyKey999');
    });
  });
}
