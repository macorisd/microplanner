import 'package:flutter/material.dart';
import '../../../../core/widgets/disclosure_icon.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/input_mode.dart';
import 'task_form_keyboard.dart';

/// Common form proportions for account pages and customization dialogs.
class EditorPanel extends StatelessWidget {
  const EditorPanel({
    super.key,
    required this.child,
    this.dialog = false,
    this.onSubmit,
    this.canSubmit = false,
  });
  final Widget child;
  final bool dialog;
  final VoidCallback? onSubmit;
  final bool canSubmit;

  @override
  Widget build(BuildContext context) {
    final compact =
        usesTouchControls(context) || MediaQuery.sizeOf(context).width < 600;
    final contents = SingleChildScrollView(
      padding: EdgeInsets.all(
        compact ? AppTheme.spacingMedium : AppTheme.spacingLarge,
      ),
      child: child,
    );
    if (dialog) {
      final panel = Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 40,
          vertical: 24,
        ),
        child: SizedBox(width: 480, child: contents),
      );
      return onSubmit == null
          ? panel
          : TaskFormKeyboard(
              canSubmit: canSubmit,
              onSubmit: onSubmit!,
              child: panel,
            );
    }
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(
          compact ? AppTheme.spacingMedium : AppTheme.spacingLarge,
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: EdgeInsets.all(
            compact ? AppTheme.spacingMedium : AppTheme.spacingLarge,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
            boxShadow: AppTheme.cardShadow,
          ),
          child: child,
        ),
      ),
    );
  }
}

class EditorHeading extends StatelessWidget {
  const EditorHeading({
    super.key,
    required this.title,
    required this.icon,
    this.onBack,
    this.onClose,
  });
  final String title;
  final IconData icon;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (onBack != null)
        IconButton(
          tooltip: 'Back',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        )
      else
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary),
        ),
      const SizedBox(width: AppTheme.spacingMedium),
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
      ),
      if (onClose != null)
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded),
        ),
    ],
  );
}

class SettingsEntry extends StatelessWidget {
  const SettingsEntry({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.onTap,
    this.trailing,
  });
  final String title;
  final IconData icon;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surfaceVariant,
    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
    child: ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? const DisclosureIcon(right: true),
      onTap: onTap,
    ),
  );
}
