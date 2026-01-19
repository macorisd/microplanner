import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/task.dart';
import 'task_card.dart';

/// A column in the task dashboard displaying tasks of a specific status
class TaskColumn extends StatelessWidget {
  final String title;
  final List<Task> tasks;
  final Color headerColor;
  final Color headerBackgroundColor;
  final IconData icon;
  final void Function(Task task) onToggleComplete;
  final void Function(Task task)? onDeleteTask;
  final void Function(Task task)? onEditTask;

  const TaskColumn({
    super.key,
    required this.title,
    required this.tasks,
    required this.headerColor,
    required this.headerBackgroundColor,
    required this.icon,
    required this.onToggleComplete,
    this.onDeleteTask,
    this.onEditTask,
  });

  @override
  Widget build(BuildContext context) {
    // Use gray colors when column is empty
    final isEmpty = tasks.isEmpty;
    final effectiveHeaderColor = isEmpty ? AppColors.textTertiary : headerColor;
    final effectiveHeaderBgColor = isEmpty ? AppColors.surfaceVariant : headerBackgroundColor;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            decoration: BoxDecoration(
              color: effectiveHeaderBgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusXLarge),
                topRight: Radius.circular(AppTheme.radiusXLarge),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: effectiveHeaderColor,
                  size: 22,
                ),
                const SizedBox(width: AppTheme.spacingSmall),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: effectiveHeaderColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingSmall,
                    vertical: AppTheme.spacingXSmall,
                  ),
                  decoration: BoxDecoration(
                    color: effectiveHeaderColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: effectiveHeaderColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
          ),

          // Task list
          Expanded(
            child: tasks.isEmpty
                ? _EmptyState(title: title)
                : ScrollbarTheme(
                    data: ScrollbarThemeData(
                      thumbVisibility: WidgetStateProperty.all(false),
                      trackVisibility: WidgetStateProperty.all(false),
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(AppTheme.spacingMedium),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        return TaskCard(
                          task: task,
                          hoverBorderColor: headerColor,
                          onToggleComplete: () => onToggleComplete(task),
                          onDelete: onDeleteTask != null
                              ? () => onDeleteTask!(task)
                              : null,
                          onEdit: onEditTask != null
                              ? () => onEditTask!(task)
                              : null,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Empty state shown when a column has no tasks
class _EmptyState extends StatelessWidget {
  final String title;

  const _EmptyState({required this.title});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String message;

    switch (title.toLowerCase()) {
      case 'complete':
        icon = Icons.check_circle_outline_rounded;
        message = 'No completed tasks yet';
        break;
      case 'late':
        icon = Icons.celebration_rounded;
        message = 'No overdue tasks!';
        break;
      case 'upcoming':
        icon = Icons.event_available_rounded;
        message = 'No upcoming tasks';
        break;
      default:
        icon = Icons.inbox_rounded;
        message = 'No tasks';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 48,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textTertiary,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
