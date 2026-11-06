import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/input_mode.dart';

ButtonStyle formActionStyle(
  BuildContext context, {
  double height = 40,
  bool secondary = false,
}) => ButtonStyle(
  minimumSize: WidgetStatePropertyAll(
    Size(
      secondary ? 48 : 64,
      math.max(height, usesTouchControls(context) ? 48 : 40),
    ),
  ),
  padding: WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: secondary ? 12 : 24, vertical: 8),
  ),
  shape: const WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
  ),
  textStyle: WidgetStatePropertyAll(
    Theme.of(
      context,
    ).textTheme.labelLarge!.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
  ),
  visualDensity: VisualDensity.standard,
  // The visible surface includes the full touch target, so footer padding also
  // measures the actual bottom/right margins rather than an invisible inset.
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

/// Shared action geometry, including equal heights with enlarged/wrapped labels.
class FormActions extends StatelessWidget {
  const FormActions({
    super.key,
    required this.children,
    this.alignment = MainAxisAlignment.end,
  });

  final List<Widget> children;
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final textStyle = theme.textTheme.labelLarge!.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      );
      var height = usesTouchControls(context) ? 48.0 : 40.0;
      for (final button in children.whereType<ButtonStyleButton>()) {
        final label = button.child;
        if (label is! Text) continue;
        final painter =
            TextPainter(
              text: TextSpan(text: label.data, style: textStyle),
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(
              maxWidth: math.max(
                1,
                constraints.maxWidth - (button is TextButton ? 24 : 48),
              ),
            );
        height = math.max(height, painter.height + 16);
        painter.dispose();
      }
      final geometry = formActionStyle(context, height: height);
      return Theme(
        data: theme.copyWith(
          textButtonTheme: TextButtonThemeData(
            style: formActionStyle(
              context,
              height: height,
              secondary: true,
            ).merge(theme.textButtonTheme.style),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: geometry.merge(theme.filledButtonTheme.style),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: geometry.merge(theme.elevatedButtonTheme.style),
          ),
        ),
        child: OverflowBar(
          alignment: alignment,
          spacing: 8,
          overflowSpacing: 8,
          overflowAlignment: OverflowBarAlignment.end,
          children: children,
        ),
      );
    },
  );
}

/// A compact, stationary action strip outside a dialog's scrolling content.
class FormFooter extends StatelessWidget {
  const FormFooter({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact =
        usesTouchControls(context) || MediaQuery.sizeOf(context).width < 600;
    return Material(
      color: AppColors.surface,
      child: Padding(
        padding: EdgeInsets.all(
          Theme.of(context).platform == TargetPlatform.windows
              ? (compact ? 8 : 12)
              : 16,
        ),
        child: child,
      ),
    );
  }
}
