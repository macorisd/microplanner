import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/data/workspace_limits.dart';
import 'package:microplanner/core/data/workspace_delta.dart';
import 'package:microplanner/core/theme/app_theme.dart';
import 'package:microplanner/features/boards/data/models/subject.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/widgets/account_pages.dart';
import 'package:microplanner/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/edit_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/board_editor_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/category_editor.dart';
import 'package:microplanner/features/tasks/presentation/widgets/new_board_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/subject_dialog.dart';
import 'support/fakes.dart';

void main() {
  test(
    'duplicate validation covers mutation/rebase and preserves legacy data',
    () {
      final base = snapshot('First').upgraded();
      final one = const Subject(
        id: 'one',
        boardId: 'default-board',
        name: 'Math',
        color: 1,
      );
      final old = base.copyWith(subjects: [one]);
      final collision = old.copyWith(
        subjects: [
          one,
          const Subject(
            id: 'two',
            boardId: 'default-board',
            name: ' MATH ',
            color: 2,
          ),
        ],
      );
      expect(
        WorkspaceLimits.validate(collision, previous: old),
        contains('already exists'),
      );
      expect(WorkspaceLimits.validate(collision, previous: collision), isNull);
      expect(WorkspaceDelta.between(base, collision).apply(old), isNull);
      final boardCollision = base.copyWith(
        boards: [
          ...base.boards,
          base.boards.single.copyWith(id: 'new', name: ' FIRST '),
        ],
      );
      expect(
        WorkspaceLimits.validate(boardCollision, previous: base),
        contains('board'),
      );
    },
  );

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final kind in [
      'task',
      'board',
      'subject',
      'task type',
      'default list',
      'legacy subject',
    ]) {
      for (final editing in [false, true]) {
        testWidgets(
          '$platform $kind ${editing ? "edit" : "create"} focus and required-name feedback',
          (tester) async {
            final f = await _mount(tester, platform);
            final context = tester.element(find.text('Open'));
            if (kind == 'subject' || kind == 'task type') {
              editCategory(
                context,
                label: kind,
                useIcon: kind == 'task type',
                initial: editing
                    ? const CategoryDraft(id: 'old', name: 'Original')
                    : null,
              );
            } else {
              final Widget dialog;
              if (kind == 'default list') {
                dialog = SettingsPage(onBack: () {});
              } else if (kind == 'board') {
                dialog = editing
                    ? BoardEditorDialog(
                        board: f.h.workspace.snapshot.boards.single,
                      )
                    : NewBoardDialog(onSave: (_) async => false);
              } else if (kind == 'legacy subject') {
                dialog = SubjectDialog(
                  title: editing ? 'Edit subject' : 'New subject',
                  initialName: editing ? 'Original' : '',
                  initialColor: 1,
                  onSave: (_, _) async => false,
                );
              } else {
                dialog = editing
                    ? EditTaskDialog(
                        task: Task(
                          id: 'task',
                          name: 'Original',
                          boardId: 'default-board',
                          deadline: DateTime(2030),
                          createdAt: DateTime(2026),
                          typeIndex: 0,
                          priorityIndex: 0,
                          subject: '',
                        ),
                        onSave: (_) async => false,
                      )
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
                      );
              }
              showDialog<void>(context: context, builder: (_) => dialog);
              await tester.pumpAndSettle();
              if (kind == 'default list') {
                for (final label in [
                  'Customization',
                  'Boards',
                  'Default lists of task types',
                ]) {
                  await tester.tap(find.text(label));
                  await tester.pumpAndSettle();
                }
                await tester.tap(
                  editing ? find.text('Academic tasks') : find.text('New list'),
                );
              }
            }
            await tester.pumpAndSettle();
            final field = find.byType(TextFormField).first;
            final editable = tester.widget<EditableText>(
              find.descendant(of: field, matching: find.byType(EditableText)),
            );
            expect(editable.focusNode.hasFocus, !editing);
            expect(find.text('Please enter a name.'), findsNothing);
            final before = tester.getRect(field);
            if (!editing) {
              FocusManager.instance.primaryFocus?.unfocus();
              await tester.pumpAndSettle();
              expect(find.text('Please enter a name.'), findsOneWidget);
              expect(tester.getRect(field), before);
            }
            await tester.enterText(field, 'Something');
            await tester.pumpAndSettle();
            expect(find.text('Please enter a name.'), findsNothing);
            await tester.enterText(field, '');
            await tester.pumpAndSettle();
            expect(find.text('Please enter a name.'), findsOneWidget);
            expect(tester.getRect(field), before);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            f.dispose();
          },
        );
      }
    }

    testWidgets(
      '$platform category duplicate creation and renaming stay in their draft',
      (tester) async {
        final f = await _mount(tester, platform);
        final context = tester.element(find.text('Open'));
        for (final editing in [false, true]) {
          editCategory(
            context,
            label: 'subject',
            useIcon: false,
            initial: editing
                ? const CategoryDraft(id: 'two', name: 'Physics')
                : null,
            siblings: const [
              CategoryDraft(id: 'one', name: 'Math'),
              CategoryDraft(id: 'two', name: 'Physics'),
            ],
          );
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextFormField), ' MATH ');
          await tester.pumpAndSettle();
          expect(
            find.text('A subject with this name already exists.'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, 'Save'),
                )
                .onPressed,
            isNull,
          );
          await tester.enterText(find.byType(TextFormField), 'Chemistry');
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<ElevatedButton>(
                  find.widgetWithText(ElevatedButton, 'Save'),
                )
                .onPressed,
            isNotNull,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );

    testWidgets(
      '$platform board footer remains fixed while scrolling and above keyboard',
      (tester) async {
        final f = await _mount(tester, platform);
        tester.view.physicalSize = platform == TargetPlatform.android
            ? const Size(360, 800)
            : const Size(700, 450);
        await tester.pumpAndSettle();
        showDialog<void>(
          context: tester.element(find.text('Open')),
          builder: (_) =>
              BoardEditorDialog(board: f.h.workspace.snapshot.boards.single),
        );
        await tester.pumpAndSettle();
        final save = find.widgetWithText(ElevatedButton, 'Save changes');
        final before = tester.getRect(save);
        expect(save.hitTestable(), findsOneWidget);
        await tester.drag(
          find.byType(SingleChildScrollView).last,
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        expect(tester.getRect(save), before);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        tester.view.viewInsets = const FakeViewPadding(bottom: 230);
        await tester.pumpAndSettle();
        expect(
          tester.getRect(save).bottom,
          lessThan(tester.view.physicalSize.height - 230),
        );
        expect(save.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }
}

Future<_Fixture> _mount(WidgetTester tester, TargetPlatform platform) async {
  tester.view.physicalSize = platform == TargetPlatform.android
      ? const Size(393, 1100)
      : const Size(1000, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final f = _Fixture();
  await tester.runAsync(() async {
    await f.h.initialize();
    await f.h.login('A');
    await f.h.workspace.mutate((s) => s.upgraded());
  });
  f.boards = BoardsProvider(f.h.workspace);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<WorkspaceController>.value(value: f.h.workspace),
        ChangeNotifierProvider<BoardsProvider>.value(value: f.boards),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme.copyWith(platform: platform),
        home: const Scaffold(body: Text('Open')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return f;
}

class _Fixture {
  final h = Harness();
  late BoardsProvider boards;
  void dispose() {
    boards.dispose();
    h.dispose();
  }
}
