import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/data/workspace_snapshot.dart';
import 'package:microplanner/core/theme/app_colors.dart';
import 'package:microplanner/core/theme/app_theme.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/data/models/board.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'package:microplanner/features/tasks/presentation/widgets/sidebar.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_column.dart';
import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final (title, color, background, icon) in [
      (
        'Complete',
        AppColors.completeHeader,
        AppColors.completeHeaderLight,
        Icons.check_circle_rounded,
      ),
      (
        'Late',
        AppColors.lateHeader,
        AppColors.lateHeaderLight,
        Icons.warning_rounded,
      ),
      (
        'Upcoming',
        AppColors.upcomingHeader,
        AppColors.upcomingHeaderLight,
        Icons.schedule_rounded,
      ),
    ]) {
      testWidgets(
        '$platform $title header retains the right empty-state color',
        (tester) async {
          final f = _Fixture();
          await tester.runAsync(f.initialize);
          Widget surface(List<Task> tasks) => f.app(
            platform,
            Center(
              child: SizedBox(
                width: 300,
                height: 500,
                child: TaskColumn(
                  title: title,
                  tasks: tasks,
                  headerColor: color,
                  headerBackgroundColor: background,
                  icon: icon,
                  onToggleComplete: (_) {},
                ),
              ),
            ),
          );
          for (final populated in [false, true, false]) {
            await tester.pumpWidget(
              surface(populated ? [_task('sample')] : []),
            );
            await tester.pumpAndSettle();
            final header = tester.widget<AnimatedContainer>(
              find
                  .descendant(
                    of: find.byType(TaskColumn),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            );
            final muted = !populated && platform == TargetPlatform.windows;
            expect(
              (header.decoration as BoxDecoration).color,
              muted ? AppColors.surfaceVariant : background,
            );
            final headerIcon = tester.widget<Icon>(find.byIcon(icon).first);
            expect(headerIcon.color, muted ? AppColors.textTertiary : color);
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          f.dispose();
        },
      );
    }
  }

  testWidgets(
    'rapid sidebar hover clears the previous rendered background immediately',
    (tester) async {
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(
        f.app(
          TargetPlatform.windows,
          const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 260, child: Sidebar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      Color? background(String name) {
        Color? value;
        tester.element(find.text(name)).visitAncestorElements((element) {
          final widget = element.widget;
          final decoration = widget is Ink
              ? widget.decoration
              : widget is DecoratedBox
              ? widget.decoration
              : null;
          if (decoration is BoxDecoration && decoration.borderRadius != null) {
            value = decoration.color;
            return false;
          }
          return true;
        });
        return value;
      }

      await mouse.moveTo(tester.getCenter(find.text('Second')));
      await tester.pumpAndSettle();
      for (final name in ['Third', 'Second', 'Third', 'Second']) {
        await mouse.moveTo(tester.getCenter(find.text(name)));
        await tester.pump(const Duration(milliseconds: 1));
        expect(background(name), AppColors.sidebarItemHover);
        expect(
          background(name == 'Second' ? 'Third' : 'Second'),
          Colors.transparent,
        );
        expect(background('First'), AppColors.sidebarItemActive);
      }
      await mouse.moveTo(const Offset(600, 20));
      await tester.pump(const Duration(milliseconds: 1));
      expect(background('Second'), Colors.transparent);
      expect(background('Third'), Colors.transparent);
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  for (final size in [
    const Size(768, 450),
    const Size(455, 232),
    const Size(342, 162),
  ]) {
    testWidgets('Windows dashboard and task form remain reachable at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(
        f.app(TargetPlatform.windows, const DashboardScreen(), scale: 1.3),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Open navigation menu'), findsOneWidget);
      expect(
        tester
            .widgetList<Scrollbar>(find.byType(Scrollbar))
            .any((bar) => bar.thumbVisibility == true),
        isTrue,
      );
      final add = size.height < 360
          ? find.byTooltip('New Task')
          : find.text('New Task');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in ['Deadline', 'Time']) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Picker $label at $size',
        );
        await tester.ensureVisible(find.text('Cancel').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cancel').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.ensureVisible(find.text('Create Task'));
      await tester.pumpAndSettle();
      expect(find.text('Create Task').hitTestable(), findsOneWidget);
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    });
  }

  test('Material roles retain the existing palette', () {
    const colors = AppTheme.lightColorScheme;
    expect(colors.primary, const Color(0xff6fa89f));
    expect(colors.onPrimary, Colors.white);
    expect(colors.surface, Colors.white);
    expect(colors.onSurface, const Color(0xff3d4156));
    expect(colors.primaryContainer, const Color(0xffe4efed));
    expect(colors.surfaceContainerLow, AppColors.background);
    expect(colors.surfaceContainer, AppColors.surfaceVariant);
    expect(colors.secondaryContainer, AppColors.primaryLight);
    expect(AppColors.sidebarItemActive, const Color(0xffe1ebe9));
    expect(AppColors.sidebarItemHover, const Color(0xffeaeaed));
  });

  testWidgets('rapid board switches only show the latest tasks', (
    tester,
  ) async {
    final f = _Fixture();
    await tester.runAsync(() async {
      await f.initialize();
      await f.tasks.addTask(
        name: 'First fixture',
        deadline: DateTime(2030),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      f.boards.selectBoard('second');
      await f.tasks.addTask(
        name: 'Second fixture',
        deadline: DateTime(2030),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      f.boards.selectBoard('default-board');
    });
    await tester.pumpWidget(
      f.app(TargetPlatform.windows, const DashboardScreen()),
    );
    await tester.pump(const Duration(milliseconds: 8));
    f.boards.selectBoard('second');
    await tester.pump(const Duration(milliseconds: 8));
    f.boards.selectBoard('default-board');
    await tester.pumpAndSettle();
    expect(find.text('First fixture'), findsOneWidget);
    expect(find.text('Second fixture'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  test(
    'status and subject navigation preserve derived task views without notifications',
    () async {
      final f = _Fixture();
      await f.initialize();
      await f.tasks.addTask(
        name: 'Seed',
        deadline: DateTime(2030),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      final before = f.tasks.tasks;
      final upcoming = f.tasks.upcomingTasks;
      final completed = f.tasks.completedTasks;
      final late = f.tasks.lateTasks;
      final boardViews = f.boards.boards;
      var notices = 0;
      f.tasks.addListener(() => notices++);
      final pending = Completer<http.Response>();
      f.h.server.nextRead = pending;
      final refresh = f.h.workspace.refresh();
      await settleAsync();
      expect(f.h.workspace.isLoading, isTrue);
      expect(notices, 0);
      pending.complete(jsonResponse(f.h.server.states['A']!.toJson()));
      await refresh;
      f.boards.showSubjectsForBoard('default-board');
      f.boards.hideSubjectsView();
      expect(identical(f.tasks.tasks, before), isTrue);
      expect(identical(f.tasks.upcomingTasks, upcoming), isTrue);
      expect(identical(f.boards.boards, boardViews), isTrue);
      expect(notices, 0);
      await f.tasks.updateTask(before.single.copyWith(name: 'Changed'));
      expect(notices, 1);
      expect(f.tasks.tasks.single.name, 'Changed');
      expect(identical(f.tasks.completedTasks, completed), isTrue);
      expect(identical(f.tasks.lateTasks, late), isTrue);
      f.boards.selectBoard('second');
      expect(f.tasks.tasks, isEmpty);
      await f.h.login('B');
      expect(f.tasks.tasks, isEmpty);
      expect(f.boards.boards.single.name, 'B private');
      f.dispose();
    },
  );

  testWidgets(
    'cached task states cross deadlines and clear on account changes',
    (tester) async {
      final h = Harness();
      var now = DateTime(2030, 6, 15, 12);
      await tester.runAsync(() async {
        await h.initialize();
        h.server.states['A'] = WorkspaceSnapshot(
          boards: snapshot('Clock').boards,
          tasks: [
            _task(
              'clock',
            ).copyWith(deadline: now.add(const Duration(seconds: 2))),
          ],
        );
        await h.login('A');
      });
      final boards = BoardsProvider(h.workspace);
      final tasks = TasksProvider(h.workspace, boards, now: () => now);
      expect(tasks.upcomingTasks.single.id, 'clock');
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      expect(tasks.upcomingTasks, isEmpty);
      expect(tasks.lateTasks.single.id, 'clock');
      now = now.subtract(const Duration(hours: 1));
      await tester.runAsync(h.workspace.refresh);
      expect(tasks.upcomingTasks.single.id, 'clock');
      await tester.runAsync(() => h.login('B'));
      expect(tasks.tasks, isEmpty);
      tasks.dispose();
      boards.dispose();
      h.dispose();
    },
  );
}

Task _task(String id) => Task.create(
  id: id,
  name: 'Task $id',
  deadline: DateTime(2030, 6, 15),
  type: TaskType.unassigned,
  priority: TaskPriority.low,
  boardId: 'default-board',
);

class _Fixture {
  final h = Harness();
  late final boards = BoardsProvider(h.workspace);
  late final tasks = TasksProvider(h.workspace, boards);
  Future<void> initialize() async {
    await h.initialize();
    boards;
    tasks;
    h.server.states['A'] = WorkspaceSnapshot(
      boards: [
        Board(id: 'default-board', name: 'First', createdAt: DateTime(2026)),
        Board(
          id: 'second',
          name: 'Second',
          createdAt: DateTime(2026),
          sortOrder: 1,
        ),
        Board(
          id: 'third',
          name: 'Third',
          createdAt: DateTime(2026),
          sortOrder: 2,
        ),
      ],
    );
    await h.login('A');
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
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', 'GB'), Locale('en', 'US')],
          locale: const Locale('en', 'GB'),
          theme: ThemeData(
            platform: platform,
            colorScheme: AppTheme.lightColorScheme,
          ),
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
