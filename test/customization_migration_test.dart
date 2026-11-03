import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/core/data/workspace_delta.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/features/boards/data/models/board_task_type.dart';
import 'package:microplanner/features/boards/data/type_list_replacement.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';

void main() {
  Map<String, dynamic> legacy() => {
    'revision': 4,
    'boards': [
      {
        'id': 'board',
        'name': 'Board',
        'sortOrder': 0,
        'createdAt': '2026-01-01T00:00:00Z',
      },
    ],
    'subjects': [
      {
        'id': 'subject',
        'name': 'Subject',
        'boardId': 'board',
        'color': 0xffaabbcc,
      },
    ],
    'tasks': [
      {
        'id': 'task',
        'name': 'Task',
        'boardId': 'board',
        'subjectId': 'subject',
        'description': null,
        'deadline': '2026-01-01T00:00:00Z',
        'createdAt': '2026-01-01T00:00:00Z',
        'typeIndex': 2,
        'priorityIndex': 1,
        'isCompleted': false,
      },
    ],
  };

  test(
    'upgrades legacy tasks and survives serialization without changing assignments',
    () {
      final first = WorkspaceSnapshot.fromJson(legacy());
      final second = WorkspaceSnapshot.fromJson(legacy());
      expect(first.schemaVersion, 2);
      expect(first.boardTypes, hasLength(6));
      expect(first.typeLists, hasLength(5));
      expect(first.tasks.single.typeId, first.boardTypes[1].id);
      expect(first.tasks.single.typeId, second.tasks.single.typeId);
      expect(first.tasks.single.subjectId, 'subject');
      final restored = WorkspaceSnapshot.fromJson(first.toJson());
      expect(restored.tasks.single.typeId, first.tasks.single.typeId);
      expect(restored.typeLists.first.types.first.name, 'Homework');
    },
  );

  test(
    'template changes rebase without overwriting unrelated newer changes',
    () {
      final start = WorkspaceSnapshot.fromJson(legacy());
      final edited = start.copyWith(
        typeLists: [
          TaskTypeList(
            id: start.typeLists.first.id,
            name: 'Studies',
            types: start.typeLists.first.types,
          ),
          ...start.typeLists.skip(1),
        ],
      );
      final remote = start.copyWith(
        boards: [start.boards.single.copyWith(name: 'Renamed')],
      );
      final result = WorkspaceDelta.between(start, edited).apply(remote);
      expect(result, isNotNull);
      expect(result!.boards.single.name, 'Renamed');
      expect(result.typeLists.first.name, 'Studies');
      expect(result.typeLists.first.types.first.name, 'Homework');
      final conflicting = start.copyWith(
        typeLists: [
          TaskTypeList(
            id: start.typeLists.first.id,
            name: 'Other',
            types: const [TypeListEntry(name: 'One', icon: 'book')],
          ),
          ...start.typeLists.skip(1),
        ],
      );
      expect(WorkspaceDelta.between(start, edited).apply(conflicting), isNull);
    },
  );

  test('removing a type conflicts if a new remote task now uses it', () {
    final base = WorkspaceSnapshot.fromJson(legacy());
    final removed = base.boardTypes[1].id;
    final changed = base.copyWith(
      boardTypes: base.boardTypes.where((type) => type.id != removed).toList(),
      tasks: [base.tasks.single.copyWith(typeId: null)],
    );
    final remote = base.copyWith(
      tasks: [
        ...base.tasks,
        Task.create(
          id: 'other',
          name: 'New task',
          deadline: DateTime(2030),
          type: TaskType.unassigned,
          priority: TaskPriority.low,
          boardId: 'board',
        )..typeId = removed,
      ],
    );
    expect(WorkspaceDelta.between(base, changed).apply(remote), isNull);
    expect(remote.tasks.last.typeId, removed);
  });

  test('replays a legacy queued type edit without dropping its assignment', () {
    final old = WorkspaceSnapshot.fromJson(legacy(), upgradeLegacy: false);
    final changed = old.copyWith(
      tasks: [old.tasks.single.copyWith(type: TaskType.homework)],
    );
    final migrated = old.upgraded();
    final result = WorkspaceDelta.between(old, changed).apply(migrated);
    expect(result, isNotNull);
    expect(
      result!.tasks.single.typeId,
      WorkspaceSnapshot.legacyTypeId('board', 1),
    );
    final changedElsewhere = migrated.copyWith(
      tasks: [
        migrated.tasks.single.copyWith(
          typeId: WorkspaceSnapshot.legacyTypeId('board', 3),
        ),
      ],
    );
    expect(
      WorkspaceDelta.between(old, changed).apply(changedElsewhere),
      isNull,
    );
  });

  test('replays a legacy queued task creation with its assigned type', () {
    final old = WorkspaceSnapshot.fromJson(legacy(), upgradeLegacy: false);
    final newTask = Task.create(
      id: 'new-task',
      name: 'New',
      deadline: DateTime(2030),
      type: TaskType.reading,
      priority: TaskPriority.low,
      boardId: 'board',
    );
    final result = WorkspaceDelta.between(
      old,
      old.copyWith(tasks: [...old.tasks, newTask]),
    ).apply(old.upgraded());
    expect(result, isNotNull);
    expect(
      result!.tasks.last.typeId,
      WorkspaceSnapshot.legacyTypeId('board', TaskType.reading.index),
    );
  });
}
