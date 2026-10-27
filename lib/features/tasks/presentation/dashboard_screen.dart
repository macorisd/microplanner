import 'widgets/action_confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/data/workspace_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/utils/input_mode.dart';
import '../../boards/providers/boards_provider.dart';
import '../data/models/task.dart';
import '../providers/tasks_provider.dart';
import 'widgets/add_task_dialog.dart';
import 'widgets/android_board_carousel.dart';
import 'widgets/edit_task_dialog.dart';
import 'widgets/sidebar.dart';
import 'widgets/task_column.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final android = Theme.of(context).platform == TargetPlatform.android;
    final backInset = MediaQuery.systemGestureInsetsOf(context).left;
    final compact = android || MediaQuery.sizeOf(context).width < 850;
    final short = MediaQuery.sizeOf(context).height < 360;
    final workspace = context.watch<WorkspaceController>();
    final boardName =
        context.select<BoardsProvider, String?>(
          (boards) => boards.currentBoard?.name,
        ) ??
        'My Tasks';
    final refresh = IconButton(
      tooltip: 'Refresh cloud data',
      onPressed: workspace.isLoading || workspace.isSaving
          ? null
          : workspace.refresh,
      icon: const Icon(Icons.refresh),
    );
    return Scaffold(
      appBar: compact
          ? AppBar(
              toolbarHeight: short ? 48 : null,
              title: MotionSwap(
                child: Text(
                  boardName,
                  key: ValueKey(boardName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              actions: [refresh],
            )
          : null,
      drawer: compact
          ? const Drawer(child: SafeArea(child: Sidebar(inDrawer: true)))
          : null,
      // Some Android skins report zero for the Back inset. Keep a small fallback
      // so an inward drag just beyond that OS-owned strip can reach the drawer.
      // This does not exclude or override the system Back gesture.
      drawerEdgeDragWidth: android
          ? 36 + (backInset < 20 ? 20 : backInset)
          : null,
      body: Row(
        children: [
          if (!compact) const Sidebar(),
          Expanded(
            child: Container(
              color: AppColors.background,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!compact)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingLarge,
                        vertical: AppTheme.spacingMedium,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: MotionSwap(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                boardName,
                                key: ValueKey(boardName),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.displaySmall,
                              ),
                            ),
                          ),
                          refresh,
                        ],
                      ),
                    ),
                  const Expanded(child: _TaskArea()),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: android
          ? null
          : PressFeedback(
              child: short
                  ? FloatingActionButton.small(
                      tooltip: 'New Task',
                      onPressed: workspace.canWrite
                          ? () => _add(context)
                          : null,
                      child: const Icon(Icons.add_rounded),
                    )
                  : FloatingActionButton.extended(
                      onPressed: workspace.canWrite
                          ? () => _add(context)
                          : null,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New Task'),
                    ),
            ),
    );
  }

  static List<Widget> _taskColumns(BuildContext context) {
    Widget column(
      String title,
      List<Task> Function(TasksProvider) select,
      Color color,
      Color background,
      IconData icon,
    ) => Selector<TasksProvider, (String?, String?, List<Task>)>(
      selector: (_, provider) => (
        provider.workspace.ownerId,
        provider.boards.currentBoardId,
        select(provider),
      ),
      shouldRebuild: (previous, next) =>
          previous.$1 != next.$1 ||
          previous.$2 != next.$2 ||
          !identical(previous.$3, next.$3),
      builder: (context, view, _) {
        final provider = context.read<TasksProvider>();
        return TaskColumn(
          key: ValueKey('${view.$1}:${view.$2}:$title'),
          title: title,
          tasks: view.$3,
          headerColor: color,
          headerBackgroundColor: background,
          icon: icon,
          onToggleComplete: (task) => provider.toggleTaskCompletion(task.id),
          onDeleteTask: (task) => _delete(context, task),
          onEditTask: (task) => _edit(context, task),
        );
      },
    );
    return [
      column(
        Theme.of(context).platform == TargetPlatform.android
            ? 'Completed'
            : 'Complete',
        (provider) => provider.completedTasks,
        AppColors.completeHeader,
        AppColors.completeHeaderLight,
        Icons.check_circle_rounded,
      ),
      column(
        'Late',
        (provider) => provider.lateTasks,
        AppColors.lateHeader,
        AppColors.lateHeaderLight,
        Icons.warning_rounded,
      ),
      column(
        'Upcoming',
        (provider) => provider.upcomingTasks,
        AppColors.upcomingHeader,
        AppColors.upcomingHeaderLight,
        Icons.schedule_rounded,
      ),
    ];
  }

  static void _add(BuildContext context) {
    final provider = context.read<TasksProvider>();
    showMotionDialog(
      context: context,
      builder: (_) => AddTaskDialog(onSave: provider.addTask),
    );
  }

  static void _edit(BuildContext context, Task task) {
    if (!context.read<WorkspaceController>().canWrite) return;
    final provider = context.read<TasksProvider>();
    showMotionDialog(
      context: context,
      builder: (_) => EditTaskDialog(task: task, onSave: provider.updateTask),
    );
  }

  static void _delete(BuildContext context, Task task) {
    if (!context.read<WorkspaceController>().canWrite) return;
    final provider = context.read<TasksProvider>();
    showMotionDialog(
      context: context,
      builder: (_) => ActionConfirmationDialog(
        actionLabel: 'Delete',
        pendingLabel: 'Deleting…',
        destructive: true,
        title: 'Delete Task',
        message: 'Are you sure you want to delete "${task.name}"?',
        onConfirm: () => provider.deleteTask(task.id),
      ),
    );
  }
}

/// Cloud status changes do not rebuild or re-sort the task workspace.
class _TaskArea extends StatefulWidget {
  const _TaskArea();
  @override
  State<_TaskArea> createState() => _TaskAreaState();
}

class _TaskAreaState extends State<_TaskArea> {
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = DashboardScreen._taskColumns(context);
      if (Theme.of(context).platform == TargetPlatform.android) {
        final identity = context.select<BoardsProvider, (String?, String?)>(
          (boards) => (boards.workspace.ownerId, boards.currentBoardId),
        );
        return AndroidBoardCarousel(
          key: ValueKey(identity),
          columns: columns,
          onAdd: () => DashboardScreen._add(context),
        );
      }
      if (MediaQuery.sizeOf(context).width < 850 &&
          usesTouchControls(context)) {
        return _TouchColumns(columns: columns);
      }
      final width = constraints.maxWidth < 900 ? 900.0 : constraints.maxWidth;
      final overflow = width > constraints.maxWidth;
      return ScrollbarTheme(
        data: const ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(AppColors.textTertiary),
        ),
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: overflow,
          trackVisibility: overflow,
          notificationPredicate: (notice) => notice.depth == 0,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  0,
                  24,
                  constraints.maxHeight < 300 ? 12 : 80,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < columns.length; i++) ...[
                      if (i > 0) const SizedBox(width: 16),
                      Expanded(child: columns[i]),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Wide touch columns snap into place while revealing the next page.
class _TouchColumns extends StatefulWidget {
  final List<Widget> columns;

  const _TouchColumns({required this.columns});

  @override
  State<_TouchColumns> createState() => _TouchColumnsState();
}

class _TouchColumnsState extends State<_TouchColumns> {
  final _controller = PageController(viewportFraction: 0.92);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView(
    controller: _controller,
    children: [
      for (final column in widget.columns)
        Padding(padding: const EdgeInsets.fromLTRB(6, 8, 6, 80), child: column),
    ],
  );
}
