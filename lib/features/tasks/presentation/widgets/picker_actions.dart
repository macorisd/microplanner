import 'package:flutter/material.dart';
import '../../../../core/utils/input_mode.dart';
import '../../../../core/widgets/form_actions.dart';

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
          style: IconButton.styleFrom(
            minimumSize: Size.square(usesTouchControls(context) ? 48 : 40),
            padding: const EdgeInsets.all(8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
          ),
          tooltip: modeTooltip,
          icon: Icon(modeIcon),
          onPressed: onModeChanged,
        ),
        TextButton(
          onPressed: onCancel,
          style: formActionStyle(
            context,
            secondary: true,
          ).merge(TextButton.styleFrom(foregroundColor: Colors.red.shade700)),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        if (showApply)
          FilledButton(
            style: formActionStyle(context),
            onPressed: onApply,
            child: const Text('Apply'),
          ),
      ],
    ),
  );
}
