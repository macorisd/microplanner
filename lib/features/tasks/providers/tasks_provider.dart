import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/data/workspace_controller.dart';
import '../../boards/providers/boards_provider.dart';
import '../data/models/task.dart';

class TasksProvider extends ChangeNotifier {
  final WorkspaceController workspace;
  final BoardsProvider boards;
  TasksProvider(this.workspace, this.boards) {
    workspace.addListener(_changed);
    boards.addListener(_changed);
  }
  void _changed() => notifyListeners();
  bool get isLoading => workspace.isLoading || workspace.isSaving;
  List<Task> get tasks => workspace.snapshot.tasks
      .where((t) => t.boardId == boards.currentBoardId)
      .toList();
  int _compare(Task a, Task b) {
    final comparison = a.deadline.compareTo(b.deadline);
    return comparison != 0
        ? comparison
        : b.priorityIndex.compareTo(a.priorityIndex);
  }

  List<Task> get completedTasks =>
      tasks.where((t) => t.isCompleted).toList()
        ..sort((a, b) => _compare(b, a));
  List<Task> get lateTasks =>
      tasks.where((t) => t.isLate).toList()..sort(_compare);
  List<Task> get upcomingTasks =>
      tasks.where((t) => t.isUpcoming).toList()..sort(_compare);
  Future<bool> addTask({
    required String name,
    required DateTime deadline,
    required TaskType type,
    required TaskPriority priority,
    String? subjectId,
    String? description,
  }) async {
    final boardId = boards.currentBoardId;
    if (boardId == null) return false;
    final finalDeadline = deadline.hour == 0 && deadline.minute == 0
        ? DateTime(deadline.year, deadline.month, deadline.day, 23, 55)
        : deadline;
    final task = Task.create(
      id: const Uuid().v4(),
      name: name,
      deadline: finalDeadline,
      type: type,
      priority: priority,
      subjectId: subjectId,
      boardId: boardId,
      description: description,
    );
    return workspace.mutate((s) => s.copyWith(tasks: [...s.tasks, task]));
  }

  Future<bool> updateTask(Task task) => workspace.mutate(
    (s) => s.copyWith(
      tasks: s.tasks.map((t) => t.id == task.id ? task : t).toList(),
    ),
  );
  Future<bool> deleteTask(String id) => workspace.mutate(
    (s) => s.copyWith(tasks: s.tasks.where((t) => t.id != id).toList()),
  );
  Future<bool> toggleTaskCompletion(String id) => workspace.mutate(
    (s) => s.copyWith(
      tasks: s.tasks
          .map((t) => t.id == id ? t.copyWith(isCompleted: !t.isCompleted) : t)
          .toList(),
    ),
  );
  @override
  void dispose() {
    workspace.removeListener(_changed);
    boards.removeListener(_changed);
    super.dispose();
  }
}
