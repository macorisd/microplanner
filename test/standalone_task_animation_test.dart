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

  TaskVisual visual(TaskTransition value) => (
    phase: value.phase,
    target: value.to,
    started: value.started,
    phaseAt: value.phaseAt,
    beforeCompleted: value.before?.isCompleted ?? false,
    afterCompleted: value.after?.isCompleted ?? false,
    carry: value.carry,
  );

  for (final creating in [true, false]) {
    for (final networkMs in [100, 2000, 5000]) {
      testWidgets(
        '${creating ? "create" : "delete"} $networkMs ms counts 2.5s from the action',
        (tester) async {
          var now = start;
          final tracker = TaskTransitions(now: () => now, changed: () {});
          final before = creating ? <Task>[] : [task];
          final after = creating ? [task] : <Task>[];
          tracker.update('A', before, []);
          tracker.update('A', before, [operation(creating)], syncing: true);
          expect(tracker['one']!.started, start);
          now = now.add(Duration(milliseconds: networkMs));
          await tester.pump(Duration(milliseconds: networkMs));
          expect(
            tracker['one'],
            isNotNull,
            reason: 'A pending request must remain visible even past 2.5s.',
          );
          tracker.update('A', after, [], syncing: false);
          now = now.add(const Duration(milliseconds: 121));
          await tester.pump(const Duration(milliseconds: 121));
          final earliest = start.add(const Duration(milliseconds: 2500));
          var finish = earliest;
          if (creating) {
            expect(tracker['one']!.phase, TaskTransitionPhase.creationFinish);
            expect(tracker.locked('one'), isFalse);
            final late = now.add(const Duration(seconds: 1));
            if (late.isAfter(finish)) finish = late;
          } else if (now.isAfter(finish)) {
            finish = now;
          }
          if (finish.isAfter(now)) {
            final wait =
                finish.difference(now) - const Duration(milliseconds: 1);
            now = now.add(wait);
            await tester.pump(wait);
            expect(tracker['one'], isNotNull);
            if (creating) {
              expect(
                taskTransitionStrength(visual(tracker['one']!), now),
                greaterThan(0),
              );
            }
            now = now.add(const Duration(milliseconds: 2));
            await tester.pump(const Duration(milliseconds: 2));
          }
          expect(tracker['one'], isNull);
          expect(tracker.present(after).length, creating ? 1 : 0);
          expect(
            now.difference(start),
            greaterThanOrEqualTo(const Duration(milliseconds: 2500)),
          );
          tracker.dispose();
        },
      );
    }
    testWidgets(
      '${creating ? "create" : "delete"} immediate failure still gives a complete 2.5s reversal',
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
        now = start.add(const Duration(milliseconds: 1501));
        await tester.pump(const Duration(milliseconds: 1501));
        expect(tracker['one']!.phase, TaskTransitionPhase.rollback);
        now = start.add(const Duration(milliseconds: 2500));
        await tester.pump(const Duration(milliseconds: 999));
        expect(tracker['one'], isNotNull);
        now = now.add(const Duration(milliseconds: 2));
        await tester.pump(const Duration(milliseconds: 2));
        expect(tracker['one'], isNull);
        expect(tracker.present(before).length, before.length);
        tracker.dispose();
      },
    );
  }

  testWidgets('confirmed creation can chain before its 2.5s visual finishes', (
    tester,
  ) async {
    var now = start;
    final tracker = TaskTransitions(now: () => now, changed: () {});
    tracker.update('A', [], []);
    tracker.update('A', [], [operation(true)], syncing: true);
    now = start.add(const Duration(milliseconds: 100));
    tracker.update('A', [task], [], syncing: false);
    now = start.add(const Duration(milliseconds: 221));
    await tester.pump(const Duration(milliseconds: 221));
    final first = visual(tracker['one']!);
    expect(tracker.locked('one'), isFalse);
    final done = task.copyWith(isCompleted: true);
    final base = snapshot('Board').copyWith(tasks: [task]);
    final second = WorkspaceOperation(
      id: 'complete',
      createdAt: now,
      delta: WorkspaceDelta.between(base, base.copyWith(tasks: [done])),
    );
    tracker.update('A', [task], [second], syncing: true);
    expect(tracker['one']!.phase, TaskTransitionPhase.source);
    expect(tracker['one']!.carry!.phase, TaskTransitionPhase.creationFinish);
    expect(
      taskTransitionCarryStrength(visual(tracker['one']!), now),
      taskTransitionStrength(first, now),
    );
    now = now.add(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    expect(tracker['one']!.operationId, 'complete');
    tracker.dispose();
  });
}
