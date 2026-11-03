import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/features/auth/data/auth_service.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'package:microplanner/features/tasks/presentation/widgets/board_editor_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/editor_panel.dart';
import 'package:microplanner/features/tasks/presentation/widgets/sidebar.dart';

import 'support/fakes.dart';

Future<BoardsProvider> mount(
  WidgetTester tester,
  TargetPlatform platform,
) async {
  final harness = Harness();
  await tester.runAsync(() async {
    await harness.initialize();
    await harness.login('A');
  });
  final boards = BoardsProvider(harness.workspace);
  final tasks = TasksProvider(harness.workspace, boards);
  tester.view.physicalSize = platform == TargetPlatform.android
      ? const Size(360, 800)
      : const Size(1000, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tasks.dispose();
    boards.dispose();
    harness.dispose();
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
        theme: ThemeData(platform: platform),
        home: const DashboardScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return boards;
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('$platform can move a board to the last position by dragging', (
      tester,
    ) async {
      final boards = await mount(tester, platform);
      await tester.runAsync(() async {
        for (var number = 2; number <= 4; number++) {
          await boards.addBoard(name: 'Board $number');
        }
      });
      await tester.pumpAndSettle();
      if (platform == TargetPlatform.android) {
        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
      }
      final original = boards.boards.map((board) => board.id).toList();
      final source = tester.getCenter(find.text('Board 3'));
      final destination =
          tester
              .getBottomLeft(
                find.descendant(
                  of: find.byType(Sidebar),
                  matching: find.text('Board 4'),
                ),
              )
              .dy +
          100;
      final gesture = await tester.startGesture(source);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await gesture.moveBy(const Offset(0, 5));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(Offset(source.dx, destination));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.runAsync(settleAsync);
      await tester.pumpAndSettle();
      expect(boards.boards.map((board) => board.id), [
        original[0],
        original[1],
        original[3],
        original[2],
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      '$platform system Back unwinds every settings level and returns to the board',
      (tester) async {
        final boards = await mount(tester, platform);
        boards.navigate(DashboardPage.profile);
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(CircleAvatar).last).aspectRatio, 1);
        await tester.tap(find.text('Settings').last);
        await tester.pumpAndSettle();
        for (final label in [
          'Customization',
          'Boards',
          'Default lists of task types',
        ]) {
          final entry = find.descendant(
            of: find.byType(EditorPanel),
            matching: find.text(label),
          );
          await tester.tap(entry);
          await tester.pumpAndSettle();
        }
        expect(find.text('Academic tasks'), findsOneWidget);
        for (final heading in ['Boards', 'Customization', 'Settings']) {
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: find.byType(EditorHeading),
              matching: find.text(heading),
            ),
            findsOneWidget,
          );
          expect(boards.page, DashboardPage.settings);
        }
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(boards.page, DashboardPage.profile);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(boards.page, DashboardPage.board);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$platform board editor limits input, detects unchanged values and releases picker focus',
      (tester) async {
        final boards = await mount(tester, platform);
        final context = tester.element(find.byType(DashboardScreen));
        showDialog<void>(
          context: context,
          builder: (_) => BoardEditorDialog(board: boards.boards.first),
        );
        await tester.pumpAndSettle();
        final save = find.widgetWithText(ElevatedButton, 'Save changes');
        expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
        final field = find.byType(TextField);
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isFalse,
        );
        await tester.enterText(field, List.filled(80, 'x').join());
        await tester.pump();
        expect(tester.widget<TextField>(field).controller!.text.length, 50);
        expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);
        await tester.enterText(field, boards.boards.first.name);
        await tester.pump();
        expect(tester.widget<ElevatedButton>(save).onPressed, isNull);
        await tester.tap(find.text('Choose icon'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('school'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isFalse,
        );
        expect(tester.testTextInput.isVisible, isFalse);
        expect(tester.widget<ElevatedButton>(save).onPressed, isNotNull);
        await tester.ensureVisible(find.text('Cancel'));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(boards.boards.first.icon, 'board');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$platform leaving settings discards only its navigation history',
      (tester) async {
        final boards = await mount(tester, platform);
        boards.navigate(DashboardPage.settings);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Customization'));
        await tester.pumpAndSettle();
        boards.selectBoard(boards.boards.first.id);
        await tester.pumpAndSettle();
        boards.navigate(DashboardPage.profile);
        await tester.pumpAndSettle();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(boards.page, DashboardPage.board);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
