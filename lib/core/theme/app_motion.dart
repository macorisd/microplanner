import 'package:flutter/material.dart';

class AppMotion {
  AppMotion._();
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 220);
  static const entrance = Duration(milliseconds: 320);
  static const curve = Curves.easeOutCubic;

  static Duration duration(BuildContext context, Duration value) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : value;
}

/// Replace a state without allowing its outgoing controls to receive input/focus.
class MotionSwap extends StatelessWidget {
  final Widget? child;
  final Alignment alignment;
  final Offset slideOffset;
  const MotionSwap({
    super.key,
    this.child,
    this.alignment = Alignment.center,
    this.slideOffset = const Offset(0, 0.04),
  });

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AppMotion.duration(context, AppMotion.normal),
    reverseDuration: AppMotion.duration(context, AppMotion.fast),
    switchInCurve: AppMotion.curve,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(
      alignment: alignment,
      children: [
        for (final old in previous)
          ExcludeFocus(
            child: ExcludeSemantics(child: IgnorePointer(child: old)),
          ),
        if (current != null) current,
      ],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: slideOffset,
          end: Offset.zero,
        ).animate(animation),
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(animation),
          child: child,
        ),
      ),
    ),
    child: child,
  );
}

/// A one-time, keyed entrance; ordinary provider rebuilds do not replay it.
class MotionEntrance extends StatelessWidget {
  final Widget child;
  final Duration duration;
  const MotionEntrance({
    super.key,
    required this.child,
    this.duration = AppMotion.entrance,
  });

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: AppMotion.duration(context, duration),
    curve: AppMotion.curve,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - value)),
        child: child,
      ),
    ),
    child: child,
  );
}

/// Adds tactile feedback without owning or delaying a child's gesture callback.
class PressFeedback extends StatefulWidget {
  final Widget child;
  const PressFeedback({super.key, required this.child});
  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => _pressed = true),
    onPointerUp: (_) => setState(() => _pressed = false),
    onPointerCancel: (_) => setState(() => _pressed = false),
    child: AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: AppMotion.duration(context, AppMotion.fast),
      curve: Curves.easeOutBack,
      child: widget.child,
    ),
  );
}

Future<T?> showMotionDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black54,
  transitionDuration: AppMotion.duration(context, AppMotion.normal),
  pageBuilder: (context, _, _) => SafeArea(child: Builder(builder: builder)),
  transitionBuilder: (context, animation, _, child) {
    final eased = animation.drive(CurveTween(curve: AppMotion.curve));
    final spatial = animation.drive(CurveTween(curve: Curves.easeOutBack));
    return FadeTransition(
      opacity: eased,
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(spatial),
        child: child,
      ),
    );
  },
);
