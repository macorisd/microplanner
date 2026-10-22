import '../../features/boards/data/models/board.dart';
import '../../features/boards/data/models/subject.dart';
import '../../features/tasks/data/models/task.dart';

class WorkspaceSnapshot {
  final int revision;
  final List<Board> boards;
  final List<Subject> subjects;
  final List<Task> tasks;
  const WorkspaceSnapshot({
    this.revision = 0,
    this.boards = const [],
    this.subjects = const [],
    this.tasks = const [],
  });

  factory WorkspaceSnapshot.fromJson(Map<String, dynamic> json) =>
      WorkspaceSnapshot(
        revision: json['revision'] as int? ?? 0,
        boards: (json['boards'] as List)
            .map(
              (b) => Board(
                id: b['id'] as String,
                name: b['name'] as String,
                createdAt: DateTime.parse(b['createdAt'] as String).toLocal(),
                sortOrder: b['sortOrder'] as int,
              ),
            )
            .toList(),
        subjects: (json['subjects'] as List)
            .map(
              (s) => Subject(
                id: s['id'] as String,
                name: s['name'] as String,
                boardId: s['boardId'] as String,
                color: s['color'] as int,
              ),
            )
            .toList(),
        tasks: (json['tasks'] as List)
            .map(
              (t) => Task(
                id: t['id'] as String,
                name: t['name'] as String,
                deadline: DateTime.parse(t['deadline'] as String).toLocal(),
                createdAt: DateTime.parse(t['createdAt'] as String).toLocal(),
                typeIndex: t['typeIndex'] as int,
                priorityIndex: t['priorityIndex'] as int,
                subject: '',
                subjectId: t['subjectId'] as String?,
                boardId: t['boardId'] as String,
                description: t['description'] as String?,
                isCompleted: t['isCompleted'] as bool,
              ),
            )
            .toList(),
      );
  Map<String, dynamic> toJson() => {
    'revision': revision,
    'boards': boards
        .map(
          (b) => {
            'id': b.id,
            'name': b.name,
            'createdAt': b.createdAt.toUtc().toIso8601String(),
            'sortOrder': b.sortOrder,
          },
        )
        .toList(),
    'subjects': subjects
        .map(
          (s) => {
            'id': s.id,
            'name': s.name,
            'boardId': s.boardId,
            'color': s.color,
          },
        )
        .toList(),
    'tasks': tasks
        .map(
          (t) => {
            'id': t.id,
            'name': t.name,
            'deadline': t.deadline.toUtc().toIso8601String(),
            'createdAt': t.createdAt.toUtc().toIso8601String(),
            'typeIndex': t.typeIndex,
            'priorityIndex': t.priorityIndex,
            'isCompleted': t.isCompleted,
            'boardId': t.boardId,
            'subjectId': t.subjectId,
            'description': t.description,
          },
        )
        .toList(),
  };
  Map<String, dynamic> get data =>
      Map<String, dynamic>.from(toJson())..remove('revision');
  WorkspaceSnapshot copyWith({
    List<Board>? boards,
    List<Subject>? subjects,
    List<Task>? tasks,
  }) => WorkspaceSnapshot(
    revision: revision,
    boards: boards ?? this.boards,
    subjects: subjects ?? this.subjects,
    tasks: tasks ?? this.tasks,
  );
  WorkspaceSnapshot clone() => WorkspaceSnapshot.fromJson(toJson());
}
