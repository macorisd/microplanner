import 'dart:ui' show PointerDeviceKind;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'package:microplanner/features/tasks/presentation/widgets/sidebar.dart';
import 'package:microplanner/features/tasks/presentation/widgets/account_pages.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';

import 'support/fakes.dart';

class _JournalCache extends MemoryCache implements WorkspaceJournal {
  final journals = <String, String>{};
  @override
  Future<String?> readJournal(String ownerId) async => journals[ownerId];
  @override
  Future<void> writeJournal(String ownerId, String value) async =>
      journals[ownerId] = value;
}

void main() {
  testWidgets(
    'default list editor closes after durable acceptance while cloud save waits',
    (tester) async {
      final harness = Harness(cache: _JournalCache());
      await tester.runAsync(() async {
        await harness.initialize();
        await harness.login('A');
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: harness.auth),
            ChangeNotifierProvider<WorkspaceController>.value(
              value: harness.workspace,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: SettingsPage(onBack: () {})),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Customization',
        'Boards',
        'Default lists of task types',
        'New list',
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField), 'Queued default list');
      final gate = Completer<http.Response>();
      harness.server.nextWrite = gate;
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.runAsync(settleAsync);
      await tester.pumpAndSettle();
      expect(find.text('New default list'), findsNothing);
      expect(find.text('Queued default list'), findsOneWidget);
      expect(harness.workspace.outbox!.hasPending, isTrue);
      gate.complete(jsonResponse(harness.server.states['A']!.toJson()));
      await tester.runAsync(settleAsync);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      harness.dispose();
    },
  );

  testWidgets('board editor starts from the latest queued board changes', (
    tester,
  ) async {
    final harness = Harness(cache: _JournalCache());
    await tester.runAsync(() async {
      await harness.initialize();
      await harness.login('A');
    });
    final boards = BoardsProvider(harness.workspace);
    final tasks = TasksProvider(harness.workspace, boards);
    final gate = Completer<http.Response>();
    harness.server.nextWrite = gate;
    late Future<bool> pending;
    await tester.runAsync(() async {
      pending = harness.workspace.mutate(
        (snapshot) => snapshot.copyWith(
          boards: [snapshot.boards.single.copyWith(name: 'Queued board name')],
        ),
      );
      await settleAsync();
    });
    expect(harness.workspace.snapshot.boards.single.name, 'A private');
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: harness.auth),
          ChangeNotifierProvider<WorkspaceController>.value(
            value: harness.workspace,
          ),
          ChangeNotifierProvider<BoardsProvider>.value(value: boards),
          ChangeNotifierProvider<TasksProvider>.value(value: tasks),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.descendant(
      of: find.byType(Sidebar),
      matching: find.text('A private'),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(row));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit board'));
    await tester.pumpAndSettle();
    expect(find.text('Queued board name'), findsOneWidget);
    gate.complete(jsonResponse(harness.server.states['A']!.toJson()));
    await tester.runAsync(() async {
      await pending;
      await settleAsync();
    });
    await tester.pumpAndSettle();
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    tasks.dispose();
    boards.dispose();
    harness.dispose();
  });

  testWidgets('Android board editor and icon picker fit a narrow phone', (
    tester,
  ) async {
    final harness = Harness(cache: _JournalCache());
    await tester.runAsync(() async {
      await harness.initialize();
      await harness.login('A');
    });
    final boards = BoardsProvider(harness.workspace);
    final tasks = TasksProvider(harness.workspace, boards);
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthService>.value(value: harness.auth),
          ChangeNotifierProvider<WorkspaceController>.value(
            value: harness.workspace,
          ),
          ChangeNotifierProvider<BoardsProvider>.value(value: boards),
          ChangeNotifierProvider<TasksProvider>.value(value: tasks),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          home: const DashboardScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Board actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit board'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose icon'));
    await tester.pumpAndSettle();
    expect(find.text('Choose an icon'), findsOneWidget);
    await tester.tap(find.byTooltip('school'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    tasks.dispose();
    boards.dispose();
    harness.dispose();
  });

  testWidgets(
    'sidebar navigates to weekly plan, profile, settings and back to a board',
    (tester) async {
      final harness = Harness(cache: _JournalCache());
      await tester.runAsync(() async {
        await harness.initialize();
        await harness.login('A');
      });
      final boards = BoardsProvider(harness.workspace);
      final tasks = TasksProvider(harness.workspace, boards);
      tester.view.physicalSize = const Size(1200, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: harness.auth),
            ChangeNotifierProvider<WorkspaceController>.value(
              value: harness.workspace,
            ),
            ChangeNotifierProvider<BoardsProvider>.value(value: boards),
            ChangeNotifierProvider<TasksProvider>.value(value: tasks),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Weekly Plan'), findsOneWidget);
      expect(find.text('Boards'), findsOneWidget);
      await tester.tap(find.text('Weekly Plan'));
      await tester.pumpAndSettle();
      expect(find.text('Coming Soon'), findsOneWidget);
      expect(find.text('New Task'), findsNothing);
      await tester.tap(find.text('A@example.com'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out'), findsOneWidget);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customization'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Boards').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Default lists of task types'));
      await tester.pumpAndSettle();
      expect(find.text('Academic tasks'), findsOneWidget);
      final row = find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('A private'),
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('Coming Soon'), findsNothing);
      expect(find.text('New Task'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
      boards.dispose();
      harness.dispose();
    },
  );

  testWidgets(
    'removing a type warns of affected tasks and clears the assignment',
    (tester) async {
      final harness = Harness(cache: _JournalCache());
      harness.server.states['A'] = snapshot('Test board').copyWith(
        tasks: [
          Task.create(
            id: 'task',
            name: 'Existing task',
            deadline: DateTime(2030),
            type: TaskType.homework,
            priority: TaskPriority.low,
            boardId: 'default-board',
          ),
        ],
      );
      await tester.runAsync(() async {
        await harness.initialize();
        await harness.login('A');
      });
      final boards = BoardsProvider(harness.workspace);
      final tasks = TasksProvider(harness.workspace, boards);
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthService>.value(value: harness.auth),
            ChangeNotifierProvider<WorkspaceController>.value(
              value: harness.workspace,
            ),
            ChangeNotifierProvider<BoardsProvider>.value(value: boards),
            ChangeNotifierProvider<TasksProvider>.value(value: tasks),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: const DashboardScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.descendant(
        of: find.byType(Sidebar),
        matching: find.text('Test board'),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(row));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit board'));
      await tester.pumpAndSettle();
      final tile = find.ancestor(
        of: find.text('Homework'),
        matching: find.byType(ListTile),
      );
      final remove = find.descendant(
        of: tile,
        matching: find.byTooltip('Remove task type'),
      );
      await tester.ensureVisible(remove);
      await tester.tap(remove);
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.textContaining('task type from 1 task'), findsOneWidget);
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Save changes'),
      );
      await tester.runAsync(() async {
        await tester.tap(confirm);
        await settleAsync();
      });
      await tester.pumpAndSettle();
      expect(harness.workspace.snapshot.tasks.single.typeId, isNull);
      expect(
        harness.workspace.snapshot.boardTypes.where(
          (type) => type.name == 'Homework',
        ),
        isEmpty,
      );
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      tasks.dispose();
      boards.dispose();
      harness.dispose();
    },
  );
}
