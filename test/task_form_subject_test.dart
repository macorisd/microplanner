import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/features/boards/data/models/subject.dart';
import 'package:microplanner/features/boards/providers/boards_provider.dart';
import 'package:microplanner/features/tasks/data/models/task.dart';
import 'package:microplanner/features/tasks/presentation/widgets/add_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/edit_task_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/new_board_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/subject_dropdown.dart';
import 'package:microplanner/features/tasks/providers/tasks_provider.dart';
import 'support/fakes.dart';

const _subject = Subject(
  id: 'subject',
  name: 'A subject with a deliberately long name for a narrow task form',
  boardId: 'default-board',
  color: 0xffed7691,
);

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final editing in [false, true]) {
      testWidgets(
        'subject color in ${editing ? 'edit' : 'new'} form on $platform',
        (tester) async {
          tester.view.physicalSize = const Size(420, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final f = _Fixture();
          await tester.runAsync(f.initialize);
          await tester.pumpWidget(f.app(platform, editing ? f.edit : f.add));
          await tester.pumpAndSettle();
          Finder swatches() => find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle &&
                (w.decoration as BoxDecoration).color == Color(_subject.color),
          );
          if (editing) expect(swatches(), findsOneWidget);
          await tester.tap(find.byType(DropdownButton<String?>));
          await tester.pumpAndSettle();
          expect(swatches(), editing ? findsNWidgets(2) : findsOneWidget);
          await tester.tap(find.text(_subject.name).last);
          await tester.pumpAndSettle();
          expect(swatches(), findsOneWidget);
          expect(
            tester.widget<SubjectDropdown>(find.byType(SubjectDropdown)).value,
            _subject.id,
          );
          await tester.tap(find.byType(DropdownButton<String?>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('No Subject').last);
          await tester.pumpAndSettle();
          expect(swatches(), findsNothing);
          expect(
            tester.widget<SubjectDropdown>(find.byType(SubjectDropdown)).value,
            isNull,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          f.dispose();
        },
      );
    }
  }

  testWidgets('submitting while refreshing waits once and preserves the form', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    await tester.pumpWidget(f.app(TargetPlatform.windows, f.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'First click');
    await tester.pump();
    final read = Completer<http.Response>();
    f.h.server.nextRead = read;
    final refreshing = f.h.workspace.refresh();
    await tester.runAsync(settleAsync);
    await tester.tap(find.text('Create Task'));
    await tester.pump();
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNull,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.runAsync(settleAsync);
    expect(f.h.server.writes, 1); // Fixture creation only.
    expect(find.text('First click'), findsOneWidget);
    read.complete(jsonResponse(f.h.server.states['A']!.toJson()));
    await tester.runAsync(() async {
      await refreshing;
      await settleAsync();
    });
    await tester.pump();
    await tester.runAsync(settleAsync);
    await tester.pumpAndSettle();
    expect(f.h.server.writes, 2);
    expect(f.h.workspace.snapshot.tasks.last.name, 'First click');
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('New Board ignores duplicate submissions while awaiting a save', (
    tester,
  ) async {
    final f = _Fixture();
    await tester.runAsync(f.initialize);
    final pending = Completer<bool>();
    var calls = 0;
    await tester.pumpWidget(
      f.app(
        TargetPlatform.windows,
        NewBoardDialog(
          onSave: (_) {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Pending board');
    await tester.tap(find.text('Create'));
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(calls, 1);
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Pending board'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });
}

class _Fixture {
  final h = Harness();
  late final boards = BoardsProvider(h.workspace);
  late final tasks = TasksProvider(h.workspace, boards);
  late final Task task;
  Future<void> initialize() async {
    await h.initialize();
    await h.login('A');
    boards;
    tasks;
    task = Task(
      id: 'task',
      name: 'Existing',
      deadline: DateTime(2026, 11, 1),
      createdAt: DateTime(2026, 10, 22),
      typeIndex: 0,
      priorityIndex: 0,
      subject: '',
      boardId: 'default-board',
      subjectId: _subject.id,
    );
    await h.workspace.mutate(
      (s) => s.copyWith(subjects: [_subject], tasks: [task]),
    );
  }

  Widget get add => AddTaskDialog(onSave: tasks.addTask);
  Widget get edit => EditTaskDialog(task: task, onSave: tasks.updateTask);
  Widget app(TargetPlatform platform, Widget form) => MultiProvider(
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
      home: Scaffold(body: form),
    ),
  );
  void dispose() {
    tasks.dispose();
    boards.dispose();
    h.dispose();
  }
}
