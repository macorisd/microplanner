import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'package:microplanner/features/tasks/presentation/widgets/sidebar.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_column.dart';
import 'package:microplanner/features/tasks/presentation/widgets/edit_task_dialog.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final subject in ['', 'A subject with a name longer than the card']) {
      testWidgets(
        '$platform task actions work at narrow width, subject=$subject',
        (tester) async {
          final fixture = _Fixture();
          await tester.runAsync(fixture.initialize);
          var edits = 0;
          var deletes = 0;
          final task = Task.create(
            id: 'task',
            name: 'A task with a long title',
            deadline: DateTime(2030, 6, 15, 15),
            type: TaskType.presentation,
            priority: TaskPriority.medium,
          )..subject = subject;
          await tester.pumpWidget(
            fixture.app(
              platform,
              SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 260,
                    child: TaskCard(
                      task: task,
                      onToggleComplete: () {},
                      onEdit: () => edits++,
                      onDelete: () => deletes++,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final edit = find.byTooltip('Edit');
          final delete = find.byTooltip('Delete');
          TestGesture? mouse;
          if (platform == TargetPlatform.windows) {
            expect(edit.hitTestable(), findsNothing);
            expect(
              tester
                  .widget<IconButton>(
                    find
                        .ancestor(of: edit, matching: find.byType(IconButton))
                        .first,
                  )
                  .onPressed,
              isNull,
            );
            mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
            await mouse.addPointer(location: const Offset(700, 500));
            await mouse.moveTo(tester.getCenter(find.byType(TaskCard)));
            await tester.pumpAndSettle();
          } else {
            expect(tester.getSize(edit).width, greaterThanOrEqualTo(48));
            expect(tester.getSize(delete).height, greaterThanOrEqualTo(48));
          }
          expect(edit.hitTestable(), findsOneWidget);
          expect(delete.hitTestable(), findsOneWidget);
          await tester.tap(edit);
          await tester.tap(delete);
          expect(edits, 1);
          expect(deletes, 1);
          if (mouse != null) {
            await mouse.moveTo(const Offset(700, 500));
            await tester.pumpAndSettle();
            expect(edit.hitTestable(), findsNothing);
            await mouse.removePointer();
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          fixture.dispose();
        },
      );
    }
  }

  for (final subject in ['', 'Doctorado']) {
    testWidgets('Android content stays compact and aligned, subject=$subject', (
      tester,
    ) async {
      final fixture = _Fixture();
      await tester.runAsync(fixture.initialize);
      var toggles = 0;
      final task = Task.create(
        id: 'spacing',
        name: 'FPU',
        deadline: DateTime(2030, 6, 15),
        type: TaskType.unassigned,
        priority: TaskPriority.high,
      )..subject = subject;
      await tester.pumpWidget(
        fixture.app(
          TargetPlatform.android,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 350,
              child: TaskCard(
                task: task,
                onToggleComplete: () => toggles++,
                onEdit: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mark = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.minWidth == 24 &&
            w.constraints?.minHeight == 24,
      );
      final date = find.byIcon(Icons.calendar_today_rounded);
      expect(
        tester.getTopLeft(mark).dx,
        closeTo(tester.getTopLeft(date).dx, 0.1),
      );
      expect(
        tester.getTopLeft(date).dy - tester.getBottomLeft(find.text('FPU')).dy,
        lessThanOrEqualTo(16),
      );
      final bottom = tester.getBottomLeft(find.byType(TaskCard)).dy - 9;
      if (subject.isNotEmpty) {
        final badge = find
            .ancestor(of: find.text(subject), matching: find.byType(Container))
            .first;
        expect(bottom - tester.getBottomLeft(badge).dy, closeTo(12, 0.1));
      } else {
        expect(bottom - tester.getBottomLeft(date).dy, lessThanOrEqualTo(18));
      }
      final checkbox = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.checked != null,
      );
      expect(tester.getSize(checkbox), const Size(48, 48));
      await tester.tapAt(tester.getTopLeft(checkbox) + const Offset(3, 3));
      expect(toggles, 1);
      for (final label in ['Edit', 'Delete']) {
        expect(tester.getSize(find.byTooltip(label)), const Size(48, 48));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      fixture.dispose();
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('$platform edit dialog focuses the name only on desktop', (
      tester,
    ) async {
      final fixture = _Fixture();
      await tester.runAsync(fixture.initialize);
      final task = Task.create(
        id: 'edit-focus',
        name: 'Existing task',
        deadline: DateTime(2030, 6, 15),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      );
      await tester.pumpWidget(
        fixture.app(
          platform,
          EditTaskDialog(task: task, onSave: (_) async => true),
        ),
      );
      await tester.pumpAndSettle();
      final name = find.byType(EditableText).first;
      expect(
        tester.widget<EditableText>(name).focusNode.hasFocus,
        platform == TargetPlatform.windows,
      );
      if (platform == TargetPlatform.android) {
        expect(tester.testTextInput.isVisible, isFalse);
        await tester.tap(name);
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isTrue);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      fixture.dispose();
    });
  }

  testWidgets(
    'Windows subject badge fits its text instead of filling the footer',
    (tester) async {
      final fixture = _Fixture();
      await tester.runAsync(fixture.initialize);
      final task = Task.create(
        id: 'badge',
        name: 'A task',
        deadline: DateTime(2030, 6, 15),
        type: TaskType.unassigned,
        priority: TaskPriority.low,
      )..subject = 'Doctorado';
      await tester.pumpWidget(
        fixture.app(
          TargetPlatform.windows,
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 400,
              child: TaskCard(
                task: task,
                onToggleComplete: () {},
                onEdit: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = find.text('Doctorado');
      final badge = find
          .ancestor(of: text, matching: find.byType(Container))
          .first;
      expect(
        tester.getSize(badge).width,
        closeTo(tester.getSize(text).width + 30, 0.1),
      );
      expect(tester.getSize(badge).width, lessThan(200));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      fixture.dispose();
    },
  );

  for (final width in [320.0, 393.0]) {
    testWidgets(
      'Android uses the available width at $width, including large text',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final fixture = _Fixture();
        await tester.runAsync(() async {
          await fixture.initialize();
          await fixture.tasks.addTask(
            name: 'Completed task',
            deadline: DateTime(2030, 6, 15),
            type: TaskType.unassigned,
            priority: TaskPriority.low,
          );
          final task = fixture.tasks.tasks.last;
          await fixture.tasks.toggleTaskCompletion(task.id);
        });
        final writes = fixture.h.server.writes;
        await tester.pumpWidget(
          fixture.app(TargetPlatform.android, const DashboardScreen()),
        );
        await tester.pumpAndSettle();
        final column = find.byType(TaskColumn).first;
        expect(tester.getSize(column).width, closeTo(width * 0.92 - 12, 0.1));
        expect(tester.getTopLeft(column).dy, lessThanOrEqualTo(64));
        expect(
          tester.getSize(find.byType(TaskCard).first).height,
          lessThan(190),
        );
        final appBar = find.byType(AppBar);
        expect(
          find.descendant(
            of: appBar,
            matching: find.byTooltip('Refresh cloud data'),
          ),
          findsOneWidget,
        );
        for (final scale in [1.0, 1.5]) {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Edit').first);
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          await tester.tap(find.text('New Task'));
          await tester.pumpAndSettle();
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          tester.view.resetViewInsets();
        }
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        await tester.drag(find.byType(PageView), Offset(-width * 0.75, 0));
        await tester.pumpAndSettle();
        final late = find.byWidgetPredicate(
          (w) => w is TaskColumn && w.title == 'Late',
        );
        expect(tester.getTopLeft(late).dx, closeTo(width * 0.04 + 6, 0.1));
        await tester.drag(find.byType(PageView), Offset(-width * 0.75, 0));
        await tester.pumpAndSettle();
        final upcoming = find.byWidgetPredicate(
          (w) => w is TaskColumn && w.title == 'Upcoming',
        );
        expect(tester.getTopLeft(upcoming).dx, closeTo(width * 0.04 + 6, 0.1));
        expect(fixture.h.server.writes, writes);
        await tester.pumpWidget(const SizedBox());
        fixture.dispose();
      },
    );

    testWidgets(
      'Android drawer fills its width and supports board/subject actions at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final fixture = _Fixture();
        await tester.runAsync(() async {
          await fixture.initialize();
          await fixture.boards.addBoard(name: 'Second board');
          fixture.boards.selectBoard(fixture.boards.boards.first.id);
          await fixture.boards.addSubject(
            name: 'A subject with a very long name',
            color: 0xFF668899,
          );
        });
        await tester.pumpWidget(
          fixture.app(TargetPlatform.android, const DashboardScreen()),
        );
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(Sidebar)).width,
          tester.getSize(find.byType(Drawer)).width,
        );
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is MouseRegion && w.cursor == SystemMouseCursors.resizeColumn,
          ),
          findsNothing,
        );
        expect(
          find.byType(ReorderableDelayedDragStartListener),
          findsNWidgets(2),
        );
        expect(find.byTooltip('Rename board').hitTestable(), findsNWidgets(2));
        expect(
          tester
              .getSize(find.byKey(ValueKey(fixture.boards.boards.first.id)))
              .height,
          lessThanOrEqualTo(116),
        );
        final original = fixture.boards.boards.first.name;
        await tester.tap(find.byTooltip('Rename board').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'Unsaved rename');
        await tester.tap(find.byTooltip('Cancel renaming'));
        await tester.pumpAndSettle();
        expect(fixture.boards.boards.first.name, original);
        await tester.tap(find.text('Subjects').first);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Edit subject').hitTestable(), findsOneWidget);
        expect(find.byTooltip('Delete subject').hitTestable(), findsOneWidget);
        await tester.tap(find.byTooltip('Edit subject'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Second board'));
        await tester.pumpAndSettle();
        expect(
          tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
          isFalse,
        );
        expect(fixture.boards.currentBoard?.name, 'Second board');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        fixture.dispose();
      },
    );
  }

  testWidgets('touch scrolling the board list does not reorder boards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = _Fixture();
    await tester.runAsync(() async {
      await fixture.initialize();
      for (var index = 2; index <= 8; index++) {
        await fixture.boards.addBoard(name: 'Board $index');
      }
    });
    final ids = fixture.boards.boards.map((b) => b.id).toList();
    final writes = fixture.h.server.writes;
    await tester.pumpWidget(
      fixture.app(TargetPlatform.android, const DashboardScreen()),
    );
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    final scroll = find.descendant(
      of: find.byType(Sidebar),
      matching: find.byType(SingleChildScrollView),
    );
    await tester.drag(scroll, const Offset(0, -250));
    await tester.pumpAndSettle();
    expect(fixture.boards.boards.map((b) => b.id), ids);
    expect(fixture.h.server.writes, writes);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    fixture.dispose();
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

  Widget app(TargetPlatform platform, Widget home) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: h.auth),
      ChangeNotifierProvider<WorkspaceController>.value(value: h.workspace),
      ChangeNotifierProvider<BoardsProvider>.value(value: boards),
      ChangeNotifierProvider<TasksProvider>.value(value: tasks),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      home: home is DashboardScreen ? home : Scaffold(body: home),
    ),
  );
  void dispose() {
    tasks.dispose();
    boards.dispose();
    h.dispose();
  }
}
