import 'package:flutter/material.dart';
import 'dart:math' as math;

/// A neutral light travelling around the edge while a board save is pending.
class BoardSyncGlow extends StatefulWidget {
  const BoardSyncGlow({
    super.key,
    required this.active,
    required this.child,
    this.foreground = false,
  });
  final bool active;
  final Widget child;
  final bool foreground;

  @override
  State<BoardSyncGlow> createState() => _BoardSyncGlowState();
}

class _BoardSyncGlowState extends State<BoardSyncGlow>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
    value: .28,
  );

  void _sync() {
    if (widget.active &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.of(context)) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(BoardSyncGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _motion.value = .28;
    _sync();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: widget.active && !widget.foreground
          ? _EdgeGlow(_motion, reduced: MediaQuery.disableAnimationsOf(context))
          : null,
      foregroundPainter: widget.active && widget.foreground
          ? _EdgeGlow(_motion, reduced: MediaQuery.disableAnimationsOf(context))
          : null,
      child: widget.child,
    ),
  );
}

class _EdgeGlow extends CustomPainter {
  _EdgeGlow(this.motion, {required this.reduced}) : super(repaint: motion);
  final Animation<double> motion;
  final bool reduced;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(12)),
    );
    final edge = RRect.fromRectAndRadius(
      bounds.deflate(1.5),
      const Radius.circular(10.5),
    );
    final rotation = GradientRotation(
      (reduced ? .15 : motion.value) * math.pi * 2,
    );
    const stops = [0.0, .68, .8, .93, .98, 1.0];
    // Separate constant-RGB layers avoid dark bands from alpha interpolation.
    final shadow = SweepGradient(
      colors: [
        Color(0x00000000),
        Color(0x00000000),
        Color(0x05000000),
        Color(0x18000000),
        Color(0x30000000),
        Color(0x00000000),
      ],
      stops: stops,
      transform: rotation,
    ).createShader(bounds);
    final light = SweepGradient(
      colors: const [
        Color(0x00ffffff),
        Color(0x00ffffff),
        Color(0x20ffffff),
        Color(0xaaffffff),
        Color(0xffffffff),
        Color(0x00ffffff),
      ],
      stops: stops,
      transform: rotation,
    ).createShader(bounds);
    canvas.drawRRect(
      edge,
      Paint()
        ..color = const Color(0x10000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8,
    );
    canvas.drawRRect(
      edge,
      Paint()
        ..shader = shadow
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(
      edge,
      Paint()
        ..shader = light
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    canvas.drawRRect(
      edge,
      Paint()
        ..shader = light
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EdgeGlow oldDelegate) =>
      oldDelegate.motion != motion || oldDelegate.reduced != reduced;
}
