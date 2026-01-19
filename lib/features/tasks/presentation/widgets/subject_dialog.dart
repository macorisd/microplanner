import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../boards/providers/boards_provider.dart';

class SubjectDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final int initialColor;
  final Function(String name, int color) onSave;

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

  void _save() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSave(_controller.text.trim(), _selectedColor);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
          Text(
            'Color',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppColors.subjectColors.map((color) {
              final isSelected = color.value == _selectedColor;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = color.value),
                child: Container(
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
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
