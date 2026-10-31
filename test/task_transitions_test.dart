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
  Task task(String id, TaskColumnKind column) => Task.create(
    id: id,
    name: id,
    boardId: 'default-board',
    type: TaskType.unassigned,
    priority: TaskPriority.low,
    deadline: start.add(
      column == TaskColumnKind.late
          ? const Duration(days: -1)
          : const Duration(days: 1),
    ),
  ).copyWith(isCompleted: column == TaskColumnKind.completed);
  WorkspaceOperation operation(Task before, Task? after) {
    final base = snapshot('Board').copyWith(tasks: [before]);
    return WorkspaceOperation(
      id: before.id,
      createdAt: start,
      delta: WorkspaceDelta.between(
        base,
        base.copyWith(tasks: after == null ? [] : [after]),
      ),
    );
  }

  test(
    'source gradient takes one second and destination takes 2.5 seconds',
    () {
      final source = (
        phase: TaskTransitionPhase.source,
        target: TaskColumnKind.completed,
        beforeCompleted: false,
        afterCompleted: true,
        started: start,
        phaseAt: start,
      );
      expect(taskTransitionStrength(source, start), 0);
      expect(
        taskTransitionStrength(
          source,
          start.add(const Duration(milliseconds: 500)),
        ),
        inExclusiveRange(0, 1),
      );
      expect(
        taskTransitionStrength(source, start.add(const Duration(seconds: 1))),
        1,
      );
      expect(
        taskTransitionStrength(source, start.add(const Duration(seconds: 5))),
        1,
      );
      final destinationAt = start.add(const Duration(seconds: 5));
      final destination = (
        phase: TaskTransitionPhase.destination,
        target: TaskColumnKind.completed,
        beforeCompleted: false,
        afterCompleted: true,
        started: start,
        phaseAt: destinationAt,
      );
      expect(taskTransitionStrength(destination, destinationAt), 1);
      expect(
        taskTransitionStrength(
          destination,
          destinationAt.add(const Duration(milliseconds: 500)),
        ),
        inExclusiveRange(0, 1),
      );
      expect(
        taskTransitionStrength(
          destination,
          destinationAt.add(const Duration(seconds: 1)),
        ),
        inExclusiveRange(0, 1),
      );
      expect(
        taskTransitionStrength(
          destination,
          destinationAt.add(const Duration(milliseconds: 2500)),
        ),
        0,
      );
    },
  );

  testWidgets(
    'a confirmed task stays in the source until all synchronization finishes',
    (tester) async {
      var now = start;
      final tracker = TaskTransitions(now: () => now, changed: () {});
      final one = task('one', TaskColumnKind.upcoming);
      final two = task('two', TaskColumnKind.upcoming);
      final oneDone = one.copyWith(isCompleted: true);
      final twoDone = two.copyWith(isCompleted: true);
      final first = operation(one, oneDone);
      final second = operation(two, twoDone);
      tracker.update('A', [one, two], []);
      tracker.update('A', [one, two], [first, second], syncing: true);
      tracker.update('A', [oneDone, two], [second], syncing: true);
      now = start.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(tracker['one']!.confirmed, isTrue);
      expect(tracker['one']!.phase, TaskTransitionPhase.source);
      expect(
        tracker.displayedColumn(tracker.present([oneDone, two]).first, now),
        TaskColumnKind.upcoming,
      );
      tracker.update('A', [oneDone, twoDone], [], syncing: false);
      expect(tracker['one']!.phase, TaskTransitionPhase.source);
      now = now.add(const Duration(milliseconds: 121));
      await tester.pump(const Duration(milliseconds: 121));
      expect(tracker['one']!.phase, TaskTransitionPhase.destination);
      expect(tracker['two']!.phase, TaskTransitionPhase.destination);
      now = now.add(const Duration(milliseconds: 2499));
      await tester.pump(const Duration(milliseconds: 2499));
      expect(tracker['one']!.phase, TaskTransitionPhase.destination);
      now = now.add(const Duration(milliseconds: 2));
      await tester.pump(const Duration(milliseconds: 2));
      expect(tracker['one'], isNull);
      expect(tracker['two'], isNull);
      tracker.dispose();
    },
  );

  for (final from in TaskColumnKind.values) {
    for (final to in TaskColumnKind.values.where((column) => column != from)) {
      testWidgets(
        '$from to $to waits for confirmation and the base animation',
        (tester) async {
          var now = start;
          final tracker = TaskTransitions(now: () => now, changed: () {});
          final old = task('a', from);
          final updated = old.copyWith(
            isCompleted: to == TaskColumnKind.completed,
            deadline: start.add(
              to == TaskColumnKind.late
                  ? const Duration(days: -1)
                  : const Duration(days: 1),
            ),
          );
          final op = operation(old, updated);
          tracker.update('A', [old], []);
          tracker.update('A', [old], [op]);
          expect(tracker['a']!.from, from);
          expect(tracker['a']!.to, to);
          tracker.update('A', [updated], []);
          expect(
            tracker.present([updated]).single.isCompleted,
            old.isCompleted,
          );
          expect(
            tracker.displayedColumn(tracker.present([updated]).single, now),
            from,
          );
          now = start.add(const Duration(milliseconds: 1001));
          await tester.pump(const Duration(milliseconds: 1001));
          expect(tracker['a']!.phase, TaskTransitionPhase.destination);
          expect(
            tracker.displayedColumn(tracker.present([updated]).single, now),
            to,
          );
          now = now.add(const Duration(milliseconds: 2499));
          await tester.pump(const Duration(milliseconds: 2499));
          expect(tracker['a']!.phase, TaskTransitionPhase.destination);
          now = now.add(const Duration(milliseconds: 2));
          await tester.pump(const Duration(milliseconds: 2));
          expect(tracker['a'], isNull);
          tracker.dispose();
        },
      );
    }
  }

  testWidgets(
    'slow work holds the source; failed work rolls back; unrelated tasks progress',
    (tester) async {
      var now = start;
      final tracker = TaskTransitions(now: () => now, changed: () {});
      final one = task('one', TaskColumnKind.upcoming);
      final two = task('two', TaskColumnKind.late);
      final oneDone = one.copyWith(isCompleted: true);
      final twoDone = two.copyWith(isCompleted: true);
      final first = operation(one, oneDone);
      final second = operation(two, twoDone);
      tracker.update('A', [one, two], []);
      tracker.update('A', [one, two], [first, second]);
      now = start.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(tracker['one']!.phase, TaskTransitionPhase.source);
      first.failure = 'Rejected';
      tracker.update('A', [one, twoDone], [first]);
      expect(tracker['one']!.phase, TaskTransitionPhase.rollback);
      expect(tracker['two']!.phase, TaskTransitionPhase.destination);
      expect(
        tracker
            .present([one, twoDone])
            .where((t) => t.id == 'one')
            .single
            .isCompleted,
        isFalse,
      );
      now = now.add(const Duration(milliseconds: 1001));
      await tester.pump(const Duration(milliseconds: 1001));
      expect(tracker['one'], isNull);
      expect(tracker['two']!.phase, TaskTransitionPhase.destination);
      now = now.add(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      expect(tracker['two'], isNull);
      tracker.dispose();
    },
  );

  testWidgets(
    'an early failure still finishes the base animation before rollback',
    (tester) async {
      var now = start;
      final tracker = TaskTransitions(now: () => now, changed: () {});
      final original = task('failed', TaskColumnKind.upcoming);
      final op = operation(original, original.copyWith(isCompleted: true));
      tracker.update('A', [original], []);
      tracker.update('A', [original], [op]);
      now = start.add(const Duration(milliseconds: 50));
      op.failure = 'Rejected';
      tracker.update('A', [original], [op]);
      expect(tracker['failed']!.phase, TaskTransitionPhase.source);
      now = start.add(const Duration(milliseconds: 1001));
      await tester.pump(const Duration(milliseconds: 1001));
      expect(tracker['failed']!.phase, TaskTransitionPhase.rollback);
      now = start.add(const Duration(milliseconds: 2002));
      await tester.pump(const Duration(milliseconds: 1001));
      expect(tracker['failed'], isNull);
      tracker.dispose();
    },
  );

  testWidgets(
    'deadline expiry and cached startup observations move from upcoming to late',
    (tester) async {
      var now = start;
      final tracker = TaskTransitions(now: () => now, changed: () {});
      final due = task(
        'due',
        TaskColumnKind.upcoming,
      ).copyWith(deadline: start.subtract(const Duration(minutes: 1)));
      tracker.seed('A', [due], start.subtract(const Duration(hours: 1)));
      tracker.update('A', [due], []);
      expect(tracker['due']!.from, TaskColumnKind.upcoming);
      expect(tracker['due']!.to, TaskColumnKind.late);
      now = start.add(const Duration(milliseconds: 1001));
      await tester.pump(const Duration(milliseconds: 1001));
      expect(tracker['due']!.phase, TaskTransitionPhase.destination);
      now = now.add(const Duration(milliseconds: 2499));
      await tester.pump(const Duration(milliseconds: 2499));
      expect(tracker['due']!.phase, TaskTransitionPhase.destination);
      now = now.add(const Duration(milliseconds: 2));
      await tester.pump(const Duration(milliseconds: 2));
      expect(tracker['due'], isNull);
      tracker.dispose();
    },
  );

  testWidgets(
    'bulk deletion waits at the source and account changes discard old visuals',
    (tester) async {
      var now = start;
      final tracker = TaskTransitions(now: () => now, changed: () {});
      final one = task('one', TaskColumnKind.completed);
      final two = task('two', TaskColumnKind.completed);
      final base = snapshot('Board').copyWith(tasks: [one, two]);
      final op = WorkspaceOperation(
        id: 'bulk',
        createdAt: start,
        delta: WorkspaceDelta.between(base, base.copyWith(tasks: [])),
      );
      tracker.update('A', [one, two], []);
      tracker.update('A', [one, two], [op]);
      expect(tracker['one']!.to, isNull);
      expect(tracker['two']!.to, isNull);
      tracker.update('A', [], []);
      expect(tracker.present([]).length, 2);
      now = start.add(const Duration(milliseconds: 1001));
      await tester.pump(const Duration(milliseconds: 1001));
      expect(tracker.present([]), isEmpty);
      tracker.update('B', [task('one', TaskColumnKind.late)], []);
      expect(tracker['one'], isNull);
      tracker.dispose();
    },
  );
}
