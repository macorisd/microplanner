import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_delta.dart';
import 'package:microplanner/core/data/workspace_operation.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/providers/task_transitions.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_transition_visual.dart';
import 'support/fakes.dart';

void main() {
  final start = DateTime(2030, 1, 2, 12);
  Task task(TaskColumnKind column) => Task.create(
    id: 'task',
    name: 'Task',
    boardId: 'default-board',
    type: TaskType.unassigned,
    priority: TaskPriority.low,
    deadline: start.add(
      column == TaskColumnKind.late
          ? const Duration(days: -1)
          : const Duration(days: 1),
    ),
  ).copyWith(isCompleted: column == TaskColumnKind.completed);
  WorkspaceOperation operation(String id, Task before, Task? after) {
    final base = snapshot('Board').copyWith(tasks: [before]);
    return WorkspaceOperation(
      id: id,
      createdAt: start,
      delta: WorkspaceDelta.between(
        base,
        base.copyWith(tasks: after == null ? [] : [after]),
      ),
    );
  }

  TaskVisual visual(TaskTransition value) => (
    phase: value.phase,
    target: value.to,
    beforeCompleted: value.before?.isCompleted ?? false,
    afterCompleted: value.after?.isCompleted ?? false,
    started: value.started,
    phaseAt: value.phaseAt,
    carry: value.carry,
  );

  for (final from in TaskColumnKind.values) {
    for (final to in TaskColumnKind.values.where((value) => value != from)) {
      for (final next in <TaskColumnKind?>[
        ...TaskColumnKind.values.where((value) => value != to),
        null,
      ]) {
        testWidgets('$from -> $to can immediately chain to $next', (
          tester,
        ) async {
          var now = start;
          final tracker = TaskTransitions(now: () => now, changed: () {});
          final original = task(from);
          final arrived = task(to);
          tracker.update('A', [original], []);
          tracker.update(
            'A',
            [original],
            [operation('first', original, arrived)],
          );
          tracker.update('A', [arrived], []);
          now = now.add(const Duration(milliseconds: 1001));
          await tester.pump(const Duration(milliseconds: 1001));
          final first = tracker['task']!;
          expect(first.phase, TaskTransitionPhase.destination);
          expect(tracker.locked('task'), isFalse);
          final target = next == null ? null : task(next);
          final second = operation('second', arrived, target);
          final captured = now;
          tracker.update('A', [arrived], [second], syncing: true);
          final chained = tracker['task']!;
          expect(chained.operationId, 'second');
          expect(chained.phase, TaskTransitionPhase.source);
          expect(chained.from, to);
          expect(chained.to, next);
          expect(chained.before!.isCompleted, arrived.isCompleted);
          expect(chained.carry!.target, to);
          expect(chained.carry!.capturedAt, captured);
          expect(tracker.locked('task'), isTrue);
          expect(taskTransitionStrength(visual(chained), now), 0);
          expect(
            taskTransitionCarryStrength(visual(chained), now),
            taskTransitionStrength(visual(first), captured),
          );
          now = now.add(const Duration(milliseconds: 500));
          expect(
            taskTransitionCarryStrength(visual(chained), now),
            inExclusiveRange(0, 1),
          );
          expect(
            taskTransitionStrength(visual(chained), now),
            inExclusiveRange(0, 1),
          );
          // The first arrival's old timer must not remove its replacement.
          now = now.add(const Duration(seconds: 3));
          await tester.pump(const Duration(milliseconds: 3500));
          expect(tracker['task'], same(chained));
          expect(chained.phase, TaskTransitionPhase.source);
          expect(
            tracker.displayedColumn(
              tracker.present(target == null ? [] : [target]).single,
              now,
            ),
            to,
          );
          tracker.update(
            'A',
            target == null ? [] : [target],
            [],
            syncing: false,
          );
          now = now.add(const Duration(milliseconds: 121));
          await tester.pump(const Duration(milliseconds: 121));
          if (target == null) {
            expect(tracker['task'], isNull);
            expect(tracker.present([]), isEmpty);
          } else {
            expect(tracker['task']!.phase, TaskTransitionPhase.destination);
            expect(tracker.locked('task'), isFalse);
          }
          tracker.dispose();
        });
      }
    }
  }

  testWidgets('a failed chained move restores the latest confirmed task', (
    tester,
  ) async {
    var now = start;
    final tracker = TaskTransitions(now: () => now, changed: () {});
    final original = task(TaskColumnKind.upcoming);
    final arrived = task(TaskColumnKind.completed);
    tracker.update('A', [original], []);
    tracker.update('A', [arrived], []);
    now = now.add(const Duration(milliseconds: 1001));
    await tester.pump(const Duration(milliseconds: 1001));
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    final oldVisual = visual(tracker['task']!);
    final second = operation('rejected', arrived, original);
    tracker.update('A', [arrived], [second]);
    expect(
      taskTransitionCarryStrength(visual(tracker['task']!), now),
      taskTransitionStrength(oldVisual, now),
    );
    second.failure = 'Rejected';
    tracker.update('A', [arrived], [second]);
    now = now.add(const Duration(milliseconds: 1001));
    await tester.pump(const Duration(milliseconds: 1001));
    expect(tracker['task']!.phase, TaskTransitionPhase.rollback);
    expect(tracker.present([arrived]).single.isCompleted, isTrue);
    expect(tracker.locked('task'), isTrue);
    now = now.add(const Duration(milliseconds: 1001));
    await tester.pump(const Duration(milliseconds: 1001));
    expect(tracker['task'], isNull);
    expect(tracker.present([arrived]).single.isCompleted, isTrue);
    tracker.dispose();
  });

  testWidgets(
    'same-column edits retain arrival and remote deletion replaces it',
    (tester) async {
      var now = start;
      final tracker = TaskTransitions(now: () => now, changed: () {});
      final old = task(TaskColumnKind.upcoming);
      final done = task(TaskColumnKind.completed);
      tracker.update('A', [old], []);
      tracker.update('A', [done], []);
      now = now.add(const Duration(milliseconds: 1001));
      await tester.pump(const Duration(milliseconds: 1001));
      final arrival = tracker['task'];
      final edited = done.copyWith(name: 'Edited during arrival');
      tracker.update('A', [done], [operation('edit', done, edited)]);
      tracker.update('A', [edited], []);
      expect(tracker['task'], same(arrival));
      tracker.update('A', [], []);
      expect(tracker['task']!.phase, TaskTransitionPhase.source);
      expect(tracker['task']!.to, isNull);
      expect(tracker['task']!.before!.name, edited.name);
      expect(tracker['task']!.carry!.target, TaskColumnKind.completed);
      tracker.update('B', [old], []);
      expect(tracker['task'], isNull);
      tracker.dispose();
    },
  );
}
