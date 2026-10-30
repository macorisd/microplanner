import '../../../../core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'save_status.dart';
import '../../../../core/data/workspace_limits.dart';
import '../../../../core/widgets/limited_text_field.dart';
import '../../../../core/widgets/pending_action.dart';

class SubjectDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final int initialColor;
  final Future<bool> Function(String name, int color) onSave;
  final bool allowUnchanged;

  const SubjectDialog({
    super.key,
    required this.title,
    required this.initialName,
    required this.initialColor,
    required this.onSave,
    this.allowUnchanged = false,
  });

  @override
  State<SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<SubjectDialog>
    with PendingActionState<SubjectDialog> {
  late TextEditingController _controller;
  late int _selectedColor;
  bool get _saving => actionBlocked;
  bool get _canSave =>
      !_saving &&
      WorkspaceLimits.nameError(_controller.text) == null &&
      (widget.allowUnchanged ||
          _controller.text.trim() != widget.initialName.trim() ||
          _selectedColor != widget.initialColor);
  void _textChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _selectedColor = widget.initialColor;
    _controller.addListener(_textChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final saved = await submitOnce(
      () => widget.onSave(_controller.text.trim(), _selectedColor),
    );
    if (saved && mounted) closeForm();
  }

  @override
  Widget build(BuildContext context) {
    return PendingForm(
      pending: _saving,
      child: AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LimitedTextField(
              limit: WorkspaceLimits.name,
              validator: WorkspaceLimits.nameError,
              enabled: !_saving,
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Subject name',
                hintText: 'e.g., Mathematics, Physics',
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            SaveStatus(error: submissionError),
            Text(
              'Color',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AppColors.subjectColors.map((color) {
                final isSelected = color.toARGB32() == _selectedColor;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      setState(() => _selectedColor = color.toARGB32());
                    },
                    child: AnimatedContainer(
                      duration: AppMotion.duration(context, AppMotion.fast),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: AppColors.textPrimary, width: 2)
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : closeForm,
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _canSave ? _save : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
