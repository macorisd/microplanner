import 'package:flutter/material.dart';

/// Reserves message space so validation and save failures do not resize forms.
/// Longer messages remain readable by scrolling, tooltip and accessibility.
class FormMessage extends StatelessWidget {
  const FormMessage({super.key, this.message, this.lines = 1});
  final String? message;
  final int lines;

  static double heightOf(BuildContext context, {int lines = 1}) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.error);
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height * lines;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.error);
    return SizedBox(
      height: heightOf(context, lines: lines),
      child: message == null
          ? null
          : Semantics(
              liveRegion: true,
              child: Tooltip(
                message: message!,
                child: SingleChildScrollView(
                  child: Text(message!, style: style),
                ),
              ),
            ),
    );
  }
}
