import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/widgets/animated_app_logo.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/widgets/android_startup_reveal.dart';
import 'package:microplanner/features/boards/data/board_column_storage.dart';
import 'package:microplanner/core/theme/app_theme.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/presentation/account_dashboard.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'package:microplanner/features/tasks/presentation/widgets/edit_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'package:microplanner/features/tasks/presentation/widgets/android_board_carousel.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_column.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'support/fakes.dart';

void main() {
  for (var source = 0; source < 3; source++) {
    for (var destination = 0; destination < 3; destination++) {
      testWidgets(
        'swipe $source to $destination survives pause and a cold restore with matching zoom',
        (tester) async {
          _viewport(tester, const Size(393, 800));
          final vault = MemoryPrivateStorage();
          final storage = PrivateBoardColumnStorage(vault);
          final f = _Fixture(columnStorage: storage);
          await tester.runAsync(f.initialize);
          await tester.pumpWidget(f.app(basicTheme: true));
          await tester.pumpAndSettle();
          const labels = ['Completed', 'Late', 'Upcoming'];
          await tester.tap(find.byTooltip(labels[source]));
          await tester.pumpAndSettle();
          var current = source;
          while (current != destination) {
            final direction = destination > current ? 1 : -1;
            await tester.dragFrom(
              const Offset(200, 300),
              Offset(-direction * 240, 0),
            );
            current += direction;
            if (current != destination) await tester.pumpAndSettle();
          }
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          expect(f.boards.currentColumnIndex, destination);
          await tester.runAsync(settleAsync);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpWidget(const SizedBox());
          f.dispose();
          final reopened = _Fixture(columnStorage: storage);
          await tester.runAsync(reopened.initialize);
          await tester.pumpWidget(reopened.app(basicTheme: true));
          expect(reopened.boards.currentColumnIndex, destination);
          expect(
            tester
                .widget<AndroidStartupReveal>(find.byType(AndroidStartupReveal))
                .column,
            destination,
          );
          expect(
            tester
                .widget<AndroidBoardCarousel>(find.byType(AndroidBoardCarousel))
                .initialColumn,
            destination,
          );
          await tester.pumpAndSettle();
          expect(
            tester.getRect(_column(labels[destination])).right,
            closeTo(381, .1),
          );
          expect(reopened.h.server.writes, 0);
          await tester.pumpWidget(const SizedBox());
          reopened.dispose();
        },
      );
    }
  }

  testWidgets(
    'a drag interrupting manual motion remembers the visible column before release',
    (tester) async {
      _viewport(tester, const Size(393, 800));
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(f.boards.currentColumnIndex, 0);
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      expect(f.boards.currentColumnIndex, 1);
      await gesture.cancel();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'an outgoing carousel cannot overwrite another board or account',
    (tester) async {
      _viewport(tester, const Size(393, 800));
      final f = _Fixture();
      await tester.runAsync(() async {
        await f.initialize();
        await f.boards.addBoard(name: 'Second board');
        f.boards.selectColumn(1);
        f.boards.selectBoard(f.boards.boards.first.id);
      });
      await tester.pumpWidget(f.app());
      await tester.pumpAndSettle();
      final outgoing = tester
          .widget<AndroidBoardCarousel>(find.byType(AndroidBoardCarousel))
          .onColumnChanged!;
      f.boards.selectBoard(f.boards.boards.last.id);
      outgoing(0);
      expect(f.boards.currentColumnIndex, 1);
      await tester.runAsync(() async {
        await f.h.auth.signOut();
        await f.h.login('B');
      });
      outgoing(0);
      expect(f.boards.currentColumnIndex, 2);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  for (final (label, column) in [('Late', 1), ('Completed', 0)]) {
    testWidgets(
      '$label is remembered immediately even if the carousel is disposed mid-transition',
      (tester) async {
        _viewport(tester, const Size(393, 800));
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        await tester.pumpWidget(f.app());
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(label));
        expect(f.boards.currentColumnIndex, column);
        await tester.pumpWidget(const SizedBox());
        expect(f.boards.currentColumnIndex, column);
        f.dispose();
      },
    );
  }

  testWidgets(
    'the visible drag column is remembered before the finger is released',
    (tester) async {
      _viewport(tester, const Size(393, 800));
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app());
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(const Offset(100, 300));
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(210, 0));
      await tester.pump();
      expect(f.boards.currentColumnIndex, 1);
      await gesture.cancel();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'selector exchanges flat layers and the latest destination wins',
    (tester) async {
      _viewport(tester, const Size(393, 800));
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app());
      await tester.pumpAndSettle();
      void selected(String title) => expect(
        find.ancestor(
          of: find.byTooltip(title),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.selected == true,
          ),
        ),
        findsOneWidget,
      );
      selected('Upcoming');
      final upcoming = tester.getRect(_column('Upcoming'));
      final late = tester.getRect(_column('Late'));
      final completed = tester.getRect(_column('Completed'));
      expect(completed.left, lessThan(late.left));
      expect(late.left, lessThan(upcoming.left));
      expect(completed.width, lessThan(late.width));
      expect(late.width, lessThan(upcoming.width));
      for (final title in ['Completed', 'Late', 'Upcoming']) {
        expect(tester.getSize(find.byTooltip(title)), const Size(48, 48));
      }
      expect(
        tester.getRect(find.byTooltip('Upcoming')).right,
        lessThan(tester.getRect(find.byTooltip('New Task')).left),
      );
      await tester.tap(find.byTooltip('Completed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      for (var i = 0; i < 3; i++) {
        final matrix = tester
            .widget<Transform>(
              find.byKey(ValueKey('carousel-layer-$i'), skipOffstage: false),
            )
            .transform;
        // Columns remain rectangular and parallel, including mid-transition.
        for (final (row, column) in [
          (0, 1),
          (1, 0),
          (0, 2),
          (1, 2),
          (3, 0),
          (3, 1),
          (3, 2),
        ]) {
          expect(matrix.entry(row, column), 0);
        }
        expect(matrix.entry(0, 0), matrix.entry(1, 1));
      }
      await tester.tap(find.byTooltip('Upcoming'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byTooltip('Late'));
      await tester.pumpAndSettle();
      selected('Late');
      expect(tester.getRect(_column('Late')).right, closeTo(381, .1));
      expect(_column('Upcoming'), findsNothing);
      expect(_column('Completed'), findsOneWidget);
      await tester.tap(find.byTooltip('Completed'));
      await tester.pumpAndSettle();
      selected('Completed');
      expect(tester.getRect(_column('Completed')).right, closeTo(381, .1));
      expect(_column('Late'), findsNothing);
      expect(_column('Upcoming'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'short drags return, longer drags snap and cancellation settles',
    (tester) async {
      _viewport(tester, const Size(393, 800));
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app());
      await tester.pumpAndSettle();
      final short = await tester.startGesture(const Offset(180, 300));
      await short.moveBy(const Offset(24, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await short.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(_column('Upcoming')).right, closeTo(381, .1));
      await tester.dragFrom(const Offset(100, 300), const Offset(160, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(_column('Late')).right, closeTo(381, .1));
      final cancelled = await tester.startGesture(const Offset(180, 300));
      await cancelled.moveBy(const Offset(-80, 0));
      await tester.pump();
      await cancelled.cancel();
      await tester.pumpAndSettle();
      expect(tester.getRect(_column('Late')).right, closeTo(381, .1));
      await _next(tester, 393);
      expect(tester.getRect(_column('Completed')).right, closeTo(381, .1));
      await _next(tester, 393);
      expect(tester.getRect(_column('Completed')).right, closeTo(381, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  for (final (size, scale) in [
    (const Size(320, 800), 1.0),
    (const Size(393, 800), 1.5),
    (const Size(900, 393), 1.3),
  ]) {
    testWidgets('Android carousel keeps page order and left peek at $size', (
      tester,
    ) async {
      _viewport(tester, size);
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await tester.pumpWidget(f.app(scale: scale));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      for (final title in ['Upcoming', 'Late', 'Completed']) {
        final active = _column(title);
        final rect = tester.getRect(active);
        expect(rect.right, closeTo(size.width - 12, 0.1));
        expect(rect.left, inExclusiveRange(12, 60));
        expect(
          tester.getRect(find.byTooltip('Completed')).left,
          closeTo(rect.left, .1),
        );
        if (title != 'Completed') {
          final left = _column(title == 'Upcoming' ? 'Late' : 'Completed');
          expect(tester.getRect(left).left, lessThan(rect.left));
          expect(tester.getRect(left).right, greaterThan(0));
          await _next(tester, size.width);
        } else {
          expect(_column('Late'), findsNothing);
          expect(_column('Upcoming'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
      // A fourth state is not introduced at the end of the finite carousel.
      await _next(tester, size.width);
      expect(
        tester.getRect(_column('Completed')).right,
        closeTo(size.width - 12, .1),
      );
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    });
  }

  testWidgets(
    'refresh preserves the page; each board remembers its last column',
    (tester) async {
      _viewport(tester, const Size(393, 800));
      final f = _Fixture();
      await tester.runAsync(() async {
        await f.initialize();
        await f.boards.addBoard(name: 'Second board');
        f.boards.selectBoard(f.boards.boards.first.id);
      });
      await tester.pumpWidget(f.app());
      await tester.pumpAndSettle();
      await _next(tester, 393);
      final late = tester.getRect(_column('Late'));
      await tester.runAsync(f.h.workspace.refresh);
      await tester.pumpAndSettle();
      expect(tester.getRect(_column('Late')), late);
      f.boards.selectBoard(f.boards.boards.last.id);
      await tester.pumpAndSettle();
      expect(tester.getRect(_column('Upcoming')).right, closeTo(381, .1));
      await _next(tester, 393);
      f.boards.selectBoard(f.boards.boards.first.id);
      await tester.pumpAndSettle();
      expect(tester.getRect(_column('Late')).right, closeTo(381, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets('edge drag opens the drawer; tap and vertical drag do not', (
    tester,
  ) async {
    _viewport(tester, const Size(393, 800));
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    ScaffoldState scaffold() => tester.state<ScaffoldState>(
      find.descendant(
        of: find.byType(DashboardScreen),
        matching: find.byType(Scaffold),
      ),
    );
    await tester.tapAt(const Offset(50, 250));
    await tester.pumpAndSettle();
    expect(scaffold().isDrawerOpen, isFalse);
    await tester.dragFrom(const Offset(50, 400), const Offset(0, -180));
    await tester.pumpAndSettle();
    expect(scaffold().isDrawerOpen, isFalse);
    await _next(tester, 393);
    expect(scaffold().isDrawerOpen, isFalse);
    expect(tester.getRect(_column('Late')).right, closeTo(381, .1));
    await tester.dragFrom(const Offset(50, 400), const Offset(270, 0));
    await tester.pumpAndSettle();
    expect(scaffold().isDrawerOpen, isTrue);
    scaffold().closeDrawer();
    await tester.pumpAndSettle();
    expect(tester.getRect(_column('Late')).right, closeTo(381, .1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets(
    'column scroll survives page changes, rotation and reduced motion',
    (tester) async {
      _viewport(tester, const Size(393, 800));
      final f = _Fixture();
      await tester.runAsync(() async {
        await f.initialize();
        for (var i = 0; i < 25; i++) {
          await f.add('Scrolling task $i');
        }
      });
      await tester.pumpWidget(f.app(reducedMotion: true));
      await tester.pumpAndSettle();
      ScrollableState list() => tester.state<ScrollableState>(
        find.descendant(
          of: _column('Upcoming'),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.dragFrom(const Offset(210, 500), const Offset(0, -320));
      await tester.pumpAndSettle();
      final pixels = list().position.pixels;
      expect(pixels, greaterThan(100));
      expect(find.byType(EditTaskDialog), findsNothing);
      await _next(tester, 393);
      tester.view.physicalSize = const Size(900, 393);
      await tester.pumpAndSettle();
      expect(tester.getRect(_column('Late')).right, closeTo(888, .1));
      await tester.dragFrom(const Offset(500, 200), const Offset(-680, 0));
      await tester.pumpAndSettle();
      expect(tester.getRect(_column('Upcoming')).right, closeTo(888, .1));
      expect(list().position.pixels, closeTo(pixels, .1));
      await tester.runAsync(f.h.workspace.refresh);
      await tester.pumpAndSettle();
      expect(list().position.pixels, closeTo(pixels, .1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets('card taps edit; checkbox, delete and swipes stay independent', (
    tester,
  ) async {
    _viewport(tester, const Size(393, 800));
    final f = _Fixture();
    await tester.runAsync(() async {
      await f.initialize();
      await f.add('Tap to edit');
    });
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit'), findsNothing);
    await tester.tap(find.text('Tap to edit'));
    await tester.pumpAndSettle();
    expect(find.byType(EditTaskDialog), findsOneWidget);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester
          .widget<EditableText>(find.byType(EditableText).first)
          .focusNode
          .hasFocus,
      isFalse,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete').hitTestable());
    await tester.pumpAndSettle();
    expect(find.text('Delete Task'), findsOneWidget);
    expect(find.byType(EditTaskDialog), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Tap to edit'), const Offset(220, 0));
    await tester.pumpAndSettle();
    expect(find.byType(EditTaskDialog), findsNothing);
    // Return to Upcoming before checking a completion tap.
    await tester.drag(find.byType(AndroidBoardCarousel), const Offset(-300, 0));
    await tester.pumpAndSettle();
    final checkbox = find
        .byWidgetPredicate(
          (w) => w is Semantics && w.properties.checked == false,
        )
        .hitTestable();
    await tester.tap(checkbox);
    await tester.runAsync(settleAsync);
    await tester.pumpAndSettle();
    expect(f.tasks.completedTasks.single.name, 'Tap to edit');
    expect(find.byType(EditTaskDialog), findsNothing);
    expect(f.h.server.writes, 2); // One creation and one completion.
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('offline card controls do not edit or mutate the cached task', (
    tester,
  ) async {
    _viewport(tester, const Size(393, 800));
    final f = _Fixture();
    await tester.runAsync(() async {
      await f.initialize();
      for (var i = 0; i < 2; i++) {
        await f.tasks.addTask(
          name: 'Earlier task $i',
          deadline: DateTime(2030, 6, 13 + i),
          type: TaskType.unassigned,
          priority: TaskPriority.low,
        );
      }
      await f.add('Offline task');
      f.h.server.offline = true;
      await f.h.workspace.refresh();
    });
    final writes = f.h.server.writes;
    await tester.pumpWidget(f.app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline task'));
    final card = find.ancestor(
      of: find.text('Offline task'),
      matching: find.byType(TaskCard),
    );
    await tester.tap(
      find.descendant(of: card, matching: find.byTooltip('Delete')),
    );
    await tester.tap(
      find.descendant(
        of: card,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.checked == false,
        ),
      ),
    );
    await tester.runAsync(settleAsync);
    await tester.pumpAndSettle();
    expect(find.byType(EditTaskDialog), findsNothing);
    expect(find.text('Delete Task'), findsNothing);
    expect(
      f.tasks.upcomingTasks
          .where((t) => t.name == 'Offline task')
          .single
          .isCompleted,
      isFalse,
    );
    expect(f.h.server.writes, writes);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      '$platform refresh uses the floating notice without a toolbar spinner',
      (tester) async {
        _viewport(
          tester,
          Size(platform == TargetPlatform.android ? 393 : 1280, 800),
        );
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        await tester.pumpWidget(f.app(platform: platform));
        await tester.pumpAndSettle();
        final refresh = find.byTooltip('Refresh cloud data');
        final refreshButton = find
            .ancestor(of: refresh, matching: find.byType(IconButton))
            .first;
        final position = tester.getRect(refresh);
        final pending = Completer<http.Response>();
        f.h.server.nextRead = pending;
        final future = f.h.workspace.refresh();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('Loading your data'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(AnimatedAppLogo), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DashboardScreen),
            matching: find.byType(CircularProgressIndicator),
          ),
          findsNothing,
        );
        expect(tester.getRect(refresh), position);
        expect(tester.widget<IconButton>(refreshButton).onPressed, isNull);
        pending.complete(jsonResponse(f.h.server.states['A']!.toJson()));
        await tester.runAsync(() => future);
        await tester.pumpAndSettle();
        expect(find.text('Loading your data'), findsNothing);
        expect(tester.widget<IconButton>(refreshButton).onPressed, isNotNull);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }
}

Finder _column(String title) =>
    find.byWidgetPredicate((w) => w is TaskColumn && w.title == title);

Future<void> _next(WidgetTester tester, double width) async {
  await tester.dragFrom(const Offset(100, 250), Offset(width * .75, 0));
  await tester.pumpAndSettle();
}

void _viewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _Fixture {
  _Fixture({this.columnStorage});
  final BoardColumnStorage? columnStorage;
  final h = Harness();
  late final boards = BoardsProvider(h.workspace, columnStorage: columnStorage);
  late final tasks = TasksProvider(h.workspace, boards);
  Future<void> initialize() async {
    await h.initialize();
    boards;
    tasks;
    await h.login('A');
  }

  Future<bool> add(String name) => tasks.addTask(
    name: name,
    deadline: DateTime(2030, 6, 15),
    type: TaskType.unassigned,
    priority: TaskPriority.low,
  );

  Widget app({
    TargetPlatform platform = TargetPlatform.android,
    double scale = 1,
    bool reducedMotion = false,
    bool basicTheme = false,
  }) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthService>.value(value: h.auth),
      ChangeNotifierProvider<WorkspaceController>.value(value: h.workspace),
      ChangeNotifierProvider<BoardsProvider>.value(value: boards),
      ChangeNotifierProvider<TasksProvider>.value(value: tasks),
    ],
    child: MaterialApp(
      theme: basicTheme
          ? ThemeData(platform: platform)
          : AppTheme.lightTheme.copyWith(platform: platform),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB')],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: const AccountDashboard(),
    ),
  );

  void dispose() {
    tasks.dispose();
    boards.dispose();
    h.dispose();
  }
}
