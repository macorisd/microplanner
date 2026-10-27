import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/data/workspace_controller.dart';
import '../../../core/data/same_list.dart';
import '../../boards/providers/boards_provider.dart';
import '../data/models/task.dart';

class TasksProvider extends ChangeNotifier {
  final WorkspaceController workspace;
  final BoardsProvider boards;
  final DateTime Function() _now;
  List<Task> _allTasks = const [];
  List<Task> _tasks = const [];
  List<Task> _completed = const [];
  List<Task> _late = const [];
  List<Task> _upcoming = const [];
  String? _owner;
  String? _board;
  DateTime? _classifiedAt;
  DateTime? _nextBoundary;
  Timer? _clock;
  TasksProvider(this.workspace, this.boards, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    workspace.addListener(_changed);
    boards.addListener(_changed);
    _changed();
  }
  void _changed() {
    final source = workspace.snapshot.tasks;
    final now = _now();
    final dataChanged = !sameList(_allTasks, source, _sameTask);
    _allTasks = source;
    final timeChanged =
        _classifiedAt == null ||
        now.isBefore(_classifiedAt!) ||
        (_nextBoundary != null && now.isAfter(_nextBoundary!));
    if (!dataChanged &&
        !timeChanged &&
        _owner == workspace.ownerId &&
        _board == boards.currentBoardId) {
      return;
    }
    if (_owner != workspace.ownerId) {
      _tasks = _completed = _late = _upcoming = const [];
    }
    _owner = workspace.ownerId;
    _board = boards.currentBoardId;
    _classifiedAt = now;
    _tasks = _view(
      _tasks,
      source.where((task) => task.boardId == _board).toList(),
      timeChanged,
    );
    final completed = <Task>[];
    final late = <Task>[];
    final upcoming = <Task>[];
    DateTime? boundary;
    for (final task in _tasks) {
      if (task.isCompleted) {
        completed.add(task);
      } else {
        (now.isAfter(task.deadline) ? late : upcoming).add(task);
        for (final candidate in [
          task.deadline,
          task.deadline.subtract(const Duration(hours: 24)),
        ]) {
          if (!candidate.isBefore(now) &&
              (boundary == null || candidate.isBefore(boundary))) {
            boundary = candidate;
          }
        }
      }
    }
    _completed = _view(
      _completed,
      completed..sort((a, b) => _compare(b, a)),
      timeChanged,
    );
    _late = _view(_late, late..sort(_compare), timeChanged);
    _upcoming = _view(_upcoming, upcoming..sort(_compare), timeChanged);
    _nextBoundary = boundary;
    _clock?.cancel();
    if (boundary != null) {
      _clock = Timer(
        boundary.difference(now) + const Duration(milliseconds: 1),
        _changed,
      );
    }
    notifyListeners();
  }

  bool get isLoading => workspace.isLoading || workspace.isSaving;
  static List<Task> _view(List<Task> previous, List<Task> next, bool force) =>
      !force && sameList(previous, next, _sameTask)
      ? previous
      : List.unmodifiable(next);

  static bool _sameTask(Task a, Task b) =>
      a.id == b.id &&
      a.name == b.name &&
      a.deadline == b.deadline &&
      a.createdAt == b.createdAt &&
      a.isCompleted == b.isCompleted &&
      a.typeIndex == b.typeIndex &&
      a.priorityIndex == b.priorityIndex &&
      a.boardId == b.boardId &&
      a.subjectId == b.subjectId &&
      a.subject == b.subject &&
      a.description == b.description;
  List<Task> get tasks => _tasks;
  int _compare(Task a, Task b) {
    final comparison = a.deadline.compareTo(b.deadline);
    return comparison != 0
        ? comparison
        : b.priorityIndex.compareTo(a.priorityIndex);
  }

  List<Task> get completedTasks => _completed;
  List<Task> get lateTasks => _late;
  List<Task> get upcomingTasks => _upcoming;
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
    _clock?.cancel();
    workspace.removeListener(_changed);
    boards.removeListener(_changed);
    super.dispose();
  }
}
