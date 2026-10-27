import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/theme/app_motion.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/presentation/account_dashboard.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'package:microplanner/features/tasks/presentation/widgets/android_board_carousel.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_column.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'support/fakes.dart';

void main() {
  for (final (width, scale) in [
    (320.0, 1.0),
    (393.0, 1.0),
    (1280.0, 1.0),
    (320.0, 1.6),
  ]) {
    testWidgets('cloud notice keeps geometry fixed at $width, text $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app(textScale: scale));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(TaskColumn).first);
      final pending = Completer<http.Response>();
      f.h.server.nextRead = pending;
      final refresh = f.h.workspace.refresh();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('Loading your data'), findsNothing);
      expect(tester.getRect(find.byType(TaskColumn).first), rect);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Loading your data'), findsOneWidget);
      expect(tester.getRect(find.byType(TaskColumn).first), rect);
      pending.complete(jsonResponse(f.h.server.states['A']!.toJson()));
      await tester.runAsync(() async => refresh);
      await tester.pumpAndSettle();
      expect(find.text('Loading your data'), findsNothing);
      expect(tester.getRect(find.byType(TaskColumn).first), rect);
      await tester.runAsync(() async {
        f.h.server.offline = true;
        await f.h.workspace.refresh();
      });
      await tester.pumpAndSettle();
      expect(find.text('Connection needs attention'), findsOneWidget);
      expect(tester.getRect(find.byType(TaskColumn).first), rect);
      expect(f.h.workspace.canWrite, isFalse);
      await tester.runAsync(() async {
        f.h.server.offline = false;
        await f.h.workspace.refresh();
      });
      await tester.pumpAndSettle();
      expect(find.text('Connection needs attention'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    });
  }

  testWidgets(
    'animated task lists settle after fast edits, reorders and removals',
    (tester) async {
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app());
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await f.add('First', DateTime(2030, 6, 16));
        await f.add('Second', DateTime(2030, 6, 17));
      });
      await tester.pump(const Duration(milliseconds: 30));
      final first = f.tasks.tasks.first;
      await tester.runAsync(
        () => f.tasks.updateTask(
          first.copyWith(name: 'Edited', deadline: DateTime(2030, 6, 18)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => f.tasks.deleteTask(f.tasks.tasks.last.id));
      await tester.pump(const Duration(milliseconds: 30));
      await tester.runAsync(() => f.tasks.toggleTaskCompletion(first.id));
      await tester.pumpAndSettle();
      // Completion moves the task out of Upcoming without changing the page.
      expect(find.text('Edited').hitTestable(), findsNothing);
      for (var i = 0; i < 2; i++) {
        await tester.drag(
          find.byType(AndroidBoardCarousel),
          const Offset(600, 0),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('First'), findsNothing);
      expect(find.text('Second'), findsNothing);
      expect(find.text('Edited'), findsOneWidget);
      expect(find.byType(TaskCard), findsOneWidget);
      await tester.runAsync(() async {
        f.h.server.offline = true;
        expect(await f.tasks.deleteTask(first.id), isFalse);
      });
      await tester.pumpAndSettle();
      expect(find.text('Edited'), findsOneWidget);
      await tester.runAsync(() async {
        f.h.server.offline = false;
        await f.h.workspace.refresh();
      });
      await tester.pumpAndSettle();
      // Switch accounts while that card is leaving: no cached outgoing task may survive.
      await tester.runAsync(() => f.tasks.deleteTask(first.id));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.runAsync(() => f.h.login('B'));
      await tester.pump();
      expect(find.text('Edited'), findsNothing);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets('outgoing swap controls cannot receive input or focus', (
    tester,
  ) async {
    var actions = 0;
    Widget surface(bool old) => MaterialApp(
      home: Scaffold(
        body: MotionSwap(
          child: old
              ? TextButton(
                  key: const ValueKey('old'),
                  onPressed: () => actions++,
                  child: const Text('Old action'),
                )
              : const Text('New state', key: ValueKey('new')),
        ),
      ),
    );
    await tester.pumpWidget(surface(true));
    await tester.pumpAndSettle();
    await tester.pumpWidget(surface(false));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Old action').hitTestable(), findsNothing);
    expect(actions, 0);
    await tester.pumpAndSettle();
    expect(find.text('Old action'), findsNothing);
    expect(find.text('New state'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion skips entrances and state transitions', (
    tester,
  ) async {
    Widget surface(String text) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: MotionEntrance(
            child: MotionSwap(child: Text(text, key: ValueKey(text))),
          ),
        ),
      ),
    );
    await tester.pumpWidget(surface('First'));
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 1);
    await tester.pumpWidget(surface('Second'));
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });
}

class _Fixture {
  final h = Harness();
  late final boards = BoardsProvider(h.workspace);
  late final tasks = TasksProvider(h.workspace, boards);
  Future<void> initialize() async {
    await h.initialize();
    boards;
    tasks;
    await h.login('A');
  }

  Future<bool> add(String name, DateTime deadline) => tasks.addTask(
    name: name,
    deadline: deadline,
    type: TaskType.unassigned,
    priority: TaskPriority.low,
  );
  Widget app({double textScale = 1}) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: h.auth),
      ChangeNotifierProvider<WorkspaceController>.value(value: h.workspace),
      ChangeNotifierProvider<BoardsProvider>.value(value: boards),
      ChangeNotifierProvider<TasksProvider>.value(value: tasks),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.android),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Consumer<AuthService>(
        builder: (_, auth, _) =>
            AccountDashboard(key: ValueKey(auth.currentUser?.id)),
      ),
    ),
  );
  void dispose() {
    tasks.dispose();
    boards.dispose();
    h.dispose();
  }
}
