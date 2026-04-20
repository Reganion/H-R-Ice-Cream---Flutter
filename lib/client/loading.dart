import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Loading screen matching the provided screenshot.
///
/// Usage:
/// `Navigator.push(context, MaterialPageRoute(builder: (_) => const LoadingPage()));`
class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: LoadingView(),
    );
  }
}

/// Reusable loading content (spinner + label).
///
/// Useful for showing a full-screen overlay when offline.
class LoadingView extends StatelessWidget {
  const LoadingView({
    super.key,
    this.text = 'Loading',
    this.size = 74,
    this.strokeWidth = 15,
  });

  final String text;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RovingSpinner(
            size: size,
            strokeWidth: strokeWidth,
          ),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16.42,
              color: Color(0xFF585858),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen overlay that keeps the previous page visible behind it.
///
/// Use this when you want the loader to appear "on top" of the current screen.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({
    super.key,
    this.text = 'Loading',
    this.barrierColor = Colors.transparent,
  });

  final String text;
  final Color barrierColor;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: barrierColor),
          ),
          LoadingView(text: text),
        ],
      ),
    );
  }
}

class _RovingSpinner extends StatefulWidget {
  const _RovingSpinner({
    required this.size,
    required this.strokeWidth,
  });

  final double size;
  final double strokeWidth;

  @override
  State<_RovingSpinner> createState() => _RovingSpinnerState();
}

class _RovingSpinnerState extends State<_RovingSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _SpinnerPainter(
              rotationT: _controller.value,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter({
    required this.rotationT,
    required this.strokeWidth,
    this.gapRadians = 0.10, // tweak if needed
  });

  final double rotationT;
  final double strokeWidth;
  final double gapRadians;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Keep the gap at the bottom (like the screenshot)
    final arcSweep = (math.pi * 2) - gapRadians;
    final baseStart = (math.pi / 2) + (gapRadians / 2);

    // Animate rotation
    final start = baseStart + (rotationT * math.pi * 2);

    const baseRed = Color(0xFFE3001B);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt // flat ends (closer to screenshot)
      ..shader = SweepGradient(
        transform: GradientRotation(start),
        colors: [
          baseRed,                 // strongest
          baseRed.withOpacity(.55),
          baseRed.withOpacity(.25),
          baseRed.withOpacity(.08), // faint tail
        ],
        stops: const [
          0.00,
          0.45,
          0.78,
          1.00,
        ],
      ).createShader(rect);

    canvas.drawArc(rect, start, arcSweep, false, paint);
  }

  @override
  bool shouldRepaint(covariant _SpinnerPainter oldDelegate) {
    return oldDelegate.rotationT != rotationT ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gapRadians != gapRadians;
  }
}
