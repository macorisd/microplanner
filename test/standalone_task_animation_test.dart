import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_delta.dart';
import 'package:microplanner/core/data/workspace_operation.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/features/boards/data/models/board_task_type.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/providers/task_transitions.dart';
import 'support/fakes.dart';

void main() {
  final start = DateTime(2030, 1, 2, 12);
  final task = Task.create(
    id: 'one',
    name: 'One',
    boardId: 'default-board',
    deadline: start.add(const Duration(days: 1)),
    type: TaskType.unassigned,
    priority: TaskPriority.low,
  );
  WorkspaceOperation operation(bool creating) {
    final base = snapshot('Board').copyWith(tasks: creating ? [] : [task]);
    return WorkspaceOperation(
      id: 'standalone',
      createdAt: start,
      delta: WorkspaceDelta.between(
        base,
        base.copyWith(tasks: creating ? [task] : []),
      ),
    );
  }

  test('pending creation preserves its board-specific task type', () {
    const typeId = 'type-reading';
    final typedTask = task.copyWith(typeId: typeId);
    final base = WorkspaceSnapshot(
      boards: snapshot('Board').boards,
      schemaVersion: 2,
      boardTypes: const [
        BoardTaskType(
          id: typeId,
          boardId: 'default-board',
          name: 'Reading',
          icon: 'book',
          sortOrder: 0,
        ),
      ],
    );
    final op = WorkspaceOperation(
      id: 'create-typed',
      createdAt: start,
      delta: WorkspaceDelta.between(base, base.copyWith(tasks: [typedTask])),
    );
    final tracker = TaskTransitions(now: () => start, changed: () {});

    tracker.update('A', [], [op], syncing: true);

    expect(tracker['one']!.phase, TaskTransitionPhase.creating);
    expect(tracker['one']!.after!.typeId, typeId);
    expect(tracker.present([]).single.typeId, typeId);
    tracker.dispose();
  });

  for (final creating in [true, false]) {
    for (final networkMs in [100, 2000, 5000]) {
      testWidgets(
        '${creating ? "create" : "delete"} follows the request: $networkMs ms',
        (tester) async {
          var now = start;
          final tracker = TaskTransitions(now: () => now, changed: () {});
          final before = creating ? <Task>[] : [task];
          final after = creating ? [task] : <Task>[];
          tracker.update('A', before, []);
          tracker.update('A', before, [operation(creating)], syncing: true);
          now = now.add(Duration(milliseconds: networkMs));
          await tester.pump(Duration(milliseconds: networkMs));
          expect(tracker['one'], isNotNull);
          tracker.update('A', after, [], syncing: true);
          expect(
            tracker['one'],
            isNull,
            reason: 'The individual request has completed.',
          );
          expect(tracker.present(after).length, after.length);
          tracker.dispose();
        },
      );
    }
    testWidgets(
      '${creating ? "create" : "delete"} failure ends feedback immediately',
      (tester) async {
        var now = start;
        final tracker = TaskTransitions(now: () => now, changed: () {});
        final before = creating ? <Task>[] : [task];
        final op = operation(creating);
        tracker.update('A', before, []);
        tracker.update('A', before, [op]);
        now = now.add(const Duration(milliseconds: 50));
        op.failure = 'Rejected';
        tracker.update('A', before, [op]);
        expect(tracker['one'], isNull);
        expect(tracker.present(before).length, before.length);
        tracker.dispose();
      },
    );
  }
}
