class TapEvent {
  final DateTime timestamp;
  final double shockMagnitude;
  final int tapIndex;

  TapEvent({
    required this.timestamp,
    required this.shockMagnitude,
    required this.tapIndex,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = (timestamp.millisecond ~/ 10).toString().padLeft(2, '0');
    return '$h:$m:$s.$ms';
  }
}
