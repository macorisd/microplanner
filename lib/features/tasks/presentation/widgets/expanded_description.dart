import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/data/workspace_limits.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/input_mode.dart';
import '../../../../core/widgets/limited_text_field.dart';

/// A compact trailing control with the same inset as the form dropdown arrows.
class DescriptionExpandButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const DescriptionExpandButton({super.key, this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 56,
    child: Center(
      widthFactor: 1,
      heightFactor: 1,
      child: IconButton(
        tooltip: 'Expand description',
        onPressed: onPressed,
        icon: const Icon(Icons.open_in_full_rounded, size: 20),
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          padding: EdgeInsets.zero,
        ),
      ),
    ),
  );
}

/// A second view of the same draft, within the original form's dialog frame.
Future<void> expandDescription(
  BuildContext context,
  TextEditingController controller, {
  required String taskName,
  required GlobalKey panelKey,
}) async {
  final panel = panelKey.currentContext?.findRenderObject() as RenderBox?;
  final panelSize = panel?.size ?? const Size(480, 600);
  FocusManager.instance.primaryFocus?.unfocus();
  await showDialog<void>(
    context: context,
    // The parent form already provides the modal scrim.
    barrierColor: Colors.transparent,
    builder: (_) => _ExpandedDescription(
      controller: controller,
      taskName: taskName.trim().isEmpty ? 'New Task' : taskName.trim(),
      panelSize: panelSize,
    ),
  );
  if (context.mounted) FocusManager.instance.primaryFocus?.unfocus();
}

class _ExpandedDescription extends StatelessWidget {
  final TextEditingController controller;
  final String taskName;
  final Size panelSize;
  const _ExpandedDescription({
    required this.controller,
    required this.taskName,
    required this.panelSize,
  });

  @override
  Widget build(BuildContext context) {
    final compact =
        usesTouchControls(context) || MediaQuery.sizeOf(context).width < 600;
    final short = MediaQuery.sizeOf(context).height < 420;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: compact ? 16 : 40,
            vertical: short ? 12 : 24,
          ),
          child: SizedBox(
            key: const ValueKey('expanded-description-panel'),
            width: panelSize.width,
            height: panelSize.height,
            child: Padding(
              padding: EdgeInsets.all(compact ? 16 : AppTheme.spacingLarge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: BackButton(
                          color: AppColors.textSecondary,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingMedium),
                      Expanded(
                        child: Text(
                          taskName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingLarge),
                  Expanded(
                    child: LimitedTextField(
                      controller: controller,
                      limit: WorkspaceLimits.description,
                      validator: WorkspaceLimits.descriptionError,
                      maxLines: null,
                      expands: true,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'Add details about this task...',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
