import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../boards/data/models/subject.dart';
import '../../../boards/providers/boards_provider.dart';
import '../../data/models/task.dart';

/// Dialog for editing an existing task
class EditTaskDialog extends StatefulWidget {
  final Task task;
  final Future<void> Function(Task updatedTask) onSave;

  const EditTaskDialog({super.key, required this.task, required this.onSave});

  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  final _descriptionFocusNode = FocusNode();

  late DateTime _deadline;
  late TimeOfDay _deadlineTime;
  late TaskType _type;
  late TaskPriority _priority;
  String? _selectedSubjectId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.task.name);
    _descriptionController = TextEditingController(
      text: widget.task.description ?? '',
    );
    _deadline = widget.task.deadline;
    _deadlineTime = TimeOfDay(
      hour: widget.task.deadline.hour,
      minute: widget.task.deadline.minute,
    );
    _type = widget.task.type;
    _priority = widget.task.priority;
    _selectedSubjectId = widget.task.subjectId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Validate that the selected subject still exists
    if (_selectedSubjectId != null) {
      final boardsProvider = context.read<BoardsProvider>();
      final subjectExists = boardsProvider.currentBoardSubjects.any(
        (s) => s.id == _selectedSubjectId,
      );
      if (!subjectExists) {
        _selectedSubjectId = null;
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    // Combinar fecha y hora
    final deadlineWithTime = DateTime(
      _deadline.year,
      _deadline.month,
      _deadline.day,
      _deadlineTime.hour,
      _deadlineTime.minute,
    );

    final updatedTask = widget.task.copyWith(
      name: _nameController.text.trim(),
      deadline: deadlineWithTime,
      type: _type,
      priority: _priority,
      subjectId: _selectedSubjectId,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
    );

    await widget.onSave(updatedTask);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final boardsProvider = context.watch<BoardsProvider>();
    final subjects = boardsProvider.currentBoardSubjects;

    return Dialog(
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter) {
            if (!_descriptionFocusNode.hasFocus) {
              _submit();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 480,
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.edit_outlined,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingMedium),
                    Text(
                      'Edit Task',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      style: IconButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingLarge),

                // Task name
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Task name',
                    hintText: 'e.g., Math homework chapter 5',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a task name';
                    }
                    return null;
                  },
                  autofocus: true,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: AppTheme.spacingMedium),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  focusNode: _descriptionFocusNode,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'Add details about this task...',
                  ),
                  maxLines: 3,
                  minLines: 2,
                ),
                const SizedBox(height: AppTheme.spacingMedium),

                // Subject dropdown
                _buildSubjectDropdown(subjects),
                const SizedBox(height: AppTheme.spacingMedium),

                // Deadline date and time
                Row(
                  children: [
                    Expanded(child: _buildDeadlinePicker(context)),
                    const SizedBox(width: AppTheme.spacingSmall),
                    _buildTimePicker(context),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMedium),

                // Type dropdown
                _buildTypeDropdown(),
                const SizedBox(height: AppTheme.spacingMedium),

                // Priority selector
                _buildPrioritySelector(),
                const SizedBox(height: AppTheme.spacingLarge),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                      ),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: AppTheme.spacingSmall),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Save Changes'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectDropdown(List<Subject> subjects) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedSubjectId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('No Subject'),
            ),
            ...subjects.map((subject) {
              return DropdownMenuItem<String?>(
                value: subject.id,
                child: Text(subject.name),
              );
            }),
          ],
          onChanged: (value) {
            setState(() => _selectedSubjectId = value);
          },
        ),
      ),
    );
  }

  Widget _buildDeadlinePicker(BuildContext context) {
    return InkWell(
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: _deadline,
          firstDate: DateTime.now().subtract(const Duration(days: 365)),
          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
          locale: const Locale('en', 'GB'), // Week starts on Monday
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                  surface: AppColors.surface,
                  onSurface: AppColors.textPrimary,
                ),
              ),
              child: child!,
            );
          },
        );
        if (date != null) {
          setState(() => _deadline = date);
        }
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Deadline',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('EEE, MMM d, y').format(_deadline),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            const Spacer(),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePicker(BuildContext context) {
    return InkWell(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: _deadlineTime,
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: AppColors.primary,
                  onPrimary: Colors.white,
                  surface: AppColors.surface,
                  onSurface: AppColors.textPrimary,
                ),
              ),
              child: child!,
            );
          },
        );
        if (time != null) {
          setState(() => _deadlineTime = time);
        }
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.access_time_rounded,
              color: AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Time', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(
                  _deadlineTime.format(context),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TaskType>(
          value: _type,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: TaskType.values.map((type) {
            return DropdownMenuItem<TaskType>(
              value: type,
              child: Row(
                children: [
                  Icon(type.icon, size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: AppTheme.spacingSmall),
                  Text(type.label),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _type = value);
            }
          },
        ),
      ),
    );
  }

  Widget _buildPrioritySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Priority', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppTheme.spacingSmall),
        Row(
          children: TaskPriority.values.map((priority) {
            final isSelected = _priority == priority;
            String text = '';

            switch (priority) {
              case TaskPriority.low:
                text = '!';
                break;
              case TaskPriority.medium:
                text = '!!';
                break;
              case TaskPriority.high:
                text = '!!!';
                break;
            }

            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: priority != TaskPriority.high
                      ? AppTheme.spacingSmall
                      : 0,
                ),
                child: InkWell(
                  onTap: () => setState(() => _priority = priority),
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppTheme.spacingMedium,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.textSecondary.withValues(alpha: 0.1)
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusMedium,
                      ),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.textSecondary
                            : AppColors.divider,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          text,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: AppTheme.spacingXSmall),
                        Text(
                          priority.label,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: isSelected
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
