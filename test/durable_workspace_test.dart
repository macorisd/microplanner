import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/cloud_status_card.dart';
import 'package:microplanner/features/tasks/presentation/widgets/failed_actions_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_transition_visual.dart';
import 'package:microplanner/features/tasks/providers/task_transitions.dart';
import 'support/fakes.dart';

class _Cache extends MemoryCache implements WorkspaceJournal, WorkspaceHistory {
  final journals = <String, String>{};
  final seen = <String, DateTime>{};
  @override
  Future<String?> readJournal(String ownerId) async => journals[ownerId];
  @override
  Future<void> writeJournal(String ownerId, String value) async =>
      journals[ownerId] = value;
  @override
  Future<DateTime?> readSeenAt(String ownerId) async => seen[ownerId];
  @override
  Future<void> markSeenAt(String ownerId, DateTime time) async {
    seen[ownerId] = time;
  }
}

class _IdempotentServer extends FakeServer {
  final committed = <String, Set<String>>{};
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'PUT' && request.url.path == '/workspace') {
      final owner = (request.headers['authorization'] ?? '').replaceFirst(
        'Bearer token-',
        '',
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final id = body['operationId'] as String;
      final ids = committed.putIfAbsent(owner, () => {});
      if (ids.contains(id)) return jsonResponse(states[owner]!.toJson());
      ids.add(id);
    }
    return super.handle(request);
  }
}

class _RejectFirstServer extends FakeServer {
  final first = Completer<void>();
  bool reject = true;
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.method == 'PUT' && reject) {
      reject = false;
      await first.future;
      return jsonResponse({
        'code': 'bad',
        'message': 'The action was rejected.',
      }, 400);
    }
    return super.handle(request);
  }
}

