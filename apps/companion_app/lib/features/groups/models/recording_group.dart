import 'package:flutter/material.dart';

/// Model representing a group or chronological log container for voice notes.
class RecordingGroup {
  final String id;
  final String name;
  final String? description;
  final int colorValue;
  final DateTime createdAt;

  const RecordingGroup({
    required this.id,
    required this.name,
    this.description,
    this.colorValue = 0xFF00E5FF, // Default Cyan
    required this.createdAt,
  });

  Color get color => Color(colorValue);

  RecordingGroup copyWith({
    String? id,
    String? name,
    String? description,
    int? colorValue,
    DateTime? createdAt,
  }) {
    return RecordingGroup(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'colorValue': colorValue,
        'createdAt': createdAt.toIso8601String(),
      };

  factory RecordingGroup.fromJson(Map<String, dynamic> json) => RecordingGroup(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? 'Neue Gruppe',
        description: json['description'] as String?,
        colorValue: json['colorValue'] as int? ?? 0xFF00E5FF,
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}
