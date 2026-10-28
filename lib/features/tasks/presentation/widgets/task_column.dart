import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/workspace_controller.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_motion.dart';
import '../../../../core/utils/input_mode.dart';
import '../../data/models/task.dart';
import 'task_card.dart';

/// A column in the task dashboard displaying tasks of a specific status
class TaskColumn extends StatelessWidget {
  final String title;
  final List<Task> tasks;
  final Color headerColor;
  final Color headerBackgroundColor;
  final IconData icon;
  final FutureOr<void> Function(Task task) onToggleComplete;
  final void Function(Task task)? onDeleteTask;
  final void Function(Task task)? onEditTask;
  final Future<void> Function()? onClearCompleted;

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
    this.onClearCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final touch = usesTouchControls(context);
    final muted =
        tasks.isEmpty && Theme.of(context).platform != TargetPlatform.android;
    final effectiveHeaderColor = muted ? AppColors.textTertiary : headerColor;
    final effectiveHeaderBgColor = muted
        ? AppColors.surfaceVariant
        : headerBackgroundColor;
    final headerPadding = !touch && MediaQuery.sizeOf(context).height < 360
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
        : EdgeInsets.all(touch ? 12 : AppTheme.spacingMedium);
    final contentPadding = EdgeInsets.symmetric(vertical: headerPadding.top);

    return MotionEntrance(
      fade: false,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppTheme.radiusXLarge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              AnimatedContainer(
                duration: AppMotion.duration(context, AppMotion.normal),
                padding: EdgeInsets.symmetric(horizontal: headerPadding.left),
                decoration: BoxDecoration(
                  color: effectiveHeaderBgColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.radiusXLarge),
                    topRight: Radius.circular(AppTheme.radiusXLarge),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: contentPadding,
                        child: Row(
                          children: [
                            Icon(icon, color: effectiveHeaderColor, size: 22),
                            const SizedBox(width: AppTheme.spacingSmall),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: effectiveHeaderColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (onClearCompleted != null)
                      _ClearCompletedButton(
                        hasTasks: tasks.isNotEmpty,
                        onClear: onClearCompleted!,
                      ),
                    Padding(
                      padding: contentPadding,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingSmall,
                          vertical: AppTheme.spacingXSmall,
                        ),
                        decoration: BoxDecoration(
                          color: effectiveHeaderColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSmall,
                          ),
                        ),
                        child: MotionSwap(
                          child: Text(
                            '${tasks.length}',
                            key: ValueKey(tasks.length),
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: effectiveHeaderColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Task list
              Expanded(child: _TaskList(column: this)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearCompletedButton extends StatefulWidget {
  final bool hasTasks;
  final Future<void> Function() onClear;
  const _ClearCompletedButton({required this.hasTasks, required this.onClear});
  @override
  State<_ClearCompletedButton> createState() => _ClearCompletedButtonState();
}

class _ClearCompletedButtonState extends State<_ClearCompletedButton> {
  bool _opening = false;
  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onClear();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final writable = context.select<WorkspaceController, bool>(
      (workspace) => workspace.canWrite,
    );
    return SizedBox.square(
      dimension: usesTouchControls(context) ? 48 : 30,
      child: IconButton(
        tooltip: 'Clear Complete Tasks',
        onPressed: widget.hasTasks && writable && !_opening ? _open : null,
        padding: EdgeInsets.zero,
        color: AppColors.textSecondary,
        icon: const Icon(Icons.delete_outline_rounded, size: 18),
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
      case 'completed':
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

    if (MediaQuery.sizeOf(context).height < 360) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(icon, size: 24, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textTertiary),
          const SizedBox(height: AppTheme.spacingSmall),
          Text(
            message,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatefulWidget {
  final TaskColumn column;
  const _TaskList({required this.column});
  @override
  State<_TaskList> createState() => _TaskListState();
}

class _TaskListState extends State<_TaskList> {
  var _listKey = GlobalKey<AnimatedListState>();
  late List<Task> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.column.tasks);
  }

  @override
  void didUpdateWidget(covariant _TaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.column.tasks;
    if (_items.length == next.length &&
        List.generate(
          next.length,
          (i) => _items[i].id == next[i].id,
        ).every((same) => same)) {
      _items = List.of(next);
      return;
    }
    final state = _listKey.currentState;
    if (state == null) {
      _items = List.of(next);
      _listKey = GlobalKey<AnimatedListState>();
      return;
    }
    final ids = next.map((task) => task.id).toSet();
    if (_items.where((task) => !ids.contains(task.id)).take(21).length > 20) {
      // Bulk removal should not create an animation/controller for every row.
      _items = List.of(next);
      _listKey = GlobalKey<AnimatedListState>();
      return;
    }
    for (var i = _items.length - 1; i >= 0; i--) {
      if (!ids.contains(_items[i].id)) _remove(state, i);
    }
    for (var i = 0; i < next.length; i++) {
      final oldIndex = _items.indexWhere((task) => task.id == next[i].id);
      if (oldIndex == i) {
        _items[i] = next[i];
      } else {
        if (oldIndex >= 0) _remove(state, oldIndex);
        _items.insert(i, next[i]);
        state.insertItem(
          i,
          duration: AppMotion.duration(context, AppMotion.normal),
        );
      }
    }
  }

  void _remove(AnimatedListState state, int index) {
    final removed = _items.removeAt(index);
    state.removeItem(
      index,
      (_, animation) => IgnorePointer(
        child: ExcludeSemantics(
          child: _transition(removed, animation, removed: true),
        ),
      ),
      duration: AppMotion.duration(context, AppMotion.fast),
    );
  }

  Widget _transition(
    Task task,
    Animation<double> animation, {
    bool removed = false,
  }) {
    final column = widget.column;
    return SizeTransition(
      sizeFactor: animation.drive(CurveTween(curve: AppMotion.curve)),
      axisAlignment: -1,
      child: FadeTransition(
        opacity: animation,
        child: TaskCard(
          key: ValueKey(task.id),
          task: task,
          hoverBorderColor: column.headerColor,
          onToggleComplete: removed
              ? () {}
              : () => column.onToggleComplete(task),
          onEdit: column.onEditTask != null
              ? (removed ? () {} : () => column.onEditTask!(task))
              : null,
          onDelete: column.onDeleteTask != null
              ? (removed ? () {} : () => column.onDeleteTask!(task))
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: ScrollbarTheme(
          data: ScrollbarThemeData(
            thumbVisibility: WidgetStateProperty.all(false),
            trackVisibility: WidgetStateProperty.all(false),
          ),
          child: AnimatedList(
            key: _listKey,
            initialItemCount: _items.length,
            padding: EdgeInsets.fromLTRB(
              usesTouchControls(context) ? 8 : AppTheme.spacingMedium,
              usesTouchControls(context) ? 8 : AppTheme.spacingMedium,
              usesTouchControls(context) ? 8 : AppTheme.spacingMedium,
              MediaQuery.sizeOf(context).height < 360
                  ? 64
                  : (usesTouchControls(context) ? 8 : AppTheme.spacingMedium),
            ),
            itemBuilder: (_, index, animation) =>
                _transition(_items[index], animation),
          ),
        ),
      ),
      if (_items.isEmpty)
        Positioned.fill(
          child: IgnorePointer(
            child: MotionEntrance(
              child: _EmptyState(title: widget.column.title),
            ),
          ),
        ),
    ],
  );
}
