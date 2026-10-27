import '../../../../core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/input_mode.dart';
import '../../../boards/data/models/subject.dart';
import '../../../boards/providers/boards_provider.dart';
import 'save_status.dart';
import '../../../../core/data/workspace_limits.dart';
import '../../../../core/widgets/limited_text_field.dart';
import '../../../../core/widgets/pending_action.dart';
import '../../../../core/utils/task_date_range.dart';
import 'subject_dropdown.dart';
import 'task_date_picker.dart';

/// Dialog for creating a new task
/// All fields are displayed in a clean, Cashew-inspired form
class AddTaskDialog extends StatefulWidget {
  final Future<bool> Function({
    required String name,
    required DateTime deadline,
    required TaskType type,
    required TaskPriority priority,
    String? subjectId,
    String? description,
  })
  onSave;

  const AddTaskDialog({super.key, required this.onSave});

  @override
  State<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends State<AddTaskDialog>
    with PendingActionState<AddTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _descriptionFocusNode = FocusNode();

  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _deadlineTime = const TimeOfDay(hour: 23, minute: 55);
  TaskType _type = TaskType.unassigned;
  TaskPriority _priority = TaskPriority.low;
  String? _selectedSubjectId;
  bool get _isLoading => actionBlocked;

  void _textChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_textChanged);
    _descriptionController.addListener(_textChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;

    // Combine date and time
    final deadlineWithTime = DateTime(
      _deadline.year,
      _deadline.month,
      _deadline.day,
      _deadlineTime.hour,
      _deadlineTime.minute,
    );

    final saved = await submitOnce(
      () => widget.onSave(
        name: _nameController.text.trim(),
        deadline: deadlineWithTime,
        type: _type,
        priority: _priority,
        subjectId: _selectedSubjectId,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
      ),
    );

    if (!mounted) return;
    if (saved) {
      closeForm();
    }
  }

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchControls(context);
    final compact = touch || MediaQuery.sizeOf(context).width < 600;
    final short = MediaQuery.sizeOf(context).height < 420;
    final boardsProvider = context.watch<BoardsProvider>();
    final subjects = boardsProvider.currentBoardSubjects;
    if (_selectedSubjectId != null &&
        !subjects.any((s) => s.id == _selectedSubjectId)) {
      _selectedSubjectId = null;
    }

    return PendingForm(
      pending: _isLoading,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 40,
          vertical: short ? 12 : 24,
        ),
        child: Focus(
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
          child: SingleChildScrollView(
            child: Container(
              width: 480,
              padding: EdgeInsets.all(compact ? 16 : AppTheme.spacingLarge),
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
                            Icons.add_task_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingMedium),
                        Expanded(
                          child: Text(
                            'New Task',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        IconButton(
                          onPressed: _isLoading ? null : closeForm,
                          icon: const Icon(Icons.close_rounded),
                          style: IconButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingLarge),

                    // Task name
                    LimitedTextField(
                      controller: _nameController,
                      limit: WorkspaceLimits.name,
                      enabled: !_isLoading,
                      decoration: const InputDecoration(
                        labelText: 'Task name',
                        hintText: 'e.g., Math homework chapter 5',
                      ),
                      validator: WorkspaceLimits.nameError,
                      autofocus: true,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppTheme.spacingMedium),

                    // Description
                    LimitedTextField(
                      controller: _descriptionController,
                      limit: WorkspaceLimits.description,
                      validator: WorkspaceLimits.descriptionError,
                      enabled: !_isLoading,
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
                    if (MediaQuery.sizeOf(context).width < 600) ...[
                      _buildDeadlinePicker(context),
                      const SizedBox(height: AppTheme.spacingSmall),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildTimePicker(context),
                      ),
                    ] else
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
                    SaveStatus(error: submissionError),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: AppTheme.spacingSmall,
                      children: [
                        TextButton(
                          onPressed: _isLoading ? null : closeForm,
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                          ),
                          child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                          onPressed:
                              _isLoading ||
                                  WorkspaceLimits.nameError(
                                        _nameController.text,
                                      ) !=
                                      null ||
                                  WorkspaceLimits.descriptionError(
                                        _descriptionController.text,
                                      ) !=
                                      null
                              ? null
                              : _submit,
                          child: isSubmitting
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
                              : const Text('Create Task'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectDropdown(List<Subject> subjects) => SubjectDropdown(
    subjects: subjects,
    value: _selectedSubjectId,
    onChanged: (value) => setState(() => _selectedSubjectId = value),
  );

  Widget _buildDeadlinePicker(BuildContext context) {
    return InkWell(
      onTap: () async {
        final range = TaskDateRange(_deadline);
        final date = await pickOnce(
          () => showTaskDatePicker(
            context: context,
            initialDate: range.initial,
            initialEntryMode:
                MediaQuery.sizeOf(context).width < 400 &&
                    !usesTouchControls(context)
                ? DatePickerEntryMode.inputOnly
                : DatePickerEntryMode.calendar,
            firstDate: range.first,
            lastDate: range.last,
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
                child: MediaQuery.sizeOf(context).height < 520
                    ? SingleChildScrollView(child: child!)
                    : child!,
              );
            },
          ),
        );
        if (date != null && mounted) {
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Deadline',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('EEE, MMM d, y').format(_deadline),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
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
        final time = await pickOnce(
          () => showTimePicker(
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
                child: MediaQuery.sizeOf(context).height < 520
                    ? SingleChildScrollView(child: child!)
                    : child!,
              );
            },
          ),
        );
        if (time != null && mounted) {
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
            // Use gray colors for selected state but slightly darker/distinct
            // Actually user wants gray exclamation marks.
            // Let's use subtle backgrounds for selection to keep it clean.

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
                    duration: AppMotion.duration(context, AppMotion.fast),
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
