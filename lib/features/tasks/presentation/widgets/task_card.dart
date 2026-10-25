import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/input_mode.dart';
import '../../../boards/providers/boards_provider.dart';
import '../../data/models/task.dart';

/// A task's details and actions, with persistent controls on touch platforms.
class TaskCard extends StatefulWidget {
  final Task task;
  final VoidCallback onToggleComplete;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final Color? hoverBorderColor;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggleComplete,
    this.onTap,
    this.onDelete,
    this.onEdit,
    this.hoverBorderColor,
  });

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchControls(context);
    final showActions = touch || _isHovered;
    final task = widget.task;
    final hasActions = widget.onEdit != null || widget.onDelete != null;
    final actionWidth =
        48.0 *
        ((widget.onEdit != null ? 1 : 0) + (widget.onDelete != null ? 1 : 0));
    final actions = IgnorePointer(
      ignoring: !showActions,
      child: ExcludeSemantics(
        excluding: !showActions,
        child: Opacity(
          opacity: showActions ? 1 : 0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onEdit != null)
                _ActionButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit',
                  onPressed: showActions ? widget.onEdit : null,
                  touch: touch,
                ),
              if (widget.onDelete != null)
                _ActionButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete',
                  onPressed: showActions ? widget.onDelete : null,
                  touch: touch,
                ),
            ],
          ),
        ),
      ),
    );
    final hoursUntilDeadline = task.deadline.difference(DateTime.now()).inHours;
    final urgent =
        !task.isCompleted && hoursUntilDeadline >= 0 && hoursUntilDeadline < 24;
    final dateColor = task.isLate || urgent
        ? AppColors.error
        : AppColors.textSecondary;
    final completion = Semantics(
      label: task.isCompleted ? 'Mark task incomplete' : 'Mark task complete',
      checked: task.isCompleted,
      child: InkResponse(
        onTap: widget.onToggleComplete,
        child: SizedBox.square(
          dimension: touch ? 48 : 24,
          child: touch ? null : _CompletionMark(completed: task.isCompleted),
        ),
      ),
    );
    // Touch targets occupy the card's padding instead of stretching content rows.
    final actionSlot = touch
        ? SizedBox(width: hasActions ? actionWidth - 12 : 0, height: 24)
        : actions;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
          boxShadow: AppTheme.cardShadow,
          border: Border.all(
            color: _isHovered
                ? widget.hoverBorderColor ??
                      AppColors.primary.withValues(alpha: 0.3)
                : AppColors.divider,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.all(touch ? 12 : AppTheme.spacingMedium),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: touch
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.center,
                        children: [
                          if (touch)
                            _CompletionMark(completed: task.isCompleted)
                          else
                            completion,
                          SizedBox(width: touch ? 12 : AppTheme.spacingMedium),
                          Expanded(
                            child: Text(
                              task.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    decoration: task.isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                    color: task.isCompleted
                                        ? AppColors.textTertiary
                                        : AppColors.textPrimary,
                                  ),
                            ),
                          ),
                          _PriorityIndicator(priority: task.priority),
                        ],
                      ),
                      const SizedBox(height: AppTheme.spacingSmall),
                      Consumer<BoardsProvider>(
                        builder: (context, boards, _) {
                          final subject = boards.getSubjectById(task.subjectId);
                          final subjectName = subject?.name ?? task.subject;
                          final hasSubject = subjectName.isNotEmpty;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Wrap(
                                      spacing: AppTheme.spacingSmall,
                                      runSpacing: AppTheme.spacingXSmall,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        if (task.type != TaskType.unassigned)
                                          _detail(
                                            context,
                                            task.type.icon,
                                            task.type.label,
                                            AppColors.textSecondary,
                                          ),
                                        _detail(
                                          context,
                                          Icons.calendar_today_rounded,
                                          DateFormat(
                                            'EEE dd/MM',
                                          ).format(task.deadline),
                                          dateColor,
                                        ),
                                        _detail(
                                          context,
                                          Icons.access_time_rounded,
                                          DateFormat(
                                            'HH:mm',
                                          ).format(task.deadline),
                                          dateColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (!hasSubject && hasActions) actionSlot,
                                ],
                              ),
                              if (hasSubject)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: AppTheme.spacingSmall,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: AppTheme.spacingSmall,
                                              vertical: AppTheme.spacingXSmall,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Color(
                                                subject?.color ?? 0xFFF0F0F2,
                                              ).withValues(alpha: 0.2),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppTheme.radiusSmall,
                                                  ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: Color(
                                                      subject?.color ??
                                                          0xFF9094A6,
                                                    ),
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Flexible(
                                                  child: Text(
                                                    subjectName,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelMedium
                                                        ?.copyWith(
                                                          color: AppColors
                                                              .textSecondary,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (hasActions) actionSlot,
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (touch) Positioned(top: 0, left: 0, child: completion),
                if (touch && hasActions)
                  Positioned(bottom: 0, right: 0, child: actions),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(
    BuildContext context,
    IconData icon,
    String label,
    Color color,
  ) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
        ),
      ),
    ],
  );
}

class _CompletionMark extends StatelessWidget {
  final bool completed;

  const _CompletionMark({required this.completed});

  @override
  Widget build(BuildContext context) => Container(
    width: 24,
    height: 24,
    decoration: BoxDecoration(
      color: completed ? AppColors.success : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        width: 2,
        color: completed ? AppColors.success : AppColors.textTertiary,
      ),
    ),
    child: completed
        ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
        : null,
  );
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool touch;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.touch,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: touch ? 48 : 30,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 18, color: AppColors.textSecondary),
    ),
  );
}

/// Small colored dot indicating task priority
/// Exclamation marks indicating task priority
class _PriorityIndicator extends StatelessWidget {
  final TaskPriority priority;

  const _PriorityIndicator({required this.priority});

  @override
  Widget build(BuildContext context) {
    String text;
    switch (priority) {
      case TaskPriority.high:
        text = '!!!';
        break;
      case TaskPriority.medium:
        text = '!!';
        break;
      case TaskPriority.low:
        text = '!';
        break;
    }

    return Tooltip(
      message: '${priority.label} priority',
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w800,
          letterSpacing: 1,
          fontSize: 12,
        ),
      ),
    );
  }
}
