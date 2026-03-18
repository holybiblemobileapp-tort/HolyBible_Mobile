import 'dart:math' as math;
import 'package:flutter/material.dart';

class NeonVisualizer extends StatefulWidget {
  final bool isPlaying;
  final Color color;
  const NeonVisualizer({super.key, required this.isPlaying, this.color = Colors.cyanAccent});

  @override
  State<NeonVisualizer> createState() => _NeonVisualizerState();
}

class _NeonVisualizerState extends State<NeonVisualizer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.isPlaying) _controller.repeat();
  }

  @override
  void didUpdateWidget(NeonVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: const Size(double.maxFinite, 40),
          painter: _WaveformPainter(
            progress: _controller.value,
            isPlaying: widget.isPlaying,
            color: widget.color,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool isPlaying;
  final Color color;

  _WaveformPainter({required this.progress, required this.isPlaying, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0);

    final path = Path();
    final double centerY = size.height / 2;
    final int barCount = 40;
    final double spacing = size.width / barCount;

    for (int i = 0; i < barCount; i++) {
      double x = i * spacing + (spacing / 2);
      
      // Calculate height based on sine wave and playback state
      double amplitude = isPlaying ? (math.sin((progress * 2 * math.pi) + (i * 0.5)) * 0.5 + 0.5) : 0.1;
      // Add some randomness/variation
      double height = (size.height * 0.8) * amplitude * (0.5 + 0.5 * math.sin(i.toDouble()));
      
      if (height < 2) height = 2;

      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        glowPaint,
      );
      canvas.drawLine(
        Offset(x, centerY - height / 2),
        Offset(x, centerY + height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => 
    oldDelegate.progress != progress || oldDelegate.isPlaying != isPlaying;
}
