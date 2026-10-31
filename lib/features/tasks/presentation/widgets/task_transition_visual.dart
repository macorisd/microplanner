import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/task_transitions.dart';

typedef TaskVisual = ({
  TaskTransitionPhase phase,
  TaskColumnKind? target,
  bool beforeCompleted,
  bool afterCompleted,
  DateTime started,
  DateTime phaseAt,
});

Color _color(TaskColumnKind? target) => switch (target) {
  TaskColumnKind.completed => AppColors.completeHeader,
  TaskColumnKind.late => AppColors.lateHeader,
  TaskColumnKind.upcoming => AppColors.upcomingHeader,
  null => AppColors.error,
};

double _fraction(Duration elapsed, Duration total) =>
    (elapsed.inMicroseconds / total.inMicroseconds).clamp(0.0, 1.0);

@visibleForTesting
double taskTransitionStrength(TaskVisual state, DateTime now) {
  final base = _fraction(
    now.difference(state.started),
    TaskTransitions.baseDuration,
  );
  if (state.phase == TaskTransitionPhase.source ||
      state.phase == TaskTransitionPhase.creating) {
    return Curves.easeOutCubic.transform(base);
  }
  if (state.phase == TaskTransitionPhase.destination) {
    final fade = _fraction(
      now.difference(state.phaseAt) - TaskTransitions.destinationHoldDuration,
      TaskTransitions.destinationDuration -
          TaskTransitions.destinationHoldDuration,
    );
    return 1 - Curves.easeOutCubic.transform(fade);
  }
  final elapsed = _fraction(
    now.difference(state.phaseAt),
    TaskTransitions.settleDuration,
  );
  final initial = state.phase == TaskTransitionPhase.rollback
      ? Curves.easeOutCubic.transform(
          _fraction(
            state.phaseAt.difference(state.started),
            TaskTransitions.baseDuration,
          ),
        )
      : 1.0;
  return initial * (1 - Curves.easeOutCubic.transform(elapsed));
}

double _strike(TaskVisual state, DateTime now) {
  final from = state.beforeCompleted ? 1.0 : 0.0;
  final to = state.afterCompleted ? 1.0 : 0.0;
  if (state.phase == TaskTransitionPhase.destination ||
      state.phase == TaskTransitionPhase.creating) {
    return to;
  }
  final progress = Curves.easeInOutCubic.transform(
    _fraction(now.difference(state.started), TaskTransitions.baseDuration),
  );
  if (state.phase == TaskTransitionPhase.source) {
    return from + (to - from) * progress;
  }
  final atFailure = Curves.easeInOutCubic.transform(
    _fraction(
      state.phaseAt.difference(state.started),
      TaskTransitions.baseDuration,
    ),
  );
  final reverse = Curves.easeInOutCubic.transform(
    _fraction(now.difference(state.phaseAt), TaskTransitions.settleDuration),
  );
  return (from + (to - from) * atFailure) * (1 - reverse) + from * reverse;
}

/// Only mounted cards animate; the coordinator finishes offscreen transitions.
class TaskTransitionVisual extends StatefulWidget {
  final TaskVisual visual;
  final Widget child;
  const TaskTransitionVisual({
    super.key,
    required this.visual,
    required this.child,
  });
  @override
  State<TaskTransitionVisual> createState() => _TaskTransitionVisualState();
}

