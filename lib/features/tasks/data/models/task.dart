import 'package:hive/hive.dart';
import '../../../../core/constants/app_constants.dart';

part 'task.g.dart';

/// Task model representing a homework, test, or other academic assignment
@HiveType(typeId: 0)
class Task extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  DateTime deadline;

  @HiveField(3)
  int typeIndex; // Stored as int, converted to TaskType

  @HiveField(4)
  int priorityIndex; // Stored as int, converted to TaskPriority

  @HiveField(5)
  String subject; // Legacy field for migration, now stores subjectId

  @HiveField(6)
  bool isCompleted;

  @HiveField(7)
  final DateTime createdAt;

  @HiveField(8)
  String? boardId;

  @HiveField(9)
  String? subjectId;

  @HiveField(10)
  String? description;

  Task({
    required this.id,
    required this.name,
    required this.deadline,
    required this.typeIndex,
    required this.priorityIndex,
    required this.subject,
    this.isCompleted = false,
    required this.createdAt,
    this.boardId,
    this.subjectId,
    this.description,
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Convenience getters for enum types
  // ─────────────────────────────────────────────────────────────────────────
  TaskType get type => TaskType.values[typeIndex];
  set type(TaskType value) => typeIndex = value.index;

  TaskPriority get priority => TaskPriority.values[priorityIndex];
  set priority(TaskPriority value) => priorityIndex = value.index;

  // ─────────────────────────────────────────────────────────────────────────
  // Status helpers
  // ─────────────────────────────────────────────────────────────────────────
  
  /// Returns true if the task is overdue (deadline has passed and not completed)
  bool get isLate {
    if (isCompleted) return false;
    return DateTime.now().isAfter(deadline);
  }

  /// Returns true if the task is upcoming (deadline in the future and not completed)
  bool get isUpcoming {
    if (isCompleted) return false;
    return !isLate;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Factory constructor
  // ─────────────────────────────────────────────────────────────────────────
  factory Task.create({
    required String id,
    required String name,
    required DateTime deadline,
    required TaskType type,
    required TaskPriority priority,
    String? subjectId,
    String? boardId,
    String? description,
  }) {
    return Task(
      id: id,
      name: name,
      deadline: deadline,
      typeIndex: type.index,
      priorityIndex: priority.index,
      subject: '', // Legacy field
      isCompleted: false,
      createdAt: DateTime.now(),
      boardId: boardId,
      subjectId: subjectId,
      description: description,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Copy with
  // ─────────────────────────────────────────────────────────────────────────
  Task copyWith({
    String? id,
    String? name,
    DateTime? deadline,
    TaskType? type,
    TaskPriority? priority,
    String? subject,
    bool? isCompleted,
    DateTime? createdAt,
    String? boardId,
    String? subjectId,
    Object? description = const _Undefined(),
  }) {
    return Task(
      id: id ?? this.id,
      name: name ?? this.name,
      deadline: deadline ?? this.deadline,
      typeIndex: type?.index ?? typeIndex,
      priorityIndex: priority?.index ?? priorityIndex,
      subject: subject ?? this.subject,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      boardId: boardId ?? this.boardId,
      subjectId: subjectId ?? this.subjectId,
      description: description is _Undefined ? this.description : description as String?,
    );
  }

  @override
  String toString() {
    return 'Task(id: $id, name: $name, boardId: $boardId, subjectId: $subjectId, isCompleted: $isCompleted)';
  }
}

class _Undefined {
  const _Undefined();
}
