import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import '../../boards/providers/boards_provider.dart';
import '../data/models/task.dart';

/// Provider for task management with Hive persistence
class TasksProvider extends ChangeNotifier {
  static const String _boxName = 'tasks';
  static const String _defaultBoardId = 'default-board';
  final Uuid _uuid = const Uuid();
  
  Box<Task>? _tasksBox;
  List<Task> _allTasks = [];
  BoardsProvider? _boardsProvider;
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  /// All tasks in the current board
  List<Task> get tasks {
    final currentBoardId = _boardsProvider?.currentBoardId;
    if (currentBoardId == null) return [];
    return _allTasks.where((t) => t.boardId == currentBoardId).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Filtered task getters (filtered by current board)
  // ─────────────────────────────────────────────────────────────────────────
  
  /// Tasks that have been marked as completed
  List<Task> get completedTasks {
    final completed = tasks.where((task) => task.isCompleted).toList();
    completed.sort((a, b) => b.deadline.compareTo(a.deadline));
    return completed;
  }

  /// Tasks that are overdue (past deadline, not completed)
  List<Task> get lateTasks {
    final late = tasks.where((task) => task.isLate).toList();
    late.sort((a, b) => a.deadline.compareTo(b.deadline));
    return late;
  }

  /// Tasks with upcoming deadlines (future, not completed)
  List<Task> get upcomingTasks {
    final upcoming = tasks.where((task) => task.isUpcoming).toList();
    upcoming.sort((a, b) => a.deadline.compareTo(b.deadline));
    return upcoming;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Initialization
  // ─────────────────────────────────────────────────────────────────────────
  
  /// Initialize Hive and load tasks
  Future<void> init(BoardsProvider boardsProvider) async {
    _boardsProvider = boardsProvider;
    _isLoading = true;
    notifyListeners();

    try {
      _tasksBox = await Hive.openBox<Task>(_boxName);
      _loadTasks();
      
      // Migrate tasks without boardId to default board
      await _migrateTasksToDefaultBoard();
      
      // Listen to board changes
      _boardsProvider?.addListener(_onBoardChanged);
    } catch (e) {
      debugPrint('Error initializing tasks: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void _onBoardChanged() {
    notifyListeners();
  }

  Future<void> _migrateTasksToDefaultBoard() async {
    final tasksWithoutBoard = _allTasks.where((t) => t.boardId == null).toList();
    for (final task in tasksWithoutBoard) {
      task.boardId = _defaultBoardId;
      await task.save();
    }
    if (tasksWithoutBoard.isNotEmpty) {
      _loadTasks();
    }
  }

  void _loadTasks() {
    if (_tasksBox != null) {
      _allTasks = _tasksBox!.values.toList();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CRUD Operations
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a new task
  Future<void> addTask({
    required String name,
    required DateTime deadline,
    required TaskType type,
    required TaskPriority priority,
    String? subjectId,
    String? description,
  }) async {
    final currentBoardId = _boardsProvider?.currentBoardId;
    if (currentBoardId == null) return;

    // Si la hora es 00:00, usar 23:55 por defecto
    DateTime finalDeadline = deadline;
    if (deadline.hour == 0 && deadline.minute == 0) {
      finalDeadline = DateTime(
        deadline.year,
        deadline.month,
        deadline.day,
        23,
        55,
      );
    }

    final task = Task.create(
      id: _uuid.v4(),
      name: name,
      deadline: finalDeadline,
      type: type,
      priority: priority,
      subjectId: subjectId,
      boardId: currentBoardId,
      description: description,
    );

    await _tasksBox?.put(task.id, task);
    _loadTasks();
    notifyListeners();
  }

  /// Update an existing task
  Future<void> updateTask(Task task) async {
    await _tasksBox?.put(task.id, task);
    _loadTasks();
    notifyListeners();
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    await _tasksBox?.delete(taskId);
    _loadTasks();
    notifyListeners();
  }

  /// Toggle task completion status
  Future<void> toggleTaskCompletion(String taskId) async {
    final task = _tasksBox?.get(taskId);
    if (task != null) {
      task.isCompleted = !task.isCompleted;
      await task.save();
      _loadTasks();
      notifyListeners();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cleanup
  // ─────────────────────────────────────────────────────────────────────────

  /// Clear all tasks (for testing or logout)
  Future<void> clearAllTasks() async {
    await _tasksBox?.clear();
    _loadTasks();
    notifyListeners();
  }

  @override
  void dispose() {
    _boardsProvider?.removeListener(_onBoardChanged);
    super.dispose();
  }
}
