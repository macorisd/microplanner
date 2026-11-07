import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/boards/data/models/board_task_type.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_transition_visual.dart';
import 'package:microplanner/features/tasks/providers/task_transitions.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:provider/provider.dart';

import 'support/fakes.dart';

class _Cache extends MemoryCache implements WorkspaceJournal {
  final journals = <String, String>{};

  @override
  Future<String?> readJournal(String ownerId) async => journals[ownerId];

  @override
  Future<void> writeJournal(String ownerId, String value) async {
    journals[ownerId] = value;
  }
}

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('$platform pending creation card keeps its task type visible', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(520, 420);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final h = Harness(cache: _Cache());
      const type = BoardTaskType(
        id: 'type-test',
        boardId: 'default-board',
        name: 'Test',
        icon: 'test',
        sortOrder: 0,
      );
      h.server.states['A'] = snapshot(
        'A private',
      ).copyWith(schemaVersion: 2, boardTypes: const [type]);
      await tester.runAsync(() async {
        await h.initialize();
        await h.login('A');
      });
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards);
      final gate = Completer<http.Response>();
      h.server.nextWrite = gate;
      await tester.runAsync(() async {
        unawaited(
          tasks.addTask(
            name: 'Pending typed task',
            deadline: DateTime.now().add(const Duration(days: 1)),
            type: TaskType.unassigned,
            priority: TaskPriority.low,
            typeId: type.id,
          ),
        );
        await settleAsync();
      });
      final pending = tasks.upcomingTasks.single;
      expect(
        tasks.transitions[pending.id]!.phase,
        TaskTransitionPhase.creating,
      );

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
              body: SizedBox(
                width: 400,
                child: TaskCard(task: pending, onToggleComplete: () {}),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(TaskTransitionVisual), findsOneWidget);
      expect(find.text('Test'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      gate.complete(jsonResponse(h.server.states['A']!.toJson()));
      tasks.dispose();
      boards.dispose();
      h.dispose();
    });
  }
}
