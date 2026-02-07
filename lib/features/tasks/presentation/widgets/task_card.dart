import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../boards/providers/boards_provider.dart';
import '../../data/models/task.dart';

/// Card widget displaying a single task
/// Shows name, deadline, type, priority, and subject
class TaskCard extends StatefulWidget {
  final Task task;
  final VoidCallback onToggleComplete;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final Color? hoverBorderColor; // New parameter for hover color

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
                ? (widget.hoverBorderColor ?? AppColors.primary.withValues(alpha: 0.3)) 
                : AppColors.divider,
            width: 1,
            // Draw outside to prevent layout shift? No, Border.all is inside. 
            // Just ensure consistent width.
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
            child: Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: Checkbox + Name + Priority
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Checkbox with pointer cursor
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: widget.onToggleComplete,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: widget.task.isCompleted
                                  ? AppColors.success
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: widget.task.isCompleted
                                    ? AppColors.success
                                    : AppColors.textTertiary,
                                width: 2,
                              ),
                            ),
                            child: widget.task.isCompleted
                                ? const Icon(
                                    Icons.check_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingMedium),

                      // Task name
                      Expanded(
                        child: Text(
                          widget.task.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                decoration: widget.task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: widget.task.isCompleted
                                    ? AppColors.textTertiary
                                    : AppColors.textPrimary,
                              ),
                        ),
                      ),

                      // Priority indicator
                      _PriorityIndicator(priority: widget.task.priority),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingSmall),

                  // Second row: Type + Date + Time (+ Action buttons if no subject)
                  Consumer<BoardsProvider>(
                    builder: (context, boardsProvider, _) {
                      // Check if task has a subject
                      final subject = boardsProvider.getSubjectById(widget.task.subjectId);
                      final subjectName = subject?.name ?? widget.task.subject;
                      final hasSubject = subjectName.isNotEmpty;
                      final hasButtons = widget.onEdit != null || widget.onDelete != null;
                      
                      // Check if deadline is within 24 hours or already late
                      final now = DateTime.now();
                      final hoursUntilDeadline = widget.task.deadline.difference(now).inHours;
                      final isUrgent = !widget.task.isCompleted && hoursUntilDeadline < 24 && hoursUntilDeadline >= 0;
                      final showRed = widget.task.isLate || isUrgent;
                      
                      return Row(
                        children: [
                          Icon(
                            widget.task.type.icon,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: AppTheme.spacingXSmall),
                          Text(
                            widget.task.type.label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(width: AppTheme.spacingSmall),
                          // Calendar icon + weekday + date
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 14,
                            color: showRed
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('EEE dd/MM').format(widget.task.deadline),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: showRed
                                      ? AppColors.error
                                      : AppColors.textSecondary,
                                ),
                          ),
                          const SizedBox(width: AppTheme.spacingSmall),
                          // Clock icon + time
                          Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: showRed
                                ? AppColors.error
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('HH:mm').format(widget.task.deadline),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: showRed
                                      ? AppColors.error
                                      : AppColors.textSecondary,
                                ),
                          ),
                          // Action buttons only if NO subject (buttons go in 3rd row if has subject)
                          if (!hasSubject && hasButtons) ...[
                            const Spacer(),
                            Opacity(
                              opacity: _isHovered ? 1.0 : 0.0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.onEdit != null)
                                      _ActionButton(
                                        icon: Icons.edit_outlined,
                                        tooltip: 'Edit',
                                        onPressed: _isHovered ? widget.onEdit : null,
                                        color: AppColors.textSecondary,
                                      ),
                                    if (widget.onDelete != null)
                                      _ActionButton(
                                        icon: Icons.delete_outline_rounded,
                                        tooltip: 'Delete',
                                        onPressed: _isHovered ? widget.onDelete : null,
                                        color: AppColors.textSecondary,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  // Third row: Subject chip + Action buttons (only if has subject)
                  Consumer<BoardsProvider>(
                    builder: (context, boardsProvider, _) {
                      final subject = boardsProvider.getSubjectById(widget.task.subjectId);
                      final subjectName = subject?.name ?? widget.task.subject;
                      final hasSubject = subjectName.isNotEmpty;
                      final hasButtons = widget.onEdit != null || widget.onDelete != null;
                      
                      // If no subject, don't show this row (buttons are in 2nd row)
                      if (!hasSubject) {
                        return const SizedBox.shrink();
                      }
                      
                      return Padding(
                        padding: const EdgeInsets.only(top: AppTheme.spacingSmall),
                        child: Row(
                          children: [
                            // Subject chip
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppTheme.spacingSmall,
                                vertical: AppTheme.spacingXSmall,
                              ),
                              decoration: BoxDecoration(
                                color: Color(subject?.color ?? 0xFFF0F0F2).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Color(subject?.color ?? 0xFF9094A6),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    subjectName,
                                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            // Action buttons (visible on hover)
                            if (hasButtons)
                              Opacity(
                                opacity: _isHovered ? 1.0 : 0.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (widget.onEdit != null)
                                        _ActionButton(
                                          icon: Icons.edit_outlined,
                                          tooltip: 'Edit',
                                          onPressed: _isHovered ? widget.onEdit : null,
                                          color: AppColors.textSecondary,
                                        ),
                                      if (widget.onDelete != null)
                                        _ActionButton(
                                          icon: Icons.delete_outline_rounded,
                                          tooltip: 'Delete',
                                          onPressed: _isHovered ? widget.onDelete : null,
                                          color: AppColors.textSecondary,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small action button for edit/delete
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;

  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Icon(
              icon,
              size: 18,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
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
