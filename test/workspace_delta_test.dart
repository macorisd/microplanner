import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_delta.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'support/fakes.dart';

Task _task(String id, {String name = 'Original', String? description}) =>
    Task.create(
      id: id,
      name: name,
      description: description,
      boardId: 'default-board',
      deadline: DateTime(2030, 1, 1, 12),
      type: TaskType.unassigned,
      priority: TaskPriority.low,
    );

void main() {
  test('a large bulk deletion preserves unrelated records and their order', () {
    final rows = [for (var i = 0; i < 5000; i++) _task('task$i')];
    final base = snapshot('Board').copyWith(tasks: rows);
    final desired = base.copyWith(
      tasks: [for (var i = 0; i < rows.length; i += 2) rows[i]],
    );
    final intent = WorkspaceDelta.between(base, desired);
    final extra = _task('remote');
    final result = intent.apply(base.copyWith(tasks: [...rows, extra]))!;
    expect(result.tasks.map((item) => item.id), [
      for (var i = 0; i < rows.length; i += 2) 'task$i',
      'remote',
    ]);
  });
  test('rebase preserves unrelated remote task edits and other tasks', () {
    final first = _task('one', description: 'Old description');
    final base = snapshot('Board').copyWith(tasks: [first]);
    final intent = WorkspaceDelta.between(
      base,
      base.copyWith(tasks: [first.copyWith(name: 'New name')]),
    );
    final restored = WorkspaceDelta.fromJson(
      jsonDecode(jsonEncode(intent.toJson())) as Map<String, dynamic>,
    );
    final other = _task('two');
    final remote = base.copyWith(
      tasks: [
        first.copyWith(description: 'Remote detail'),
        other,
      ],
    );
    final result = restored.apply(remote)!;
    expect(result.tasks.map((task) => task.id), ['one', 'two']);
    expect(result.tasks.first.name, 'New name');
    expect(result.tasks.first.description, 'Remote detail');
    expect(remote.tasks.first.name, 'Original');
  });

  test(
    'a conflicting field or changed deletion target is never overwritten',
    () {
      final first = _task('one', description: 'Old');
      final base = snapshot('Board').copyWith(tasks: [first]);
      final rename = WorkspaceDelta.between(
        base,
        base.copyWith(tasks: [first.copyWith(name: 'Mine')]),
      );
      expect(
        rename.apply(base.copyWith(tasks: [first.copyWith(name: 'Theirs')])),
        isNull,
      );
      final deletion = WorkspaceDelta.between(base, base.copyWith(tasks: []));
      expect(
        deletion.apply(
          base.copyWith(tasks: [first.copyWith(description: 'Remote change')]),
        ),
        isNull,
      );
      expect(deletion.apply(base.copyWith(tasks: []))!.tasks, isEmpty);
    },
  );

  test(
    'queued independent edits compose and missing parents cannot be recreated',
    () {
      final first = _task('one');
      final base = snapshot('Board').copyWith(tasks: [first]);
      final second = _task('two');
      final added = WorkspaceDelta.between(
        base,
        base.copyWith(tasks: [first, second]),
      );
      final projected = added.apply(base)!;
      final completed = WorkspaceDelta.between(
        projected,
        projected.copyWith(tasks: [first.copyWith(isCompleted: true), second]),
      );
      final combined = completed.apply(added.apply(base)!)!;
      expect(combined.tasks.first.isCompleted, isTrue);
      expect(combined.tasks.last.id, 'two');
      final noBoard = WorkspaceSnapshot(
        boards: [snapshot('Other').boards.first.copyWith(id: 'other')],
      );
      expect(added.apply(noBoard), isNull);
    },
  );
}
