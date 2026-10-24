import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/data/workspace_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../boards/providers/boards_provider.dart';
import '../data/models/task.dart';
import '../providers/tasks_provider.dart';
import 'widgets/add_task_dialog.dart';
import 'widgets/edit_task_dialog.dart';
import 'widgets/sidebar.dart';
import 'widgets/task_column.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 850;
    final workspace = context.watch<WorkspaceController>();
    return Scaffold(
      appBar: compact ? AppBar(title: const Text('microplanner')) : null,
      drawer: compact
          ? const Drawer(child: SafeArea(child: Sidebar(inDrawer: true)))
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
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingLarge,
                      vertical: AppTheme.spacingMedium,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context
                                    .watch<BoardsProvider>()
                                    .currentBoard
                                    ?.name ??
                                'My Tasks',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                        ),
                        if (workspace.isLoading || workspace.isSaving)
                          const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        IconButton(
                          tooltip: 'Refresh cloud data',
                          onPressed: workspace.isLoading || workspace.isSaving
                              ? null
                              : workspace.refresh,
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth < 900
                            ? 900.0
                            : constraints.maxWidth;
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: width,
                            height: constraints.maxHeight,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(24, 0, 24, 80),
                              child: _columns(context),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: workspace.canWrite ? () => _add(context) : null,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Task'),
      ),
    );
  }

  Widget _columns(BuildContext context) {
    final provider = context.watch<TasksProvider>();
    Widget column(
      String title,
      List<Task> tasks,
      Color color,
      Color background,
      IconData icon,
    ) => Expanded(
      child: TaskColumn(
        title: title,
        tasks: tasks,
        headerColor: color,
        headerBackgroundColor: background,
        icon: icon,
        onToggleComplete: (task) => provider.toggleTaskCompletion(task.id),
        onDeleteTask: (task) => _delete(context, task),
        onEditTask: (task) => _edit(context, task),
      ),
    );
    return Row(
      children: [
        column(
          'Complete',
          provider.completedTasks,
          AppColors.completeHeader,
          AppColors.completeHeaderLight,
          Icons.check_circle_rounded,
        ),
        const SizedBox(width: AppTheme.spacingMedium),
        column(
          'Late',
          provider.lateTasks,
          AppColors.lateHeader,
          AppColors.lateHeaderLight,
          Icons.warning_rounded,
        ),
        const SizedBox(width: AppTheme.spacingMedium),
        column(
          'Upcoming',
          provider.upcomingTasks,
          AppColors.upcomingHeader,
          AppColors.upcomingHeaderLight,
          Icons.schedule_rounded,
        ),
      ],
    );
  }

  void _add(BuildContext context) {
    final provider = context.read<TasksProvider>();
    showDialog(
      context: context,
      builder: (_) => AddTaskDialog(onSave: provider.addTask),
    );
  }

  void _edit(BuildContext context, Task task) {
    if (!context.read<WorkspaceController>().canWrite) return;
    final provider = context.read<TasksProvider>();
    showDialog(
      context: context,
      builder: (_) => EditTaskDialog(task: task, onSave: provider.updateTask),
    );
  }

  void _delete(BuildContext context, Task task) {
    if (!context.read<WorkspaceController>().canWrite) return;
    final provider = context.read<TasksProvider>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (await provider.deleteTask(task.id) && dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            autofocus: true,
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
