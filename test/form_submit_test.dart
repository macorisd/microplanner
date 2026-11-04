import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:microplanner/core/data/workspace_controller.dart';
import 'package:microplanner/features/tasks/presentation/widgets/board_editor_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/account_pages.dart';
import 'package:microplanner/features/tasks/presentation/widgets/category_editor.dart';
import 'package:microplanner/features/tasks/presentation/widgets/new_board_dialog.dart';
import 'package:microplanner/features/tasks/presentation/widgets/subject_dialog.dart';
import 'support/fakes.dart';

Future<Harness> open(
  WidgetTester tester,
  TargetPlatform platform,
  Widget Function(Harness) dialog,
) async {
  final h = Harness();
  await tester.runAsync(() async {
    await h.initialize();
    await h.login('A');
  });
  addTearDown(h.dispose);
  tester.view.physicalSize = const Size(900, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider<WorkspaceController>.value(
      value: h.workspace,
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Open'),
              onPressed: () =>
                  showDialog<void>(context: context, builder: (_) => dialog(h)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return h;
}

void main() {
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets(
      '$platform default-list Enter saves after leaving its text field',
      (tester) async {
        final h = await open(
          tester,
          platform,
          (_) => SettingsPage(onBack: () {}),
        );
        for (final entry in [
          'Customization',
          'Boards',
          'Default lists of task types',
          'New list',
        ]) {
          await tester.tap(find.text(entry).last);
          await tester.pumpAndSettle();
        }
        await tester.enterText(
          find.byType(TextFormField).last,
          'Keyboard list',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.runAsync(settleAsync);
        await tester.pumpAndSettle();
        expect(find.text('New default list'), findsNothing);
        expect(
          h.workspace.snapshot.typeLists.any(
            (list) => list.name == 'Keyboard list',
          ),
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      '$platform board Enter saves color-only edits and ignores unchanged saves',
      (tester) async {
        final h = await open(
          tester,
          platform,
          (h) => BoardEditorDialog(board: h.workspace.snapshot.boards.first),
        );
        final before = h.workspace.snapshot.boards.first;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(BoardEditorDialog), findsOneWidget);
        await tester.tap(find.byTooltip('Color 1'));
        await tester.pump();
        expect(
          FocusManager.instance.primaryFocus?.context?.widget,
          isNot(isA<EditableText>()),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
        await tester.runAsync(settleAsync);
        await tester.pumpAndSettle();
        expect(find.byType(BoardEditorDialog), findsNothing);
        expect(h.workspace.snapshot.boards.first.color, isNot(before.color));
        expect(h.workspace.snapshot.boards.first.name, before.name);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$platform nested category Enter saves only its own route before board Enter',
      (tester) async {
        final h = await open(
          tester,
          platform,
          (h) => BoardEditorDialog(board: h.workspace.snapshot.boards.first),
        );
        await tester.ensureVisible(find.byTooltip('Add subject'));
        await tester.tap(find.byTooltip('Add subject'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField).last,
          'Keyboard subject',
        );
        await tester.tap(find.byTooltip('Color 2').last);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.text('New subject'), findsNothing);
        expect(find.byType(BoardEditorDialog), findsOneWidget);
        expect(h.workspace.snapshot.subjects, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.runAsync(settleAsync);
        await tester.pumpAndSettle();
        expect(find.byType(BoardEditorDialog), findsNothing);
        expect(h.workspace.snapshot.subjects.single.name, 'Keyboard subject');
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('$platform type Enter works after its icon picker returns', (
      tester,
    ) async {
      CategoryDraft? result;
      final h = Harness();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () async => result = await editCategory(
                  context,
                  label: 'task type',
                  useIcon: true,
                  initial: const CategoryDraft(id: 'type', name: 'Homework'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Choose icon'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('code'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(result?.icon, 'code');
      expect(result?.name, 'Homework');
      await tester.pumpWidget(const SizedBox());
      h.dispose();
    });

    testWidgets(
      '$platform new board Enter matches enabled default-name Create',
      (tester) async {
        var calls = 0;
        await open(
          tester,
          platform,
          (_) => NewBoardDialog(
            onSave: (name) async {
              expect(name, isNull);
              calls++;
              return true;
            },
          ),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.byType(NewBoardDialog), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      '$platform subject Enter after color change submits once while pending',
      (tester) async {
        var calls = 0;
        final pending = Completer<bool>();
        await open(
          tester,
          platform,
          (_) => SubjectDialog(
            title: 'Edit subject',
            initialName: 'Math',
            initialColor: 0xff7986cb,
            onSave: (name, color) {
              calls++;
              return pending.future;
            },
          ),
        );
        await tester.tap(find.byTooltip('Color 1'));
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(calls, 1);
        pending.complete(true);
        await tester.pumpAndSettle();
        expect(find.byType(SubjectDialog), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
