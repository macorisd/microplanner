import '../../../../core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'save_status.dart';

class SubjectDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final int initialColor;
  final Future<bool> Function(String name, int color) onSave;

  const SubjectDialog({
    super.key,
    required this.title,
    required this.initialName,
    required this.initialColor,
    required this.onSave,
  });

  @override
  State<SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends State<SubjectDialog> {
  late TextEditingController _controller;
  late int _selectedColor;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_controller.text.trim().isNotEmpty) {
      setState(() => _saving = true);
      final saved = await widget.onSave(
        _controller.text.trim(),
        _selectedColor,
      );
      if (!mounted) return;
      if (saved) {
        Navigator.of(context).pop();
      } else {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Subject name',
              hintText: 'e.g., Mathematics, Physics',
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          const SaveStatus(),
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
                  onTap: () =>
                      setState(() => _selectedColor = color.toARGB32()),
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
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
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
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
