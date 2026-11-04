import 'package:flutter/material.dart';

/// Keep mode switches and text actions centered on the same footer row.
class PickerActions extends StatelessWidget {
  const PickerActions({
    super.key,
    required this.modeTooltip,
    required this.modeIcon,
    required this.onModeChanged,
    required this.onCancel,
    this.showApply = false,
    this.onApply,
  });
  final String modeTooltip;
  final IconData modeIcon;
  final VoidCallback? onModeChanged;
  final VoidCallback? onCancel;
  final bool showApply;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        IconButton(
          tooltip: modeTooltip,
          icon: Icon(modeIcon),
          onPressed: onModeChanged,
        ),
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            minimumSize: const Size(64, 40),
          ),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        if (showApply)
          FilledButton(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(64, 40),
            ),
            onPressed: onApply,
            child: const Text('Apply'),
          ),
      ],
    ),
  );
}
