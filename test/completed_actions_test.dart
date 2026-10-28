import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/data/models/board.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_column.dart';
import 'support/fakes.dart';

Task task(
  String id, {
  bool completed = false,
  String board = 'default-board',
}) => Task(
  id: id,
  name: id,
  deadline: DateTime(2030),
  createdAt: DateTime(2026),
  typeIndex: 0,
  priorityIndex: 2,
  subject: '',
  boardId: board,
  isCompleted: completed,
);
WorkspaceSnapshot data() => WorkspaceSnapshot(
  boards: [
    Board.create(id: 'default-board', name: 'Current board'),
    Board.create(id: 'other', name: 'Other board', sortOrder: 1),
  ],
  tasks: [
    task('done1', completed: true),
    task('done2', completed: true),
    task('pending'),
    task('otherDone', completed: true, board: 'other'),
  ],
);
final _clear = find.byWidgetPredicate(
  (w) => w is IconButton && w.tooltip == 'Clear Complete Tasks',
);

void main() {
  testWidgets(
    'large clear removes the list without retaining hundreds of outgoing controls',
    (tester) async {
      _viewport(tester, TargetPlatform.windows);
      final f = _Fixture();
      final initial = data().copyWith(
        tasks: [
          for (var i = 0; i < 500; i++) task('done$i', completed: true),
          task('pending'),
        ],
      );
      await tester.runAsync(() => f.initialize(initial: initial));
      await tester.pumpWidget(
        f.app(TargetPlatform.windows, const DashboardScreen()),
      );
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(
          () => f.tasks.clearCompletedTasks(
            boardId: 'default-board',
            taskIds: initial.tasks
                .where((t) => t.isCompleted)
                .map((t) => t.id)
                .toSet(),
          ),
        ),
        isTrue,
      );
      await tester.pump();
      final column = find.byWidgetPredicate(
        (w) => w is TaskColumn && w.title == 'Complete',
      );
      expect(
        find.descendant(of: column, matching: find.byType(TaskCard)),
        findsNothing,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(f.h.workspace.snapshot.tasks.single.id, 'pending');
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
  test(
    'one bulk mutation clears only the confirmed board and completed IDs',
    () async {
      final f = _Fixture();
      await f.initialize();
      final ids = {'done1', 'done2', 'otherDone', 'pending'};
      final result = f.tasks.clearCompletedTasks(
        boardId: 'default-board',
        taskIds: ids,
      );
      ids.clear();
      f.boards.selectBoard('other');
      expect(await result, isTrue);
      expect(f.h.server.writes, 1);
      expect(f.h.workspace.snapshot.tasks.map((t) => t.id), [
        'pending',
        'otherDone',
      ]);
      expect(f.h.workspace.snapshot.boards.length, 2);
      f.dispose();
    },
  );

  test(
    'refresh reconciliation keeps newly completed tasks and tasks marked incomplete',
    () async {
      final f = _Fixture();
      await f.initialize();
      final read = Completer<http.Response>();
      f.h.server.nextRead = read;
      final refreshing = f.h.workspace.refresh();
      final clear = f.tasks.clearCompletedTasks(
        boardId: 'default-board',
        taskIds: {'done1', 'done2'},
      );
      await settleAsync();
      expect(f.h.server.writes, 0);
      final remote = WorkspaceSnapshot(
        revision: 5,
        boards: data().boards,
        tasks: [
          task('done1'),
          task('done2', completed: true),
          task('pending', completed: true),
          task('otherDone', completed: true, board: 'other'),
          task('new', completed: true),
        ],
      );
      f.h.server.states['A'] = remote;
      read.complete(jsonResponse(remote.toJson()));
      await refreshing;
      expect(await clear, isTrue);
      expect(f.h.server.writes, 1);
      expect(f.h.server.writeRevisions, [5]);
      expect(f.h.workspace.snapshot.tasks.map((t) => t.id), [
        'done1',
        'pending',
        'otherDone',
        'new',
      ]);
      expect(f.h.workspace.snapshot.tasks.first.isCompleted, isFalse);
      f.dispose();
    },
  );

  test(
    'a changed confirmation with no remaining eligible IDs does not write',
    () async {
      final f = _Fixture();
      await f.initialize();
      expect(
        await f.tasks.clearCompletedTasks(
          boardId: 'default-board',
          taskIds: {'pending', 'otherDone'},
        ),
        isFalse,
      );
      expect(f.h.server.writes, 0);
      expect(f.h.workspace.snapshot.tasks.length, 4);
      f.dispose();
    },
  );

  test(
    'revision conflict preserves confirmed tasks and reports the failure',
    () async {
      final f = _Fixture();
      await f.initialize();
      f.h.server.conflict = true;
      expect(
        await f.tasks.clearCompletedTasks(
          boardId: 'default-board',
          taskIds: {'done1', 'done2'},
        ),
        isFalse,
      );
      expect(f.h.workspace.snapshot.tasks.length, 4);
      expect(f.h.workspace.error, contains('Another device'));
      f.dispose();
    },
  );

  test(
    'an accepted clear cannot cross an account change while waiting for refresh',
    () async {
      final f = _Fixture();
      await f.initialize();
      final read = Completer<http.Response>();
      f.h.server.nextRead = read;
      final refreshing = f.h.workspace.refresh();
      final clear = f.tasks.clearCompletedTasks(
        boardId: 'default-board',
        taskIds: {'done1', 'done2'},
      );
      await f.h.auth.signOut();
      await f.h.login('B');
      read.complete(jsonResponse(data().toJson()));
      await refreshing;
      expect(await clear, isFalse);
      expect(f.h.server.writes, 0);
      expect(f.h.workspace.ownerId, 'B');
      f.dispose();
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      '$platform bulk clear is beside its count, confirms, and submits once',
      (tester) async {
        _viewport(tester, platform);
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        await tester.pumpWidget(f.app(platform, const DashboardScreen()));
        await tester.pumpAndSettle();
        if (platform == TargetPlatform.android) {
          await tester.tap(find.byTooltip('Completed'));
          await tester.pumpAndSettle();
        }
        expect(_clear, findsOneWidget);
        final column = find.byWidgetPredicate(
          (w) =>
              w is TaskColumn &&
              (w.title == 'Complete' || w.title == 'Completed'),
        );
        final count = find.descendant(of: column, matching: find.text('2'));
        expect(
          tester.getRect(_clear).right,
          lessThanOrEqualTo(tester.getRect(count).left),
        );
        await tester.tap(_clear);
        await tester.pumpAndSettle();
        expect(
          find.text('Delete 2 completed tasks from "Current board"?'),
          findsOneWidget,
        );
        expect(tester.widget<IconButton>(_clear).onPressed, isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(f.h.server.writes, 0);
        final pending = Completer<http.Response>();
        f.h.server.nextWrite = pending;
        await tester.tap(_clear);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear'));
        await tester.pump();
        await tester.runAsync(settleAsync);
        await tester.pump();
        await tester.runAsync(settleAsync);
        expect(
          f.h.server.writes,
          1,
          reason:
              'error=${f.h.workspace.error}; saving=${f.h.workspace.isSaving}; loading=${f.h.workspace.isLoading}; clearing=${find.text('Clearing…').evaluate().length}',
        );
        expect(find.text('Clearing…'), findsOneWidget);
        expect(tester.widget<IconButton>(_clear).onPressed, isNull);
        pending.complete(jsonResponse(f.h.server.states['A']!.toJson()));
        await tester.runAsync(settleAsync);
        await tester.pump();
        await tester.runAsync(settleAsync);
        await tester.pumpAndSettle();
        expect(find.text('Clearing…'), findsNothing);
        expect(f.h.workspace.snapshot.tasks.map((t) => t.id), [
          'pending',
          'otherDone',
        ]);
        expect(tester.widget<IconButton>(_clear).onPressed, isNull);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );

    testWidgets(
      '$platform clear is disabled offline and when this board has no completed tasks',
      (tester) async {
        _viewport(tester, platform);
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        f.h.server.offline = true;
        await tester.runAsync(f.h.workspace.refresh);
        await tester.pumpWidget(f.app(platform, const DashboardScreen()));
        await tester.pumpAndSettle();
        if (platform == TargetPlatform.android) {
          await tester.tap(find.byTooltip('Completed'));
          await tester.pumpAndSettle();
        }
        expect(tester.widget<IconButton>(_clear).onPressed, isNull);
        await tester.runAsync(() async {
          f.h.server.offline = false;
          f.h.server.states['A'] = data().copyWith(
            tasks: [
              task('pending'),
              task('otherDone', completed: true, board: 'other'),
            ],
          );
          await f.h.workspace.refresh();
        });
        await tester.pumpAndSettle();
        expect(tester.widget<IconButton>(_clear).onPressed, isNull);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );

    for (final subject in ['', 'A subject']) {
      for (final level in TaskPriority.values) {
        testWidgets(
          '$platform ${level.label} priority aligns with deletion and has title separation, subject=$subject',
          (tester) async {
            final f = _Fixture();
            await tester.runAsync(f.initialize);
            final sample = task(
              'A wrapping task title that uses several lines',
            ).copyWith(priority: level)..subject = subject;
            await tester.pumpWidget(
              f.app(
                platform,
                Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 260,
                    child: TaskCard(
                      task: sample,
                      onToggleComplete: () {},
                      onDelete: () {},
                      onEdit: () {},
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (platform == TargetPlatform.windows) {
              final mouse = await tester.createGesture(
                kind: PointerDeviceKind.mouse,
              );
              await mouse.addPointer();
              await mouse.moveTo(tester.getCenter(find.byType(TaskCard)));
              await tester.pumpAndSettle();
              addTearDown(mouse.removePointer);
            }
            final priority = find.byTooltip('${level.label} priority');
            final deletion = find.byIcon(Icons.delete_outline_rounded);
            expect(
              tester.getCenter(priority).dx,
              closeTo(tester.getCenter(deletion).dx, 0.1),
            );
            expect(
              tester.getRect(priority).left -
                  tester.getRect(find.text(sample.name)).right,
              greaterThanOrEqualTo(8),
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            f.dispose();
          },
        );
      }
    }
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'clear action preserves the original header height on $platform at $scale',
        (tester) async {
          _viewport(tester, platform);
          final f = _Fixture();
          await tester.runAsync(f.initialize);
          Widget column({Future<void> Function()? onClear}) => f.app(
            platform,
            Scaffold(
              body: TaskColumn(
                title: 'Completed',
                tasks: [task('done', completed: true)],
                headerColor: Colors.green,
                headerBackgroundColor: Colors.green.shade100,
                icon: Icons.check_circle_rounded,
                onToggleComplete: (_) {},
                onClearCompleted: onClear,
              ),
            ),
            scale: scale,
          );
          final header = find
              .ancestor(
                of: find.text('Completed'),
                matching: find.byType(AnimatedContainer),
              )
              .first;
          await tester.pumpWidget(column());
          await tester.pumpAndSettle();
          final originalHeight = tester.getSize(header).height;
          final originalTitleY = tester.getCenter(find.text('Completed')).dy;

          await tester.pumpWidget(column(onClear: () async {}));
          await tester.pumpAndSettle();
          expect(tester.getSize(header).height, originalHeight);
          expect(tester.getCenter(find.text('Completed')).dy, originalTitleY);
          final buttonRect = tester.getRect(_clear);
          final headerRect = tester.getRect(header);
          expect(buttonRect.top, greaterThanOrEqualTo(headerRect.top));
          expect(buttonRect.bottom, lessThanOrEqualTo(headerRect.bottom));
          expect(_clear.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          f.dispose();
        },
      );
    }
  }

  for (final width in [320.0, 393.0]) {
    testWidgets(
      'completed header controls remain reachable at $width and large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        await tester.pumpWidget(
          f.app(TargetPlatform.android, const DashboardScreen(), scale: 1.8),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Completed'));
        await tester.pumpAndSettle();
        expect(tester.getSize(_clear), const Size(48, 48));
        expect(_clear.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }
}

void _viewport(WidgetTester tester, TargetPlatform platform) {
  tester.view.physicalSize = Size(
    platform == TargetPlatform.android ? 393 : 1280,
    900,
  );
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Fixture {
  final h = Harness();
  late final boards = BoardsProvider(h.workspace);
  late final tasks = TasksProvider(h.workspace, boards);
  Future<void> initialize({WorkspaceSnapshot? initial}) async {
    h.server.states['A'] = initial ?? data();
    await h.initialize();
    await h.login('A');
    boards;
    tasks;
  }

  Widget app(TargetPlatform platform, Widget child, {double scale = 1}) =>
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: h.auth),
          ChangeNotifierProvider<WorkspaceController>.value(value: h.workspace),
          ChangeNotifierProvider<BoardsProvider>.value(value: boards),
          ChangeNotifierProvider<TasksProvider>.value(value: tasks),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      );
  void dispose() {
    tasks.dispose();
    boards.dispose();
    h.dispose();
  }
}
