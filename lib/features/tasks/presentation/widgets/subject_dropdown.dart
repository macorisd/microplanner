import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../boards/data/models/subject.dart';

/// The same color/name pairing is used in the selected field and its menu.
class SubjectDropdown extends StatelessWidget {
  final List<Subject> subjects;
  final String? value;
  final ValueChanged<String?> onChanged;
  const SubjectDropdown({
    super.key,
    required this.subjects,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
    decoration: BoxDecoration(
      color: AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: value,
        isExpanded: true,
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: AppColors.textSecondary,
        ),
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('No Subject'),
          ),
          for (final subject in subjects)
            DropdownMenuItem<String?>(
              value: subject.id,
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Color(subject.color),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.divider),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subject.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        onChanged: onChanged,
      ),
    ),
  );
}
