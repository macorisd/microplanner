import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/theme/app_theme.dart';
import 'package:microplanner/core/widgets/limited_text_field.dart';
import 'package:microplanner/core/widgets/form_actions.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/edit_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/subject_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/new_board_dialog.dart';
import 'support/fakes.dart';

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    for (final kind in ['create task', 'edit task', 'subject', 'new board']) {
      testWidgets(
        '$platform $kind keeps dialog and controls fixed for validation and save errors',
        (tester) async {
          final h = Harness();
          await tester.runAsync(() async {
            await h.initialize();
            await h.login('A');
          });
          final boards = BoardsProvider(h.workspace);
          final size = platform == TargetPlatform.windows
              ? const Size(1000, 1100)
              : const Size(393, 1100);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final task = Task(
            id: 'task',
            name: 'Sample',
            deadline: DateTime(2030),
            createdAt: DateTime(2026),
            typeIndex: 0,
            priorityIndex: 0,
            subject: '',
            boardId: 'default-board',
          );
          final Widget editor = switch (kind) {
            'new board' => NewBoardDialog(onSave: (_) async => false),
            'subject' => SubjectDialog(
              title: 'Edit subject',
              initialName: 'Math',
              initialColor: 0xff7986cb,
              onSave: (_, _) async => false,
            ),
            'edit task' => EditTaskDialog(
              task: task,
              onSave: (_) async => false,
            ),
            _ => AddTaskDialog(
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
          };
          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider<WorkspaceController>.value(
                  value: h.workspace,
                ),
                ChangeNotifierProvider<BoardsProvider>.value(value: boards),
              ],
              child: MaterialApp(
                theme: AppTheme.lightTheme.copyWith(platform: platform),
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      child: const Text('Open'),
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => editor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          final dialog = tester.getRect(find.byType(Dialog));
          final field = find.byType(TextFormField).first;
          final fieldRect = tester.getRect(field);
          final cancelRect = tester.getRect(find.text('Cancel'));
          final footer = tester.getRect(find.byType(FormFooter));
          final proceed = find.byWidgetPredicate(
            (widget) => widget is ElevatedButton || widget is FilledButton,
          );
          final surface = tester.getRect(
            find.descendant(of: proceed, matching: find.byType(Material)),
          );
          final inset = platform == TargetPlatform.windows
              ? 12
              : (kind == 'edit task' ? 8 : 16);
          expect(footer.right - surface.right, inset);
          expect(footer.bottom - surface.bottom, inset);
          if (kind == 'new board') {
            final container = InputDecorator.containerOf(
              tester.element(find.byType(EditableText)),
            )!;
            final bottom =
                container.localToGlobal(Offset.zero).dy + container.size.height;
            final buttonTop = tester
                .getTopLeft(find.widgetWithText(TextButton, 'Cancel'))
                .dy;
            // Reserved name message row + body spacing + balanced footer inset.
            expect(
              buttonTop - bottom,
              platform == TargetPlatform.windows ? 40 : 44,
            );
          }
          await tester.enterText(field, 'A valid name');
          await tester.pumpAndSettle();
          await tester.enterText(field, '');
          await tester.pumpAndSettle();
          expect(find.text('Please enter a name.'), findsOneWidget);
          expect(tester.getRect(find.byType(Dialog)), dialog);
          expect(tester.getRect(field), fieldRect);
          expect(tester.getRect(find.text('Cancel')), cancelRect);
          await tester.enterText(field, 'Changed name');
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(Dialog)), dialog);
          final action = kind == 'subject'
              ? 'Save changes'
              : kind == 'new board'
              ? 'Create board'
              : kind == 'edit task'
              ? 'Save changes'
              : 'Create task';
          await tester.ensureVisible(find.text(action));
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          expect(
            find.text('The action could not be completed. Please try again.'),
            findsOneWidget,
          );
          expect(tester.getRect(find.byType(Dialog)), dialog);
          expect(tester.getRect(find.text('Cancel')), cancelRect);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          boards.dispose();
          h.dispose();
        },
      );
    }

    testWidgets(
      '$platform shared fields keep geometry for external and long errors at large text sizes',
      (tester) async {
        final controller = TextEditingController(text: 'Valid');
        final error = ValueNotifier<String?>(null);
        final key = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: platform),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 220,
                    child: ValueListenableBuilder<String?>(
                      valueListenable: error,
                      builder: (_, value, _) => Column(
                        key: key,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LimitedTextField(
                            controller: controller,
                            limit: 50,
                            validator: (_) => null,
                            errorText: value,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                            ),
                          ),
                          const Text('Footer'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final before = tester.getRect(find.byKey(key));
        final footer = tester.getRect(find.text('Footer'));
        error.value =
            'This is a longer error explaining how to resolve a save conflict without losing your draft.';
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(key)), before);
        expect(tester.getRect(find.text('Footer')), footer);
        expect(find.text(error.value!), findsOneWidget);
        error.value = null;
        await tester.pumpAndSettle();
        expect(tester.getRect(find.byKey(key)), before);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        error.dispose();
      },
    );
  }
}
