import 'package:flutter/material.dart';

/// A neutral, paint-only sheen that lasts exactly as long as the pending save.
class BoardSyncGlow extends StatefulWidget {
  const BoardSyncGlow({super.key, required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<BoardSyncGlow> createState() => _BoardSyncGlowState();
}

class _BoardSyncGlowState extends State<BoardSyncGlow>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
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
      painter: widget.active
          ? _Sheen(_motion, reduced: MediaQuery.disableAnimationsOf(context))
          : null,
      child: widget.child,
    ),
  );
}

class _Sheen extends CustomPainter {
  _Sheen(this.motion, {required this.reduced}) : super(repaint: motion);
  final Animation<double> motion;
  final bool reduced;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(12)),
    );
    final width = size.width * .65;
    final x = reduced
        ? size.width / 2
        : -width + (size.width + width * 2) * motion.value;
    final sheen = Rect.fromCenter(
      center: Offset(x, size.height / 2),
      width: width,
      height: size.height * 3,
    );
    // Achromatic shoulders give the light contrast on very pale board surfaces.
    // Only the reflection moves; the saved board hue and its content stay intact.
    final shader = const LinearGradient(
      colors: [
        Color(0x00000000),
        Color(0x24000000),
        Color(0xfaffffff),
        Color(0x18000000),
        Color(0x00000000),
      ],
      stops: [0, .28, .5, .72, 1],
      begin: Alignment(-1, -.2),
      end: Alignment(1, .2),
    ).createShader(sheen);
    canvas.drawRect(bounds, Paint()..shader = shader);
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds.deflate(1), const Radius.circular(11)),
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Sheen oldDelegate) =>
      oldDelegate.motion != motion || oldDelegate.reduced != reduced;
}
