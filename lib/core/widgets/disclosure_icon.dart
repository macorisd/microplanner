import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Use the same rounded chevron for every selector and disclosure control.
class DisclosureIcon extends StatelessWidget {
  const DisclosureIcon({
    super.key,
    this.right = false,
    this.color = AppColors.textSecondary,
  });
  final bool right;
  final Color color;

  @override
  Widget build(BuildContext context) => RotatedBox(
    quarterTurns: right ? 3 : 0,
    child: Icon(Icons.keyboard_arrow_down_rounded, color: color, size: 24),
  );
}
