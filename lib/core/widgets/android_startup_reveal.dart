import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'animated_app_logo.dart';

/// Prepare the destination before moving; only the cover repaints during zoom.
class AndroidStartupReveal extends StatefulWidget {
  final int column;
  final Widget child;
  const AndroidStartupReveal({
    super.key,
    required this.column,
    required this.child,
  });
  static const duration = Duration(milliseconds: 600);

  @override
  State<AndroidStartupReveal> createState() => _AndroidStartupRevealState();
}

class _AndroidStartupRevealState extends State<AndroidStartupReveal>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: AndroidStartupReveal.duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _done = true);
          }
        });
  late final _column = widget.column.clamp(0, 2);
  bool _started = false;
  bool _done = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _done = true;
    } else if (!_started && !_done) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_done) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ExcludeSemantics(
        excluding: !_done,
        child: IgnorePointer(
          ignoring: !_done,
          child: RepaintBoundary(child: widget.child),
        ),
      ),
      if (!_done)
        Positioned.fill(
          child: Semantics(
            label:
                'Opening ${const ['Completed', 'Late', 'Upcoming'][_column]}',
            liveRegion: true,
            child: RepaintBoundary(
              key: const ValueKey('startup-zoom-overlay'),
              child: CustomPaint(painter: _ZoomPainter(_controller, _column)),
            ),
          ),
        ),
    ],
  );
}

class _ZoomPainter extends CustomPainter {
  final Animation<double> progress;
  final int column;
  _ZoomPainter(this.progress, this.column) : super(repaint: progress);
  double _ease(double value) =>
      Curves.easeInOutCubic.transform(value.clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    final eased = _ease(p);
    final height = AppLogoArt.heightForViewport(size);
    final base = height / AppLogoArt.sourceSize.height;
    final cover = math.max(1.0, size.longestSide * 2 / (764 * base));
    final zoom = math.exp(math.log(cover) * eased);
    final backgroundAlpha = 1 - _ease((p - 0.62) / 0.18);
    final sheetAlpha = 1 - _ease((p - 0.80) / 0.20);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawColor(
      AppColors.background.withValues(alpha: backgroundAlpha),
      BlendMode.srcOver,
    );
    final focusX = 645 + (AppLogoArt.slots[column] + 382 - 645) * eased;
    canvas.translate(
      size.width / 2 - focusX * base * zoom,
      size.height / 2 - 643 * base * zoom,
    );
    canvas.scale(base * zoom);
    for (var i = 0; i < 3; i++) {
      final alpha = sheetAlpha * (i == column ? 1 : 1 - _ease(p / 0.20));
      if (alpha <= 0) continue;
      canvas.save();
      canvas.translate(AppLogoArt.slots[i], 0);
      canvas.drawRRect(
        AppLogoArt.leaf,
        Paint()..color = AppLogoArt.colors[i].withValues(alpha: alpha),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ZoomPainter oldDelegate) =>
      progress != oldDelegate.progress || column != oldDelegate.column;
}
