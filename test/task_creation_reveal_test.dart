import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/data/workspace_storage.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/account_dashboard.dart';
import 'package:microplanner/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_column.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_transition_visual.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:provider/provider.dart';

import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('$platform centers an accepted task when the list can scroll', (
      tester,
    ) async {
      _viewport(tester, platform);
      final now = DateTime.now();
      final f = _Fixture(
        tasks: [..._beforeTasks(now, 18), ..._afterTasks(now, 8)],
      );
      await tester.runAsync(f.initialize);
      f.boards.selectColumn(platform == TargetPlatform.android ? 0 : 2);
      await tester.pumpWidget(f.app(platform));
      await tester.pumpAndSettle();

      await _create(tester, f, 'A newly centered task');
      expect(f.tasks.latestCreatedTask, isNotNull);
      await tester.pump(const Duration(milliseconds: 250));
      expect(f.boards.currentColumnIndex, 2);
      final scroll = _scrollPosition(tester, 'Upcoming');
      final samples = <double>[];
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        samples.add(scroll.pixels);
      }
      expect(f.boards.currentColumnIndex, 2);
      expect(
        find.text('A newly centered task', skipOffstage: false),
        findsOneWidget,
      );
      expect(samples.toSet().length, greaterThan(2));
      final card = tester.getRect(_card('A newly centered task'));
      final viewport = tester.getRect(
        find.descendant(
          of: _column('Upcoming'),
          matching: find.byType(AnimatedList),
        ),
      );
      expect(card.center.dy, closeTo(viewport.center.dy, 2));
      expect(scroll.pixels, greaterThan(scroll.minScrollExtent));
      expect(scroll.pixels, lessThan(scroll.maxScrollExtent));

      await _finish(tester, f);
    });

    testWidgets('$platform clamps reveal at the top and bottom limits', (
      tester,
    ) async {
      _viewport(tester, platform);
      final now = DateTime.now();
      for (final atEnd in [false, true]) {
        final f = _Fixture(
          tasks: atEnd
              ? _beforeTasks(now, 24)
              : [_beforeTasks(now, 1).single, ..._afterTasks(now, 24)],
        );
        await tester.runAsync(f.initialize);
        f.boards.selectColumn(platform == TargetPlatform.android ? 0 : 2);
        await tester.pumpWidget(f.app(platform));
        await tester.pumpAndSettle();

        final name = atEnd ? 'At the final limit' : 'Near the top limit';
        await _create(tester, f, name);
        await _waitForReveal(tester);
        final scroll = _scrollPosition(tester, 'Upcoming');
        expect(
          scroll.pixels,
          closeTo(atEnd ? scroll.maxScrollExtent : scroll.minScrollExtent, 0.5),
        );
        expect(scroll.maxScrollExtent, greaterThan(scroll.minScrollExtent));

        await _finish(tester, f);
      }
    });

    testWidgets('$platform leaves a non-scrollable task list in place', (
      tester,
    ) async {
      _viewport(tester, platform);
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app(platform));
      await tester.pumpAndSettle();

      await _create(tester, f, 'Only task');
      await _waitForReveal(tester);
      final scroll = _scrollPosition(tester, 'Upcoming');
      expect(scroll.minScrollExtent, closeTo(scroll.maxScrollExtent, 0.5));
      expect(scroll.pixels, closeTo(scroll.minScrollExtent, 0.5));

      await _finish(tester, f);
    });

    testWidgets('$platform editing keeps the current list position', (
      tester,
    ) async {
      _viewport(tester, platform);
      final f = _Fixture(tasks: _beforeTasks(DateTime.now(), 30));
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app(platform));
      await tester.pumpAndSettle();

      final scroll = _scrollPosition(tester, 'Upcoming');
      scroll.jumpTo(600);
      await tester.pump();
      final visible = find
          .textContaining('Existing before')
          .hitTestable()
          .first;
      await tester.tap(visible);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(EditableText).first,
        'Edited without revealing',
      );
      await tester.pump();
      await tester.tap(find.text('Save changes'));
      await tester.pump();
      await tester.runAsync(settleAsync);
      await tester.pumpAndSettle();

      expect(scroll.pixels, closeTo(600, 0.5));
      await _finish(tester, f);
    });

    testWidgets('$platform keeps creation feedback during the reveal', (
      tester,
    ) async {
      _viewport(tester, platform);
      final now = DateTime.now();
      final f = _Fixture(
        tasks: [..._beforeTasks(now, 8), ..._afterTasks(now, 8)],
      );
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app(platform));
      await tester.pumpAndSettle();

      final gate = await _create(
        tester,
        f,
        'Visible while syncing',
        holdWrite: true,
      );
      await _waitForReveal(tester);
      expect(find.byType(TaskTransitionVisual), findsOneWidget);
      expect(
        f.tasks.tasks.singleWhere(
          (task) => task.name == 'Visible while syncing',
        ),
        isNotNull,
      );

      gate!.complete(jsonResponse(f.h.server.states['A']!.toJson()));
      await _finish(tester, f);
    });
  }
}

