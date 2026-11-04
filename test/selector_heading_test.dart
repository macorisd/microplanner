import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microplanner/core/theme/app_colors.dart';
import 'package:microplanner/core/widgets/disclosure_icon.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/dashboard_screen.dart';
import 'package:microplanner/features/tasks/presentation/widgets/action_confirmation_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/edit_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/board_editor_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/sidebar.dart';
import 'customization_interaction_test.dart' as fixture;

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final editing in [false, true]) {
      for (final width in [320.0, 1000.0]) {
        testWidgets(
          '$platform $width ${editing ? 'edit' : 'new'} selectors use the same chevron and color',
          (tester) async {
            final boards = await fixture.mount(tester, platform);
            tester.view.physicalSize = Size(width, 900);
            await tester.pumpAndSettle();
            final context = tester.element(find.byType(DashboardScreen));
            final task = Task(
              id: 'task',
              name: 'Example',
              deadline: DateTime(2030),
              createdAt: DateTime(2026),
              typeIndex: 0,
              priorityIndex: 0,
              subject: '',
              boardId: boards.currentBoardId,
            );
            showDialog<void>(
              context: context,
              builder: (_) => editing
                  ? EditTaskDialog(task: task, onSave: (_) async => false)
                  : AddTaskDialog(
                      onSave:
                          ({
                            required name,
                            required deadline,
                            required type,
                            required priority,
                            subjectId,
                            description,
                          }) async => false,
                    ),
            );
            await tester.pumpAndSettle();
            final dropdowns = tester.widgetList<DropdownButton>(
              find.byWidgetPredicate((w) => w is DropdownButton),
            );
            expect(dropdowns.length, 2);
            for (final dropdown in dropdowns) {
              expect(dropdown.icon, isA<DisclosureIcon>());
            }
            final right = find.byWidgetPredicate(
              (w) => w is DisclosureIcon && w.right,
            );
            expect(right, findsNWidgets(2));
            for (final icon in tester.widgetList<DisclosureIcon>(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(DisclosureIcon),
              ),
            )) {
              expect(icon.color, AppColors.textSecondary);
            }
            if (width < 600) {
              final deadline = tester.getRect(
                find
                    .ancestor(
                      of: find.text('Deadline'),
                      matching: find.byType(InkWell),
                    )
                    .first,
              );
              final time = tester.getRect(
                find
                    .ancestor(
                      of: find.text('Time'),
                      matching: find.byType(InkWell),
                    )
                    .first,
              );
              expect(time.left, deadline.left);
              expect(time.right, deadline.right);
            }
            expect(tester.takeException(), isNull);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }

    testWidgets(
      '$platform sidebar headings align and board title opens its editor',
      (tester) async {
        final boards = await fixture.mount(tester, platform);
        if (platform == TargetPlatform.android) {
          await tester.tap(find.byTooltip('Open navigation menu'));
          await tester.pumpAndSettle();
        }
        final sidebar = find.byType(Sidebar);
        final weeklyIcon = find.descendant(
          of: sidebar,
          matching: find.byIcon(Icons.calendar_view_week_outlined),
        );
        final boardsIcon = find.descendant(
          of: sidebar,
          matching: find.byIcon(Icons.dashboard_outlined),
        );
        expect(
          tester.getTopLeft(weeklyIcon).dx,
          tester.getTopLeft(boardsIcon).dx,
        );
        expect(
          tester.getTopLeft(find.text('Weekly Plan')).dx,
          tester.getTopLeft(find.text('Boards')).dx,
        );
        await tester.tap(find.text('Boards'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('New board').hitTestable(), findsOneWidget);
        await tester.tap(find.text('Boards'));
        await tester.pumpAndSettle();
        if (platform == TargetPlatform.android) {
          await tester.tap(
            find.descendant(
              of: sidebar,
              matching: find.text(boards.currentBoard!.name),
            ),
          );
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('board-heading')));
        await tester.pumpAndSettle();
        expect(find.byType(BoardEditorDialog), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          boards.currentBoard!.name,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(BoardEditorDialog), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'keyboard focus reveals heading actions and long titles fit narrow layouts',
    (tester) async {
      final boards = await fixture.mount(tester, TargetPlatform.windows);
      await tester.runAsync(() => boards.addBoard(name: 'Second'));
      await tester.pumpAndSettle();
      final heading = find.byKey(const ValueKey('board-heading'));
      final title = find.descendant(of: heading, matching: find.text('Second'));
      Focus.of(tester.element(title)).requestFocus();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: heading, matching: find.byTooltip('Delete board')),
        findsOneWidget,
      );
      await tester.runAsync(
        () => boards.updateBoard(
          boards.currentBoard!.copyWith(
            name: List.filled(10, 'Long board title ').join(),
          ),
        ),
      );
      tester.view.physicalSize = const Size(342, 450);
      await tester.pumpAndSettle();
      expect(tester.getRect(heading).right, lessThanOrEqualTo(342));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'heading expands right on hover, shares deletion and protects the last board',
    (tester) async {
      final boards = await fixture.mount(tester, TargetPlatform.windows);
      final heading = find.byKey(const ValueKey('board-heading'));
      final titleDelete = find.descendant(
        of: heading,
        matching: find.byTooltip('Delete board'),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(950, 650));
      await mouse.moveTo(tester.getCenter(heading));
      await tester.pumpAndSettle();
      expect(titleDelete, findsNothing);
      await tester.runAsync(() => boards.addBoard(name: 'Second'));
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(950, 650));
      await tester.pumpAndSettle();
      final box = find
          .ancestor(of: heading, matching: find.byType(AnimatedSize))
          .first;
      final before = tester.getRect(box);
      await mouse.moveTo(Offset(950, before.center.dy));
      await tester.pumpAndSettle();
      expect(
        titleDelete,
        findsNothing,
        reason: 'Only the title card responds to hover',
      );
      await mouse.moveTo(tester.getCenter(heading));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(box).width, greaterThan(before.width));
      await tester.pumpAndSettle();
      final after = tester.getRect(box);
      expect(after.left, before.left);
      expect(after.height, before.height);
      expect(after.width - before.width, closeTo(36, .1));
      await tester.tap(titleDelete);
      await tester.pumpAndSettle();
      expect(find.byType(ActionConfirmationDialog), findsOneWidget);
      expect(find.byType(BoardEditorDialog), findsNothing);
      final titleMessage = tester
          .widget<ActionConfirmationDialog>(
            find.byType(ActionConfirmationDialog),
          )
          .message;
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final sidebarDelete = find
          .descendant(
            of: find.byType(Sidebar),
            matching: find.byTooltip('Delete board'),
          )
          .last;
      await mouse.moveTo(tester.getCenter(find.text('Second').first));
      await tester.pumpAndSettle();
      await tester.tap(sidebarDelete);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ActionConfirmationDialog>(
              find.byType(ActionConfirmationDialog),
            )
            .message,
        titleMessage,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(boards.boards.length, 2);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