void main() {
  test(
    'startup compares the cached observation with the first cloud snapshot',
    () async {
      final now = DateTime(2030, 1, 2, 12);
      final due = Task.create(
        id: 'due',
        name: 'Due',
        boardId: 'default-board',
        deadline: now.subtract(const Duration(minutes: 1)),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      final cached = snapshot('Board').copyWith(tasks: [due]);
      final cache = _Cache()
        ..values['A'] = cached
        ..seen['A'] = now.subtract(const Duration(hours: 1));
      final h = Harness(cache: cache);
      h.server.states['A'] = cached;
      await h.initialize();
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards, now: () => now);
      await h.login('A');
      expect(tasks.transitions['due']?.from, TaskColumnKind.upcoming);
      expect(tasks.transitions['due']?.to, TaskColumnKind.late);
      expect(tasks.upcomingTasks.map((item) => item.id), contains('due'));
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
  testWidgets(
    'a pending completion paints the source and blocks only that task',
    (tester) async {
      tester.view.physicalSize = const Size(900, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = Harness(cache: _Cache());
      final original = Task.create(
        id: 'one',
        name: 'One',
        boardId: 'default-board',
        deadline: DateTime(2030),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      final other = original.copyWith(id: 'two', name: 'Two');
      h.server.states['A'] = h.server.states['A']!.copyWith(
        tasks: [original, other],
      );
      await tester.runAsync(() async {
        await h.initialize();
        await h.login('A');
      });
      final boards = BoardsProvider(h.workspace);
      var now = DateTime.now();
      final tasks = TasksProvider(h.workspace, boards, now: () => now);
      final gate = Completer<http.Response>();
      h.server.nextWrite = gate;
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
            home: Scaffold(
              body: Column(
                children: [
                  TaskCard(
                    task: original,
                    onToggleComplete: () => tasks.toggleTaskCompletion('one'),
                    onEdit: () {},
                    onDelete: () {},
                  ),
                  TaskCard(
                    task: other,
                    onToggleComplete: () => tasks.toggleTaskCompletion('two'),
                    onEdit: () {},
                    onDelete: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final result = tasks.toggleTaskCompletion('one');
      await tester.pump();
      final visual = tester.widget<TaskTransitionVisual>(
        find.byType(TaskTransitionVisual),
      );
      expect(visual.visual.target, TaskColumnKind.completed);
      expect(visual.visual.phase, TaskTransitionPhase.source);
      expect(tasks.upcomingTasks.map((task) => task.id), contains('one'));
      expect(await tasks.toggleTaskCompletion('one'), isFalse);
      expect(tasks.transitions.locked('two'), isFalse);
      await tester.runAsync(() async {
        await settleAsync();
        gate.complete(jsonResponse(h.server.states['A']!.toJson()));
        await settleAsync();
      });
      expect(await result, isTrue);
      now = now.add(const Duration(milliseconds: 501));
      await tester.pump(const Duration(milliseconds: 501));
      expect(tasks.completedTasks.map((task) => task.id), contains('one'));
      now = now.add(const Duration(milliseconds: 381));
      await tester.pump(const Duration(milliseconds: 381));
      expect(tasks.transitions.locked('one'), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
  testWidgets(
    'a rejected creation keeps a reviewable draft after its form closes',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final server = _RejectFirstServer();
      final h = Harness(cache: _Cache(), server: server);
      await tester.runAsync(() async {
        await h.initialize();
        await h.login('A');
      });
      final boards = BoardsProvider(h.workspace);
      var transitionTime = DateTime.now();
      final tasks = TasksProvider(
        h.workspace,
        boards,
        now: () => transitionTime,
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
            home: Scaffold(
              body: Column(
                children: [
                  CloudStatusCard(workspace: h.workspace),
                  Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => AddTaskDialog(onSave: tasks.addTask),
                      ),
                      child: const Text('Open'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Saved draft');
      await tester.pump();
      await tester.tap(find.text('Create Task'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AddTaskDialog), findsNothing);
      await tester.runAsync(() async {
        server.first.complete();
        await settleAsync();
      });
      transitionTime = transitionTime.add(const Duration(milliseconds: 510));
      await tester.pump(const Duration(milliseconds: 510));
      transitionTime = transitionTime.add(const Duration(milliseconds: 390));
      await tester.pump(const Duration(milliseconds: 390));
      expect(h.workspace.outbox!.hasFailures, isTrue);
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(find.byType(FailedActionsDialog), findsOneWidget);
      expect(find.text('Saved draft'), findsOneWidget);
      await tester.tap(find.text('Review draft'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(find.byType(TextFormField).first)
            .controller!
            .text,
        'Saved draft',
      );
      await tester.enterText(find.byType(TextFormField).first, 'Revised draft');
      await tester.pump();
      await tester.tap(find.text('Create Task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(settleAsync);
      await tester.pump();
      expect(h.workspace.snapshot.tasks.single.name, 'Revised draft');
      expect(h.workspace.outbox!.hasFailures, isFalse);
      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
  testWidgets(
    'a queued create closes the form while its request is still pending',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final h = Harness(cache: _Cache());
      await tester.runAsync(() async {
        await h.initialize();
        await h.login('A');
      });
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards);
      final gate = Completer<http.Response>();
      h.server.nextWrite = gate;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WorkspaceController>.value(
              value: h.workspace,
            ),
            ChangeNotifierProvider<BoardsProvider>.value(value: boards),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AddTaskDialog(onSave: tasks.addTask),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).first,
        'Background task',
      );
      await tester.pump();
      await tester.tap(find.text('Create Task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(AddTaskDialog), findsNothing);
      expect(h.workspace.snapshot.tasks.single.name, 'Background task');
      expect(h.workspace.outbox!.hasPending, isTrue);
      await tester.runAsync(() async {
        await settleAsync();
        gate.complete(jsonResponse(h.server.states['A']!.toJson()));
        await settleAsync();
      });
      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
  test('refresh requested during a save runs after it finishes', () async {
    final h = Harness(cache: _Cache());
    await h.initialize();
    await h.login('A');
    final boards = BoardsProvider(h.workspace);
    final tasks = TasksProvider(h.workspace, boards);
    final gate = Completer<http.Response>();
    h.server.nextWrite = gate;
    final pending = tasks.addTask(
      name: 'Pending',
      deadline: DateTime(2030),
      type: TaskType.unassigned,
      priority: TaskPriority.low,
    );
    await settleAsync();
    final reads = h.server.reads;
    final refresh = h.workspace.refresh();
    await settleAsync();
    expect(h.server.reads, reads);
    gate.complete(jsonResponse(h.server.states['A']!.toJson()));
    expect(await pending, isTrue);
    await refresh;
    expect(h.server.reads, reads + 1);
    expect(h.workspace.snapshot.tasks.single.name, 'Pending');
    tasks.dispose();
    boards.dispose();
    h.dispose();
  });
  test(
    'a stale task form preserves unrelated edits and reports conflicting edits',
    () async {
      final h = Harness(cache: _Cache());
      final original = Task.create(
        id: 'one',
        name: 'Original',
        boardId: 'default-board',
        deadline: DateTime(2030),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      h.server.states['A'] = h.server.states['A']!.copyWith(tasks: [original]);
      await h.initialize();
      await h.login('A');
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards);
      h.server.states['A'] = h.server.states['A']!.copyWith(
        tasks: [original.copyWith(description: 'Updated elsewhere')],
      );
      await h.workspace.refresh();
      expect(
        await tasks.updateTask(
          original.copyWith(name: 'My edit'),
          original: original,
        ),
        isTrue,
      );
      expect(h.workspace.snapshot.tasks.single.name, 'My edit');
      expect(
        h.workspace.snapshot.tasks.single.description,
        'Updated elsewhere',
      );
      final stale = h.workspace.snapshot.tasks.single;
      h.server.states['A'] = h.server.states['A']!.copyWith(
        tasks: [stale.copyWith(name: 'Another device')],
      );
      await h.workspace.refresh();
      expect(
        await tasks.updateTask(
          stale.copyWith(name: 'My conflicting draft'),
          original: stale,
        ),
        isFalse,
      );
      expect(h.workspace.snapshot.tasks.single.name, 'Another device');
      expect(
        h.workspace.outbox!.operations.single.delta.items.single.after!['name'],
        'My conflicting draft',
      );
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
  test(
    'accepted task creations appear pending and serialize without losing either',
    () async {
      final h = Harness(cache: _Cache());
      await h.initialize();
      await h.login('A');
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards);
      final pending = Completer<http.Response>();
      h.server.nextWrite = pending;
      Future<bool> add(String name) => tasks.addTask(
        name: name,
        deadline: DateTime(2030),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      final first = add('First pending');
      await settleAsync();
      final second = add('Second pending');
      await settleAsync();
      expect(h.workspace.snapshot.tasks.map((task) => task.name), [
        'First pending',
        'Second pending',
      ]);
      expect(h.workspace.outbox!.pendingTaskIds.length, 2);
      expect(
        (jsonDecode((h.cache as _Cache).journals['A']!)['operations'] as List)
            .length,
        2,
      );
      expect(h.server.writes, 1);
      pending.complete(jsonResponse(h.server.states['A']!.toJson()));
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(h.workspace.snapshot.tasks.map((task) => task.name), [
        'First pending',
        'Second pending',
      ]);
      expect(h.workspace.outbox!.hasPending, isFalse);
      expect(h.server.writeRevisions, [0, 1]);
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );

  test(
    'signing out mid-send keeps the request for the same account and does not replay it for another',
    () async {
      final cache = _Cache();
      final server = _IdempotentServer();
      final h = Harness(cache: cache, server: server);
      await h.initialize();
      await h.login('A');
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards);
      final pending = Completer<http.Response>();
      server.nextWrite = pending;
      final result = tasks.addTask(
        name: 'Recoverable',
        deadline: DateTime(2030),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      await settleAsync();
      expect(server.writes, 1);
      await h.auth.signOut();
      await h.login('B');
      await settleAsync();
      expect(await result, isFalse);
      expect(h.workspace.snapshot.tasks, isEmpty);
      expect(h.workspace.outbox!.operations, isEmpty);
      await h.auth.signOut();
      await h.login('A');
      await settleAsync();
      expect(h.workspace.snapshot.tasks.single.name, 'Recoverable');
      expect(server.writes, 1);
      expect(h.workspace.outbox!.hasPending, isFalse);
      pending.complete(jsonResponse(server.states['A']!.toJson()));
      await settleAsync();
      expect(h.workspace.snapshot.tasks.single.name, 'Recoverable');
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
}
