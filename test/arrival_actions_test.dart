import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/providers/task_transitions.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'support/fakes.dart';

class _Cache extends MemoryCache implements WorkspaceJournal {
  final records = <String, String>{};
  @override
  Future<String?> readJournal(String ownerId) async => records[ownerId];
  @override
  Future<void> writeJournal(String ownerId, String value) async {
    records[ownerId] = value;
  }
}

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final action in ['move', 'delete', 'edit']) {
      testWidgets(
        '$platform $action works during arrival and retains pending guards',
        (tester) async {
          final h = Harness(cache: _Cache());
          final original = Task.create(
            id: 'one',
            name: 'One',
            boardId: 'default-board',
            deadline: DateTime(2030),
            type: TaskType.unassigned,
            priority: TaskPriority.low,
          );
          h.server.states['A'] = h.server.states['A']!.copyWith(
            tasks: [original],
          );
          await tester.runAsync(() async {
            await h.initialize();
            await h.login('A');
          });
          final boards = BoardsProvider(h.workspace);
          var now = DateTime.now();
          final tasks = TasksProvider(h.workspace, boards, now: () => now);
          var edits = 0;
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<WorkspaceController>.value(
                  value: h.workspace,
                ),
                ChangeNotifierProvider<BoardsProvider>.value(value: boards),
                ChangeNotifierProvider<TasksProvider>.value(value: tasks),
              ],
              child: MaterialApp(
                theme: ThemeData(platform: platform),
                home: Scaffold(
                  body: Consumer<TasksProvider>(
                    builder: (_, provider, _) => Column(
                      children: [
                        for (final task in provider.tasks)
                          SizedBox(
                            width: 400,
                            child: TaskCard(
                              key: ValueKey(task.id),
                              task: task,
                              onToggleComplete: () =>
                                  tasks.toggleTaskCompletion(task.id),
                              onDelete: () {
                                unawaited(tasks.deleteTask(task.id));
                              },
                              onEdit: () => edits++,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            expect(await tasks.toggleTaskCompletion('one'), isTrue);
            await settleAsync();
          });
          now = now.add(const Duration(milliseconds: 1001));
          boards.selectColumn((boards.currentColumnIndex + 1) % 3);
          await tester.pump(const Duration(milliseconds: 1001));
          final arrival = tasks.transitions['one'];
          expect(arrival!.phase, TaskTransitionPhase.destination);
          expect(tasks.transitions.locked('one'), isFalse);
          await tester.tap(find.text('One'));
          await tester.pump();
          expect(edits, 1);
          final gate = Completer<http.Response>();
          h.server.nextWrite = gate;
          Future<bool>? saving;
          if (action == 'delete') {
            if (platform == TargetPlatform.windows) {
              final mouse = await tester.createGesture(
                kind: ui.PointerDeviceKind.mouse,
              );
              await mouse.addPointer(location: Offset.zero);
              await mouse.moveTo(tester.getCenter(find.byType(TaskCard)));
              await tester.pump(const Duration(milliseconds: 200));
              addTearDown(mouse.removePointer);
            }
            await tester.tap(find.byTooltip('Delete'));
          } else if (action == 'move') {
            await tester.tap(find.bySemanticsLabel('Mark task incomplete'));
          } else {
            saving = tasks.updateTask(
              tasks.tasks.single.copyWith(name: 'Edited'),
            );
          }
          await tester.pump();
          expect(h.workspace.outbox!.pendingTaskIds, contains('one'));
          final pending = tasks.transitions['one']!;
          if (action == 'edit') {
            expect(pending, same(arrival));
          } else {
            expect(pending.phase, TaskTransitionPhase.source);
            expect(pending.before!.isCompleted, isTrue);
            expect(pending.carry!.target, TaskColumnKind.completed);
          }
          await tester.tap(find.text('One'));
          await tester.pump();
          expect(
            edits,
            1,
            reason: 'A real pending write must still disable editing.',
          );
          expect(await tasks.toggleTaskCompletion('one'), isFalse);
          await tester.runAsync(() async {
            await settleAsync();
            gate.complete(jsonResponse(h.server.states['A']!.toJson()));
            await settleAsync();
          });
          await tester.pump();
          if (saving != null) expect(await saving, isTrue);
          final finishDelay = Duration(
            milliseconds: action == 'delete' ? 2501 : 1001,
          );
          now = now.add(finishDelay);
          boards.selectColumn((boards.currentColumnIndex + 1) % 3);
          await tester.pump(finishDelay);
          expect(h.workspace.outbox!.pendingTaskIds, isEmpty);
          expect(
            h.server.writes,
            2,
            reason: 'The first move and new action each save exactly once.',
          );
          if (action == 'move') {
            expect(tasks.tasks.single.isCompleted, isFalse);
            expect(
              tasks.transitions['one']!.phase,
              TaskTransitionPhase.destination,
            );
            expect(tasks.transitions.locked('one'), isFalse);
          } else if (action == 'delete') {
            expect(tasks.tasks, isEmpty);
          } else {
            expect(tasks.tasks.single.name, 'Edited');
            expect(tasks.transitions['one'], same(arrival));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          tasks.dispose();
          boards.dispose();
          h.dispose();
        },
      );
    }
  }
}
