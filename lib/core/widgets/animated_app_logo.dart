import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Keep one motion timeline across bootstrap, session and workspace loading.
/// The ticker runs only while at least one visible loader uses it.
class LogoMotionHost extends StatefulWidget {
  final Widget child;
  const LogoMotionHost({super.key, required this.child});
  @override
  State<LogoMotionHost> createState() => _LogoMotionHostState();
}

class _LogoMotionHostState extends State<LogoMotionHost>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: AnimatedAppLogo.cycleDuration,
  );
  final _clients = <Object>{};
  bool _disposed = false;

  void attach(Object client) {
    _clients.add(client);
    if (!controller.isAnimating) controller.repeat();
  }

  void detach(Object client) {
    if (_clients.remove(client) && _clients.isEmpty && !_disposed) {
      controller.stop();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _LogoTimeline(host: this, child: widget.child);
}

class _LogoTimeline extends InheritedWidget {
  final _LogoMotionHostState host;
  const _LogoTimeline({required this.host, required super.child});
  @override
  bool updateShouldNotify(covariant _LogoTimeline oldWidget) =>
      host != oldWidget.host;
}

/// The three original logo leaves take turns slipping to the back of the deck.
class AnimatedAppLogo extends StatefulWidget {
  final bool animate;
  const AnimatedAppLogo({super.key, this.animate = true});

  static const cycleDuration = Duration(milliseconds: 3600);

  @override
  State<AnimatedAppLogo> createState() => _AnimatedAppLogoState();
}

class _AnimatedAppLogoState extends State<AnimatedAppLogo>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  _LogoMotionHostState? _host;
  Animation<double> _progress = kAlwaysDismissedAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(covariant AnimatedAppLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) _configure();
  }

  void _configure() {
    final host = context
        .dependOnInheritedWidgetOfExactType<_LogoTimeline>()
        ?.host;
    if (host != _host) {
      _host?.detach(this);
      _host = host;
    }
    if (!widget.animate || MediaQuery.disableAnimationsOf(context)) {
      _host?.detach(this);
      _controller?.stop();
      _progress = kAlwaysDismissedAnimation;
    } else if (_host != null) {
      _controller?.stop();
      _host!.attach(this);
      _progress = _host!.controller;
    } else {
      final controller = _controller ??= AnimationController(
        vsync: this,
        duration: AnimatedAppLogo.cycleDuration,
      );
      if (!controller.isAnimating) controller.repeat();
      _progress = controller;
    }
  }

  @override
  void dispose() {
    _host?.detach(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: SizedBox(
      width: 280,
      height: 200,
      child: CustomPaint(painter: _ShufflePainter(_progress)),
    ),
  );
}

/// Shared artwork for the static mark, Windows shuffle and Android reveal.
class AppLogoArt {
  AppLogoArt._();
  static const colors = _ShufflePainter._colors;
  static const slots = _ShufflePainter._slots;
  static final leaf = _ShufflePainter._leaf;
  static const sourceSize = Size(1290, 1286);
  static double heightForViewport(Size size) => math.min(
    math.min(size.width, 280) / 2.5,
    math.min(size.height, 200) / 1.8,
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
      Curves.easeInOutSine.transform(value.clamp(0.0, 1.0));

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
    final outgoing = _ease(t / 0.42);
    final incoming = _ease((t - 0.42) / 0.58);
    final following = _ease(t);
    final travel = _ease(t);
    final lift = math.sin(math.pi * travel);
    final frontX = t < 0.42
        ? _slots[2] + (1368 - _slots[2]) * outgoing
        : 1368 * (1 - incoming);

    void draw(int color, double x, {bool moving = false}) {
      canvas.save();
      canvas.translate(x, moving ? -1286 * 0.07 * lift : 0);
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
