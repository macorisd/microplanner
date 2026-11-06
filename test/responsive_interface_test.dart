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
import 'package:microplanner/features/boards/data/board_catalog.dart';
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
        'Completed',
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
    'sidebar hover reserves action width only while shown without resizing rows',
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
      BoxDecoration? rowDecoration(String name) {
        BoxDecoration? value;
        tester.element(find.text(name)).visitAncestorElements((element) {
          final widget = element.widget;
          final decoration = widget is Ink
              ? widget.decoration
              : widget is DecoratedBox
              ? widget.decoration
              : null;
          if (decoration is BoxDecoration && decoration.borderRadius != null) {
            value = decoration;
            return false;
          }
          return true;
        });
        return value;
      }

      final rowRects = {
        for (final id in ['default-board', 'second', 'third'])
          id: tester.getRect(find.byKey(ValueKey(id))),
      };
      final labelRects = {
        for (final name in ['First', 'Second', 'Third'])
          name: tester.getRect(find.text(name)),
      };
      expect(find.byTooltip('Edit board').hitTestable(), findsNothing);
      await mouse.moveTo(tester.getCenter(find.text('Second')));
      await tester.pumpAndSettle();
      for (final name in ['Third', 'Second', 'Third', 'Second']) {
        await mouse.moveTo(tester.getCenter(find.text(name)));
        await tester.pump(const Duration(milliseconds: 1));
        expect(
          (rowDecoration(name)!.border! as Border).top.color,
          const Color(0xff7986cb).withValues(alpha: .25),
        );
        expect(
          (rowDecoration(name == 'Second' ? 'Third' : 'Second')!.border!
                  as Border)
              .top
              .color,
          Colors.transparent,
        );
        expect(
          (rowDecoration('First')!.border! as Border).top.color,
          const Color(0xff7986cb).withValues(alpha: .7),
        );
        for (final title in ['First', 'Second', 'Third']) {
          expect(
            rowDecoration(title)!.color,
            boardRowBackground(const Color(0xff7986cb)),
          );
          final label = tester.getRect(find.text(title));
          final original = labelRects[title]!;
          expect(label.left, original.left);
          expect(label.top, original.top);
          expect(label.height, original.height);
          expect(
            label.width,
            title == name ? original.width - 48 : original.width,
          );
          expect(
            tester.widget<Text>(find.text(title)).style!.color,
            const Color(0xff7986cb),
          );
          expect(
            tester.widget<Text>(find.text(title)).style!.fontWeight,
            FontWeight.w700,
          );
        }
      }
      for (final entry in rowRects.entries) {
        expect(tester.getRect(find.byKey(ValueKey(entry.key))), entry.value);
      }
      await mouse.moveTo(const Offset(600, 20));
      await tester.pump(const Duration(milliseconds: 1));
      for (final title in labelRects.keys) {
        expect(tester.getRect(find.text(title)), labelRects[title]);
      }
      expect(
        (rowDecoration('Second')!.border! as Border).top.color,
        Colors.transparent,
      );
      expect(
        (rowDecoration('Third')!.border! as Border).top.color,
        Colors.transparent,
      );
      tester.view.physicalSize = const Size(800, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SingleChildScrollView),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(scroll.maxScrollExtent, greaterThan(0));
      final before = tester.getRect(find.byKey(const ValueKey('second')));
      await mouse.moveTo(tester.getCenter(find.text('First')));
      await tester.pump();
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byKey(const ValueKey('second')));
      expect(after.size, before.size);
      expect(after.top, closeTo(before.top - scroll.pixels, .01));
      for (final entry in rowRects.entries) {
        expect(
          tester.getSize(find.byKey(ValueKey(entry.key))),
          entry.value.size,
        );
      }
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      '$platform board heading follows saved identity on a neutral canvas',
      (tester) async {
        tester.view.physicalSize = Size(
          platform == TargetPlatform.android ? 393 : 1200,
          800,
        );
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        await tester.pumpWidget(f.app(platform, const DashboardScreen()));
        await tester.pumpAndSettle();
        final heading = find.byKey(const ValueKey('board-heading'));
        expect(heading, findsOneWidget);
        if (platform == TargetPlatform.android) {
          final burger = tester.getRect(find.byIcon(Icons.menu));
          final surface = tester.getRect(
            find
                .ancestor(of: heading, matching: find.byType(DecoratedBox))
                .first,
          );
          expect(surface.left - burger.right, closeTo(burger.left, .1));
        }

        expect(
          find.descendant(of: heading, matching: find.text('First')),
          findsOneWidget,
        );
        // A customization can change the color/icon without changing its name.
        await tester.runAsync(
          () => f.boards.updateBoard(
            f.boards.currentBoard!.copyWith(icon: 'science', color: 0xff64b5f6),
          ),
        );
        await tester.pumpAndSettle();
        final title = tester.widget<Text>(
          find.descendant(of: heading, matching: find.byType(Text)),
        );
        expect(title.style!.color, const Color(0xff64b5f6));
        final icon = tester.widget<Icon>(
          find.descendant(of: heading, matching: find.byType(Icon)),
        );
        expect(icon.icon, Icons.science_rounded);
        expect(icon.color, title.style!.color);
        final titleSurface = tester.widget<DecoratedBox>(
          find.ancestor(of: heading, matching: find.byType(DecoratedBox)).first,
        );
        expect(
          (titleSurface.decoration as BoxDecoration).color,
          boardRowBackground(const Color(0xff64b5f6)),
        );

        final coloredAncestors = tester.widgetList<ColoredBox>(
          find.ancestor(
            of: find.byType(TaskColumn).first,
            matching: find.byType(ColoredBox),
          ),
        );
        expect(
          coloredAncestors.map((box) => box.color),
          isNot(
            contains(
              Color.alphaBlend(
                const Color(0xff64b5f6).withValues(alpha: .07),
                AppColors.background,
              ),
            ),
          ),
        );
        f.boards.selectBoard('second');
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: heading, matching: find.text('Second')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }

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
      await tester.ensureVisible(find.text('Create task'));
      await tester.pumpAndSettle();
      expect(find.text('Create task').hitTestable(), findsOneWidget);
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
