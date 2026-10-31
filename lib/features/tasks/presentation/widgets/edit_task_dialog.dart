import 'expanded_description.dart';
import 'task_form_keyboard.dart';
import '../../../../core/theme/app_motion.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/input_mode.dart';
import '../../../boards/data/models/subject.dart';
import '../../../boards/providers/boards_provider.dart';
import '../../data/models/task.dart';
import 'save_status.dart';
import '../../../../core/data/workspace_limits.dart';
import '../../../../core/widgets/limited_text_field.dart';
import '../../../../core/widgets/pending_action.dart';
import '../../../../core/utils/task_date_range.dart';
import 'subject_dropdown.dart';
import 'task_date_picker.dart';

/// Dialog for editing an existing task
class EditTaskDialog extends StatefulWidget {
  final Task task;
  final Task? draft;
  final Future<bool> Function(Task updatedTask) onSave;

  const EditTaskDialog({
    super.key,
    required this.task,
    required this.onSave,
    this.draft,
  });

  @override
  State<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends State<EditTaskDialog>
    with PendingActionState<EditTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _panelKey = GlobalKey();
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  final _descriptionFocusNode = FocusNode();

  late DateTime _deadline;
  late TimeOfDay _deadlineTime;
  late TaskType _type;
  late TaskPriority _priority;
  String? _selectedSubjectId;
  bool get _isLoading => actionBlocked;
  bool get _canSubmit =>
      !_isLoading &&
      _hasChanges &&
      WorkspaceLimits.nameError(_nameController.text) == null &&
      WorkspaceLimits.descriptionError(_descriptionController.text) == null;

  void _textChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    final draft = widget.draft ?? widget.task;
    _nameController = TextEditingController(text: draft.name);
    _descriptionController = TextEditingController(
      text: draft.description ?? '',
    );
    _deadline = draft.deadline;
    _deadlineTime = TimeOfDay(
      hour: draft.deadline.hour,
      minute: draft.deadline.minute,
    );
    _type = draft.type;
    _priority = draft.priority;
    _selectedSubjectId = draft.subjectId;
    _nameController.addListener(_textChanged);
    _descriptionController.addListener(_textChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Validate that the selected subject still exists
    if (_selectedSubjectId != null) {
      final boardsProvider = context.read<BoardsProvider>();
      final subjectExists = boardsProvider.subjects
          .where((s) => s.boardId == widget.task.boardId)
          .any((s) => s.id == _selectedSubjectId);
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
    if (!_canSubmit) return;
    if (!_formKey.currentState!.validate()) return;

    final deadlineWithTime = _selectedDeadline;

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

    final saved = await submitOnce(() => widget.onSave(updatedTask));
    if (!mounted) return;
    if (saved) {
      closeForm();
    }
  }

  DateTime get _selectedDeadline {
    final old = widget.task.deadline;
    if (_deadline.year == old.year &&
        _deadline.month == old.month &&
        _deadline.day == old.day &&
        _deadlineTime.hour == old.hour &&
        _deadlineTime.minute == old.minute) {
      return old;
    }
    return DateTime(
      _deadline.year,
      _deadline.month,
      _deadline.day,
      _deadlineTime.hour,
      _deadlineTime.minute,
    );
  }

  bool get _hasChanges =>
      _nameController.text.trim() != widget.task.name.trim() ||
      _descriptionController.text.trim() !=
          (widget.task.description?.trim() ?? '') ||
      _selectedDeadline != widget.task.deadline ||
      _type != widget.task.type ||
      _priority != widget.task.priority ||
      _selectedSubjectId != widget.task.subjectId;

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchControls(context);
    final compact = touch || MediaQuery.sizeOf(context).width < 600;
    final short = MediaQuery.sizeOf(context).height < 420;
    final boardsProvider = context.watch<BoardsProvider>();
    final subjects = boardsProvider.subjects
        .where((s) => s.boardId == widget.task.boardId)
        .toList();
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
        child: TaskFormKeyboard(
          descriptionFocus: _descriptionFocusNode,
          canSubmit: _canSubmit,
          onSubmit: _submit,
          child: SingleChildScrollView(
            child: Container(
              key: _panelKey,
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
                            Icons.edit_outlined,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingMedium),
                        Expanded(
                          child: Text(
                            'Edit Task',
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
                      decoration: InputDecoration(
                        suffixIcon: DescriptionExpandButton(
                          onPressed: _isLoading
                              ? null
                              : () => pickOnce<void>(
                                  () => expandDescription(
                                    context,
                                    _descriptionController,
                                    taskName: _nameController.text,
                                    panelKey: _panelKey,
                                  ),
                                ),
                        ),
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
                          onPressed: _canSubmit ? _submit : null,
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
                              : const Text('Save Changes'),
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
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
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
                  onTap: () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    setState(() => _priority = priority);
                  },
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
