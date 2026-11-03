import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../features/boards/data/models/board.dart';
import '../../features/boards/data/models/board_task_type.dart';
import '../../features/boards/data/models/subject.dart';
import '../../features/boards/data/board_catalog.dart';
import '../../features/tasks/data/models/task.dart';

class WorkspaceSnapshot {
  final int revision;
  final List<Board> boards;
  final List<Subject> subjects;
  final List<Task> tasks;
  final int schemaVersion;
  final List<BoardTaskType> boardTypes;
  final List<TaskTypeList> typeLists;
  const WorkspaceSnapshot({
    this.revision = 0,
    this.boards = const [],
    this.subjects = const [],
    this.tasks = const [],
    this.schemaVersion = 1,
    this.boardTypes = const [],
    this.typeLists = const [],
  });

  factory WorkspaceSnapshot.fromJson(
    Map<String, dynamic> json, {
    bool upgradeLegacy = true,
  }) {
    final parsed = WorkspaceSnapshot(
      revision: json['revision'] as int? ?? 0,
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      // Entity deltas update sortOrder without rearranging their backing array.
      // Normalize both cloud and journal/cache snapshots to the saved order.
      boards:
          ((json['boards'] as List)
              .map(
                (b) => Board(
                  id: b['id'] as String,
                  name: b['name'] as String,
                  createdAt: DateTime.parse(b['createdAt'] as String).toLocal(),
                  sortOrder: b['sortOrder'] as int,
                  icon: b['icon'] as String? ?? 'board',
                  color: b['color'] as int? ?? 0xff7986cb,
                ),
              )
              .toList()
            ..sort((a, b) {
              final order = a.sortOrder.compareTo(b.sortOrder);
              return order != 0 ? order : a.createdAt.compareTo(b.createdAt);
            })),
      subjects: (json['subjects'] as List)
          .map(
            (s) => Subject(
              id: s['id'] as String,
              name: s['name'] as String,
              boardId: s['boardId'] as String,
              color: s['color'] as int,
              sortOrder: s['sortOrder'] as int? ?? 0,
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
              typeId: t['typeId'] as String?,
            ),
          )
          .toList(),
      boardTypes: ((json['boardTypes'] as List?) ?? const [])
          .map(
            (t) => BoardTaskType.fromJson(Map<String, dynamic>.from(t as Map)),
          )
          .toList(),
      typeLists: ((json['typeLists'] as List?) ?? const [])
          .map(
            (t) => TaskTypeList.fromJson(Map<String, dynamic>.from(t as Map)),
          )
          .toList(),
    );
    return parsed.schemaVersion == 1 && upgradeLegacy
        ? parsed.upgraded()
        : parsed;
  }

  static String legacyTypeId(String boardId, int index) =>
      'bt-${sha256.convert(utf8.encode('$boardId:$index'))}';

  static List<BoardTaskType> defaultBoardTypes(String boardId) {
    final academic = initialTypeLists.first.types;
    return [
      for (var i = 0; i < academic.length; i++)
        BoardTaskType(
          id: legacyTypeId(boardId, i + 1),
          boardId: boardId,
          name: academic[i].name,
          icon: academic[i].icon,
          sortOrder: i,
        ),
    ];
  }

  WorkspaceSnapshot upgraded() {
    if (schemaVersion == 2) return this;
    final order = <String, int>{};
    final migratedSubjects = subjects.map((subject) {
      final next = order[subject.boardId] ?? 0;
      order[subject.boardId] = next + 1;
      return subject.copyWith(sortOrder: next);
    }).toList();
    const ids = [
      'default-academic',
      'default-software',
      'default-work',
      'default-personal',
      'default-creative',
    ];
    return copyWith(
      schemaVersion: 2,
      subjects: migratedSubjects,
      tasks: tasks
          .map(
            (task) => task.copyWith(
              typeId: task.typeIndex == 0 || task.boardId == null
                  ? null
                  : legacyTypeId(task.boardId!, task.typeIndex),
            ),
          )
          .toList(),
      boardTypes: [for (final board in boards) ...defaultBoardTypes(board.id)],
      typeLists: [
        for (var i = 0; i < initialTypeLists.length; i++)
          TaskTypeList(
            id: ids[i],
            name: initialTypeLists[i].name,
            types: List.of(initialTypeLists[i].types),
          ),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'revision': revision,
    'boards': boards
        .map(
          (b) => {
            'id': b.id,
            'name': b.name,
            'createdAt': b.createdAt.toUtc().toIso8601String(),
            'sortOrder': b.sortOrder,
            if (schemaVersion == 2) 'icon': b.icon,
            if (schemaVersion == 2) 'color': b.color,
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
            if (schemaVersion == 2) 'sortOrder': s.sortOrder,
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
            if (schemaVersion == 2) 'typeId': t.typeId,
          },
        )
        .toList(),
    if (schemaVersion == 2) 'schemaVersion': 2,
    if (schemaVersion == 2)
      'boardTypes': boardTypes.map((type) => type.toJson()).toList(),
    if (schemaVersion == 2)
      'typeLists': typeLists.map((list) => list.toJson()).toList(),
  };
  Map<String, dynamic> get data =>
      Map<String, dynamic>.from(toJson())..remove('revision');
  WorkspaceSnapshot copyWith({
    List<Board>? boards,
    List<Subject>? subjects,
    List<Task>? tasks,
    int? schemaVersion,
    List<BoardTaskType>? boardTypes,
    List<TaskTypeList>? typeLists,
  }) => WorkspaceSnapshot(
    revision: revision,
    boards: boards ?? this.boards,
    subjects: subjects ?? this.subjects,
    tasks: tasks ?? this.tasks,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    boardTypes: boardTypes ?? this.boardTypes,
    typeLists: typeLists ?? this.typeLists,
  );
  WorkspaceSnapshot clone() =>
      WorkspaceSnapshot.fromJson(toJson(), upgradeLegacy: false);
}
