import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class WaveformVisualizer extends StatefulWidget {
  final bool isActive;
  final bool isRecording;
  final Color? activeColor;

  const WaveformVisualizer({
    super.key,
    required this.isActive,
    this.isRecording = false,
    this.activeColor,
  });

  @override
  State<WaveformVisualizer> createState() => _WaveformVisualizerState();
}

class _WaveformVisualizerState extends State<WaveformVisualizer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Random _rnd = Random();
  final List<double> _heights = List.generate(24, (i) => 0.2 + (i % 5) * 0.15);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    )..addListener(() {
        if (widget.isActive) {
          setState(() {
            for (int i = 0; i < _heights.length; i++) {
              if (widget.isRecording) {
                _heights[i] = (0.2 + _rnd.nextDouble() * 0.8);
              } else {
                _heights[i] = (0.25 + sin(i * 0.4 + _controller.value * 2 * pi).abs() * 0.7);
              }
            }
          });
        }
      });

    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant WaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isActive && _controller.isAnimating) {
      _controller.stop();
      setState(() {
        for (int i = 0; i < _heights.length; i++) {
          _heights[i] = 0.15;
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.activeColor ??
        (widget.isRecording ? AppTheme.accentRed : AppTheme.primaryCyan);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1522),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isActive ? color.withAlpha(128) : const Color(0xFF243248),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(_heights.length, (index) {
          final h = widget.isActive ? _heights[index] : 0.15;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 3,
            height: 38 * h.clamp(0.1, 1.0),
            decoration: BoxDecoration(
              color: widget.isActive ? color : AppTheme.textMuted.withAlpha(77),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}
