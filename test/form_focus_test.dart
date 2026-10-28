import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/constants/app_constants.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/core/theme/app_motion.dart';
import 'package:microplanner/features/boards/data/models/subject.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/edit_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/subject_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/subject_dropdown.dart';
import 'support/fakes.dart';

void main() {
  testWidgets(
    'Windows dropdowns remain usable with Tab, Space and arrow keys',
    (tester) async {
      _viewport(tester);
      final f = _Fixture();
      await tester.runAsync(f.initialize);
      await _open(tester, f, TargetPlatform.windows, f.add);
      await tester.enterText(
        find.byType(TextFormField).first,
        'Keyboard navigation',
      );
      await tester.pump();
      bool inSubject() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<DropdownButton<String?>>() !=
          null;
      for (var i = 0; i < 6 && !inSubject(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(inSubject(), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SubjectDropdown>(find.byType(SubjectDropdown)).value,
        'subject',
      );
      expect(tester.testTextInput.isVisible, isFalse);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final editing in [false, true]) {
      for (final field in [0, 1]) {
        testWidgets(
          '$platform ${editing ? 'edit' : 'new'} field $field stays unfocused after date/time pickers',
          (tester) async {
            _viewport(tester);
            final f = _Fixture();
            await tester.runAsync(f.initialize);
            await _open(tester, f, platform, editing ? f.edit : f.add);
            final source = find.byType(TextFormField).at(field);
            final focus = tester
                .widget<EditableText>(
                  find.descendant(
                    of: source,
                    matching: find.byType(EditableText),
                  ),
                )
                .focusNode;
            for (final selector in ['Deadline', 'Time']) {
              for (final outcome in ['Cancel', 'OK']) {
                await tester.enterText(source, 'Unsaved text');
                await tester.pump();
                expect(focus.hasFocus, isTrue);
                expect(tester.testTextInput.isVisible, isTrue);
                await tester.tap(find.text(selector));
                await tester.pumpAndSettle();
                await tester.tap(find.text(outcome).last);
                await tester.pumpAndSettle();
                expect(
                  focus.hasFocus,
                  isFalse,
                  reason: '$selector/$outcome must not restore the old input.',
                );
                expect(tester.testTextInput.isVisible, isFalse);
                expect(find.text('Unsaved text'), findsOneWidget);
              }
            }
            if (platform == TargetPlatform.windows) {
              for (var i = 0; i < 5 && !tester.testTextInput.isVisible; i++) {
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await tester.pump();
              }
              expect(
                tester.testTextInput.isVisible,
                isTrue,
                reason: 'Tab must still reach editable fields.',
              );
            }
            await tester.pumpWidget(const SizedBox());
            f.dispose();
          },
        );
      }

      testWidgets(
        '$platform ${editing ? 'edit' : 'new'} non-text task controls release the keyboard',
        (tester) async {
          _viewport(tester);
          final f = _Fixture();
          await tester.runAsync(f.initialize);
          await _open(tester, f, platform, editing ? f.edit : f.add);
          final source = find.byType(TextFormField).first;
          for (final control in ['subject', 'type', 'priority']) {
            await tester.enterText(source, 'Retained title');
            await tester.pump();
            if (control == 'subject') {
              await tester.tap(find.byType(SubjectDropdown));
              await tester.pumpAndSettle();
              await tester.tap(find.text('Math').last);
            } else if (control == 'type') {
              await tester.tap(find.byType(DropdownButton<TaskType>));
              await tester.pumpAndSettle();
              await tester.tap(find.text(TaskType.presentation.label).last);
            } else {
              await tester.tap(find.text('High'));
            }
            await tester.pumpAndSettle();
            expect(tester.testTextInput.isVisible, isFalse, reason: control);
            expect(find.text('Retained title'), findsOneWidget);
          }
          // Explicitly tapping an input must still open it again.
          await tester.tap(source);
          await tester.pump();
          expect(tester.testTextInput.isVisible, isTrue);
          await tester.pumpWidget(const SizedBox());
          f.dispose();
        },
      );
    }

    testWidgets(
      '$platform choosing a subject color does not retain name focus',
      (tester) async {
        _viewport(tester);
        final f = _Fixture();
        await tester.runAsync(f.initialize);
        await _open(
          tester,
          f,
          platform,
          SubjectDialog(
            title: 'Edit Subject',
            initialName: 'Math',
            initialColor: 0xffe57373,
            onSave: (_, _) async => false,
          ),
        );
        await tester.enterText(find.byType(TextFormField), 'Retained subject');
        await tester.pump();
        await tester.tap(
          find.byWidgetPredicate(
            (w) =>
                w is AnimatedContainer &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color ==
                    const Color(0xfff06292),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.testTextInput.isVisible, isFalse);
        expect(find.text('Retained subject'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      },
    );
  }
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _open(
  WidgetTester tester,
  _Fixture f,
  TargetPlatform platform,
  Widget dialog,
) async {
  await tester.pumpWidget(
    f.app(
      platform,
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
    id: 'task',
    name: 'Sample',
    description: 'Description',
    deadline: DateTime(2030),
    createdAt: DateTime(2026),
    typeIndex: 0,
    priorityIndex: 0,
    subject: '',
    boardId: 'default-board',
    subjectId: 'subject',
  );
  Future<void> initialize() async {
    await h.initialize();
    await h.login('A');
    boards;
    await h.workspace.mutate(
      (s) => s.copyWith(
        subjects: [
          const Subject(id: 'subject', name: 'Math', boardId: 'default-board'),
        ],
      ),
    );
  }

  Widget get add => AddTaskDialog(
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
  Widget get edit => EditTaskDialog(task: task, onSave: (_) async => false);
  Widget app(TargetPlatform platform, Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<WorkspaceController>.value(value: h.workspace),
      ChangeNotifierProvider<BoardsProvider>.value(value: boards),
    ],
    child: MaterialApp(
      theme: ThemeData(platform: platform),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'GB')],
      home: Scaffold(body: child),
    ),
  );
  void dispose() {
    boards.dispose();
    h.dispose();
  }
}
