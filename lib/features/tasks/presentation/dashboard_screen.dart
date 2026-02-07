import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../boards/providers/boards_provider.dart';
import '../data/models/task.dart';
import '../providers/tasks_provider.dart';
import 'widgets/add_task_dialog.dart';
import 'widgets/edit_task_dialog.dart';
import 'widgets/sidebar.dart';
import 'widgets/task_column.dart';

/// Main dashboard screen with 3-column task board
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          const Sidebar(),

          // Main content area
          Expanded(
            child: Container(
              color: AppColors.background,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingLarge,
                      vertical: AppTheme.spacingMedium,
                    ),
                    child: Row(
                      children: [
                        Consumer<BoardsProvider>(
                          builder: (context, boardsProvider, _) {
                            final boardName =
                                boardsProvider.currentBoard?.name ?? 'My Tasks';
                            return Text(
                              boardName,
                              style: Theme.of(context).textTheme.displaySmall,
                            );
                          },
                        ),
                        const Spacer(),
                        // Refresh indicator
                        Consumer<TasksProvider>(
                          builder: (context, provider, _) {
                            if (provider.isLoading) {
                              return const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ),
                  ),

                  // Task columns
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppTheme.spacingLarge,
                        0,
                        AppTheme.spacingLarge,
                        AppTheme.spacingLarge,
                      ),
                      child: Consumer<TasksProvider>(
                        builder: (context, provider, _) {
                          return Row(
                            children: [
                              // Complete column
                              Expanded(
                                child: TaskColumn(
                                  title: 'Complete',
                                  tasks: provider.completedTasks,
                                  headerColor: AppColors.completeHeader,
                                  headerBackgroundColor:
                                      AppColors.completeHeaderLight,
                                  icon: Icons.check_circle_rounded,
                                  onToggleComplete: (task) {
                                    provider.toggleTaskCompletion(task.id);
                                  },
                                  onDeleteTask: (task) {
                                    _showDeleteConfirmDialog(context, task);
                                  },
                                  onEditTask: (task) {
                                    _showEditTaskDialog(context, task);
                                  },
                                ),
                              ),
                              const SizedBox(width: AppTheme.spacingMedium),

                              // Late column
                              Expanded(
                                child: TaskColumn(
                                  title: 'Late',
                                  tasks: provider.lateTasks,
                                  headerColor: AppColors.lateHeader,
                                  headerBackgroundColor:
                                      AppColors.lateHeaderLight,
                                  icon: Icons.warning_rounded,
                                  onToggleComplete: (task) {
                                    provider.toggleTaskCompletion(task.id);
                                  },
                                  onDeleteTask: (task) {
                                    _showDeleteConfirmDialog(context, task);
                                  },
                                  onEditTask: (task) {
                                    _showEditTaskDialog(context, task);
                                  },
                                ),
                              ),
                              const SizedBox(width: AppTheme.spacingMedium),

                              // Upcoming column
                              Expanded(
                                child: TaskColumn(
                                  title: 'Upcoming',
                                  tasks: provider.upcomingTasks,
                                  headerColor: AppColors.upcomingHeader,
                                  headerBackgroundColor:
                                      AppColors.upcomingHeaderLight,
                                  icon: Icons.schedule_rounded,
                                  onToggleComplete: (task) {
                                    provider.toggleTaskCompletion(task.id);
                                  },
                                  onDeleteTask: (task) {
                                    _showDeleteConfirmDialog(context, task);
                                  },
                                  onEditTask: (task) {
                                    _showEditTaskDialog(context, task);
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTaskDialog(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Task'),
      ),
    );
  }

  void _showAddTaskDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AddTaskDialog(
        onSave:
            ({
              required String name,
              required DateTime deadline,
              required type,
              required priority,
              String? subjectId,
              String? description,
            }) async {
              await context.read<TasksProvider>().addTask(
                name: name,
                deadline: deadline,
                type: type,
                priority: priority,
                subjectId: subjectId,
                description: description,
              );
            },
      ),
    );
  }

  void _showEditTaskDialog(BuildContext context, Task task) {
    showDialog(
      context: context,
      builder: (dialogContext) => EditTaskDialog(
        task: task,
        onSave: (updatedTask) async {
          await context.read<TasksProvider>().updateTask(updatedTask);
        },
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, Task task) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Task'),
        content: Text('Are you sure you want to delete "${task.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              context.read<TasksProvider>().deleteTask(task.id);
              Navigator.of(dialogContext).pop();
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
