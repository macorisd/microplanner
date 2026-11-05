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
    duration: const Duration(milliseconds: 1800),
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
    final width = size.width * .75;
    final x = reduced
        ? size.width / 2
        : -width + (size.width + width * 2) * motion.value;
    final sheen = Rect.fromCenter(
      center: Offset(x, size.height / 2),
      width: width,
      height: size.height * 3,
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x00ffffff), Color(0xb3ffffff), Color(0x00ffffff)],
          stops: [0, .5, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(sheen),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Sheen oldDelegate) =>
      oldDelegate.motion != motion || oldDelegate.reduced != reduced;
}
