import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The three original logo leaves take turns slipping to the back of the deck.
class AnimatedAppLogo extends StatefulWidget {
  const AnimatedAppLogo({super.key});

  static const cycleDuration = Duration(milliseconds: 3600);

  @override
  State<AnimatedAppLogo> createState() => _AnimatedAppLogoState();
}

class _AnimatedAppLogoState extends State<AnimatedAppLogo>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AnimatedAppLogo.cycleDuration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: 280,
      height: 200,
      child: CustomPaint(painter: _ShufflePainter(_controller)),
    ),
  );
}

class _ShufflePainter extends CustomPainter {
  final Animation<double> progress;
  _ShufflePainter(this.progress) : super(repaint: progress);

  // Geometry and opaque colors from assets/images/microplanner_logo.png.
  static const _colors = [
    Color(0xFF8DD4A0),
    Color(0xFFF5D68A),
    Color(0xFF88B6E7),
  ];
  static const _slots = [0.0, 267.0, 526.0];
  static final _leaf = RRect.fromRectAndRadius(
    const Rect.fromLTWH(0, 0, 764, 1286),
    const Radius.circular(340),
  );

  double _ease(double value) =>
      Curves.easeInOutCubic.transform(value.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final height = math.min(size.width / 2.5, size.height / 1.8);
    final scale = height / 1286;
    canvas.save();
    canvas.translate(
      (size.width - 1290 * scale) / 2,
      (size.height - height) / 2,
    );
    canvas.scale(scale);

    final cycle = progress.value * 3;
    final turn = cycle.floor() % 3;
    final t = cycle - cycle.floor();
    final order = List.generate(3, (rank) => (rank - turn + 3) % 3);
    final outgoing = _ease((t - 0.10) / 0.32);
    final incoming = _ease((t - 0.42) / 0.48);
    final following = _ease((t - 0.16) / 0.58);
    final travel = Curves.easeInOutSine.transform(
      ((t - 0.10) / 0.80).clamp(0.0, 1.0),
    );
    final lift = math.sin(math.pi * travel);
    final frontX = t < 0.42
        ? _slots[2] + (1368 - _slots[2]) * outgoing
        : 1368 * (1 - incoming);

    void draw(int color, double x, {bool moving = false}) {
      canvas.save();
      canvas.translate(x + 382, 643 - (moving ? 1286 * 0.13 * lift : 0));
      if (moving) {
        canvas.rotate(math.sin(math.pi * 2 * travel) * 0.06);
        canvas.scale(1 - 0.065 * lift);
      }
      canvas.translate(-382.0, -643.0);
      if (moving && lift > 0) {
        canvas.drawShadow(
          Path()..addRRect(_leaf),
          Colors.black.withValues(alpha: 0.14 * lift),
          24 * lift,
          false,
        );
      }
      canvas.drawRRect(_leaf, Paint()..color = _colors[color]);
      canvas.restore();
    }

    // Change depth only when the departing sheet has cleared the entire stack.
    if (t >= 0.42) draw(order[2], frontX, moving: true);
    for (var rank = 0; rank < 2; rank++) {
      draw(
        order[rank],
        _slots[rank] + (_slots[rank + 1] - _slots[rank]) * following,
      );
    }
    if (t < 0.42) draw(order[2], frontX, moving: true);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShufflePainter oldDelegate) =>
      progress != oldDelegate.progress;
}
