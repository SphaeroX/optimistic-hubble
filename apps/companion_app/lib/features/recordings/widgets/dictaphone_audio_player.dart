import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../core/audio/native_audio_player.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../models/dictula_recording.dart';

/// A sleek, dictaphone-style audio player component featuring an interactive
/// scrubber timeline, waveform visualizer, fast rewind/forward controls (-10s / +10s),
/// and live timestamp display.
class DictaphoneAudioPlayer extends StatefulWidget {
  final DictulaRecording recording;
  final NativeAudioPlayer audioPlayer;
  final VoidCallback? onContinueRecording;

  const DictaphoneAudioPlayer({
    super.key,
    required this.recording,
    required this.audioPlayer,
    this.onContinueRecording,
  });

  @override
  State<DictaphoneAudioPlayer> createState() => _DictaphoneAudioPlayerState();
}

class _DictaphoneAudioPlayerState extends State<DictaphoneAudioPlayer> {
  bool _isDragging = false;
  double _dragFraction = 0.0;

  @override
  void initState() {
    super.initState();
    widget.audioPlayer.addListener(_onPlayerUpdate);
  }

  @override
  void didUpdateWidget(covariant DictaphoneAudioPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioPlayer != widget.audioPlayer) {
      oldWidget.audioPlayer.removeListener(_onPlayerUpdate);
      widget.audioPlayer.addListener(_onPlayerUpdate);
    }
  }

  @override
  void dispose() {
    widget.audioPlayer.removeListener(_onPlayerUpdate);
    super.dispose();
  }

  void _onPlayerUpdate() {
    if (mounted) setState(() {});
  }

  bool get _isThisRecordingActive =>
      widget.audioPlayer.currentFilePath != null &&
      widget.audioPlayer.currentFilePath == widget.recording.localWavPath;

  bool get _isPlaying => _isThisRecordingActive && widget.audioPlayer.isPlaying;

  Duration get _effectiveTotalDuration {
    if (_isThisRecordingActive && widget.audioPlayer.totalDuration > Duration.zero) {
      return widget.audioPlayer.totalDuration;
    }
    return widget.recording.duration > Duration.zero
        ? widget.recording.duration
        : const Duration(seconds: 1);
  }

  Duration get _effectivePosition {
    if (!_isThisRecordingActive) return Duration.zero;
    if (_isDragging) {
      return Duration(
        milliseconds: (_effectiveTotalDuration.inMilliseconds * _dragFraction).round(),
      );
    }
    return widget.audioPlayer.currentPosition;
  }

  double get _progressFraction {
    if (_effectiveTotalDuration.inMilliseconds == 0) return 0.0;
    if (_isDragging) return _dragFraction;
    if (!_isThisRecordingActive) return 0.0;
    return (_effectivePosition.inMilliseconds / _effectiveTotalDuration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  void _handlePlayToggle() {
    if (_isPlaying) {
      widget.audioPlayer.pause();
    } else {
      widget.audioPlayer.play(
        widget.recording.localWavPath,
        duration: widget.recording.duration,
      );
    }
  }

  void _seekToFraction(double fraction) {
    final clamped = fraction.clamp(0.0, 1.0);
    final targetMs = (_effectiveTotalDuration.inMilliseconds * clamped).round();
    final target = Duration(milliseconds: targetMs);

    if (!_isThisRecordingActive) {
      widget.audioPlayer.play(
        widget.recording.localWavPath,
        duration: widget.recording.duration,
      ).then((_) {
        widget.audioPlayer.seek(target);
      });
    } else {
      widget.audioPlayer.seek(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTotal = _effectiveTotalDuration;
    final effectivePos = _effectivePosition;
    final waveform = widget.recording.waveformSamples;

    return Card(
      color: AppTheme.cardDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: _isPlaying ? AppTheme.primaryCyan.withAlpha(90) : const Color(0xFF243248),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            // Dictaphone LCD-Style Header with Status & Time Counters
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF070B12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isPlaying ? AppTheme.primaryCyan.withAlpha(50) : const Color(0xFF1E2838),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isPlaying ? AppTheme.primaryCyan : AppTheme.textMuted.withAlpha(100),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isPlaying
                            ? 'WIEDERGABE'
                            : (_isThisRecordingActive && effectivePos > Duration.zero ? 'PAUSE' : 'BEREIT'),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                          color: _isPlaying ? AppTheme.primaryCyan : AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${Formatters.formatDuration(effectivePos)} / ${Formatters.formatDuration(effectiveTotal)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Interactive Waveform / Scrubber
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                setState(() {
                  _isDragging = true;
                });
              },
              onHorizontalDragUpdate: (details) {
                final RenderBox? box = context.findRenderObject() as RenderBox?;
                if (box == null || box.size.width <= 0) return;
                final double localX = details.localPosition.dx.clamp(0.0, box.size.width);
                setState(() {
                  _dragFraction = (localX / box.size.width).clamp(0.0, 1.0);
                });
              },
              onHorizontalDragEnd: (details) {
                _seekToFraction(_dragFraction);
                setState(() {
                  _isDragging = false;
                });
              },
              onTapDown: (details) {
                final RenderBox? box = context.findRenderObject() as RenderBox?;
                if (box == null || box.size.width <= 0) return;
                final double localX = details.localPosition.dx.clamp(0.0, box.size.width);
                final double fraction = (localX / box.size.width).clamp(0.0, 1.0);
                _seekToFraction(fraction);
              },
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0F1A),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CustomPaint(
                    painter: _DictaphoneScrubberPainter(
                      waveform: waveform,
                      progress: _progressFraction,
                      isDragging: _isDragging,
                    ),
                    child: Container(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Main Control Buttons: [-10s] [Play/Pause] [+10s] [Weiterführen]
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Rewind 10s
                IconButton(
                  icon: const Icon(Icons.replay_10, size: 28),
                  tooltip: '10 Sekunden zurückspulen',
                  color: Colors.white70,
                  onPressed: () => widget.audioPlayer.seekBackward(const Duration(seconds: 10)),
                ),

                // Play / Pause Prominent Center Button
                ElevatedButton(
                  onPressed: _handlePlayToggle,
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(16),
                    backgroundColor: AppTheme.primaryCyan,
                    foregroundColor: Colors.black,
                    elevation: 3,
                    shadowColor: AppTheme.primaryCyan.withAlpha(120),
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 28,
                  ),
                ),

                // Fast Forward 10s
                IconButton(
                  icon: const Icon(Icons.forward_10, size: 28),
                  tooltip: '10 Sekunden vorspulen',
                  color: Colors.white70,
                  onPressed: () => widget.audioPlayer.seekForward(const Duration(seconds: 10)),
                ),

                // Optional: Continue recording
                if (widget.onContinueRecording != null)
                  OutlinedButton.icon(
                    onPressed: widget.onContinueRecording,
                    icon: const Icon(Icons.mic, size: 15),
                    label: const Text('Fortsetzen', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accentGreen,
                      side: const BorderSide(color: AppTheme.accentGreen),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DictaphoneScrubberPainter extends CustomPainter {
  final List<double> waveform;
  final double progress;
  final bool isDragging;

  _DictaphoneScrubberPainter({
    required this.waveform,
    required this.progress,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double midY = size.height * 0.5;
    final double playheadX = size.width * progress;

    // Draw background grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF162234)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), gridPaint);

    if (waveform.isNotEmpty) {
      final int barCount = waveform.length;
      final double barWidth = max(2.0, size.width / barCount);
      final double maxBarHeight = size.height * 0.38;

      for (int i = 0; i < barCount; i++) {
        final double x = i * (size.width / barCount) + barWidth * 0.5;
        final double normalizedAmp = waveform[i].clamp(0.08, 1.0);
        final double h = max(3.0, normalizedAmp * maxBarHeight);

        final bool isPlayed = x <= playheadX;
        final barPaint = Paint()
          ..color = isPlayed
              ? AppTheme.primaryCyan
              : const Color(0xFF283A52)
          ..strokeWidth = max(1.5, barWidth - 1.0)
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(Offset(x, midY - h), Offset(x, midY + h), barPaint);
      }
    } else {
      // Fallback progress track if no waveform points
      final trackPaint = Paint()
        ..color = const Color(0xFF1E2E42)
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(8, midY), Offset(size.width - 8, midY), trackPaint);

      final activePaint = Paint()
        ..color = AppTheme.primaryCyan
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(8, midY), Offset(playheadX.clamp(8.0, size.width - 8), midY), activePaint);
    }

    // Playhead Vertical Needle
    final needlePaint = Paint()
      ..color = isDragging ? AppTheme.accentOrange : AppTheme.primaryCyan
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(playheadX, 4), Offset(playheadX, size.height - 4), needlePaint);

    // Needle Head Marker
    final thumbPaint = Paint()
      ..color = isDragging ? AppTheme.accentOrange : Colors.white;
    canvas.drawCircle(Offset(playheadX, midY), isDragging ? 5.5 : 4.0, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _DictaphoneScrubberPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.waveform != waveform;
  }
}