void _viewport(WidgetTester tester, TargetPlatform platform) {
  tester.view.physicalSize = platform == TargetPlatform.android
      ? const Size(393, 800)
      : const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

List<Task> _beforeTasks(DateTime now, int count) => [
  for (var i = 0; i < count; i++)
    Task.create(
      id: 'before-$i',
      name: 'Existing before $i',
      boardId: 'default-board',
      deadline: now.add(Duration(hours: i + 1)),
      type: TaskType.unassigned,
      priority: TaskPriority.low,
    ),
];

List<Task> _afterTasks(DateTime now, int count) => [
  for (var i = 0; i < count; i++)
    Task.create(
      id: 'after-$i',
      name: 'Existing after $i',
      boardId: 'default-board',
      deadline: now.add(Duration(days: i + 2)),
      type: TaskType.unassigned,
      priority: TaskPriority.low,
    ),
];

Finder _column(String title) => find.byWidgetPredicate(
  (widget) => widget is TaskColumn && widget.title == title,
  skipOffstage: false,
);

Finder _card(String name) => find
    .ancestor(
      of: find.text(name, skipOffstage: false),
      matching: find.byType(TaskCard, skipOffstage: false),
    )
    .first;

ScrollPosition _scrollPosition(WidgetTester tester, String column) {
  final scrollable = tester.widget<Scrollable>(
    find.descendant(
      of: _column(column),
      matching: find.byType(Scrollable, skipOffstage: false),
      skipOffstage: false,
    ),
  );
  return scrollable.controller!.position;
}

Future<Completer<http.Response>?> _create(
  WidgetTester tester,
  _Fixture fixture,
  String name, {
  bool holdWrite = false,
}) async {
  await tester.tap(find.text('New Task').hitTestable().first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(EditableText).first, name);
  await tester.pumpAndSettle();
  final create = find.text('Create task').hitTestable();
  expect(create, findsOneWidget);
  await tester.ensureVisible(create);
  await tester.pumpAndSettle();
  final gate = holdWrite ? Completer<http.Response>() : null;
  fixture.h.server.nextWrite = gate;
  await tester.tap(create);
  await tester.pump();
  await tester.runAsync(settleAsync);
  await tester.pump();
  for (var i = 0; i < 40; i++) {
    if (find.byType(AddTaskDialog).evaluate().isEmpty) break;
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(find.byType(AddTaskDialog), findsNothing);
  return gate;
}

Future<void> _waitForReveal(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _finish(WidgetTester tester, _Fixture fixture) async {
  await tester.runAsync(settleAsync);
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox());
  fixture.dispose();
}

class _Fixture {
  _Fixture({List<Task> tasks = const []}) {
    h.server.states['A'] = snapshot('A private').copyWith(tasks: tasks);
  }

  final h = Harness(cache: _JournalCache());
  late final boards = BoardsProvider(h.workspace);
  late final tasks = TasksProvider(h.workspace, boards);

  Future<void> initialize() async {
    await h.initialize();
    boards;
    tasks;
    await h.login('A');
  }

  Widget app(TargetPlatform platform) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: h.auth),
      ChangeNotifierProvider<WorkspaceController>.value(value: h.workspace),
      ChangeNotifierProvider<BoardsProvider>.value(value: boards),
      ChangeNotifierProvider<TasksProvider>.value(value: tasks),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB')],
      home: const AccountDashboard(),
    ),
  );

  void dispose() {
    tasks.dispose();
    boards.dispose();
    h.dispose();
  }
}

class _JournalCache extends MemoryCache implements WorkspaceJournal {
  final journals = <String, String>{};

  @override
  Future<String?> readJournal(String ownerId) async => journals[ownerId];

  @override
  Future<void> writeJournal(String ownerId, String value) async {
    journals[ownerId] = value;
  }
}
