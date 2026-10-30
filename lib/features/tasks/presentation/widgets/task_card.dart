import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/utils/input_mode.dart';
import '../../../boards/providers/boards_provider.dart';
import '../../../boards/data/models/subject.dart';
import '../../data/models/task.dart';
import '../../providers/tasks_provider.dart';
import 'task_transition_visual.dart';

/// Android edits through the card; completion and deletion stay independent.
class TaskCard extends StatefulWidget {
  final Task task;
  final FutureOr<void> Function() onToggleComplete;
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
  static final _dateFormat = DateFormat('EEE dd/MM');
  static final _timeFormat = DateFormat('HH:mm');
  final _hovered = ValueNotifier(false);
  bool _toggling = false;

  Future<void> _toggle() async {
    if (_toggling ||
        (context.read<TasksProvider?>()?.transitions.locked(widget.task.id) ??
            false) ||
        (context.read<WorkspaceController?>()?.outbox?.pendingTaskIds.contains(
              widget.task.id,
            ) ??
            false)) {
      return;
    }
    setState(() => _toggling = true);
    try {
      await widget.onToggleComplete();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not update this task. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchControls(context);
    final visual = context.select<TasksProvider?, TaskVisual?>((provider) {
      final transition = provider?.transitions[widget.task.id];
      if (transition == null) return null;
      return (
        phase: transition.phase,
        target: transition.to,
        beforeCompleted: transition.before?.isCompleted ?? false,
        afterCompleted: transition.after?.isCompleted ?? false,
        started: transition.started,
        phaseAt: transition.phaseAt,
      );
    });
    final pending =
        visual != null ||
        context.select<WorkspaceController?, bool>(
          (workspace) =>
              workspace?.outbox?.pendingTaskIds.contains(widget.task.id) ??
              false,
        );
    final android = Theme.of(context).platform == TargetPlatform.android;
    final showEdit = !android && widget.onEdit != null;
    final task = widget.task;
    final hasActions = showEdit || widget.onDelete != null;
    final actionWidth =
        48.0 * ((showEdit ? 1 : 0) + (widget.onDelete != null ? 1 : 0));
    final actions = ValueListenableBuilder<bool>(
      valueListenable: _hovered,
      builder: (context, hovered, _) {
        final showActions = touch || hovered;
        return IgnorePointer(
          ignoring: !showActions,
          child: ExcludeSemantics(
            excluding: !showActions,
            child: AnimatedOpacity(
              duration: AppMotion.duration(context, AppMotion.fast),
              opacity: showActions ? 1 : 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showEdit)
                    _ActionButton(
                      icon: Icons.edit_outlined,
                      tooltip: 'Edit',
                      onPressed: showActions && !pending ? widget.onEdit : null,
                      touch: touch,
                    ),
                  if (widget.onDelete != null)
                    _ActionButton(
                      icon: Icons.delete_outline_rounded,
                      tooltip: 'Delete',
                      onPressed: showActions && !pending
                          ? widget.onDelete
                          : null,
                      touch: touch,
                    ),
                ],
              ),
            ),
          ),
        );
      },
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
      enabled: !_toggling && !pending,
      child: InkResponse(
        onTap: _toggling || pending ? null : _toggle,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        borderRadius: BorderRadius.circular(6),
        radius: touch ? 24 : 16,
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
      onEnter: (_) => _hovered.value = true,
      onExit: (_) => _hovered.value = false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
        child: ValueListenableBuilder<bool>(
          valueListenable: _hovered,
          builder: (context, hovered, child) => AnimatedContainer(
            duration: AppMotion.duration(context, AppMotion.fast),
            curve: AppMotion.curve,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              boxShadow: AppTheme.cardShadow,
              border: Border.all(
                color: hovered
                    ? widget.hoverBorderColor ??
                          AppColors.primary.withValues(alpha: 0.3)
                    : AppColors.divider,
              ),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
          child: Builder(
            builder: (context) {
              final content = InkWell(
                onTap: pending
                    ? null
                    : (android ? widget.onEdit ?? widget.onTap : widget.onTap),
                borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                child: Stack(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(
                        touch ? 12 : AppTheme.spacingMedium,
                      ),
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
                              SizedBox(
                                width: touch ? 12 : AppTheme.spacingMedium,
                              ),
                              Expanded(
                                child: visual == null
                                    ? Text(
                                        task.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              decoration: task.isCompleted
                                                  ? TextDecoration.lineThrough
                                                  : null,
                                              color: task.isCompleted
                                                  ? AppColors.textTertiary
                                                  : AppColors.textPrimary,
                                            ),
                                      )
                                    : AnimatedTaskTitle(
                                        text: task.name,
                                        completed: task.isCompleted,
                                        visual: visual,
                                        style:
                                            (Theme.of(
                                                      context,
                                                    ).textTheme.titleMedium ??
                                                    const TextStyle())
                                                .copyWith(
                                                  color: task.isCompleted
                                                      ? AppColors.textTertiary
                                                      : AppColors.textPrimary,
                                                ),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: touch ? 24 : 30,
                                child: Center(
                                  heightFactor: 1,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: _PriorityIndicator(
                                      priority: task.priority,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppTheme.spacingSmall),
                          Selector<BoardsProvider, Subject?>(
                            selector: (_, boards) =>
                                boards.getSubjectById(task.subjectId),
                            builder: (context, subject, _) {
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
                                            if (task.type !=
                                                TaskType.unassigned)
                                              _detail(
                                                context,
                                                task.type.icon,
                                                task.type.label,
                                                AppColors.textSecondary,
                                              ),
                                            _detail(
                                              context,
                                              Icons.calendar_today_rounded,
                                              _dateFormat.format(task.deadline),
                                              dateColor,
                                            ),
                                            _detail(
                                              context,
                                              Icons.access_time_rounded,
                                              _timeFormat.format(task.deadline),
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
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal:
                                                          AppTheme.spacingSmall,
                                                      vertical: AppTheme
                                                          .spacingXSmall,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Color(
                                                    subject?.color ??
                                                        0xFFF0F0F2,
                                                  ).withValues(alpha: 0.2),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        AppTheme.radiusSmall,
                                                      ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
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
                                                        overflow: TextOverflow
                                                            .ellipsis,
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
              );
              return visual == null
                  ? content
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                      child: TaskTransitionVisual(
                        visual: visual,
                        child: content,
                      ),
                    );
            },
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
  Widget build(BuildContext context) => AnimatedContainer(
    duration: AppMotion.duration(context, AppMotion.fast),
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
    child: MotionSwap(
      child: completed
          ? const Icon(
              Icons.check_rounded,
              key: ValueKey('checked'),
              size: 16,
              color: Colors.white,
            )
          : const SizedBox.shrink(key: ValueKey('unchecked')),
    ),
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
  Widget build(BuildContext context) => PressFeedback(
    child: SizedBox.square(
      dimension: touch ? 48 : 30,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: AppColors.textSecondary),
      ),
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
