import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Interactive visual waveform editor supporting real-time amplitude animation, timeline scrubbing, and punch-in needle.
class InteractiveWaveformEditor extends StatelessWidget {
  final List<double> amplitudes;
  final Duration totalDuration;
  final Duration currentPosition;
  final bool isRecording;
  final bool isPaused;
  final ValueChanged<Duration>? onScrub;

  const InteractiveWaveformEditor({
    super.key,
    required this.amplitudes,
    required this.totalDuration,
    required this.currentPosition,
    this.isRecording = false,
    this.isPaused = false,
    this.onScrub,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;

        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            if (isRecording || totalDuration == Duration.zero) return;
            final double localX = details.localPosition.dx.clamp(0.0, width);
            final double ratio = localX / width;
            final Duration target = Duration(
              milliseconds: (totalDuration.inMilliseconds * ratio).round(),
            );
            onScrub?.call(target);
          },
          onTapDown: (details) {
            if (isRecording || totalDuration == Duration.zero) return;
            final double localX = details.localPosition.dx.clamp(0.0, width);
            final double ratio = localX / width;
            final Duration target = Duration(
              milliseconds: (totalDuration.inMilliseconds * ratio).round(),
            );
            onScrub?.call(target);
          },
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: const Color(0xFF0F1522),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isRecording ? AppTheme.accentRed.withAlpha(80) : const Color(0xFF223046),
                width: 1.5,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: CustomPaint(
                painter: _WaveformPainter(
                  amplitudes: amplitudes,
                  totalDuration: totalDuration,
                  currentPosition: currentPosition,
                  isRecording: isRecording,
                  isPaused: isPaused,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final Duration totalDuration;
  final Duration currentPosition;
  final bool isRecording;
  final bool isPaused;

  _WaveformPainter({
    required this.amplitudes,
    required this.totalDuration,
    required this.currentPosition,
    required this.isRecording,
    required this.isPaused,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double midY = size.height * 0.5;
    final double maxBarHeight = size.height * 0.42;

    // Draw center baseline
    final Paint linePaint = Paint()
      ..color = const Color(0xFF1C273B)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), linePaint);

    if (amplitudes.isEmpty) {
      // Empty placeholder waveform
      final Paint emptyPaint = Paint()
        ..color = const Color(0xFF2A3B52)
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.5;

      const int sampleBars = 40;
      final double spacing = size.width / sampleBars;
      for (int i = 0; i < sampleBars; i++) {
        final double x = i * spacing + spacing * 0.5;
        final double h = sin(i * 0.3) * 6 + 8;
        canvas.drawLine(Offset(x, midY - h), Offset(x, midY + h), emptyPaint);
      }
      return;
    }

    final int count = amplitudes.length;
    final double barWidth = 3.0;
    final double barGap = 1.5;

    // Compute progress ratio (0.0 to 1.0)
    final double progressRatio = totalDuration.inMilliseconds > 0
        ? (currentPosition.inMilliseconds / totalDuration.inMilliseconds).clamp(0.0, 1.0)
        : 1.0;

    final double needleX = size.width * progressRatio;

    // Draw Amplitude Bars
    final Paint activePaint = Paint()
      ..color = isRecording ? AppTheme.accentRed : AppTheme.primaryCyan
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final Paint inactivePaint = Paint()
      ..color = const Color(0xFF324660)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    final Paint playedPaint = Paint()
      ..color = AppTheme.accentGreen
      ..strokeCap = StrokeCap.round
      ..strokeWidth = barWidth;

    // Scale or scroll bars to fit width
    final int displayCount = min(count, (size.width / (barWidth + barGap)).floor());
    final int startIndex = count > displayCount ? (count - displayCount) : 0;
    final double spacing = size.width / max(1, count - startIndex);

    for (int i = startIndex; i < count; i++) {
      final double normalized = amplitudes[i].clamp(0.04, 1.0);
      final double barHeight = normalized * maxBarHeight;
      final double x = (i - startIndex) * spacing + spacing * 0.5;

      Paint p;
      if (isRecording) {
        p = activePaint;
      } else {
        if (x <= needleX) {
          p = isPaused ? activePaint : playedPaint;
        } else {
          p = inactivePaint;
        }
      }

      canvas.drawLine(
        Offset(x, midY - barHeight),
        Offset(x, midY + barHeight),
        p,
      );
    }

    // Draw Scrub / Punch-In Needle (Scrubbing / Paused Cursor)
    if (!isRecording && totalDuration > Duration.zero) {
      final Paint needlePaint = Paint()
        ..color = isPaused ? AppTheme.accentOrange : AppTheme.primaryCyan
        ..strokeWidth = 2.5;

      canvas.drawLine(
        Offset(needleX, 8),
        Offset(needleX, size.height - 8),
        needlePaint,
      );

      // Top and Bottom Needle caps
      final Paint capPaint = Paint()
        ..color = isPaused ? AppTheme.accentOrange : AppTheme.primaryCyan
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(needleX, 10), 4.5, capPaint);
      canvas.drawCircle(Offset(needleX, size.height - 10), 4.5, capPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.amplitudes.length != amplitudes.length ||
        oldDelegate.currentPosition != currentPosition ||
        oldDelegate.isRecording != isRecording ||
        oldDelegate.isPaused != isPaused;
  }
}
