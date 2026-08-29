import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/recording_group.dart';

/// Repository for persistent storage and management of recording groups.
class GroupsRepository with ChangeNotifier {
  final List<RecordingGroup> _groups = [];
  bool _isLoaded = false;

  List<RecordingGroup> get groups => List.unmodifiable(_groups);
  bool get isLoaded => _isLoaded;

  GroupsRepository() {
    loadGroups();
  }

  Future<File> _getStorageFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/dictula_groups.json');
  }

  Future<void> loadGroups() async {
    try {
      final file = await _getStorageFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        _groups.clear();
        _groups.addAll(jsonList.map((j) => RecordingGroup.fromJson(j as Map<String, dynamic>)));
      } else {
        // Seed default initial groups
        _groups.clear();
        _groups.addAll([
          RecordingGroup(
            id: 'daily_log',
            name: 'Tagesprotokoll',
            description: 'Tägliche Sprachnotizen und Logbuch-Einträge',
            colorValue: 0xFF00E5FF,
            createdAt: DateTime.now(),
          ),
          RecordingGroup(
            id: 'ideas',
            name: 'Ideen & Brainstorming',
            description: 'Schnelle Gedanken und Sprachmemos',
            colorValue: 0xFFFF9100,
            createdAt: DateTime.now(),
          ),
        ]);
        await _save();
      }
    } catch (e) {
      debugPrint('[GroupsRepository] Error loading groups: $e');
    } finally {
      _isLoaded = true;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    try {
      final file = await _getStorageFile();
      final jsonList = _groups.map((g) => g.toJson()).toList();
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(jsonList));
    } catch (e) {
      debugPrint('[GroupsRepository] Error saving groups: $e');
    }
  }

  Future<RecordingGroup> createGroup({
    required String name,
    String? description,
    int colorValue = 0xFF00E5FF,
  }) async {
    final String id = 'grp_${DateTime.now().millisecondsSinceEpoch}';
    final group = RecordingGroup(
      id: id,
      name: name,
      description: description,
      colorValue: colorValue,
      createdAt: DateTime.now(),
    );
    _groups.insert(0, group);
    await _save();
    notifyListeners();
    return group;
  }

  Future<void> updateGroup(RecordingGroup updatedGroup) async {
    final index = _groups.indexWhere((g) => g.id == updatedGroup.id);
    if (index != -1) {
      _groups[index] = updatedGroup;
      await _save();
      notifyListeners();
    }
  }

  Future<void> deleteGroup(String groupId) async {
    _groups.removeWhere((g) => g.id == groupId);
    await _save();
    notifyListeners();
  }

  RecordingGroup? getGroupById(String? groupId) {
    if (groupId == null) return null;
    try {
      return _groups.firstWhere((g) => g.id == groupId);
    } catch (_) {
      return null;
    }
  }
}
