import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/theme/app_motion.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/widgets/action_confirmation_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/edit_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/new_board_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/subject_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_card.dart';
import 'support/fakes.dart';
import 'package:microplanner/features/tasks/presentation/widgets/task_date_picker.dart';

void main() {
  testWidgets('new board limits pasted titles to 50 characters', (
    tester,
  ) async {
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    String? saved;
    await _open(
      tester,
      f,
      NewBoardDialog(
        onSave: (name) async {
          saved = name;
          return true;
        },
      ),
    );
    await tester.enterText(
      find.byType(TextFormField),
      List.filled(51, 'x').join(),
    );
    await tester.pump();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField))
          .controller!
          .text
          .length,
      50,
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(saved?.length, 50);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('Windows edit opens without selecting a text field', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    await _open(
      tester,
      f,
      EditTaskDialog(task: f.task, onSave: (_) async => true),
    );
    for (final editable in tester.widgetList<EditableText>(
      find.byType(EditableText),
    )) {
      expect(editable.focusNode.hasFocus, isFalse);
    }
    expect(tester.testTextInput.isVisible, isFalse);
    await tester.tap(find.byType(TextFormField).first);
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  for (final editing in [false, true]) {
    testWidgets(
      'Windows Ctrl+Enter in ${editing ? 'edit' : 'create'} description submits once only when enabled',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        final pending = Completer<bool>();
        var calls = 0;
        Future<bool> save() {
          calls++;
          return pending.future;
        }

        final Widget dialog = editing
            ? EditTaskDialog(task: f.task, onSave: (_) => save())
            : AddTaskDialog(
                onSave:
                    ({
                      required name,
                      required deadline,
                      required type,
                      required priority,
                      subjectId,
                      description,
                    }) => save(),
              );
        await _open(tester, f, dialog);
        final description = find.byType(TextFormField).last;
        await tester.tap(description);
        await tester.pump();
        Future<void> shortcut() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.pump();
        }

        await shortcut();
        expect(
          calls,
          0,
          reason: 'The unchanged or incomplete form is disabled.',
        );
        if (!editing) {
          await tester.enterText(find.byType(TextFormField).first, 'New task');
        }
        await tester.enterText(description, 'First line');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(
          calls,
          0,
          reason: 'Plain Enter must never submit a description.',
        );
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'First line\n',
            selection: TextSelection.collapsed(offset: 11),
          ),
        );
        await tester.pump();
        expect(
          tester.widget<TextFormField>(description).controller!.text,
          'First line\n',
        );
        await shortcut();
        expect(calls, 1);
        await shortcut();
        expect(
          calls,
          1,
          reason: 'An in-flight submission cannot be duplicated.',
        );
        pending.complete(false);
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }

  for (final form in [
    'new task',
    'edit task',
    'new board',
    'new subject',
    'edit subject',
    'delete',
  ]) {
    testWidgets(
      '$form submits once, blocks dismissal, and recovers after failure',
      (tester) async {
        tester.view.physicalSize = const Size(900, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        final pending = Completer<bool>();
        var calls = 0;
        Future<bool> save() {
          calls++;
          return calls == 1 ? pending.future : Future.value(true);
        }

        final (widget, label) = switch (form) {
          'new task' => (
            AddTaskDialog(
              onSave:
                  ({
                    required name,
                    required deadline,
                    required type,
                    required priority,
                    subjectId,
                    description,
                  }) => save(),
            ),
            'Create Task',
          ),
          'edit task' => (
            EditTaskDialog(task: f.task, onSave: (_) => save()),
            'Save Changes',
          ),
          'new board' => (NewBoardDialog(onSave: (_) => save()), 'Create'),
          'new subject' => (
            SubjectDialog(
              title: 'New Subject',
              initialName: '',
              initialColor: 0xffe57373,
              onSave: (_, _) => save(),
            ),
            'Save',
          ),
          'edit subject' => (
            SubjectDialog(
              title: 'Edit Subject',
              initialName: 'Original',
              initialColor: 0xffe57373,
              onSave: (_, _) => save(),
            ),
            'Save',
          ),
          _ => (
            ActionConfirmationDialog(
              title: 'Delete Task',
              message: 'Delete the sample?',
              actionLabel: 'Delete',
              pendingLabel: 'Deleting…',
              destructive: true,
              onConfirm: save,
            ),
            'Delete',
          ),
        };
        await _open(tester, f, widget);
        if (form != 'delete') {
          await tester.enterText(
            find.byType(TextFormField).first,
            'Updated name',
          );
          await tester.pump();
        }
        await tester.tap(find.text(label));
        await tester.tap(find.text(label));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(calls, 1);
        final saveButton = find.descendant(
          of: find.byWidget(widget),
          matching: find.byWidgetPredicate(
            (w) => w is FilledButton || w is ElevatedButton,
          ),
        );
        expect(saveButton, findsOneWidget);
        for (final button in tester.widgetList<ButtonStyleButton>(saveButton)) {
          expect(button.onPressed, isNull);
        }
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .every((w) => w.enabled == false),
          isTrue,
        );
        await tester.binding.handlePopRoute();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.tapAt(const Offset(2, 2));
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byWidget(widget), findsOneWidget);
        pending.complete(false);
        await tester.pumpAndSettle();
        expect(find.textContaining('could not be completed'), findsOneWidget);
        if (form != 'delete') expect(find.text('Updated name'), findsOneWidget);
        await tester.tap(find.text(label));
        await tester.pump(const Duration(milliseconds: 20));
        if (find.text(label).evaluate().isNotEmpty) {
          await tester.tap(find.text(label), warnIfMissed: false);
        }
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(find.byWidget(widget), findsNothing);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }

  testWidgets(
    'unchanged task values disable saving, including an edit reverted to its original value',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      var calls = 0;
      await _open(
        tester,
        f,
        EditTaskDialog(
          task: f.task,
          onSave: (_) async {
            calls++;
            return true;
          },
        ),
      );
      ElevatedButton button() =>
          tester.widget(find.widgetWithText(ElevatedButton, 'Save Changes'));
      expect(button().onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(calls, 0);
      await tester.enterText(find.byType(TextFormField).first, 'Modified');
      await tester.pump();
      expect(button().onPressed, isNotNull);
      await tester.enterText(find.byType(TextFormField).first, f.task.name);
      await tester.pump();
      expect(button().onPressed, isNull);
      await tester.enterText(
        find.byType(TextFormField).last,
        'New description',
      );
      await tester.pump();
      expect(button().onPressed, isNotNull);
      await tester.enterText(
        find.byType(TextFormField).last,
        f.task.description!,
      );
      await tester.pump();
      expect(button().onPressed, isNull);
      expect(calls, 0);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets('a subject requires an actual name or color change', (
    tester,
  ) async {
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    await _open(
      tester,
      f,
      SubjectDialog(
        title: 'Edit Subject',
        initialName: 'Original',
        initialColor: 0xffe57373,
        onSave: (_, _) async => true,
      ),
    );
    FilledButton button() =>
        tester.widget(find.widgetWithText(FilledButton, 'Save'));
    expect(button().onPressed, isNull);
    await tester.enterText(find.byType(TextFormField), '  Original  ');
    await tester.pump();
    expect(button().onPressed, isNull);
    await tester.tap(
      find.byIcon(Icons.check),
    ); // Re-selecting the current color is a no-op.
    await tester.pump();
    expect(button().onPressed, isNull);
    await tester.enterText(find.byType(TextFormField), 'Different');
    await tester.pump();
    expect(button().onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('rapid dialog-opening actions create a single route', (
    tester,
  ) async {
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    await tester.pumpWidget(
      f.app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () {
              for (var i = 0; i < 5; i++) {
                showMotionDialog(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('Single form')),
                );
              }
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Single form', skipOffstage: false), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Single form', skipOffstage: false), findsNothing);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('completion cannot be toggled again until its request finishes', (
    tester,
  ) async {
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      f.app(
        Scaffold(
          body: SizedBox(
            width: 420,
            child: TaskCard(
              task: f.task,
              onToggleComplete: () {
                calls++;
                return pending.future;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final checkbox = find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'Mark task complete',
    );
    await tester.tap(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  for (final year in [2000, 2100]) {
    testWidgets('editing a deadline in $year can open the calendar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await _open(
        tester,
        f,
        EditTaskDialog(
          task: f.task.copyWith(deadline: DateTime(year, 1, 2)),
          onSave: (_) async => true,
        ),
      );
      await tester.tap(find.text('Deadline'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskDatePickerDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    });
  }

  testWidgets('manual date entry is bounded and rejects impossible dates', (
    tester,
  ) async {
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    await _open(
      tester,
      f,
      TaskDatePickerDialog(
        initialDate: DateTime(2030, 1, 1),
        firstDate: DateTime(2020),
        lastDate: DateTime(2040),
      ),
    );
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '31/02/2026extra');
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.length, 10);
    expect(find.text('Enter a valid date.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'OK'))
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextFormField), '01/01/2030');
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'OK'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskDatePickerDialog), findsNothing);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('rapid deadline and time taps cannot stack picker dialogs', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    await _open(
      tester,
      f,
      EditTaskDialog(task: f.task, onSave: (_) async => true),
    );
    for (final label in ['Deadline', 'Time']) {
      final ink = tester.widget<InkWell>(
        find
            .ancestor(of: find.text(label), matching: find.byType(InkWell))
            .first,
      );
      ink.onTap!();
      ink.onTap!();
      await tester.pumpAndSettle();
      expect(
        find.byType(
          label == 'Deadline' ? TaskDatePickerDialog : TimePickerDialog,
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(EditTaskDialog), findsOneWidget);
    }
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });
}

Future<void> _open(WidgetTester tester, _Fixture f, Widget dialog) async {
  await tester.pumpWidget(
    f.app(
      Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              showMotionDialog(context: context, builder: (_) => dialog),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

class _Fixture {
  final h = Harness();
  late final boards = BoardsProvider(h.workspace);
  final task = Task(
    id: 'sample',
    name: 'Original',
    description: 'Original description',
    deadline: DateTime(2030, 1, 2, 12, 30, 45),
    createdAt: DateTime(2026, 10, 22),
    typeIndex: 0,
    priorityIndex: 0,
    subject: '',
    boardId: 'default-board',
  );
  Future<void> initialize() async {
    await h.initialize();
    await h.login('A');
    boards;
  }

  Widget app(Widget body) => MultiProvider(
    providers: [
      ChangeNotifierProvider<WorkspaceController>.value(value: h.workspace),
      ChangeNotifierProvider<BoardsProvider>.value(value: boards),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: TargetPlatform.windows),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB')],
      home: Scaffold(body: body),
    ),
  );
  void dispose() {
    boards.dispose();
    h.dispose();
  }
}