class _TaskTransitionVisualState extends State<TaskTransitionVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();
  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _NebulaPainter(widget.visual, reduced, _clock),
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _NebulaPainter extends CustomPainter {
  final TaskVisual visual;
  final bool reduced;
  final Animation<double> clock;
  _NebulaPainter(this.visual, this.reduced, this.clock)
    : super(repaint: reduced ? null : clock);
  @override
  void paint(Canvas canvas, Size size) {
    final strength = reduced
        ? (visual.phase == TaskTransitionPhase.source ||
                  visual.phase == TaskTransitionPhase.creating
              ? 0.45
              : 0.0)
        : taskTransitionStrength(visual, DateTime.now());
    if (strength <= 0) return;
    final color = _color(visual.target);
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()..color = color.withValues(alpha: 0.24 * strength),
    );
    final motion = reduced ? 0.0 : math.sin(clock.value * math.pi * 2);
    final gradient = RadialGradient(
      center: Alignment(-0.5 + motion * 0.6, -0.35),
      radius: 1.1,
      colors: [
        color.withValues(alpha: 0.32 * strength),
        color.withValues(alpha: 0.06 * strength),
        Colors.transparent,
      ],
    );
    canvas.drawRect(bounds, Paint()..shader = gradient.createShader(bounds));
  }

  @override
  bool shouldRepaint(covariant _NebulaPainter oldDelegate) =>
      oldDelegate.visual != visual || oldDelegate.reduced != reduced;
}

class AnimatedTaskTitle extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool completed;
  final TaskVisual? visual;
  const AnimatedTaskTitle({
    super.key,
    required this.text,
    required this.style,
    required this.completed,
    required this.visual,
  });
  @override
  State<AnimatedTaskTitle> createState() => _AnimatedTaskTitleState();
}

class _AnimatedTaskTitleState extends State<AnimatedTaskTitle>
    with SingleTickerProviderStateMixin {
  AnimationController? _clock;
  bool _reduced = false;

  void _syncClock() {
    if (widget.visual == null || _reduced) {
      _clock?.stop();
      return;
    }
    final clock = _clock ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (!clock.isAnimating) clock.repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context);
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant AnimatedTaskTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncClock();
  }

  @override
  void dispose() {
    _clock?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visual = widget.visual;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return CustomPaint(
      foregroundPainter: _StrikePainter(
        text: widget.text,
        style: widget.style,
        direction: Directionality.of(context),
        scaler: MediaQuery.textScalerOf(context),
        visual: visual,
        completed: widget.completed,
        reduced: reduced,
        clock: _clock,
      ),
      child: Text(widget.text, style: widget.style),
    );
  }
}

class _StrikePainter extends CustomPainter {
  final String text;
  final TextStyle style;
  final TextDirection direction;
  final TextScaler scaler;
  final TaskVisual? visual;
  final bool completed, reduced;
  final Animation<double>? clock;
  _StrikePainter({
    required this.text,
    required this.style,
    required this.direction,
    required this.scaler,
    required this.visual,
    required this.completed,
    required this.reduced,
    required this.clock,
  }) : super(repaint: visual == null || reduced ? null : clock);
  @override
  void paint(Canvas canvas, Size size) {
    final value = visual == null || reduced
        ? (completed ? 1.0 : 0.0)
        : _strike(visual!, DateTime.now());
    if (value <= 0) return;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: size.width);
    final lines = painter.computeLineMetrics();
    final total = lines.fold<double>(0, (sum, line) => sum + line.width);
    var remaining = total * value;
    final completingAtSource =
        visual != null &&
        (visual!.phase == TaskTransitionPhase.source ||
            visual!.phase == TaskTransitionPhase.rollback) &&
        !visual!.beforeCompleted &&
        visual!.afterCompleted;
    final paint = Paint()
      ..color = completingAtSource
          ? Colors.black
          : style.decorationColor ?? style.color ?? AppColors.textPrimary
      ..strokeWidth = 1.3;
    for (final line in lines) {
      final width = remaining.clamp(0.0, line.width);
      final y = line.baseline - line.ascent * 0.32;
      canvas.drawLine(
        Offset(line.left, y),
        Offset(line.left + width, y),
        paint,
      );
      remaining -= line.width;
    }
    painter.dispose();
  }

  @override
  bool shouldRepaint(covariant _StrikePainter old) =>
      old.visual != visual ||
      old.text != text ||
      old.style != style ||
      old.completed != completed ||
      old.scaler != scaler ||
      old.direction != direction ||
      old.reduced != reduced;
}
